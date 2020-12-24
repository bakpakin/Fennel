-- We want to make sure the compiler can load under strict mode
local strict = function(_, k) if k then error("STRICT MODE YALL: " .. k) end end
setmetatable(_G, {__index = strict, __newindex = strict})

-- Ensure we're getting the Fennel we expect, not luarocks or anything
package.loaded.fennel = dofile("fennel.lua")
table.insert(package.loaders or package.searchers, package.loaded.fennel.searcher)
package.loaded.fennelview = package.loaded.fennel.dofile("fennelview.fnl")
package.loaded.fennelfriend = package.loaded.fennel.dofile("src/fennel/friend.fnl")
setmetatable(_G, nil) -- but we don't want strict mode for tests

local runner = require("test.luaunit").LuaUnit:new()
runner:setOutputType(os.getenv("FNL_TEST_OUTPUT") or "tap")

-- We have to load the tests with the old version of Fennel; otherwise
-- bugs in the current implementation will prevent the tests from loading!
local oldfennel = dofile("old/fennel.lua")

local function testall(suites)
    local instances = {}
    for _, test in ipairs(suites) do
        -- attach test modules (which export k/v tables of test fns) as alists
        local suite = oldfennel.dofile("test/" .. test .. ".fnl")
        for name, testfn in pairs(suite) do
            table.insert(instances, {name,testfn})
        end
    end
    return runner:runSuiteByInstances(instances)
end

if(#arg == 0) then
   testall({"core", "mangling", "quoting", "misc", "docstring", "fennelview",
            "failures", "repl", "cli", "macro", "linter"})
else
   testall(arg)
end

os.exit(runner.result.notSuccessCount == 0 and 0 or 1)
