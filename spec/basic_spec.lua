local fnl = require 'fnl'

local fixtures = {
    2, [[(+ 1 2 (- 1 2))]],
    1, [[(* 1 2 (/ 1 2))]],
    4, [[(+ 1 2 (^ 1 2))]],
    2, [[(+ 1 2 (- 1 2))]],
    0, [[(% 1 2 (- 1 2))]],
}

describe('basic calculations are correct.', function()
    for i = 1, #fixtures, 2 do
        it('correctly does fixture ' .. i, function()
            assert.are.same(fixtures[i], fnl.eval(fixtures[i + 1]))
        end)
    end
end)
