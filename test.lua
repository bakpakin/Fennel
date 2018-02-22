local fennel = require("fennel")

local cases = {
    calculations = {
        ["(+ 1 2 (- 1 2))"]=2,
        ["(* 1 2 (/ 1 2))"]=1,
        ["(+ 1 2 (^ 1 2))"]=4,
        ["(+ 1 2 (- 1 2))"]=2,
        ["(% 1 2 (- 1 2))"]=0,
    },

    booleans = {
        ["(or false nil true 12 false)"]=true,
        ["(or 11 true false)"]=11,
        ["(and true 12 \"hey\")"]="hey",
        ["(and 43 table false)"]=false,
        ["(not true)"]=false,
        ["(not 39)"]=false,
        ["(not nil)"]=true,
    },

    comparisons = {
        ["(> 2 0)"]=true,
        ["(> -4 89)"]=false,
        ["(< -4 89)"]=true,
        ["(>= 22 (+ 21 1))"]=true,
        ["(<= 88 32)"]=false,
        ["(~= 33 1)"]=true,
    },

    functions = {
        -- regular function
        ["((fn [x] (* x 2)) 26)"]=52,
        -- nested functions
        ["(let [f (fn [x y f2] (+ x (f2 y)))\
            f2 (fn [x y] (* x (+ 2 y)))\
            f3 (fn [f] (fn [x] (f 5 x)))]\
         (f 9 5 (f3 f2)))"]=44,
        -- closures can set variables they close over
        ["(let [a 11 f (fn [] (set a (+ a 2)))] (f) (f) a)"]=15,
        -- functions with empty bodies return nil
        ["(if (= nil ((fn [a]) 1)) :pass :fail)"]="pass",
        -- basic lambda
        ["((lambda [x] (+ x 2)) 4)"]=6,
        -- vararg lambda
        ["((lambda [x ...] (+ x 2)) 4)"]=6,
        -- lambdas perform arity checks
        ["(let [(ok e) (pcall (lambda [x] (+ x 2)))]\
            (string.match e \"Missing argument: x\"))"]="Missing argument: x",
        -- lambda arity checks skip argument names starting with ?
        ["(let [(ok val) (pcall (λ [?x] (+ (or ?x 1) 8)))] (and ok val))"]=9,
    },

    conditionals = {
        -- basic if
        ["(let [x 1 y 2] (if (= (* 2 x) y) \"yep\"))"]="yep",
        -- if can contain side-effects
        ["(let [x 12] (if true (set x 22) 0) x)"]=22,
        -- else branch works
        ["(if false \"yep\" \"nope\")"]="nope",
        -- else branch runs on nil
        ["(if non-existent 1 (* 3 9))"]=27,
        -- when is for side-effects
        ["(do (when true (set a 192) (set z 12)) (+ z a))"]=204,
        -- when body does not run on false
        ["(do (when (= 12 88) (os.exit 1)) false)"]=false,
    },

    core = {
        -- comments
        ["74 ; (require \"hey.dude\")"]=74,
        -- comments go to the end of the line
        ["(do (set x 12) ;; (set x 99)\n x)"]=12,
        -- calling built-in lua functions
        ["(table.concat [\"ab\" \"cde\"] \",\")"]="ab,cde",
        -- table lookup
        ["(let [t []] (table.insert t \"lo\") (. t 1))"]="lo",
        -- local names with dashes in them
        ["(let [my-tbl {} k :key] (tset my-tbl k :val) my-tbl.key)"]="val",
    },

    destructuring = {
        -- regular tables
        ["(let [[a b c d] [4 2 43 7]] (+ (* a b) (- c d)))"]=44,
        -- mismatched count
        ["(let [[a b c] [4 2]] (or c :missing))"]="missing",
        ["(let [[a b] [9 2 49]] (+ a b))"]=11,
        -- recursively
        ["(let [[a [b c] d] [4 [2 43] 7]] (+ (* a b) (- c d)))"]=44,
        -- multiple values
        ["(let [(a b) ((fn [] (values 4 2)))] (+ a b))"]=6,
        -- multiple values recursively
        ["(let [(a [b [c] d]) ((fn [] (values 4 [2 [1] 9])))] (+ a b c d))"]=16,
        -- set destructures tables
        ["(do (set [a b c d] [4 2 43 7]) (+ (* a b) (- c d)))"]=44,
        -- set multiple values
        ["(do (set (a b) ((fn [] (values 4 29)))) (+ a b))"]=33,
    },

    loops = {
        -- numeric loop
        ["(let [x 0] (for [y 1 5] (set x (+ x 1))) x)"]=5,
        -- numeric loop with step
        ["(let [x 0] (for [y 1 20 2] (set x (+ x 1))) x)"]=10,
        -- while loop
        ["(let [x 0] (*while (< x 7) (set x (+ x 1))) x)"]=7,
        -- each loop iterates over tables
        ["(let [t {:a 1 :b 2} t2 {}]\
               (each [k v (pairs t)]\
               (tset t2 k v))\
            (+ t2.a t2.b))"]=3,
    },
}

local pass, fail, err = 0, 0, 0

for name, tests in pairs(cases) do
    print("Running tests for " .. name .. "...")
    for code, expected in pairs(tests) do
        local ok, res = pcall(fennel.eval, code)
        if not ok then
            err = err + 1
            print(" Error: " .. res .. " in: ".. fennel.compile(code))
        else
            local actual = fennel.eval(code)
            if expected ~= actual then
                fail = fail + 1
                print(" Expected " .. tostring(actual) .. " to be " .. tostring(expected))
            else
                pass = pass + 1
            end
        end
    end
end

local compile_failures = {
    ["(f"]="unexpected end of source",
    ["(+))"]="unexpected closing delimiter",
    ["(fn)"]="expected vector arg list",
    ["(lambda [x])"]="missing body",
    ["(let [x 1])"]="missing body",
    ["(. tbl)"]="table and key argument",
    ["(each [x 34 (pairs {})] 21)"]="expected iterator symbol",
    ["(for [32 34 32] 21)"]="expected iterator symbol",
}

print("Running tests for compile errors...")
for code, expected_msg in pairs(compile_failures) do
    local ok, msg = pcall(fennel.compileString, code)
    if(ok) then
        print(" Expected failure when compiling " .. code .. ": " .. msg)
    elseif(not msg:match(expected_msg)) then
        print(" Expected " .. expected_msg .. " when compiling " .. code ..
                  " but got " .. msg)
    end
end

print(string.format("\n%s passes, %s failures, %s errors.", pass, fail, err))
if(fail > 0 or err > 0) then os.exit(1) end
