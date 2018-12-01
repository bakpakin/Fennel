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
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local unpack = unpack or table.unpack

--
-- Main Types and support functions
--

local function deref(self) return self[1] end

local SYMBOL_MT = { 'SYMBOL', __tostring = deref }
local EXPR_MT = { 'EXPR', __tostring = deref }
local VARARG = setmetatable({ '...' }, { 'VARARG', __tostring = deref })
local LIST_MT = { 'LIST',
    __tostring = function (self)
        local strs = {}
        for _, s in ipairs(self) do
            table.insert(strs, tostring(s))
        end
        return '(' .. table.concat(strs, ', ', 1, #self) .. ')'
    end
}

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
local function sym(str, scope, meta)
    local s = {str, scope = scope}
    if meta then
        for k, v in pairs(meta) do
            if type(k) == 'string' then s[k] = v end
        end
    end
    return setmetatable(s, SYMBOL_MT)
end

-- Create a new expr
-- etype should be one of
--   "literal", -- literals like numbers, strings, nil, true, false
--   "expression", -- Complex strings of Lua code, may have side effects, etc, but is an expression
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
            r = getbyte()
        end
        byteindex = byteindex + 1
        if r == 10 then line = line + 1 end
        return r
    end
    local function parseError(msg)
        return error(msg .. ' in ' .. (filename or 'unknown') .. ':' .. line, 0)
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
                if #stack > 0 then parseError 'unexpected end of source' end
                return nil
            end

            if b == 59 then -- ; Comment
                repeat
                    b = getb()
                until not b or b == 10 -- newline
            elseif type(delims[b]) == 'number' then -- Opening delimiter
                table.insert(stack, setmetatable({
                    closer = delims[b],
                    line = line,
                    filename = filename,
                    bytestart = byteindex
                }, LIST_MT))
            elseif delims[b] then -- Closing delimiter
                if #stack == 0 then parseError 'unexpected closing delimiter' end
                local last = stack[#stack]
                local val
                if last.closer ~= b then
                    parseError('unexpected delimiter ' .. string.char(b) ..
                               ', expected ' .. string.char(last.closer))
                end
                last.byteend = byteindex -- Set closing byte index
                if b == 41 then -- )
                    val = last
                elseif b == 93 then -- ]
                    val = {}
                    for i = 1, #last do
                        val[i] = last[i]
                    end
                else -- }
                    if #last % 2 ~= 0 then
                        parseError('expected even number of values in table literal')
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
                if not b then parseError('unexpected end of source') end
                local raw = string.char(unpack(chars))
                local formatted = raw:gsub("[\1-\31]", function (c) return '\\' .. c:byte() end)
                local loadFn = loadCode(('return %s'):format(formatted), nil, filename)
                dispatch(loadFn())
            else -- Try symbol
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
                elseif rawstr == '...' then dispatch(VARARG)
                elseif rawstr:match('^:.+$') then -- keyword style strings
                    dispatch(rawstr:sub(2))
                else
                    local forceNumber = rawstr:match('^%d')
		    local numberWithStrippedUnderscores = rawstr:gsub("_", "")
                    local x
                    if forceNumber then
                        x = tonumber(numberWithStrippedUnderscores) or
                            parseError('could not read token "' .. rawstr .. '"')
                    else
                        x = tonumber(numberWithStrippedUnderscores) or
                            sym(rawstr, nil, { line = line,
                                               filename = filename,
                                               bytestart = bytestart,
                                               byteend = byteindex, })
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

-- Create a new Scope, optionally under a parent scope. Scopes are compile time constructs
-- that are responsible for keeping track of local variables, name mangling, and macros.
-- They are accessible to user code via the '*compiler' special form (may change). They
-- use metatables to implement nesting via inheritance.
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
        symmeta = setmetatable({}, {
            __index = parent and parent.symmeta
        }),
        parent = parent,
        vararg = parent and parent.vararg,
        depth = parent and ((parent.depth or 0) + 1) or 0
    }
end

-- Assert a condition and raise a compile error with line numbers. The ast arg
-- should be unmodified so that its first element is the form being called.
local function assertCompile(condition, msg, ast)
    -- if we use regular `assert' we can't provide the `level' argument of zero
    if not condition then
        error(string.format("Compile error in '%s' %s:%s: %s",
                            isSym(ast[1]) and ast[1][1] or ast[1] or '()',
                            ast.filename or "unknown", ast.line or '?', msg), 0)
    end
    return condition
end

local GLOBAL_SCOPE = makeScope()
GLOBAL_SCOPE.vararg = true
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

local function isValidLuaIdentifier(str)
    return (str:match('^[%a_][%w_]*$') and not luaKeywords[str])
end

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

-- Mangler for global symbols. Does not protect against collisions,
-- but makes them unlikely. This is the mangling that is exposed to
-- to the world.
local function globalMangling(str)
    if isValidLuaIdentifier(str) then
        return str
    end
    -- Use underscore as escape character
    return '__fnl_global__' .. str:gsub('[^%w]', function (c)
        return ('_%02x'):format(c:byte())
    end)
end

-- Reverse a global mangling. Takes a Lua identifier and
-- returns the fennel symbol string that created it.
local function globalUnmangling(identifier)
    local rest = identifier:match('^__fnl_global__(.*)$')
    if rest then
        return rest:gsub('_[%da-f][%da-f]', function (code)
            return string.char(tonumber(code:sub(2), 16))
        end)
    else
        return identifier
    end
end

-- Creates a symbol from a string by mangling it.
-- ensures that the generated symbol is unique
-- if the input string is unique in the scope.
local function localMangling(str, scope, ast)
    if scope.manglings[str] then
        return scope.manglings[str]
    end
    local append = 0
    local mangling = str
    assertCompile(not isMultiSym(str), 'did not expect multi symbol ' .. str, ast)

    -- Mapping mangling to a valid Lua identifier
    if luaKeywords[mangling] or mangling:match('^%d') then
        mangling = '_' .. mangling
    end
    mangling = mangling:gsub('-', '_')
    mangling = mangling:gsub('[^%w_]', function (c)
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

-- Combine parts of a symbol
local function combineParts(parts, scope)
    local ret = scope.manglings[parts[1]] or globalMangling(parts[1])
    for i = 2, #parts do
        if isValidLuaIdentifier(parts[i]) then
            ret = ret .. '.' .. parts[i]
        else
            ret = ret .. '[' .. serializeString(parts[i]) .. ']'
        end
    end
    return ret
end

-- Generates a unique symbol in the scope.
local function gensym(scope)
    local mangling
    local append = 0
    repeat
        mangling = '_' .. append .. '_'
        append = append + 1
    until not scope.unmanglings[mangling]
    scope.unmanglings[mangling] = true
    return mangling
end

-- Declare a local symbol
local function declareLocal(symbol, meta, scope, ast)
    local name = symbol[1]
    assertCompile(not isMultiSym(name), "did not expect mutltisym", ast)
    local mangling = localMangling(name, scope, ast)
    scope.symmeta[name] = meta
    return mangling
end

-- If there's a provided list of allowed globals, don't let references
-- thru that aren't on the list. This list is set at the compiler
-- entry points of compile and compileStream.
local allowedGlobals

local function globalAllowed(name)
    if not allowedGlobals then return true end
    for _, g in ipairs(allowedGlobals) do
        if g == name then return true end
    end
end

-- Convert symbol to Lua code. Will only work for local symbols
-- if they have already been declared via declareLocal
local function symbolToExpression(symbol, scope, isReference)
    local name = symbol[1]
    local parts = isMultiSym(name) or {name}
    local etype = (#parts > 1) and "expression" or "sym"
    local isLocal = scope.manglings[parts[1]]
    -- if it's a reference and not a symbol which introduces a new binding
    -- then we need to check for allowed globals
    assertCompile(not isReference or isLocal or globalAllowed(parts[1]),
                  'unknown global in strict mode: ' .. parts[1], symbol)
    return expr(combineParts(parts, scope), etype)
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
    if #chunk == 3 and
        chunk[1].leaf == 'do' and
        not chunk[2].leaf and
        chunk[3].leaf == 'end' then
        return peephole(chunk[2])
    end
    -- Recurse
    for i, v in ipairs(chunk) do
        chunk[i] = peephole(v)
    end
    return chunk
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
                    if subchunk.ast and file == subchunk.ast.file then
                        lastLine = math.max(lastLine, subchunk.ast.line or 0)
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
        local parts = {}
        for i = 1, #chunk do
            -- Ignore empty chunks
            if chunk[i].leaf or #(chunk[i]) > 0 then
                local sub = flattenChunk(sm, chunk[i], tab, depth + 1)
                if depth > 0 then sub = tab .. sub:gsub('\n', '\n' .. tab) end
                table.insert(parts, sub)
            end
        end
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
    local sm = options.sourcemap and {}
    chunk = peephole(chunk)
    if(options.correlate) then
        return flattenChunkCorrelated(chunk), {}
    else
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

-- Convert expressions to Lua string
local function exprs1(exprs)
    local t = {}
    for _, e in ipairs(exprs) do
        t[#t + 1] = e[1]
    end
    return table.concat(t, ', ')
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
            emit(chunk, tostring(se), ast)
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
        assertCompile(len > 0, "expected a function to call", ast)
        -- Test for special form
        local first = ast[1]
        if isSym(first) then -- Resolve symbol
            first = first[1]
        end
        local special = scope.specials[first]
        if special and isSym(ast[1]) then
            -- Special form
            exprs = special(ast, scope, parent, opts) or expr('nil', 'literal')
            -- Be very accepting of strings or expression
            -- as well as lists or expressions
            if type(exprs) == 'string' then exprs = expr(exprs, 'expression') end
            if getmetatable(exprs) == EXPR_MT then exprs = {exprs} end
            -- Unless the special form explicitly handles the target, tail, and nval properties,
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
            assertCompile(fcallee.type ~= 'literal',
                          'cannot call literal value', ast)
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
        assertCompile(scope.vararg, "unexpected vararg", ast)
        exprs = handleCompileOpts({expr('...', 'varg')}, parent, opts, ast)
    elseif isSym(ast) then
        local e
        -- Handle nil as special symbol - it resolves to the nil literal rather than
        -- being unmangled. Alternatively, we could remove it from the lua keywords table.
        if ast[1] == 'nil' then
            e = expr('nil', 'literal')
        else
            e = symbolToExpression(ast, scope, true)
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
            local nval = i ~= #ast and 1
            buffer[#buffer + 1] = exprs1(compile1(ast[i], scope, parent, {nval = nval}))
        end
        local keys = {}
        for k, _ in pairs(ast) do -- Write other keys.
            if type(k) ~= 'number' or math.floor(k) ~= k or k < 1 or k > #ast then
                local kstr
                if type(k) == 'string' and isValidLuaIdentifier(k) then
                    kstr = k
                else
                    kstr = '[' .. tostring(compile1(k, scope, parent, {nval = 1})[1]) .. ']'
                end
                table.insert(keys, { kstr, k })
            end
        end
        table.sort(keys, function (a, b) return a[1] < b[1] end)
        for _, k in ipairs(keys) do
            local v = ast[k[2]]
            buffer[#buffer + 1] = ('%s = %s'):format(
                k[1], tostring(compile1(v, scope, parent, {nval = 1})[1]))
        end
        local tbl = '{' .. table.concat(buffer, ', ') ..'}'
        exprs = handleCompileOpts({expr(tbl, 'expression')}, parent, opts, ast)
    else
        assertCompile(false, 'could not compile value of type ' .. type(ast), ast)
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

    -- Get Lua source for symbol, and check for errors
    local function getname(symbol, up1)
        local raw = symbol[1]
        assertCompile(not (nomulti and isMultiSym(raw)),
            'did not expect multisym', up1)
        if declaration then
            return declareLocal(symbol, {var = isvar}, scope, symbol)
        else
            local parts = isMultiSym(raw) or {raw}
            local meta = scope.symmeta[parts[1]]
            if #parts == 1 and not forceset then
                assertCompile(not(forceglobal and meta),
                    'expected global, found var', up1)
                assertCompile(meta or not noundef,
                    'expected local var ' .. parts[1], up1)
                assertCompile(not (meta and not meta.var),
                    'expected local var', up1)
            end
            return symbolToExpression(symbol, scope)[1]
        end
    end

    -- Recursive auxiliary function
    local function destructure1(left, rightexprs, up1)
        if isSym(left) and left[1] ~= "nil" then
            emit(parent, setter:format(getname(left, up1), exprs1(rightexprs)), left)
        elseif isTable(left) then -- table destructuring
            local s = gensym(scope)
            emit(parent, ("local %s = %s"):format(s, exprs1(rightexprs)), left)
            for i, v in ipairs(left) do
                if isSym(left[i]) and left[i][1] == "&" then
                    assertCompile(not left[i+2],
                        "expected rest argument in final position", left)
                    local subexpr = expr(('{(table.unpack or unpack)(%s, %s)}'):format(s, i),
                        'expression')
                    destructure1(left[i+1], {subexpr}, left)
                    return
                else
                    local subexpr = expr(('%s[%d]'):format(s, i), 'expression')
                    destructure1(v, {subexpr}, left)
                end
            end
        elseif isList(left) then -- values destructuring
            local leftNames, tables = {}, {}
            for i, name in ipairs(left) do
                local symname
                if isSym(name) then -- binding directly to a name
                    symname = getname(name, up1)
                else -- further destructuring of tables inside values
                    symname = gensym(scope)
                    tables[i] = {name, expr(symname, 'sym')}
                end
                table.insert(leftNames, symname)
            end
            emit(parent, setter:
            format(table.concat(leftNames, ", "), exprs1(rightexprs)), left)
            for _, pair in pairs(tables) do -- recurse if left-side tables found
                destructure1(pair[1], {pair[2]}, left)
            end
        else
            assertCompile(false, 'unable to destructure ' .. tostring(left), up1)
        end
    end

    local rexps = compile1(from, scope, parent)
    local ret = destructure1(to, rexps, ast)
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

-- Implements a do statement, starting at the 'start' element. By default, start is 2.
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
            local fargs = scope.vararg and '...' or ''
            emit(parent, ('local function %s(%s)'):format(fname, fargs), ast)
            retexprs = expr(fname .. '(' .. fargs .. ')', 'statement')
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
    fScope.vararg = false
    if fnName and fnName[1] ~= 'nil' then
        isLocalFn = not isMultiSym(fnName[1])
        if isLocalFn then
            fnName = declareLocal(fnName, {}, scope, ast)
        else
            fnName = symbolToExpression(fnName, scope)[1]
        end
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
            assertCompile(i == #argList, "expected vararg in last parameter position", ast)
            argNameList[i] = '...'
            fScope.vararg = true
        elseif(isSym(argList[i]) and argList[i][1] ~= "nil"
               and not isMultiSym(argList[i][1])) then
            argNameList[i] = declareLocal(argList[i], {}, fScope, ast)
        elseif isTable(argList[i]) then
            local raw = sym(gensym(scope))
            argNameList[i] = declareLocal(raw, {}, fScope, ast)
            destructure(argList[i], raw, ast, fScope, fChunk,
                        { declaration = true, nomulti = true })
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
    return expr(fnName, 'sym')
end

SPECIALS['luaexpr'] = function(ast)
    return tostring(ast[2])
end

SPECIALS['luastatement'] = function(ast)
    return expr(tostring(ast[2]), 'statement')
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
            local index = ast[i]
            if type(index) == 'string' and isValidLuaIdentifier(index) then
                table.insert(indices, '.' .. index)
            else
                index = compile1(index, scope, parent, {nval = 1})[1]
                table.insert(indices, '[' .. tostring(index) .. ']')
            end
        end
        -- extra parens are needed for table literals
        if isTable(ast[2]) then
            return '(' .. tostring(lhs[1]) .. ')' .. table.concat(indices)
        else
            return tostring(lhs[1]) .. table.concat(indices)
        end
    end
end

SPECIALS['global'] = function(ast, scope, parent)
    assertCompile(#ast == 3, "expected name and value", ast)
    if allowedGlobals then table.insert(allowedGlobals, ast[2][1]) end
    destructure(ast[2], ast[3], ast, scope, parent, {
        nomulti = true,
        forceglobal = true
    })
end

SPECIALS['set'] = function(ast, scope, parent)
    assertCompile(#ast == 3, "expected name and value", ast)
    destructure(ast[2], ast[3], ast, scope, parent, {
        noundef = true
    })
end

SPECIALS['set-forcibly!'] = function(ast, scope, parent)
    assertCompile(#ast == 3, "expected name and value", ast)
    destructure(ast[2], ast[3], ast, scope, parent, {
        forceset = true
    })
end

SPECIALS['local'] = function(ast, scope, parent)
    assertCompile(#ast == 3, "expected name and value", ast)
    destructure(ast[2], ast[3], ast, scope, parent, {
        declaration = true,
        nomulti = true
    })
end

SPECIALS['var'] = function(ast, scope, parent)
    assertCompile(#ast == 3, "expected name and value", ast)
    destructure(ast[2], ast[3], ast, scope, parent, {
        declaration = true,
        nomulti = true,
        isvar = true
    })
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
        destructure(bindings[i], bindings[i + 1], ast, subScope, subChunk, {
            declaration = true,
            nomulti = true
        })
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
        branch.nested = i ~= 2 and next(condchunk, nil) == nil
        table.insert(branches, branch)
    end
    local hasElse = #ast > 3 and #ast % 2 == 0
    if hasElse then elseBranch = compileBody(#ast) end

    -- Emit code
    local s = gensym(scope)
    local buffer = {}
    local lastBuffer = buffer
    for i = 1, #branches do
        local branch = branches[i]
        local fstr = not branch.nested and 'if %s then' or 'elseif %s then'
        local condLine = fstr:format(tostring(branch.cond[1]))
        if branch.nested then
            emit(lastBuffer, branch.condchunk, ast)
        else
            for _, v in ipairs(branch.condchunk) do emit(lastBuffer, v, ast) end
        end
        emit(lastBuffer, condLine, ast)
        emit(lastBuffer, branch.chunk, ast)
        if i == #branches then
            if hasElse then
                emit(lastBuffer, 'else', ast)
                emit(lastBuffer, elseBranch.chunk, ast)
            end
            emit(lastBuffer, 'end', ast)
        elseif not branches[i + 1].nested then
            emit(lastBuffer, 'else', ast)
            local nextBuffer = {}
            emit(lastBuffer, nextBuffer, ast)
            emit(lastBuffer, 'end', ast)
            lastBuffer = nextBuffer
        end
    end

    if wrapper == 'iife' then
        local iifeargs = scope.vararg and '...' or ''
        emit(parent, ('local function %s(%s)'):format(tostring(s), iifeargs), ast)
        emit(parent, buffer, ast)
        emit(parent, 'end', ast)
        return expr(('%s(%s)'):format(tostring(s), iifeargs), 'statement')
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
    local destructures = {}
    for _, v in ipairs(binding) do
        assertCompile(isSym(v) or isTable(v),
                      'expected iterator symbol or table', ast)
        if(isSym(v)) then
            table.insert(bindVars, declareLocal(v, {}, scope, ast))
        else
            local raw = sym(gensym(scope))
            destructures[raw] = v
            table.insert(bindVars, declareLocal(raw, {}, scope, ast))
        end
    end
    emit(parent, ('for %s in %s do'):format(
             table.concat(bindVars, ', '),
             tostring(compile1(iter, scope, parent, {nval = 1})[1])), ast)
    local chunk = {}
    for raw, args in pairs(destructures) do
        destructure(args, raw, ast, scope, chunk,
                    { declaration = true, nomulti = true })
    end
    compileDo(ast, scope, chunk, 3)
    emit(parent, chunk, ast)
    emit(parent, 'end', ast)
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
             declareLocal(bindingSym, {}, scope, ast),
             table.concat(rangeArgs, ', ')), ast)
    local chunk = {}
    compileDo(ast, scope, chunk, 3)
    emit(parent, chunk, ast)
    emit(parent, 'end', ast)
end

SPECIALS[':'] = function(ast, scope, parent)
    assertCompile(#ast >= 3, 'expected at least 3 arguments', ast)
    -- Compile object
    local objectexpr = compile1(ast[2], scope, parent, {nval = 1})[1]
    -- Compile method selector
    local methodstring
    local methodident = false
    if type(ast[3]) == 'string' and isValidLuaIdentifier(ast[3]) then
        methodident = true
        methodstring = ast[3]
    else
        methodstring = tostring(compile1(ast[3], scope, parent, {nval = 1})[1])
        objectexpr = once(objectexpr, ast[2], scope, parent)
    end
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
    local fstring
    if methodident then
        fstring = objectexpr.type == 'literal'
            and '(%s):%s(%s)'
            or '%s:%s(%s)'
    else
        -- Make object first argument
        table.insert(args, 1, tostring(objectexpr))
        fstring = objectexpr.type == 'sym'
            and '%s[%s](%s)'
            or '(%s)[%s](%s)'
    end
    return expr(fstring:format(
        tostring(objectexpr),
        methodstring,
        table.concat(args, ', ')), 'statement')
end

local function defineArithmeticSpecial(name, zeroArity, unaryPrefix)
    local paddedOp = ' ' .. name .. ' '
    SPECIALS[name] = function(ast, scope, parent)
        local len = #ast
        if len == 1 then
            assertCompile(zeroArity ~= nil, 'Expected more than 0 arguments', ast)
            return expr(zeroArity, 'literal')
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
end

defineArithmeticSpecial('+', '0')
defineArithmeticSpecial('..', "''")
defineArithmeticSpecial('^')
defineArithmeticSpecial('-', nil, '')
defineArithmeticSpecial('*', '1')
defineArithmeticSpecial('%')
defineArithmeticSpecial('/', nil, '1')
defineArithmeticSpecial('//', nil, '1')
defineArithmeticSpecial('or', 'false')
defineArithmeticSpecial('and', 'true')

local function defineComparatorSpecial(name, realop)
    local op = realop or name
    SPECIALS[name] = function(ast, scope, parent)
        local len = #ast
        assertCompile(len > 2, 'expected at least two arguments', ast)
        local lhs = compile1(ast[2], scope, parent, {nval = 1})[1]
        local lastval = compile1(ast[3], scope, parent, {nval = 1})[1]
        -- avoid double-eval by introducing locals for possible side-effects
        if len > 3 then lastval = once(lastval, ast[3], scope, parent) end
        local out = ('(%s %s %s)'):
            format(tostring(lhs), op, tostring(lastval))
        if len > 3 then
            for i = 4, len do -- variadic comparison
                local nextval = once(compile1(ast[i], scope, parent, {nval = 1})[1],
                                     ast[i], scope, parent)
                out = (out .. " and (%s %s %s)"):
                    format(tostring(lastval), op, tostring(nextval))
                lastval = nextval
            end
            out = '(' .. out .. ')'
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
    local oldGlobals = allowedGlobals
    allowedGlobals = options.allowedGlobals
    if options.indent == nil then options.indent = '  ' end
    local chunk = {}
    local scope = options.scope or makeScope(GLOBAL_SCOPE)
    local exprs = compile1(ast, scope, chunk, {tail = true})
    keepSideEffects(exprs, chunk, nil, ast)
    allowedGlobals = oldGlobals
    return flatten(chunk, options)
end

local function compileStream(strm, options)
    options = options or {}
    local oldGlobals = allowedGlobals
    allowedGlobals = options.allowedGlobals
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
    allowedGlobals = oldGlobals
    return flatten(chunk, options)
end

local function compileString(str, options)
    local strm = stringStream(str)
    return compileStream(strm, options)
end

---
--- Evaluation
---

-- A custom traceback function for Fennel that looks similar to
-- the Lua's debug.traceback.
-- Use with xpcall to produce fennel specific stacktraces.
local function traceback(msg, start)
    local level = start or 2 -- Can be used to skip some frames
    local lines = {}
    if msg then
        table.insert(lines, msg)
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
                -- Overwrite info with values from the mapping (mapping is now just integer,
                -- but may eventually be a table
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

local function currentGlobalNames(env)
    local names = {}
    for k in pairs(env or _G) do table.insert(names, k) end
    return names
end

local function eval(str, options, ...)
    options = options or {}
    -- eval and dofile are considered "live" entry points, so we can assume
    -- that the globals available at compile time are a reasonable allowed list
    -- UNLESS there's a metatable on env, in which case we can't assume that
    -- pairs will return all the effective globals; for instance openresty
    -- sets up _G in such a way that all the globals are available thru
    -- the __index meta method, but as far as pairs is concerned it's empty.
    if options.allowedGlobals == nil and not getmetatable(options.env) then
        options.allowedGlobals = currentGlobalNames(options.env)
    end
    local luaSource = compileString(str, options)
    local loader = loadCode(luaSource, options.env,
        options.filename and ('@' .. options.filename) or str)
    return loader(...)
end

local function dofile_fennel(filename, options, ...)
    options = options or {sourcemap = true}
    if options.allowedGlobals == nil then
        options.allowedGlobals = currentGlobalNames(options.env)
    end
    local f = assert(io.open(filename, "rb"))
    local source = f:read("*all"):gsub("^#![^\n]*\n", "")
    f:close()
    options.filename = options.filename or filename
    return eval(source, options, ...)
end

-- Implements a configurable repl
local function repl(options)

    local opts = options or {}
    -- This would get set for us when calling eval, but we want to seed it
    -- with a value that is persistent so it doesn't get reset on each eval.
    if opts.allowedGlobals == nil then
        options.allowedGlobals = currentGlobalNames(opts.env)
    end

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
        if (errtype == 'Runtime') then
            io.write(traceback(err, 4))
            io.write('\n')
        else
            io.write(('%s error: %s\n'):format(errtype, tostring(err)))
        end
    end

    -- Read options
    local readChunk = opts.readChunk or defaultReadChunk
    local onValues = opts.onValues or defaultOnValues
    local onError = opts.onError or defaultOnError
    local pp = opts.pp or tostring

    -- Make parser
    local bytestream, clearstream = granulate(readChunk)
    local chars = {}
    local read = parser(function()
        local c = bytestream()
        chars[#chars + 1] = c
        return c
    end)

    local envdbg = (opts.env or _G)["debug"]
    -- if the environment doesn't support debug.getlocal you can't save locals
    local saveLocals = opts.saveLocals ~= false and envdbg and envdbg.getlocal
    local saveSource = table.
       concat({"local ___i___ = 1",
               "while true do",
               " local name, value = debug.getlocal(1, ___i___)",
               " if(name and name ~= \"___i___\") then",
               " ___replLocals___[name] = value",
               " ___i___ = ___i___ + 1",
               " else break end end"}, "\n")

    local spliceSaveLocals = function(luaSource)
        -- we do some source munging in order to save off locals from each chunk
        -- and reintroduce them to the beginning of the next chunk, allowing
        -- locals to work in the repl the way you'd expect them to.
        env.___replLocals___ = env.___replLocals___ or {}
        local splicedSource = {}
        for line in luaSource:gmatch("([^\n]+)\n?") do
            table.insert(splicedSource, line)
        end
        -- reintroduce locals from the previous time around
        local bind = "local %s = ___replLocals___['%s']"
        for name in pairs(env.___replLocals___) do
            table.insert(splicedSource, 1, bind:format(name, name))
        end
        -- save off new locals at the end - if safe to do so (i.e. last line is a return)
        if (string.match(splicedSource[#splicedSource], "^ *return .*$")) then
            if (#splicedSource > 1) then
                table.insert(splicedSource, #splicedSource, saveSource)
            end
        end
        return table.concat(splicedSource, "\n")
    end

    local scope = makeScope(GLOBAL_SCOPE)

    -- REPL loop
    while true do
        chars = {}
        local ok, parseok, x = pcall(read)
        local srcstring = string.char(unpack(chars))
        if not ok then
            onError('Parse', parseok)
            clearstream()
        else
            if not parseok then break end -- eof
            local compileOk, luaSource = pcall(compile, x, {
                sourcemap = opts.sourcemap,
                source = srcstring,
                scope = scope,
            })
            if not compileOk then
                clearstream()
                onError('Compile', luaSource) -- luaSource is error message in this case
            else
                if saveLocals then
                    luaSource = spliceSaveLocals(luaSource)
                end
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

local macroLoaded = {}

local module = {
    parser = parser,
    granulate = granulate,
    stringStream = stringStream,
    compile = compile,
    compileString = compileString,
    compileStream = compileStream,
    compile1 = compile1,
    mangle = globalMangling,
    unmangle = globalUnmangling,
    list = list,
    sym = sym,
    varg = varg,
    scope = makeScope,
    gensym = gensym,
    eval = eval,
    repl = repl,
    dofile = dofile_fennel,
    macroLoaded = macroLoaded,
    path = "./?.fnl;./?/init.fnl",
    traceback = traceback,
    version = "0.1.1-dev",
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

module.make_searcher = function(options)
   return function(modulename)
      local opts = {}
      for k,v in pairs(options or {}) do opts[k] = v end
      local filename = searchModule(modulename)
      if filename then
         return function(modname)
            return dofile_fennel(filename, opts, modname)
         end
      end
   end
end

-- This will allow regular `require` to work with Fennel:
-- table.insert(package.loaders, fennel.searcher)
module.searcher = module.make_searcher()

local function makeCompilerEnv(ast, scope, parent)
    return setmetatable({
        -- State of compiler if needed
        _SCOPE = scope,
        _CHUNK = parent,
        _AST = ast,
        _IS_COMPILER = true,
        _SPECIALS = SPECIALS,
        _VARARG = VARARG,
        -- Expose the module in the compiler
        fennel = module,
        -- Useful for macros and meta programming. All of Fennel can be accessed
        -- via fennel.myfun, for example (fennel.eval "(print 1)").
        list = list,
        sym = sym,
        unpack = unpack,
        gensym = function() return sym(gensym(scope)) end,
        [globalMangling("list?")] = isList,
        [globalMangling("multi-sym?")] = isMultiSym,
        [globalMangling("sym?")] = isSym,
        [globalMangling("table?")] = isTable,
        [globalMangling("varg?")] = isVarg,
    }, { __index = _ENV or _G })
end

local function macroGlobals(env, globals)
    local allowed = {}
    for k in pairs(env) do
        local g = globalUnmangling(k)
        table.insert(allowed, g)
    end
    if globals then
        for _, k in pairs(globals) do
            table.insert(allowed, k)
        end
    end
    return allowed
end

SPECIALS['require-macros'] = function(ast, scope, parent)
    for i = 2, #ast do
        local modname = ast[i]
        local mod
        if macroLoaded[modname] then
            mod = macroLoaded[modname]
        else
            local filename = assertCompile(searchModule(modname),
                                           modname .. " not found.", ast)
            local env = makeCompilerEnv(ast, scope, parent)
            mod = dofile_fennel(filename, {
                env = env,
                allowedGlobals = macroGlobals(env, currentGlobalNames())
            })
            macroLoaded[modname] = mod
        end
        for k, v in pairs(assertCompile(isTable(mod), 'expected ' .. modname ..
                                        ' module to be table', ast)) do
            if allowedGlobals then table.insert(allowedGlobals, k) end
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
{"->" (fn [val ...]
        (var x val)
        (each [_ elt (ipairs [...])]
          (table.insert elt 2 x)
          (set x elt))
        x)
 "->>" (fn [val ...]
         (var x val)
         (each [_ elt (pairs [...])]
           (table.insert elt x)
           (set x elt))
         x)
 :doto (fn [val ...]
         (let [name (gensym)
               form (list (sym :let) [name val])]
           (each [_ elt (pairs [...])]
             (table.insert elt 2 name)
             (table.insert form elt))
           (table.insert form name)
           form))
 :when (fn [condition body1 ...]
         (assert body1 "expected body")
         (list (sym 'if') condition
               (list (sym 'do') body1 ...)))
 :partial (fn [f ...]
            (let [body (list f ...)]
              (table.insert body _VARARG)
              (list (sym "fn") [_VARARG] body)))
 :lambda (fn [...]
           (let [args [...]
                 has-internal-name? (sym? (. args 1))
                 arglist (if has-internal-name? (. args 2) (. args 1))
                 arity-check-position (if has-internal-name? 3 2)]
             (assert (> (# args) 1) "missing body expression")
             (each [i a (ipairs arglist)]
               (if (and (not (: (tostring a) :match "^?"))
                        (~= (tostring a) "..."))
                   (table.insert args arity-check-position
                                 (list (sym "assert")
                                       (list (sym "~=") (sym "nil") a)
                                       (: "Missing argument %s on %s:%s"
                                          :format (tostring a)
                                          (or a.filename "unknown")
                                          (or a.line "?"))))))
             (list (sym "fn") (unpack args))))
}
]===]
do
    local env = makeCompilerEnv(nil, GLOBAL_SCOPE, {})
    for name, fn in pairs(eval(stdmacros, {
        env = env,
        allowedGlobals = macroGlobals(env, currentGlobalNames()),
    })) do
        SPECIALS[name] = macroToSpecial(fn)
    end
end
SPECIALS['λ'] = SPECIALS['lambda']

return module
