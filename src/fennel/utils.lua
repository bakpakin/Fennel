
-- Like pairs, but gives consistent ordering every time. On 5.1, 5.2, and LuaJIT
-- pairs is already stable, but on 5.3 every run gives different ordering.
local function stablepairs(t)
    local keys, succ = {}, {}
    for k in pairs(t) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for i,k in ipairs(keys) do succ[k] = keys[i+1] end
    local function stablenext(tbl, idx)
        if idx == nil then return keys[1], tbl[keys[1]] end
        return succ[idx], tbl[succ[idx]]
    end
    return stablenext, t, nil
end

-- Map function f over sequential table t, removing values where f returns nil.
-- Optionally takes a target table to insert the mapped values into.
local function map(t, f, out)
    out = out or {}
    if type(f) ~= "function" then local s = f f = function(x) return x[s] end end
    for _,x in ipairs(t) do
        local v = f(x)
        if v then table.insert(out, v) end
    end
    return out
end

-- Map function f over key/value table t, similar to above, but it can return a
-- sequential table if f returns a single value or a k/v table if f returns two.
-- Optionally takes a target table to insert the mapped values into.
local function kvmap(t, f, out)
    out = out or {}
    if type(f) ~= "function" then local s = f f = function(x) return x[s] end end
    for k,x in stablepairs(t) do
        local korv, v = f(k, x)
        if korv and not v then table.insert(out, korv) end
        if korv and v then out[korv] = v end
    end
    return out
end

-- Returns a shallow copy of its table argument. Returns an empty table on nil.
local function copy(from)
   local to = {}
   for k, v in pairs(from or {}) do to[k] = v end
   return to
end

-- Like pairs, but if the table has an __index metamethod, it will recurisvely
-- traverse upwards, skipping duplicates, to iterate all inherited properties
local function allpairs(t)
    assert(type(t) == 'table', 'allpairs expects a table')
    local seen = {}
    local function allpairsNext(_, state)
        local nextState, value = next(t, state)
        if seen[nextState] then
            return allpairsNext(nil, nextState)
        elseif nextState then
            seen[nextState] = true
            return nextState, value
        end
        local meta = getmetatable(t)
        if meta and meta.__index then
            t = meta.__index
            return allpairsNext(t)
        end
    end
    return allpairsNext
end

local function deref(self) return self[1] end

local nilSym -- haven't defined sym yet; create this later

local function listToString(self, tostring2)
    local safe, max = {}, 0
    for k in pairs(self) do if type(k) == "number" and k>max then max=k end end
    for i=1,max do -- table.maxn was removed from Lua 5.3 for some reason???
        safe[i] = self[i] == nil and nilSym or self[i]
    end
    return '(' .. table.concat(map(safe, tostring2 or tostring), ' ', 1, max) .. ')'
end

local SYMBOL_MT = { 'SYMBOL', __tostring = deref, __fennelview = deref }
local EXPR_MT = { 'EXPR', __tostring = deref }
local VARARG = setmetatable({ '...' },
    { 'VARARG', __tostring = deref, __fennelview = deref })
local LIST_MT = { 'LIST', __tostring = listToString, __fennelview = listToString }
local SEQUENCE_MARKER = { 'SEQUENCE' }

-- Safely load an environment variable
local getenv = os and os.getenv or function() return nil end

local pathTable = {"./?.fnl", "./?/init.fnl"}
table.insert(pathTable, getenv("FENNEL_PATH"))

local function debugOn(flag)
    local level = getenv("FENNEL_DEBUG") or ""
    return level == "all" or level:find(flag)
end

-- Create a new list. Lists are a compile-time construct in Fennel; they are
-- represented as tables with a special marker metatable. They only come from
-- the parser, and they represent code which comes from reading a paren form;
-- they are specifically not cons cells.
local function list(...)
    return setmetatable({...}, LIST_MT)
end

-- Create a new symbol. Symbols are a compile-time construct in Fennel and are
-- not exposed outside the compiler. Symbols have source data describing what
-- file, line, etc that they came from.
local function sym(str, scope, source)
    local s = {str, scope = scope}
    for k, v in pairs(source or {}) do
        if type(k) == 'string' then s[k] = v end
    end
    return setmetatable(s, SYMBOL_MT)
end

nilSym = sym("nil")

-- Create a new sequence. Sequences are tables that come from the parser when
-- it encounters a form with square brackets. They are treated as regular tables
-- except when certain macros need to look for binding forms, etc specifically.
local function sequence(...)
    -- can't use SEQUENCE_MT directly as the sequence metatable like we do with
    -- the other types without giving up the ability to set source metadata
    -- on a sequence, (which we need for error reporting) so embed a marker
    -- value in the metatable instead.
    return setmetatable({...}, {sequence=SEQUENCE_MARKER})
end

-- Create a new expr
-- etype should be one of
--   "literal": literals like numbers, strings, nil, true, false
--   "expression": Complex strings of Lua code, may have side effects, etc
--                 but is an expression
--   "statement": Same as expression, but is also a valid statement
--                (function calls).
--   "vargs": varargs symbol
--   "sym": symbol reference
local function expr(strcode, etype)
    return setmetatable({ strcode, type = etype }, EXPR_MT)
end

local function varg()
    return VARARG
end

local function isExpr(x)
    return type(x) == 'table' and getmetatable(x) == EXPR_MT and x
end

local function isVarg(x)
    return x == VARARG and x
end

-- Checks if an object is a List. Returns the object if is a List.
local function isList(x)
    return type(x) == 'table' and getmetatable(x) == LIST_MT and x
end

-- Checks if an object is a symbol. Returns the object if it is a symbol.
local function isSym(x)
    return type(x) == 'table' and getmetatable(x) == SYMBOL_MT and x
end

-- Checks if an object any kind of table, EXCEPT list or symbol
local function isTable(x)
    return type(x) == 'table' and
        x ~= VARARG and
        getmetatable(x) ~= LIST_MT and getmetatable(x) ~= SYMBOL_MT and x
end

-- Checks if an object is a sequence (created with a [] literal)
local function isSequence(x)
    local mt = type(x) == "table" and getmetatable(x)
    return mt and mt.sequence == SEQUENCE_MARKER and x
end

-- A multi symbol is a symbol that is actually composed of
-- two or more symbols using the dot syntax. The main differences
-- from normal symbols is that they cannot be declared local, and
-- they may have side effects on invocation (metatables)
local function isMultiSym(str)
    if isSym(str) then
        return isMultiSym(tostring(str))
    end
    if type(str) ~= 'string' then return end
    local parts = {}
    for part in str:gmatch('[^%.%:]+[%.%:]?') do
        local lastChar = part:sub(-1)
        if lastChar == ":" then
            parts.multiSymMethodCall = true
        end
        if lastChar == ":" or lastChar == "." then
            parts[#parts + 1] = part:sub(1, -2)
        else
            parts[#parts + 1] = part
        end
    end
    return #parts > 0 and
        (str:match('%.') or str:match(':')) and
        (not str:match('%.%.')) and
        str:byte() ~= string.byte '.' and
        str:byte(-1) ~= string.byte '.' and
        parts
end

local function isQuoted(symbol) return symbol.quoted end

-- Walks a tree (like the AST), invoking f(node, idx, parent) on each node.
-- When f returns a truthy value, recursively walks the children.
local walkTree = function(root, f, customIterator)
    local function walk(iterfn, parent, idx, node)
        if f(idx, node, parent) then
            for k, v in iterfn(node) do walk(iterfn, node, k, v) end
        end
    end

    walk(customIterator or pairs, nil, nil, root)
    return root
end

local luaKeywords = {
    'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for',
    'function', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return',
    'then', 'true', 'until', 'while'
}

for i, v in ipairs(luaKeywords) do luaKeywords[v] = i end

local function isValidLuaIdentifier(str)
    return (str:match('^[%a_][%w_]*$') and not luaKeywords[str])
end

-- Certain options should always get propagated onwards when a function that
-- has options calls down into compile.
local propagatedOptions = {"allowedGlobals", "indent", "correlate",
                           "useMetadata", "env"}
local function propagateOptions(options, subopts)
    for _,name in ipairs(propagatedOptions) do subopts[name] = options[name] end
    return subopts
end

local root = {
    -- Top level compilation bindings.
    chunk=nil, scope=nil, options=nil,

    -- The root.reset function needs to be called at every exit point of the
    -- compiler including when there's a parse error or compiler
    -- error. This would be better done using dynamic scope, but we don't
    -- have dynamic scope, so we fake it by ensuring we call this at every
    -- exit point, including errors.
    reset=function() end,

    setReset=function(root)
        local chunk, scope, options = root.chunk, root.scope, root.options
        local oldResetRoot = root.reset -- this needs to nest!
        root.reset = function()
            root.chunk, root.scope, root.options = chunk, scope, options
            root.reset = oldResetRoot
        end
    end,
}

return {
    -- basic general table functions:
    stablepairs=stablepairs, allpairs=allpairs, map=map, kvmap=kvmap,
    copy=copy, walkTree=walkTree,

    -- AST functions:
    list=list, sym=sym, sequence=sequence, expr=expr, varg=varg,
    isVarg=isVarg, isList=isList, isSym=isSym, isTable=isTable,
    isSequence=isSequence, isMultiSym=isMultiSym, isQuoted=isQuoted,
    isExpr=isExpr, deref=deref,

    -- other functions:
    isValidLuaIdentifier=isValidLuaIdentifier, luaKeywords=luaKeywords,
    propagateOptions=propagateOptions, debugOn=debugOn,
    root=root, path=table.concat(pathTable, ";")}
