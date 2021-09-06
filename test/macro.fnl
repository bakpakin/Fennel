(local l (require :test.luaunit))
(local fennel (require :fennel))

(fn test-arrows []
  (let [cases [["(-> (+ 85 21) (+ 1) (- 99))" 8]
               ["(-> 1234 (string.reverse) (string.upper))" "4321"]
               ["(-> 1234 string.reverse string.upper)" "4321"]
               ["(->> (+ 85 21) (+ 1) (- 99))" (- 8)]
               ["(-?> [:a :b] (table.concat \" \"))" "a b"]
               ["(-?> {:a {:b {:c :z}}} (. :a) (. :b) (. :c))" "z"]
               ["(-?> {:a {:b {:c :z}}} (. :a) (. :missing) (. :c))" nil]
               ["(-?>> \" \" (table.concat [:a :b]))" "a b"]
               ["(-?>> :w (. {:w :x}) (. {:x :missing}) (. {:y :z}))" nil]
               ["(-?>> :w (. {:w :x}) (. {:x :y}) (. {:y :z}))" "z"]]]
    (each [_ [code expected] (ipairs cases)]
      (l.assertEquals (fennel.eval code) expected code))))

(fn test-?. []
  (let [cases [["(?. {:a 1})" {:a 1}]
               ["(?. {:a 1} :a)" 1]
               ["(?. {:a 1} :b)" nil]
               ["(?. [-1 -2])" [-1 -2]]
               ["(?. [-1 -2] 1)" -1]
               ["(?. [-1 -2] 3)" nil]
               ["(?. {:a {:b {:c 3}}} :a :b :c)" 3]
               ["(?. {:a {:b {:c 3}}} :d :b :c)" nil]
               ["(?. nil 1 2 3)" nil] ; safe when table itself is nil
               ["(?. [-1 [-2 [-3] [-4]]] 2 3 1)" -4]
               ["(pcall #(?. [1] 1 2))" false] ; error due to indexing a number
               ["(pcall #(?. {:a true} :a :b))" false] ; error due to indexing a boolean
               ["(?. {:a [{} {:b {:c 4}}]} :a 2 :b :c)" 4]
               ["(?. {:a [[{:b {:c 5}}]]} :a 1 :b :c)" nil]
               ["(?. {:a [[{:b {:c 5}}]]} :a 1 1 :b :c)" 5]
               ["(local t {:a [[{:b {:c 5}}]]}) (?. t :a 1 :b :c)" nil]
               ["(local t {:a [[{:b {:c 5}}]]}) (?. t :a 1 1 :b :c)" 5]
               ["(?. {:a [[{:b {:c false}}]]} :a 1 1 :b :c)" false]]]
    (each [_ [code expected] (ipairs cases)]
      (l.assertEquals (fennel.eval code) expected code))))

(fn test-eval-compiler []
  (let [reverse "(eval-compiler
                   (tset _SPECIALS \"reverse-it\" (fn [ast scope parent opts]
                     (tset ast 1 \"do\")
                     (for [i 2 (math.ceil (/ (length ast) 2))]
                       (let [a (. ast i) b (. ast (- (length ast) (- i 2)))]
                         (tset ast (- (length ast) (- i 2)) a)
                         (tset ast i b)))
                     (_SPECIALS.do ast scope parent opts))))
                 (reverse-it 1 2 3 4 5 6)"
        nest-quote "(eval-compiler (set tbl.nest ``nest)) (tostring tbl.nest)"
        env (setmetatable {:tbl {}} {:__index _G})]
    (l.assertEquals (fennel.eval reverse) 1)
    (l.assertEquals (fennel.eval nest-quote {:compiler-env env :env env})
                    "(quote nest)")
    (fennel.eval "(eval-compiler (set _SPECIALS.reverse-it nil))")
    (l.assertEquals (fennel.eval "(eval-compiler 99)") 99)
    (l.assertEquals (fennel.eval "(eval-compiler true)") true)))

(fn test-import-macros []
  (let [multigensym "(import-macros m :test.macros) (m.multigensym)"
        inc "(import-macros m :test.macros) (var x 1) (m.inc! x 2) (m.inc! x) x"
        inc2 "(import-macros test :test.macros {:inc INC} :test.macros)
              (INC (test.inc 5))"
        rename "(import-macros {:defn1 defn : ->1} :test.macros)
                (defn join [sep ...] (table.concat [...] sep))
                (join :: :num (->1 5 (* 2) (+ 8)))"
        unsandboxed "(import-macros {: unsandboxed} :test.macros)
                     (unsandboxed)"]
    (l.assertEquals (fennel.eval multigensym) 519)
    (l.assertEquals (fennel.eval inc) 4)
    (l.assertEquals (fennel.eval inc2) 7)
    (l.assertEquals (fennel.eval rename) "num:18")
    (l.assertEquals (fennel.eval unsandboxed {:compiler-env _G})
                    "[\"no\" \"sandbox\"]") ))

(fn test-macro-path []
  (l.assertEquals (fennel.eval "(import-macros m :test.other-macros) (m.m)")
                  "testing macro path"))

(fn test-relative-macros []
  (l.assertEquals (fennel.eval "(require :test.relative)") 3))

(fn test-require-macros []
  (let [arrow "(require-macros \"test.macros\") (->1 9 (+ 2) (* 11))"
        defn1 "(require-macros \"test.macros\")
               (defn1 hui [x y] (global z (+ x y))) (hui 8 4) z"]
    (l.assertEquals (fennel.eval arrow) 121)
    (l.assertEquals (fennel.eval defn1) 12)))

(fn test-inline-macros []
  (let [cases {"(macro five [] 5) (five)" 5
               "(macro greet [] :Hi!) (greet)" "Hi!"
               "(macro seq? [expr] (sequence? expr)) (seq? [65])" [65]
               "(macros {:m (fn [y] `(let [xa# 1] (+ xa# ,y)))}) (m 4)" 5
               "(macros {:plus (fn [x y] `(+ ,x ,y))}) (plus 9 9)" 18
               "(macros {:when2 (fn [c val] `(when ,c ,val))})
                (when2 true :when2)" "when2"
               "(macros {:when3 (fn [c val] `(do (when ,c ,val)))})
                (when3 true :when3)" "when3"
               "(macros {:x (fn [] `(fn [...] (+ 1 1)))}) ((x))" 2
               "(macros {:yes (fn [] true) :no (fn [] false)}) [(yes) (no)]"
               [true false]}
        g-using "(macros {:m (fn [x] (set _G.sided x))}) (m 952) _G.sided"]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code) expected code))
    (l.assertEquals (fennel.eval g-using {:compiler-env _G}) 952)))

(fn test-macrodebug []
  (let [eval-normalize #(-> (pick-values 1 (fennel.eval $1 $2))
                            (: :gsub "table: 0x[0-9a-f]+" "#<TABLE>")
                            (: :gsub "\n%s*" " "))
        code "(macrodebug (when (= 1 1) (let [x :X] {: x})) true)"
        expected "(if (= 1 1) (do (let [x \"X\"] {:x x})))"]
    (l.assertEquals (eval-normalize code) expected)))

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
               "(match [1 2 3] [3 2 1] :no [2 9 1] :NO _ :default)" "default"
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
               "(var x 1) (fn i [] (set x (+ x 1)) x) (match (i) 4 :N 3 :n 2 :y)" "y"
               ;; New syntax -- general case
               "(match [1 2 3 4]
                  1 :nope1
                  [1 2 4] :nope2
                  (where [1 2 4]) :nope3
                  (where (or [1 2 4] [4 5 6])) :nope4
                  (where [a 1 2] (> a 0)) :nope5
                  (where [a b c] (> a 2) (> b 0) (> c 0)) :nope6
                  (where (or [a 1] [a -2 -3] [a 2 3 4]) (> a 0)) :success
                  _ :nope7)" :success
               ;; Booleans are OR'ed as patterns
               "(match false
                  (where (or false true)) :false
                  _ :nil)" :false
               "(match true
                  (where (or false true)) :true
                  _ :nil)" :true
               ;; Old syntax as well as new syntax
               "(match [1 2 3 4]
                  (where (or [1 2 4] [4 5 6])) :nope1
                  (where [a 2 3 4] (> a 10)) :nope2
                  ([a 2 3 4] ? (> a 10)) :nope3
                  ([a 2 3 4] ? (= a 1)) :success)" :success
               "(match [1 2 3 4]
                  (where (or [1 2 4] [4 5 6])) :nope1
                  (where [a 2 3 4] (> a 0)) :success1
                  ([a 2 3 4] ? (> a 10)) :nope3
                  ([a 2 3 4] ? (= a 1)) :success2)" :success1
               ;; nil matching
               "(match nil
                  1 :nope1
                  1.2 :nope2
                  :2 :nope3
                  \"3 4\" :nope4
                  [1] :nope5
                  [1 2] :nope6
                  (1) :nope7
                  (1 2) :nope8
                  {:a 1} :nope9
                  [[1 2] [3 4]] :nope10
                  nil :success
                  _ :nope11)" :success
               ;; nil matching with where
               "(match nil
                  (where (1 2 3 4) true) :nope1
                  (where {:a 1 :b 2} true) :nope2
                  (where [a b c d] (= 100 (* a b c d))) :nope3
                  ([a b c d] ? (= 100 (* a b c d))) :nope4
                  _ :success)" :success
               ;; no match
               "(match [1 2 3 4]
                  (1 2 3 4) :nope1
                  {:a 1 :b 2} :nope2
                  (where [a b c d] (= 100 (* a b c d))) :nope3
                  ([a b c d] ? (= 100 (* a b c d))) :nope4
                  _ :success)" :success
               ;; destructure multiple values with where
               "(match (values 1 2 3 4 :ok)
                  (where (a b c d e) (= 1 a)) e
                  _ :not-ok)" :ok
               ;; old tests adopted to new syntax
               "(match [{:sieze :him} 5]
                  (where [f 4] f.sieze (= f.sieze :him)) 4
                  (where [f 5] f.sieze (= f.sieze :him)) 5)" 5
               "(match {:sieze :him}
                  (where tbl (. tbl :no)) :no
                  (where tbl (. tbl :sieze)) :siezed)" :siezed
               "(match {:sieze :him}
                  (where tbl tbl.sieze tbl.no) :no
                  (where tbl tbl.sieze (= tbl.sieze :him)) :siezed2)" :siezed2
               "(match false false false _ true)" false
               "(match nil false false _ true)" true
               "(match true (where (or nil false true)) :ok _ :not-ok)" :ok
               "(match false (where (or nil false true)) :ok _ :not-ok)" :ok
               "(match nil (where (or nil false true)) :ok _ :not-ok)" :ok
               "(match {:a 1 :b 2} {: a &as t} (+ a t.b))" 3
               "(match [1 2 3] [a b &as t] (+ a b (. t 3)))" 6}]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code {:correlate true}) expected code))))

(fn test-lua-module []
  (let [ok-code "(macro abc [] (let [l (require :test.luamod)] (l.abc))) (abc)"
        bad-code "(macro bad [] (let [l (require :test.luabad)] (l.bad))) (bad)"
        reversed "(import-macros {: reverse} :test.mod.reverse) (reverse (29 2 +))"]
    (l.assertEquals (fennel.eval ok-code) "abc")
    (l.assertFalse (pcall fennel.eval bad-code {:compiler-env :strict}))
    (l.assertEquals 31 (fennel.eval reversed))))

(fn test-disabled-sandbox-searcher []
  (let [opts {:env :_COMPILER :compiler-env _G}
        code "{:path (fn [] (os.getenv \"PATH\"))}"
        searcher #(match $
                    :dummy (fn [] (fennel.eval code opts)))]
    (table.insert fennel.macro-searchers 1 searcher)
    (let [(ok msg) (pcall fennel.eval "(import-macros {: path} :dummy) (path)")]
      (l.assertTrue ok msg))
    (table.remove fennel.macro-searchers 1)))

(fn test-expand []
  (let [code "(macro expand-string [f]
                (list (sym :table.concat)
                      (icollect [_ x (ipairs (macroexpand f))] (tostring x))))
              (expand-string (when true (fn [] :x)))"]
    (l.assertEquals (fennel.eval code) "iftrue(do (fn {} \"x\"))")))

{: test-arrows
 : test-?.
 : test-import-macros
 : test-require-macros
 : test-relative-macros
 : test-eval-compiler
 : test-inline-macros
 : test-macrodebug
 : test-macro-path
 : test-match
 : test-lua-module
 : test-disabled-sandbox-searcher
 : test-expand}
