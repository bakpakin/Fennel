(local l (require :luaunit))
(local fennel (require :fennel))

(macro == [form expected ?opts]
  `(let [(ok# val#) (pcall fennel.eval ,(view form) ,?opts)]
     (l.assertTrue ok# val#)
     (l.assertEquals val# ,expected)))

(fn test-arrows []
  (== (-> (+ 85 21) (+ 1) (- 99)) 8)
  (== (-> 1234 (string.reverse) (string.upper)) "4321")
  (== (-> 1234 string.reverse string.upper) "4321")
  (== (->> (+ 85 21) (+ 1) (- 99)) -8)
  (== (-?> {:a {:b {:c :z}}} (. :a) (. :b) (. :c)) "z")
  (== (-?> {:a {:b {:c :z}}} (. :a) (. :missing) (. :c)) nil)
  (== (-?>> :w (. {:w :x}) (. {:x :missing}) (. {:y :z})) nil)
  (== (-?>> :w (. {:w :x}) (. {:x :y}) (. {:y :z})) "z")
  (== (-?> [:a :b] (table.concat :=)) "a=b")
  (== (-?>> := (table.concat [:a :b])) "a=b"))

(fn test-doto []
  (== (doto [1 3 2] (table.sort #(> $1 $2)) table.sort) [1 2 3])
  (== (do (macro twice [x] `(do ,x ,x))
          (let [t []] (twice (doto t (table.insert 5)))))
      [5 5]))

(fn test-?. []
  (== (?. {:a 1}) {:a 1})
  (== (?. {:a 1} :a) 1)
  (== (?. {:a 1} :b) nil)
  (== (?. [-1 -2]) [-1 -2])
  (== (?. [-1 -2] 1) -1)
  (== (?. [-1 -2] 3) nil)
  (== (?. {:a {:b {:c 3}}} :a :b :c) 3)
  (== (?. {:a {:b {:c 3}}} :d :b :c) nil)
  (== (?. nil 1 2 3) nil)
  (== (?. [-1 [-2 [-3] [-4]]] 2 3 1) -4)
  (== (pcall #(?. [1] 1 2)) false)
  (== (pcall #(?. {:a true} :a :b)) false)
  (== (?. {:a [{} {:b {:c 4}}]} :a 2 :b :c) 4)
  (== (?. {:a [[{:b {:c 5}}]]} :a 1 :b :c) nil)
  (== (?. {:a [[{:b {:c 5}}]]} :a 1 1 :b :c) 5)
  (== (do (local t {:a [[{:b {:c 5}}]]}) (?. t :a 1 :b :c)) nil)
  (== (do (local t {:a [[{:b {:c 5}}]]}) (?. t :a 1 1 :b :c)) 5)
  (== (?. {:a [[{:b {:c false}}]]} :a 1 1 :b :c) false))

(fn test-eval-compiler []
  (== (do (eval-compiler
            (tset _SPECIALS :reverse-it
                  (fn [ast scope parent opts]
                    (tset ast 1 :do)
                    (for [i 2 (math.ceil (/ (length ast) 2))]
                      (let [a (. ast i) b (. ast (- (length ast) (- i 2)))]
                        (tset ast (- (length ast) (- i 2)) a)
                        (tset ast i b)))
                    (_SPECIALS.do ast scope parent opts))))
          (reverse-it 1 2 3 4 5 6)) 1)
  (== (eval-compiler 99) 99)
  (== (eval-compiler true) true)
  (let [env (setmetatable {:tbl {}} {:__index _G})]
    (== (do (eval-compiler (set tbl.nest ``nest)) (tostring tbl.nest))
        "(quote nest)"
        {:compiler-env env :env env})))

(fn test-import-macros []
  (== (do (import-macros m :test.macros) (m.multigensym)) 519)
  (== (do (import-macros m :test.macros) (var x 1) (m.inc! x 2) (m.inc! x) x) 4)
  (== (do (import-macros test :test.macros {:inc INC} :test.macros)
          (INC (test.inc 5))) 7)
  (== (do (import-macros {:defn1 defn : ->1} :test.macros)
          (defn join [sep ...] (table.concat [...] sep))
          (join :: :num (->1 5 (* 2) (+ 8))))
      "num:18")
  (== (do (import-macros {: unsandboxed} :test.macros) (unsandboxed))
      "[\"no\" \"sandbox\"]" {:compiler-env _G})
  (let [not-unqualified "(import-macros hi :test.macros) (print (inc 1))"]
    (l.assertFalse (pcall fennel.eval not-unqualified))))

(fn test-macro-path []
  (== (do (import-macros m :test.other-macros) (m.m)) "testing macro path"))

(fn test-relative-macros []
  (== (require :test.relative) 3))

(fn test-require-macros []
  (== (do (require-macros :test.macros) (->1 9 (+ 2) (* 11))) 121)
  (== (do (require-macros :test.macros)
          (defn1 hui [x y] (global z (+ x y))) (hui 8 4) z) 12))

(fn test-inline-macros []
  (== (do (macro five [] 5) (five)) 5)
  (== (do (macros {:m (fn [y] `(let [xa# 1] (+ xa# ,y)))}) (m 4)) 5)
  (== (do (macros {:x (fn [] `(fn [...] (+ 1 1)))}) ((x))) 2)
  (== (do (macros {:yes (fn [] true) :no (fn [] false)}) [(yes) (no)]) [true false])
  (== (do (macro seq? [expr] (sequence? expr)) (seq? [65])) [65])
  (== (do (macros {:when3 (fn [c val] `(do (when ,c ,val)))})
          (when3 true :when3)) "when3")
  (== (do (macro greet [] :Hi!) (greet)) "Hi!")
  (== (do (macros {:when2 (fn [c val] `(when ,c ,val))})
          (when2 true :when2)) "when2")
  (== (do (macros {:plus (fn [x y] `(+ ,x ,y))}) (plus 9 9)) 18)
  (== (do (macros {:m (fn [x] (set _G.sided x))}) (m 952) _G.sided) 952
      {:compiler-env _G}))

(fn test-macrodebug []
  (let [eval-normalize #(-> (pick-values 1 (fennel.eval $1 $2))
                            (: :gsub "table: 0x[0-9a-f]+" "#<TABLE>")
                            (: :gsub "\n%s*" " "))
        code "(macrodebug (when (= 1 1) (let [x :X] {: x})) true)"
        expected "(if (= 1 1) (do (let [x \"X\"] {:x x})))"]
    (l.assertEquals (eval-normalize code) expected)))

(fn test-match []
  (== (match false false false _ true) false)
  (== (match [:a {:b 8}] [a b :c] :no [:a {:b b}] b) 8)
  (== (match (values 1 2 3 4 :ok)
        (where (a b c d e) (= 1 a)) e
        _ :not-ok) "ok")
  (== (match [:a :b :c] [a b c] (.. b :eee)) "beee")
  (== (let [x {:y :z}] (match :z x.y 1 _ 0)) 1)
  (== (match (io.open "/does/not/exist") (nil msg) :err f f) "err")
  (== (let [k :k] (match [5 :k] :b :no [n k] n)) 5)
  (== (match true
        (where (or false true)) :true
        _ :nil) "true")
  (== (match [1 2 1] [x y x] :yes) "yes")
  (== (match false
        (where (or false true)) :false
        _ :nil) "false")
  (== (match [1 2 3] [x y x] :no [x y z] :yes) "yes")
  (== (match [1 2 3] [3 2 1] :no [2 9 1] :NO _ :default) "default")
  (== (match [1 2 [[3]]] [x y [[x]]] :no [x y z] :yes) "yes")
  (== (match [9 5] [a b c] :three [a b] (+ a b)) 14)
  (== (let [s :hey] (match s :wat :no :hey :yes)) "yes")
  (== (match nil (where (or nil false true)) :ok _ :not-ok) "ok")
  (== (match {:sieze :him}
        (tbl ? tbl.sieze tbl.no) :no
        (tbl ? tbl.sieze (= tbl.sieze :him)) :siezed2) "siezed2")
  (== (match [1] [a & b] (length b)) 0)
  (== (match (+ 1 6) 7 8) 8)
  ;; new syntax -- general case
  (== (match [1 2 3 4]
        (where (or [1 2 4] [4 5 6])) :nope1
        (where [a 2 3 4] (> a 0)) :success1
        ([a 2 3 4] ? (> a 10)) :nope3
        ([a 2 3 4] ? (= a 1)) :success2) "success1")
  (== (match {:a 1 :b 2} {:c 3} :no {:a n} n) 1)
  (== (match [1 2] [a & [b c]] (+ a b c) _ :subrest) "subrest")
  (== (match nil
        (where (1 2 3 4) true) :nope1
        (where {:a 1 :b 2} true) :nope2
        (where [a b c d] (= 100 (* a b c d))) :nope3
        ([a b c d] ? (= 100 (* a b c d))) :nope4
        _ :success) "success")
  (== (match (values nil :nonnil) (true _) :no (nil b) b) "nonnil")
  (== (match [1 2 3] [a b &as t] (+ a b (. t 3))) 6)
  (== (match {:a 1 :b 2} {: a &as t} (+ a t.b)) 3)
  (== (match [1 2 3] [a & b] (+ a (. b 1) (. b 2))) 6)
  (== (match [{:sieze :him} 5]
        (where [f 4] f.sieze (= f.sieze :him)) 4
        (where [f 5] f.sieze (= f.sieze :him)) 5) 5)
  (== (match true (where (or nil false true)) :ok _ :not-ok) "ok")
  (== (match [1 2] [_ _] :wildcard) "wildcard")
  (== (match (+ 1 6) 7 8 8 1 9 2) 8)
  (== (match nil false false _ true) true)
  (== (match [1] [a & b] (# b)) 0)
  (== (match [{:sieze :him} 5]
        ([f 4] ? f.sieze (= f.sieze :him)) 4
        ([f 5] ? f.sieze (= f.sieze :him)) 5) 5)
  (== (match {:sieze :him}
        (where tbl tbl.sieze tbl.no) :no
        (where tbl tbl.sieze (= tbl.sieze :him)) :siezed2) "siezed2")
  (== (match {:sieze :him}
        (tbl ? (. tbl :no)) :no
        (tbl ? (. tbl :sieze)) :siezed) "siezed")
  (== (match {:sieze :him}
        (where tbl (. tbl :no)) :no
        (where tbl (. tbl :sieze)) :siezed) "siezed")
  (== (match [1 2 [[1]]] [x y [z]] (. z 1)) 1)
  ;; Booleans are ORed as patterns
  (== (match false (where (or nil false true)) :ok _ :not-ok) "ok")
  (== (match [1 2 3 4]
        (1 2 3 4) :nope1
        {:a 1 :b 2} :nope2
        (where [a b c d] (= 100 (* a b c d))) :nope3
        ([a b c d] ? (= 100 (* a b c d))) :nope4
        _ :success) "success")
  (== (match [:a :b :c] [1 t d] :no [a b :d] :NO [a b :c] b) "b")
  ;; nil matching
  (== (match nil
        1 :nope1
        1.2 :nope2
        :2 :nope3
        "3 4" :nope4
        [1] :nope5
        [1 2] :nope6
        (1) :nope7
        (1 2) :nope8
        {:a 1} :nope9
        [[1 2] [3 4]] :nope10
        nil :success
        _ :nope11) "success")
  (== (match [1 2 3 4]
        (where (or [1 2 4] [4 5 6])) :nope1
        (where [a 2 3 4] (> a 10)) :nope2
        ([a 2 3 4] ? (> a 10)) :nope3
        ([a 2 3 4] ? (= a 1)) :success) "success")
  (== (match (values 1 [1 2]) (x [x x]) :no (x [x y]) :yes) "yes")
  (== (match [1 2 3 4]
        1 :nope1
        [1 2 4] :nope2
        (where [1 2 4]) :nope3
        (where (or [1 2 4] [4 5 6])) :nope4
        (where [a 1 2] (> a 0)) :nope5
        (where [a b c] (> a 2) (> b 0) (> c 0)) :nope6
        (where (or [a 1] [a -2 -3] [a 2 3 4]) (> a 0)) :success
        _ :nope7) "success")
  (== (match [:a [:b :c]] [a b :c] :no [:a [:b c]] c) "c")
  (== (do (var x 1) (fn i [] (set x (+ x 1)) x) (match (i) 4 :N 3 :n 2 :y)) "y")
  (== (let [x 95] (match [52 85 95] [x y z] :nope [a b x] :yes)) "yes")
  (== (match (values 5 9) 9 :no (a b) (+ a b)) 14)
  (== (let [x 3 res (match x 1 :ONE 2 :TWO _ :???)] res) "???")
  (== (match [9 5] [a b ?c] :three [a b] (+ a b)) "three")
  (== (match nil _ :yes nil :no) "yes")
  (== (let [_ :bar] (match :foo _ :should-match :foo :no)) "should-match"))

(macro == [code expected ?msg]
  `(l.assertEquals (fennel.eval (macrodebug ,code true)) ,expected ,?msg))

(fn test-match-try []
  (== (match-try [1 2 1]
        [1 a b] [b a]
        [1 & rest] rest)
      [2]
      "matching all the way thru")
  (== (match-try [1 2 3]
        [1 a b] [b a]
        [1 & rest] rest)
      [3 2]
      "stopping on the second clause")
  (== [(match-try (values nil "whatever")
         [1 a b] [b a]
         [1 & rest] rest)]
      [nil :whatever]
      "nil, msg failure representation stops immediately")
  (== (select 2 (match-try "hey"
                  x (values nil "error")
                  y nil))
      "error"
      "all values are in fact propagated even on a mid-chain mismatch")
  (== (select :# (match-try "hey"
                   x (values nil "error" nil nil)
                   y nil))
      4
      "trailing nils are preserved")
  (== (match-try {:a "abc" :x "xyz"}
        {: b} :son-of-a-b!
        (catch
         {: a : x} (.. a x)))
      "abcxyz"
      "catch clause works")
  (== (match-try {:a "abc" :x "xyz"}
        {: a} {:abc "whatever"}
        {: b} :son-of-a-b!
        (catch
         [hey] :idunno
         {: abc} (.. abc "yo")))
      "whateveryo"
      "multiple catch clauses works")
  (let [(_ msg1) (pcall fennel.eval "(match-try abc def)")
        (_ msg2) (pcall fennel.eval "(match-try abc {} :def _ :wat (catch 55))")]
    (l.assertStrMatches msg1 ".*expected every pattern to have a body.*")
    (l.assertStrMatches msg2 ".*expected every catch pattern to have a body.*")))

(fn test-lua-module []
  (== (do (macro abc [] (let [l (require :test.luamod)] (l.abc))) (abc)) :abc)
  (== (do (import-macros {: reverse} :test.mod.reverse) (reverse (29 2 +))) 31)
  (let [badcode "(macro bad [] (let [l (require :test.luabad)] (l.bad))) (bad)"]
    (l.assertFalse (pcall fennel.eval badcode {:compiler-env :strict}))))

(fn test-disabled-sandbox-searcher []
  (let [opts {:env :_COMPILER :compiler-env _G}
        code "{:path (fn [] (os.getenv \"PATH\"))}"
        searcher #(match $
                    :dummy (fn [] (fennel.eval code opts)))]
    (table.insert fennel.macro-searchers 1 searcher)
    (l.assertTrue (pcall fennel.eval "(import-macros {: path} :dummy) (path)"))
    (table.remove fennel.macro-searchers 1)
    (l.assertTrue (pcall fennel.eval "(import-macros i :test.indirect-macro)"
                         {:compiler-env _G}))))

(fn test-expand []
  (== (do (macro expand-string [f]
            (list (sym :table.concat)
                  (icollect [_ x (ipairs (macroexpand f))] (tostring x))))
          (expand-string (when true (fn [] :x))))
      "iftrue(do (fn {} \"x\"))"))

{: test-arrows
 : test-doto
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
 : test-expand
 : test-match-try}
