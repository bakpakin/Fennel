local utils = require("fennel.utils")
local parser = require("fennel.parser")
local unpack = _G.unpack or table.unpack

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
local function applyManglings(scope, newManglings, ast)
    for raw, mangled in pairs(newManglings) do
        assertCompile(not scope.refedglobals[mangled],
        "use of global " .. raw .. " is aliased by a local", ast)
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

-- Generates a unique symbol in the scope.
local function gensym(scope, base)
    local mangling
    local append = 0
    repeat
        mangling = (base or '') .. '_' .. append .. '_'
        append = append + 1
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
            -- occurance and updates plen to be the index of the last
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
                else
                    if utils.isSym(k) and tostring(k) == ":" and utils.isSym(v) then
                        k = tostring(v)
                    end
                    if type(k) ~= "number" then k = serializeString(k) end
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

