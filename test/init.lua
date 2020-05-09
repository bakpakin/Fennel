local l = require("luaunit")
-- prevent luarocks-installed fennel from overriding
package.loaded.fennel = dofile("fennel.lua")
table.insert(package.loaders or package.searchers, package.loaded.fennel.searcher)
package.loaded.fennelview = package.loaded.fennel.dofile("fennelview.fnl")

-- luaunit wants the test suite in a really weird alist format
local function test(moduleName)
    local i = {}
    for k,v in pairs(require(moduleName)) do
        table.insert(i, {k, v})
    end
    print("Running", moduleName)
    l.LuaUnit:runSuiteByInstances(i)
end

-- these tests need to be in Lua; if anything here breaks, we can't even load
-- our tests that are written in Fennel.
test("test.core")
test("test.mangling")
test("test.quoting")
test("test.misc")

-- these can be in Fennel
test("test.docstring")
test("test.fennelview")
test("test.failures")
test("test.repl")
test("test.cli")

os.exit(l.LuaUnit.result.notSuccessCount > 0 and 1 or 0)
