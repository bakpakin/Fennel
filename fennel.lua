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

--
-- Main Types and support functions
--

local SYMBOL_MT = { 'SYMBOL',
    __tostring = function (self)
        return self[1]
    end
}
local LIST_MT = { 'LIST',
    __tostring = function (self)
        local strs = {}
        for _, s in ipairs(self) do
            table.insert(strs, tostring(s))
        end
        return '(' .. table.concat(strs, ', ', 1, #self) .. ')'
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
    return setmetatable({...}, LIST_MT)
end

-- Create a new symbol
local function sym(str, scope, line, filename)
    return setmetatable({ str, scope = scope, line = line, filename = filename},
        SYMBOL_MT)
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

--
-- Parser
--

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
local function stringStream(str)
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
local function parser(getbyte, filename)

    -- Stack of unfinished values
    local stack = {}

    -- Provide one character buffer and keep
    -- track of current line
    local line = 1
    local lastb
    local function ungetb(ub)
        if ub == 10 then line = line - 1 end
        lastb = ub
    end
    local function getb()
        local r
        if lastb then
            r, lastb = lastb, nil
        else
            r = getbyte()
        end
        if r == 10 then line = line + 1 end
        return r
    end

    -- Parse stream
    return function ()

        -- Dispatch when we complete a value
        local done, retval
        local function dispatch(v)
            if #stack == 0 then
                retval = v
                done = true
            else
                table.insert(stack[#stack], v)
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
                local l = setmetatable({closer = delims[b], n = 0}, LIST_MT)
                l.line, l.filename = line, filename
                table.insert(stack, l)
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
                    for i = 1, #last do
                        val[i] = last[i]
                    end
                else -- }
                    if #last % 2 ~= 0 then
                        error('expected even number of values in table literal'
                                  .. ' on line ' .. line .. ' of ' .. filename)
                    end
                    val = {}
                    for i = 1, #last, 2 do
                        val[last[i]] = last[i + 1]
                    end
                end
                stack[#stack] = nil
                dispatch(val)
            elseif b == 34 or b == 39 then -- Quoted string
                local start = b
                local state = "base"
                local chars = {start}
                repeat
                    b = getb()
                    chars[#chars + 1] = b
                    if state == "base" then
                        if b == 92 then
                            state = "backslash"
                        elseif b == start then
                            state = "done"
                        end
                    else
                        -- state == "backslash"
                        state = "base"
                    end
                until not b or (state == "done")
                if not b then error 'unexpected end of source' end
                local raw = string.char(unpack(chars))
                local loadFn = loadCode(('return %s'):format(raw), nil, filename)
                dispatch(loadFn())
            else -- Try symbol
                local chars = {}
                repeat
                    chars[#chars + 1] = b
                    b = getb()
                until not b or not issymbolchar(b)
                if b then ungetb(b) end
                local rawstr = string.char(unpack(chars))
                if rawstr == 'true' then dispatch(true)
                elseif rawstr == 'false' then dispatch(false)
                elseif rawstr == '...' then dispatch(VARARG)
                elseif rawstr:match('^:.+$') then -- keyword style strings
                    dispatch(rawstr:sub(2))
                else
                    local forceNumber = rawstr:match('^%d')
                    local x
                    if forceNumber then
                        x = tonumber(rawstr) or error('could not read token "' .. rawstr .. '"')
                    else
                        x = tonumber(rawstr) or sym(rawstr, nil, line, filename)
                    end
                    dispatch(x)
                end
            end
        until done
        return true, retval
    end
end

--
-- Compilation
--

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
        vars = {}, -- whitelist for whether set works on a local
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

-- Assert a condition and raise a compile error with line numbers. The ast arg
-- should be unmodified so that its first element is the form being called.
local function assertCompile(condition, msg, ast)
    -- if we use regular `assert' we can't provide the `level' argument of zero
    if not condition then
        error(string.format("Compile error in `%s' %s:%s: %s", ast[1][1],
                            ast.filename or "unknown", ast.line or '?', msg), 0)
    end
    return condition
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

-- Allow printing a string to Lua
local function serializeString(str)
    local s = ("(%q)"):format(str):gsub('\n', 'n'):gsub("[\128-\255]", function(c)
        return "\\" .. c:byte()
    end)
    return s
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

-- Creates Lua-friendly symbol from a single symbol by mangling it.
local function symMangle(symb)
    if luaKeywords[symb] then
        symb = '_' .. symb
    end
    return symb:gsub('[^%w_]', function(c)
        return ('_%02x'):format(c:byte())
    end)
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
                ret = ret .. '[' .. serializeString(parts[i]) .. ']'
            else
                ret = stringMangle(parts[i], scope)
            end
        end
        if ret then
            if noMulti then error 'did not expect a multi symbol' end
            return ret
        end
    end
    mangling = symMangle(mangling)
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

-- Flatten a tree of indented Lua source code lines.
-- Tab is what is used to indent a block.
local function flattenChunkPretty(chunk, tab, depth)
    if type(chunk) == 'string' then return chunk end
    for i = 1, #chunk do
        local sub = flattenChunkPretty(chunk[i], tab, depth + 1)
        if depth > 2 then sub = tab .. sub:gsub('\n', '\n' .. tab) end
        chunk[i] = sub
    end
    return table.concat(chunk, '\n')
end

-- Place strings from chunk inside out table in a place that corresponds
-- as best possible with its line number data from parser/emit.
local function flattenChunkTables(chunk, out, lastLine, file)
    if type(chunk) == 'string' then
        if out[lastLine] then
            out[lastLine] = out[lastLine] .. " " .. chunk
        else
            out[lastLine] = chunk
        end
    else
        if file == chunk.file then -- don't bump line unless file matches
            lastLine = math.max(lastLine, chunk.line or 0)
        end
        for _, line in ipairs(chunk) do
            lastLine = flattenChunkTables(line, out, lastLine, file)
        end
    end
    return lastLine
end

-- Turn a chunk into a single code string, either with indentation if given
-- or by attempting to preserve line numbering.
local function flattenChunk(chunk, tab)
    if tab then
        return flattenChunkPretty(chunk, tab, 0)
    else
        local out = {}
        local lineCount = flattenChunkTables(chunk, out, 1, chunk.file)
        -- fill in the gaps
        for i = 1, lineCount do
            if not out[i] then out[i] = "" end
        end
        return table.concat(out, "\n")
    end
end

-- Convert expressions to Lua string
local function exprs1(exprs)
    local t = {}
    for _, e in ipairs(exprs) do
        t[#t + 1] = e[1]
    end
    return table.concat(t, ', ')
end

local function emit(chunk, out, ast)
    table.insert(chunk, {out, line = ast and ast.line})
end

-- Compile sideffects for a chunk
local function keepSideEffects(exprs, chunk, start, ast)
    start = start or 1
    for j = start, #exprs do
        local se = exprs[j]
        if se.type == 'expression' then
            emit(chunk, ('do local _ = %s end'):format(tostring(se)), ast)
        elseif se.type == 'statement' then
            emit(chunk, tostring(se), ast)
        end
    end
end

-- Does some common handling of returns and register
-- targets for special forms. Also ensures a list expression
-- has an accetable number of expressions if opts contains the
-- "nval" option.
local function handleCompileOpts(exprs, parent, opts, ast)
    if opts.nval then
        local n = opts.nval
        if n ~= #exprs then
            local len = #exprs
            if len > n then
                -- Drop extra
                keepSideEffects(exprs, parent, n + 1, ast)
                for i = n, len do
                    exprs[i] = nil
                end
            else
                -- Pad with nils
                for i = #exprs + 1, n do
                    exprs[i] = expr('nil', 'literal')
                end
            end
        end
    end
    if opts.tail then
        emit(parent, ('return %s'):format(exprs1(exprs)), ast)
    end
    if opts.target then
        emit(parent, ('%s = %s'):format(opts.target, exprs1(exprs)), ast)
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
local function compile1(ast, scope, parent, opts)
    opts = opts or {}
    local exprs = {}

    -- Compile the form
    if isList(ast) then
        -- Function call or special form
        local len = #ast
        assert(len > 0, "expected a function to call")
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
            -- Unless the special form explicitely handles the target, tail, and nval properties,
            -- (indicated via the 'returned' flag, handle these options.
            if not exprs.returned then
                exprs = handleCompileOpts(exprs, parent, opts, ast)
            elseif opts.tail or opts.target then
                exprs = {}
            end
            exprs.returned = true
            return exprs
        else
            -- Function call
            local fargs = {}
            local fcallee = compile1(ast[1], scope, parent, {
                nval = 1
            })[1]
            assert(fcallee.type ~= 'literal', 'cannot call literal value')
            fcallee = tostring(fcallee)
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
                    keepSideEffects(subexprs, parent, 2, ast[i])
                end
            end
            local call = ('%s(%s)'):format(tostring(fcallee), exprs1(fargs))
            exprs = handleCompileOpts({expr(call, 'statement')}, parent, opts, ast)
        end
    elseif isVarg(ast) then
        exprs = handleCompileOpts({expr('...', 'varg')}, parent, opts, ast)
    elseif isSym(ast) then
        local e
        -- Handle nil as special symbol - it resolves to the nil literal rather than
        -- being unmangled. Alternatively, we could remove it from the lua keywords table.
        if ast[1] == 'nil' then
            e = expr('nil', 'literal')
        else
            e = expr(stringMangle(ast[1], scope), 'sym')
        end
        exprs = handleCompileOpts({e}, parent, opts, ast)
    elseif type(ast) == 'nil' or type(ast) == 'boolean' then
        exprs = handleCompileOpts({expr(tostring(ast), 'literal')}, parent, opts)
    elseif type(ast) == 'number' then
        local n = ('%.17g'):format(ast)
        exprs = handleCompileOpts({expr(n, 'literal')}, parent, opts)
    elseif type(ast) == 'string' then
        local s = serializeString(ast)
        exprs = handleCompileOpts({expr(s, 'literal')}, parent, opts)
    elseif type(ast) == 'table' then
        local buffer = {}
        for i = 1, #ast do -- Write numeric keyed values.
            buffer[#buffer + 1] = tostring(compile1(ast[i], scope, parent, {nval = 1})[1])
        end
        local keys = {}
        for k, _ in pairs(ast) do -- Write other keys.
            if type(k) ~= 'number' or math.floor(k) ~= k or k < 1 or k > #ast then
                table.insert(keys, { tostring(compile1(k, scope, parent, {nval = 1})[1]), k })
            end
        end
        table.sort(keys, function (a, b) return a[1] < b[1] end)
        for _, k in ipairs(keys) do
            local v = ast[k[2]]
            buffer[#buffer + 1] = ('[%s] = %s'):format(
                k[1], tostring(compile1(v, scope, parent, {nval = 1})[1]))
        end
        local tbl = '({' .. table.concat(buffer, ', ') ..'})'
        exprs = handleCompileOpts({expr(tbl, 'expression')}, parent, opts, ast)
    else
        error('could not compile value of type ' .. type(ast))
    end
    exprs.returned = true
    return exprs
end

-- SPECIALS --

-- For statements and expressions, put the value in a local to avoid
-- double-evaluating it.
local function once(val, ast, scope, parent)
    if val.type == 'statement' or val.type == 'expression' then
        local s = gensym(scope)
        emit(parent, ('local %s = %s'):format(s, tostring(val)), ast)
        return expr(s, 'sym')
    else
        return val
    end
end

-- Implements destructuring for forms like let, bindings, etc.
local function destructure1(left, rightexprs, scope, parent, nonlocal)
    local setter = nonlocal and "%s = %s" or "local %s = %s"
    if isSym(left) and left[1] ~= "nil" then
        emit(parent, (setter):
                 format(stringMangle(left[1], scope), exprs1(rightexprs)), left)
    elseif isTable(left) then -- table destructuring
        local s = gensym(scope)
        emit(parent, (setter):format(s, exprs1(rightexprs)), left)
        for i, v in ipairs(left) do
            if isSym(left[i]) and left[i][1] == "&" then
                assertCompile(not left[i+2],
                              "expected rest argument in final position", left)
                local subexpr = expr(('{(table.unpack or unpack)(%s, %s)}'):format(s, i),
                    'expression')
                destructure1(left[i+1], {subexpr}, scope, parent, nonlocal)
                return
            else
                local subexpr = expr(('%s[%d]'):format(s, i), 'expression')
                destructure1(v, {subexpr}, scope, parent, nonlocal)
            end
        end
    elseif isList(left)  then -- values destructuring
        local leftNames, tables = {}, {}
        for i, name in ipairs(left) do
            local symname
            if isSym(name)  then -- binding directly to a name
                symname = stringMangle(name[1], scope)
            else -- further destructuring of tables inside values
                symname = gensym(scope)
                tables[i] = {name, expr(symname, 'sym')}
            end
            table.insert(leftNames, symname)
        end
        emit(parent, (setter):
                 format(table.concat(leftNames, ", "), exprs1(rightexprs)), left)
        for _, pair in pairs(tables) do -- recurse if left-side tables found
            destructure1(pair[1], {pair[2]}, scope, parent, nonlocal)
        end
    else
        error('unable to destructure ' .. tostring(left))
    end
end

local function destructure(left, right, scope, parent, nonlocal)
    local rexps = compile1(right, scope, parent)
    local ret = destructure1(left, rexps, scope, parent, nonlocal)
    return ret
end

-- Unlike most expressions and specials, 'values' resolves with multiple
-- values, one for each argument, allowing multiple return values. The last
-- expression, can return multiple arguments as well, allowing for more than the number
-- of expected arguments.
local function values(ast, scope, parent)
    local len = #ast
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
            keepSideEffects(subexprs, parent, 2, ast)
        end
    end
    return exprs
end

-- Compile a list of forms for side effects
local function compileDo(ast, scope, parent, start)
    start = start or 2
    local len = #ast
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
                local s = gensym(scope)
                syms[i] = s
                retexprs[i] = expr(s, 'sym')
            end
            outerTarget = table.concat(syms, ', ')
            emit(parent, ('local %s'):format(outerTarget), ast)
            emit(parent, 'do', ast)
        else
            -- We will use an IIFE for the do
            local fname = gensym(scope)
            emit(parent, ('local function %s()'):format(fname), ast)
            retexprs = expr(fname .. '()', 'statement')
            outerTail = true
            outerTarget = nil
        end
    else
        emit(parent, 'do', ast)
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
                nval = i ~= len and 0 or opts.nval,
                tail = i == len and outerTail or nil,
                target = i == len and outerTarget or nil
            }
            local subexprs = compile1(ast[i], subScope, chunk, subopts)
            if i ~= len then
                keepSideEffects(subexprs, parent, nil, ast[i])
            end
        end
    end
    emit(parent, chunk, ast)
    emit(parent, 'end', ast)
    return retexprs
end

SPECIALS['do'] = doImpl
SPECIALS['values'] = values

-- The fn special declares a function. Syntax is similar to other lisps;
-- (fn optional-name [arg ...] (body))
-- Further decoration such as docstrings, meta info, and multibody functions a possibility.
SPECIALS['fn'] = function(ast, scope, parent)
    local fScope = makeScope(scope)
    local fChunk = {}
    local index = 2
    local fnName = isSym(ast[index])
    local isLocalFn
    if fnName and fnName[1] ~= 'nil' then
        isLocalFn = not isMultiSym(fnName[1])
        fnName = stringMangle(fnName[1], scope)
        index = index + 1
    else
        isLocalFn = true
        fnName = gensym(scope)
    end
    local argList = assertCompile(isTable(ast[index]),
                                  'expected vector arg list [a b ...]', ast)
    local argNameList = {}
    for i = 1, #argList do
        if isVarg(argList[i]) then
            argNameList[i] = '...'
            fScope.vararg = true
        elseif isSym(argList[i]) and argList[i][1] ~= "nil" then
            argNameList[i] = stringMangle(argList[i][1], fScope)
        else
            assertCompile(false, 'expected symbol for function parameter', ast)
        end
    end
    for i = index + 1, #ast do
        compile1(ast[i], fScope, fChunk, {
            tail = i == #ast,
            nval = i ~= #ast and 0 or nil
        })
    end
    if isLocalFn then
        emit(parent, ('local function %s(%s)')
                 :format(fnName, table.concat(argNameList, ', ')), ast)
    else
        emit(parent, ('%s = function(%s)')
                 :format(fnName, table.concat(argNameList, ', ')), ast)
    end
    emit(parent, fChunk, ast)
    emit(parent, 'end', ast)
    return fnName
end

SPECIALS['luaexpr'] = function(ast)
    return tostring(ast[2])
end

SPECIALS['luastatement'] = function(ast)
    return expr(tostring(ast[2]), 'statement')
end

SPECIALS['lambda'] = function(ast, scope, parent)
    assertCompile(#ast >= 3, "missing body expression", ast)
    local arglist = ast[2]
    local checks = {}
    for _, arg in ipairs(arglist) do
        if not arg[1]:match("^?") and arg[1] ~= "..." then
            table.insert(checks, 1,
                         list(sym("assert", ast.line, ast.filename),
                              list(sym('~='), sym('nil'), arg),
                              string.format("Missing argument %s on %s:%s",
                                            arg[1], ast.filename or 'unknown', ast.line or '?')))
        end
    end
    local new = list(sym("lambda", ast[1].line, ast[1].filename),
                     arglist, unpack(checks))
    new.line, new.filename = ast.line, ast.filename
    for i = 3, #ast do
        table.insert(new, ast[i])
    end
    return SPECIALS.fn(new, scope, parent)
end
SPECIALS['λ'] = SPECIALS['lambda']

SPECIALS['partial'] = function(ast, scope, parent)
    local f = ast[2]
    local innerArgs = {}
    for i = 3, #ast do table.insert(innerArgs, ast[i]) end
    table.insert(innerArgs, VARARG)
    local new = list(sym("fn", ast[1].line, ast[1].filename),
                     {VARARG}, list(f, unpack(innerArgs)))
    new.line, new.filename = ast.line, ast.filename
    return SPECIALS.fn(new, scope, parent)
end

SPECIALS['special'] = function(ast, scope, parent)
    assertCompile(scopeInside(COMPILER_SCOPE, scope),
                  "can only declare special forms in 'eval-compiler'", ast)
    assertCompile(isSym(ast[2]), "expected symbol for name of special form", ast)
    local specname = tostring(ast[2])
    local spec = SPECIALS.fn(ast, scope, parent, {nval = 1})
    emit(parent, ('_SPECIALS[%q] = %s'):format(specname, tostring(spec)), ast)
end

SPECIALS['macro'] = function(ast, scope, parent, opts)
    assertCompile(scopeInside(COMPILER_SCOPE, scope),
                  "can only declare macros in 'eval-compiler'", ast)
    local macroName = SPECIALS.fn(ast, scope, parent, opts)
    local unmangled = ast[2][1]
    local s = gensym(scope)

    emit(parent, ('local function %s(ast, scope, chunk, opts)'):format(s), ast)
    emit(parent, {'local unpack = table.unpack or unpack',
                  ('return _FNL.compile1(%s(unpack(ast, 2, #ast)), scope, chunk, opts)')
                      :format(macroName)}, ast)
    emit(parent, 'end', ast)
    emit(parent, ('_SPECIALS[%q] = %s'):format(unmangled, s), ast)
end

-- Wrapper for table access
SPECIALS['.'] = function(ast, scope, parent)
    local len = #ast
    assertCompile(len > 1, "expected table argument", ast)
    local lhs = compile1(ast[2], scope, parent, {nval = 1})
    if len == 2 then
        return tostring(lhs[1])
    else
        local indices = {}
        for i = 3, len do
            table.insert(indices, tostring(compile1(ast[i], scope, parent, {nval = 1})[1]))
        end
        return tostring(lhs[1]) .. '[' .. table.concat(indices, '][') .. ']'
    end
end

-- TODO: referring to a global can put an entry in the manglings table
local function inScope(name, scope)
    return scope.manglings[name] or scope.parent and inScope(name, scope.parent)
end

SPECIALS['global'] = function(ast, scope, parent)
    assertCompile(#ast == 3, "expected name and value", ast)
    local target = ast[2][1]
    local parts = isMultiSym(target)
    if parts then target = parts[1] end
    assertCompile(not inScope(target, scope),
                  ("tried to set local %s"):format(tostring(target)), ast)
    destructure(ast[2], ast[3], scope, parent, true)
    return 'nil'
end

local function isVar(name, scope)
    return scope.vars[name] or scope.parent and isVar(name, scope.parent)
end

SPECIALS['set'] = function(ast, scope, parent)
    assertCompile(#ast == 3, "expected name and value", ast)
    local target = ast[2][1]
    local parts = isMultiSym(target)
    if parts then target = parts[1] end
    assertCompile(isVar(target, scope) or parts,
                  ("expected local var %s"):format(tostring(target)), ast)
    destructure(ast[2], ast[3], scope, parent, true)
    return 'nil'
end

SPECIALS['local'] = function(ast, scope, parent)
    assertCompile(#ast == 3, "expected name and value", ast)
    destructure(ast[2], ast[3], scope, parent, false)
    return 'nil'
end

local function scopeVars(v, scope)
    if isSym(v) then
        scope.vars[v[1]] = true
    else
        for _, v2 in ipairs(v) do scopeVars(v2, scope) end
    end
end

SPECIALS['var'] = function(ast, scope, parent)
    assertCompile(#ast == 3, "expected name and value", ast)
    scopeVars(ast[2], scope)
    destructure(ast[2], ast[3], scope, parent, false)
    return 'nil'
end

SPECIALS['let'] = function(ast, scope, parent, opts)
    local bindings = ast[2]
    assertCompile(isList(bindings) or isTable(bindings),
                  'expected table for destructuring', ast)
    assertCompile(#bindings % 2 == 0,
                  'expected even number of name/value bindings', ast)
    assertCompile(#ast >= 3, 'missing body expression', ast)
    local subScope = makeScope(scope)
    local subChunk = {}
    for i = 1, #bindings, 2 do
        destructure(bindings[i], bindings[i + 1], subScope, subChunk)
    end
    return doImpl(ast, scope, parent, opts, 3, subChunk, subScope)
end

-- For setting items in a table
SPECIALS['tset'] = function(ast, scope, parent)
    local root = compile1(ast[2], scope, parent, {nval = 1})[1]
    local keys = {}
    for i = 3, #ast - 1 do
        local key = compile1(ast[i], scope, parent, {nval = 1})[1]
        keys[#keys + 1] = tostring(key)
    end
    local value = compile1(ast[#ast], scope, parent, {nval = 1})[1]
    emit(parent, ('%s[%s] = %s'):format(tostring(root),
                                        table.concat(keys, ']['),
                                        tostring(value)), ast)
    return 'nil'
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
    for i = 2, #ast - 1, 2 do
        local condchunk = {}
        local cond =  compile1(ast[i], doScope, condchunk, {nval = 1})
        local branch = compileBody(i + 1)
        branch.cond = cond
        branch.condchunk = condchunk
        table.insert(branches, branch)
    end
    local hasElse = #ast > 3 and ast.n % 2 == 0
    if hasElse then elseBranch = compileBody(#ast) end

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
        emit(parent, ('local function %s()'):format(tostring(s)), ast)
        emit(parent, buffer, ast)
        emit(parent, 'end', ast)
        return expr(('%s()'):format(tostring(s)), 'statement')
    elseif wrapper == 'none' then
        -- Splice result right into code
        for i = 1, #buffer do
            emit(parent, buffer[i], ast)
        end
        return {returned = true}
    end
end

-- (each [k v (pairs t)] body...) => []
SPECIALS['each'] = function(ast, scope, parent)
    local binding = assertCompile(isTable(ast[2]), 'expected binding table', ast)
    local iter = table.remove(binding, #binding) -- last item is iterator call
    local bindVars = {}
    for _, v in ipairs(binding) do
        assertCompile(isSym(v), 'expected iterator symbol', ast)
        table.insert(bindVars, stringMangle(v[1], scope))
    end
    emit(parent, ('for %s in %s do'):format(
             table.concat(bindVars, ', '),
             tostring(compile1(iter, scope, parent, {nval = 1})[1])), ast)
    local chunk = {}
    compileDo(ast, scope, chunk, 3)
    emit(parent, chunk, ast)
    emit(parent, 'end', ast)
    return 'nil'
end

-- (while condition body...) => []
SPECIALS['while'] = function(ast, scope, parent)
    local len1 = #parent
    local condition = compile1(ast[2], scope, parent, {nval = 1})[1]
    local len2 = #parent
    local subChunk = {}
    if len1 ~= len2 then
        -- Compound condition
        emit(parent, 'while true do', ast)
        -- Move new compilation to subchunk
        for i = len1 + 1, len2 do
            subChunk[#subChunk + 1] = parent[i]
            parent[i] = nil
        end
        emit(parent, ('if %s then break end'):format(condition[1]), ast)
    else
        -- Simple condition
        emit(parent, 'while ' .. tostring(condition) .. ' do', ast)
    end
    compileDo(ast, makeScope(scope), subChunk, 3)
    emit(parent, subChunk, ast)
    emit(parent, 'end', ast)
    return 'nil'
end

SPECIALS['for'] = function(ast, scope, parent)
    local ranges = assertCompile(isTable(ast[2]), 'expected binding table', ast)
    local bindingSym = assertCompile(isSym(table.remove(ast[2], 1)),
                                     'expected iterator symbol', ast)
    local rangeArgs = {}
    for i = 1, math.min(#ranges, 3) do
        rangeArgs[i] = tostring(compile1(ranges[i], scope, parent, {nval = 1})[1])
    end
    emit(parent, ('for %s = %s do'):format(
             stringMangle(bindingSym[1], scope),
             table.concat(rangeArgs, ', ')), ast)
    local chunk = {}
    compileDo(ast, scope, chunk, 3)
    emit(parent, chunk, ast)
    emit(parent, 'end', ast)
    return 'nil'
end

SPECIALS[':'] = function(ast, scope, parent)
    assertCompile(#ast >= 3, 'expected at least 3 arguments', ast)
    -- Compile object
    local objectexpr = once(compile1(ast[2], scope, parent, {nval = 1})[1],
                            ast[2], scope, parent)
    -- Compile method selector
    local methodexpr = compile1(ast[3], scope, parent, {nval = 1})[1]
    -- Compile arguments
    local args = {}
    for i = 4, #ast do
        local subexprs = compile1(ast[i], scope, parent, {
            nval = i ~= #ast and 1 or nil
        })
        for j = 1, #subexprs do
            args[#args + 1] = tostring(subexprs[j])
        end
    end
    -- Make object first argument
    table.insert(args, 1, tostring(objectexpr))
    -- Wrap literals in parens (strings)
    local fstring = objectexpr.type == 'literal'
        and '(%s)[%s](%s)'
        or '%s[%s](%s)'
    return expr(fstring:format(
        tostring(objectexpr),
        tostring(methodexpr),
        table.concat(args, ', ')), 'statement')
end

local function defineArithmeticSpecial(name, unaryPrefix)
    local paddedOp = ' ' .. name .. ' '
    SPECIALS[name] = function(ast, scope, parent)
        local len = #ast
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
defineArithmeticSpecial('//', 1)
defineArithmeticSpecial('or')
defineArithmeticSpecial('and')

local function defineComparatorSpecial(name, realop)
    local op = realop or name
    SPECIALS[name] = function(ast, scope, parent)
        assertCompile(#ast > 2, 'expected at least two arguments', ast)
        local lhs = compile1(ast[2], scope, parent, {nval = 1})[1]
        local lastval = compile1(ast[3], scope, parent, {nval = 1})[1]
        -- avoid double-eval by introducing locals for possible side-effects
        if #ast > 3 then lastval = once(lastval, ast[3], scope, parent) end
        local out = ('((%s) %s (%s))'):
            format(tostring(lhs), op, tostring(lastval))
        for i = 4, #ast do -- variadic comparison
            local nextval = once(compile1(ast[i], scope, parent, {nval = 1})[1],
                                 ast[i], scope, parent)
            out = ("(" .. out .. " and ((%s) %s (%s)))"):
                format(tostring(lastval), op, tostring(nextval))
            lastval = nextval
        end
        return out
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
        assertCompile(#ast == 2, 'expected one argument', ast)
        local tail = compile1(ast[2], scope, parent, {nval = 1})
        return (realop or op) .. tostring(tail[1])
    end
end

defineUnarySpecial('not', 'not ')
defineUnarySpecial('#')

-- Covert a macro function to a special form
local function macroToSpecial(mac)
    return function(ast, scope, parent, opts)
        local ok, transformed = pcall(mac, unpack(ast, 2))
        assertCompile(ok, transformed, ast)
        return compile1(transformed, scope, parent, opts)
    end
end

local function compile(ast, options)
    options = options or {}
    if options.indent == nil then options.indent = '  ' end
    local chunk = {}
    local scope = options.scope or makeScope(GLOBAL_SCOPE)
    local exprs = compile1(ast, scope, chunk, {tail = true})
    keepSideEffects(exprs, chunk, nil, ast)
    return flattenChunk(chunk, options.indent)
end

local function compileStream(strm, options)
    options = options or {}
    if options.indent == nil then options.indent = '  ' end
    local scope = options.scope or makeScope(GLOBAL_SCOPE)
    local vals = {}
    for ok, val in parser(strm, options.filename) do
        if not ok then break end
        vals[#vals + 1] = val
    end
    local chunk = {}
    for i = 1, #vals do
        local exprs = compile1(vals[i], scope, chunk, {
            tail = i == #vals
        })
        keepSideEffects(exprs, chunk, nil, vals[i])
    end
    return flattenChunk(chunk, options.indent)
end

local function compileString(str, options)
    local strm = stringStream(str)
    return compileStream(strm, options)
end

local function eval(str, options, ...)
    options = options or {}
    options.indent = options.indent or false
    local luaSource = compileString(str, options)
    local loader = loadCode(luaSource, options.env, options.filename)
    return loader(...)
end

local function dofile_fennel(filename, options, ...)
    options = options or {}
    local f = assert(io.open(filename, "rb"))
    local source = f:read("*all")
    f:close()
    options.filename = options.filename or filename
    return eval(source, options, ...)
end

-- Implements a configurable repl
local function repl(options)

    local opts = options or {}

    if not opts.pp then opts.pp = tostring end

    local env = opts.env or setmetatable({}, {
        __index = _ENV or _G
    })

    local function defaultReadChunk()
        io.write('>> ')
        io.flush()
        local input = io.read()
        return input and input .. '\n'
    end

    local function defaultOnValues(xs)
        io.write(table.concat(xs, '\t'))
        io.write('\n')
    end

    local function defaultOnError(errtype, err, luaSource)
        if (errtype == 'Lua Compile') then
            io.write('Bad code generated - likely a bug with the compiler:\n')
            io.write('--- Generated Lua Start ---\n')
            io.write(luaSource .. '\n')
            io.write('--- Generated Lua End ---\n')
        end
        io.write(('%s error: %s\n'):format(errtype, tostring(err)))
    end

    -- Read options
    local readChunk = opts.readChunk or defaultReadChunk
    local onValues = opts.onValues or defaultOnValues
    local onError = opts.onError or defaultOnError
    pp = opts.pp or pp

    -- Make parser
    local bytestream, clearstream = granulate(readChunk)
    local read = parser(bytestream)

    -- REPL loop
    while true do
        local ok, parseok, x = pcall(read)
        if not ok then
            onError('Parse', parseok)
            clearstream()
        else
            if not parseok then break end -- eof
            local compileOk, luaSource = pcall(compile, x, opts)
            if not compileOk then
                clearstream()
                onError('Compile', luaSource) -- luaSource is error message in this case
            else
                local luacompileok, loader = pcall(loadCode, luaSource, env)
                if not luacompileok then
                    clearstream()
                    onError('Lua Compile', loader, luaSource)
                else
                    local loadok, ret = xpcall(function () return {loader()} end,
                        function (runtimeErr)
                            onError('Runtime', runtimeErr)
                        end)
                    if loadok then
                        env._ = ret[1]
                        env.__ = ret
                        for i = 1, #ret do ret[i] = pp(ret[i]) end
                        onValues(ret)
                    end
                end
            end
        end
    end
end

local module = {
    parser = parser,
    granulate = granulate,
    stringStream = stringStream,
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
    repl = repl,
    dofile = dofile_fennel,
    path = "./?.fnl",
}

local function searchModule(modulename)
    modulename = modulename:gsub("%.", "/")
    for path in string.gmatch(module.path..";", "([^;]*);") do
        local filename = path:gsub("%?", modulename)
        local file = io.open(filename, "rb")
        if(file) then
            file:close()
            return filename
        end
    end
end

-- This will allow regular `require` to work with Fennel:
-- table.insert(package.loaders, fennel.searcher)
module.searcher = function(modulename)
    local filename = searchModule(modulename)
    if filename then
        return function(modname)
            return dofile_fennel(filename, nil, modname)
        end
    end
end

local function makeCompilerEnv(ast, scope, parent)
    return setmetatable({
        -- State of compiler if needed
        _SCOPE = scope,
        _CHUNK = parent,
        _AST = ast,
        _IS_COMPILER = true,
        _SPECIALS = SPECIALS,
        -- Expose the module in the compiler
        fennel = module,
        -- Useful for macros and meta programming. All of Fennel can be accessed
        -- via fennel.myfun, for example (fennel.eval "(print 1)").
        list = list,
        sym = sym,
        [symMangle("list?")] = isList,
        [symMangle("multi-sym?")] = isMultiSym,
        [symMangle("sym?")] = isSym,
        [symMangle("table?")] = isTable,
        [symMangle("varg?")] = isVarg,
    }, { __index = _ENV or _G })
end

SPECIALS['require-macros'] = function(ast, scope, parent)
    for i = 2, #ast do
        local filename = assertCompile(searchModule(ast[i]),
                                       ast[i] .. " not found.", ast)
        local mod = dofile_fennel(filename, {env=makeCompilerEnv(ast, scope, parent)})
        for k, v in pairs(assertCompile(isTable(mod), 'expected ' .. ast[i] ..
                                        'module to be table', ast)) do
            scope.specials[k] = macroToSpecial(v)
        end
    end
end

SPECIALS['eval-compiler'] = function(ast, scope, parent)
    local oldFirst = ast[1]
    ast[1] = sym('do')
    local luaSource = compile(ast, { scope = makeScope(COMPILER_SCOPE) })
    ast[1] = oldFirst
    local loader = loadCode(luaSource, makeCompilerEnv(ast, scope, parent))
    loader()
end

-- Load standard macros
local stdmacros = [===[
;; this module is loaded by the test suite, but these are handy macros to
;; have around so feel free to steal them for your own projects.
{"->" (fn [val ...]
        (var x val)
        (each [_ elt (ipairs [...])]
          (table.insert elt 2 x)
          (set elt.n (+ 1 elt.n))
          (set x elt))
        x)
 "->>" (fn [val ...]
         (var x val)
         (each [_ elt (pairs [...])]
           (table.insert elt x)
           (set elt.n (+ 1 elt.n))
           (set x elt))
         x)
 :defn (fn [name args ...]
         (assert (sym? name) "defn: function names must be symbols")
         (let [op (if (multi-sym? (. name 1)) :set :local)]
           (list (sym op) name
                 (list (sym :fn) args ...))))
 :when (fn [condition body1 ...]
         (assert body1 "expected body")
         (list (sym 'if') condition
               (list (sym 'do') body1 ...)))
}
]===]
for name, fn in pairs(eval(stdmacros, {
    env = makeCompilerEnv(nil, GLOBAL_SCOPE, {})
})) do
    SPECIALS[name] = macroToSpecial(fn)
end

return module
