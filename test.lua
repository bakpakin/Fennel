-- don't use require; that will pick up luarocks-installed module, not checkout
local fennel = dofile("fennel.lua")
table.insert(package.loaders or package.searchers, fennel.searcher)
package.loaded.fennel = fennel
local generate = fennel.dofile("generate.fnl")
local view = fennel.dofile("fennelview.fnl")

-- Allow deterministic re-runs of generated things.
local seed = os.getenv("SEED") or os.time()
print("SEED=" .. seed)
math.randomseed(seed)

local pass, fail, err = 0, 0, 0

-- one global to store values in during tests
_G.tbl = {}

---- core language tests ----

local cases = {
    calculations = {
        ["(+ 1 2 (- 1 2))"]=2,
        ["(* 1 2 (/ 1 2))"]=1,
        ["(+ 1 2 (^ 1 2))"]=4,
        ["(% 1 2 (- 1 2))"]=0,
        -- 1 arity results
        ["(- 1)"]=-1,
        ["(/ 2)"]=1/2,
        -- ["(// 2)"]=1//2,
        -- 0 arity results
        ["(+)"]=0,
        ["(*)"]=1,
    },

    booleans = {
        ["(or false nil true 12 false)"]=true,
        ["(or 11 true false)"]=11,
        ["(and true 12 \"hey\")"]="hey",
        ["(and 43 table false)"]=false,
        ["(not true)"]=false,
        ["(not 39)"]=false,
        ["(not nil)"]=true,
        -- 1 arity results
        ["(or 5)"]=5,
        ["(and 5)"]=5,
        -- 0 arity results
        ["(or)"]=false,
        ["(and)"]=true,
    },

    comparisons = {
        ["(> 2 0)"]=true,
        ["(> 2 0 -1)"]=true,
        ["(<= 5 1 91)"]=false,
        ["(> -4 89)"]=false,
        ["(< -4 89)"]=true,
        ["(>= 22 (+ 21 1))"]=true,
        ["(<= 88 32)"]=false,
        ["(not= 33 1)"]=true,
        ["(~= 33 1)"]=true, -- undocumented alias for backwards-compatibility
        ["(= 1 1 2 2)"]=false,
        ["(not= 6 6 9)"]=true,
        ["(let [f (fn [] (tset tbl :dbl (+ 1 (or (. tbl :dbl) 0))) 1)]\
            (< 0 (f) 2) (. tbl :dbl))"]=1,
    },

    parsing = {
        ["\"\\\\\""]="\\",
        ["\"abc\\\"def\""]="abc\"def",
        ["\"abc\\240\""]="abc\240",
        ["\"abc\n\\240\""]="abc\n\240",
        ["150_000"]=150000,
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
        ["(if _G.non-existent 1 (* 3 9))"]=27,
        -- else works with temporaries
        ["(let [x {:y 2}] (if false \"yep\" (< 1 x.y 3) \"uh-huh\" \"nope\"))"]="uh-huh",
        -- when is for side-effects
        ["(var [a z] [0 0]) (when true (set a 192) (set z 12)) (+ z a)"]=204,
        -- when treats nil as falsey
        ["(var a 884) (when nil (set a 192)) a"]=884,
        -- when body does not run on false
        ["(when (= 12 88) (os.exit 1)) false"]=false,
        -- make sure bad code isn't emitted when an always-true
        -- condition exists in the middle of an if
        ["(if false :y true :x :trailing :condition)"]="x",
        ["(let [b :original b (if false :not-this)] (or b :nil))"]="nil",
        -- make sure nested/assigned conditionals always set the tgt,
        -- and don't double-emit "else"
        ["(let [x 3 res (if (= x 1) :ONE (= x 2) :TWO true :???)] res)"] = "???",
        -- Conditional of while
        ["(while (let [f false] f) (lua :break))"]=nil,
        ["(var i 0) (var s 0) (while (let [l 11] (< i l)) (set s (+ s i)) (set i (+ 1 i))) s"]=55
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
        -- table lookup with literal
        ["(+ (. {:a 93 :b 4} :a) (. [1 2 3] 2))"]=95,
        -- table lookup with literal using matching-key-and-variable shorthand
        ["(let [k 5 t {: k}] t.k)"]=5,
        -- set works with multisyms
        ["(let [t {}] (set t.a :multi) (. t :a))"]="multi",
        -- set works on parent scopes
        ["(var n 0) (let [f (fn [] (set n 96))] (f) n)"]=96,
        -- set-forcibly! works on local & let vars
        ["(local a 3) (let [b 2] (set-forcibly! a 7) (set-forcibly! b 6) (+ a b))"]=13,
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
        -- Setting multivalue vars
        ["(do (var a nil) (var b nil) (local ret (fn [] a)) (set (a b) (values 4 5)) (ret))"]=4,
        -- Tset doesn't screw up with table literal
        ["(do (tset {} :a 1) 1)"]=1,
        -- # is valid symbol constituent character
        ["(local x#x# 90) x#x#"]=90,
        -- : works on literal tables
        ["(: {:foo (fn [self] (.. self.bar 2)) :bar :baz} :foo)"]="baz2",
        -- line numbers correlated with input
        ["(fn b [] (each [e {}] (e))) (let [(_ e) (pcall b)] (e:match \":1.*\"))"]=
            ":1: attempt to call a table value",
        -- mangling avoids global names
        ["(global a_b :global) (local a-b :local) a_b"]="global",
        -- global definition doesn't count as local
        ["(global x 1) (global x 284) x"]=284,
    },

    ifforms = {
        ["(do (fn myfn [x y z] (+ x y z)) (myfn 1 (if 1 2 3) 4))"]=7,
        ["(do (fn myfn [x y z] (+ x y z)) (myfn 1 (if 1 (values 2 5) 3) 4))"]=7,
        ["(let [x (if false 3 (values 2 5))] x)"]=2,
        ["(if (values 1 2) 3 4)"]=3,
        ["(if (values 1) 3 4)"]=3,
        ["(do (fn myfn [x y z] (+ x y z)) (myfn 1 4 (if 1 2 3)))"]=7,
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
        -- rest args on lambda
        ["((lambda [[a & b]] (+ a (. b 2))) [90 99 4])"]=94,
        -- all vars get flagged as var
        ["(var [a [b c]] [1 [2 3]]) (set a 2) (set c 8) (+ a b c)"]=12,
        -- fn args
        ["((fn dest [a [b c] [d]] (+ a b c d)) 5 [9 7] [2])"]=23,
        -- each
        ["(var x 0) (each [_ [a b] (ipairs [[1 2] [3 4]])] (set x (+ x (* a b)))) x"]=14,
        -- key/value destructuring
        ["(let [{:a x :b y} {:a 2 :b 4}] (+ x y))"]=6,
        -- key/value destructuring with the same names
        ["(let [{: a : b} {:a 3 :b 5}] (+ a b))"]=8,
        -- nesting k/v and sequential
        ["(let [{:a [x y z]} {:a [1 2 4]}] (+ x y z))"]=7,
        -- Local shadowing in let form
        ["(let [x 1 x (if (= x 1) 2 3)] x)"]=2,
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
        -- indirect iterators
        ["(var t 0) (local (f s v) (pairs [1 2 3])) \
          (each [_ x (values f s v)] (set t (+ t x))) t"]=6,
        ["(var t 0) (local (f s v) (pairs [1 2 3])) \
          (each [_ x (values f (doto s (table.remove 1)))] (set t (+ t x))) t"]=5,
    },

    edge = {
        -- IIFE in if statement required
        ["(let [(a b c d e f g) (if (= (+ 1 1) 2) (values 1 2 3 4 5 6 7))] (+ a b c d e f g))"]=28,
        -- IIFE in if statement required v2
        ["(let [(a b c d e f g) (if (= (+ 1 1) 3) nil\
                                       ((or _G.unpack table.unpack) [1 2 3 4 5 6 7]))]\
            (+ a b c d e f g))"]=28,
        -- IIFE if test v3
        ["(length [(if (= (+ 1 1) 2) (values 1 2 3 4 5) (values 1 2 3))])"]=5,
        -- IIFE if test v4
        ["(select \"#\" (if (= 1 (- 3 2)) (values 1 2 3 4 5) :onevalue))"]=5,
        -- Values special in array literal
        ["(length [(values 1 2 3 4 5)])"]=5,
        ["(let [x (if 3 4 5)] x)"]=4,
        -- Ambiguous Lua syntax generated
        ["(let [t {:st {:v 5 :f #(+ $.v $2)}} x (#(+ $ $2) 1 3)] (t.st:f x) nil)"]=nil,
        ["(do (local c1 20) (local c2 40) (fn xyz [A B] (and A B)) " ..
         "(xyz (if (and c1 c2) true false) 52))"]=52
    },

    macros = {
        -- built-in macros
        ["(let [x [1]]\
            (doto x (table.insert 2) (table.insert 3)) (table.concat x))"]="123",
        -- arrow threading
        ["(-> (+ 85 21) (+ 1) (- 99))"]=8,
        ["(->> (+ 85 21) (+ 1) (- 99))"]=-8,
        -- nil-safe forms
        ["(-?> {:a {:b {:c :z}}} (. :a) (. :b) (. :c))"]="z",
        ["(-?> {:a {:b {:c :z}}} (. :a) (. :missing) (. :c))"]=nil,
        ["(-?>> :w (. {:w :x}) (. {:x :y}) (. {:y :z}))"]="z",
        ["(-?>> :w (. {:w :x}) (. {:x :missing}) (. {:y :z}))"]=nil,
        -- just a boring old set+fn combo
        ["(require-macros \"test-macros\")\
          (defn1 hui [x y] (global z (+ x y))) (hui 8 4) z"]=12,
        -- macros with mangled names
        ["(require-macros \"test-macros\")\
          (->1 9 (+ 2) (* 11))"]=121,
        -- special form
        [ [[(eval-compiler
             (tset _SPECIALS "reverse-it" (fn [ast scope parent opts]
               (tset ast 1 "do")
               (for [i 2 (math.ceil (/ (length ast) 2))]
                 (let [a (. ast i) b (. ast (- (length ast) (- i 2)))]
                   (tset ast (- (length ast) (- i 2)) a)
                   (tset ast i b)))
               (_SPECIALS.do ast scope parent opts))))
           (reverse-it 1 2 3 4 5 6)]]]=1,
        -- nesting quote can only happen in the compiler
        ["(eval-compiler (set tbl.nest ``nest))\
          (tostring tbl.nest)"]="(quote nest)",
        -- inline macros
        ["(macros {:plus (fn [x y] `(+ ,x ,y))}) (plus 9 9)"]=18,
        -- Vararg in quasiquote
        ["(macros {:x (fn [] `(fn [...] (+ 1 1)))}) ((x))"]=2,
        -- Threading macro with single function, with and without parens
        ["(-> 1234 (string.reverse) (string.upper))"]="4321",
        ["(-> 1234 string.reverse string.upper)"]="4321",
        -- Auto-gensym
        ["(macros {:m (fn [y] `(let [xa# 1] (+ xa# ,y)))}) (m 4)"]=5,
    },
    hashfn = {
        -- Basic hashfn
        ["(#(+ $1 $2) 3 4)"]=7,
        -- Ignore arguments hashfn
        ["(#(+ $3 $4) 1 1 3 4)"]=7,
        -- One argument
        ["(#(+ $1 45) 1)"]=46,
        -- Immediately returned argument
        ["(+ (#$ 1) (#$2 2 3))"]=4,
        -- With let
        ["(let [f #(+ $1 45)] (f 1))"]=46,
        -- Complex body
        ["(let [f #(do (local a 1) (local b (+ $1 $1 a)) (+ a b))] (f 1))"]=4,
        -- Basic hashfn ($)
        ["(#(+ $ 2) 3)"]=5,
        -- Mixed $ types
        ["(let [f #(+ $ $1 $2)] (f 1 2))"]=4,
        -- Multisyms containing $ arguments
        ["(#$.foo {:foo :bar})"]="bar",
        ["(#$2.foo.bar.baz nil {:foo {:bar {:baz :quux}}})"]="quux",
    },
    methodcalls = {
        -- multisym method call
        ["(let [x {:foo (fn [self arg1] (.. self.bar arg1)) :bar :baz}] (x:foo :quux))"]=
            "bazquux",
        -- multisym method call on property
        ["(let [x {:y {:foo (fn [self arg1] (.. self.bar arg1)) :bar :baz}}] (x.y:foo :quux))"]=
            "bazquux",
    },
    match = {
        -- basic literal
        ["(match (+ 1 6) 7 8)"]=8,
        -- actually return the one that matches
        ["(match (+ 1 6) 7 8 8 1 9 2)"]=8,
        -- string literals? and values that come from locals?
        ["(let [s :hey] (match s :wat :no :hey :yes))"]="yes",
        -- tables please
        ["(match [:a :b :c] [a b c] (.. b :eee))"]="beee",
        -- tables with literals in them
        ["(match [:a :b :c] [1 t d] :no [a b :d] :NO [a b :c] b)"]="b",
        -- nested tables
        ["(match [:a [:b :c]] [a b :c] :no [:a [:b c]] c)"]="c",
        -- non-sequential tables
        ["(match {:a 1 :b 2} {:c 3} :no {:a n} n)"]=1,
        -- nested non-sequential
        ["(match [:a {:b 8}] [a b :c] :no [:a {:b b}] b)"]=8,
        -- unification
        ["(let [k :k] (match [5 :k] :b :no [n k] n))"]=5,
        -- length mismatch
        ["(match [9 5] [a b c] :three [a b] (+ a b))"]=14,
        -- 3rd arg may be nil here
        ["(match [9 5] [a b ?c] :three [a b] (+ a b))"]="three",
        -- no double-eval
        ["(var x 1) (fn i [] (set x (+ x 1)) x) (match (i) 4 :N 3 :n 2 :y)"]="y",
        -- multi-valued
        ["(match (values 5 9) 9 :no (a b) (+ a b))"]=14,
        -- multi-valued with nil
        ["(match (values nil :nonnil) (true _) :no (nil b) b)"]="nonnil",
        -- error values
        ["(match (io.open \"/does/not/exist\") (nil msg) :err f f)"]="err",
        -- last clause becomes default
        ["(match [1 2 3] [3 2 1] :no [2 9 1] :NO :default)"]="default",
        ["(let [x 3 res (match x 1 :ONE 2 :TWO _ :???)] res)"]="???",
        -- intra-pattern unification
        ["(match [1 2 3] [x y x] :no [x y z] :yes)"]="yes",
        ["(match [1 2 1] [x y x] :yes)"]="yes",
        ["(match (values 1 [1 2]) (x [x x]) :no (x [x y]) :yes)"]="yes",
        -- external unification
        ["(let [x 95] (match [52 85 95] [x y z] :nope [a b x] :yes))"]="yes",
        -- deep nested unification
        ["(match [1 2 [[3]]] [x y [[x]]] :no [x y z] :yes)"]="yes",
        ["(match [1 2 [[1]]] [x y [z]] (. z 1))"]=1,
        -- _ wildcard
        ["(match [1 2] [_ _] :wildcard)"]="wildcard",
        ["(match nil _ :yes nil :no)"]="yes",
        -- rest args
        ["(match [1 2 3] [a & b] (+ a (. b 1) (. b 2)))"]=6,
        ["(match [1] [a & b] (# b))"]=0,
        -- guard clause
        ["(match {:sieze :him} \
            (tbl ? (. tbl :no)) :no \
            (tbl ? (. tbl :sieze)) :siezed)"]="siezed",
        -- multiple guard clauses
        ["(match {:sieze :him} \
            (tbl ? tbl.sieze tbl.no) :no \
            (tbl ? tbl.sieze (= tbl.sieze :him)) :siezed2)"]="siezed2",
        -- guards with patterns inside
        ["(match [{:sieze :him} 5] \
            ([f 4] ? f.sieze (= f.sieze :him)) 4\
            ([f 5] ? f.sieze (= f.sieze :him)) 5)"]=5,
        ["(match [1] [a & b] (length b))"]=0,
        -- multisym
        ["(let [x {:y :z}] (match :z x.y 1 _ 0))"]=1,
        -- never unify underscore
        ["(let [_ :bar] (match :foo _ :should-match :foo :no))"]="should-match",
    },
    fennelview = { -- generative fennelview tests are also below
        ["((require :fennelview) {:a 1 :b 52})"]="{\n  :a 1\n  :b 52\n}",
        ["((require :fennelview) {:a 1 :b 5} {:one-line true})"]="{:a 1 :b 5}",
        ["((require :fennelview) (let [t {}] [t t]))"]="[ {} #<table 2> ]",
        ["((require :fennelview) (let [t {}] [t t]) {:detect-cycles? false})"]=
            "[ {} {} ]",
    },
}

for name, tests in pairs(cases) do
    print("Running tests for " .. name .. "...")
    for code, expected in pairs(tests) do
        local ok, res = pcall(fennel.eval, code, {correlate = true})
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

fennel.eval("(eval-compiler (set _SPECIALS.reverse-it nil))") -- clean up

---- fennelview tests ----

local function count(t)
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

print("Running tests for fennelview...")
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

---- tests for compilation failures ----

local compile_failures = {
    ["(f"]="expected closing delimiter %) in unknown:1",
    ["\n\n(+))"]="unexpected closing delimiter %) in unknown:3",
    ["(fn)"]="expected vector arg list",
    ["(fn [12])"]="expected symbol for function parameter",
    ["(fn [:huh] 4)"]="expected symbol for function parameter",
    ["(fn [false] 4)"]="expected symbol for function parameter",
    ["(fn [nil] 4)"]="expected symbol for function parameter",
    ["(lambda [x])"]="missing body",
    ["(let [x 1])"]="missing body",
    ["(let [x 1 y] 8)"]="expected even number of name/value bindings",
    ["(let [[a & c d] [1 2]] c)"]="rest argument in final position",
    ["(set a 19)"]="error in 'set' unknown:1: expected local var a",
    ["(set [a b c] [1 2 3]) (+ a b c)"]="expected local var",
    ["(let [x 1] (set-forcibly! x 2) (set x 3) x)"]="expected local var",
    ["(not true false)"]="expected one argument",
    ["\n\n(let [x.y 9] nil)"]="unknown:3: did not expect multi",
    ["()"]="expected a function to call",
    ["(789)"]="789.*cannot call literal value",
    ["(fn [] [...])"]="unexpected vararg",
    -- line numbers
    ["(set)"]="Compile error in 'set' unknown:1: expected name and value",
    ["(let [b 9\nq (.)] q)"]="2: expected table argument",
    ["(do\n\n\n(each \n[x 34 (pairs {})] 21))"]="4: expected iterator symbol",
    ["(fn []\n(for [32 34 32] 21))"]="2: expected iterator symbol",
    ["\n\n(let [f (lambda []\n(local))] (f))"]="4: expected name and value",
    ["(do\n\n\n(each \n[x (pairs {})] (when)))"]="when' unknown:5:",
    -- macro errors have macro names in them
    ["\n(when)"]="Compile error in .when. unknown:2",
    -- strict about unknown global reference
    ["(hey)"]="unknown global",
    ["(fn global-caller [] (hey))"]="unknown global",
    ["(let [bl 8 a bcd] nil)"]="unknown global",
    ["(let [t {:a 1}] (+ t.a BAD))"]="BAD",
    ["(each [k v (pairs {})] (BAD k v))"]="BAD",
    ["(global good (fn [] nil)) (good) (BAD)"]="BAD",
    -- shadowing built-ins
    ["(global + 1)"]="overshadowed",
    ["(global // 1)"]="overshadowed",
    ["(global let 1)"]="overshadowed",
    ["(global - 1)"]="overshadowed",
    ["(let [global 1] 1)"]="overshadowed",
    ["(fn global [] 1)"]="overshadowed",
    -- symbol capture detection
    ["(macros {:m (fn [y] `(let [x 1] (+ x ,y)))}) (m 4)"]=
        "tried to bind x without gensym",
    ["(macros {:m (fn [t] `(fn [xabc] (+ xabc 9)))}) ((m 4))"]=
        "tried to bind xabc without gensym",
    ["(macros {:m (fn [t] `(each [mykey (pairs ,t)] (print mykey)))}) (m [])"]=
        "tried to bind mykey without gensym",
    -- legal identifier rules
    ["(let [:x 1] 1)"]="unable to bind",
    ["(let [false 1] 9)"]="unable to bind false",
    ["(let [nil 1] 9)"]="unable to bind nil",
    ["(local 47 :forty-seven)"]="unable to bind 47",
    ["(global 48 :forty-eight)"]="unable to bind 48",
    ["(let [t []] (set t.47 :forty-seven))"]=
        "can't start multisym segment with digit: t.47",
    ["(let [t []] (set t.:x :y))"]="malformed multisym: t.:x",
    ["(let [t []] (set t:.x :y))"]="malformed multisym: t:.x",
    ["(let [t []] (set t::x :y))"]="malformed multisym: t.:x",
    ["(local a~b 3)"]="illegal character: ~",
    ["(print @)"]="illegal character: @",
    -- unused locals checking
    ["(let [x 1 y 2] y)"]="unused local x",
    ["(fn [xx y] y)"]="unused local xx",
    ["(fn [_x y z] y)"]="unused local z",
    -- unmangled globals shouldn't conflict with mangled locals
    ["(local a-b 1) (global a_b 2)"]="global a_b conflicts with local",
    ["(local a-b 1) (global [a_b] [2])"]="global a_b conflicts with local",
    -- macros loaded in function scope shouldn't leak to other functions
    ["((fn [] (require-macros \"test-macros\") (global x1 (->1 99 (+ 31)))))\
      (->1 23 (+ 1))"]="unknown global in strict mode",
    -- other
    ["(match [1 2 3] [a & b c] nil)"]="rest argument in final position",
    ["(x(y))"]="expected whitespace before opening delimiter %(",
    ["(x[1 2])"]="expected whitespace before opening delimiter %[",
    ["(let [x {:foo (fn [self] self.bar) :bar :baz}] x:foo)"]=
        "multisym method calls may only be in call position",
    ["(let [x {:y {:foo (fn [self] self.bar) :bar :baz}}] x:y:foo)"]=
        "method call must be last component of multisym: x:y:foo",
}

print("Running tests for compile errors...")
for code, expected_msg in pairs(compile_failures) do
    local ok, msg = pcall(fennel.compileString, code,
                          {allowedGlobals = {"pairs"}, checkUnusedLocals = true})
    if(ok) then
        fail = fail + 1
        print(" Expected failure when compiling " .. code .. ": " .. msg)
    elseif(not msg:match(expected_msg)) then
        fail = fail + 1
        print(" Expected " .. expected_msg .. " when compiling " .. code ..
                  " but got " .. msg)
    else
        pass = pass + 1
    end
end

---- mangling and unmangling ----

-- Mapping from any string to Lua identifiers. (in practice, will only be from
-- fennel identifiers to lua, should be general for programatically created
-- symbols)

local mangling_tests = {
    ['a'] = 'a',
    ['a_3'] = 'a_3',
    ['3'] = '__fnl_global__3', -- a fennel symbol would usually not be a number
    ['a-b-c'] = '__fnl_global__a_2db_2dc',
    ['a_b-c'] = '__fnl_global__a_5fb_2dc',
}

print("Running tests for mangling / unmangling...")
for k, v in pairs(mangling_tests) do
    local manglek = fennel.mangle(k)
    local unmanglev = fennel.unmangle(v)
    if v ~= manglek then
        print(" Expected fennel.mangle(" .. k .. ") to be " .. v ..
                  ", got " .. manglek)
        fail = fail + 1
    else
        pass = pass + 1
    end
    if k ~= unmanglev then
        print(" Expected fennel.unmangle(" .. v .. ") to be " .. k ..
                  ", got " .. unmanglev)
        fail = fail + 1
    else
        pass = pass + 1
    end
end

---- quoting and unquoting ----

local quoting_tests = {
    ['`:abcde'] = {"return \"abcde\"", "simple string quoting"},
    [',a'] = {"return unquote(a)",
              "unquote outside quote is simply passed thru"},
    ['`[1 2 ,(+ 1 2) 4]'] = {
        "return {1, 2, (1 + 2), 4}",
        "unquote inside quote leads to evaluation"
    },
    ['(let [a (+ 2 3)] `[:hey ,(+ a a)])'] = {
        "local a = (2 + 3)\nreturn {\"hey\", (a + a)}",
        "unquote inside other forms"
    },
    ['`[:a :b :c]'] = {
      "return {\"a\", \"b\", \"c\"}",
      "quoted sequential table"
    },
    ['`{:a 5 :b 9}'] = {
        {
            ["return {[\"a\"]=5, [\"b\"]=9}"] = true,
            ["return {[\"b\"]=9, [\"a\"]=5}"] = true,
        },
      "quoted keyed table"
    }
}

print("Running tests for quote / unquote...")
for k, v in pairs(quoting_tests) do
    local compiled = fennel.compileString(k, {allowedGlobals=false})
    local accepted, ans = v[1]
    if type(accepted) ~= 'table' then
        ans = accepted
        accepted = {}
        accepted[ans] = true
    end
    local message = v[2]
    local errorformat = "While testing %s\n" ..
        "Expected fennel.compileString(\"%s\") to be \"%s\" , got \"%s\""
    if accepted[compiled] then
        pass = pass + 1
    else
        print(errorformat:format(message, k, ans, compiled))
        fail = fail + 1
    end
end

---- docstring tests ----

print("Running tests for metadata and docstrings...")
local docstring_tests = {
    ['(fn foo [a] :C 1) (doc foo)'] = {'(foo a)\n  C',
      'for named functions, (doc fnname) shows name, args invocation, docstring'},
    ['(λ foo [] :D 1) (doc foo)'] = {'(foo)\n  D',
      '(doc fnname) for named lambdas appear like named functions'},
    ['(fn ml [] "a\nmultiline\ndocstring" :result) (doc ml)'] =
        {'(ml)\n  a\n  multiline\n  docstring',
        'multiline docstrings work correctly'},
    [ '(fn ew [] "so \\"gross\\" \\\\\\\"I\\\\\\\" can\'t even" 1) (doc ew)'] =
        {'(ew)\n  so "gross" \\"I\\" can\'t even',
         'docstrings should be auto-escaped'},
    ['(fn foo! [-kebab- {:x x}] 1) (doc foo!)'] =
        { "(foo! -kebab- #<table>)\n  #<undocumented>",
          "fn-name and args mangling" },
    ['(doc doto)'] =
        {"(doto val ...)\n  Evaluates val and splices it into the " ..
             "first argument of subsequent forms.",
         "docstrings for built-in macros"},
    ['(doc doc)'] =
        {"(doc x)\n  Print the docstring and arglist for a function, macro, or special form.",
         "docstrings for special forms"},
    ['(macro abc [x y z] "this is a macro." :123) (doc abc)'] =
        {"(abc x y z)\n  this is a macro.",
         "docstrings for user-defined macros"},
    ['(doc table.concat)'] =
        {"(table.concat #<unknown-arguments>)\n  #<undocumented>",
         "docstrings for built-in Lua functions"},
    ['(let [x-tbl []] (fn x-tbl.y! [d] "why" 123) (doc x-tbl.y!))'] =
        {"(x-tbl.y! d)\n  why",
         "docstrings for mangled multisyms"},
    ['(let [f (fn [] "f" :f) g (fn [] f)] (doc (g)))'] =
        {"((g))\n  f",
         "doc on expression"},
    ['(local generate (fennel.dofile "generate.fnl" {:useMetadata true})) (doc generate)'] =
        {"(generate table-chance)\n  Generate a random piece of data.",
         "docstrings from required module."}
}

local docEnv = setmetatable({ print = function(x) return x end, fennel = fennel},
    { __index=_G })

for code, cond_msg in pairs(docstring_tests) do
    local expected, msg = (unpack or table.unpack)(cond_msg)
    local ok, actual = pcall(fennel.eval, code, { useMetadata = true, env = docEnv })
    if ok and expected == actual then
        pass = pass + 1
    elseif ok then
        fail = fail + 1
        print(string.format('While testing %s,\n\tExpected "%s" to be "%s"',
                            msg, actual, expected))
    else
        err = err + 1
        print(string.format('While testing %s, got error:\n\t%s', msg, actual))
    end
end

-- we don't need to mention these forms...
local undocumentedOk = {["lua"]=true, ["set-forcibly!"]=true, include=true }
fennel.eval("(eval-compiler (set fennel._SPECIALS _SPECIALS))")
for name in pairs(fennel._SPECIALS) do
    if((not undocumentedOk[name]) and (fennel.eval(("(doc %s )"):format(name),
                                           { useMetadata = true, env = docEnv })
                                       :find("undocumented"))) then
        fail = fail + 1
        print("Missing docstring for " .. name)
    end
end


---- misc one-off tests ----

if pcall(fennel.eval, "(->1 1 (+ 4))", {allowedGlobals = false}) then
    fail = fail + 1
    print(" Expected require-macros not leak into next evaluation.")
else
    pass = pass + 1
end

if pcall(fennel.eval, "`(hey)", {allowedGlobals = false}) then
    fail = fail + 1
    print(" Expected quoting lists to fail at runtime.")
else
    pass = pass + 1
end

if pcall(fennel.eval, "`[hey]", {allowedGlobals = false}) then
    fail = fail + 1
    print(" Expected quoting syms to fail at runtime.")
else
    pass = pass + 1
end

if not pcall(fennel.eval, "(.. hello-world :w)",
             {env = {["hello-world"] = "hi"}}) then
    fail = fail + 1
    print(" Expected global mangling to work.")
else
    pass = pass + 1
end

-- include test - writes file to file system
do
    local bazsrc = [[
    [:BAZ 3]
    ]]

    local barsrc = [[
    (local bar [:BAR 2])
    (each [_ v (ipairs (include :baz))]
    (table.insert bar v))
    bar
    ]]

    local foosrc = [[
    (local foo [:FOO 1])
    (local bar (include :bar))
    (.. "foo:" (table.concat foo "-") "bar:" (table.concat bar "-"))
    ]]

    local function spit(path, src)
        local f = io.open(path, 'w')
        f:write(src)
        f:close()
    end

    -- Write files.
    spit('bar.fnl', barsrc)
    spit('baz.fnl', bazsrc)

    local ok, result = pcall(fennel.eval, foosrc)
    if ok and result == "foo:FOO-1bar:BAR-2-BAZ-3" then
        pass = pass + 1
    else
        fail = fail + 1
        print(" Expected include to work.")
    end

    -- Remove files
    os.remove('bar.fnl')
    os.remove('baz.fnl')
end

local g = {["hello-world"] = "hi", tbl = _G.tbl,
    -- tragically lua 5.1 does not have metatable-aware pairs so we fake it here
    pairs = function(t)
        local mt = getmetatable(t)
        if(mt and mt.__pairs) then
            return mt.__pairs(t)
        else
            return pairs(t)
        end
    end}
g._G = g

if(not pcall(fennel.eval, "(each [k (pairs _G)] (tset tbl k true))", {env = g})
   or not _G.tbl["hello-world"]) then
    fail = fail + 1
    print(" Expected wrapped _G to support env iteration.")
else
    pass = pass + 1
end

do
    local e = {}
    if (not pcall(fennel.eval, "(global x-x 42)", {env = e})
        or not pcall(fennel.eval, "x-x", {env = e})) then
        fail = fail + 1
        print(" Expected mangled globals to be accessible across eval invocations.")
    else
        pass = pass + 1
    end
end

---- REPL tests ----
print("Running tests for REPL completion...")
local wrapRepl = function()
    local replComplete
    local replSend = coroutine.wrap(function()
        local output = {}
        fennel.repl({
            readChunk = function()
                local chunk = coroutine.yield(output)
                output = {}
                return chunk and chunk .. '\n' or nil
            end,
            onValues = function(xs)
                table.insert(output, xs)
            end,
            registerCompleter = function(completer)
                replComplete = completer
            end,
            pp = function(x) return x end,
        })
    end) replSend()
    return replSend, replComplete
end

-- Skip REPL tests in non-JIT Lua 5.1 only to avoid engine coroutine bug
if _VERSION ~= 'Lua 5.1' or type(jit) == 'table' then
    local send, comp = wrapRepl()
    send('(local [foo foo-bar* moe-larry] [1 2 {:*curly* "Why soitenly!"}])')
    send('(local [!x-y !x_y] [1 2])')
    local testCases = {
        {comp'foo',  {'foo', 'foo-bar*'},
            'local completion works & accounts for mangling'},
        {comp'moe-larry.', { 'moe-larry.*curly*' },
            'completion traverses tables without mangling keys when input is "tbl-var."'},
        {send'(values !x-y !x_y)', {{1, 2}},
            'mangled locals do not collide'},
        {comp'!x', {'!x-y', '!x_y'},
            'completions on mangled locals do not collide'},
    }
    for _, results in ipairs(testCases) do
        local a, b, msg = (unpack or table.unpack)(results)
        if deep_equal(a, b) then
            pass = pass + 1
        else
            fail = fail + 1
            print(string.format('Expected: %s to be %s:\n\t%s', a, b, msg))
        end
    end
    send()
else
    print('Skipping REPL tests in (non-LuaJIT) Lua 5.1')
end


print(string.format("\n%s passes, %s failures, %s errors.", pass, fail, err))
if(fail > 0 or err > 0) then os.exit(1) end
