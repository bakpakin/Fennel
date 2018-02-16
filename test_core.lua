local fnl = require("fnl")
local t = require("lunatest")

local make_test = function(data)
    return function()
        for code, expected in pairs(data) do
            local msg = "Expected " .. code .. " to be " .. tostring(expected)
            t.assert_equal(expected, fnl.eval(code), msg)
        end
    end
end

local calculations = {
    ["(+ 1 2 (- 1 2))"]=2,
    ["(* 1 2 (/ 1 2))"]=1,
    ["(+ 1 2 (^ 1 2))"]=4,
    ["(+ 1 2 (- 1 2))"]=2,
    ["(% 1 2 (- 1 2))"]=0,
}

local functions = {
    ["((fn [x] (* x 2)) 26)"]=52,
    ["(let [f (fn [x y f2] (+ x (f2 y)))\
            f2 (fn [x y] (* x (+ 2 y)))\
            f3 (fn [f] (fn [x] (f 5 x)))]\
         (f 9 5 (f3 f2)))"]=44,
    ["(let [a 11 f (fn [] (set a (+ a 2)))] (f) (f) a)"]=15,
    -- TODO: functions without a body don't return nil
    -- ["(if (= nil ((fn [a]) 1)) :pass :fail)"]="pass",
}

local conditionals = {
    ["(let [x 1 y 2] (if (= (* 2 x) y) \"yep\"))"]="yep",
    -- TODO: currently if cannot be used for side-effects
    -- ["(let [x 12] (if true (block (set x 22) x) 0))"]=22,
    ["(if false \"yep\" \"nope\")"]="nope",
    ["(if non-existent 1 (* 3 9))"]=27,
    -- TODO: implement when
    -- ["(do (when true (set a 192) (set z 12)) (+ z a))"]=204,
    -- ["(do (when (= 12 88) (os.exit 1)) false)"]=false,
}

local core = {
    -- TODO: we, uhm. don't have comments yet.
    -- ["(do (set x 12) ;; (set x 99)\n x)"]=12,
    ["(table.concat [\"ab\" \"cde\"] \",\")"]="ab,cde",
    ["(let [t []] (table.insert t \"lo\") (. t 1))"]="lo",
    ["(let [t {} k :key] (tset t k :val) t.key)"]="val",
    -- TODO: setting multiple things at once is broken?
    -- ["(do (set x 1 y 2) y)"]=2,
}

local booleans = {
    ["(or false nil true 12 false)"]=true,
    ["(or 11 true false)"]=11,
    ["(and true 12 \"hey\")"]="hey",
    ["(and 43 table false)"]=false,
    ["(not true)"]=false,
    ["(not 39)"]=false,
    ["(not nil)"]=true,
}

local comparisons = {
    ["(> 2 0)"]=true,
    ["(> -4 89)"]=false,
    ["(< -4 89)"]=true,
    ["(>= 22 (+ 21 1))"]=true,
    ["(<= 88 32)"]=false,
    ["(~= 33 1)"]=true,
}

local loops = {
    ["(let [x 0] (*for y [1 5] (set x (+ x 1))) x)"]=5,
    ["(let [x 0] (*while (< x 7) (set x (+ x 1))) x)"]=7,
}

return {
    test_calculations = make_test(calculations),
    test_fn = make_test(functions),
    test_conditionals = make_test(conditionals),
    test_core = make_test(core),
    test_booleans = make_test(booleans),
    test_comparisons = make_test(comparisons),
    test_loops = make_test(loops),
}
