--[[
Copyright (c) 2016-2023 Calvin Rose and contributors
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

-- This is a copy of an old version of the compiler from right before it became
-- self-hosted, with a few newer features backported to it. We use this to
-- bootstrap the current compiler in the src/ directory, which is written in
-- Fennel, and thus needs a Fennel compiler to run.

-- Changelog: (since 0.4.3)

-- * set _G in compiler env
-- * backport magic :_COMPILER scope option
-- * replace global mangling with _G["whatever?"] <- backwards incompatibility!
-- * backport idempotency checks in 3+ arity operator calls
-- * backport some IIFE avoidance
-- * add workaround for luajit bug
-- * add support for &until in addition to :until in loops
-- * fix setReset to not accidentally set a global

-- Make global variables local.
local setmetatable = setmetatable
local getmetatable = getmetatable
local type = type
local assert = assert
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local unpack = _G.unpack or table.unpack

--
-- Main Types and support functions
--

local utils = (function()
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

    local function every(t, f)
       for _,v in ipairs(t) do
          if(not f(v)) then return false end
       end
       return true
    end

    -- Returns a shallow copy of its table argument. Returns an empty table on nil.
    local function copy(from)
       local to = {}
       for k, v in pairs(from or {}) do to[k] = v end
       return to
    end

    -- Like pairs, but if the table has an __index metamethod, it will recursively
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

    local function symeq(a, b)
       return ((deref(a) == deref(b)) and (getmetatable(a) == getmetatable(b)))
    end

    local function symlt(a, b)
       return (a[1] < tostring(b))
    end

    local nilSym -- haven't defined sym yet; create this later

    local function listToString(self, tostring2)
        local safe, max = {}, 0
        for k in pairs(self) do if type(k) == "number" and k>max then max=k end end
        for i=1,max do -- table.maxn was removed from Lua 5.3 for some reason???
            safe[i] = self[i] == nil and nilSym or self[i]
        end
        return '(' .. table.concat(map(safe, tostring2 or tostring), ' ', 1, max) .. ')'
    end

    local SYMBOL_MT = { 'SYMBOL', __tostring = deref, __fennelview = deref,
                        __eq = symeq, __lt = symlt }
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

    local function isIdempotent(expr)
       local t = type(expr)
       return t == "string" or t == "integer" or t == "number" or
          (isSym(expr) and not isMultiSym(expr))
    end

    local function astSource(ast)
       if (isTable(ast) or isSequence(ast)) then
          return (getmetatable(ast) or {})
       elseif ("table" == type(ast)) then
          return ast
       else
          return {}
       end
    end

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
        ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
        ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
        ["function"] = true, ["if"] = true, ["in"] = true, ["local"] = true,
        ["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true,
        ["return"] = true, ["then"] = true, ["true"] = true, ["until"] = true,
        ["while"] = true, ["goto"] = true,
    }

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
    }

    root.setReset=function(root)
       local chunk, scope, options = root.chunk, root.scope, root.options
       local oldResetRoot = root.reset -- this needs to nest!
       root.reset = function()
          root.chunk, root.scope, root.options = chunk, scope, options
          root.reset = oldResetRoot
       end
    end

    return {
        -- basic general table functions:
        stablepairs=stablepairs, allpairs=allpairs, map=map, kvmap=kvmap,
        every=every, copy=copy, walkTree=walkTree,

        -- AST functions:
        list=list, sym=sym, sequence=sequence, expr=expr, varg=varg,
        isVarg=isVarg, isList=isList, isSym=isSym, isTable=isTable, deref=deref,
        isSequence=isSequence, isMultiSym=isMultiSym, isQuoted=isQuoted,
        isExpr=isExpr, astSource=astSource, isIdempotent=isIdempotent,

        -- other functions:
        isValidLuaIdentifier=isValidLuaIdentifier, luaKeywords=luaKeywords,
        propagateOptions=propagateOptions, debugOn=debugOn,
        root=root, path=table.concat(pathTable, ";"),}
end)()

--
-- Parser
--

local parser = (function()
    -- Convert a stream of chunks to a stream of bytes.
    -- Also returns a second function to clear the buffer in the byte stream
    local function granulate(getchunk)
        local c = ''
        local index = 1
        local done = false
        return function (parserState)
            if done then return nil end
            if index <= #c then
                local b = c:byte(index)
                index = index + 1
                return b
            else
                c = getchunk(parserState)
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
    local function stringStream(str)
        str=str:gsub("^#![^\n]*\n", "") -- remove shebang
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
        return b == 32 or (b >= 9 and b <= 13)
    end

    local function issymbolchar(b)
        return b > 32 and
            not delims[b] and
            b ~= 127 and -- "<BS>"
            b ~= 34 and -- "\""
            b ~= 39 and -- "'"
            b ~= 126 and -- "~"
            b ~= 59 and -- ";"
            b ~= 44 and -- ","
            b ~= 64 and -- "@"
            b ~= 96 -- "`"
    end

    local prefixes = { -- prefix chars substituted while reading
        [96] = 'quote', -- `
        [44] = 'unquote', -- ,
        [39] = 'quote', -- '
        [35] = 'hashfn' -- #
    }

    -- Parse one value given a function that
    -- returns sequential bytes. Will throw an error as soon
    -- as possible without getting more bytes on bad input. Returns
    -- if a value was read, and then the value read. Will return nil
    -- when input stream is finished.
    local function parser(getbyte, filename, options)

        -- Stack of unfinished values
        local stack = {}

        -- Provide one character buffer and keep
        -- track of current line and byte index
        local line = 1
        local byteindex = 0
        local lastb
        local function ungetb(ub)
            if ub == 10 then line = line - 1 end
            byteindex = byteindex - 1
            lastb = ub
        end
        local function getb()
            local r
            if lastb then
                r, lastb = lastb, nil
            else
                r = getbyte({ stackSize = #stack })
            end
            byteindex = byteindex + 1
            if r == 10 then line = line + 1 end
            return r
        end

        -- If you add new calls to this function, please update fenneldfriend.fnl
        -- as well to add suggestions for how to fix the new error.
        local function parseError(msg)
            local source = utils.root.options and utils.root.options.source
            utils.root.reset()
            local override = options and options["parse-error"]
            if override then override(msg, filename or "unknown", line or "?",
                                      byteindex, source) end
            return error(("Parse error in %s:%s: %s"):
                    format(filename or "unknown", line or "?", msg), 0)
        end

        -- Parse stream
        return function()

            -- Dispatch when we complete a value
            local done, retval
            local whitespaceSinceDispatch = true
            local function dispatch(v)
                local len = #stack
                local stacktop = stack[len]
                if len == 0 then
                    retval = v
                    done = true
                elseif stack[len].prefix then
                    stack[len] = nil
                    return dispatch(utils.list(utils.sym(stacktop.prefix), v))
                else
                    table.insert(stack[len], v)
                end
                whitespaceSinceDispatch = false
            end

            -- Throw nice error when we expect more characters
            -- but reach end of stream.
            local function badend()
                local accum = utils.map(stack, "closer")
                parseError(('expected closing delimiter%s %s'):format(
                    #stack == 1 and "" or "s",
                    string.char(unpack(accum))))
            end

            -- The main parse loop
            repeat
                local b

                -- Skip whitespace
                repeat
                    b = getb()
                    if b and iswhitespace(b) then
                        whitespaceSinceDispatch = true
                    end
                until not b or not iswhitespace(b)
                if not b then
                    if #stack > 0 then badend() end
                    return nil
                end

                if b == 59 then -- ; Comment
                    repeat
                        b = getb()
                    until not b or b == 10 -- newline
                elseif type(delims[b]) == 'number' then -- Opening delimiter
                    if not whitespaceSinceDispatch then
                        parseError('expected whitespace before opening delimiter '
                                       .. string.char(b))
                    end
                    table.insert(stack, setmetatable({
                        closer = delims[b],
                        line = line,
                        filename = filename,
                        bytestart = byteindex
                    }, getmetatable(utils.list())))
                elseif delims[b] then -- Closing delimiter
                    if #stack == 0 then parseError('unexpected closing delimiter '
                                                       .. string.char(b)) end
                    local last = stack[#stack]
                    local val
                    if last.closer ~= b then
                        parseError('mismatched closing delimiter ' .. string.char(b) ..
                                   ', expected ' .. string.char(last.closer))
                    end
                    last.byteend = byteindex -- Set closing byte index
                    if b == 41 then -- ; )
                        val = last
                    elseif b == 93 then -- ; ]
                        val = utils.sequence(unpack(last))
                        -- for table literals we can store file/line/offset source
                        -- data in fields on the table itself, because the AST node
                        -- *is* the table, and the fields would show up in the
                        -- compiled output. keep them on the metatable instead.
                        for k,v in pairs(last) do getmetatable(val)[k]=v end
                    else -- ; }
                        if #last % 2 ~= 0 then
                            byteindex = byteindex - 1
                            parseError('expected even number of values in table literal')
                        end
                        val = {}
                        setmetatable(val, last) -- see note above about source data
                        for i = 1, #last, 2 do
                            if(tostring(last[i]) == ":" and utils.isSym(last[i + 1])
                               and utils.isSym(last[i])) then
                                last[i] = tostring(last[i + 1])
                            end
                            val[last[i]] = last[i + 1]
                        end
                    end
                    stack[#stack] = nil
                    dispatch(val)
                elseif b == 34 then -- Quoted string
                    local state = "base"
                    local chars = {34}
                    stack[#stack + 1] = {closer = 34}
                    repeat
                        b = getb()
                        chars[#chars + 1] = b
                        if state == "base" then
                            if b == 92 then
                                state = "backslash"
                            elseif b == 34 then
                                state = "done"
                            end
                        else
                            -- state == "backslash"
                            state = "base"
                        end
                    until not b or (state == "done")
                    if not b then badend() end
                    stack[#stack] = nil
                    local raw = string.char(unpack(chars))
                    local formatted = raw:gsub("[\1-\31]", function (c)
                                                   return '\\' .. c:byte() end)
                    local loadFn = assert((loadstring or load)(('return %s'):format(formatted)))
                    dispatch(loadFn())
                elseif prefixes[b] then
                    -- expand prefix byte into wrapping form eg. '`a' into '(quote a)'
                    table.insert(stack, {
                        prefix = prefixes[b]
                    })
                    local nextb = getb()
                    if iswhitespace(nextb) then
                        if b == 35 then
                            stack[#stack] = nil
                            dispatch(utils.sym('#'))
                        else
                            parseError('invalid whitespace after quoting prefix')
                        end
                    end
                    ungetb(nextb)
                elseif issymbolchar(b) or b == string.byte("~") then -- Try sym
                    local chars = {}
                    local bytestart = byteindex
                    repeat
                        chars[#chars + 1] = b
                        b = getb()
                    until not b or not issymbolchar(b)
                    if b then ungetb(b) end
                    local rawstr = string.char(unpack(chars))
                    if rawstr == 'true' then dispatch(true)
                    elseif rawstr == 'false' then dispatch(false)
                    elseif rawstr == '...' then dispatch(utils.varg())
                    elseif rawstr:match('^:.+$') then -- colon style strings
                        dispatch(rawstr:sub(2))
                    elseif rawstr:match("^~") and rawstr ~= "~=" then
                        -- for backwards-compatibility, special-case allowance
                        -- of ~= but all other uses of ~ are disallowed
                        parseError("illegal character: ~")
                    else
                        local forceNumber = rawstr:match('^%d')
                        local numberWithStrippedUnderscores = rawstr:gsub("_", "")
                        local x
                        if forceNumber then
                            x = tonumber(numberWithStrippedUnderscores) or
                                parseError('could not read number "' .. rawstr .. '"')
                        else
                            x = tonumber(numberWithStrippedUnderscores)
                            if (x == nil) or (rawstr == "nan") then
                                if(rawstr:match("%.[0-9]")) then
                                    byteindex = (byteindex - #rawstr +
                                                     rawstr:find("%.[0-9]") + 1)
                                    parseError("can't start multisym segment " ..
                                                   "with a digit: ".. rawstr)
                                elseif(rawstr:match("[%.:][%.:]") and
                                       rawstr ~= ".." and rawstr ~= '$...') then
                                    byteindex = (byteindex - #rawstr +
                                                     rawstr:find("[%.:][%.:]") + 1)
                                    parseError("malformed multisym: " .. rawstr)
                                elseif(rawstr:match(":.+[%.:]")) then
                                    byteindex = (byteindex - #rawstr +
                                                     rawstr:find(":.+[%.:]"))
                                    parseError("method must be last component "
                                                   .. "of multisym: " .. rawstr)
                                else
                                    x = utils.sym(rawstr, nil, {line = line,
                                                          filename = filename,
                                                          bytestart = bytestart,
                                                          byteend = byteindex,})
                                end
                            end
                        end
                        dispatch(x)
                    end
                else
                    parseError("illegal character: " .. string.char(b))
                end
            until done
            return true, retval
        end, function ()
            stack = {}
        end
    end
    return { granulate=granulate, stringStream=stringStream, parser=parser }
end)()

--
-- Compilation
--

local compiler = (function()
    local scopes = {}

    -- Create a new Scope, optionally under a parent scope. Scopes are compile time
    -- constructs that are responsible for keeping track of local variables, name
    -- mangling, and macros.  They are accessible to user code via the
    -- 'eval-compiler' special form (may change). They use metatables to implement
    -- nesting.
    local function makeScope(parent)
        if not parent then parent = scopes.global end
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
            macros = setmetatable({}, {
                __index = parent and parent.macros
            }),
            symmeta = setmetatable({}, {
                __index = parent and parent.symmeta
            }),
            includes = setmetatable({}, {
                __index = parent and parent.includes
            }),
            refedglobals = setmetatable({}, {
                __index = parent and parent.refedglobals
            }),
            autogensyms = {},
            parent = parent,
            vararg = parent and parent.vararg,
            depth = parent and ((parent.depth or 0) + 1) or 0,
            hashfn = parent and parent.hashfn
        }
    end

    -- Assert a condition and raise a compile error with line numbers. The ast arg
    -- should be unmodified so that its first element is the form being called.
    -- If you add new calls to this function, please update fenneldfriend.fnl
    -- as well to add suggestions for how to fix the new error.
    local function assertCompile(condition, msg, ast)
        local override = utils.root.options and utils.root.options["assert-compile"]
        if override then
            local source = utils.root.options and utils.root.options.source
            -- don't make custom handlers deal with resetting root; it's error-prone
            if not condition then utils.root.reset() end
            override(condition, msg, ast, source)
            -- should we fall thru to the default check, or should we allow the
            -- override to swallow the error?
        end
        if not condition then
            utils.root.reset()
            local m = getmetatable(ast)
            local filename = m and m.filename or ast.filename or "unknown"
            local line = m and m.line or ast.line or "?"
            -- if we use regular `assert' we can't provide the `level' argument of 0
            error(string.format("Compile error in '%s' %s:%s: %s",
                                tostring(utils.isSym(ast[1]) and ast[1][1] or
                                             ast[1] or '()'),
                                filename, line, msg), 0)
        end
        return condition
    end

    scopes.global = makeScope()
    scopes.global.vararg = true
    scopes.compiler = makeScope(scopes.global)
    scopes.macro = scopes.global -- used by gensym, in-scope?, etc

    -- Allow printing a string to Lua, also keep as 1 line.
    local serializeSubst = {
        ['\a'] = '\\a',
        ['\b'] = '\\b',
        ['\f'] = '\\f',
        ['\n'] = 'n',
        ['\t'] = '\\t',
        ['\v'] = '\\v'
    }
    local function serializeString(str)
        local s = ("%q"):format(str)
        s = s:gsub('.', serializeSubst):gsub("[\128-\255]", function(c)
            return "\\" .. c:byte()
        end)
        return s
    end

    -- Mangler for global symbols. Does not protect against collisions,
    -- but makes them unlikely. This is the mangling that is exposed to
    -- to the world.
    local function globalMangling(str)
        if utils.isValidLuaIdentifier(str) then
            return str
        end
        return ("_G[%q]"):format(str)
    end

    -- Reverse a global mangling. Takes a Lua identifier and
    -- returns the fennel symbol string that created it.
    local function globalUnmangling(identifier)
        local rest = identifier:match('^__fnl_global__(.*)$')
        if rest then
            local r = rest:gsub('_[%da-f][%da-f]', function (code)
                return string.char(tonumber(code:sub(2), 16))
            end)
            return r -- don't return multiple values
        else
            return identifier
        end
    end

    -- If there's a provided list of allowed globals, don't let references thru that
    -- aren't on the list. This list is set at the compiler entry points of compile
    -- and compileStream.
    local allowedGlobals

    local function globalAllowed(name)
        if not allowedGlobals then return true end
        for _, g in ipairs(allowedGlobals) do
            if g == name then return true end
        end
    end

    -- Creates a symbol from a string by mangling it.
    -- ensures that the generated symbol is unique
    -- if the input string is unique in the scope.
    local function localMangling(str, scope, ast, tempManglings)
        local append = 0
        local mangling = str
        assertCompile(not utils.isMultiSym(str), 'unexpected multi symbol ' .. str, ast)

        -- Mapping mangling to a valid Lua identifier
        if utils.luaKeywords[mangling] or mangling:match('^%d') then
            mangling = '_' .. mangling
        end
        mangling = mangling:gsub('-', '_')
        mangling = mangling:gsub('[^%w_]', function (c)
            return ('_%02x'):format(c:byte())
        end)

        -- Prevent name collisions with existing symbols
        local raw = mangling
        while scope.unmanglings[mangling] do
            mangling = raw .. append
            append = append + 1
        end

        scope.unmanglings[mangling] = str
        local manglings = tempManglings or scope.manglings
        manglings[str] = mangling
        return mangling
    end

    -- Calling this function will mean that further
    -- compilation in scope will use these new manglings
    -- instead of the current manglings.
    local function applyManglings(scope, newManglings)
        for raw, mangled in pairs(newManglings) do
            -- Disabled because of some unknown bug in the old compiler
            -- assertCompile(not scope.refedglobals[mangled],
            -- "use of global " .. raw .. " is aliased by a local", ast)
            scope.manglings[raw] = mangled
        end
    end

    -- Combine parts of a symbol
    local function combineParts(parts, scope)
        local ret = scope.manglings[parts[1]] or globalMangling(parts[1])
        for i = 2, #parts do
            if utils.isValidLuaIdentifier(parts[i]) then
                if parts.multiSymMethodCall and i == #parts then
                    ret = ret .. ':' .. parts[i]
                else
                    ret = ret .. '.' .. parts[i]
                end
            else
                ret = ret .. '[' .. serializeString(parts[i]) .. ']'
            end
        end
        return ret
    end

    local function next_append()
        utils.root.scope.gensym_append = (utils.root.scope.gensym_append or 0) + 1
        return "_" .. utils.root.scope.gensym_append .. "_"
    end

    -- Generates a unique symbol in the scope.
    local function gensym(scope, base)
        local mangling
        repeat
            mangling = (base or '') .. next_append()
        until not scope.unmanglings[mangling]
        scope.unmanglings[mangling] = true
        return mangling
    end

    -- Generates a unique symbol in the scope based on the base name. Calling
    -- repeatedly with the same base and same scope will return existing symbol
    -- rather than generating new one.
    local function autogensym(base, scope)
        local parts = utils.isMultiSym(base)
        if(parts) then
            parts[1] = autogensym(parts[1], scope)
            return table.concat(parts, parts.multiSymMethodCall and ":" or ".")
        end

        if scope.autogensyms[base] then return scope.autogensyms[base] end
        local mangling = gensym(scope, base:sub(1, -2))
        scope.autogensyms[base] = mangling
        return mangling
    end

    -- Check if a binding is valid
    local function checkBindingValid(symbol, scope, ast)
        -- Check if symbol will be over shadowed by special
        local name = symbol[1]
        assertCompile(not scope.specials[name] and not scope.macros[name],
                      ("local %s was overshadowed by a special form or macro")
                          :format(name), ast)
        assertCompile(not utils.isQuoted(symbol),
                      ("macro tried to bind %s without gensym"):format(name), symbol)

    end

    -- Declare a local symbol
    local function declareLocal(symbol, meta, scope, ast, tempManglings)
        checkBindingValid(symbol, scope, ast)
        local name = symbol[1]
        assertCompile(not utils.isMultiSym(name),
                      "unexpected multi symbol " .. name, ast)
        local mangling = localMangling(name, scope, ast, tempManglings)
        scope.symmeta[name] = meta
        return mangling
    end

    -- Convert symbol to Lua code. Will only work for local symbols
    -- if they have already been declared via declareLocal
    local function symbolToExpression(symbol, scope, isReference)
        local name = symbol[1]
        local multiSymParts = utils.isMultiSym(name)
        if scope.hashfn then
           if name == '$' then name = '$1' end
           if multiSymParts then
              if multiSymParts[1] == "$" then
                 multiSymParts[1] = "$1"
                 name = table.concat(multiSymParts, ".")
              end
           end
        end
        local parts = multiSymParts or {name}
        local etype = (#parts > 1) and "expression" or "sym"
        local isLocal = scope.manglings[parts[1]]
        if isLocal and scope.symmeta[parts[1]] then scope.symmeta[parts[1]].used = true end
        -- if it's a reference and not a symbol which introduces a new binding
        -- then we need to check for allowed globals
        assertCompile(not isReference or isLocal or globalAllowed(parts[1]),
                      'unknown global in strict mode: ' .. parts[1], symbol)
        if not isLocal then
            utils.root.scope.refedglobals[parts[1]] = true
        end
        return utils.expr(combineParts(parts, scope), etype)
    end


    -- Emit Lua code
    local function emit(chunk, out, ast)
        if type(out) == 'table' then
            table.insert(chunk, out)
        else
            table.insert(chunk, {leaf = out, ast = ast})
        end
    end

    -- Do some peephole optimization.
    local function peephole(chunk)
        if chunk.leaf then return chunk end
        -- Optimize do ... end in some cases.
        if #chunk >= 3 and
            chunk[#chunk - 2].leaf == 'do' and
            not chunk[#chunk - 1].leaf and
            chunk[#chunk].leaf == 'end' then
            local kid = peephole(chunk[#chunk - 1])
            local newChunk = {ast = chunk.ast}
            for i = 1, #chunk - 3 do table.insert(newChunk, peephole(chunk[i])) end
            for i = 1, #kid do table.insert(newChunk, kid[i]) end
            return newChunk
        end
        -- Recurse
        return utils.map(chunk, peephole)
    end

    -- correlate line numbers in input with line numbers in output
    local function flattenChunkCorrelated(mainChunk)
        local function flatten(chunk, out, lastLine, file)
            if chunk.leaf then
                out[lastLine] = (out[lastLine] or "") .. " " .. chunk.leaf
            else
                for _, subchunk in ipairs(chunk) do
                    -- Ignore empty chunks
                    if subchunk.leaf or #subchunk > 0 then
                        -- don't increase line unless it's from the same file
                        local source = utils.astSource(subchunk.ast)
                        if file == source.file then
                            lastLine = math.max(lastLine, source.line or 0)
                        end
                        lastLine = flatten(subchunk, out, lastLine, file)
                    end
                end
            end
            return lastLine
        end
        local out = {}
        local last = flatten(mainChunk, out, 1, mainChunk.file)
        for i = 1, last do
            if out[i] == nil then out[i] = "" end
        end
        return table.concat(out, "\n")
    end

    -- Flatten a tree of indented Lua source code lines.
    -- Tab is what is used to indent a block.
    local function flattenChunk(sm, chunk, tab, depth)
        if type(tab) == 'boolean' then tab = tab and '  ' or '' end
        if chunk.leaf then
            local code = chunk.leaf
            local info = chunk.ast
            -- Just do line info for now to save memory
            if sm then sm[#sm + 1] = info and info.line or -1 end
            return code
        else
            local parts = utils.map(chunk, function(c)
                if c.leaf or #c > 0 then -- Ignore empty chunks
                    local sub = flattenChunk(sm, c, tab, depth + 1)
                    if depth > 0 then sub = tab .. sub:gsub('\n', '\n' .. tab) end
                    return sub
                end
            end)
            return table.concat(parts, '\n')
        end
    end

    -- Some global state for all fennel sourcemaps. For the time being,
    -- this seems the easiest way to store the source maps.
    -- Sourcemaps are stored with source being mapped as the key, prepended
    -- with '@' if it is a filename (like debug.getinfo returns for source).
    -- The value is an array of mappings for each line.
    local fennelSourcemap = {}
    -- TODO: loading, unloading, and saving sourcemaps?

    local function makeShortSrc(source)
        source = source:gsub('\n', ' ')
        if #source <= 49 then
            return '[fennel "' .. source .. '"]'
        else
            return '[fennel "' .. source:sub(1, 46) .. '..."]'
        end
    end

    -- Return Lua source and source map table
    local function flatten(chunk, options)
        chunk = peephole(chunk)
        if(options.correlate) then
            return flattenChunkCorrelated(chunk), {}
        else
            local sm = {}
            local ret = flattenChunk(sm, chunk, options.indent, 0)
            if sm then
                local key, short_src
                if options.filename then
                    short_src = options.filename
                    key = '@' .. short_src
                else
                    key = ret
                    short_src = makeShortSrc(options.source or ret)
                end
                sm.short_src = short_src
                sm.key = key
                fennelSourcemap[key] = sm
            end
            return ret, sm
        end
    end

    -- module-wide state for metadata
    -- create metadata table with weakly-referenced keys
    local function makeMetadata()
        return setmetatable({}, {
            __mode = 'k',
            __index = {
                get = function(self, tgt, key)
                    if self[tgt] then return self[tgt][key] end
                end,
                set = function(self, tgt, key, value)
                    self[tgt] = self[tgt] or {}
                    self[tgt][key] = value
                    return tgt
                end,
                setall = function(self, tgt, ...)
                    local kvLen, kvs = select('#', ...), {...}
                    if kvLen % 2 ~= 0 then
                        error('metadata:setall() expected even number of k/v pairs')
                    end
                    self[tgt] = self[tgt] or {}
                    for i = 1, kvLen, 2 do self[tgt][kvs[i]] = kvs[i + 1] end
                    return tgt
                end,
            }})
    end

    -- Convert expressions to Lua string
    local function exprs1(exprs)
        return table.concat(utils.map(exprs, 1), ', ')
    end

    -- Compile side effects for a chunk
    local function keepSideEffects(exprs, chunk, start, ast)
        start = start or 1
        for j = start, #exprs do
            local se = exprs[j]
            -- Avoid the rogue 'nil' expression (nil is usually a literal,
            -- but becomes an expression if a special form
            -- returns 'nil'.)
            if se.type == 'expression' and se[1] ~= 'nil' then
                emit(chunk, ('do local _ = %s end'):format(tostring(se)), ast)
            elseif se.type == 'statement' then
                local code = tostring(se)
                emit(chunk, code:byte() == 40 and ("do end " .. code) or code , ast)
            end
        end
    end

    -- Does some common handling of returns and register
    -- targets for special forms. Also ensures a list expression
    -- has an acceptable number of expressions if opts contains the
    -- "nval" option.
    local function handleCompileOpts(exprs, parent, opts, ast)
        if opts.nval then
            local n = opts.nval
            if n ~= #exprs then
                local len = #exprs
                if len > n then
                    -- Drop extra
                    keepSideEffects(exprs, parent, n + 1, ast)
                    for i = n + 1, len do
                        exprs[i] = nil
                    end
                else
                    -- Pad with nils
                    for i = #exprs + 1, n do
                        exprs[i] = utils.expr('nil', 'literal')
                    end
                end
            end
        end
        if opts.tail then
            emit(parent, ('return %s'):format(exprs1(exprs)), ast)
        end
        if opts.target then
            local result = exprs1(exprs)
            if result == '' then result = 'nil' end
            emit(parent, ('%s = %s'):format(opts.target, result), ast)
        end
        if opts.tail or opts.target then
            -- Prevent statements and expression from being used twice if they
            -- have side-effects. Since if the target or tail options are set,
            -- the expressions are already emitted, we should not return them. This
            -- is fine, as when these options are set, the caller doesn't need the result
            -- anyways.
            exprs = {}
        end
        return exprs
    end

    local function macroexpand(ast, scope, once)
        if not utils.isList(ast) then return ast end -- bail early if not a list form
        local multiSymParts = utils.isMultiSym(ast[1])
        local macro = utils.isSym(ast[1]) and scope.macros[utils.deref(ast[1])]
        if not macro and multiSymParts then
            local inMacroModule
            macro = scope.macros
            for i = 1, #multiSymParts do
                macro = utils.isTable(macro) and macro[multiSymParts[i]]
                if macro then inMacroModule = true end
            end
            assertCompile(not inMacroModule or type(macro) == 'function',
                'macro not found in imported macro module', ast)
        end
        if not macro then return ast end
        local oldScope = scopes.macro
        scopes.macro = scope
        local ok, transformed = pcall(macro, unpack(ast, 2))
        scopes.macro = oldScope
        assertCompile(ok, transformed, ast)
        if once or not transformed then return transformed end -- macroexpand-1
        return macroexpand(transformed, scope)
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
    --      Could be one variable, 'a', or a list, like 'a, b, _0_'.
    --   'tail' - boolean indicating tail position if set. If set, form will generate a return
    --   instruction.
    --   'nval' - The number of values to compile to if it is known to be a fixed value.

    -- In Lua, an expression can evaluate to 0 or more values via multiple
    -- returns. In many cases, Lua will drop extra values and convert a 0 value
    -- expression to nil. In other cases, Lua will use all of the values in an
    -- expression, such as in the last argument of a function call. Nval is an
    -- option passed to compile1 to say that the resulting expression should have
    -- at least n values. It lets us generate better code, because if we know we
    -- are only going to use 1 or 2 values from an expression, we can create 1 or 2
    -- locals to store intermediate results rather than turn the expression into a
    -- closure that is called immediately, which we have to do if we don't know.

    local function compile1(ast, scope, parent, opts)
        opts = opts or {}
        local exprs = {}
        -- expand any top-level macros before parsing and emitting Lua
        ast = macroexpand(ast, scope)
        -- Compile the form
        if utils.isList(ast) then -- Function call or special form
            assertCompile(#ast > 0, "expected a function, macro, or special to call", ast)
            -- Test for special form
            local len, first = #ast, ast[1]
            local multiSymParts = utils.isMultiSym(first)
            local special = utils.isSym(first) and scope.specials[utils.deref(first)]
            if special then -- Special form
                exprs = special(ast, scope, parent, opts) or utils.expr('nil', 'literal')
                -- Be very accepting of strings or expression
                -- as well as lists or expressions
                if type(exprs) == 'string' then exprs = utils.expr(exprs, 'expression') end
                if utils.isExpr(exprs) then exprs = {exprs} end
                -- Unless the special form explicitly handles the target, tail, and
                -- nval properties, (indicated via the 'returned' flag), handle
                -- these options.
                if not exprs.returned then
                    exprs = handleCompileOpts(exprs, parent, opts, ast)
                elseif opts.tail or opts.target then
                    exprs = {}
                end
                exprs.returned = true
                return exprs
            elseif multiSymParts and multiSymParts.multiSymMethodCall then
                local tableWithMethod = table.concat({
                        unpack(multiSymParts, 1, #multiSymParts - 1)
                                                     }, '.')
                local methodToCall = multiSymParts[#multiSymParts]
                local newAST = utils.list(utils.sym(':', scope), utils.sym(tableWithMethod, scope),
                                          methodToCall)
                for i = 2, len do
                    newAST[#newAST + 1] = ast[i]
                end
                local compiled = compile1(newAST, scope, parent, opts)
                exprs = compiled
            else -- Function call
                local fargs = {}
                local fcallee = compile1(ast[1], scope, parent, {
                    nval = 1
                })[1]
                assertCompile(fcallee.type ~= 'literal',
                              'cannot call literal value ' .. tostring(ast[1]), ast)
                fcallee = tostring(fcallee)
                for i = 2, len do
                    local subexprs = compile1(ast[i], scope, parent, {
                        nval = i ~= len and 1 or nil
                    })
                    fargs[#fargs + 1] = subexprs[1] or utils.expr('nil', 'literal')
                    if i == len then
                        -- Add sub expressions to function args
                        for j = 2, #subexprs do
                            fargs[#fargs + 1] = subexprs[j]
                        end
                    else
                        -- Emit sub expression only for side effects
                        keepSideEffects(subexprs, parent, 2, ast[i])
                    end
                end
                local call = ('%s(%s)'):format(tostring(fcallee), exprs1(fargs))
                exprs = handleCompileOpts({utils.expr(call, 'statement')}, parent, opts, ast)
            end
        elseif utils.isVarg(ast) then
            assertCompile(scope.vararg, "unexpected vararg", ast)
            exprs = handleCompileOpts({utils.expr('...', 'varg')}, parent, opts, ast)
        elseif utils.isSym(ast) then
            local e
            local multiSymParts = utils.isMultiSym(ast)
            assertCompile(not (multiSymParts and multiSymParts.multiSymMethodCall),
                          "multisym method calls may only be in call position", ast)
            -- Handle nil as special symbol - it resolves to the nil literal rather than
            -- being unmangled. Alternatively, we could remove it from the lua keywords table.
            if ast[1] == 'nil' then
                e = utils.expr('nil', 'literal')
            else
                e = symbolToExpression(ast, scope, true)
            end
            exprs = handleCompileOpts({e}, parent, opts, ast)
        elseif type(ast) == 'nil' or type(ast) == 'boolean' then
            exprs = handleCompileOpts({utils.expr(tostring(ast), 'literal')}, parent, opts)
        elseif type(ast) == 'number' then
            local n = ('%.17g'):format(ast)
            exprs = handleCompileOpts({utils.expr(n, 'literal')}, parent, opts)
        elseif type(ast) == 'string' then
            local s = serializeString(ast)
            exprs = handleCompileOpts({utils.expr(s, 'literal')}, parent, opts)
        elseif type(ast) == 'table' then
            local buffer = {}
            for i = 1, #ast do -- Write numeric keyed values.
                local nval = i ~= #ast and 1
                buffer[#buffer + 1] = exprs1(compile1(ast[i], scope,
                                                      parent, {nval = nval}))
            end
            local function writeOtherValues(k)
                if type(k) ~= 'number' or math.floor(k) ~= k or k < 1 or k > #ast then
                    if type(k) == 'string' and utils.isValidLuaIdentifier(k) then
                        return {k, k}
                    else
                        local kstr = '[' .. tostring(compile1(k, scope, parent,
                                                              {nval = 1})[1]) .. ']'
                        return { kstr, k }
                    end
                end
            end
            local keys = utils.kvmap(ast, writeOtherValues)
            table.sort(keys, function (a, b) return a[1] < b[1] end)
            utils.map(keys, function(k)
                    local v = tostring(compile1(ast[k[2]], scope, parent, {nval = 1})[1])
                    return ('%s = %s'):format(k[1], v) end,
                buffer)
            local tbl = '{' .. table.concat(buffer, ', ') ..'}'
            exprs = handleCompileOpts({utils.expr(tbl, 'expression')}, parent, opts, ast)
        else
            assertCompile(false, 'could not compile value of type ' .. type(ast), ast)
        end
        exprs.returned = true
        return exprs
    end

    -- Implements destructuring for forms like let, bindings, etc.
    -- Takes a number of options to control behavior.
    -- var: Whether or not to mark symbols as mutable
    -- declaration: begin each assignment with 'local' in output
    -- nomulti: disallow multisyms in the destructuring. Used for (local) and (global).
    -- noundef: Don't set undefined bindings. (set)
    -- forceglobal: Don't allow local bindings
    local function destructure(to, from, ast, scope, parent, opts)
        opts = opts or {}
        local isvar = opts.isvar
        local declaration = opts.declaration
        local nomulti = opts.nomulti
        local noundef = opts.noundef
        local forceglobal = opts.forceglobal
        local forceset = opts.forceset
        local setter = declaration and "local %s = %s" or "%s = %s"

        local newManglings = {}

        -- Get Lua source for symbol, and check for errors
        local function getname(symbol, up1)
            local raw = symbol[1]
            assertCompile(not (nomulti and utils.isMultiSym(raw)),
                'unexpected multi symbol ' .. raw, up1)
            if declaration then
                return declareLocal(symbol, {var = isvar}, scope,
                                    symbol, newManglings)
            else
                local parts = utils.isMultiSym(raw) or {raw}
                local meta = scope.symmeta[parts[1]]
                if #parts == 1 and not forceset then
                    assertCompile(not(forceglobal and meta),
                        ("global %s conflicts with local"):format(tostring(symbol)), symbol)
                    assertCompile(not (meta and not meta.var),
                        'expected var ' .. raw, symbol)
                    assertCompile(meta or not noundef,
                        'expected local ' .. parts[1], symbol)
                end
                if forceglobal then
                    assertCompile(not scope.symmeta[scope.unmanglings[raw]],
                                  "global " .. raw .. " conflicts with local", symbol)
                    scope.manglings[raw] = globalMangling(raw)
                    scope.unmanglings[globalMangling(raw)] = raw
                    if allowedGlobals then
                        table.insert(allowedGlobals, raw)
                    end
                end

                return symbolToExpression(symbol, scope)[1]
            end
        end

        -- Compile the outer most form. We can generate better Lua in this case.
        local function compileTopTarget(lvalues)
            -- Calculate initial rvalue
            local inits = utils.map(lvalues, function(x)
                                  return scope.manglings[x] and x or 'nil' end)
            local init = table.concat(inits, ', ')
            local lvalue = table.concat(lvalues, ', ')

            local plen, plast = #parent, parent[#parent]
            local ret = compile1(from, scope, parent, {target = lvalue})
            if declaration then
                -- A single leaf emitted at the end of the parent chunk means
                -- a simple assignment a = x was emitted, and we can just
                -- splice "local " onto the front of it. However, we can't
                -- just check based on plen, because some forms (such as
                -- include) insert new chunks at the top of the parent chunk
                -- rather than just at the end; this loop checks for this
                -- occurrence and updates plen to be the index of the last
                -- thing in the parent before compiling the new value.
                for pi = plen, #parent do
                    if parent[pi] == plast then plen = pi end
                end
                if #parent == plen + 1 and parent[#parent].leaf then
                    parent[#parent].leaf = 'local ' .. parent[#parent].leaf
                else
                    table.insert(parent, plen + 1,
                                 { leaf = 'local ' .. lvalue .. ' = ' .. init,
                                   ast = ast})
                end
            end
            return ret
        end

        -- Recursive auxiliary function
        local function destructure1(left, rightexprs, up1, top)
            if utils.isSym(left) and left[1] ~= "nil" then
                checkBindingValid(left, scope, left)
                local lname = getname(left, up1)
                if top then
                    compileTopTarget({lname})
                else
                    emit(parent, setter:format(lname, exprs1(rightexprs)), left)
                end
            elseif utils.isTable(left) then -- table destructuring
                if top then rightexprs = compile1(from, scope, parent) end
                local s = gensym(scope)
                local right = exprs1(rightexprs)
                if right == '' then right = 'nil' end
                emit(parent, ("local %s = %s"):format(s, right), left)
                for k, v in utils.stablepairs(left) do
                    if utils.isSym(left[k]) and left[k][1] == "&" then
                        assertCompile(type(k) == "number" and not left[k+2],
                            "expected rest argument before last parameter", left)
                        local subexpr = utils.expr(('{(table.unpack or unpack)(%s, %s)}')
                                :format(s, k), 'expression')
                        destructure1(left[k+1], {subexpr}, left)
                        return
                    elseif (utils.isSym(k) and (tostring(k) == "&as")) then
                        destructure1(v, {utils.expr(tostring(s))}, left)
                    elseif (utils.isSequence(left) and (tostring(v) == "&as")) then
                        destructure1(left[k+1], {utils.expr(tostring(s))}, left)
                        return
                    else
                        if utils.isSym(k) and tostring(k) == ":" and utils.isSym(v) then
                            k = tostring(v)
                        end
                        if type(k) ~= "number" then k = serializeString(tostring(k)) end
                        local subexpr = utils.expr(('%s[%s]'):format(s, k), 'expression')
                        destructure1(v, {subexpr}, left)
                    end
                end
            elseif utils.isList(left) then -- values destructuring
                local leftNames, tables = {}, {}
                for i, name in ipairs(left) do
                    local symname
                    if utils.isSym(name) then -- binding directly to a name
                        symname = getname(name, up1)
                    else -- further destructuring of tables inside values
                        symname = gensym(scope)
                        tables[i] = {name, utils.expr(symname, 'sym')}
                    end
                    table.insert(leftNames, symname)
                end
                if top then
                    compileTopTarget(leftNames)
                else
                    local lvalue = table.concat(leftNames, ', ')
                    emit(parent, setter:format(lvalue, exprs1(rightexprs)), left)
                end
                for _, pair in utils.stablepairs(tables) do -- recurse if left-side tables found
                    destructure1(pair[1], {pair[2]}, left)
                end
            else
                assertCompile(false, ("unable to bind %s %s"):
                                  format(type(left), tostring(left)),
                              type(up1[2]) == "table" and up1[2] or up1)
            end
            if top then return {returned = true} end
        end

        local ret = destructure1(to, nil, ast, true)
        applyManglings(scope, newManglings, ast)
        return ret
    end

    local function requireInclude(ast, scope, parent, opts)
        opts.fallback = function(e)
            return utils.expr(('require(%s)'):format(tostring(e)), 'statement')
        end
        return scopes.global.specials['include'](ast, scope, parent, opts)
    end

    local function compileStream(strm, options)
        local opts = utils.copy(options)
        local oldGlobals = allowedGlobals
        utils.root:setReset()
        allowedGlobals = opts.allowedGlobals
        if opts.indent == nil then opts.indent = '  ' end
        if opts.scope == "_COMPILER" then opts.scope = scopes.compiler end
        local scope = opts.scope or makeScope(scopes.global)
        if opts.requireAsInclude then scope.specials.require = requireInclude end
        local vals = {}
        for ok, val in parser.parser(strm, opts.filename, opts) do
            if not ok then break end
            vals[#vals + 1] = val
        end
        local chunk = {}
        utils.root.chunk, utils.root.scope, utils.root.options = chunk, scope, opts
        for i = 1, #vals do
            local exprs = compile1(vals[i], scope, chunk, {
                tail = i == #vals,
                nval = i < #vals and 0 or nil
            })
            keepSideEffects(exprs, chunk, nil, vals[i])
        end
        allowedGlobals = oldGlobals
        utils.root.reset()
        return flatten(chunk, opts)
    end

    local function compileString(str, options)
        options = options or {}
        local oldSource = options.source
        options.source = str -- used by fennelfriend
        local ast = compileStream(parser.stringStream(str), options)
        options.source = oldSource
        return ast
    end

    local function compile(ast, options)
        local opts = utils.copy(options)
        local oldGlobals = allowedGlobals
        utils.root:setReset()
        allowedGlobals = opts.allowedGlobals
        if opts.indent == nil then opts.indent = '  ' end
        local chunk = {}
        local scope = opts.scope or makeScope(scopes.global)
        utils.root.chunk, utils.root.scope, utils.root.options = chunk, scope, opts
        if opts.requireAsInclude then scope.specials.require = requireInclude end
        local exprs = compile1(ast, scope, chunk, {tail = true})
        keepSideEffects(exprs, chunk, nil, ast)
        allowedGlobals = oldGlobals
        utils.root.reset()
        return flatten(chunk, opts)
    end

    -- A custom traceback function for Fennel that looks similar to
    -- the Lua's debug.traceback.
    -- Use with xpcall to produce fennel specific stacktraces.
    local function traceback(msg, start)
        local level = start or 2 -- Can be used to skip some frames
        local lines = {}
        if msg then
            if msg:find("^Compile error") or msg:find("^Parse error") then
                -- End users don't want to see compiler stack traces, but when
                -- you're hacking on the compiler, export FENNEL_DEBUG=trace
                if not utils.debugOn("trace") then return msg end
                table.insert(lines, msg)
            else
                local newmsg = msg:gsub('^[^:]*:%d+:%s+', 'runtime error: ')
                table.insert(lines, newmsg)
            end
        end
        table.insert(lines, 'stack traceback:')
        while true do
            local info = debug.getinfo(level, "Sln")
            if not info then break end
            local line
            if info.what == "C" then
                if info.name then
                    line = ('  [C]: in function \'%s\''):format(info.name)
                else
                    line = '  [C]: in ?'
                end
            else
                local remap = fennelSourcemap[info.source]
                if remap and remap[info.currentline] then
                    -- And some global info
                    info.short_src = remap.short_src
                    local mapping = remap[info.currentline]
                    -- Overwrite info with values from the mapping (mapping is now
                    -- just integer, but may eventually be a table)
                    info.currentline = mapping
                end
                if info.what == 'Lua' then
                    local n = info.name and ("'" .. info.name .. "'") or '?'
                    line = ('  %s:%d: in function %s'):format(info.short_src, info.currentline, n)
                elseif info.short_src == '(tail call)' then
                    line = '  (tail call)'
                else
                    line = ('  %s:%d: in main chunk'):format(info.short_src, info.currentline)
                end
            end
            table.insert(lines, line)
            level = level + 1
        end
        return table.concat(lines, '\n')
    end

    -- make a transformer for key / value table pairs, preserving all numeric keys
    local function entryTransform(fk,fv)
        return function(k, v)
            if type(k) == 'number' then
                return k,fv(v)
            else
                return fk(k),fv(v)
            end
        end
    end

    -- consume everything return nothing
    local function no() end

    local function mixedConcat(t, joiner)
        local ret = ""
        local s = ""
        local seen = {}
        for k,v in ipairs(t) do
            table.insert(seen, k)
            ret = ret .. s .. v
            s = joiner
        end
        for k,v in utils.stablepairs(t) do
            if not(seen[k]) then
                ret = ret .. s .. '[' .. k .. ']' .. '=' .. v
                s = joiner
            end
        end
        return ret
    end

    -- expand a quoted form into a data literal, evaluating unquote
    local function doQuote (form, scope, parent, runtime)
        local q = function (x) return doQuote(x, scope, parent, runtime) end
        -- vararg
        if utils.isVarg(form) then
            assertCompile(not runtime, "quoted ... may only be used at compile time", form)
            return "_VARARG"
        -- symbol
        elseif utils.isSym(form) then
            assertCompile(not runtime, "symbols may only be used at compile time", form)
            -- We should be able to use "%q" for this but Lua 5.1 throws an error
            -- when you try to format nil, because it's extremely bad.
            local filename = form.filename and ('%q'):format(form.filename) or "nil"
            if utils.deref(form):find("#$") or utils.deref(form):find("#[:.]") then -- autogensym
                return ("sym('%s', nil, {filename=%s, line=%s})"):
                    format(autogensym(utils.deref(form), scope), filename, form.line or "nil")
            else -- prevent non-gensymmed symbols from being bound as an identifier
                return ("sym('%s', nil, {quoted=true, filename=%s, line=%s})"):
                    format(utils.deref(form), filename, form.line or "nil")
            end
        -- unquote
        elseif(utils.isList(form) and utils.isSym(form[1]) and
               (utils.deref(form[1]) == 'unquote')) then
            local payload = form[2]
            local res = unpack(compile1(payload, scope, parent))
            return res[1]
        -- list
        elseif utils.isList(form) then
            assertCompile(not runtime, "lists may only be used at compile time", form)
            local mapped = utils.kvmap(form, entryTransform(no, q))
            local filename = form.filename and ('%q'):format(form.filename) or "nil"
            -- Constructing a list and then adding file/line data to it triggers a
            -- bug where it changes the value of # for lists that contain nils in
            -- them; constructing the list all in one go with the source data and
            -- contents is how we construct lists in the parser and works around
            -- this problem; allowing # to work in a way that lets us see the nils.
            return ("setmetatable({filename=%s, line=%s, bytestart=%s, %s}" ..
                        ", getmetatable(list()))")
                :format(filename, form.line or "nil", form.bytestart or "nil",
                        mixedConcat(mapped, ", "))
        -- table
        elseif type(form) == 'table' then
            local mapped = utils.kvmap(form, entryTransform(q, q))
            local source = getmetatable(form)
            local filename = source.filename and ('%q'):format(source.filename) or "nil"
            return ("setmetatable({%s}, {filename=%s, line=%s})"):
                format(mixedConcat(mapped, ", "), filename, source and source.line or "nil")
        -- string
        elseif type(form) == 'string' then
            return serializeString(form)
        else
            return tostring(form)
        end
    end
    return {
        -- compiling functions:
        compileString=compileString, compileStream=compileStream,
        compile=compile, compile1=compile1, emit=emit, destructure=destructure,
        requireInclude=requireInclude,

        -- AST functions:
        gensym=gensym, autogensym=autogensym, doQuote=doQuote,
        macroexpand=macroexpand, globalUnmangling=globalUnmangling,
        applyManglings=applyManglings, globalMangling=globalMangling,

        -- scope functions:
        makeScope=makeScope, keepSideEffects=keepSideEffects,
        declareLocal=declareLocal, symbolToExpression=symbolToExpression,

        -- general functions:
        assert=assertCompile, metadata=makeMetadata(), traceback=traceback,
        scopes=scopes,
    }
end)()

--
-- Specials and macros
--

local specials = (function()
    local SPECIALS = compiler.scopes.global.specials

    -- Convert a fennel environment table to a Lua environment table.
    -- This means automatically unmangling globals when getting a value,
    -- and mangling values when setting a value. This means the original env
    -- will see its values updated as expected, regardless of mangling rules.
    local function wrapEnv(env)
        return setmetatable({}, {
            __index = function(_, key)
                if type(key) == 'string' then
                    key = compiler.globalUnmangling(key)
                end
                return env[key]
            end,
            __newindex = function(_, key, value)
                if type(key) == 'string' then
                    key = compiler.globalMangling(key)
                end
                env[key] = value
            end,
            -- checking the __pairs metamethod won't work automatically in Lua 5.1
            -- sadly, but it's important for 5.2+ and can be done manually in 5.1
            __pairs = function()
                local function putenv(k, v)
                    return type(k) == 'string' and compiler.globalUnmangling(k) or k, v
                end
                local pt = utils.kvmap(env, putenv)
                return next, pt, nil
            end,
        })
    end

    local function currentGlobalNames(env)
        return utils.kvmap(env or _G, compiler.globalUnmangling)
    end

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

    -- Return a docstring
    local doc = function(tgt, name)
        if(not tgt) then return name .. " not found" end
        local docstring = (compiler.metadata:get(tgt, 'fnl/docstring') or
                               '#<undocumented>'):gsub('\n$', ''):gsub('\n', '\n  ')
        if type(tgt) == "function" then
            local arglist = table.concat(compiler.metadata:get(tgt, 'fnl/arglist') or
                                             {'#<unknown-arguments>'}, ' ')
            return string.format("(%s%s%s)\n  %s", name, #arglist > 0 and ' ' or '',
                                 arglist, docstring)
        else
            return string.format("%s\n  %s", name, docstring)
        end
    end

    local function docSpecial(name, arglist, docstring)
        compiler.metadata[SPECIALS[name]] =
            { ["fnl/docstring"] = docstring, ["fnl/arglist"] = arglist }
    end

    -- Compile a list of forms for side effects
    local function compileDo(ast, scope, parent, start)
        start = start or 2
        local len = #ast
        local subScope = compiler.makeScope(scope)
        for i = start, len do
            compiler.compile1(ast[i], subScope, parent, {
                nval = 0
            })
        end
    end

    -- Implements a do statement, starting at the 'start' element. By default, start is 2.
    local function doImpl(ast, scope, parent, opts, start, chunk, subScope, preSyms)
        start = start or 2
        subScope = subScope or compiler.makeScope(scope)
        chunk = chunk or {}
        local len = #ast
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
                    local s = preSyms and preSyms[i] or compiler.gensym(scope)
                    syms[i] = s
                    retexprs[i] = utils.expr(s, 'sym')
                end
                outerTarget = table.concat(syms, ', ')
                compiler.emit(parent, ('local %s'):format(outerTarget), ast)
                compiler.emit(parent, 'do', ast)
            else
                -- We will use an IIFE for the do
                local fname = compiler.gensym(scope)
                local fargs = scope.vararg and '...' or ''
                compiler.emit(parent, ('local function %s(%s)'):format(fname, fargs), ast)
                retexprs = utils.expr(fname .. '(' .. fargs .. ')', 'statement')
                outerTail = true
                outerTarget = nil
            end
        else
            compiler.emit(parent, 'do', ast)
        end
        -- Compile the body
        if start > len then
            -- In the unlikely case we do a do with no arguments.
            compiler.compile1(nil, subScope, chunk, {
                tail = outerTail,
                target = outerTarget
            })
            -- There will be no side effects
        else
            for i = start, len do
                local subopts = {
                    nval = i ~= len and 0 or opts.nval,
                    tail = i == len and outerTail or nil,
                    target = i == len and outerTarget or nil
                }
                utils.propagateOptions(opts, subopts)
                local subexprs = compiler.compile1(ast[i], subScope, chunk, subopts)
                if i ~= len then
                    compiler.keepSideEffects(subexprs, parent, nil, ast[i])
                end
            end
        end
        compiler.emit(parent, chunk, ast)
        compiler.emit(parent, 'end', ast)
        return retexprs
    end

    SPECIALS["do"] = doImpl
    docSpecial("do", {"..."}, "Evaluate multiple forms; return last value.")

    -- Unlike most expressions and specials, 'values' resolves with multiple
    -- values, one for each argument, allowing multiple return values. The last
    -- expression can return multiple arguments as well, allowing for more than
    -- the number of expected arguments.
    SPECIALS["values"] = function(ast, scope, parent)
        local len = #ast
        local exprs = {}
        for i = 2, len do
            local subexprs = compiler.compile1(ast[i], scope, parent, {
                nval = (i ~= len) and 1
            })
            exprs[#exprs + 1] = subexprs[1]
            if i == len then
                for j = 2, #subexprs do
                    exprs[#exprs + 1] = subexprs[j]
                end
            end
        end
        return exprs
    end
    docSpecial("values", {"..."},
               "Return multiple values from a function.  Must be in tail position.")

    -- The fn special declares a function. Syntax is similar to other lisps;
    -- (fn optional-name [arg ...] (body))
    -- Further decoration such as docstrings, meta info, and multibody functions a possibility.
    SPECIALS["fn"] = function(ast, scope, parent)
        local fScope = compiler.makeScope(scope)
        local fChunk = {}
        local index = 2
        local fnName = utils.isSym(ast[index])
        local isLocalFn
        local docstring
        fScope.vararg = false
        local multi = fnName and utils.isMultiSym(fnName[1])
        compiler.assert(not multi or not multi.multiSymMethodCall,
                      "unexpected multi symbol " .. tostring(fnName), ast[index])
        if fnName and fnName[1] ~= 'nil' then
            isLocalFn = not multi
            if isLocalFn then
                fnName = compiler.declareLocal(fnName, {}, scope, ast)
            else
                fnName = compiler.symbolToExpression(fnName, scope)[1]
            end
            index = index + 1
        else
            isLocalFn = true
            fnName = compiler.gensym(scope)
        end
        local argList = compiler.assert(utils.isTable(ast[index]),
                                      "expected parameters",
                                      type(ast[index]) == "table" and ast[index] or ast)
        local function getArgName(name)
            if utils.isVarg(name) then
                compiler.assert(name == argList[#argList],
                                "expected vararg as last parameter", ast[2])
                fScope.vararg = true
                return "..."
            elseif(utils.isSym(name) and utils.deref(name) ~= "nil"
                   and not utils.isMultiSym(utils.deref(name))) then
                return compiler.declareLocal(name, {}, fScope, ast)
            elseif utils.isTable(name) then
                local raw = utils.sym(compiler.gensym(scope))
                local declared = compiler.declareLocal(raw, {}, fScope, ast)
                compiler.destructure(name, raw, ast, fScope, fChunk,
                                     { declaration = true, nomulti = true })
                return declared
            else
                compiler.assert(false, ("expected symbol for function parameter: %s"):
                                  format(tostring(name)), ast[2])
            end
        end
        local argNameList = utils.map(argList, getArgName)
        if type(ast[index + 1]) == 'string' and index + 1 < #ast then
            index = index + 1
            docstring = ast[index]
        end
        for i = index + 1, #ast do
            compiler.compile1(ast[i], fScope, fChunk, {
                tail = i == #ast,
                nval = i ~= #ast and 0 or nil,
            })
        end
        if isLocalFn then
            compiler.emit(parent, ('local function %s(%s)')
                     :format(fnName, table.concat(argNameList, ', ')), ast)
        else
            compiler.emit(parent, ('%s = function(%s)')
                     :format(fnName, table.concat(argNameList, ', ')), ast)
        end

        compiler.emit(parent, fChunk, ast)
        compiler.emit(parent, 'end', ast)

        if utils.root.options.useMetadata then
            local args = utils.map(argList, function(v)
                -- TODO: show destructured args properly instead of replacing
                return utils.isTable(v) and '"#<table>"' or string.format('"%s"', tostring(v))
            end)

            local metaFields = {
                '"fnl/arglist"', '{' .. table.concat(args, ', ') .. '}',
            }
            if docstring then
                table.insert(metaFields, '"fnl/docstring"')
                table.insert(metaFields, '"' .. docstring:gsub('%s+$', '')
                                 :gsub('\\', '\\\\'):gsub('\n', '\\n')
                                 :gsub('"', '\\"') .. '"')
            end
            if(type(utils.root.options.useMetadata) == "string") then
               compiler.emit(parent, string.format('%s:setall(%s, %s)',
                                                   utils.root.options.useMetadata, fnName,
                                                   table.concat(metaFields, ', ')))
            else
               local metaStr = ('require("%s").metadata'):
                  format(utils.root.options.moduleName or "fennel")
               compiler.emit(parent, string.format('pcall(function() %s:setall(%s, %s) end)',
                                                   metaStr, fnName, table.concat(metaFields, ', ')))
            end
        end

        return utils.expr(fnName, 'sym')
    end
    docSpecial("fn", {"name?", "args", "docstring?", "..."},
               "Function syntax. May optionally include a name and docstring."
                   .."\nIf a name is provided, the function will be bound in the current scope."
                   .."\nWhen called with the wrong number of args, excess args will be discarded"
                   .."\nand lacking args will be nil, use lambda for arity-checked functions.")

    -- (lua "print('hello!')") -> prints hello, evaluates to nil
    -- (lua "print 'hello!'" "10") -> prints hello, evaluates to the number 10
    -- (lua nil "{1,2,3}") -> Evaluates to a table literal
    SPECIALS['lua'] = function(ast, _, parent)
        compiler.assert(#ast == 2 or #ast == 3, "expected 1 or 2 arguments", ast)
        if ast[2] ~= nil then
            table.insert(parent, {leaf = tostring(ast[2]), ast = ast})
        end
        if #ast == 3 then
            return tostring(ast[3])
        end
    end

    SPECIALS['doc'] = function(ast, scope, parent)
        assert(utils.root.options.useMetadata, "can't look up doc with metadata disabled.")
        compiler.assert(#ast == 2, "expected one argument", ast)

        local target = utils.deref(ast[2])
        local specialOrMacro = scope.specials[target] or scope.macros[target]
        if specialOrMacro then
            return ("print([[%s]])"):format(doc(specialOrMacro, target))
        else
            local value = tostring(compiler.compile1(ast[2], scope, parent, {nval = 1})[1])
            -- need to require here since the metadata is stored in the module
            -- and we need to make sure we look it up in the same module it was
            -- declared from.
            return ("print(require('%s').doc(%s, '%s'))")
                :format(utils.root.options.moduleName or "fennel", value, tostring(ast[2]))
        end
    end
    docSpecial("doc", {"x"},
               "Print the docstring and arglist for a function, macro, or special form.")

    -- Table lookup
    SPECIALS["."] = function(ast, scope, parent)
        local len = #ast
        compiler.assert(len > 1, "expected table argument", ast)
        local lhs = compiler.compile1(ast[2], scope, parent, {nval = 1})
        if len == 2 then
            return tostring(lhs[1])
        else
            local indices = {}
            for i = 3, len do
                local index = ast[i]
                if type(index) == 'string' and utils.isValidLuaIdentifier(index) then
                    table.insert(indices, '.' .. index)
                else
                    index = compiler.compile1(index, scope, parent, {nval = 1})[1]
                    table.insert(indices, '[' .. tostring(index) .. ']')
                end
            end
            -- extra parens are needed for table literals
            if utils.isTable(ast[2]) then
                return '(' .. tostring(lhs[1]) .. ')' .. table.concat(indices)
            else
                return tostring(lhs[1]) .. table.concat(indices)
            end
        end
    end
    docSpecial(".", {"tbl", "key1", "..."},
               "Look up key1 in tbl table. If more args are provided, do a nested lookup.")

    SPECIALS["global"] = function(ast, scope, parent)
        compiler.assert(#ast == 3, "expected name and value", ast)
        compiler.destructure(ast[2], ast[3], ast, scope, parent, {
            nomulti = true,
            forceglobal = true
        })
    end
    docSpecial("global", {"name", "val"}, "Set name as a global with val.")

    SPECIALS["set"] = function(ast, scope, parent)
        compiler.assert(#ast == 3, "expected name and value", ast)
        compiler.destructure(ast[2], ast[3], ast, scope, parent, {
            noundef = true
        })
    end
    docSpecial("set", {"name", "val"},
               "Set a local variable to a new value. Only works on locals using var.")

    SPECIALS["set-forcibly!"] = function(ast, scope, parent)
        compiler.assert(#ast == 3, "expected name and value", ast)
        compiler.destructure(ast[2], ast[3], ast, scope, parent, {
            forceset = true
        })
    end

    SPECIALS["local"] = function(ast, scope, parent)
        compiler.assert(#ast == 3, "expected name and value", ast)
        compiler.destructure(ast[2], ast[3], ast, scope, parent, {
            declaration = true,
            nomulti = true
        })
    end
    docSpecial("local", {"name", "val"},
               "Introduce new top-level immutable local.")

    SPECIALS["var"] = function(ast, scope, parent)
        compiler.assert(#ast == 3, "expected name and value", ast)
        compiler.destructure(ast[2], ast[3], ast, scope, parent, {
                                 declaration = true, nomulti = true, isvar = true })
    end
    docSpecial("var", {"name", "val"},
               "Introduce new mutable local.")

    SPECIALS["let"] = function(ast, scope, parent, opts)
        local bindings = ast[2]
        compiler.assert(utils.isList(bindings) or utils.isTable(bindings),
                      "expected binding table", ast)
        compiler.assert(#bindings % 2 == 0,
                      "expected even number of name/value bindings", ast[2])
        compiler.assert(#ast >= 3, "expected body expression", ast[1])
        -- we have to gensym the binding for the let body's return value before
        -- compiling the binding vector, otherwise there's a possibility to conflict
        local preSyms = {}
        for _ = 1, (opts.nval or 0) do table.insert(preSyms, compiler.gensym(scope)) end
        local subScope = compiler.makeScope(scope)
        local subChunk = {}
        for i = 1, #bindings, 2 do
            compiler.destructure(bindings[i], bindings[i + 1], ast, subScope, subChunk, {
                                     declaration = true, nomulti = true })
        end
        return doImpl(ast, scope, parent, opts, 3, subChunk, subScope, preSyms)
    end
    docSpecial("let", {"[name1 val1 ... nameN valN]", "..."},
               "Introduces a new scope in which a given set of local bindings are used.")

    -- For setting items in a table
    SPECIALS["tset"] = function(ast, scope, parent)
        compiler.assert(#ast > 3, ("expected table, key, and value arguments"), ast)
        local root = compiler.compile1(ast[2], scope, parent, {nval = 1})[1]
        local keys = {}
        for i = 3, #ast - 1 do
            local key = compiler.compile1(ast[i], scope, parent, {nval = 1})[1]
            keys[#keys + 1] = tostring(key)
        end
        local value = compiler.compile1(ast[#ast], scope, parent, {nval = 1})[1]
        local rootstr = tostring(root)
        -- Prefix 'do end ' so parens are not ambiguous (grouping or function call?)
        local fmtstr = (rootstr:match("^{")) and "do end (%s)[%s] = %s" or "%s[%s] = %s"
        compiler.emit(parent, fmtstr:format(tostring(root),
                                   table.concat(keys, ']['),
                                   tostring(value)), ast)
    end
    docSpecial("tset", {"tbl", "key1", "...", "keyN", "val"},
               "Set the value of a table field. Can take additional keys to set"
            .. "nested values,\nbut all parents must contain an existing table.")

    -- The if special form behaves like the cond form in
    -- many languages
    SPECIALS["if"] = function(ast, scope, parent, opts)
        local doScope = compiler.makeScope(scope)
        local branches = {}
        local elseBranch = nil

        -- Calculate some external stuff. Optimizes for tail calls and what not
        local wrapper, innerTail, innerTarget, targetExprs
        if opts.tail or opts.target or opts.nval then
            if opts.nval and opts.nval ~= 0 and not opts.target then
                -- We need to create a target
                targetExprs = {}
                local accum = {}
                for i = 1, opts.nval do
                    local s = compiler.gensym(scope)
                    accum[i] = s
                    targetExprs[i] = utils.expr(s, 'sym')
                end
                wrapper = 'target'
                innerTail = opts.tail
                innerTarget = table.concat(accum, ', ')
            else
                wrapper = 'none'
                innerTail = opts.tail
                innerTarget = opts.target
            end
        else
            wrapper = 'iife'
            innerTail = true
            innerTarget = nil
        end

        -- Compile bodies and conditions
        local bodyOpts = {
            tail = innerTail,
            target = innerTarget,
            nval = opts.nval
        }
        local function compileBody(i)
            local chunk = {}
            local cscope = compiler.makeScope(doScope)
            compiler.keepSideEffects(compiler.compile1(ast[i], cscope, chunk, bodyOpts),
            chunk, nil, ast[i])
            return {
                chunk = chunk,
                scope = cscope
            }
        end
        for i = 2, #ast - 1, 2 do
            local condchunk = {}
            local res = compiler.compile1(ast[i], doScope, condchunk, {nval = 1})
            local cond = res[1]
            local branch = compileBody(i + 1)
            branch.cond = cond
            branch.condchunk = condchunk
            branch.nested = i ~= 2 and next(condchunk, nil) == nil
            table.insert(branches, branch)
        end
        local hasElse = #ast > 3 and #ast % 2 == 0
        if hasElse then elseBranch = compileBody(#ast) end

        -- Emit code
        local s = compiler.gensym(scope)
        local buffer = {}
        local lastBuffer = buffer
        for i = 1, #branches do
            local branch = branches[i]
            local fstr = not branch.nested and 'if %s then' or 'elseif %s then'
            local cond = tostring(branch.cond)
            local condLine = (cond == "true" and branch.nested and i == #branches)
                and "else"
                or fstr:format(cond)
            if branch.nested then
                compiler.emit(lastBuffer, branch.condchunk, ast)
            else
                for _, v in ipairs(branch.condchunk) do compiler.emit(lastBuffer, v, ast) end
            end
            compiler.emit(lastBuffer, condLine, ast)
            compiler.emit(lastBuffer, branch.chunk, ast)
            if i == #branches then
                if hasElse then
                    compiler.emit(lastBuffer, 'else', ast)
                    compiler.emit(lastBuffer, elseBranch.chunk, ast)
                -- TODO: Consolidate use of condLine ~= "else" with hasElse
                elseif(innerTarget and condLine ~= 'else') then
                    compiler.emit(lastBuffer, 'else', ast)
                    compiler.emit(lastBuffer, ("%s = nil"):format(innerTarget), ast)
                end
                compiler.emit(lastBuffer, 'end', ast)
            elseif not branches[i + 1].nested then
                compiler.emit(lastBuffer, 'else', ast)
                local nextBuffer = {}
                compiler.emit(lastBuffer, nextBuffer, ast)
                compiler.emit(lastBuffer, 'end', ast)
                lastBuffer = nextBuffer
            end
        end

        if wrapper == 'iife' then
            local iifeargs = scope.vararg and '...' or ''
            compiler.emit(parent, ('local function %s(%s)'):format(tostring(s), iifeargs), ast)
            compiler.emit(parent, buffer, ast)
            compiler.emit(parent, 'end', ast)
            return utils.expr(('%s(%s)'):format(tostring(s), iifeargs), 'statement')
        elseif wrapper == 'none' then
            -- Splice result right into code
            for i = 1, #buffer do
                compiler.emit(parent, buffer[i], ast)
            end
            return {returned = true}
        else -- wrapper == 'target'
            compiler.emit(parent, ('local %s'):format(innerTarget), ast)
            for i = 1, #buffer do
                compiler.emit(parent, buffer[i], ast)
            end
            return targetExprs
        end
    end
    docSpecial("if", {"cond1", "body1", "...", "condN", "bodyN"},
               "Conditional form.\n" ..
                   "Takes any number of condition/body pairs and evaluates the first body where"
                   .. "\nthe condition evaluates to truthy. Similar to cond in other lisps.")

    local function remove_until_condition(bindings)
       if ("until" == bindings[(#bindings - 1)] or
           "&until" == tostring(bindings[(#bindings - 1)])) then
          table.remove(bindings, (#bindings - 1))
          return table.remove(bindings)
       end
    end

    local function compile_until(condition, scope, chunk)
       if condition then
          local condition_lua = compiler.compile1(condition, scope, chunk, {nval = 1})[1]
          return compiler.emit(chunk, ("if %s then break end"):format(tostring(condition_lua)),
                               utils.expr(condition, "expression"))
       end
    end

    -- (each [k v (pairs t)] body...) => []
    SPECIALS["each"] = function(ast, scope, parent)
        local binding = compiler.assert(utils.isTable(ast[2]), "expected binding table", ast)
        compiler.assert(#ast >= 3, "expected body expression", ast[1])
        local until_condition = remove_until_condition(binding)
        local iter = table.remove(binding, #binding) -- last item is iterator call
        local destructures = {}
        local newManglings = {}
        local subScope = compiler.makeScope(scope)
        local function destructureBinding(v)
            if utils.isSym(v) then
                return compiler.declareLocal(v, {}, subScope, ast, newManglings)
            else
                local raw = utils.sym(compiler.gensym(subScope))
                destructures[raw] = v
                return compiler.declareLocal(raw, {}, subScope, ast)
            end
        end
        local bindVars = utils.map(binding, destructureBinding)
        local vals = compiler.compile1(iter, subScope, parent)
        local valNames = utils.map(vals, tostring)

        compiler.emit(parent, ('for %s in %s do'):format(table.concat(bindVars, ', '),
                                                table.concat(valNames, ", ")), ast)
        local chunk = {}
        for raw, args in utils.stablepairs(destructures) do
            compiler.destructure(args, raw, ast, subScope, chunk,
                                 { declaration = true, nomulti = true })
        end
        compiler.applyManglings(subScope, newManglings, ast)
        compile_until(until_condition, subScope, chunk)
        compileDo(ast, subScope, chunk, 3)
        compiler.emit(parent, chunk, ast)
        compiler.emit(parent, 'end', ast)
    end
    docSpecial("each", {"[key value (iterator)]", "..."},
               "Runs the body once for each set of values provided by the given iterator."
               .."\nMost commonly used with ipairs for sequential tables or pairs for"
                   .." undefined\norder, but can be used with any iterator.")

    -- (while condition body...) => []
    SPECIALS["while"] = function(ast, scope, parent)
        local len1 = #parent
        local condition = compiler.compile1(ast[2], scope, parent, {nval = 1})[1]
        local len2 = #parent
        local subChunk = {}
        if len1 ~= len2 then
            -- Compound condition
            -- Move new compilation to subchunk
            for i = len1 + 1, len2 do
                subChunk[#subChunk + 1] = parent[i]
                parent[i] = nil
            end
            compiler.emit(parent, 'while true do', ast)
            compiler.emit(subChunk, ('if not %s then break end'):format(condition[1]), ast)
        else
            -- Simple condition
            compiler.emit(parent, 'while ' .. tostring(condition) .. ' do', ast)
        end
        compileDo(ast, compiler.makeScope(scope), subChunk, 3)
        compiler.emit(parent, subChunk, ast)
        compiler.emit(parent, 'end', ast)
    end
    docSpecial("while", {"condition", "..."},
               "The classic while loop. Evaluates body until a condition is non-truthy.")

    SPECIALS["for"] = function(ast, scope, parent)
        local ranges = compiler.assert(utils.isTable(ast[2]), "expected binding table", ast)
        local until_condition = remove_until_condition(ast[2])
        local bindingSym = table.remove(ast[2], 1)
        local subScope = compiler.makeScope(scope)
        compiler.assert(utils.isSym(bindingSym),
                      ("unable to bind %s %s"):
                          format(type(bindingSym), tostring(bindingSym)), ast[2])
        compiler.assert(#ast >= 3, "expected body expression", ast[1])
        local rangeArgs = {}
        for i = 1, math.min(#ranges, 3) do
            rangeArgs[i] = tostring(compiler.compile1(ranges[i], subScope, parent, {nval = 1})[1])
        end
        compiler.emit(parent, ('for %s = %s do'):format(
                 compiler.declareLocal(bindingSym, {}, subScope, ast),
                 table.concat(rangeArgs, ', ')), ast)
        local chunk = {}
        compile_until(until_condition, subScope, chunk)
        compileDo(ast, subScope, chunk, 3)
        compiler.emit(parent, chunk, ast)
        compiler.emit(parent, 'end', ast)
    end
    docSpecial("for", {"[index start stop step?]", "..."}, "Numeric loop construct." ..
                   "\nEvaluates body once for each value between start and stop (inclusive).")

    -- For statements and expressions, put the value in a local to avoid
    -- double-evaluating it.
    local function once(val, ast, scope, parent)
        if val.type == 'statement' or val.type == 'expression' then
            local s = compiler.gensym(scope)
            compiler.emit(parent, ('local %s = %s'):format(s, tostring(val)), ast)
            return utils.expr(s, 'sym')
        else
            return val
        end
    end

    SPECIALS[":"] = function(ast, scope, parent)
        compiler.assert(#ast >= 3, "expected at least 2 arguments", ast)
        -- Compile object
        local objectexpr = compiler.compile1(ast[2], scope, parent, {nval = 1})[1]
        -- Compile method selector
        local methodstring
        local methodident = false
        if type(ast[3]) == 'string' and utils.isValidLuaIdentifier(ast[3]) then
            methodident = true
            methodstring = ast[3]
        else
            methodstring = tostring(compiler.compile1(ast[3], scope, parent, {nval = 1})[1])
            objectexpr = once(objectexpr, ast[2], scope, parent)
        end
        -- Compile arguments
        local args = {}
        for i = 4, #ast do
            local subexprs = compiler.compile1(ast[i], scope, parent, {
                nval = i ~= #ast and 1 or nil
            })
            utils.map(subexprs, tostring, args)
        end
        local fstring
        if not methodident then
            -- Make object first argument
            table.insert(args, 1, tostring(objectexpr))
            fstring = objectexpr.type == 'sym'
                and '%s[%s](%s)'
                or '(%s)[%s](%s)'
        elseif(objectexpr.type == 'literal' or objectexpr.type == 'expression') then
            fstring = '(%s):%s(%s)'
        else
            fstring = '%s:%s(%s)'
        end
        return utils.expr(fstring:format(
            tostring(objectexpr),
            methodstring,
            table.concat(args, ', ')), 'statement')
    end
    docSpecial(":", {"tbl", "method-name", "..."},
               "Call the named method on tbl with the provided args."..
               "\nMethod name doesn\"t have to be known at compile-time; if it is, use"
                   .."\n(tbl:method-name ...) instead.")

    SPECIALS["comment"] = function(ast, _, parent)
        local els = {}
        for i = 2, #ast do
            els[#els + 1] = tostring(ast[i]):gsub('\n', ' ')
        end
        compiler.emit(parent, '-- ' .. table.concat(els, ' '), ast)
    end
    docSpecial("comment", {"..."}, "Comment which will be emitted in Lua output.")

    SPECIALS["hashfn"] = function(ast, scope, parent)
        compiler.assert(#ast == 2, "expected one argument", ast)
        local fScope = compiler.makeScope(scope)
        local fChunk = {}
        local name = compiler.gensym(scope)
        local symbol = utils.sym(name)
        compiler.declareLocal(symbol, {}, scope, ast)
        fScope.vararg = false
        fScope.hashfn = true
        local args = {}
        for i = 1, 9 do args[i] = compiler.declareLocal(utils.sym('$' .. i), {}, fScope, ast) end
        -- recursively walk the AST, transforming $... into ...
        utils.walkTree(ast[2], function(idx, node, parentNode)
            if utils.isSym(node) and utils.deref(node) == '$...' then
                parentNode[idx] = utils.varg()
                fScope.vararg = true
            else -- truthy return value determines whether to traverse children
                return utils.isList(node) or utils.isTable(node)
            end
        end)
        -- Compile body
        compiler.compile1(ast[2], fScope, fChunk, {tail = true})
        local maxUsed = 0
        for i = 1, 9 do if fScope.symmeta['$' .. i].used then maxUsed = i end end
        if fScope.vararg then
            compiler.assert(maxUsed == 0, '$ and $... in hashfn are mutually exclusive', ast)
            args = {utils.deref(utils.varg())}
            maxUsed = 1
        end
        local argStr = table.concat(args, ', ', 1, maxUsed)
        compiler.emit(parent, ('local function %s(%s)'):format(name, argStr), ast)
        compiler.emit(parent, fChunk, ast)
        compiler.emit(parent, 'end', ast)
        return utils.expr(name, 'sym')
    end
    docSpecial("hashfn", {"..."},
               "Function literal shorthand; args are either $... OR $1, $2, etc.")

    local function defineArithmeticSpecial(name, zeroArity, unaryPrefix, luaName)
        local paddedOp = ' ' .. (luaName or name) .. ' '
        SPECIALS[name] = function(ast, scope, parent)
            local len = #ast
            if len == 1 then
                compiler.assert(zeroArity ~= nil, 'Expected more than 0 arguments', ast)
                return utils.expr(zeroArity, 'literal')
            else
                local operands = {}
                for i = 2, len do
                    local subexprs = compiler.compile1(ast[i], scope, parent, {
                        nval = (i == 1 and 1 or nil)
                    })
                    utils.map(subexprs, tostring, operands)
                end
                if #operands == 1 then
                    if unaryPrefix then
                        return '(' .. unaryPrefix .. paddedOp .. operands[1] .. ')'
                    else
                        return operands[1]
                    end
                else
                    return '(' .. table.concat(operands, paddedOp) .. ')'
                end
            end
        end
        docSpecial(name, {"a", "b", "..."},
                   "Arithmetic operator; works the same as Lua but accepts more arguments.")
    end

    defineArithmeticSpecial('+', '0')
    defineArithmeticSpecial('..', "''")
    defineArithmeticSpecial('^')
    defineArithmeticSpecial('-', nil, '')
    defineArithmeticSpecial('*', '1')
    defineArithmeticSpecial('%')
    defineArithmeticSpecial('/', nil, '1')
    defineArithmeticSpecial('//', nil, '1')

    defineArithmeticSpecial("lshift", nil, "1", "<<")
    defineArithmeticSpecial("rshift", nil, "1", ">>")
    defineArithmeticSpecial("band", "0", "0", "&")
    defineArithmeticSpecial("bor", "0", "0", "|")
    defineArithmeticSpecial("bxor", "0", "0", "~")

    docSpecial("lshift", {"x", "n"},
               "Bitwise logical left shift of x by n bits; only works in Lua 5.3+.")
    docSpecial("rshift", {"x", "n"},
               "Bitwise logical right shift of x by n bits; only works in Lua 5.3+.")
    docSpecial("band", {"x1", "x2"}, "Bitwise AND of arguments; only works in Lua 5.3+.")
    docSpecial("bor", {"x1", "x2"}, "Bitwise OR of arguments; only works in Lua 5.3+.")
    docSpecial("bxor", {"x1", "x2"}, "Bitwise XOR of arguments; only works in Lua 5.3+.")

    defineArithmeticSpecial('or', 'false')
    defineArithmeticSpecial('and', 'true')

    docSpecial("and", {"a", "b", "..."},
               "Boolean operator; works the same as Lua but accepts more arguments.")
    docSpecial("or", {"a", "b", "..."},
               "Boolean operator; works the same as Lua but accepts more arguments.")
    docSpecial("..", {"a", "b", "..."},
               "String concatenation operator; works the same as Lua but accepts more arguments.")

    local function native_comparator(op, lhs_ast, rhs_ast, scope, parent)
        local lhs = compiler.compile1(lhs_ast, scope, parent, {nval = 1})[1]
        local rhs = compiler.compile1(rhs_ast, scope, parent, {nval = 1})[1]
        return string.format("(%s %s %s)", tostring(lhs), op, tostring(rhs))
    end

    local function idempotent_comparator(op, chain_op, ast, scope, parent)
       local vals, comparisons = {}, {}
       local chain = string.format(" %s ", chain_op or "and")
       for i=2, #ast do
          local val = compiler.compile1(ast[i], scope, parent, {nval=1})[1]
          table.insert(vals, tostring(val))
       end
       for i=1,#vals-1 do
          local comparison = string.format("(%s %s %s)", vals[i], op, vals[i+1])
          table.insert(comparisons, comparison)
       end
       return "(" .. table.concat(comparisons, chain) .. ")"
    end

    local function double_eval_protected_comparator(op, chain_op, ast, scope, parent)
        local arglist, comparisons, vals = {}, {}, {}
        local chain = string.format(" %s ", (chain_op or "and"))
        for i = 2, #ast do
            table.insert(arglist, tostring(compiler.gensym(scope)))
            table.insert(vals, tostring(compiler.compile1(ast[i], scope,
                                                          parent, {nval = 1})[1]))
        end
        for i = 1, (#arglist - 1) do
            table.insert(comparisons, string.format("(%s %s %s)", arglist[i],
                                                    op, arglist[(i + 1)]))
        end
        return string.format("(function(%s) return %s end)(%s)",
                             table.concat(arglist, ","),
                             table.concat(comparisons, chain),
                             table.concat(vals, ","))
    end

    local function defineComparatorSpecial(name, lua_op, chain_op)
        local op = (lua_op or name)
        local function opfn(ast, scope, parent)
            compiler.assert((2 < #ast), "expected at least two arguments", ast)
            if (3 == #ast) then
                return native_comparator(op, ast[2], ast[3], scope, parent)
            elseif(utils.every({unpack(ast, 2)}, utils.isIdempotent)) then
                return idempotent_comparator(op, chain_op, ast, scope, parent)
            else
                return double_eval_protected_comparator(op, chain_op, ast, scope, parent)
            end
        end
        SPECIALS[name] = opfn
    end

    defineComparatorSpecial('>')
    defineComparatorSpecial('<')
    defineComparatorSpecial('>=')
    defineComparatorSpecial('<=')
    defineComparatorSpecial('=', '==')
    defineComparatorSpecial('not=', '~=', 'or')
    SPECIALS["~="] = SPECIALS["not="] -- backwards-compatibility alias

    local function defineUnarySpecial(op, realop)
        SPECIALS[op] = function(ast, scope, parent)
            compiler.assert(#ast == 2, 'expected one argument', ast)
            local tail = compiler.compile1(ast[2], scope, parent, {nval = 1})
            return (realop or op) .. tostring(tail[1])
        end
    end

    defineUnarySpecial("not", "not ")
    docSpecial("not", {"x"}, "Logical operator; works the same as Lua.")

    defineUnarySpecial("bnot", "~")
    docSpecial("bnot", {"x"}, "Bitwise negation; only works in Lua 5.3+.")

    defineUnarySpecial("length", "#")
    docSpecial("length", {"x"}, "Returns the length of a table or string.")
    SPECIALS["#"] = SPECIALS["length"]

    SPECIALS['quote'] = function(ast, scope, parent)
        compiler.assert(#ast == 2, "expected one argument")
        local runtime, thisScope = true, scope
        while thisScope do
            thisScope = thisScope.parent
            if thisScope == compiler.scopes.compiler then runtime = false end
        end
        return compiler.doQuote(ast[2], scope, parent, runtime)
    end
    docSpecial('quote', {'x'}, 'Quasiquote the following form. Only works in macro/compiler scope.')

    local function makeCompilerEnv(ast, scope, parent)
        local viewok, view = pcall(require, "bootstrap.view")
        local env = {
            -- State of compiler if needed
            _SCOPE = scope,
            _CHUNK = parent,
            _AST = ast,
            _IS_COMPILER = true,
            _SPECIALS = compiler.scopes.global.specials,
            _VARARG = utils.varg(),
            -- Expose the module in the compiler
            fennel = utils.fennelModule,
            unpack = unpack,
            pairs = utils.stablepairs, -- reproducible builds!
            view = (viewok and view or tostring),

            -- Useful for macros and meta programming. All of Fennel can be accessed
            -- via fennel.myfun, for example (fennel.eval "(print 1)").
            list = utils.list,
            sym = utils.sym,
            sequence = utils.sequence,
            gensym = function()
                return utils.sym(compiler.gensym(compiler.scopes.macro or scope))
            end,
            ["list?"] = utils.isList,
            ["multi-sym?"] = utils.isMultiSym,
            ["sym?"] = utils.isSym,
            ["table?"] = utils.isTable,
            ["sequence?"] = utils.isSequence,
            ["varg?"] = utils.isVarg,
            ["get-scope"] = function() return compiler.scopes.macro end,
            ["in-scope?"] = function(symbol)
                compiler.assert(compiler.scopes.macro, "must call from macro", ast)
                return compiler.scopes.macro.manglings[tostring(symbol)]
            end,
            ["macroexpand"] = function(form)
                compiler.assert(compiler.scopes.macro, "must call from macro", ast)
                return compiler.macroexpand(form, compiler.scopes.macro)
            end,
        }
        env._G = env
        return setmetatable(env, { __index = _ENV or _G })
    end

    -- have searchModule use package.config to process package.path (windows compat)
    local cfg = string.gmatch(package.config, "([^\n]+)")
    local dirsep, pathsep, pathmark = cfg() or '/', cfg() or ';', cfg() or '?'
    local pkgConfig = {dirsep = dirsep, pathsep = pathsep, pathmark = pathmark}

    -- Escape a string for safe use in a Lua pattern
    local function escapepat(str)
        return string.gsub(str, "[^%w]", "%%%1")
    end

    local function searchModule(modulename, pathstring)
        local pathsepesc = escapepat(pkgConfig.pathsep)
        local pathsplit = string.format("([^%s]*)%s", pathsepesc, pathsepesc)
        local nodotModule = modulename:gsub("%.", pkgConfig.dirsep)
        for path in string.gmatch((pathstring or utils.fennelModule.path) ..
                                  pkgConfig.pathsep, pathsplit) do
            local filename = path:gsub(escapepat(pkgConfig.pathmark), nodotModule)
            local filename2 = path:gsub(escapepat(pkgConfig.pathmark), modulename)
            local file = io.open(filename) or io.open(filename2)
            if(file) then
                file:close()
                return filename
            end
        end
    end

    local function macroGlobals(env, globals)
        local allowed = currentGlobalNames(env)
        for _, k in pairs(globals or {}) do table.insert(allowed, k) end
        return allowed
    end

    local function addMacros(macros, ast, scope)
        compiler.assert(utils.isTable(macros), 'expected macros to be table', ast)
        for k,v in pairs(macros) do
            compiler.assert(type(v) == 'function', 'expected each macro to be function', ast)
            scope.macros[k] = v
        end
    end

    local function loadMacros(modname, ast, scope, parent)
        local filename = compiler.assert(searchModule(modname),
                                       modname .. " module not found.", ast)
        local env = makeCompilerEnv(ast, scope, parent)
        local globals = macroGlobals(env, currentGlobalNames())
        return compiler.dofileFennel(filename,
                                     { env = env, allowedGlobals = globals,
                                       useMetadata = utils.root.options.useMetadata,
                                       scope = compiler.scopes.compiler })
    end

    local macroLoaded = {}

    SPECIALS['require-macros'] = function(ast, scope, parent)
        compiler.assert(#ast == 2, "Expected one module name argument", ast)
        local modname = ast[2]
        if not macroLoaded[modname] then
            macroLoaded[modname] = loadMacros(modname, ast, scope, parent)
        end
        if(tostring(ast[1]) == "import-macros") then
            return macroLoaded[modname]
        else
            addMacros(macroLoaded[modname], ast, scope, parent)
        end
    end
    docSpecial('require-macros', {'macro-module-name'},
               'Load given module and use its contents as macro definitions in current scope.'
                   ..'\nMacro module should return a table of macro functions with string keys.'
                   ..'\nConsider using import-macros instead as it is more flexible.')

    SPECIALS['include'] = function(ast, scope, parent, opts)
        compiler.assert(#ast == 2, 'expected one argument', ast)

        -- Compile mod argument
        local modexpr = compiler.compile1(ast[2], scope, parent, {nval = 1})[1]
        if modexpr.type ~= 'literal' or modexpr[1]:byte() ~= 34 then
            if opts.fallback then
                return opts.fallback(modexpr)
            else
                compiler.assert(false, 'module name must resolve to a string literal', ast)
            end
        end
        local code = 'return ' .. modexpr[1]
        local mod = loadCode(code)()

        -- Check cache
        if utils.root.scope.includes[mod] then return utils.root.scope.includes[mod] end

        -- Find path to source
        local path = searchModule(mod)
        local isFennel = true
        if not path then
            isFennel = false
            path = searchModule(mod, package.path)
            if not path then
                if opts.fallback then
                    return opts.fallback(modexpr)
                else
                    compiler.assert(false, 'module not found ' .. mod, ast)
                end
            end
        end

        -- Read source
        local f = io.open(path)
        local s = f:read('*all'):gsub('[\r\n]*$', '')
        f:close()

        -- splice in source and memoize it in compiler AND package.preload
        -- so we can include it again without duplication, even in runtime
        local ret = utils.expr('require("' .. mod .. '")', 'statement')
        local target = ('package.preload[%q]'):format(mod)
        local preloadStr = target .. ' = ' .. target .. ' or function(...)'

        local tempChunk, subChunk = {}, {}
        compiler.emit(tempChunk, preloadStr, ast)
        compiler.emit(tempChunk, subChunk)
        compiler.emit(tempChunk, 'end', ast)
        -- Splice tempChunk to begining of root chunk
        for i, v in ipairs(tempChunk) do table.insert(utils.root.chunk, i, v) end

        -- For fnl source, compile subChunk AFTER splicing into start of root chunk.
        if isFennel then
            local subscope = compiler.makeScope(utils.root.scope.parent)
            if utils.root.options.requireAsInclude then
                subscope.specials.require = compiler.requireInclude
            end
            -- parse Fennel src into table of exprs to know which expr is the tail
            local forms, p = {}, parser.parser(parser.stringStream(s), path)
            for _, val in p do table.insert(forms, val) end
            -- Compile the forms into subChunk; compiler.compile1 is necessary for all nested
            -- includes to be emitted in the same root chunk in the top-level module
            for i = 1, #forms do
                local subopts = i == #forms and {nval=1, tail=true} or {nval=0}
                utils.propagateOptions(opts, subopts)
                compiler.compile1(forms[i], subscope, subChunk, subopts)
            end
        else -- for Lua source, simply emit the src into the loader's body
            compiler.emit(subChunk, s, ast)
        end

        -- Put in cache and return
        utils.root.scope.includes[mod] = ret
        return ret
    end
    docSpecial('include', {'module-name-literal'},
               'Like require, but load the target module during compilation and embed it in the\n'
            .. 'Lua output. The module must be a string literal and resolvable at compile time.')

    local function evalCompiler(ast, scope, parent)
        local luaSource =
            compiler.compile(ast, { scope = compiler.makeScope(compiler.scopes.compiler),
                                    useMetadata = utils.root.options.useMetadata })
        local loader = loadCode(luaSource, wrapEnv(makeCompilerEnv(ast, scope, parent)))
        return loader()
    end

    SPECIALS['macros'] = function(ast, scope, parent)
        compiler.assert(#ast == 2, "Expected one table argument", ast)
        local macros = evalCompiler(ast[2], scope, parent)
        addMacros(macros, ast, scope, parent)
    end
    docSpecial('macros', {'{:macro-name-1 (fn [...] ...) ... :macro-name-N macro-body-N}'},
               'Define all functions in the given table as macros local to the current scope.')

    SPECIALS['eval-compiler'] = function(ast, scope, parent)
        local oldFirst = ast[1]
        ast[1] = utils.sym('do')
        local val = evalCompiler(ast, scope, parent)
        ast[1] = oldFirst
        return val
    end
    docSpecial('eval-compiler', {'...'}, 'Evaluate the body at compile-time.'
                   .. ' Use the macro system instead if possible.')

    -- A few things that aren't specials, but are needed to define specials, but
    -- are also needed for the following code.
    return { wrapEnv=wrapEnv,
             currentGlobalNames=currentGlobalNames,
             loadCode=loadCode,
             doc=doc,
             macroLoaded=macroLoaded,
             searchModule=searchModule,
             makeCompilerEnv=makeCompilerEnv, }
end)()

---
--- Evaluation, repl, public API, and macros
---

local function eval(str, options, ...)
    local opts = utils.copy(options)
    -- eval and dofile are considered "live" entry points, so we can assume
    -- that the globals available at compile time are a reasonable allowed list
    -- UNLESS there's a metatable on env, in which case we can't assume that
    -- pairs will return all the effective globals; for instance openresty
    -- sets up _G in such a way that all the globals are available thru
    -- the __index meta method, but as far as pairs is concerned it's empty.
    if opts.allowedGlobals == nil and not getmetatable(opts.env) then
        opts.allowedGlobals = specials.currentGlobalNames(opts.env)
    end
    local env = opts.env and specials.wrapEnv(opts.env)
    local luaSource = compiler.compileString(str, opts)
    local loader = specials.loadCode(luaSource, env, opts.filename and
                                         ('@' .. opts.filename) or str)
    opts.filename = nil
    return loader(...)
end

-- This is bad; we have a circular dependency between the specials section and
-- the evaluation section due to require-macros/import-macros needing to be able
-- to do this. For now stash it in the compiler table, but we should untangle it
compiler.dofileFennel = function(filename, options, ...)
    local opts = utils.copy(options)
    local f = assert(io.open(filename, "rb"))
    local source = f:read("*all")
    f:close()
    opts.filename = filename
    return eval(source, opts, ...)
end

-- Everything exported by the module
local module = {
    parser = parser.parser,
    granulate = parser.granulate,
    stringStream = parser.stringStream,

    compile = compiler.compile,
    compileString = compiler.compileString,
    compileStream = compiler.compileStream,
    compile1 = compiler.compile1,
    traceback = compiler.traceback,
    mangle = compiler.globalMangling,
    unmangle = compiler.globalUnmangling,
    metadata = compiler.metadata,
    scope = compiler.makeScope,
    gensym = compiler.gensym,

    list = utils.list,
    sym = utils.sym,
    varg = utils.varg,
    path = utils.path,

    loadCode = specials.loadCode,
    macroLoaded = specials.macroLoaded,
    searchModule = specials.searchModule,
    doc = specials.doc,

    eval = eval,
    dofile = compiler.dofileFennel,
    version = "0.4.4-dev",
}

utils.fennelModule = module -- yet another circular dependency =(

-- In order to make this more readable, you can switch your editor to treating
-- this file as if it were Fennel for the purposes of this section
local replsource = [===[(local (fennel internals) ...)

(fn default-read-chunk [parser-state]
  (io.write (if (< 0 parser-state.stackSize) ".." ">> "))
  (io.flush)
  (let [input (io.read)]
    (and input (.. input "\n"))))

(fn default-on-values [xs]
  (io.write (table.concat xs "\t"))
  (io.write "\n"))

(fn default-on-error [errtype err lua-source]
  (io.write
   (match errtype
     "Lua Compile" (.. "Bad code generated - likely a bug with the compiler:\n"
                       "--- Generated Lua Start ---\n"
                       lua-source
                       "--- Generated Lua End ---\n")
     "Runtime" (.. (fennel.traceback err 4) "\n")
     _ (: "%s error: %s\n" :format errtype (tostring err)))))

(local save-source
       (table.concat ["local ___i___ = 1"
                      "while true do"
                      " local name, value = debug.getlocal(1, ___i___)"
                      " if(name and name ~= \"___i___\") then"
                      " ___replLocals___[name] = value"
                      " ___i___ = ___i___ + 1"
                      " else break end end"] "\n"))

(fn splice-save-locals [env lua-source]
  (set env.___replLocals___ (or env.___replLocals___ {}))
  (let [spliced-source []
        bind "local %s = ___replLocals___['%s']"]
    (each [line (lua-source:gmatch "([^\n]+)\n?")]
      (table.insert spliced-source line))
    (each [name (pairs env.___replLocals___)]
      (table.insert spliced-source 1 (bind:format name name)))
    (when (and (< 1 (# spliced-source))
               (: (. spliced-source (# spliced-source)) :match "^ *return .*$"))
      (table.insert spliced-source (# spliced-source) save-source))
    (table.concat spliced-source "\n")))

(fn completer [env scope text]
  (let [matches []
        input-fragment (text:gsub ".*[%s)(]+" "")]
    (fn add-partials [input tbl prefix] ; add partial key matches in tbl
      (each [k (internals.allpairs tbl)]
        (let [k (if (or (= tbl env) (= tbl env.___replLocals___))
                    (. scope.unmanglings k)
                    k)]
          (when (and (< (# matches) 2000) ; stop explosion on too many items
                     (= (type k) "string")
                     (= input (k:sub 0 (# input))))
            (table.insert matches (.. prefix k))))))
    (fn add-matches [input tbl prefix] ; add matches, descending into tbl fields
      (let [prefix (if prefix (.. prefix ".") "")]
        (if (not (input:find "%.")) ; no more dots, so add matches
            (add-partials input tbl prefix)
            (let [(head tail) (input:match "^([^.]+)%.(.*)")
                  raw-head (if (or (= tbl env) (= tbl env.___replLocals___))
                               (. scope.manglings head)
                               head)]
              (when (= (type (. tbl raw-head)) "table")
                (add-matches tail (. tbl raw-head) (.. prefix head)))))))

    (add-matches input-fragment (or scope.specials []))
    (add-matches input-fragment (or scope.macros []))
    (add-matches input-fragment (or env.___replLocals___ []))
    (add-matches input-fragment env)
    (add-matches input-fragment (or env._ENV env._G []))
    matches))

(fn repl [options]
  (let [old-root-options internals.rootOptions
        env (if options.env
                (internals.wrapEnv options.env)
                (setmetatable {} {:__index (or _G._ENV _G)}))
        save-locals? (and (not= options.saveLocals false)
                          env.debug env.debug.getlocal)
        opts {}
        _ (each [k v (pairs options)] (tset opts k v))
        read-chunk (or opts.readChunk default-read-chunk)
        on-values (or opts.onValues default-on-values)
        on-error (or opts.onError default-on-error)
        pp (or opts.pp tostring)
        ;; make parser
        (byte-stream clear-stream) (fennel.granulate read-chunk)
        chars []
        (read reset) (fennel.parser (fn [parser-state]
                                      (let [c (byte-stream parser-state)]
                                        (tset chars (+ (# chars) 1) c)
                                        c)))
        scope (fennel.scope)]

    ;; use metadata unless we've specifically disabled it
    (set opts.useMetadata (not= options.useMetadata false))
    (when (= opts.allowedGlobals nil)
      (set opts.allowedGlobals (internals.currentGlobalNames opts.env)))

    (when opts.registerCompleter
      (opts.registerCompleter (partial completer env scope)))

    (fn loop []
      (each [k (pairs chars)] (tset chars k nil))
      (let [(ok parse-ok? x) (pcall read)
            src-string (string.char ((or _G.unpack table.unpack) chars))]
        (internals.setRootOptions opts)
        (if (not ok)
            (do (on-error "Parse" parse-ok?)
                (clear-stream)
                (reset)
                (loop))
            (when parse-ok? ; if this is false, we got eof
              (match (pcall fennel.compile x {:correlate opts.correlate
                                              :source src-string
                                              :scope scope
                                              :useMetadata opts.useMetadata
                                              :moduleName opts.moduleName
                                              :assert-compile opts.assert-compile
                                              :parse-error opts.parse-error})
                (false msg) (do (clear-stream)
                                (on-error "Compile" msg))
                (true source) (let [source (if save-locals?
                                               (splice-save-locals env source)
                                               source)
                                    (lua-ok? loader) (pcall fennel.loadCode
                                                            source env)]
                                (if (not lua-ok?)
                                    (do (clear-stream)
                                        (on-error "Lua Compile" loader source))
                                    (match (xpcall #[(loader)]
                                                   (partial on-error "Runtime"))
                                      (true ret)
                                      (do (set env._ (. ret 1))
                                          (set env.__ ret)
                                          (on-values (internals.map ret pp)))))))
              (internals.setRootOptions old-root-options)
              (loop)))))
    (loop)))]===]

module.repl = function(options)
    -- functionality the repl needs that isn't part of the public API yet
    local internals = { rootOptions = utils.root.options,
                        setRootOptions = function(r) utils.root.options = r end,
                        currentGlobalNames = specials.currentGlobalNames,
                        wrapEnv = specials.wrapEnv,
                        allpairs = utils.allpairs,
                        map = utils.map }
    return eval(replsource, { correlate = true }, module, internals)(options)
end

module.makeSearcher = function(options)
    return function(modulename)
      -- this will propagate options from the repl but not from eval, because
      -- eval unsets utils.root.options after compiling but before running the actual
      -- calls to require.
      local opts = utils.copy(utils.root.options)
      for k,v in pairs(options or {}) do opts[k] = v end
      local filename = specials.searchModule(modulename)
      if filename then
         return function(modname)
            return compiler.dofileFennel(filename, opts, modname)
         end
      end
   end
end

-- This will allow regular `require` to work with Fennel:
-- table.insert(package.loaders, fennel.searcher)
module.searcher = module.makeSearcher()
module.make_searcher = module.makeSearcher -- oops backwards compatibility
module["make-searcher"] = module.makeSearcher
module["compile-string"] = module.compileString

-- Load standard macros
local stdmacros = [===[
;; These macros are awkward because their definition cannot rely on the any
;; built-in macros, only special forms. (no when, no icollect, etc)

(fn copy [t]
  (let [out []]
    (each [_ v (ipairs t)] (table.insert out v))
    (setmetatable out (getmetatable t))))

(fn ->* [val ...]
  "Thread-first macro.
Take the first value and splice it into the second form as its first argument.
The value of the second form is spliced into the first arg of the third, etc."
  (var x val)
  (each [_ e (ipairs [...])]
    (let [elt (if (list? e) (copy e) (list e))]
      (table.insert elt 2 x)
      (set x elt)))
  x)

(fn ->>* [val ...]
  "Thread-last macro.
Same as ->, except splices the value into the last position of each form
rather than the first."
  (var x val)
  (each [_ e (ipairs [...])]
    (let [elt (if (list? e) (copy e) (list e))]
      (table.insert elt x)
      (set x elt)))
  x)

(fn -?>* [val ?e ...]
  "Nil-safe thread-first macro.
Same as -> except will short-circuit with nil when it encounters a nil value."
  (if (= nil ?e)
      val
      (let [el (if (list? ?e) (copy ?e) (list ?e))
            tmp (gensym)]
        (table.insert el 2 tmp)
        `(let [,tmp ,val]
           (if (not= nil ,tmp)
               (-?> ,el ,...)
               ,tmp)))))

(fn -?>>* [val ?e ...]
  "Nil-safe thread-last macro.
Same as ->> except will short-circuit with nil when it encounters a nil value."
  (if (= nil ?e)
      val
      (let [el (if (list? ?e) (copy ?e) (list ?e))
            tmp (gensym)]
        (table.insert el tmp)
        `(let [,tmp ,val]
           (if (not= ,tmp nil)
               (-?>> ,el ,...)
               ,tmp)))))

(fn ?dot [tbl ...]
  "Nil-safe table look up.
Same as . (dot), except will short-circuit with nil when it encounters
a nil value in any of subsequent keys."
  (let [head (gensym :t)
        lookups `(do
                   (var ,head ,tbl)
                   ,head)]
    (each [_ k (ipairs [...])]
      ;; Kinda gnarly to reassign in place like this, but it emits the best lua.
      ;; With this impl, it emits a flat, concise, and readable set of ifs
      (table.insert lookups (# lookups) `(if (not= nil ,head)
                                           (set ,head (. ,head ,k)))))
    lookups))

(fn doto* [val ...]
  "Evaluate val and splice it into the first argument of subsequent forms."
  (assert (not= val nil) "missing subject")
  (let [rebind? (or (not (sym? val))
                    (multi-sym? val))
        name (if rebind? (gensym)            val)
        form (if rebind? `(let [,name ,val]) `(do))]
    (each [_ elt (ipairs [...])]
      (let [elt (if (list? elt) (copy elt) (list elt))]
        (table.insert elt 2 name)
        (table.insert form elt)))
    (table.insert form name)
    form))

(fn when* [condition body1 ...]
  "Evaluate body for side-effects only when condition is truthy."
  (assert body1 "expected body")
  `(if ,condition
       (do
         ,body1
         ,...)))

(fn with-open* [closable-bindings ...]
  "Like `let`, but invokes (v:close) on each binding after evaluating the body.
The body is evaluated inside `xpcall` so that bound values will be closed upon
encountering an error before propagating it."
  (let [bodyfn `(fn []
                  ,...)
        closer `(fn close-handlers# [ok# ...]
                  (if ok# ... (error ... 0)))
        traceback `(. (or package.loaded.fennel debug) :traceback)]
    (for [i 1 (length closable-bindings) 2]
      (assert (sym? (. closable-bindings i))
              "with-open only allows symbols in bindings")
      (table.insert closer 4 `(: ,(. closable-bindings i) :close)))
    `(let ,closable-bindings
       ,closer
       (close-handlers# (_G.xpcall ,bodyfn ,traceback)))))

(fn extract-into [iter-tbl]
  (var (into iter-out found?) (values [] (copy iter-tbl)))
  (for [i (length iter-tbl) 2 -1]
    (let [item (. iter-tbl i)]
      (if (or (= `&into item)
              (= :into  item))
          (do
            (assert (not found?) "expected only one &into clause")
            (set found? true)
            (set into (. iter-tbl (+ i 1)))
            (table.remove iter-out i)
            (table.remove iter-out i)))))
  (assert (or (not found?) (sym? into) (table? into) (list? into))
          "expected table, function call, or symbol in &into clause")
  (values into iter-out))

(fn collect* [iter-tbl key-expr value-expr ...]
  "Return a table made by running an iterator and evaluating an expression that
returns key-value pairs to be inserted sequentially into the table.  This can
be thought of as a table comprehension. The body should provide two expressions
(used as key and value) or nil, which causes it to be omitted.

For example,
  (collect [k v (pairs {:apple \"red\" :orange \"orange\"})]
    (values v k))
returns
  {:red \"apple\" :orange \"orange\"}

Supports an &into clause after the iterator to put results in an existing table.
Supports early termination with an &until clause."
  (assert (and (sequence? iter-tbl) (<= 2 (length iter-tbl)))
          "expected iterator binding table")
  (assert (not= nil key-expr) "expected key and value expression")
  (assert (= nil ...)
          "expected 1 or 2 body expressions; wrap multiple expressions with do")
  (let [kv-expr (if (= nil value-expr) key-expr `(values ,key-expr ,value-expr))
        (into iter) (extract-into iter-tbl)]
    `(let [tbl# ,into]
       (each ,iter
         (let [(k# v#) ,kv-expr]
           (if (and (not= k# nil) (not= v# nil))
             (tset tbl# k# v#))))
       tbl#)))

(fn seq-collect [how iter-tbl value-expr ...]
  "Common part between icollect and fcollect for producing sequential tables.

Iteration code only differs in using the for or each keyword, the rest
of the generated code is identical."
  (assert (not= nil value-expr) "expected table value expression")
  (assert (= nil ...)
          "expected exactly one body expression. Wrap multiple expressions in do")
  (let [(into iter) (extract-into iter-tbl)]
    `(let [tbl# ,into]
       ;; believe it or not, using a var here has a pretty good performance
       ;; boost: https://p.hagelb.org/icollect-performance.html
       (var i# (length tbl#))
       (,how ,iter
             (let [val# ,value-expr]
               (when (not= nil val#)
                 (set i# (+ i# 1))
                 (tset tbl# i# val#))))
       tbl#)))

(fn icollect* [iter-tbl value-expr ...]
  "Return a sequential table made by running an iterator and evaluating an
expression that returns values to be inserted sequentially into the table.
This can be thought of as a table comprehension. If the body evaluates to nil
that element is omitted.

For example,
  (icollect [_ v (ipairs [1 2 3 4 5])]
    (when (not= v 3)
      (* v v)))
returns
  [1 4 16 25]

Supports an &into clause after the iterator to put results in an existing table.
Supports early termination with an &until clause."
  (assert (and (sequence? iter-tbl) (<= 2 (length iter-tbl)))
          "expected iterator binding table")
  (seq-collect 'each iter-tbl value-expr ...))

(fn fcollect* [iter-tbl value-expr ...]
  "Return a sequential table made by advancing a range as specified by
for, and evaluating an expression that returns values to be inserted
sequentially into the table.  This can be thought of as a range
comprehension. If the body evaluates to nil that element is omitted.

For example,
  (fcollect [i 1 10 2]
    (when (not= i 3)
      (* i i)))
returns
  [1 25 49 81]

Supports an &into clause after the range to put results in an existing table.
Supports early termination with an &until clause."
  (assert (and (sequence? iter-tbl) (< 2 (length iter-tbl)))
          "expected range binding table")
  (seq-collect 'for iter-tbl value-expr ...))

(fn accumulate-impl [for? iter-tbl body ...]
  (assert (and (sequence? iter-tbl) (<= 4 (length iter-tbl)))
          "expected initial value and iterator binding table")
  (assert (not= nil body) "expected body expression")
  (assert (= nil ...)
          "expected exactly one body expression. Wrap multiple expressions with do")
  (let [[accum-var accum-init] iter-tbl
        iter (sym (if for? "for" "each"))] ; accumulate or faccumulate?
    `(do
       (var ,accum-var ,accum-init)
       (,iter ,[(unpack iter-tbl 3)]
              (set ,accum-var ,body))
       ,(if (list? accum-var)
          (list (sym :values) (unpack accum-var))
          accum-var))))

(fn accumulate* [iter-tbl body ...]
  "Accumulation macro.

It takes a binding table and an expression as its arguments.  In the binding
table, the first form starts out bound to the second value, which is an initial
accumulator. The rest are an iterator binding table in the format `each` takes.

It runs through the iterator in each step of which the given expression is
evaluated, and the accumulator is set to the value of the expression. It
eventually returns the final value of the accumulator.

For example,
  (accumulate [total 0
               _ n (pairs {:apple 2 :orange 3})]
    (+ total n))
returns 5"
  (accumulate-impl false iter-tbl body ...))

(fn faccumulate* [iter-tbl body ...]
  "Identical to accumulate, but after the accumulator the binding table is the
same as `for` instead of `each`. Like collect to fcollect, will iterate over a
numerical range like `for` rather than an iterator."
  (accumulate-impl true iter-tbl body ...))

(fn double-eval-safe? [x type]
  (or (= :number type) (= :string type) (= :boolean type)
      (and (sym? x) (not (multi-sym? x)))))

(fn partial* [f ...]
  "Return a function with all arguments partially applied to f."
  (assert f "expected a function to partially apply")
  (let [bindings []
        args []]
    (each [_ arg (ipairs [...])]
      (if (double-eval-safe? arg (type arg))
        (table.insert args arg)
        (let [name (gensym)]
          (table.insert bindings name)
          (table.insert bindings arg)
          (table.insert args name))))
    (let [body (list f (unpack args))]
      (table.insert body _VARARG)
      ;; only use the extra let if we need double-eval protection
      (if (= 0 (length bindings))
          `(fn [,_VARARG] ,body)
          `(let ,bindings
             (fn [,_VARARG] ,body))))))

(fn pick-args* [n f]
  "Create a function of arity n that applies its arguments to f.

For example,
  (pick-args 2 func)
expands to
  (fn [_0_ _1_] (func _0_ _1_))"
  (if (and _G.io _G.io.stderr)
      (_G.io.stderr:write
       "-- WARNING: pick-args is deprecated and will be removed in the future.\n"))
  (assert (and (= (type n) :number) (= n (math.floor n)) (<= 0 n))
          (.. "Expected n to be an integer literal >= 0, got " (tostring n)))
  (let [bindings []]
    (for [i 1 n]
      (tset bindings i (gensym)))
    `(fn ,bindings
       (,f ,(unpack bindings)))))

(fn pick-values* [n ...]
  "Evaluate to exactly n values.

For example,
  (pick-values 2 ...)
expands to
  (let [(_0_ _1_) ...]
    (values _0_ _1_))"
  (assert (and (= :number (type n)) (<= 0 n) (= n (math.floor n)))
          (.. "Expected n to be an integer >= 0, got " (tostring n)))
  (let [let-syms (list)
        let-values (if (= 1 (select "#" ...)) ... `(values ,...))]
    (for [i 1 n]
      (table.insert let-syms (gensym)))
    (if (= n 0) `(values)
        `(let [,let-syms ,let-values]
           (values ,(unpack let-syms))))))

(fn lambda* [...]
  "Function literal with nil-checked arguments.
Like `fn`, but will throw an exception if a declared argument is passed in as
nil, unless that argument's name begins with a question mark."
  (let [args [...]
        has-internal-name? (sym? (. args 1))
        arglist (if has-internal-name? (. args 2) (. args 1))
        docstring-position (if has-internal-name? 3 2)
        has-docstring? (and (< docstring-position (length args))
                            (= :string (type (. args docstring-position))))
        arity-check-position (- 4 (if has-internal-name? 0 1)
                                (if has-docstring? 0 1))
        empty-body? (< (length args) arity-check-position)]
    (fn check! [a]
      (if (table? a)
          (each [_ a (pairs a)]
            (check! a))
          (let [as (tostring a)]
            (and (not (as:match "^?")) (not= as "&") (not= as "_")
                 (not= as "...") (not= as "&as")))
          (table.insert args arity-check-position
                        `(_G.assert (not= nil ,a)
                                    ,(: "Missing argument %s on %s:%s" :format
                                        (tostring a)
                                        (or a.filename :unknown)
                                        (or a.line "?"))))))

    (assert (= :table (type arglist)) "expected arg list")
    (each [_ a (ipairs arglist)]
      (check! a))
    (if empty-body?
        (table.insert args (sym :nil)))
    `(fn ,(unpack args))))

(fn macro* [name ...]
  "Define a single macro."
  (assert (sym? name) "expected symbol for macro name")
  (local args [...])
  `(macros {,(tostring name) (fn ,(unpack args))}))

(fn macrodebug* [form return?]
  "Print the resulting form after performing macroexpansion.
With a second argument, returns expanded form as a string instead of printing."
  (let [handle (if return? `do `print)]
    `(,handle ,(view (macroexpand form _SCOPE)))))

(fn import-macros* [binding1 module-name1 ...]
  "Bind a table of macros from each macro module according to a binding form.
Each binding form can be either a symbol or a k/v destructuring table.
Example:
  (import-macros mymacros                 :my-macros    ; bind to symbol
                 {:macro1 alias : macro2} :proj.macros) ; import by name"
  (assert (and binding1 module-name1 (= 0 (% (select "#" ...) 2)))
          "expected even number of binding/modulename pairs")
  (for [i 1 (select "#" binding1 module-name1 ...) 2]
    ;; delegate the actual loading of the macros to the require-macros
    ;; special which already knows how to set up the compiler env and stuff.
    ;; this is weird because require-macros is deprecated but it works.
    (let [(binding modname) (select i binding1 module-name1 ...)
          scope (get-scope)
          ;; if the module-name is an expression (and not just a string) we
          ;; patch our expression to have the correct source filename so
          ;; require-macros can pass it down when resolving the module-name.
          expr `(import-macros ,modname)
          filename (if (list? modname) (. modname 1 :filename) :unknown)
          _ (tset expr :filename filename)
          macros* (_SPECIALS.require-macros expr scope {} binding)]
      (if (sym? binding)
          ;; bind whole table of macros to table bound to symbol
          (tset scope.macros (. binding 1) macros*)
          ;; 1-level table destructuring for importing individual macros
          (table? binding)
          (each [macro-name [import-key] (pairs binding)]
            (assert (= :function (type (. macros* macro-name)))
                    (.. "macro " macro-name " not found in module "
                        (tostring modname)))
            (tset scope.macros import-key (. macros* macro-name))))))
  nil)

{:-> ->*
 :->> ->>*
 :-?> -?>*
 :-?>> -?>>*
 :?. ?dot
 :doto doto*
 :when when*
 :with-open with-open*
 :collect collect*
 :icollect icollect*
 :fcollect fcollect*
 :accumulate accumulate*
 :faccumulate faccumulate*
 :partial partial*
 :lambda lambda*
 :λ lambda*
 :pick-args pick-args*
 :pick-values pick-values*
 :macro macro*
 :macrodebug macrodebug*
 :import-macros import-macros*}
]===]

local matchmacros = [===[
;;; Pattern matching
;; This is separated out so we can use the "core" macros during the
;; implementation of pattern matching.

(fn copy [t] (collect [k v (pairs t)] k v))

(fn with [opts k]
  (doto (copy opts) (tset k true)))

(fn without [opts k]
  (doto (copy opts) (tset k nil)))

(fn case-values [vals pattern unifications case-pattern opts]
  (let [condition `(and)
        bindings []]
    (each [i pat (ipairs pattern)]
      (let [(subcondition subbindings) (case-pattern [(. vals i)] pat
                                                      unifications (without opts :multival?))]
        (table.insert condition subcondition)
        (icollect [_ b (ipairs subbindings) &into bindings] b)))
    (values condition bindings)))

(fn case-table [val pattern unifications case-pattern opts]
  (let [condition `(and (= (_G.type ,val) :table))
        bindings []]
    (each [k pat (pairs pattern)]
      (if (= pat `&)
          (let [rest-pat (. pattern (+ k 1))
                rest-val `(select ,k ((or table.unpack _G.unpack) ,val))
                subcondition (case-table `(pick-values 1 ,rest-val)
                                          rest-pat unifications case-pattern
                                          (without opts :multival?))]
            (if (not (sym? rest-pat))
                (table.insert condition subcondition))
            (assert (= nil (. pattern (+ k 2)))
                    "expected & rest argument before last parameter")
            (table.insert bindings rest-pat)
            (table.insert bindings [rest-val]))
          (= k `&as)
          (do
            (table.insert bindings pat)
            (table.insert bindings val))
          (and (= :number (type k)) (= `&as pat))
          (do
            (assert (= nil (. pattern (+ k 2)))
                    "expected &as argument before last parameter")
            (table.insert bindings (. pattern (+ k 1)))
            (table.insert bindings val))
          ;; don't process the pattern right after &/&as; already got it
          (or (not= :number (type k)) (and (not= `&as (. pattern (- k 1)))
                                           (not= `& (. pattern (- k 1)))))
          (let [subval `(. ,val ,k)
                (subcondition subbindings) (case-pattern [subval] pat
                                                          unifications
                                                          (without opts :multival?))]
            (table.insert condition subcondition)
            (icollect [_ b (ipairs subbindings) &into bindings] b))))
    (values condition bindings)))

(fn case-guard [vals condition guards unifications case-pattern opts]
  (if (= 0 (length guards))
    (case-pattern vals condition unifications opts)
    (let [(pcondition bindings) (case-pattern vals condition unifications opts)
          condition `(and ,(unpack guards))]
       (values `(and ,pcondition
                     (let ,bindings
                       ,condition)) bindings))))

(fn symbols-in-pattern [pattern]
  "gives the set of symbols inside a pattern"
  (if (list? pattern)
      (let [result {}]
        (each [_ child-pattern (ipairs pattern)]
          (collect [name symbol (pairs (symbols-in-pattern child-pattern)) &into result]
            name symbol))
        result)
      (sym? pattern)
      (if (and (not= pattern `or)
               (not= pattern `where)
               (not= pattern `?)
               (not= pattern `nil))
          {(tostring pattern) pattern}
          {})
      (= (type pattern) :table)
      (let [result {}]
        (each [key-pattern value-pattern (pairs pattern)]
          (collect [name symbol (pairs (symbols-in-pattern key-pattern)) &into result]
            name symbol)
          (collect [name symbol (pairs (symbols-in-pattern value-pattern)) &into result]
            name symbol))
        result)
      {}))

(fn symbols-in-every-pattern [pattern-list infer-unification?]
  "gives a list of symbols that are present in every pattern in the list"
  (let [?symbols (accumulate [?symbols nil
                              _ pattern (ipairs pattern-list)]
                   (let [in-pattern (symbols-in-pattern pattern)]
                     (if ?symbols
                       (do
                         (each [name symbol (pairs ?symbols)]
                           (when (not (. in-pattern name))
                             (tset ?symbols name nil)))
                         ?symbols)
                       in-pattern)))]
    (icollect [_ symbol (pairs (or ?symbols {}))]
      (if (not (and infer-unification?
                    (in-scope? symbol)))
        symbol))))

(fn case-or [vals pattern guards unifications case-pattern opts]
  (let [pattern [(unpack pattern 2)]
        bindings (symbols-in-every-pattern pattern opts.infer-unification?)] ;; TODO opts.infer-unification instead of opts.unification?
    (if (= 0 (length bindings))
      ;; no bindings special case generates simple code
      (let [condition
            (icollect [i subpattern (ipairs pattern) &into `(or)]
              (let [(subcondition subbindings) (case-pattern vals subpattern unifications opts)]
                subcondition))]
        (values
          (if (= 0 (length guards))
            condition
            `(and ,condition ,(unpack guards)))
          []))
      ;; case with bindings is handled specially, and returns three values instead of two
      (let [matched? (gensym :matched?)
            bindings-mangled (icollect [_ binding (ipairs bindings)]
                               (gensym (tostring binding)))
            pre-bindings `(if)]
        (each [i subpattern (ipairs pattern)]
          (let [(subcondition subbindings) (case-guard vals subpattern guards {} case-pattern opts)]
            (table.insert pre-bindings subcondition)
            (table.insert pre-bindings `(let ,subbindings
                                          (values true ,(unpack bindings))))))
        (values matched?
                [`(,(unpack bindings)) `(values ,(unpack bindings-mangled))]
                [`(,matched? ,(unpack bindings-mangled)) pre-bindings])))))

(fn case-pattern [vals pattern unifications opts top-level?]
  "Take the AST of values and a single pattern and returns a condition
to determine if it matches as well as a list of bindings to
introduce for the duration of the body if it does match."

  ;; This function returns the following values (multival):
  ;; a "condition", which is an expression that determines whether the
  ;;   pattern should match,
  ;; a "bindings", which bind all of the symbols used in a pattern
  ;; an optional "pre-bindings", which is a list of bindings that happen
  ;;   before the condition and bindings are evaluated. These should only
  ;;   come from a (case-or). In this case there should be no recursion:
  ;;   the call stack should be case-condition > case-pattern > case-or
  ;;
  ;; Here are the expected flags in the opts table:
  ;;   :infer-unification? boolean - if the pattern should guess when to unify  (ie, match -> true, case -> false)
  ;;   :multival? boolean - if the pattern can contain multivals  (in order to disallow patterns like [(1 2)])
  ;;   :in-where? boolean - if the pattern is surrounded by (where)  (where opts into more pattern features)
  ;;   :legacy-guard-allowed? boolean - if the pattern should allow `(a ? b) patterns

  ;; we have to assume we're matching against multiple values here until we
  ;; know we're either in a multi-valued clause (in which case we know the #
  ;; of vals) or we're not, in which case we only care about the first one.
  (let [[val] vals]
    (if (and (sym? pattern)
             (or (= pattern `nil)
                 (and opts.infer-unification?
                      (in-scope? pattern)
                      (not= pattern `_))
                 (and opts.infer-unification?
                      (multi-sym? pattern)
                      (in-scope? (. (multi-sym? pattern) 1)))))
        (values `(= ,val ,pattern) [])
        ;; unify a local we've seen already
        (and (sym? pattern) (. unifications (tostring pattern)))
        (values `(= ,(. unifications (tostring pattern)) ,val) [])
        ;; bind a fresh local
        (sym? pattern)
        (let [wildcard? (: (tostring pattern) :find "^_")]
          (if (not wildcard?) (tset unifications (tostring pattern) val))
          (values (if (or wildcard? (string.find (tostring pattern) "^?")) true
                      `(not= ,(sym :nil) ,val)) [pattern val]))
        ;; opt-in unify with (=)
        (and (list? pattern)
             (= (. pattern 1) `=)
             (sym? (. pattern 2)))
        (let [bind (. pattern 2)]
          (assert-compile (= 2 (length pattern)) "(=) should take only one argument" pattern)
          (assert-compile (not opts.infer-unification?) "(=) cannot be used inside of match" pattern)
          (assert-compile opts.in-where? "(=) must be used in (where) patterns" pattern)
          (assert-compile (and (sym? bind) (not= bind `nil) "= has to bind to a symbol" bind))
          (values `(= ,val ,bind) []))
        ;; where-or clause
        (and (list? pattern) (= (. pattern 1) `where) (list? (. pattern 2)) (= (. pattern 2 1) `or))
        (do
          (assert-compile top-level? "can't nest (where) pattern" pattern)
          (case-or vals (. pattern 2) [(unpack pattern 3)] unifications case-pattern (with opts :in-where?)))
        ;; where clause
        (and (list? pattern) (= (. pattern 1) `where))
        (do
          (assert-compile top-level? "can't nest (where) pattern" pattern)
          (case-guard vals (. pattern 2) [(unpack pattern 3)] unifications case-pattern (with opts :in-where?)))
        ;; or clause (not allowed on its own)
        (and (list? pattern) (= (. pattern 1) `or))
        (do
          (assert-compile top-level? "can't nest (or) pattern" pattern)
          ;; This assertion can be removed to make patterns more permissive
          (assert-compile false "(or) must be used in (where) patterns" pattern)
          (case-or vals pattern [] unifications case-pattern opts))
        ;; guard clause
        (and (list? pattern) (= (. pattern 2) `?))
        (do
          (assert-compile opts.legacy-guard-allowed? "legacy guard clause not supported in case" pattern)
          (case-guard vals (. pattern 1) [(unpack pattern 3)] unifications case-pattern opts))
        ;; multi-valued patterns (represented as lists)
        (list? pattern)
        (do
          (assert-compile opts.multival? "can't nest multi-value destructuring" pattern)
          (case-values vals pattern unifications case-pattern opts))
        ;; table patterns
        (= (type pattern) :table)
        (case-table val pattern unifications case-pattern opts)
        ;; literal value
        (values `(= ,val ,pattern) []))))

(fn add-pre-bindings [out pre-bindings]
  "Decide when to switch from the current `if` AST to a new one"
  (if pre-bindings
      ;; `out` no longer needs to grow.
      ;; Instead, a new tail `if` AST is introduced, which is where the rest of
      ;; the clauses will get appended. This way, all future clauses have the
      ;; pre-bindings in scope.
      (let [tail `(if)]
        (table.insert out true)
        (table.insert out `(let ,pre-bindings ,tail))
        tail)
      ;; otherwise, keep growing the current `if` AST.
      out))

(fn case-condition [vals clauses match?]
  "Construct the actual `if` AST for the given match values and clauses."
  ;; root is the original `if` AST.
  ;; out is the `if` AST that is currently being grown.
  (let [root `(if)]
    (faccumulate [out root
                  i 1 (length clauses) 2]
      (let [pattern (. clauses i)
            body (. clauses (+ i 1))
            (condition bindings pre-bindings) (case-pattern vals pattern {}
                                                            {:multival? true
                                                             :infer-unification? match?
                                                             :legacy-guard-allowed? match?}
                                                            true)
            out (add-pre-bindings out pre-bindings)]
        ;; grow the `if` AST by one extra condition
        (table.insert out condition)
        (table.insert out `(let ,bindings
                            ,body))
        out))
    root))

(fn count-case-multival [pattern]
  "Identify the amount of multival values that a pattern requires."
  (if (and (list? pattern) (= (. pattern 2) `?))
      (count-case-multival (. pattern 1))
      (and (list? pattern) (= (. pattern 1) `where))
      (count-case-multival (. pattern 2))
      (and (list? pattern) (= (. pattern 1) `or))
      (accumulate [longest 0
                   _ child-pattern (ipairs pattern)]
        (math.max longest (count-case-multival child-pattern)))
      (list? pattern)
      (length pattern)
      1))

(fn case-val-syms [clauses]
  "What is the length of the largest multi-valued clause? return a list of that
many gensyms."
  (let [patterns (fcollect [i 1 (length clauses) 2]
                   (. clauses i))
        sym-count (accumulate [longest 0
                               _ pattern (ipairs patterns)]
                    (math.max longest (count-case-multival pattern)))]
    (fcollect [i 1 sym-count &into (list)]
      (gensym))))

(fn case-impl [match? val ...]
  "The shared implementation of case and match."
  (assert (not= val nil) "missing subject")
  (assert (= 0 (math.fmod (select :# ...) 2))
          "expected even number of pattern/body pairs")
  (assert (not= 0 (select :# ...))
          "expected at least one pattern/body pair")
  (let [clauses [...]
        vals (case-val-syms clauses)]
    ;; protect against multiple evaluation of the value, bind against as
    ;; many values as we ever match against in the clauses.
    (list `let [vals val] (case-condition vals clauses match?))))

(fn case* [val ...]
  "Perform pattern matching on val. See reference for details.

Syntax:

(case data-expression
  pattern body
  (where pattern guards*) body
  (or pattern patterns*) body
  (where (or pattern patterns*) guards*) body
  ;; legacy:
  (pattern ? guards*) body)"
  (case-impl false val ...))

(fn match* [val ...]
  "Perform pattern matching on val, automatically unifying on variables in
local scope. See reference for details.

Syntax:

(match data-expression
  pattern body
  (where pattern guards*) body
  (or pattern patterns*) body
  (where (or pattern patterns*) guards*) body
  ;; legacy:
  (pattern ? guards*) body)"
  (case-impl true val ...))

(fn case-try-step [how expr else pattern body ...]
  (if (= nil pattern body)
      expr
      ;; unlike regular match, we can't know how many values the value
      ;; might evaluate to, so we have to capture them all in ... via IIFE
      ;; to avoid double-evaluation.
      `((fn [...]
          (,how ...
            ,pattern ,(case-try-step how body else ...)
            ,(unpack else)))
        ,expr)))

(fn case-try-impl [how expr pattern body ...]
  (let [clauses [pattern body ...]
        last (. clauses (length clauses))
        catch (if (= `catch (and (= :table (type last)) (. last 1)))
                 (let [[_ & e] (table.remove clauses)] e) ; remove `catch sym
                 [`_# `...])]
    (assert (= 0 (math.fmod (length clauses) 2))
            "expected every pattern to have a body")
    (assert (= 0 (math.fmod (length catch) 2))
            "expected every catch pattern to have a body")
    (case-try-step how expr catch (unpack clauses))))

(fn case-try* [expr pattern body ...]
  "Perform chained pattern matching for a sequence of steps which might fail.

The values from the initial expression are matched against the first pattern.
If they match, the first body is evaluated and its values are matched against
the second pattern, etc.

If there is a (catch pat1 body1 pat2 body2 ...) form at the end, any mismatch
from the steps will be tried against these patterns in sequence as a fallback
just like a normal match. If there is no catch, the mismatched values will be
returned as the value of the entire expression."
  (case-try-impl `case expr pattern body ...))

(fn match-try* [expr pattern body ...]
  "Perform chained pattern matching for a sequence of steps which might fail.

The values from the initial expression are matched against the first pattern.
If they match, the first body is evaluated and its values are matched against
the second pattern, etc.

If there is a (catch pat1 body1 pat2 body2 ...) form at the end, any mismatch
from the steps will be tried against these patterns in sequence as a fallback
just like a normal match. If there is no catch, the mismatched values will be
returned as the value of the entire expression."
  (case-try-impl `match expr pattern body ...))

{:case case*
 :case-try case-try*
 :match match*
 :match-try match-try*}
]===]
do
    -- docstrings rely on having a place to "put" metadata; we use the module
    -- system for that. but if you try to require the module while it's being
    -- loaded, you get a stack overflow. so we fake out the module for the
    -- purposes of boostrapping the built-in macros here.
    local moduleName = "__fennel-bootstrap__"
    package.preload[moduleName] = function() return module end
    local env = specials.makeCompilerEnv(nil, compiler.scopes.compiler, {})
    env["assert-compile"] = assert
    local opts = { env = env,
                   scope = compiler.makeScope(compiler.scopes.compiler),
                   useMetadata = true,
                   filename = "src/fennel/macros.fnl",
                   moduleName = moduleName }
    local macros = eval(stdmacros, opts)
    for k,v in pairs(macros) do compiler.scopes.global.macros[k] = v end
    local matches = eval(matchmacros, opts)
    for k,v in pairs(matches) do compiler.scopes.global.macros[k] = v end
    package.preload[moduleName] = nil
end
compiler.scopes.global.macros['λ'] = compiler.scopes.global.macros['lambda']

return module
