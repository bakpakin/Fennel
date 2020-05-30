local l = require("test.luaunit")
local fennel = require("fennel")

local mangling_tests = {
    ['a'] = 'a',
    ['a_3'] = 'a_3',
    ['3'] = '__fnl_global__3', -- a fennel symbol would usually not be a number
    ['a-b-c'] = '__fnl_global__a_2db_2dc',
    ['a_b-c'] = '__fnl_global__a_5fb_2dc',
}

local function test_mangling()
    for k, v in pairs(mangling_tests) do
        local manglek = fennel.mangle(k)
        local unmanglev = fennel.unmangle(v)
        l.assertEquals(v, manglek)
        l.assertEquals(k, unmanglev)
    end
end

return {test_mangling=test_mangling}
