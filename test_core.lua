local fnl = require("fnl")
local t = require("lunatest")

local calculations = {
    ["(+ 1 2 (- 1 2))"]=2,
    ["(* 1 2 (/ 1 2))"]=1,
    ["(+ 1 2 (^ 1 2))"]=4,
    ["(+ 1 2 (- 1 2))"]=2,
    ["(% 1 2 (- 1 2))"]=0,
}

local test_calculations = function()
    for code, expected in pairs(calculations) do
        t.assert_equal(expected, fnl.eval(code))
    end
end

return {test_calculations = test_calculations}
