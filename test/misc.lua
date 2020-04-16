local l = require("luaunit")
local fennel = require("fennel")

local function test_leak()
    l.assertFalse(pcall(fennel.eval, "(->1 1 (+ 4))", {allowedGlobals = false}),
                  "Expected require-macros not leak into next evaluation.")
end

local function test_runtime_quote()
    l.assertFalse(pcall(fennel.eval, "`(hey)", {allowedGlobals = false}),
                  "Expected quoting lists to fail at runtime.")
    l.assertFalse(pcall(fennel.eval, "`[hey]", {allowedGlobals = false}),
                  "Expected quoting syms to fail at runtime.")
end

local function test_global_mangling()
    l.assertTrue(pcall(fennel.eval, "(.. hello-world :w)",
                       {env = {["hello-world"] = "hi"}}),
                 "Expected global mangling to work.")
end

local function test_include()
    local quuxsrc = 'return foo or false\n-- comment in lua'
    local bazsrc = '[:BAZ 3]\n'
    local barsrc = ([[
    (local bar [:BAR 2])
    (each [_ v (ipairs (include :baz))]
          (table.insert bar v))
    bar
    ]]):gsub("(\n)%s+$", "%1")

    local foosrc = ([[
    (local foo [:FOO 1])
    (local quux (include :quux))
    (local bar (include :bar))
    {:result (.. "foo:" (table.concat foo "-") "bar:" (table.concat bar "-")) : quux}
    ]]):gsub("(\n)%s+$", "%1")

    local function spit(path, src)
        local f = io.open(path, 'w')
        f:write(src)
        f:close()
    end

    -- Write files.
    spit('quux.lua', quuxsrc)
    spit('baz.fnl', bazsrc)
    spit('bar.fnl', barsrc)

    local expected = "foo:FOO-1bar:BAR-2-BAZ-3"
    local ok, out = pcall(fennel.eval, foosrc)
    l.assertTrue(ok, "Expected foo to work")
    out = out or {}
    l.assertEquals(out.result, expected,
                   "Expected include to have result: " .. expected)
    l.assertFalse(out.quux,
                  "Expected include not to leak upvalues into included modules")

    -- Remove files
    os.remove('quux.lua')
    os.remove('baz.fnl')
    os.remove('bar.fnl')
end

local function test_env_iteration()
    local tbl = {}
    local g = {["hello-world"] = "hi", tbl = tbl,
        -- tragically lua 5.1 does not have metatable-aware pairs so we fake it
        pairs = function(t)
            local mt = getmetatable(t)
            if(mt and mt.__pairs) then
                return mt.__pairs(t)
            else
                return pairs(t)
            end
    end}
    g._G = g

    fennel.eval("(each [k (pairs _G)] (tset tbl k true))", {env = g})
    l.assertTrue(tbl["hello-world"],
                 "Expected wrapped _G to support env iteration.")

    local e, k = {}
    fennel.eval("(global x-x 42)", {env = e})
    fennel.eval("x-x", {env = e})
    for mangled in pairs(e) do k = mangled end
    l.assertEquals(e[k], 42,
                   "Expected mangled globals to be kept across eval invocations.")
end

local function test_empty_values()
    l.assertTrue(fennel.eval[=[
        (let [a (values)
              b (values (values))
              (c d) (values)
              e (if (values) (values))
              f (while (values) (values))
              [g] [(values)]
              {: h} {:h (values)}]
              (not (or a b c d e f g h)))
    ]=], "empty (values) should resolve to nil")

    local broken_code = fennel.compile [[
        (local [x] (values))
        (local {: y} (values))
    ]]
    l.assertNotNil(broken_code, "code should compile")
    l.assertError(broken_code, "code should fail at runtime");
end

return {
    test_leak=test_leak,
    test_runtime_quote=test_runtime_quote,
    test_global_mangling=test_global_mangling,
    test_include=test_include,
    test_env_iteration=test_env_iteration,
    test_empty_values=test_empty_values,
}

