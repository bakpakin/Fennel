--[[
Copyright (c) 2016-2018 Calvin Rose and contributors
Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]

-- Make global variables local.
local setmetatable = setmetatable
local getmetatable = getmetatable
local type = type
local assert = assert
local select = select
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local unpack = unpack or table.unpack
local tpack = table.pack or function(...)
    return {n = select('#', ...), ...}
end

local SYMBOL_MT = { 'SYMBOL',
    __tostring = function (self)
        return self[1]
    end
}
local LIST_MT = { 'LIST',
    __len = function (self)
        return self.n or rawlen(self)
    end,
    __tostring = function (self)
        local strs = {}
        local n = self.n or #self
        for i = 1, n do
            strs[i] = tostring(self[i])
        end
        return '(' .. table.concat(strs, ', ', 1, n) .. ')'
    end
}
local EXPR_MT = { 'EXPR',
    __tostring = function (self)
        return self[1]
    end
}
local VARARG = setmetatable({ '...' }, { 'VARARG' })

-- Load code with an environment in all recent Lua versions
local function loadCode(code, environment, filename)
    environment = environment or _ENV or _G
    if setfenv and loadstring then
        local f = assert(loadstring(code, filename))
        setfenv(f, environment)
        return f
    else
        return assert(load(code, filename, "t", environment))
    end
end

-- Create a new list
local function list(...)
    local t = {...}
    t.n = select('#', ...)
    return setmetatable(t, LIST_MT)
end

-- Create a new symbol
local function sym(str, scope)
    return setmetatable({ str, scope = scope }, SYMBOL_MT)
end

-- Create a new expr
-- etype should be one of
--   "literal", -- literals like numbers, strings, nil, true, false
--   "expression", -- Complex strigns of Lua code, may have side effects, etc, but is an expression
--   "statement", -- Same as expression, but is also a valid statement (function calls).
--   "vargs", -- varargs symbol
--   "sym", -- symbol reference
local function expr(strcode, etype)
    return setmetatable({ strcode, type = etype }, EXPR_MT)
end

local function varg()
    return VARARG
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

-- Parser

-- Convert a stream of chunks to a stream of bytes.
-- Also returns a second function to clear the buffer in the byte stream
local function granulate(getchunk)
    local c = ''
    local index = 1
    local done = false
    return function ()
        if done then return nil end
        if index <= #c then
            local b = c:byte(index)
            index = index + 1
            return b
        else
            c = getchunk()
            if not c or c == '' then
                done = true
                return nil
            end
            index = 2
            return c:byte(1)
        end
    end, function ()
        c = ''
    end
end

-- Convert a string into a stream of bytes
local function stringstream(str)
    local index = 1
    return function()
        local r = str:byte(index)
        index = index + 1
        return r
    end
end

-- Table of delimiter bytes - (, ), [, ], {, }
-- Opener keys have closer as the value, and closers keys
-- have true as their value.
local delims = {
    [40] = 41,        -- (
    [41] = true,      -- )
    [91] = 93,        -- [
    [93] = true,      -- ]
    [123] = 125,      -- {
    [125] = true      -- }
}

local function iswhitespace(b)
    return b == 32 or (b >= 9 and b <= 13) or b == 44
end

local function issymbolchar(b)
    return b > 32 and
        not delims[b] and
        b ~= 127 and
        b ~= 34 and
        b ~= 39 and
        b ~= 59 and
        b ~= 44
end

-- Parse one value given a function that
-- returns sequential bytes. Will throw an error as soon
-- as possible without getting more bytes on bad input. Returns
-- if a value was read, and then the value read. Will return nil
-- when input stream is finished.
local function parse(getbyte)
    -- Stack of unfinished values
    local stack = {}

    -- Provide one character buffer
    local lastb
    local function ungetb(ub)
        lastb = ub
    end
    local function getb()
        if lastb then
            local r = lastb
            lastb = nil
            return r
        end
        return getbyte()
    end

    -- Dispatch when we complete a value
    local done, retval
    local function dispatch(v)
        if #stack == 0 then
            retval = v
            done = true
        else
            local last = stack[#stack]
            last.n = last.n + 1
            last[last.n] = v
        end
    end

    -- The main parse loop
    repeat
        local b

        -- Skip whitespace
        repeat
            b = getb()
        until not b or not iswhitespace(b)
        if not b then 
            if #stack > 0 then error 'unexpected end of source' end
            return nil
        end

        if b == 59 then -- ; Comment
            repeat
                b = getb()
            until not b or b == 10 -- newline
        elseif type(delims[b]) == 'number' then -- Opening delimiter
            table.insert(stack, setmetatable({
                closer = delims[b],
                n = 0
            }, LIST_MT))
        elseif delims[b] then -- Closing delimiter
            if #stack == 0 then error 'unexpected closing delimiter' end
            local last = stack[#stack]
            local val
            if last.closer ~= b then
                error('unexpected delimiter ' .. string.char(b) .. ', expected ' .. string.char(last.closer))
            end
            if b == 41 then -- )
                val = last
            elseif b == 93 then -- ]
                val = {}
                for i = 1, last.n do
                    val[i] = last[i]
                end
            else -- }
                if last.n % 2 ~= 0 then
                    error 'expected even number of values in table literal'
                end
                val = {}
                for i = 1, last.n, 2 do
                    val[last[i]] = last[i + 1]
                end
            end
            stack[#stack] = nil
            dispatch(val)
        elseif b == 34 or b == 39 then -- Quoted string
            local start = b
            local last
            local chars = {start}
            repeat
                last = b
                b = getb()
                chars[#chars + 1] = b
            until not b or (b == start and last ~= 92)
            if not b then error 'unexpected end of source' end
            local raw = string.char(unpack(chars))
            local loadFn = loadCode(('return %s'):format(raw))
            dispatch(loadFn())
        else -- Try symbol
            local chars = {}
            repeat
                chars[#chars + 1] = b
                b = getb()
            until not b or not issymbolchar(b)
            if b then ungetb(b) end
            local rawstr = string.char(unpack(chars))
            if rawstr == 'nil' then dispatch(nil)
            elseif rawstr == 'true' then dispatch(true)
            elseif rawstr == 'false' then dispatch(false)
            elseif rawstr == '...' then dispatch(VARARG)
            elseif rawstr:match('^:[%w_-]*$') then -- keyword style strings
                dispatch(rawstr:sub(2))
            else
                local forceNumber = rawstr:match('^%d')
                local x
                if forceNumber then
                    x = tonumber(rawstr) or error('could not read token "' .. rawstr .. '"')
                else
                    x = tonumber(rawstr) or sym(rawstr)
                end
                dispatch(x)
            end
        end
    until done
    return true, retval
end

-- Serializer

local toStrings = {}

-- Serialize an AST into a string that can be read back again with the parser.
-- Cyclic and other non-normal tables are not readable but should print fine.
local function astToString(ast, seen)
    return (toStrings[type(ast)] or tostring)(ast, seen)
end

function toStrings.table(tab, seen)
    seen = seen or {n = 0}
    if seen[tab] then
        return ('<cycle %d>'):format(seen[tab])
    end
    local n = seen.n + 1
    seen[tab] = n
    seen.n = n
    if isSym(tab) then
        return tab[1]
    elseif isList(tab) then
        local buffer = {}
        for i = 1, tab.n do
            buffer[i] = astToString(tab[i], _G)
        end
        return '(' .. table.concat(buffer, ' ') .. ')'
    else
        local buffer = {}
        for k, v in pairs(tab) do
            buffer[#buffer + 1] = astToString(k, seen)
            buffer[#buffer + 1] = astToString(v, seen)
        end
        return '{' .. table.concat(buffer, ' ') .. '}'
    end
end

function toStrings.string(str)
    local ret = ("%q"):format(str):gsub('\n', 'n'):gsub("[\128-\255]", function(c)
        return "\\" .. c:byte()
    end)
    return ret
end

function toStrings.number(num)
    return ('%.17g'):format(num)
end

-- Compilation

-- Creat a new Scope, optionally under a parent scope. Scopes are compile time constructs
-- that are responsible for keeping track of local variables, name mangling, and macros.
-- They are accessible to user code via the '*compiler' special form (may change). They
-- use metatables to implmenent nesting via inheritance.
local function makeScope(parent)
    return {
        unmanglings = setmetatable({}, {
            __index = parent and parent.unmanglings
        }),
        manglings = setmetatable({}, {
            __index = parent and parent.manglings
        }),
        specials = setmetatable({}, {
            __index = parent and parent.specials
        }),
        parent = parent,
        vararg = parent and parent.vararg,
        depth = parent and ((parent.depth or 0) + 1) or 0
    }
end

local function scopeInside(outer, inner)
    repeat
        if inner == outer then return true end
        inner = inner.parent
    until not inner
    return false
end

local GLOBAL_SCOPE = makeScope()
local SPECIALS = GLOBAL_SCOPE.specials
local COMPILER_SCOPE = makeScope(GLOBAL_SCOPE)

local luaKeywords = {
    'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function',
    'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true',
    'until', 'while'
}
for i, v in ipairs(luaKeywords) do
    luaKeywords[v] = i
end

-- A multi symbol is a symbol that is actually composed of
-- two or more symbols using the dot syntax. The main differences
-- from normal symbols is that they cannot be declared local, and
-- they may have side effects on invocation (metatables)
local function isMultiSym(str)
    if type(str) ~= 'string' then return end
    local parts = {}
    for part in str:gmatch('[^%.]+') do
        parts[#parts + 1] = part
    end
    return #parts > 0 and
        str:match('%.') and
        (not str:match('%.%.')) and
        str:byte() ~= string.byte '.' and
        str:byte(-1) ~= string.byte '.' and
        parts
end

-- Creates a symbol from a string by mangling it.
-- ensures that the generated symbol is unique
-- if the input string is unique in the scope.
local function stringMangle(str, scope, noMulti)
    if scope.manglings[str] then
        return scope.manglings[str]
    end
    local append = 0
    local mangling = str
    local parts = isMultiSym(str)
    if parts then
        local ret
        for i = 1, #parts do
            if ret then
                ret = ret .. '[' .. toStrings.string(parts[i]) .. ']'
            else
                ret = stringMangle(parts[i], scope)
            end
        end
        if ret then
            if noMulti then error 'did not expect a multi symbol' end
            return ret
        end
    end
    if luaKeywords[mangling] then
        mangling = '_' .. mangling
    end
    mangling = mangling:gsub('[^%w_]', function(c)
        return ('_%02x'):format(c:byte())
    end)
    local raw = mangling
    while scope.unmanglings[mangling] do
        mangling = raw .. append
        append = append + 1
    end
    scope.unmanglings[mangling] = str
    scope.manglings[str] = mangling
    return mangling
end

-- Generates a unique symbol in the scope, ensuring it is unique in child scopes as well
-- if they are passed in.
local function gensym(...)
    local scope = ... -- the root scope
    assert(scope, 'expected at least 1 scope')
    local len = select('#', ...)
    local mangling, append = nil, 0
    local function done(...)
        for i = 1, len do
            if select(i, ...).unmanglings[mangling] then
                return false
            end
        end
        return true
    end
    repeat
        mangling = '_' .. append .. '_'
        append = append + 1
    until done(...)
    scope.unmanglings[mangling] = true
    return mangling
end

-- Convert a literal in the AST to a Lua string. Note that this is very different from astToString,
-- which converts and AST into a MLP readable string.
local function literalToString(x, scope)
    if isSym(x) then return stringMangle(x[1], scope) end
    if x == VARARG then return '...' end
    if type(x) == 'number' then return ('%.17g'):format(x) end
    if type(x) == 'string' then return toStrings.string(x) end
    if type(x) == 'table' then
        local buffer = {}
        for i = 1, #x do -- Write numeric keyed values.
            buffer[#buffer + 1] = literalToString(x[i], scope)
        end
        for k, v in pairs(x) do -- Write other keys.
            if type(k) ~= 'number' or math.floor(k) ~= k or k < 1 or k > #x then
                buffer[#buffer + 1] = ('[%s] = %s'):format(literalToString(k, scope), literalToString(v, scope))
            end
        end
        return '{' .. table.concat(buffer, ', ') ..'}'
    end
    return tostring(x)
end

-- Flatten a tree of Lua source code lines.
-- Tab is what is used to indent a block. By default it is two spaces.
local function flattenChunk(chunk, tab, subChunk)
    if type(chunk) == 'string' then
        return chunk
    end
    tab = tab or '  ' -- 2 spaces
    for i = 1, #chunk do
        local sub = flattenChunk(chunk[i], tab, true)
        if subChunk then sub = tab .. sub:gsub('\n', '\n' .. tab) end
        chunk[i] = sub
    end
    return table.concat(chunk, '\n')
end

-- Convert expressions to Lua string
local function exprs1(exprs)
    local t = {}
    for _, e in ipairs(exprs) do
        t[#t + 1] = e[1]
    end
    return table.concat(t, ', ')
end

-- Compile sideffects for a chunk
local function keepSideEffects(exprs, chunk, start)
    start = start or 1
    for j = start, #exprs do
        local se = exprs[j]
        if se.type == 'expression' then
            chunk[#chunk + 1] = ('do local _ = %s end'):format(tostring(se))
        elseif se.type == 'statement' then
            chunk[#chunk + 1] = tostring(se)
        end
    end
end

-- Make sure a list of expression has the correct arity
-- Modify exprs
local function checkNval(exprs, parent, n)
    if n ~= #exprs then
        local len = #exprs
        if len > n then
            -- Drop extra
            keepSideEffects(exprs, parent, n + 1)
            for i = n, len do
                exprs[i] = nil
            end
        else
            -- Should we pad with nils?
            -- Pad with nils
            for i = #exprs + 1, n do
                exprs[i] = expr('nil', 'literal')
            end
        end
    end
    return exprs
end

-- Does some common handling of returns and register
-- targets for special forms.
local function handleCompileOpts(exprs, parent, opts)
    if opts.nval then
        checkNval(exprs, parent, opts.nval)
    end
    if opts.tail then
        parent[#parent + 1] = ('return %s'):format(exprs1(exprs))
    end
    if opts.target then
        parent[#parent + 1] = ('%s = %s'):format(opts.target, exprs1(exprs))
    end
    if opts.tail or opts.target then
        exprs = {}
    end
    return exprs
end

-- Compile an AST expression in the scope into parent, a tree
-- of lines that is eventually compiled into Lua code. Also
-- returns some information about the evaluation of the compiled expression,
-- which can be used by the calling function. Macros
-- are resolved here, as well as special forms in that order.
-- the 'ast' param is the root AST to compile
-- the 'scope' param is the scope in which we are compiling
-- the 'parent' param is the table of lines that we are compiling into.
-- add lines to parent by appending strings. Add indented blocks by appending
-- tables of more lines.
-- the 'opts' param contains info about where the form is being compiled.
-- Options include:
--   'target' - mangled name of symbol(s) being compiled to.
--   'tail' - boolean indicating tail position if set.
local function compile1(ast, scope, parent, opts)
    opts = opts or {}
    local exprs = {}
    local target = opts.target

    -- Compile the form
    if isList(ast) then
        -- Function call or special form
        local len = ast.n
        -- Test for special form
        local first = ast[1]
        if isSym(first) then -- Resolve symbol
            first = first[1]
        end
        local special = scope.specials[first]
        if special and isSym(ast[1]) then
            -- Special form
            exprs = special(ast, scope, parent, opts) or {}
            -- Be very accepting of strings or expression
            -- as well as lists or expressions
            if type(exprs) == 'string' then exprs = expr(exprs, 'expression') end
            if getmetatable(exprs) == EXPR_MT then exprs = {exprs} end
            if not exprs.returned then
                exprs = handleCompileOpts(exprs, parent, opts)
            end
            if opts.tail or opts.target then
                exprs = {}
            end
            exprs.returned = true
            return exprs
        else
            -- Function call
            local fargs = {}
            local fcallee = tostring(compile1(ast[1], scope, parent, {
                nval = 1
            })[1])
            for i = 2, len do
                local subexprs = compile1(ast[i], scope, parent, {
                    nval = i ~= len and 1 or nil
                })
                fargs[#fargs + 1] = subexprs[1] or expr('nil', 'literal')
                if i == len then
                    -- Add sub expressions to function args
                    for j = 2, #subexprs do
                        fargs[#fargs + 1] = subexprs[j]
                    end
                else
                    -- Emit sub expression only for side effects
                    keepSideEffects(subexprs, parent, 2)
                end
            end
            local call = ('%s(%s)'):format(tostring(fcallee), exprs1(fargs))
            if opts.tail then
                -- Tail calls
                parent[#parent + 1] = ('return %s'):format(call)
            elseif target then
                parent[#parent + 1] = ('%s = %s'):format(target, call)
            else
                exprs[1] = expr(call, 'statement')
            end
        end
    else
        -- Literal (string, number, etc.)
        local literal = literalToString(ast, scope)
        if opts.tail then
            parent[#parent + 1] = ('return %s'):format(literal)
        elseif target then
            parent[#parent + 1] = ('%s = %s'):format(target, literal)
        else
            exprs[1] = expr(literal, 'literal')
        end
    end
    if opts.nval then
        checkNval(exprs, parent, opts.nval)
    end
    exprs.returned = true
    return exprs
end

-- SPECIALS --

-- Implements destructuring for forms like let, bindings, etc.
local function destructure1(left, rightexpr, scope, parent)
    if isSym(left) then
        parent[#parent + 1] = ('local %s = %s'):format(left[1], tostring(rightexpr))
        return
    end
    if not isTable(left) then
        error('unable to destructure ' .. literalToString(left, scope))
    end
    local s = gensym(scope)
    parent[#parent + 1] = ('local %s = %s'):format(s, tostring(rightexpr))
    for i, v in ipairs(left) do
        local subexpr = expr(('%s[%d]'):format(s, i), 'expression')
        destructure1(v, subexpr, scope, parent)
    end
end

local function destructure(left, right, scope, parent)
    local rexp = compile1(right, scope, parent, {nval = 1})[1]
    local ret = destructure1(left, rexp[1], scope, parent)
    return ret
end

-- Unlike most expressions and specials, 'values' resolves with multiple
-- values, one for each argument, allowing multiple return values. The last
-- expression, can return multiple arguments as well, allowing for more than the number
-- of expected arguments.
local function values(ast, scope, parent)
    local len = ast.n
    local exprs = {}
    for i = 2, len do
        local subexprs = compile1(ast[i], scope, parent, {})
        exprs[#exprs + 1] = subexprs[1] or expr('nil', 'literal')
        if i == len then
            for j = 2, #subexprs do
                exprs[#exprs + 1] = subexprs[j]
            end
        else
            -- Emit sub expression only for side effects
            keepSideEffects(subexprs, parent, 2)
        end
    end
    return exprs
end

-- Implements packing an ast into a single value.
local function pack(ast, scope, parent)
    local subexprs = SPECIALS.values(ast, scope, parent, {})
    local exprs = {expr('{' .. table.concat(subexprs, ', ') .. '}', 'expression')}
    return exprs
end

-- Compile a list of forms for side effects
local function compileDo(ast, scope, parent, start)
    start = start or 2
    local len = ast.n or #ast
    local subScope = makeScope(scope)
    for i = start, len do
        compile1(ast[i], subScope, parent, {
            nval = 0
        })
    end
end

-- Implements a do statment, starting at the 'start' element. By default, start is 2.
local function doImpl(ast, scope, parent, opts, start, chunk, subScope)
    start = start or 2
    subScope = subScope or makeScope(scope)
    chunk = chunk or {}
    local len = ast.n
    local outerTarget = opts.target
    local outerTail = opts.tail
    local retexprs = {returned = true}

    -- See if we need special handling to get the return values
    -- of the do block
    if not outerTarget and opts.nval ~= 0 and not outerTail then
        if opts.nval then
            -- Generate a local target
            local syms = {}
            for i = 1, opts.nval do
                local s = gensym(scope)
                syms[i] = s
                retexprs[i] = expr(s, 'sym')
            end
            outerTarget = table.concat(syms, ', ')
            parent[#parent + 1] = ('local %s'):format(outerTarget)
            parent[#parent + 1] = 'do'
        else
            -- We will use an IIFE for the do
            local fname = gensym(scope)
            parent[#parent + 1] = ('local function %s()'):format(fname)
            retexprs = expr(fname .. '()', 'statement')
            outerTail = true
            outerTarget = nil
        end
    else
        parent[#parent + 1] = 'do'
    end
    -- Compile the body
    if start > len then
        -- In the unlikely case we do a do with no arguments.
        compile1(nil, subScope, chunk, {
            tail = outerTail,
            target = outerTarget
        })
        -- There will be no side effects
    else
        for i = start, len do
            local subopts = {
                nval = i ~= len and 0 or nil,
                tail = i == len and outerTail or nil,
                target = i == len and outerTarget or nil
            }
            local subexprs = compile1(ast[i], subScope, chunk, subopts)
            if i ~= len then
                keepSideEffects(subexprs, parent)
            end
        end
    end
    parent[#parent + 1] = chunk
    parent[#parent + 1] = 'end'
    return retexprs
end

SPECIALS['do'] = doImpl
SPECIALS['values'] = values

-- Wrap a variadic number of arguments into a table. Does NOT do length capture
SPECIALS['pack'] = pack

-- The fn special declares a function. Syntax is similar to other lisps;
-- (fn optional-name [arg ...] (body))
-- Further decoration such as docstrings, meta info, and multibody functions a possibility.
SPECIALS['fn'] = function(ast, scope, parent)
    local fScope = makeScope(scope)
    local fChunk = {}
    local index = 2
    local fnName = isSym(ast[index])
    local isLocalFn
    if fnName then
        isLocalFn = not isMultiSym(fnName[1])
        fnName = stringMangle(fnName[1], scope)
        index = index + 1
    else
        isLocalFn = true
        fnName = gensym(scope)
    end
    local argList = assert(isTable(ast[index]), 'expected vector arg list [a b ...]')
    local argNameList = {}
    for i = 1, #argList do
        if isVarg(argList[i]) then
            argNameList[i] = '...'
            fScope.vararg = true
        else
            argNameList[i] = stringMangle(assert(isSym(argList[i]),
            'expected symbol for function parameter')[1], fScope)
        end
    end
    for i = index + 1, ast.n do
        compile1(ast[i], fScope, fChunk, {
            tail = i == ast.n,
            nval = i ~= ast.n and 0 or nil
        })
    end
    if isLocalFn then
        parent[#parent + 1] = ('local function %s(%s)')
        :format(fnName, table.concat(argNameList, ', '))
    else
        parent[#parent + 1] = ('%s = function(%s)')
        :format(fnName, table.concat(argNameList, ', '))
    end
    parent[#parent + 1] = fChunk
    parent[#parent + 1] = 'end'
    return fnName
end

SPECIALS['$'] = function(ast, scope, parent)
    local maxArg = 0
    local function walk(node)
        if type(node) ~= 'table' then return end
        if isSym(node) then
            local num = node[1]:match('^%$(%d+)$')
            if num then
                maxArg = math.max(maxArg, tonumber(num))
            end
            return
        end
        for k, v in pairs(node) do
            walk(k)
            walk(v)
        end
    end
    walk(ast)
    local fargs = {}
    for i = 1, maxArg do table.insert(fargs, sym('$' .. i)) end
    table.remove(ast, 1)
    ast.n = ast.n - 1
    return SPECIALS.fn({'', sym('$$'), fargs, ast, n = 4}, scope, parent)
end

SPECIALS['lambda'] = function(ast, scope, parent)
    table.remove(ast, 1)
    local arglist = table.remove(ast, 1)
    for _, arg in ipairs(arglist) do
        if not arg[1]:match("^?") then
            table.insert(ast, 1,
                list(sym("assert"), arg, "Missing argument: " .. arg[1]))
        end
    end
    local new = list(sym("lambda"), arglist, unpack(ast))
    return SPECIALS.fn(new, scope, parent)
end
SPECIALS['λ'] = SPECIALS['lambda']

SPECIALS['special'] = function(ast, scope, parent)
    assert(scopeInside(COMPILER_SCOPE, scope), 'can only declare special forms in \'eval-compiler\'')
    assert(isSym(ast[2]), "expected symbol for name of special form")
    local specname = tostring(ast[2])
    local spec = SPECIALS.fn(ast, scope, parent, {nval = 1})[1]
    parent[#parent + 1] = ('_SCOPE.specials[%q] = %s'):format(
        stringMangle(specname, scope), tostring(spec))
end

SPECIALS['macro'] = function(ast, scope, parent, opts)
    assert(scopeInside(COMPILER_SCOPE, scope), 'can only declare macros in \'eval-compiler\'')
    local mac = SPECIALS.fn(ast, scope, parent, opts)[1]
    local macroName = tostring(mac) -- the fn special form always returns a value
    local s = gensym(scope)
    parent[#parent + 1] = ('local function %s(ast, scope, chunk, opts)'):format(s)
    parent[#parent + 1] = {
        'local unpack = table.unpack or unpack',
        ('return _FNL.compile1(%s(unpack(ast, 2, ast.n)), scope, chunk, opts)'):format(macroName)
    }
    parent[#parent + 1] = 'end'
    parent[#parent + 1] = ('_SCOPE.specials[%s] = %s'):format(macroName, s)
end

-- Wrapper for table access
SPECIALS['.'] = function(ast, scope, parent)
    local lhs = compile1(ast[2], scope, parent, {nval = 1})
    local rhs = compile1(ast[3], scope, parent, {nval = 1})
    return ('%s[%s]'):format(tostring(lhs[1]), tostring(rhs[1]))
end

SPECIALS['set'] = function(ast, scope, parent)
    local vars = {}
    for i = 2, math.max(2, ast.n - 1) do
        local s = assert(isSym(ast[i]), "expected symbol")
        vars[i - 1] = stringMangle(s[1], scope)
    end
    assert(#vars > 0, "expected at least 1 variable to set")
    local varname = table.concat(vars, ', ')
    return compile1(ast[ast.n], scope, parent, {
        target = varname
    })
end

SPECIALS['let'] = function(ast, scope, parent, opts)
    local bindings = ast[2]
    assert(isTable(bindings), 'expected table for destructuring')
    local subScope = makeScope(scope)
    local subChunk = {}
    for i = 1, bindings.n or #bindings, 2 do
        destructure(bindings[i], bindings[i + 1], subScope, subChunk)
    end
    return doImpl(ast, scope, parent, opts, 3, subChunk, subScope)
end

-- For setting items in a table
SPECIALS['tset'] = function(ast, scope, parent)
    local root = compile1(ast[2], scope, parent, {nval = 1})[1]
    local keys = {}
    for i = 3, ast.n - 1 do
        local key = compile1(ast[i], scope, parent, {nval = 1})[1]
        keys[#keys + 1] = tostring(key)
    end
    local value = compile1(ast[ast.n], scope, parent, {nval = 1})[1]
    parent[#parent + 1] = ('%s[%s] = %s'):format(tostring(root), table.concat(keys, ']['), tostring(value))
end

-- The if special form behaves like the cond form in
-- many languages
SPECIALS['if'] = function(ast, scope, parent, opts)
    local doScope = makeScope(scope)
    local branches = {}
    local elseBranch = nil

    -- Calculate some external stuff. Optimizes for tail calls and what not
    local outerTail = true
    local outerTarget = nil
    local wrapper = 'iife'
    if opts.tail then
        wrapper = 'none'
    end

    -- Compile bodies and conditions
    local bodyOpts = {
        tail = outerTail,
        target = outerTarget
    }
    local function compileBody(i)
        local chunk = {}
        local cscope = makeScope(doScope)
        compile1(ast[i], cscope, chunk, bodyOpts)
        return {
            chunk = chunk,
            scope = cscope
        }
    end
    for i = 2, ast.n - 1, 2 do
        local condchunk = {}
        local cond =  compile1(ast[i], doScope, condchunk, {nval = 1})
        local branch = compileBody(i + 1)
        branch.cond = cond
        branch.condchunk = condchunk
        table.insert(branches, branch)
    end
    local hasElse = ast.n > 3 and ast.n % 2 == 0
    if hasElse then elseBranch = compileBody(ast.n) end

    -- Emit code
    local s = gensym(scope)
    local buffer = {}
    local lastBuffer = buffer
    for i = 1, #branches do
        local branch = branches[i]
        local condLine = ('if %s then'):format(tostring(branch.cond[1]))
        table.insert(lastBuffer, branch.condchunk)
        table.insert(lastBuffer, condLine)
        table.insert(lastBuffer, branch.chunk)
        if i == #branches then
            if hasElse then
                table.insert(lastBuffer, 'else')
                table.insert(lastBuffer, elseBranch.chunk)
            end
            table.insert(lastBuffer, 'end')
        else
            table.insert(lastBuffer, 'else')
            local nextBuffer = {}
            table.insert(lastBuffer, nextBuffer)
            table.insert(lastBuffer, 'end')
            lastBuffer = nextBuffer
        end
    end

    if wrapper == 'iife' then
        parent[#parent + 1] = ('local function %s()'):format(tostring(s))
        parent[#parent + 1] = buffer
        parent[#parent + 1] = 'end'
        return expr(('%s()'):format(tostring(s)), 'statement')
    elseif wrapper == 'none' then
        -- Splice result right into code
        for i = 1, #buffer do
            parent[#parent + 1] = buffer[i]
        end
        return {returned = true}
    end
end

-- (when condition body...) => []
SPECIALS['when'] = function(ast, scope, parent, opts)
    table.remove(ast, 1)
    local condition = table.remove(ast, 1)
    local new_ast = list(sym("if"), condition, list(sym("block"), unpack(ast)))
    return SPECIALS["if"](new_ast, scope, parent, opts)
end

-- (block body...) => []
SPECIALS['block'] = function(ast, scope, parent)
    compileDo(ast, scope, parent, 2)
end

-- (each [k v (pairs t)] body...) => []
SPECIALS['each'] = function(ast, scope, parent)
    local binding = assert(isTable(ast[2]), 'expected binding table in each')
    local iter = table.remove(binding, #binding) -- last item is iterator call
    local bindVars = {}
    for _, v in ipairs(binding) do
        table.insert(bindVars, literalToString(v, scope))
    end
    parent[#parent + 1] = ('for %s in %s do'):format(
        table.concat(bindVars, ', '),
        tostring(compile1(iter, scope, parent, {nval = 1})[1]))
    local chunk = {}
    local subScope = makeScope(scope)
    compileDo(ast, subScope, chunk, 3)
    parent[#parent + 1] = chunk
    parent[#parent + 1] = 'end'
end

-- (while condition body...) => []
SPECIALS['*while'] = function(ast, scope, parent)
    local len1 = #parent
    local condition = compile1(ast[2], scope, parent, {nval = 1})[1]
    local len2 = #parent
    local subChunk = {}
    if len1 ~= len2 then
        -- Compound condition
        parent[#parent + 1] = 'while true do'
        -- Move new compilation to subchunk
        for i = len1 + 1, len2 do
            subChunk[#subChunk + 1] = parent[i]
            parent[i] = nil
        end
        parent[#parent + 1] = ('if %s then break end'):format(condition[1])
    else
        -- Simple condition
        parent[#parent + 1] = 'while ' .. tostring(condition) .. ' do'
    end
    compileDo(ast, makeScope(scope), subChunk, 3)
    parent[#parent + 1] = subChunk
    parent[#parent + 1] = 'end'
end

SPECIALS['for'] = function(ast, scope, parent)
    local ranges = assert(isTable(ast[2]), 'expected binding table in for')
    local bindingSym = assert(isSym(table.remove(ast[2], 1)),
    'expected iterator symbol in for')
    local rangeArgs = {}
    for i = 1, math.min(#ranges, 3) do
        rangeArgs[i] = tostring(compile1(ranges[i], scope, parent, {nval = 1})[1])
    end
    parent[#parent + 1] = ('for %s = %s do'):format(
        literalToString(bindingSym, scope),
        table.concat(rangeArgs, ', '))
    local chunk = {}
    local subScope = makeScope(scope)
    compileDo(ast, subScope, chunk, 3)
    parent[#parent + 1] = chunk
    parent[#parent + 1] = 'end'
end

-- Do we need this? Is there a more elegnant way to compile with break?
SPECIALS['*break'] = function(_, _, parent)
    parent[#parent + 1] = 'break'
end

local function defineArithmeticSpecial(name, unaryPrefix)
    local paddedOp = ' ' .. name .. ' '
    SPECIALS[name] = function(ast, scope, parent)
        local len = ast.n or #ast
        if len == 1 then
            return unaryPrefix or '0'
        else
            local operands = {}
            for i = 2, len do
                local subexprs = compile1(ast[i], scope, parent, {
                    nval = (i == 1 and 1 or nil)
                })
                for j = 1, #subexprs do
                    operands[#operands + 1] = tostring(subexprs[j])
                end
            end
            if #operands == 1 and unaryPrefix then
                return '(' .. unaryPrefix .. paddedOp .. operands[1] .. ')'
            else
                return '(' .. table.concat(operands, paddedOp) .. ')'
            end
        end
    end
end

defineArithmeticSpecial('+')
defineArithmeticSpecial('..')
defineArithmeticSpecial('^')
defineArithmeticSpecial('-', '')
defineArithmeticSpecial('*')
defineArithmeticSpecial('%')
defineArithmeticSpecial('/', 1)
defineArithmeticSpecial('or')
defineArithmeticSpecial('and')

local function defineComparatorSpecial(name, realop)
    local op = realop or name
    SPECIALS[name] = function(ast, scope, parent)
        local lhs = compile1(ast[2], scope, parent, {nval = 1})
        local rhs = compile1(ast[3], scope, parent, {nval = 1})
        return ('((%s) %s (%s))'):format(tostring(lhs[1]), op, tostring(rhs[1]))
    end
end

defineComparatorSpecial('>')
defineComparatorSpecial('<')
defineComparatorSpecial('>=')
defineComparatorSpecial('<=')
defineComparatorSpecial('=', '==')
defineComparatorSpecial('~=')

local function defineUnarySpecial(op, realop)
    SPECIALS[op] = function(ast, scope, parent)
        local tail = compile1(ast[2], scope, parent, {nval = 1})
        return (realop or op) .. tostring(tail[1])
    end
end

defineUnarySpecial('not', 'not ')
defineUnarySpecial('#')

local function compile(ast, options)
    options = options or {}
    local chunk = {}
    local scope = options.scope or makeScope(GLOBAL_SCOPE)
    local exprs = compile1(ast, scope, chunk, {tail = true})
    keepSideEffects(exprs, chunk)
    return flattenChunk(chunk, options.indent)
end

local function compileStream(strm, options)
    options = options or {}
    local scope = options.scope or makeScope(GLOBAL_SCOPE)
    local vals = {}
    while true do
        local ok, val = parse(strm)
        if not ok then break end
        vals[#vals + 1] = val
    end
    local chunk = {}
    for i = 1, #vals do
        local exprs = compile1(vals[i], scope, chunk, {
            tail = i == #vals
        })
        keepSideEffects(exprs, chunk)
    end
    return flattenChunk(chunk, options.indent)
end

local function compileString(str, options)
    local strm = stringstream(str)
    return compileStream(strm, options)
end

local function eval(str, options)
    options = options or {}
    local luaSource = compileString(str, options)
    local loader = loadCode(luaSource, options.env, options.filename)
    return loader()
end

-- Implements a simple repl
local function repl(givenOptions)
    local options = {
        prompt = '>> ',
        read = io.read,
        write = io.write,
        flush = io.flush,
        print = print,
    }
    for k,v in pairs(givenOptions or {}) do
        options[k] = v
    end

    local env = options.env or setmetatable({}, {
        __index = _ENV or _G
    })
    local bytestream, clearstream = granulate(function()
        options.write(options.prompt)
        options.flush()
        local input = options.read()
        return input and input .. '\n'
    end)
    while true do
        local ok, parseok, x = pcall(parse, bytestream)
        if ok then
            if not parseok then break end -- eof
            local luaSource = compile(x)
            local loader, err = loadCode(luaSource, env)
            if err then
                clearstream()
                options.print(err)
            else
                local ok, ret = xpcall(function () return tpack(loader()) end, 
                    function (err)
                        -- We can do more sophisticated display here
                        options.print(err)
                    end)
                if ok then
                    for i = 1, ret.n do
                        ret[i] = astToString(ret[i])
                    end
                    options.print(unpack(ret))
                end
            end
        else
            -- parse error
            options.print(parseok)
            clearstream()
        end
    end
end

local module = {
    parse = parse,
    granulate = granulate,
    stringstream = stringstream,
    astToString = astToString,
    compile = compile,
    compileString = compileString,
    compileStream = compileStream,
    compile1 = compile1,
    list = list,
    sym = sym,
    varg = varg,
    scope = makeScope,
    gensym = gensym,
    eval = eval,
    repl = repl
}

SPECIALS['eval-compiler'] = function(ast, scope, parent)
    local oldFirst = ast[1]
    ast[1] = sym('do')
    local luaSource = compile(ast, {
        scope = makeScope(COMPILER_SCOPE)
    })
    ast[1] = oldFirst
    local env = setmetatable({
        _FNL = module,
        _SCOPE = scope,
        _CHUNK = parent,
        _AST = ast,
        _IS_COMPILER = true
    }, { __index = _ENV or _G })
    local loader = loadCode(luaSource, env)
    loader()
end

return module
