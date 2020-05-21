local l = require("test.luaunit")
local fennel = require("fennel")

_G.tbl = {}

local function test_calculations()
    local cases = {
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
    }
    for code,expected in pairs(cases) do
        l.assertEquals(fennel.eval(code, {correlate=true}), expected, code)
    end
end

local function test_booleans()
    local cases = {
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
    }
    for code,expected in pairs(cases) do
        l.assertEquals(fennel.eval(code, {correlate=true}), expected, code)
    end
end

local function test_comparisons()
    local cases = {
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
    }
    for code,expected in pairs(cases) do
        l.assertEquals(fennel.eval(code, {correlate=true}), expected, code)
    end
end

local function test_parsing()
    local cases = {
        ["\"\\\\\""]="\\",
        ["\"abc\\\"def\""]="abc\"def",
        ["\"abc\\240\""]="abc\240",
        ["\"abc\n\\240\""]="abc\n\240",
        ["150_000"]=150000,
    }
    for code,expected in pairs(cases) do
        l.assertEquals(fennel.eval(code, {correlate=true}), expected, code)
    end
end

local function test_functions()
    local cases = {
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
        -- pick-args
        ["(let [f (fn [...] [...]) f-2 (pick-args 2 f)] (f-2 1 2 3))"]={1,2},
        ["(let [f (fn [...] [...]) f-0 (pick-args 0 f)] (f-0 :foo))"]={},
        ["((pick-args 5 (partial select :#)))"] = 5,
        -- pick-values
        ["[(pick-values 4 :a :b :c (values :d :e))]"]={'a','b','c','d'},
        ["(let [f #(values :a :b :c)] [(pick-values 0 (f))])"]={},
        ["(select :# (pick-values 3))"]=3,
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
    }
    for code,expected in pairs(cases) do
        l.assertEquals(fennel.eval(code, {correlate=true}), expected, code)
    end
end

local function test_conditionals()
    local cases = {
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
    }
    for code,expected in pairs(cases) do
        l.assertEquals(fennel.eval(code, {correlate=true}), expected, code)
    end
end

local function test_core()
    local cases = {
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
        -- tset with let inside binds correctly
        ["(let [t []] (tset t :a (let [{: a} {:a :bcd}] a)) t.a)"]="bcd",
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
        -- do/let shadowing
        ["(let [xx (let [xx 1] (* xx 2))] xx)"]=2,
        ["(var [x y] [3 2]) (set (x y) (do (local [x y] [(* x 3) 0]) (values x y))) (+ x y)"]=9,
    }
    for code,expected in pairs(cases) do
        l.assertEquals(fennel.eval(code, {correlate=true}), expected, code)
    end
end

local function test_if()
    local cases = {
        ["(do (fn myfn [x y z] (+ x y z)) (myfn 1 (if 1 2 3) 4))"]=7,
        ["(do (fn myfn [x y z] (+ x y z)) (myfn 1 (if 1 (values 2 5) 3) 4))"]=7,
        ["(let [x (if false 3 (values 2 5))] x)"]=2,
        ["(if (values 1 2) 3 4)"]=3,
        ["(if (values 1) 3 4)"]=3,
        ["(do (fn myfn [x y z] (+ x y z)) (myfn 1 4 (if 1 2 3)))"]=7,
    }
    for code,expected in pairs(cases) do
        l.assertEquals(fennel.eval(code, {correlate=true}), expected, code)
    end
end

local function test_destructuring()
    local cases = {
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
    }
    for code,expected in pairs(cases) do
        l.assertEquals(fennel.eval(code, {correlate=true}), expected, code)
    end
end

local function test_loops()
    local cases = {
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
    }
    for code,expected in pairs(cases) do
        l.assertEquals(fennel.eval(code, {correlate=true}), expected, code)
    end
end

local function test_edge()
    local cases = {
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
         "(xyz (if (and c1 c2) true false) 52))"]=52,
        -- Aliasing issues
        ["(. (let [t (let [t {} k :a] (tset t k 123) t) k :b] (tset t k 321) t) :a)"]=123
    }
    for code,expected in pairs(cases) do
        l.assertEquals(fennel.eval(code, {correlate=true}), expected, code)
    end
end

local function test_macros()
    local cases = {
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
        ["(-?> [:a :b] (table.concat \" \"))"]="a b",
        ["(-?>> \" \" (table.concat [:a :b]))"]="a b",
        -- just a boring old set+fn combo
        ["(require-macros \"test.macros\")\
          (defn1 hui [x y] (global z (+ x y))) (hui 8 4) z"]=12,
        -- macros with mangled names
        ["(require-macros \"test.macros\")\
          (->1 9 (+ 2) (* 11))"]=121,
        -- import-macros targeting one name import and one aliased
        ["(import-macros {:defn1 defn : ->1} :test.macros)\
          (defn join [sep ...] (table.concat [...] sep))\
          (join :: :num (->1 5 (* 2) (+ 8)))"]="num:18",
        -- targeting a namespace AND an alias
        ["(import-macros test :test.macros {:inc INC} :test.macros)\
          (INC (test.inc 5))"]=7,
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
        -- macro expanding to macro
        ["(macros {:when2 (fn [c val] `(when ,c ,val))})\
          (when2 true :when2)"]="when2",
        -- macro expanding to indirect macro
        ["(macros {:when3 (fn [c val] `(do (when ,c ,val)))})\
          (when3 true :when3)"]="when3",
        -- Threading macro with single function, with and without parens
        ["(-> 1234 (string.reverse) (string.upper))"]="4321",
        ["(-> 1234 string.reverse string.upper)"]="4321",
        -- Auto-gensym
        ["(macros {:m (fn [y] `(let [xa# 1] (+ xa# ,y)))}) (m 4)"]=5,
        -- macro expanding to primitives
        ["(macro five [] 5) (five)"] = 5,
        ["(macro greet [] :Hi!) (greet)"] = "Hi!",
        ["(macros {:yes (fn [] true) :no (fn [] false)}) [(yes) (no)]"]={true, false},
        -- Side-effecting macros
        ["(macros {:m (fn [x] (set _G.sided x))}) (m 952) _G.sided"]=952,
        -- Macros returning nil in unquote
        ["(import-macros m :test.macros) (var x 1) (m.inc! x 2) (m.inc! x) x"]=4,
    }
    for code,expected in pairs(cases) do
        l.assertEquals(fennel.eval(code, {correlate=true}), expected, code)
    end
    fennel.eval("(eval-compiler (set _SPECIALS.reverse-it nil))") -- clean up
end

local function test_hashfn()
    local cases = {
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
    }
    for code,expected in pairs(cases) do
        l.assertEquals(fennel.eval(code, {correlate=true}), expected, code)
    end
end

local function test_method_calls()
    local cases = {
        -- multisym method call
        ["(let [x {:foo (fn [self arg1] (.. self.bar arg1)) :bar :baz}] (x:foo :quux))"]=
            "bazquux",
        -- multisym method call on property
        ["(let [x {:y {:foo (fn [self arg1] (.. self.bar arg1)) :bar :baz}}] (x.y:foo :quux))"]=
            "bazquux",
    }
    for code,expected in pairs(cases) do
        l.assertEquals(fennel.eval(code, {correlate=true}), expected, code)
    end
end

local function test_match()
    local cases = {
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
    }
    for code,expected in pairs(cases) do
        l.assertEquals(fennel.eval(code, {correlate=true}), expected, code)
    end
end

local function test_fennelview()
    local cases = { -- generative fennelview tests are also below
        ["((require :fennelview) {:a 1 :b 52})"]="{\n  :a 1\n  :b 52\n}",
        ["((require :fennelview) {:a 1 :b 5} {:one-line true})"]="{:a 1 :b 5}",
        ["((require :fennelview) (let [t {}] [t t]))"]="[{} #<table 2>]",
        ["((require :fennelview) (let [t {}] [t t]) {:detect-cycles? false})"]=
            "[{} {}]",
        -- ensure fennelview works on lists and syms
        ["(eval-compiler (set _G.out ((require :fennelview) '(a {} [1 2])))) _G.out"]=
            "(a {} [1 2])",
    }
    for code,expected in pairs(cases) do
        l.assertEquals(fennel.eval(code, {correlate=true}), expected, code)
    end
    local mt = setmetatable({}, {__fennelview=function() return "META" end})
    l.assertEquals(require("fennelview")(mt), "META")
end

return {
    test_calculations = test_calculations,
    test_booleans = test_booleans,
    test_comparisons = test_comparisons,
    test_parsing = test_parsing,
    test_functions = test_functions,
    test_conditionals = test_conditionals,
    test_core = test_core,
    test_if = test_if,
    test_destructuring = test_destructuring,
    test_loops = test_loops,
    test_edge = test_edge,
    test_macros = test_macros,
    test_hashfn = test_hashfn,
    test_method_calls = test_method_calls,
    test_match = test_match,
    test_fennelview = test_fennelview,
}
