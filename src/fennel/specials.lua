local utils = require("fennel.utils")
local parser = require("fennel.parser")
local compiler = require("fennel.compiler")
local unpack = _G.unpack or table.unpack

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
    local function getArgName(i, name)
        if utils.isVarg(name) then
            compiler.assert(i == #argList, "expected vararg as last parameter", ast[2])
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
    local argNameList = utils.kvmap(argList, getArgName)
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
        local metaStr = ('require("%s").metadata'):
            format(utils.root.options.moduleName or "fennel")
        compiler.emit(parent, string.format('pcall(function() %s:setall(%s, %s) end)',
                                   metaStr, fnName, table.concat(metaFields, ', ')))
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

-- (each [k v (pairs t)] body...) => []
SPECIALS["each"] = function(ast, scope, parent)
    local binding = compiler.assert(utils.isTable(ast[2]), "expected binding table", ast)
    compiler.assert(#ast >= 3, "expected body expression", ast[1])
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

local function defineComparatorSpecial(name, realop, chainOp)
    local op = realop or name
    SPECIALS[name] = function(ast, scope, parent)
        local len = #ast
        compiler.assert(len > 2, "expected at least two arguments", ast)
        local lhs = compiler.compile1(ast[2], scope, parent, {nval = 1})[1]
        local lastval = compiler.compile1(ast[3], scope, parent, {nval = 1})[1]
        -- avoid double-eval by introducing locals for possible side-effects
        if len > 3 then lastval = once(lastval, ast[3], scope, parent) end
        local out = ('(%s %s %s)'):
            format(tostring(lhs), op, tostring(lastval))
        if len > 3 then
            for i = 4, len do -- variadic comparison
                local nextval = once(compiler.compile1(ast[i], scope, parent, {nval = 1})[1],
                                     ast[i], scope, parent)
                out = (out .. " %s (%s %s %s)"):
                    format(chainOp or 'and', tostring(lastval), op, tostring(nextval))
                lastval = nextval
            end
            out = '(' .. out .. ')'
        end
        return out
    end
    docSpecial(name, {"a", "b", "..."},
               "Comparison operator; works the same as Lua but accepts more arguments.")
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
    return setmetatable({
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
    }, { __index = _ENV or _G })
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
    addMacros(macroLoaded[modname], ast, scope, parent)
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

