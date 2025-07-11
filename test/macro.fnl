(local unpack (or _G.unpack table.unpack))
(local t (require :test.faith))
(local fennel (require :fennel))

(local env (setmetatable {} {:__index _G}))
(set env._G env)

(macro view [x] (view x))
(macro macro-wrap [helper ...]
  (let [expr `(do (macro ,helper [,_VARARG] (,helper ,_VARARG))
                  ,...)]
    `(fennel.eval ,(view expr))))

(macro == [form expected ?msg ?opts]
  `(let [(ok# val#) (pcall fennel.eval ,(view form) ,?opts)]
     (t.is ok# val#)
     (t.= ,expected val# ,?msg)))

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
  (== (let [(result count) (-?> :abc (: :gsub "a" "b"))] count) 1)
  (== (-?>> := (table.concat [:a :b])) "a=b"))

(fn test-doto []
  (== (doto [1 3 2] (table.sort #(> $1 $2)) table.sort) [1 2 3])
  (== (do (macro twice [x] `(do ,x ,x))
          (let [t []] (twice (doto t (table.insert 5)))))
      [5 5])
  (== (do (var x 1) (let [y (doto x (set 2))]
                      [x y]))
      [2 2]))

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
        "(quote nest)" ""
        {:compiler-env env :env env})))

(fn test-import-macros []
  (== (do (import-macros m :test.macros) (m.multigensym)) 519)
  (== (do (import-macros m :test.macros) (var x 1) (m.inc! x 2) (m.inc! x) x) 4)
  (== (do (import-macros test :test.macros {:inc INC} :test.macros)
          (INC (test.inc 5))) 7)
  (== (do (import-macros {:defn1 defn : ->1} :test.macros)
          (defn join [sep ...] (table.concat [...] sep))
          (join :: :num (->1 5 (* 2) (+ 8))))
      "num:18" nil {: env})
  (== (do (import-macros {: unsandboxed} :test.macros) (unsandboxed))
      "[\"no\" \"sandbox\"]" "should disable sandbox" {:compiler-env _G})
  (let [not-unqualified "(import-macros hi :test.macros) (print (inc 1))"]
    (t.is (not (pcall fennel.eval not-unqualified))))
  (== 2 (do (import-macros {: gensym-shadow} :test.macros) (gensym-shadow))))

(fn test-macro-path []
  (== (do (import-macros m :test.other-macros) (m.m)) "testing macro path")
  (== (do (import-macros m :test.mod.macroed) (m.reverse3 [1 2 3]))
      [3 2 1]))

(fn test-relative-macros []
  (== (require :test.relative) 3))

(fn test-relative-chained-mac-mod-mac []
  (== (require :test.relative-chained-mac-mod-mac) [:a :b :c]))

(fn test-relative-filename []
  ;; manual pcall instead of == macro for smaller failure message
  (let [(ok? val) (pcall require :test.relative-filename)]
    (t.is ok? val)
    (t.= val 2)))

(fn test-require-macros []
  (== (do (require-macros :test.macros) (->1 9 (+ 2) (* 11))) 121)
  (== (do (require-macros :test.macros)
          (defn1 hui [x y] (global z (+ x y)))
          (hui 8 4) z)
      12 nil {: env}))

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
      "should disable sandbox" {:compiler-env env : env})
  (== (do (macro n [] 1) (local x (n)) (macro n [] 2) (values x (n)))
      (values 1 2) "macro-macro shadowing should be allowed")
  (== (do (macros (let [noop #nil] {: noop})) (noop))
      nil "(macros) should accept an expr that returns a table"))

(fn test-macrodebug []
  (let [eval-normalize #(-> (pick-values 1 (fennel.eval $1 $2))
                            (: :gsub "table: 0x[0-9a-f]+" "#<TABLE>")
                            (: :gsub "\n%s*" " "))
        code "(macrodebug (when (= 1 1) (let [x :X] {: x})) true)"
        expected "(if (= 1 1) (do (let [x \"X\"] {:x x})))"
        cyclic "(macrodebug (case [1 2] (where (or [x y] [y nil x]) (= 3 (+ x y))) x) true)"]
    (t.= (eval-normalize code) expected)
    (t.= (fennel.eval (pick-values 1 (eval-normalize cyclic)))
         1
         "cyclic/recursive AST's should serialize to valid syntax")))

;; many of these are copied wholesale from test-match, pending implementation,
;; if match is implemented via case then it should be reasonable to remove much
;; of test-match except for those tests that unify bindings
;;
;; See NEW-CASE-TESTS for new case specific tests
(fn test-case []
  (== (case false
        false false
        _ true)
      false)
  (== (case [:a {:b 8}]
        [a b :c] :no
        [:a {:b b}] b)
      8)
  (== (case (values 1 2 3 4 :ok)
        (where (a b c d e) (= 1 a)) e
        _ :not-ok) "ok")
  (== (case [:a :b :c]
        [a b c] (.. b :eee))
      "beee")

  ;; regression test, ensure that we don't try to bind `&` even though both patterns technically have it.
  (== (case [:a :b]
        (where (or [:a & rest] [:b & rest])) rest)
      [:b])

  ;; regression test, ensure that we don't try to bind `&as`
  (== (case [:a :b]
        (where (or [:a &as rest] [:b &as rest])) rest)
      [:a :b])

  ;; can't expand blind multi sym
  (let [(_ msg1) (pcall fennel.eval "(let [x {:y :z}] (case :z x.y 1 _ 0))")]
    (t.match ".*unexpected multi symbol x.y.*" msg1))
  ;; but can unify with a multi sym
  (== (let [x {:y :z}]
        (case :z
          (where (= x.y)) 1
          _ 0))
      1)

  (== (case (io.open "/does/not/exist")
        (nil msg) :err
        f f)
      "err")

  (== (let [k :k]
        (case [5 :k]
          :b :no
          ;; k will rebind to the same value, but it has no effect on result
          [n k] n))
      5)

  (== (let [k :k]
        (case [5 :k]
          :b :no
          ;; should check unified value and match
          (where [n (= k)]) n))
      5)

  (== (case true
        (where (or false true)) :true
        _ :nil)
      "true")

  (== (case [1 2 1]
        [x y x] :yes)
      "yes")

  (== (case false
        (where (or false true)) :false
        _ :nil)
      "false")

  (== (case [1 2 3]
        ;; case will check el 1 and el 3 are the same
        [x y x] :no
        [x y z] :yes)
      "yes")

  (== (case [1 2 3]
        [3 2 1] :no
        [2 9 1] :NO
        _ :default)
      "default")

  (== (case [1 2 [[3]]]
        [x y [[x]]] :no
        [x y z] :yes)
      "yes")

  (== (case [9 5]
        [a b c] :three
        [a b] (+ a b))
      14)

  (== (let [s :hey]
        (case s
          :wat :no
          :hey :yes))
      "yes")

  (== (case nil
        (where (or nil false true))
        :ok
        _ :not-ok)
      "ok")

  (== (case [1]
        [a & b] (length b))
      0)

  (== (case (+ 1 6)
        7 8)
      8)

  ;; legacy not supported
  (let [(_ msg1) (pcall fennel.eval "(case [1 2] ([a 2] ? (> a 10)) :error-please)")]
    (t.match ".*legacy guard clause not supported in case.*" msg1))

  ;; new syntax -- general case
  (== (case [1 2 3 4]
        (where (or [1 2 4] [4 5 6])) :nope1
        (where [a 2 3 4] (> a 0)) :success1
        (where [a 2 3 4] (> a 10)) :nope3
        (where [a 2 3 4] (= a 1)) :success2) "success1")

  (== (case {:a 1 :b 2}
        {:c 3} :no
        {:a n} n)
      1)

  (== (case [1 2]
        [a & [b c]] (+ a b c)
        _ :subrest)
      "subrest")

  (== (case nil
        (where (1 2 3 4) true) :nope1
        (where {:a 1 :b 2} true) :nope2
        (where [a b c d] (= 100 (* a b c d))) :nope3
        _ :success)
      "success")

  (== (case (values nil :nonnil)
        (true _) :no
        (nil b) b)
      "nonnil")

  (== (case [1 2 3]
        [a b &as t] (+ a b (. t 3)))
      6)

  (== (case {:a 1 :b 2}
        {: a &as t} (+ a t.b))
      3)

  (== (case [1 2 3]
        [a & b] (+ a (. b 1) (. b 2)))
      6)

  (== (case [{:sieze :him} 5]
        (where [f 4] f.sieze (= f.sieze :him)) 4
        (where [f 5] f.sieze (= f.sieze :him)) 5)
      5)

  (== (case true
        (where (or nil false true)) :ok
        _ :not-ok)
      "ok")

  (== (case [1 2]
        [_ _] :wildcard)
      "wildcard")

  (== (case (+ 1 6)
        7 8
        8 1
        9 2)
      8)

  (== (case nil
        false false
        _ true)
      true)

  (== (case [1]
        [a & b] (# b))
      0)

  (== (case {:sieze :him}
        (where tbl tbl.sieze tbl.no) :no
        (where tbl tbl.sieze (= tbl.sieze :him)) :siezed2)
      "siezed2")

  (== (case {:sieze :him}
        (where tbl (. tbl :no)) :no
        (where tbl (. tbl :sieze)) :siezed)
      "siezed")

  (== (case [1 2 [[1]]]
        [x y [z]] (. z 1))
      1)

  ;; Booleans are ORed as patterns
  (== (case false
        (where (or nil false true)) :ok
        _ :not-ok)
      "ok")

  (== (case [1 2 3 4]
        (1 2 3 4) :nope1
        {:a 1 :b 2} :nope2
        (where [a b c d] (= 100 (* a b c d))) :nope3
        _ :success)
      "success")

  (== (case [:a :b :c]
        [1 t d] :no
        [a b :d] :NO
        [a b :c] b)
      "b")

  ;; nil matching
  (== (case nil
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
        _ :nope11)
      "success")

  (== (case [1 2 3 4]
        (where (or [1 2 4] [4 5 6])) :nope1
        (where [a 2 3 4] (> a 10)) :nope2
        (where [a 2 3 4] (= a 1)) :success)
      "success")

  (== (case (values 1 [1 2])
        (x [x x]) :no
        (x [x y]) :yes)
      "yes")

  (== (case [1 2 3 4]
        1 :nope1
        [1 2 4] :nope2
        (where [1 2 4]) :nope3
        (where (or [1 2 4] [4 5 6])) :nope4
        (where [a 1 2] (> a 0)) :nope5
        (where [a b c] (> a 2) (> b 0) (> c 0)) :nope6
        (where (or [a 1] [a -2 -3] [a 2 3 4]) (> a 0)) :success
        _ :nope7)
      "success")

  (== (case [:a [:b :c]]
        [a b :c] :no
        [:a [:b c]] c)
      "c")

  (== (do
        (var x 1)
        (fn i []
          (set x (+ x 1))
          x)
        (case (i)
          4 :N
          3 :n
          2 :y))
      "y")

  ;; should not unify x
  (== (let [x 95]
        (case [52 85 95]
          [x y z] :nope
          [a b x] :yes))
      "nope")

  ;; unify x
  (== (let [x 95]
        (case [52 85 95]
          (where [(= x) y z]) :nope
          (where [a b (= x)]) :yes))
      "yes")

  (== (case (values 5 9)
        9 :no
        (a b) (+ a b))
      14)

  (== (let [x 3
            res (case x
                  1 :ONE
                  2 :TWO
                  _ :???)]
        res)
      "???")

  (== (case [9 5]
        [a b ?c] :three
        [a b] (+ a b))
      "three")

  (== (case nil
        _ :yes
        nil :no)
      "yes")

  (== (let [_ :bar]
        (case :foo
          _ :should-match
          :foo :no))
      "should-match")

  ;; NEW-CASE-TESTS

  (== (let [x 1]
         (case [:hello]
           [x] x))
      :hello)

  (== (let [x 1]
        (case [:hello]
          ;; 1 != :hello
          (where [(= x)]) x
          _ :no-match))
      :no-match)

  (== (let [x 1]
        (case [1]
          ;; 1 == 1
          (where [(= x)]) x
          _ :no-match))
     1)

  (== (let [pass :hunter2
            user-input #:hunter2]
        (case (user-input)
          (where (= pass)) :login
          _ :try-again!))
      :login)

  (== (let [limit 10]
        (case [5 6]
          (where [a b] (<= limit (+ a b))) :over-the-limit
          [a b] (+ a b limit)))
      :over-the-limit)

  (== (let [x 99]
        (case [10 20]
          ;; x is not unified, so it's a new binding
          [x y] (+ x y)))
     (+ 10 20))

  (== (let [x 99]
        (case [10 20]
          ;; x was not rebound, so the existing symbol is used
          [a b] (+ a x)))
     (+ 10 99))

  (== (let [x 99]
        (case [99 20]
          ;; [99 20] = [99 b]
          (where [(= x) b]) (+ x b)))
     (+ 99 20))

  (== (let [x 99]
        (case [99 20]
          ;; [99 20] = [99 x]
          ;; note that x is bound in the pattern, so the body uses that value
          (where [(= x) x]) (+ x x)))
     (+ 20 20))

  (== (let [x 99]
        (case [20 99]
          ;; [20 99] = [x 20]
          ;; x is bound in the pattern, so the body uses that value
          (where (or [(= x) x]
                     [x (= x)])) (+ x x)))
     (+ 20 20)))

(fn test-case-try []
  ;; ensure we do not unify in a success path
  ;; these can be sense checked by running match-try with fresh bindings at
  ;; each step
  (== (case-try 10
        a [(+ a a) (+ 1 1)]
        ;; should rebind, not unify up
        (where [a b] (<= a 20)) true
        (catch
          a :ay ;; should not get here
          _ :nothing))
     true)

  ;; ensure we do not unify in a catch
  ;; these can be sense checked by running match-try with fresh bindings at
  ;; each step
  (== (case-try 20
        a [(+ a a) (+ 1 1)]
        ;; fail this match
        (where [a b] (<= a 20)) true
        (catch
          [a _] :we-can-work-it-out
          _ :nothing))
      :we-can-work-it-out))

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
  (== (let [_ :bar] (match :foo _ :should-match :foo :no)) "should-match")
  ;; match (or) without bindings
  (== (let [x 10 y 9] (match 9 (where (or x 1 2 3)) :a (where (or x y)) :b)) :b)
  (== (let [x 3] (match x (where (or 1 2 3) true false) :a (where (or 1 2 3) true) :b)) :b)
  (== (match 4 (where (or 1 3)) :odd (where (or 2 4)) :even) :even)
  (== (match [3] (where (or [1] [3])) :odd (where (or [2] [4])) :even) :odd)
  (== (match (values 1 2) (where (or (1 1) (2 2))) :bad (where (or (2 1) (1 2))) :good) :good)
  ;; match (or) with bindings
  (== (match [1 2] (where (or [x y] [y x]) (< y x)) x) 2)
  (== (let [x 10] (match [10 5] (where (or [y x] [x y])) y)) 5)
  (== (let [x 5] (match [10 5] (where (or [y x] [x y])) y)) 10)
  (== (match [:a] (where (or [x] x)) (x:upper)) :A)
  (== (match :a (where (or [x] x)) (x:upper)) :A)
  (== (match nil (where (or [x] x)) (x:upper)) nil)
  (== (match (values 1 2) (where (or (y y x) (x y) (y x))) [x y]) [1 2])
  (== (do (var x 5) (match 5 (where (or x x)) (set x 6)) x) 6))

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
        (_ msg2) (pcall fennel.eval "(match-try abc {} :def _ :wat (catch 55))")
        (_ msg3) (pcall fennel.eval "(match-try abc {} :def _ :wat [catch 55 :body])")]
    (t.match ".*expected every pattern to have a body.*" msg1)
    (t.match ".*expected every catch pattern to have a body.*" msg2)
    (t.match ".*expected every pattern to have a body.*" msg3)))

(fn test-lua-module []
  (== (do (macro abc [] (let [l (require :test.luamod)] (l.abc))) (abc)) :abc)
  (== (do (import-macros {: reverse} :test.mod.reverse) (reverse (29 2 +))) 31)
  (let [badcode "(macro bad [] (let [l (require :test.luabad)] (l.bad))) (bad)"]
    (t.is (not (pcall fennel.eval badcode {:compiler-env :strict})))))

(fn test-disabled-sandbox-searcher []
  (let [opts {:env :_COMPILER :compiler-env _G}
        code "{:path (fn [] (os.getenv \"PATH\"))}"
        searcher #(match $
                    :dummy (fn [] (fennel.eval code opts)))]
    (table.insert fennel.macro-searchers 1 searcher)
    (t.is (pcall fennel.eval "(import-macros {: path} :dummy) (path)"))
    (table.remove fennel.macro-searchers 1)
    (t.is (pcall fennel.eval "(import-macros i :test.indirect-macro)"
                         {:compiler-env _G}))))

(fn test-expand []
  (== (do (macro expand-string [f]
            (list (sym :table.concat)
                  (icollect [_ x (ipairs (macroexpand f))] (tostring x))))
          (expand-string (when true #x)))
      "iftrue(do (hashfn x))"))

(fn test-literal []
  (== (do (macro splice [t] (doto t (tset :hello :world)))
          (splice {:greetings "comrade"}))
      {:hello "world" :greetings "comrade"}))

(fn test-assert-repl []
  (let [inputs ["x\n" "(inc x)\n" "(length hello)\n" ",return 22\n"]
        outputs []
        _ (do (set fennel.repl.readChunk #(table.remove inputs 1))
              (set fennel.repl.onValues (fn [[x]] (table.insert outputs x))))
        form (view (let [hello :world]
                     (fn inc [x] (+ x 1))
                     (fn g [x]
                       (assert-repl (< x 2000) "AAAAAH" "WAHHHH"))
                     (fn f [x] (g (* x 2)))
                     (f 28)
                     (f 1010)))]
    (t.= [true 22]
         [(pcall fennel.eval form)])
    (t.= [] inputs)
    (t.= ["AAAAAH" "2020" "2021" "5" "22"]
         [(string.gsub (. outputs 1) "%s*stack traceback:.*" "")
          (unpack outputs 2)])
    (t.= [(assert-repl :a-string :b-string :c-string)] [:a-string :b-string :c-string])
    ;; Set REPL to return immediately for next assertions
    (set fennel.repl.readChunk #",return nil")
    (set fennel.repl.onError #nil)
    (set fennel.repl.onValues #nil)
    (let [form (view (assert-repl false "oh no"))
          multi-args-form (view (assert-repl (select 1 :a :b nil nil :c)))
          (ok? msg) (pcall fennel.eval form)]
      (t.= false ok? "assertion should fail from repl when returning nil")
      (t.= [true :a :b nil nil :c] [(pcall fennel.eval multi-args-form)]
           "assert-repl should pass along all runtime ret vals upon success"))))

(fn test-assert-as-repl []
  (set fennel.repl.readChunk #",return :nerevar")
  (set fennel.repl.onValues #nil)
  (let [form (view (assert nil "you nwah"))
        (ok? val) (pcall fennel.eval form {:assertAsRepl true})]
    (t.is ok? "should be able to recover from nil assertion.")
    (t.= "nerevar" val)))

(fn test-lambda []
  (lambda arglist-lambda [x]
    "docstring"
    {:fnl/arglist [y]}
    (do :something))
  (t.= [:y] (. fennel.metadata arglist-lambda :fnl/arglist))
  (let [l2 (lambda [x]
             "docstring"
             {:fnl/arglist [z]}
             (do :something))]
    (t.= [:z] (. fennel.metadata l2 :fnl/arglist)))
  (fn call-lambda [] (arglist-lambda) nil)
  (let [(ok msg) (pcall call-lambda)] (t.match "test/macro.fnl:815" msg)))

(fn test-env-lua-helpers []
  (t.= :e (macro-wrap unpack (unpack [:a :b nil nil :e] 5))
       "unpack is in compiler-env")
  (t.= {1 :a 3 :c 5 :e :n 5} (macro-wrap pack (pack :a nil :c nil :e))
       "pack is in compiler-env"))

(fn test-sym []
  (macro use-sym [arg]
    `(do ,(sym arg)))

  (t.= "(do something)"
       (macrodebug (use-sym "something") true)
       "constructing a symbol from string should not fail")

  (let [(ok? err) (pcall fennel.eval "(do
                                       (macro use-sym [arg] `(do ,(sym arg)))
                                       (use-sym something))")]
    (t.is (not ok?))
    (t.match ".*sym expects a string as the first argument.*" err)))

{:teardown #(each [k (pairs fennel.repl)]
              (tset fennel.repl k nil))
 : test-arrows
 : test-doto
 : test-?.
 : test-import-macros
 : test-require-macros
 : test-relative-macros
 : test-relative-chained-mac-mod-mac
 : test-relative-filename
 : test-eval-compiler
 : test-inline-macros
 : test-macrodebug
 : test-macro-path
 : test-match
 : test-case
 : test-lua-module
 : test-disabled-sandbox-searcher
 : test-assert-repl
 : test-assert-as-repl
 : test-expand
 : test-match-try
 : test-case-try
 : test-lambda
 : test-literal
 : test-env-lua-helpers
 : test-sym}
