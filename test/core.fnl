(local l (require :test.luaunit))
(local fennel (require :fennel))

(set _G.tbl [])

(fn test-calculations []
  (let [cases {"(% 1 2 (- 1 2))" 0
               "(* 1 2 (/ 1 2))" 1
               "(*)" 1
               "(+ 1 2 (- 1 2))" 2
               "(+ 1 2 (^ 1 2))" 4
               "(+)" 0
               "(- 1)" (- 1)
               "(/ 2)" (/ 1 2)}]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code {:correlate true}) expected code))))

(fn test-booleans []
  (let [cases {"(and 43 table false)" false
               "(and 5)" 5
               "(and true 12 \"hey\")" "hey"
               "(and)" true
               "(not 39)" false
               "(not nil)" true
               "(not true)" false
               "(or 11 true false)" 11
               "(or 5)" 5
               "(or false nil true 12 false)" true
               "(or)" false}]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code {:correlate true}) expected code))))

(fn test-comparisons []
  (let [cases {"(< -4 89)" true
               "(<= 5 1 91)" false
               "(<= 88 32)" false
               "(= 1 1 2 2)" false
               "(> -4 89)" false
               "(> 2 0 -1)" true
               "(> 2 0)" true
               "(>= 22 (+ 21 1))" true
               "(let [f (fn [] (tset tbl :dbl (+ 1 (or (. tbl :dbl) 0))) 1)]
                   (< 0 (f) 2) (. tbl :dbl))" 1
               "(not= 33 1)" true
               "(not= 6 6 9)" true
               "(~= 33 1)" true ; undocumented backwards-compat alias
               }]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code {:correlate true}) expected code))))

(fn test-parsing []
  (let [cases {"\"\\\\\"" "\\"
               "\"abc\n\\240\"" "abc\n\240"
               "\"abc\\\"def\"" "abc\"def"
               "\"abc\\240\"" "abc\240"
               :150_000 150000}]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code {:correlate true}) expected code))))

(fn test-functions []
  (let [cases {;; regular function
               "((fn [x] (* x 2)) 26)" 52
               ;; basic lambda
               "((lambda [x] (+ x 2)) 4)" 6
               ;; vararg lambda
               "((lambda [x ...] (+ x 2)) 4)" 6
               ;; lambdas perform arity checks
               "(let [(ok e) (pcall (lambda [x] (+ x 2)))]
                  (string.match e \"Missing argument x\"))" "Missing argument x"
               ;; lambda arity checks skip argument names starting with ?
               "(let [(ok val) (pcall (λ [?x] (+ (or ?x 1) 8)))] (and ok val))" 9
               ;; lambda with no body returns nil
               "(if (= nil ((lambda [a]) 1)) :lambda-works)" :lambda-works
               ;; closures can set vars they close over
               "(var a 11) (let [f (fn [] (set a (+ a 2)))] (f) (f) a)" 15
               ;; nested functions
               "(let [f (fn [x y f2] (+ x (f2 y)))
                     f2 (fn [x y] (* x (+ 2 y)))
                     f3 (fn [f] (fn [x] (f 5 x)))]
                  (f 9 5 (f3 f2)))" 44

               ;; pick-args
               "((pick-args 5 (partial select :#)))" 5
               "(let [f (fn [...] [...]) f-0 (pick-args 0 f)] (f-0 :foo))" []
               "(let [f (fn [...] [...]) f-2 (pick-args 2 f)] (f-2 1 2 3))" [1 2]
               ;; pick-values
               "(select :# (pick-values 3))" 3
               "(let [f #(values :a :b :c)] [(pick-values 0 (f))])" []
               "[(pick-values 4 :a :b :c (values :d :e))]" ["a" "b" "c" "d"]

               ;; method calls work
               "(: :hello :find :e)" 2
               ;; method calls don't double up side effects
               "(var a 0) (let [f (fn [] (set a (+ a 1)) :hi)] (: (f) :find :h)) a" 1

               ;; functions with empty bodies return nil
               "(if (= nil ((fn [a]) 1)) :pass :fail)" "pass"

               ;; partial application
               "(let [add (fn [x y z] (+ x y z)) f2 (partial add 1 2)] (f2 6))" 9
               "(let [add (fn [x y] (+ x y)) add2 (partial add)] (add2 99 2))" 101
               "(let [add (fn [x y] (+ x y)) inc (partial add 1)] (inc 99))" 100
               }]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code {:correlate true}) expected code))))

(fn test-conditionals []
  (let [cases {"(if _G.non-existent 1 (* 3 9))" 27
               "(if false \"yep\" \"nope\")" "nope"
               "(if false :y true :x :trailing :condition)" "x"
               "(let [b :original b (if false :not-this)] (or b :nil))" "nil"
               "(let [x 1 y 2] (if (= (* 2 x) y) \"yep\"))" "yep"
               "(let [x 3 res (if (= x 1) :ONE (= x 2) :TWO true :???)] res)" "???"
               "(let [x {:y 2}] (if false \"yep\" (< 1 x.y 3) \"uh-huh\" \"nope\"))" "uh-huh"
               "(var [a z] [0 0]) (when true (set a 192) (set z 12)) (+ z a)" 204
               "(var a 884) (when nil (set a 192)) a" 884
               "(var i 0) (var s 0) (while (let [l 11] (< i l)) (set s (+ s i)) (set i (+ 1 i))) s" 55
               "(var x 12) (if true (set x 22) 0) x" 22
               "(when (= 12 88) (os.exit 1)) false" false
               "(while (let [f false] f) (lua :break))" nil}]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code {:correlate true}) expected code))))

(fn test-core []
  (let [cases {"(+ (. {:a 93 :b 4} :a) (. [1 2 3] 2))" 95
               "(: {:foo (fn [self] (.. self.bar 2)) :bar :baz} :foo)" "baz2"
               "(do (tset {} :a 1) 1)" 1
               "(do (var a nil) (var b nil) (local ret (fn [] a)) (set (a b) (values 4 5)) (ret))" 4
               "(fn b [] (each [e {}] (e))) (let [(_ e) (pcall b)] (e:match \":1.*\"))" ":1: attempt to call a table value"
               "(global a_b :global) (local a-b :local) a_b" "global"
               "(global x 1) (global x 284) x" 284
               "(let [k 5 t {: k}] t.k)" 5
               "(let [my-tbl {} k :key] (tset my-tbl k :val) my-tbl.key)" "val"
               "(let [t [[21]]] (+ (. (. t 1) 1) (. t 1 1)))" 42
               "(let [t []] (table.insert t \"lo\") (. t 1))" "lo"
               "(let [t []] (tset t :a (let [{: a} {:a :bcd}] a)) t.a)" "bcd"
               "(let [t {} _ (tset t :a 84)] (. t :a))" 84
               "(let [t {}] (set t.a :multi) (. t :a))" "multi"
               "(let [x 17] (. 17))" 17
               "(let [x 3 y nil z 293] z)" 293
               "(let [xx (let [xx 1] (* xx 2))] xx)" 2
               "(local a 3) (let [b 2] (set-forcibly! a 7) (set-forcibly! b 6) (+ a b))" 13
               "(local x#x# 90) x#x#" 90
               "(table.concat [\"ab\" \"cde\"] \",\")" "ab,cde"
               "(var [x y] [3 2]) (set (x y) (do (local [x y] [(* x 3) 0]) (values x y))) (+ x y)" 9
               "(var a 0) (for [_ 1 3] (let [] (table.concat []) (set a 33))) a" 33
               "(var i 0) (each [_ ((fn [] (pairs [1])))] (set i 1)) i" 1
               "(var n 0) (let [f (fn [] (set n 96))] (f) n)" 96
               "(var x 1) (let [_ (set x 92)] x)" 92
               "(var x 12) ;; (set x 99)\n x" 12
               "74 ; (require \"hey.dude\")" 74}]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code {:correlate true}) expected code))))

(fn test-if []
  (let [cases {"(do (fn myfn [x y z] (+ x y z)) (myfn 1 (if 1 (values 2 5) 3) 4))" 7
               "(do (fn myfn [x y z] (+ x y z)) (myfn 1 (if 1 2 3) 4))" 7
               "(do (fn myfn [x y z] (+ x y z)) (myfn 1 4 (if 1 2 3)))" 7
               "(if (values 1 2) 3 4)" 3
               "(if (values 1) 3 4)" 3
               "(let [x (if false 3 (values 2 5))] x)" 2}]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code {:correlate true}) expected code))))

(fn test-destructuring []
  (let [cases {"((fn dest [a [b c] [d]] (+ a b c d)) 5 [9 7] [2])" 23
               "((lambda [[a & b]] (+ a (. b 2))) [90 99 4])" 94
               "(global (a b) ((fn [] (values 4 29)))) (+ a b)" 33
               "(global [a b c d] [4 2 43 7]) (+ (* a b) (- c d))" 44
               "(let [(a [b [c] d]) ((fn [] (values 4 [2 [1] 9])))] (+ a b c d))" 16
               "(let [(a [b [c] d]) (values 4 [2 [1] 9])] (+ a b c d))" 16
               "(let [(a b) ((fn [] (values 4 2)))] (+ a b))" 6
               "(let [[a [b c] d] [4 [2 43] 7]] (+ (* a b) (- c d)))" 44
               "(let [[a b & c] [1 2 3 4 5]] (+ a (. c 2) (. c 3)))" 10
               "(let [[a b c d] [4 2 43 7]] (+ (* a b) (- c d)))" 44
               "(let [[a b c] [4 2]] (or c :missing))" "missing"
               "(let [[a b] [9 2 49]] (+ a b))" 11
               "(let [x 1 x (if (= x 1) 2 3)] x)" 2
               "(let [{: a : b} {:a 3 :b 5}] (+ a b))" 8
               "(let [{:a [x y z]} {:a [1 2 4]}] (+ x y z))" 7
               "(let [{:a x :b y} {:a 2 :b 4}] (+ x y))" 6
               "(local (-a -b) ((fn [] (values 4 29)))) (+ -a -b)" 33
               "(var [a [b c]] [1 [2 3]]) (set a 2) (set c 8) (+ a b c)" 12
               "(var x 0) (each [_ [a b] (ipairs [[1 2] [3 4]])] (set x (+ x (* a b)))) x" 14}]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code {:correlate true}) expected code))))

(fn test-loops []
  (let [cases {"(for [y 0 2] nil) (each [x (pairs [])] nil)
          (match [1 2] [x y] (+ x y))" 3
               "(let [t {:a 1 :b 2} t2 {}]
               (each [k v (pairs t)]
               (tset t2 k v))
            (+ t2.a t2.b))" 3
               "(var t 0) (local (f s v) (pairs [1 2 3]))
          (each [_ x (values f (doto s (table.remove 1)))] (set t (+ t x))) t" 5
               "(var t 0) (local (f s v) (pairs [1 2 3]))
          (each [_ x (values f s v)] (set t (+ t x))) t" 6
               "(var x 0) (for [y 1 20 2] (set x (+ x 1))) x" 10
               "(var x 0) (for [y 1 5] (set x (+ x 1))) x" 5
               "(var x 0) (while (< x 7) (set x (+ x 1))) x" 7}]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code) expected code))))

(fn test-edge []
  (let [cases {"(. (let [t (let [t {} k :a] (tset t k 123) t) k :b] (tset t k 321) t) :a)" 123
               "(length [(if (= (+ 1 1) 2) (values 1 2 3 4 5) (values 1 2 3))])" 5
               "(length [(values 1 2 3 4 5)])" 5
               "(let [(a b c d e f g) (if (= (+ 1 1) 2) (values 1 2 3 4 5 6 7))] (+ a b c d e f g))" 28
               "(let [(a b c d e f g) (if (= (+ 1 1) 3) nil
                                       ((or _G.unpack table.unpack) [1 2 3 4 5 6 7]))]
            (+ a b c d e f g))" 28
               "(let [t {:st {:v 5 :f #(+ $.v $2)}} x (#(+ $ $2) 1 3)] (t.st:f x) nil)" nil
               "(let [x (if 3 4 5)] x)" 4
               "(select \"#\" (if (= 1 (- 3 2)) (values 1 2 3 4 5) :onevalue))" 5
               (.. "(do (local c1 20) (local c2 40) (fn xyz [A B] (and A B)) "
                   "(xyz (if (and c1 c2) true false) 52))") 52
               "(let [t {} _ (set t.field :let-side)] t.field)" :let-side}]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code {:correlate true}) expected code))))

(fn test-macros []
  (let [cases {"(-> (+ 85 21) (+ 1) (- 99))" 8
               "(-> 1234 (string.reverse) (string.upper))" "4321"
               "(-> 1234 string.reverse string.upper)" "4321"
               "(->> (+ 85 21) (+ 1) (- 99))" (- 8)
               "(-?> [:a :b] (table.concat \" \"))" "a b"
               "(-?> {:a {:b {:c :z}}} (. :a) (. :b) (. :c))" "z"
               "(-?> {:a {:b {:c :z}}} (. :a) (. :missing) (. :c))" nil
               "(-?>> \" \" (table.concat [:a :b]))" "a b"
               "(-?>> :w (. {:w :x}) (. {:x :missing}) (. {:y :z}))" nil
               "(-?>> :w (. {:w :x}) (. {:x :y}) (. {:y :z}))" "z"
               "(eval-compiler
             (tset _SPECIALS \"reverse-it\" (fn [ast scope parent opts]
               (tset ast 1 \"do\")
               (for [i 2 (math.ceil (/ (length ast) 2))]
                 (let [a (. ast i) b (. ast (- (length ast) (- i 2)))]
                   (tset ast (- (length ast) (- i 2)) a)
                   (tset ast i b)))
               (_SPECIALS.do ast scope parent opts))))
           (reverse-it 1 2 3 4 5 6)" 1
               "(eval-compiler (set tbl.nest ``nest))
          (tostring tbl.nest)" "(quote nest)"
               "(import-macros m :test.macros) (m.multigensym)" 519
               "(import-macros m :test.macros) (var x 1) (m.inc! x 2) (m.inc! x) x" 4
               "(import-macros test :test.macros {:inc INC} :test.macros)
          (INC (test.inc 5))" 7
               "(import-macros {:defn1 defn : ->1} :test.macros)
          (defn join [sep ...] (table.concat [...] sep))
          (join :: :num (->1 5 (* 2) (+ 8)))" "num:18"
               "(let [x [1]]
            (doto x (table.insert 2) (table.insert 3)) (table.concat x))" "123"
               "(macro five [] 5) (five)" 5
               "(macro greet [] :Hi!) (greet)" "Hi!"
               "(macro seq? [expr] (sequence? expr)) (seq? [65])" [65]
               "(macros {:m (fn [x] (set _G.sided x))}) (m 952) _G.sided" 952
               "(macros {:m (fn [y] `(let [xa# 1] (+ xa# ,y)))}) (m 4)" 5
               "(macros {:plus (fn [x y] `(+ ,x ,y))}) (plus 9 9)" 18
               "(macros {:when2 (fn [c val] `(when ,c ,val))})
          (when2 true :when2)" "when2"
               "(macros {:when3 (fn [c val] `(do (when ,c ,val)))})
          (when3 true :when3)" "when3"
               "(macros {:x (fn [] `(fn [...] (+ 1 1)))}) ((x))" 2
               "(macros {:yes (fn [] true) :no (fn [] false)}) [(yes) (no)]" [true false]
               "(require-macros \"test.macros\")
          (->1 9 (+ 2) (* 11))" 121
               "(require-macros \"test.macros\")
          (defn1 hui [x y] (global z (+ x y))) (hui 8 4) z" 12
               "(var (fh1 fh2) nil) [(with-open [f1 (io.tmpfile) f2 (io.tmpfile)]
          (set [fh1 fh2] [f1 f2]) (f1:write :asdf) (f1:seek :set 0) (f1:read :*a))
          (io.type fh1) (io.type fh2)]" ["asdf" "closed file" "closed file"]
               "(var fh nil) (local (ok msg) (pcall #(with-open [f (io.tmpfile)] (set fh f)
          (error :bork!)))) [(io.type fh) ok (msg:match :bork!)]" ["closed file" false "bork!"]
               "[(with-open [proc1 (io.popen \"echo hi\") proc2 (io.popen \"echo bye\")]
            (values (proc1:read) (proc2:read)))]" ["hi" "bye"]}]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code {:correlate true}) expected code))
    (fennel.eval "(eval-compiler (set _SPECIALS.reverse-it nil))")))

(fn test-hashfn []
  (let [cases {"(#$.foo {:foo :bar})" "bar"
               "(#$2.foo.bar.baz nil {:foo {:bar {:baz :quux}}})" "quux"
               "(#(+ $ 2) 3)" 5
               "(#(+ $1 $2) 3 4)" 7
               "(#(+ $1 45) 1)" 46
               "(#(+ $3 $4) 1 1 3 4)" 7
               "(#[(select :# $...) $...] :a :b :c)" [3 "a" "b" "c"]
               "(+ (#$ 1) (#$2 2 3))" 4
               "(let [f #(+ $ $1 $2)] (f 1 2))" 4
               "(let [f #(+ $1 45)] (f 1))" 46
               "(let [f #(do (local a 1) (local b (+ $1 $1 a)) (+ a b))] (f 1))" 4}]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code {:correlate true}) expected code))))

(fn test-method_calls []
  (let [cases {"(let [x {:foo (fn [self arg1] (.. self.bar arg1)) :bar :baz}] (x:foo :quux))"
               "bazquux"
               "(let [x {:y {:foo (fn [self arg1] (.. self.bar arg1)) :bar :baz}}] (x.y:foo :quux))"
               "bazquux"}]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code {:correlate true}) expected code))))

(fn test-match []
  (let [cases {"(let [_ :bar] (match :foo _ :should-match :foo :no))" "should-match"
               "(let [k :k] (match [5 :k] :b :no [n k] n))" 5
               "(let [s :hey] (match s :wat :no :hey :yes))" "yes"
               "(let [x 3 res (match x 1 :ONE 2 :TWO _ :???)] res)" "???"
               "(let [x 95] (match [52 85 95] [x y z] :nope [a b x] :yes))" "yes"
               "(let [x {:y :z}] (match :z x.y 1 _ 0))" 1
               "(match (+ 1 6) 7 8 8 1 9 2)" 8
               "(match (+ 1 6) 7 8)" 8
               "(match (io.open \"/does/not/exist\") (nil msg) :err f f)" "err"
               "(match (values 1 [1 2]) (x [x x]) :no (x [x y]) :yes)" "yes"
               "(match (values 5 9) 9 :no (a b) (+ a b))" 14
               "(match (values nil :nonnil) (true _) :no (nil b) b)" "nonnil"
               "(match [1 2 1] [x y x] :yes)" "yes"
               "(match [1 2 3] [3 2 1] :no [2 9 1] :NO :default)" "default"
               "(match [1 2 3] [a & b] (+ a (. b 1) (. b 2)))" 6
               "(match [1 2 3] [x y x] :no [x y z] :yes)" "yes"
               "(match [1 2 [[1]]] [x y [z]] (. z 1))" 1
               "(match [1 2 [[3]]] [x y [[x]]] :no [x y z] :yes)" "yes"
               "(match [1 2] [_ _] :wildcard)" "wildcard"
               "(match [1] [a & b] (# b))" 0
               "(match [1] [a & b] (length b))" 0
               "(match [9 5] [a b ?c] :three [a b] (+ a b))" "three"
               "(match [9 5] [a b c] :three [a b] (+ a b))" 14
               "(match [:a :b :c] [1 t d] :no [a b :d] :NO [a b :c] b)" "b"
               "(match [:a :b :c] [a b c] (.. b :eee))" "beee"
               "(match [:a [:b :c]] [a b :c] :no [:a [:b c]] c)" "c"
               "(match [:a {:b 8}] [a b :c] :no [:a {:b b}] b)" 8
               "(match [{:sieze :him} 5]
            ([f 4] ? f.sieze (= f.sieze :him)) 4
            ([f 5] ? f.sieze (= f.sieze :him)) 5)" 5
               "(match nil _ :yes nil :no)" "yes"
               "(match {:a 1 :b 2} {:c 3} :no {:a n} n)" 1
               "(match {:sieze :him}
            (tbl ? (. tbl :no)) :no
            (tbl ? (. tbl :sieze)) :siezed)" "siezed"
               "(match {:sieze :him}
            (tbl ? tbl.sieze tbl.no) :no
            (tbl ? tbl.sieze (= tbl.sieze :him)) :siezed2)" "siezed2"
               "(var x 1) (fn i [] (set x (+ x 1)) x) (match (i) 4 :N 3 :n 2 :y)" "y"}]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code {:correlate true}) expected code))))

(fn test-fennelview []
  (let [cases {"((require :fennelview) (let [t {}] [t t]) {:detect-cycles? false})"
               "[{} {}]"
               "((require :fennelview) (let [t {}] [t t]))"
               "[<2>{} #<table 2>]"
               "((require :fennelview) {:a 1 :b 52})"
               "{
  :a 1
  :b 52
}"
               "((require :fennelview) {:a 1 :b 5} {:one-line true})"
               "{:a 1 :b 5}"
               ;; ensure it works on lists/syms inside compiler
               "(eval-compiler
                  (set _G.out ((require :fennelview) '(a {} [1 2]))))
                _G.out"
               "(a {} [1 2])"}]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code {:correlate true}) expected code))
    (let [mt (setmetatable [] {:__fennelview (fn [] "META")})]
      (l.assertEquals ((require "fennelview") mt) "META"))))

{: test-booleans
 : test-calculations
 : test-comparisons
 : test-conditionals
 : test-core
 : test-destructuring
 : test-edge
 : test-fennelview
 : test-functions
 : test-hashfn
 : test-if
 : test-loops
 : test-macros
 : test-match
 : test-method_calls
 : test-parsing}
