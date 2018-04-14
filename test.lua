local fennel = require("fennel")
table.insert(package.loaders or package.searchers, fennel.searcher)
local generate = require("generate")
local view = require("fennelview")

-- Allow deterministic re-runs of generated things.
local seed = os.getenv("SEED") or os.time()
print("SEED=" .. seed)
math.randomseed(seed)

-- to store values in during tests
tbl = {}

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
        ["(> 2 0 -1)"]=true,
        ["(<= 5 1 91)"]=false,
        ["(> -4 89)"]=false,
        ["(< -4 89)"]=true,
        ["(>= 22 (+ 21 1))"]=true,
        ["(<= 88 32)"]=false,
        ["(~= 33 1)"]=true,
        ["(let [f (fn [] (tset tbl :dbl (+ 1 (or (. tbl :dbl) 0))) 1)]\
            (< 0 (f) 2) (. tbl :dbl))"]=1,
    },

    parsing = {
        ["\"\\\\\""]="\\",
        ["\"abc\\\"def\""]="abc\"def",
        ["\'abc\\\"\'"]="abc\"",
        ["\"abc\\240\""]="abc\240",
    },

    functions = {
        -- regular function
        ["((fn [x] (* x 2)) 26)"]=52,
        -- nested functions
        ["(let [f (fn [x y f2] (+ x (f2 y)))\
                  f2 (fn [x y] (* x (+ 2 y)))\
                  f3 (fn [f] (fn [x] (f 5 x)))]\
                  (f 9 5 (f3 f2)))"]=44,
        -- closures can set vars they close over
        ["(var a 11) (let [f (fn [] (set a (+ a 2)))] (f) (f) a)"]=15,
        -- partial application
        ["(let [add (fn [x y] (+ x y)) inc (partial add 1)] (inc 99))"]=100,
        ["(let [add (fn [x y z] (+ x y z)) f2 (partial add 1 2)] (f2 6))"]=9,
        ["(let [add (fn [x y] (+ x y)) add2 (partial add)] (add2 99 2))"]=101,
        -- functions with empty bodies return nil
        ["(if (= nil ((fn [a]) 1)) :pass :fail)"]="pass",
        -- basic lambda
        ["((lambda [x] (+ x 2)) 4)"]=6,
        -- vararg lambda
        ["((lambda [x ...] (+ x 2)) 4)"]=6,
        -- lambdas perform arity checks
        ["(let [(ok e) (pcall (lambda [x] (+ x 2)))]\
            (string.match e \"Missing argument x\"))"]="Missing argument x",
        -- lambda arity checks skip argument names starting with ?
        ["(let [(ok val) (pcall (λ [?x] (+ (or ?x 1) 8)))] (and ok val))"]=9,
        -- method calls work
        ["(: :hello :find :e)"]=2,
        -- method calls don't double side effects
        ["(var a 0) (let [f (fn [] (set a (+ a 1)) :hi)] (: (f) :find :h)) a"]=1,
    },

    conditionals = {
        -- basic if
        ["(let [x 1 y 2] (if (= (* 2 x) y) \"yep\"))"]="yep",
        -- if can contain side-effects
        ["(var x 12) (if true (set x 22) 0) x"]=22,
        -- else branch works
        ["(if false \"yep\" \"nope\")"]="nope",
        -- else branch runs on nil
        ["(if non-existent 1 (* 3 9))"]=27,
        -- else works with temporaries
        ["(let [x {:y 2}] (if false \"yep\" (< 1 x.y 3) \"uh-huh\" \"nope\"))"]="uh-huh",
        -- when is for side-effects
        ["(var [a z] [0 0]) (when true (set a 192) (set z 12)) (+ z a)"]=204,
        -- when treats nil as falsey
        ["(var a 884) (when nil (set a 192)) a"]=884,
        -- when body does not run on false
        ["(when (= 12 88) (os.exit 1)) false"]=false,
    },

    core = {
        -- comments
        ["74 ; (require \"hey.dude\")"]=74,
        -- comments go to the end of the line
        ["(var x 12) ;; (set x 99)\n x"]=12,
        -- calling built-in lua functions
        ["(table.concat [\"ab\" \"cde\"] \",\")"]="ab,cde",
        -- table lookup
        ["(let [t []] (table.insert t \"lo\") (. t 1))"]="lo",
        -- nested table lookup
        ["(let [t [[21]]] (+ (. (. t 1) 1) (. t 1 1)))"]=42,
        -- table lookup base case
        ["(let [x 17] (. 17))"]=17,
        -- set works with multisyms
        ["(let [t {}] (set t.a :multi) (. t :a))"]="multi",
        -- set works on parent scopes
        ["(var n 0) (let [f (fn [] (set n 96))] (f) n)"]=96,
        -- local names with dashes in them
        ["(let [my-tbl {} k :key] (tset my-tbl k :val) my-tbl.key)"]="val",
        -- functions inside each
        ["(var i 0) (each [_ ((fn [] (pairs [1])))] (set i 1)) i"]=1,
        -- let with nil value
        ["(let [x 3 y nil z 293] z)"]=293,
        -- nested let inside loop
        ["(var a 0) (for [_ 1 3] (let [] (table.concat []) (set a 33))) a"]=33,
        -- set can be used as expression
        ["(var x 1) (let [_ (set x 92)] x)"]=92,
        -- tset can be used as expression
        ["(let [t {} _ (tset t :a 84)] (. t :a))"]=84,
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
        -- multiple values without function wrapper
        ["(let [(a [b [c] d]) (values 4 [2 [1] 9])] (+ a b c d))"]=16,
        -- global destructures tables
        ["(global [a b c d] [4 2 43 7]) (+ (* a b) (- c d))"]=44,
        -- global works with multiple values
        ["(global (a b) ((fn [] (values 4 29)))) (+ a b)"]=33,
        -- local keyword
        ["(local (-a -b) ((fn [] (values 4 29)))) (+ -a -b)"]=33,
        -- rest args
        ["(let [[a b & c] [1 2 3 4 5]] (+ a (. c 2) (. c 3)))"]=10,
        -- all vars get flagged as var
        ["(var [a [b c]] [1 [2 3]]) (set a 2) (set c 8) (+ a b c)"]=12,
    },

    loops = {
        -- numeric loop
        ["(var x 0) (for [y 1 5] (set x (+ x 1))) x"]=5,
        -- numeric loop with step
        ["(var x 0) (for [y 1 20 2] (set x (+ x 1))) x"]=10,
        -- while loop
        ["(var x 0) (while (< x 7) (set x (+ x 1))) x"]=7,
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
            if expected ~= res then
                fail = fail + 1
                print(" Expected " .. view(res) .. " to be " .. view(expected))
            else
                pass = pass + 1
            end
        end
    end
end

local count = function(t)
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end

local function table_equal(a, b, deep_equal)
    local miss_a, miss_b = {}, {}
    for k in pairs(a) do
        if deep_equal(a[k], b[k]) then a[k], b[k] = nil, nil end
    end
    for k, v in pairs(a) do
        if type(k) ~= "table" then miss_a[view(k)] = v end
    end
    for k, v in pairs(b) do
        if type(k) ~= "table" then miss_b[view(k)] = v end
    end
    return (count(a) == count(b)) or deep_equal(miss_a, miss_b)
end

local function deep_equal(a, b)
    if (a ~= a) or (b ~= b) then return true end -- don't fail on nan
    if type(a) == type(b) then
        if type(a) == "table" then return table_equal(a, b, deep_equal) end
        return tostring(a) == tostring(b)
    end
end

print("Running tests for viewer...")
for _ = 1, 16 do
    local item = generate()
    local ok, viewed = pcall(view, item)
    if ok then
        local ok2, round_tripped = pcall(fennel.eval, viewed)
        if(ok2) then
            if deep_equal(item, round_tripped) then
                pass = pass + 1
            else
                print("Expected " .. viewed .. " to round-trip thru view/eval: "
                          .. tostring(round_tripped))
                fail = fail + 1
            end
        else
            print(" Error loading viewed item: " .. viewed, round_tripped)
            err = err + 1
        end
    else
        print(" Error viewing " .. tostring(item))
        err = err + 1
    end
end

fennel.eval([[(eval-compiler
  (tset _SPECIALS "reverse-it" (fn [ast scope parent opts]
    (tset ast 1 "do")
    (for [i 2 (math.ceil (/ (# ast) 2))]
      (let [a (. ast i) b (. ast (- (# ast) (- i 2)))]
        (tset ast (- (# ast) (- i 2)) a)
        (tset ast i b)))
    (_SPECIALS.do ast scope parent opts)))
)]])

local macro_cases = {
    -- just a boring old set+fn combo
    ["(require-macros \"test-macros\")\
      (defn hui [x y] (global z (+ x y))) (hui 8 4) z"]=12,
    -- macros with mangled names
    ["(require-macros \"test-macros\")\
      (->1 9 (+ 2) (* 11))"]=121,
    -- require-macros doesn't leak into new evaluation contexts
    ["(let [(_ e) (pcall (fn [] (->1 8 (+ 2))))] (: e :match :global))"]="global",
    -- macros loaded in function scope shouldn't leak to other functions
    ["((fn [] (require-macros \"test-macros\") (global x1 (->1 99 (+ 31)))))\
      (pcall (fn [] (global x1 (->1 23 (+ 1)))))\
      x1"]=130,
    -- special form
    ["(reverse-it 1 2 3 4 5 6)"]=1,
}

print("Running tests for macro system...")
for code, expected in pairs(macro_cases) do
    local ok, res = pcall(fennel.eval, code)
    if not ok then
        err = err + 1
        print(" Error: " .. res .. " in: ".. fennel.compile(code))
    else
        local actual = fennel.eval(code)
        if expected ~= actual then
            fail = fail + 1
            print(" Expected " .. view(actual) .. " to be " .. view(expected))
            print("   Compiled to: " .. fennel.compileString(code))
        else
            pass = pass + 1
        end
    end
end

local compile_failures = {
    ["(f"]="unexpected end of source",
    ["(+))"]="unexpected closing delimiter",
    ["(fn)"]="expected vector arg list",
    ["(fn [12])"]="expected symbol for function parameter",
    ["(fn [:huh] 4)"]="expected symbol for function parameter",
    ["(fn [false] 4)"]="expected symbol for function parameter",
    ["(fn [nil] 4)"]="expected symbol for function parameter",
    ["(lambda [x])"]="missing body",
    ["(let [x 1])"]="missing body",
    ["(let [x 1 y] 8)"]="expected even number of name/value bindings",
    ["(let [:x 1] 1)"]="unable to destructure",
    ["(let [false 1] 9)"]="unable to destructure false",
    ["(let [nil 1] 9)"]="unable to destructure nil",
    ["(let [[a & c d] [1 2]] c)"]="rest argument in final position",
    ["(set a 19)"]="expected local var a",
    ["(set [a b c] [1 2 3]) (+ a b c)"]="expected local var",
    ["(not true false)"]="expected one argument",
    -- compiler environment
    ["(defn [:foo] [] nil)"]="defn.*function names must be symbols",
    -- line numbers
    ["(set)"]="Compile error in 'set' unknown:1: expected name and value",
    ["(let [b 9\nq (.)] q)"]="2: expected table argument",
    ["(do\n\n\n(each \n[x 34 (pairs {})] 21))"]="4: expected iterator symbol",
    ["(fn []\n(for [32 34 32] 21))"]="2: expected iterator symbol",
    ["\n\n(let [f (lambda []\n(local))] (f))"]="4: expected name and value",
    ["(do\n\n\n(each \n[x (pairs {})] (when)))"]="when' unknown:5:",
    -- macro errors have macro names in them
    ["\n(when)"]="Compile error in .when. unknown:2",
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

-- Mapping from any string to Lua identifiers. (in practice, will only be from fennel identifiers to lua, 
-- should be general for programatically created symbols)
local mangling_tests = {
    ['a'] = 'a',
    ['a_3'] = 'a_3',
    ['3'] = '__fnl_global__3', -- a fennel symbol would usually not be a number
    ['a-b-c'] = '__fnl_global__a_2db_2dc',
    ['a_b-c'] = '__fnl_global__a_5fb_2dc',
}

for k, v in pairs(mangling_tests) do
    local manglek = fennel.mangle(k)
    local unmanglev = fennel.unmangle(v)
    if v ~= manglek then
        print(" Expected fennel.mangle(" .. k .. ") to be " .. v .. ", got " .. manglek)
        fail = fail + 1
    else
        pass = pass + 1
    end
    if k ~= unmanglev then
        print(" Expected fennel.unmangle(" .. v .. ") to be " .. k .. ", got " .. unmanglev)
        fail = fail + 1
    else
        pass = pass + 1
    end
end

print(string.format("\n%s passes, %s failures, %s errors.", pass, fail, err))
if(fail > 0 or err > 0) then os.exit(1) end
