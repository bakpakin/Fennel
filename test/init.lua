-- prevent luarocks-installed fennel from overriding
package.loaded.fennel = dofile("fennel.lua")
table.insert(package.loaders or package.searchers, package.loaded.fennel.searcher)
package.loaded.fennelview = package.loaded.fennel.dofile("fennelview.fnl")

local lu, outputType = require('luaunit'), os.getenv('FNL_TEST_OUTPUT') or 'tap'
local runner = lu.LuaUnit:new()
runner:setOutputType(outputType)

-- attach test modules (which export k/v tables of test fns) as alists
local function addModule(instances, moduleName)
    for k, v in pairs(require(moduleName)) do
        instances[#instances + 1] = {k, v}
    end
end

local function testAll(testModules)
    local instances = {}
    for _, module in ipairs(testModules) do
        addModule(instances, module)
    end
    return runner:runSuiteByInstances(instances)
end

testAll({
    -- these tests need to be in Lua; if anything here breaks
    -- we can't even load our tests that are written in Fennel.
    'test.core',
    'test.mangling',
    'test.quoting',
    'test.misc',
    -- these can be in fennel
    'test.docstring',
    'test.fennelview',
    'test.failures',
    'test.repl',
    'test.cli',
})

os.exit(runner.result.notSuccessCount == 0 and 0 or 1)
