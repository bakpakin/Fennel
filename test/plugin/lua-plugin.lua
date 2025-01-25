-- inject some macros into rootScope
local fennel = require('fennel')

local function inscope(s)
    return _G['in-scope?'](s)
end

local rootScope = fennel.scope()
while rootScope.parent do rootScope = rootScope.parent end

rootScope.macros['is-in-scope'] = inscope

return {name = "in-scope-lua-plugin", versions = "^1.5"}
