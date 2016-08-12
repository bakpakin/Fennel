-- fnl.lua

--[[
Copyright (c) 2016 Calvin Rose
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
local unpack = unpack or table.unpack
local tpack = table.pack or function(...)
    return {n = select('#', ...), ...}
end

local SYMBOL_MT = { 'SYMBOL' }
local VARARG = setmetatable({ '...' }, { 'VARARG' })
local LIST_MT = { 'LIST' }

-- Load code with an environment in all recent Lua versions
local function loadCode(code, environment)
    environment = environment or _ENV or _G
    if setfenv and loadstring then
        local f = assert(loadstring(code))
        setfenv(f, environment)
        return f
    else
        return assert(load(code, nil, "t", environment))
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

-- Append b to list a. Return a. If b is a list and not 'force', append all
-- elements of b to a.
local function listAppend(a, b)
    assert(isList(a), 'expected list')
    assert(isList(b), 'expected list')
    for i = 1, b.n do
        a[a.n + i] = b[i]
    end
    a.n = b.n + a.n
    return a
end

-- Turn a list like table of values into a non-sequence table by
-- assigning successive elements as key-value pairs. mapify {1, 'a', 'b', true}
-- should become {[1] = 'a', ['b'] = true}
local function mapify(tab)
    local max = 0
    for k, v in pairs(tab) do
        if type(k) == 'number' then
            max = max > k and max or k
        end
    end
    local ret = {}
    for i = 1, max, 2 do
        if tab[i] ~= nil then
            ret[tab[i]] = tab[i + 1]
        end
    end
    return ret
end

local READER_INDEX = { length = math.huge }
local READER_MT = {__index = READER_INDEX}

function READER_INDEX:sub(a, b)
    assert(a and b, 'reader sub requires two arguments')
    assert(a > 0 and b > 0, 'no non-zero sub support')
    a, b = a - self.offset, b - self.offset
    return self.buffer:sub(a, b)
end

function READER_INDEX:free(index)
    local dOffset = index - self.offset
    if dOffset < 1 then
        return
    end
    self.offset = index
    self.buffer = self.buffer:sub(dOffset + 1)
end

function READER_INDEX:getMore()
    local chunk = self.more()
    self.buffer = self.buffer .. chunk
end

function READER_INDEX:byte(i)
    i = i or 1
    local index = i - self.offset
    assert(index > 0, 'index below buffer range')
    while index > #self.buffer do
        self:getMore()
    end
    return self.buffer:byte(index)
end

-- Create a reader. A reader emulates a subset of the string api
-- in order to allow streams to be parsed as if the were strings.
local function createReader(more)
    return setmetatable({
        more = more or io.read,
        buffer = '',
        offset = 0
    }, READER_MT)
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

-- Parser
-- Parse a string into an AST. The ast is a list-like table consiting of
-- strings, symbols, numbers, booleans, nils, and other ASTs. Each AST has
-- a value 'n' for length, as ASTs can have nils which do not cooperate with
-- Lua's semantics for table length.
-- Returns an AST containing multiple expressions. For example, "(+ 1 2) (+ 3 4)"
-- would parse and return a single AST containing two sub trees.
local function parseSequence(str, dispatch, index, opener)
    index = index or 1
    local seqLen = 0
    local values = {}
    local strlen = str.length or #str
    local function free(i)
        if str.free then
            str:free(i)
        end
    end
    local function onWhitespace(includeParen)
        local b = str:byte(index)
        if not b then return false end
        return b == 32 or (b >= 9 and b <= 13) or
            (includeParen and delims[b])
    end
    local function readValue()
        local start = str:byte(index)
        local stringStartIndex = index
        -- Check if quoted string
        if start == 34 or start == 39 then
            local last, current
            repeat
                index = index + 1
                current, last = str:byte(index), current
            until index >= strlen or (current == start and last ~= 92)
            local raw = str:sub(stringStartIndex, index)
            local loadFn = loadCode(('return %s'):format(raw))
            index = index + 1
            return loadFn()
        else -- non-quoted string - symbol, number, or nil
            while not onWhitespace(true) do
                index = index + 1
            end
            local rawSubstring = str:sub(stringStartIndex, index - 1)
            if rawSubstring == 'nil' then return nil end
            if rawSubstring == 'true' then return true end
            if rawSubstring == 'false' then return false end
            if rawSubstring == '...' then return VARARG end
            if rawSubstring:match('^:[%w_-]*$') then -- keyword style strings
                return rawSubstring:sub(2)
            end
            local forceNumber = rawSubstring:match('^%d')
            if forceNumber then
                return tonumber(rawSubstring) or error('could not read token "' .. rawSubstring .. '"')
            end
            return tonumber(rawSubstring) or sym(rawSubstring)
        end
    end
    while index < strlen do
        while index < strlen and onWhitespace() do
            index = index + 1
        end
        local b = str:byte(index)
        if not b then break end
        free(index - 1)
        local value, vlen
        if type(delims[b]) == 'number' then -- Opening delimiter
            value, index, vlen  = parseSequence(str, nil, index + 1, b)
            if b == 40 then
                value.n = vlen
                value = setmetatable(value, LIST_MT)
            elseif b == 123 then
                value = mapify(value)
            end
        elseif delims[b] then -- Closing delimiter
            if delims[opener] ~= b then
                error('unexpected delimiter ' .. string.char(b))
            end
            index = index + 1
            break
        else -- Other values
            value = readValue()
        end
        seqLen = seqLen + 1
        if dispatch then
            dispatch(value)
        else
            values[seqLen] = value
        end
    end
    return values, index, seqLen
end

-- Parse a string and return an AST, along with its length as the second return value.
local function parse(str, dispatch)
    local values, _, len = parseSequence(str, dispatch)
    values.n = len
    return setmetatable(values, LIST_MT), len
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
            buffer[i] = astToString(tab[i], G)
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
local function stringMangle(str, scope)
    if scope.manglings[str] then
        return scope.manglings[str]
    end
    local append = 0
    local mangling = str
    local parts = isMultiSym(str)
    if parts then
        local ret
        for i = 1, #parts do
            if parts[i]:match('^%d+$') then
                ret = nil
                break
            elseif ret then
                ret = ret .. '.' .. stringMangle(parts[i], scope)
            else
                ret = stringMangle(parts[i], scope)
            end
        end
        if ret then return ret end
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

-- Generates a unique symbol in the scope.
local function gensym(scope)
    local mangling, append = nil, 0
    repeat
        mangling = '_' .. append
        append = append + 1
    until not scope.unmanglings[mangling]
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

-- Forward declaration
local compileTossRest

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
local function compileExpr(ast, scope, parent)
    local head = {}
    if isList(ast) then
        local len = ast.n
        -- Test for special form
        local first = ast[1]
        if isSym(first) then -- Resolve symbol
            first = first[1]
        end
        local special = scope.specials[first]
        if special and isSym(ast[1]) then
            local ret = special(ast, scope, parent)
            ret = ret or {}
            if type(ret.expr) == 'string' then ret.expr = list(ret.expr) end
            ret.expr = ret.expr or list()
            return ret
        else
            local fargs = list()
            local fcall = compileTossRest(ast[1], scope, parent).expr[1]
            for i = 2, len do
                if i == len then
                    listAppend(fargs, compileExpr(ast[i], scope, parent).expr)
                else
                    listAppend(fargs, compileTossRest(ast[i], scope, parent).expr)
                end
            end
            head.validStatement = true
            head.singleEval = true
            head.sideEffects = true
            head.expr = list(('%s(%s)'):format(fcall, table.concat(fargs, ', ')))
            head.unknownExprCount = true
        end
    else
        head.expr = list(literalToString(ast, scope))
    end
    return head
end

-- Compile an AST, and ensure that the expression
-- is fully executed in it scope. compileExpr doesn't necesarrily
-- compile all of its code into parent, and might return some code
-- to the calling function to allow inlining.
local function compileDo(ast, scope, parent, i, j)
    if i then
        for x = i, j or ast.n do
            compileDo(ast[x], scope, parent)
        end
        return
    end
    local tail = compileExpr(ast, scope, parent)
    if tail.expr.n > 0 and tail.sideEffects then
        local stringExpr = table.concat(tail.expr, ', ')
        if tail.validStatement then
            parent[#parent + 1] = stringExpr
        else
            parent[#parent + 1] = ('do local _ = %s end'):format(stringExpr)
        end
    end
end

local function compileTail(ast, scope, parent, start)
    local len = ast.n or #ast
    compileDo(ast, scope, parent, start or 2, len - 1)
    return compileExpr(ast[len], scope, parent)
end

-- Toss out the later expressions (non first) in the tail. Also
-- sets the empty expression to 'nil'.
-- This ensures exactly one return value for most manipulations.
local function tossRest(tail, scope, parent)
    if tail.expr.n == 0 then
        tail.expr[1] = 'nil'
    else
        -- Ensure proper order of evaluation
        -- The first AST MUST be evaluated first.
        if tail.expr.n > 1 then
            local s = gensym(scope)
            parent[#parent + 1] = ('local %s = %s'):format(s, tail.expr[1])
            tail.expr[1] = s
            tail = { -- Remove non expr keys
                expr = tail.expr,
                scoped = true
            }
        end
        for i = 2, tail.expr.n do
            parent[#parent + 1] = ('do local _ = %s end'):format(tail.expr[i])
            tail.expr[i] = nil -- Not strictly necesarry
        end
    end
    tail.expr.n = 1
    return tail
end

-- Compile a sub expression, and return a tail that contains exactly one expression.
function compileTossRest(ast, scope, parent)
    return tossRest(compileExpr(ast, scope, parent), scope, parent)
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
--
-- Convert an ast into a chunk of Lua source code by compiling it and flattening.
-- Optionally appends a return statement at the end to return the last statement.
local function transpile(ast, scope, options)
    scope = scope or GLOBAL_SCOPE
    local root = {}
    local head = compileExpr(ast, scope, root)
    if head.expr.n > 0 then
        local expr = table.concat(head.expr, ', ')
        if options.returnTail then
            root[#root + 1] = 'return ' .. expr
        elseif head.sideEffects then
            if head.validStatement then
                root[#root + 1] = expr
            else
                root[#root + 1] = ('do local _ = %s end'):format(expr)
            end
        end
    end
    return flattenChunk(root, options.tab)
end

-- SPECIALS --

-- Implements destructuring for forms like let, bindings, etc.
local function destructure(left, right, scope, parent)
    local rightFirst = compileTossRest(right, scope, parent)
    local skeyPairs, rest, as, keys = {}
    if isSym(left) then
        assert(not isMultiSym(left[1]), 'did not expect multi symbol')
        parent[#parent + 1] = ('local %s = %s'):format(
            stringMangle(left[1], scope), rightFirst.expr[1])
        return
    elseif isTable(left) then
        local i = 0
        while i < #left do
            i = i + 1
            local sub = left[i]
            if type(sub) == 'string' then -- check for special syntax
                i = i + 1
                if sub == 'as' then -- Bind remainder of right (packed) to symbol n
                    if as then error 'already found as in destructure' end
                    as = assert(isSym(left[i]), 'expected symbol instead of ' .. literalToString(left[i]))
                    assert(not isMultiSym(as[1]), 'did not expect multi symbol')
                    as = stringMangle(as, scope)
                else
                    error('unknwon key in destructure: ' .. sub)
                end
            else
                skeyPairs[#skeyPairs + 1] = {
                    expr = stringMangle(sub, scope),
                    key = i
                }
            end
        end
    else
        error('unable to destructure ' .. literalToString(left))
    end
    -- Now build it
    if as or rightFirst.singleEval then
        if not as then as = gensym(scope) end
        parent[#parent + 1] = ('local %s = %s'):format(as, rightFirst.expr[1])
    else
        as = rightFirst.expr[1]
    end
    for i, skpair in ipairs(skeyPairs) do
        parent[#parent + 1] = ('local %s = %s[%s]'):format(skpair.expr, as, skpair.key)
    end
end

-- Unlike most expressions and specials, 'values' resolves with multiple
-- values, one for each argument, allowing multiple return values. The last
-- expression, can return multiple arguments as well, allowing for more than the number
-- of expected arguments.
local function values(ast, scope, parent, start)
    local returnValues = list()
    local scoped, sideEffects, singleEval, unknownExprCount = false, false, false, false
    for i = start or 2, ast.n do
        local tail
        if i == ast.n then
            tail = compileExpr(ast[i], scope, parent)
        else
            tail = compileTossRest(ast[i], scope, parent)
        end
        listAppend(returnValues, tail.expr)
        if tail.scoped then scoped = true end
        if tail.sideEffects then sideEffects = true end
        if tail.singleEval then singleEval = true end
    end
    return {
        scoped = scoped,
        sideEffects = sideEffects,
        singleEval = singleEval,
        expr = returnValues,
        unknownExprCount = unknownExprCount
    }
end

-- Implements packing an ast into a single value.
local function pack(ast, scope, parent, i, j)
    local tail = SPECIALS.values(ast, scope, parent)
    local expr = '{' .. table.concat(tail.expr, ', ', i, j) .. '}'
    tail.expr = list(expr)
    tail.unknownExprCount = false
    tail.singleEval = true
    tail.sideEffects = true -- Are there necessarily side-effects? Is creating a table a side effect?
    return tail
end

-- Implements a do statment, starting at the 'start' element. By default, start is 2.
local function doImpl(ast, scope, parent, subScope, chunk, start, forceScoped)
    subScope = subScope or makeScope(scope)
    chunk = chunk or {}
    local tail = compileTail(ast, subScope, chunk)
    local expr, sideEffects, singleEval, validStatement, unknownExprCount, scoped =
        tail.expr, tail.sideEffects, tail.singleEval, tail.validStatement, tail.unknownExprCount, tail.scoped
    if unknownExprCount then -- Use imediately invoked closure to wrap instead of do ... end
        chunk[#chunk + 1] = ('return %s'):format(table.concat(expr, ', '))
        local s = gensym(scope)
        -- Use CPS to make varargs accesible to inner function scope.
        local farg = scope.vararg and '...' or ''
        parent[#parent + 1] = ('local function %s(%s)'):format(s, farg)
        parent[#parent + 1] = chunk
        parent[#parent + 1] = 'end'
        expr = list(s .. ('(%s)'):format(farg))
        singleEval = true
        scoped = true
        sideEffects = true
        validStatement = true
    else -- Use do ... end - preferred because more efficient
        if expr.n > 0 and (scoped or forceScoped) then
            singleEval, sideEffects, validStatement = false, false, false
            local syms = {n = expr.n}
            for i = 1, expr.n do
                syms[i] = gensym(scope)
            end
            local s = table.concat(syms, ', ')
            parent[#parent + 1] = 'local ' .. s
            chunk[#chunk + 1] = ('%s = %s'):format(s, table.concat(expr, ', '))
            expr = setmetatable(syms, LIST_MT)
        end
        parent[#parent + 1] = 'do'
        parent[#parent + 1] = chunk
        parent[#parent + 1] = 'end'
    end
    return {
        scoped = scoped or forceScoped,
        expr = expr,
        sideEffects = sideEffects,
        singleEval = singleEval,
        validStatement = validStatement,
        unknownExprCount = unknownExprCount
    }
end

SPECIALS['do'] = doImpl
SPECIALS['values'] = values
SPECIALS['pack'] = pack

-- The fn special declares a function. Syntax is similar to other lisps;
-- (fn optional-name [arg ...] (body))
-- Further decoration such as docstrings, meta info, and multibody functions a possibility.
SPECIALS['fn'] = function(ast, scope, parent)
    local fScope = makeScope(scope)
    local index = 2
    local fnName = isSym(ast[index])
    local isLocalFn = not isMultiSym(fnName[1])
    if fnName then
        fnName = stringMangle(fnName[1], scope)
        index = index + 1
    else
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
    local fChunk = {}
    local tail = compileTail(ast, fScope, fChunk, index + 1)
    local expr = table.concat(tail.expr, ', ')
    fChunk[#fChunk + 1] = 'return ' .. expr
    parent[#parent + 1] = ('%sfunction %s(%s)')
        :format(isLocalFn and 'local ' or '', fnName, table.concat(argNameList, ', '))
    parent[#parent + 1] = fChunk
    parent[#parent + 1] = 'end'
    return {
        expr = list(fnName),
        scoped = true
    }
end

SPECIALS['special'] = function(ast, scope, parent)
    assert(scopeInside(COMPILER_SCOPE, scope), 'can only declare special forms in \'eval-compiler\'')
    local spec = SPECIALS.fn(ast, scope, parent)
    local specialName = spec.expr[1] -- the fn special form always returns a value
    local lit = literalToString(specialName)
    parent[#parent + 1] = ('_SCOPE.specials[%s] = %s'):format(lit, specialName)
    return spec
end

SPECIALS['macro'] = function(ast, scope, parent)
    assert(scopeInside(COMPILER_SCOPE, scope), 'can only declare macros in \'eval-compiler\'')
    local mac = SPECIALS.fn(ast, scope, parent)
    local macroName = mac.expr[1] -- the fn special form always returns a value
    local lit = literalToString(macroName)
    local s = gensym(scope)
    parent[#parent + 1] = ('local function %s(ast, scope, chunk)'):format(s)
    parent[#parent + 1] = {
        'local unpack = table.unpack or unpack',
        ('return _FNL.compileExpr(%s(unpack(ast, 2, ast.n), scope, chunk))'):format(macroName)
    }
    parent[#parent + 1] = 'end'
    parent[#parent + 1] = ('_SCOPE.specials[%s] = %s'):format(lit, s)
    mac.expr = list(s)
    return mac
end

-- Wrapper for table access
SPECIALS['.'] = function(ast, scope, parent)
    local lhs = compileTossRest(ast[2], scope, parent)
    local rhs = compileTossRest(ast[3], scope, parent)
    return {
        expr = list(('%s[%s]'):format(lhs.expr[1], rhs.expr[1])),
        scoped = lhs.scoped or rhs.scoped,
        singleEval = true,
        sideEffects = true
    }
end

-- Wrap a variadic number of arguments into a table. Does NOT do length capture.
SPECIALS['pack'] = function(ast, scope, parent)
    return pack(ast, scope, parent)
end

local function defineSetterSpecial(name, prefix, noMulti)
    local formatString = ('%s%%s = %%s'):format(prefix)
    SPECIALS[name] = function(ast, scope, parent)
        local vars = {}
        for i = 2, math.max(2, ast.n - 1) do
            local s = assert(isSym(ast[i]))
            if noMulti then
                assert(not isMultiSym(s[1]), 'did not expect multi symbol')
            end
            vars[i - 1] = stringMangle(s[1], scope)
        end
        local varname = table.concat(vars, ', ')
        local assign = table.concat(compileExpr(ast[ast.n], scope, parent).expr, ', ')
        if assign == '' then
            assign = 'nil'
        end
        parent[#parent + 1] = formatString:format(varname, assign)
    end
end

-- Simple wrappers for declaring and setting locals.
defineSetterSpecial('var', 'local ', true)
defineSetterSpecial('set', '')

SPECIALS['let'] = function(ast, scope, parent)
    local bindings = ast[2]
    assert(isTable(bindings), 'expected table for destructuring')
    local subScope = makeScope(scope)
    local subChunk = {}
    for i = 1, bindings.n or #bindings, 2 do
        destructure(bindings[i], bindings[i + 1], subScope, subChunk)
    end
    return doImpl(ast, scope, parent, subScope, subChunk, 3, true)
end

-- For setting items in a table
SPECIALS['tset'] = function(ast, scope, parent)
    local root = compileExpr(ast[2], scope, parent).expr[1]
    local keys = {}
    for i = 3, ast.n - 1 do
        local key = compileTossRest(ast[i], scope, parent).expr[1]
        keys[#keys + 1] = key
    end
    local value = compileTossRest(ast[ast.n], scope, parent).expr[1]
    parent[#parent + 1] = ('%s[%s] = %s'):format(root, table.concat(keys, ']['), value)
end

-- Add a comment to the generated code.
SPECIALS['--'] = function(ast, scope, parent)
    for i = 2, ast.n do
        local com = ast[i]
        assert(type(com) == 'string', 'expected string comment')
        parent[#parent + 1] = '-- ' .. com:gsub('\n', '\n-- ')
    end
end

-- Executes a series of statements. Unlike do, evaultes to nil.
-- this potentially simplifies the resulting Lua code. It certainly
-- simplifies the implementation.
SPECIALS['block'] = function(ast, scope, parent)
    local subScope = makeScope(scope)
    parent[#parent + 1] = 'do'
    local chunk = {}
    compileDo(ast, subScope, chunk, 2)
    parent[#parent + 1] = chunk
    parent[#parent + 1] = 'end'
end

-- Special form for branching - covers all situations with if, elseif, and else.
-- Not meant to be used in most user code, targeted by macros.
SPECIALS['*branch'] = function(ast, scope, parent)
    -- First condition
    local condition = compileTossRest(ast[2], scope, parent)
    parent[#parent + 1] = 'if ' .. condition.expr[1] .. ' then'
    local len = ast.n or #asr
    local subScope = makeScope(scope)
    local subChunk = {}
    local i = 3
    while i <= len do
        local subAst = ast[i]
        if isSym(subAst) and subAst[1] == '*branch' then
            parent[#parent + 1] = subChunk
            subChunk = {}
            i = i + 1
            local nextSym = ast[i]
            assert(isSym(nextSym), 'expected symbol after branch')
            local symVal = nextSym[1]
            subScope = makeScope(scope)
            if symVal == 'else' then
                parent[#parent + 1] = 'else'
            elseif symVal == 'elseif' then
                i = i + 1
                condition = compileTossRest(ast[i], scope, parent)
                parent[#parent + 1] = 'elseif ' .. condition.expr[1] .. ' then'
            else
                error('expected \'else\' or \'elseif\' after \'branch\'.')
            end
        else
            compileDo(ast[i], subScope, subChunk)
        end
        i = i + 1
    end
    parent[#parent + 1] = subChunk
    parent[#parent + 1] = 'end'
end

SPECIALS['*while'] = function(ast, scope, parent)
    local condition = compileTossRest(ast[2], scope, parent)
    parent[#parent + 1] = 'while ' .. condition.expr[1] .. ' do'
    local subChunk = {}
    compileDo(ast, makeScope(scope), subChunk, 3)
    parent[#parent + 1] = subChunk
    parent[#parent + 1] = 'end'
end

SPECIALS['*dowhile'] = function(ast, scope, parent)
    local condition = compileTossRest(ast[2], scope, parent)
    parent[#parent + 1] = 'repeat'
    local subChunk = {}
    compileDo(ast, makeScope(scope), subChunk, 3)
    parent[#parent + 1] = subChunk
    parent[#parent + 1] = 'until ' .. condition.expr[1]
end

SPECIALS['*for'] = function(ast, scope, parent)
    local bindingSym = assert(isSym(ast[2]), 'expected symbol in *for')
    local ranges = assert(isTable(ast[3]), 'expected list table in *for')
    local rangeArgs = {}
    for i = 1, math.min(#ranges, 3) do
        rangeArgs[i] = compileTossRest(ranges[i], scope, parent).expr[1]
    end
    parent[#parent + 1] = ('for %s = %s do')
        :format(literalToString(bindingSym, scope), table.concat(rangeArgs, ', '))
    local chunk = {}
    local subScope = makeScope(scope)
    compileDo(ast, subScope, chunk, 4)
    parent[#parent + 1] = chunk
    parent[#parent + 1] = 'end'
end

-- Do wee need this? Is there a more elegnant way to comile with break?
SPECIALS['*break'] = function(ast, scope, parent)
    parent[#parent + 1] = 'break'
end

local function defineArithmeticSpecial(name, unaryPrefix)
    local paddedOp = ' ' .. name .. ' '
    SPECIALS[name] = function(ast, scope, parent)
        local len = ast.n or #ast
        local head = {}
        if len == 0 then
            head.expr = list(unaryPrefix or '0')
        else
            local operands = list()
            local subSingleEval, sideEffects, scoped = false, false, false
            for i = 2, len do
                local subTree
                if i == len then
                    subTree = compileExpr(ast[i], scope, parent)
                else
                    subTree = compileTossRest(ast[i], scope, parent)
                end
                listAppend(operands, subTree.expr)
                if subTree.singleEval then subSingleEval = true end
                if subTree.sideEffects then sideEffects = true end
                if subTree.scoped then scoped = true end
            end
            head.sideEffects = sideEffects
            head.scoped = scoped
            if #operands == 1 and unaryPrefix then
                head.singleEval = true
                head.expr = list('(' .. unaryPrefix .. paddedOp .. operands[1] .. ')')
            else
                head.singleEval = #operands > 1 or subSingleEval
                head.expr = list('(' .. table.concat(operands, paddedOp) .. ')')
            end
        end
        return head
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
        local lhs = compileTossRest(ast[2], scope, parent)
        local rhs = compileTossRest(ast[3], scope, parent)
        return {
            sideEffects = lhs.sideEffects or rhs.sideEffects,
            singleEval = true,
            expr = list(('((%s) %s (%s))'):format(lhs.expr[1], op, rhs.expr[1])),
            scoped = lhs.scoped or rhs.scoped
        }
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
        local tail = compileTossRest(ast[2], scope, parent)
        return {
            singleEval = true,
            sideEffects = tail.sideEffects,
            expr = list((realop or op) .. tail.expr[1]),
            scoped = tail.scoped
        }
    end
end

defineUnarySpecial('not', 'not ')
defineUnarySpecial('#')

local function compileAst(ast, options)
    options = options or {}
    local scope = options.scope or makeScope(GLOBAL_SCOPE)
    return transpile(ast, scope, options)
end

local function compile(str, options)
    options = options or {}
    local asts, len = parse(str)
    local scope = options.scope or makeScope(GLOBAL_SCOPE)
    local bodies = {}
    for i = 1, len do
        local source = transpile(asts[i], scope, {
            returnTail = i == len
        })
        bodies[#bodies + 1] = source
    end
    return table.concat(bodies, '\n')
end

local function eval(str, options)
    options = options or {}
    local luaSource = compile(str, options)
    local loader = loadCode(luaSource, options.env)
    return loader()
end

-- Implements a simple repl
local function repl(options)
    local defaultPrompt = '>> '
    options = options or {}
    local env = options.env or setmetatable({}, {
        __index = _ENV or _G
    })
    while true do
        io.write(env._P or defaultPrompt)
        local reader = createReader(function()
            return io.read() .. '\n'
        end)
        local ok, err = pcall(function()
            return parse(reader, function(x)
                local luaSource = compileAst(x, {
                    returnTail = true
                })
                local loader, err = loadCode(luaSource, env)
                if err then
                    print(err)
                else
                    local ret = tpack(loader())
                    for i = 1, ret.n do
                        ret[i] = astToString(ret[i])
                    end
                    print(unpack(ret))
                    io.write(env._P or defaultPrompt)
                    io.flush()
                end
            end)
        end)
        if not ok then
            print(debug.traceback(err))
        end
    end
end

local module = {
    parse = parse,
    astToString = astToString,
    compile = compile,
    compileAst = compileAst,
    compileExpr = compileExpr,
    compileTossRest = compileTossRest,
    compileDo = compileDo,
    list = list,
    sym = sym,
    varg = varg,
    scope = makeScope,
    gensym = gensym,
    createReader = createReader,
    eval = eval,
    repl = repl
}

SPECIALS['eval-compiler'] = function(ast, scope, parent)
    local oldFirst = ast[1]
    ast[1] = sym('do')
    local luaSource = compileAst(ast, {
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
