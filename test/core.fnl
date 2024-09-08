(local t (require :test.faith))
(local fennel (require :fennel))

(macro == [form expected ?opts]
  `(let [(ok# val#) (pcall fennel.eval ,(view form) ,?opts)]
     (t.is ok# val#)
     (t.= ,expected val# ,(view form))))

(macro assert-no-iife [code ...]
  `(t.not-match "function _[0-9]+_" (fennel.compile-string ,(view code)) ,...))

(fn test-calculations []
  (== (% 1 2 (- 1 2)) 0)
  (== (* 1 2 (/ 1 2)) 1)
  (== (*) 1)
  (== (+) 0)
  (== (+ 1 2 (- 1 2)) 2)
  (== (+ 1 2 (^ 1 2)) 4)
  (== (- 1) -1)
  (== (+ 99) 99)
  (== (* 32) 32)
  (== (/ 2) 0.5))

(local stderr io.stderr)
(fn test-booleans []
  (set io.stderr nil) ; silence deprecation warnings
  (== (not 39) false)
  (== (and true 12 "hey") "hey")
  (== (or false nil true 12 false) true)
  (== (or 11 true false) 11)
  (== (not true) false)
  (== (and 5) 5)
  (== (and 43 table false) false)
  (== (and true true (values)) true)
  (== (and true (values true false)) false)
  (== (or false (values false (do true))) true)
  (== (tostring (and _G.xyz (do _G.xyz.y) _G.xyz)) "nil")
  (== (not nil) true)
  (== (and true (values true false) true) true)
  (== (or) false)
  (== (and (values)) true)
  (== (or 5) 5)
  (== (and) true)
  ;; the side effect rules are complicated
  (== (do (var i 1) (and true (values (set i 2) true)) i) 2)
  (== (do (var i 1) (and false (values (set i 2) true)) i) 1)
  (== (do (var i 1) (and true (values true (set i 2))) i) 2)
  (== (do (var i 1) (and true (values false (set i 2))) i) 1)
  (== (do (var i 1) (and true (do (values false (set i 2)))) i) 2)
  ;; (and) should never return a second value under any circumstances
  (== (let [(x y) (and true (values true true))] y) nil)
  (== (let [(x y) (and true (values (values true true)))] y) nil)
  (== (let [(x y) (and true (#(values true true)))] y) nil)
  (== (let [(x y) (and true (do (values true true)))] y) nil)
  ;; short-circuit special forms
  (== (let [t {:a 85}] (or true (tset t :a 1)) t.a) 85)
  ;; short-circuit macros too
  (== (do (macro ts [t k v] `(tset ,t ,k ,v))
          (let [t {:a 521}] (or true (ts t :a 1)) t.a)) 521)
  (== ((fn [...] (or (doto [...] (tset 4 4)) :never)) 1 2 3)
      [1 2 3 4])
  ;; short-circuit with methods
  (== (do (var i 1) (let [x {:method #(set i 2)}] (and false (: (#x) (#:method))) i)) 1)
  (== (do (var i 1) (let [x {:method #(set i 2)}] (and true (: (#x) (#:method))) i)) 2)
  (== (do (var i 1) (let [x {:method #nil}] (and false (: (#x) (#:method) (set i 2))) i)) 1)
  (== (do (var i 1) (let [x {:method #nil}] (and true (: (#x) (#:method) (set i 2))) i)) 2)
  ;; address (not expr) bypassing short-circuit protections
  (== (do (var i 1) (fn i++! [] (set i (+ i 1)) i) (or true (not (do (i++!)))) i)
      1)
  (== (do (var i 1) (fn i++! [] (set i (+ i 1)) i)
          (or true (not (when true (i++!))))
          i)
      1)
  (== (do (var i 1) (fn i++! [] (set i (+ i 1)) i)
          (or true (length (do [(i++!)])))
          i)
      1)
  (== (do (var i 1) (fn i++! [] (set i (+ i 1)) i) (fn noop [])
          (or true (noop (not (let [x (i++!)] (* x 2)))))
          i)
      1)
  (== (do (var i 1) (fn i++! [] (set i (+ i 1))) (fn noop [])
          (or true (noop [1 2 (i++!)]))
          i)
      1)
  (== (do (var i 1) (fn i++! [] (set i (+ i 1)) i)
          (or true [:x :y (not (let [b (i++!)] b)) :z])
          i)
      1)
  (== (do (var i 1)  (fn i++! [] (set i (+ i 1)) i)
          (or true (and (let [x (i++!)] x) true))
          i)
      1)
  (== (do (var i 1) (fn i++! [] (set i (+ i 1)) i)
          (or true (if (= i 1) (i++!)))
          i)
      1)
  (== (do (var i 1) (fn i++! [] (set i (+ i 1)) i)
          (or true (for [j 1 1] (i++!)))
          i)
      1)
  (== (do (var i 1) (fn i++! [] (set i (+ i 1)) i)
          (or true (each [j (ipairs [:item])] (i++!)))
          i)
      1)
  (== (do (var i 1) (fn i++! [] (set i (+ i 1)) i)
          (or true (while (= i 1) (i++!)))
          i)
      1)
  (== (do (var i 1)
          (or true (set i 2))
          i)
      1)
  (== (let [t {:field 1}]
          (or true (tset t :field 2))
          t.field)
      1)
  (== (let [t {}]
          (or true (fn t.field []))
          t.field)
      nil)
  (== (do (var i 1)
          (or (lua "i = i + 1" "true") (lua "i = i + 1" "true"))
          i)
      2)
  (set io.stderr stderr))

(fn test-comparisons []
  (== (= 1 1 2 2) false)
  (== (<= 88 32) false)
  (== (> -4 89) false)
  (== (not= 6 6 9) true)
  (== (> 2 0 -1) true)
  (== (~= 33 1) true) ; undocumented backwards-compat alias
  (== (< -4 89) true)
  (== (<= 5 1 91) false)
  (== (>= 22 (+ 21 1)) true)
  (== (not= 33 1) true)
  (== (> 2 0) true)
  (== (let [tbl {}
            f (fn [] (tset tbl :dbl (+ 1 (or (. tbl :dbl) 0))) 1)]
        (< 0 (f) 2) (. tbl :dbl)) 1))

(fn test-functions []
  (== ((fn [a b c] (+ a b c)) 1 (values 8 2)) 11)
  (== ((fn [x] (* x 2)) 26) 52)
  (== ((fn f [a sin cos radC cx cy x y limit dis] sin) 8 529) 529)

  (== (do
        (fn func [] {:map #$1})
        (macro foo [] `(let [a# (func)] ((. a# :map) 123)))
        (foo)
        :yeah)
      "yeah")

  (== ((lambda [[x &as t]] t) [10]) [10])
  (== ((lambda [x ...] (+ x 2)) 4) 6)
  (== ((lambda [x _ y] (+ x y)) 4 5 6) 10)
  (== ((lambda [x] (+ x 2)) 4) 6)

  (== (if (= nil ((fn [a]) 1)) :pass :fail) "pass")
  (== (if (= nil ((lambda [a]) 1)) :lambda-works) "lambda-works")

  (== (let [(ok e) (pcall (lambda [x] (+ x 2)))]
        (string.match e "Missing argument x"))
      "Missing argument x")
  (== (let [(ok val) (pcall (λ [?x] (+ (or ?x 1) 8)))] (and ok val)) 9)
  (== (let [add (fn [x y z] (+ x y z)) f2 (partial add 1 2)] (f2 6)) 9)
  (== (let [add (fn [x y] (+ x y)) add2 (partial add)] (add2 99 2)) 101)
  (== (let [add (fn [x y] (+ x y)) inc (partial add 1)] (inc 99)) 100)
  (== (let [f (fn [x y f2] (+ x (f2 y)))
            f2 (fn [x y] (* x (+ 2 y)))
            f3 (fn [f] (fn [x] (f 5 x)))]
        (f 9 5 (f3 f2))) 44)
  (== (let [f (partial #(doto $1 (table.insert $2)) [])]
        (f 1) (f 2) (f 3)) [1 2 3])
  (== (let [f (partial + (math.random 10))]
        (= (f 1) (f 1) (f 1))) true)
  (== (let [t {:x 1} f (partial + t.x)]
        [(f 1) (do (set t.x 2) (f 1))]) [2 2])
  (== (pcall (lambda [string] nil) 1) true)
  (== (do
        (tset (getmetatable ::) :__call (fn [s t] (. t s)))
        (let [res (:answer {:answer 42})]
          (tset (getmetatable ::) :__call nil)
          res))
      42)
  (== (do
        (var a 11)
        (let [f (fn [] (set a (+ a 2)))]
          (f) (f) a))
      15)
  (== ((fn [a & [b {: c}]] (string.format a (+ b c))) "haha %s" 4 {:c 3})
      "haha 7")
  (== ((fn [& {1 _ 2 _ 3 x}] x) :one :two :three) "three")
  (== (tail! (select 1 :hi))
      "hi")
  (== (if (= 1 1) (tail! (select 1 :yes)) (tail! (select 1 :no)))
      "yes"))

(fn test-conditionals []
  (== (if _G.non-existent 1 (* 3 9)) 27)
  (== (if false "yep" "nope") "nope")
  (== (if false :y true :x :trailing :condition) "x")
  (== (let [b :original b (if false :not-this)] (or b nil)) nil)
  (== (let [x 1 y 2] (if (= (* 2 x) y) "yep")) "yep")
  (== (let [x 3 res (if (= x 1) :ONE (= x 2) :TWO true :???)] res) "???")
  (== (let [x {:y 2}] (if false "yep" (< 1 x.y 3) "uh-huh" "nope")) "uh-huh")
  (== (do
        (var [a z] [0 0])
        (when true (set a 192) (set z 12))
        (+ z a)) 204)
  (== (do
        (var a 884)
        (when nil (set a 192))
        a)
      884)
  (== (do
        (var i 0)
        (var s 0)
        (while (let [l 11]
                 (< i l))
          (set s (+ s i))
          (set i (+ 1 i)))
        s)
      55)
  (== (do
        (var x 12)
        (if true (set x 22) 0)
        x)
      22)
  (== (do
        (when (= 12 88)
          (os.exit 1))
        false)
      false)
  (== (while (let [f false] f)
        (lua :break))
      nil)
  (== (if _G.abc :abc true 55 :else) 55)
  (== (select :# (if false 3)) 1))

(fn test-core []
  (== (table.concat ["ab" "cde"] ",") "ab,cde")
  (== (do
        (var [x y] [3 2])
        (set (x y) (do (local [x y] [(* x 3) 0]) (values x y)))
        (+ x y))
      9)
  (== (+ (. {:a 93 :b 4} :a) (. [1 2 3] 2)) 95)
  (== (do (global a_b :global) (local a-b :local) a_b) "global"
      {:env {}})
  (== (do (tset {} :a 1) 1) 1)
  (== (: {:foo (fn [self] (.. self.bar 2)) :bar :baz} :foo) "baz2")
  (== (do (local x#x# 90) x#x#) 90)
  (== (let [xx (let [xx 1] (* xx 2))] xx) 2)
  (== (let [t {}] (set t.a :multi) (. t :a)) "multi")
  (== (let [t []] (tset t :a (let [{: a} {:a :bcd}] a)) t.a) "bcd")
  (== (let [t {:supported-chars {:x true}}
            field1 :supported-chars
            field2 :y]
        (set (. t field1 field2) true) t.supported-chars.y) true)
  (== (let [t {} tt [[]] value-two :hehe]
        (var x nil)
        (set ((. t 1) x (. tt 1 1)) (values :lol 2 :hey))
        (set (. t 2) value-two)
        (set [(. t 3)] [:lmao])
        (set x 87)
        (.. x (table.concat t " ") (table.concat (. tt 1))))
      "87lol hehe lmaohey")
  (== (do (set (. _G :dynamic-set-global?) true) _G.dynamic-set-global?)
      true
      {:env {:_G {}}})
  (== (let [set-x #(do (set (. $1 :x) $2) $1)] (set-x {} :aw-yiss))
      {:x :aw-yiss})
  (== (let [t [8 9]] (set [(. t 1) (. t 2)] [(. t 2) (. t 1)]) t)
      [9 8])
  (== (let [x 17] (. 17)) 17)
  (== (let [my-tbl {} k :key] (tset my-tbl k :val) my-tbl.key) "val")
  (== (let [t {} _ (tset t :a 84)] (. t :a)) 84)
  (== (let [x 3 y nil z 293] z) 293)
  (== (let [k 5 t {: k}] t.k) 5)
  (== (let [t [[21]]] (+ (. (. t 1) 1) (. t 1 1))) 42)
  (== (let [t []] (table.insert t "lo") (. t 1)) "lo")
  (== (pcall #(each [e {}] nil)) false)
  (== (do
        (var x 12) ;; (set x 99)
        x)
      12 {:scope (fennel.scope)})
  (== (do (var x 1) (let [_ (set x 92)] x)) 92)
  (== (do (var n 0) (let [f (fn [] (set n 96))] (f) n)) 96)
  (== (do (var i 0) (each [_ ((fn [] (pairs [1])))] (set i 1)) i) 1)
  (== (do (var a 0)
          (for [_ 1 3]
            (let []
              (table.concat [])
              (set a 33)))
          a) 33)
  (== (do
        (local a 3)
        (let [b 2]
          (set-forcibly! a 7)
          (set-forcibly! b 6)
          (+ a b))) 13)
  (== (do (global x 1) (global x 284) x) 284 {:env {}})
  (== (do
        (var a nil)
        (var b nil)
        (local ret (fn [] a))
        (set (a b) (values 4 5))
        (ret)) 4)
  (when (not _G.getfenv)
    (== (type _ENV) :table))
  ;; ensure sparse tables don't print with a ton of nils in them
  (t.is (not (string.find (fennel.compileString "{1 :a 999999 :b}") :nil))))

(fn test-if []
  (== (if (values 1 2) 3 4) 3)
  (== (if (values 1) 3 4) 3)
  (== (if _G.nothing :no true :yes) :yes)
  (== (if true :haha-yesss) :haha-yesss)
  (== (let [x (if false 3 (values 2 5))] x) 2)
  (== (do (fn myfn [x y z] (+ x y z))
          (myfn 1 (if 1 (values 2 5) 3) 4))
      7)
  (== (do (fn myfn [x y z] (+ x y z))
          (myfn 1 (if 1 2 3) 4))
      7)
  (== (do (fn myfn [x y z] (+ x y z))
          (myfn 1 4 (if 1 2 3)))
      7))

(fn test-destructuring []
  (== ((fn dest [a [b c] [d]] (+ a b c d)) 5 [9 7] [2]) 23)
  (== ((lambda [[a & b]] (+ a (. b 2))) [90 99 4]) 94)
  (== (do (global (a b) ((fn [] (values 4 29)))) (+ a b)) 33 {:env {}})
  (== (do (global [a b c d] [4 2 43 7]) (+ (* a b) (- c d))) 44 {:env {}})
  (== (let [(a [b [c] d]) ((fn [] (values 4 [2 [1] 9])))] (+ a b c d)) 16)
  (== (let [(a [b [c] d]) (values 4 [2 [1] 9])] (+ a b c d)) 16)
  (== (let [(a b) ((fn [] (values 4 2)))] (+ a b)) 6)
  (== (let [({: x} y) (values {:x 10} 20)] (+ x y)) 30)
  (== (let [[a & b] (setmetatable {} {:__fennelrest #42})] b) 42)
  (== (let [[a & b] (setmetatable {} {:__fennelrest #false})] b) false)
  (== (let [[a [b c] d] [4 [2 43] 7]] (+ (* a b) (- c d))) 44)
  (== (let [[a b & c] [1 2 3 4 5]] (+ a (. c 2) (. c 3))) 10)
  (== (let [[a b c d] [4 2 43 7]] (+ (* a b) (- c d))) 44)
  (== (let [[a b c] [4 2]] (or c :missing)) "missing")
  (== (let [[a b] [9 2 49]] (+ a b)) 11)
  (== (let [x 1 x (if (= x 1) 2 3)] x) 2)
  (== (let [{: a & r} {:a 1 :b 2}] a) 1)
  (== (let [{: a & r} {:a 1 :b 2}] r) {:b 2})
  (== (let [{: a : b} {:a 3 :b 5}] (+ a b)) 8)
  (== (let [{:a [x y z]} {:a [1 2 4]}] (+ x y z)) 7)
  (== (let [{:a x :b y} {:a 2 :b 4}] (+ x y)) 6)
  (== (let [[a & b] (setmetatable [1 2 3 4 5]
                                  {:__fennelrest
                                   (fn [t k]
                                     [((or table.unpack _G.unpack)
                                       t (+ k 1))])})]
        b) [3 4 5])
  (== (do (local (-a -b) ((fn [] (values 4 29)))) (+ -a -b)) 33)
  (== (do (local [a b c &as t] [1 2 3]) (+ c (. t 2))) 5)
  (== (do (local {:a x &as t} {:a 2 :b 4}) (+ x t.b)) 6)
  (== (do
        (var [a [b c]] [1 [2 3]])
        (set a 2)
        (set c 8)
        (+ a b c))
      12)
  (== (do
        (var x 0) (each [_ [a b] (ipairs [[1 2] [3 4]])]
                    (set x (+ x (* a b))))
        x) 14)
  (== (let [[a b & c &as t] [1 2 3 4]] a) 1)
  (== (let [[a b & c &as t] [1 2 3 4]] b) 2)
  (== (let [[a b & c &as t] [1 2 3 4]] c) [3 4])
  (== (let [[a b & c &as t] [1 2 3 4]] t) [1 2 3 4]))

(fn test-edge []
  (let [env {}]
    (set env._G env)
    (== (do (local x (lua "y = 4" "6")) (* _G.y x)) 24 {: env}))
  (== (length [(if (= (+ 1 1) 2) (values 1 2 3 4 5) (values 1 2 3))]) 5)
  (== (let [(a b c d e f g) (if (= (+ 1 1) 3)
                                nil
                                ((or table.unpack _G.unpack) [1 2 3 4 5 6 7]))]
        (+ a b c d e f g)) 28)
  (== (select "#" (if (= 1 (- 3 2)) (values 1 2 3 4 5) :onevalue)) 5)
  (== (let [(a b c d e f g) (if (= (+ 1 1) 2) (values 1 2 3 4 5 6 7))]
        (+ a b c d e f g)) 28)
  (== (do
        (local a_0_ (or (getmetatable {}) {:b-c {}}))
        (tset (. a_0_ :b-c) :d 12)
        (. a_0_ :b-c :d))
      12)
  (== (tostring (. {} 12)) "nil")
  ;; ensure that the over-zealous workaround for the
  ;; (let [pairs #(pairs $)] pairs) bug doesn't affect normal code
  (== (do (type _G) (let [type :string] type)) "string")
  (== (let [(_ m) (pcall #(. 1 1))]
        (m:match "attempt to index a number"))
      "attempt to index a number")
  ;; ensure (. (some-macro) k1 ...) doesn't allow invalid Lua output
  (== (do (macro identity [...] ...) (. (identity {:x 1 :y 2 :z 3}) :y))
      2)
  (== (. (let [t (let [t {} k :a] (tset t k 123) t) k :b]
           (tset t k 321)
           t) :a) 123)
  (== (tostring (. :hello 12)) "nil")
  (== (let [t {} _ (set t.field :let-side)] t.field) "let-side")
  (== (do
        (local c1 20)
        (local c2 40)
        (fn xyz [A B] (and A B))
        (xyz (if (and c1 c2) true false) 52))
      52)
  (== (length [(values 1 2 3 4 5)]) 5)
  (== (let [x (if 3 4 5)] x) 4)
  (== (tostring (let [t {:st {:v 5 :f #(+ $.v $2)}}
                      x (#(+ $ $2) 1 3)]
                  (t.st:f x)
                  nil)) "nil")
  (== (let [x [:a] y x]
        (tset (or x y) 2 :b)
        (. y 2))
      :b)
  ;; we have to let fn names escape into surrounding scope
  (== (let [f (fn abc-def [] 99)] (abc-def)) 99)
  (== (let [x [#(tset $1 $2 $3)] y x]
        (: x 1 2 :b)
        (. y 2))
      :b)
  ;; regression test for kv-rest codegen
  (== (let [{& a+b+c} {:key :value}]
        a+b+c.key)
      :value))

(fn test-hashfn []
  (== (#$.foo {:foo :bar}) "bar")
  (== (#$2.foo.bar.baz nil {:foo {:bar {:baz :quux}}}) "quux")
  (== (#(+ $ 2) 3) 5)
  (== (#(+ $1 $2) 3 4) 7)
  (== (#(+ $1 45) 1) 46)
  (== (#(+ $3 $4) 1 1 3 4) 7)
  (== (#[(select :# $...) $...] :a :b :c) [3 "a" "b" "c"])
  (== [(#$... 85 96)] [85 96])
  (== (+ (#$ 1) (#$2 2 3)) 4)
  (== (let [f #(+ $ $1 $2)]
        (f 1 2)) 4)
  (== (let [f #(+ $1 45)]
        (f 1)) 46)
  (== (let [f #(do #(values $...))]
        (table.concat [((f) 1 2 3)])) "123")
  (== (let [f #(do (local a 1) (local b (+ $1 $1 a)) (+ a b))]
        (f 1)) 4)
  (== (let [t {:x 41} f #(set $.x 86)] (f t) t.x) 86))

(fn test-method-calls []
    ;; method calls work
  (== (: :hello :find :e) 2)
  ;; method calls work on identifiers that aren't valid lua
  (== (let [f {:+ #(+ $2 $3 $4)}] (f:+ 1 2 9)) 12)
  ;; method calls work non-native with no args
  (== (let [f {:+ #18}] (f:+)) 18)
  ;; method calls don't double up side effects
  (== (do (var a 0)
          (let [f (fn [] (set a (+ a 1)) :hi)] (: (f) :find :h))
          a) 1)
  ;; method calls don't emit illegal semicolon
  (== (do (fn x [y] (y.obj:method) 77) (x {:obj {:method #$2}})) 77)
  ;; avoid ambiguous calls
  (== (let [state0 {"sheep one" {} :sheep-1 {}}]
        (tset (. state0 "sheep one") :x state0.sheep-1.x)
        (tset (. state0 "sheep one") :y state0.sheep-1.y)
        (type state0)) :table)
  ;; method calls work with varg
  (== ((fn [...] (: ... :gsub :foo :bar)) :foofoo) :barbar)
  (== (let [x {:foo (fn [self arg1] (.. self.bar arg1)) :bar :baz}]
        (x:foo :quux))
      "bazquux")
  (== (let [x {:y {:foo (fn [self arg1] (.. self.bar arg1)) :bar :baz}}]
        (x.y:foo :quux))
      "bazquux"))

(fn test-values []
  (== (let [(x y) (values :x (do :y))] [x y])
      [:x :y])
  (== [(values 1 2 (values 3 4) 4)]
      [1 2 3 4])
  (assert-no-iife [(values 1 2 (values 3 4) 4)])
  (== (let [(x y z Z) (values :x (do :y) (values :z (do :Z)))] [x y z Z])
      [:x :y :z :Z])
  (== (let [t {:field :hi} f #t]
        (tset (f :bork :bork) :field (values (do :BYE) (do :HI)))
        t)
      {:field :BYE})
  (== (do (var i 0) (fn i++ [] (set i (+ 1 i)) i)
          [(values (i++) (values (do (i++)) (do (i++))))])
      [2 1 3])
  (== (do (macro myvalues [x y z] `(values ,x ,y ,z))
          [(values 1 2 (myvalues 3 4))])
      [1 2 3 4]))

(fn test-pick-values []
  (== [(pick-values 4 0 (#(values 1 2 3 4)))] [0 1 2 3])
  (== (do (var i 0) (fn i++ [] (set i (+ 1 i)) i)
          [(pick-values 3 (i++) (do (i++)) (do (i++)))])
      [2 1 3])
  (== (select :# (pick-values 3))
      3)
  (== [(pick-values 0 (select 1 :a :b :c))]
      [])
  (== [(pick-values 4 :a :b :c (values :d :e))]
      ["a" "b" "c" "d"])
  ;; ensure pick-values output respects nval, e.g. in middle of table literal
  (== [:X (pick-values 2 :Y :YY) :Z] [:X :Y :Z])
  (== [:X (pick-values 0 :YY) :Y] [:X nil :Y])
  (t.= "return (select(1, \"x\", \"y\", \"z\"))"
       (fennel.compile-string "(pick-values 1 (select 1 :x :y :z))"))
  (== [(if (= 1 1) (pick-values 1 (select 1 :x :y :z)) :bork)]
      [:x])
  (== (let [ret [(pick-values 3 :x :y (do :z) :A (do :B))]]
        [ret (length ret)])
    [[:x :y :z] 3])
  (== (do (var i 0) (fn i++ [] (set i (+ i 1)) i)
          (doto [(pick-values 1 (i++) (i++) (i++))]
                (table.insert i)))
      [3 3])
  ;; Ensure (pick-values 0 ...) emits nil when needed, and keeps side effects
  (== (do (var i 0) (fn i++ [] (set i (+ i 1)) i)
          (doto [:X (pick-values 0 (i++) (i++) (i++)) :Y]
                ;; Using tset because, in luajit and luajit only,
                ;; (doto [:X (values) :Y] (table.insert :Z)) returns [:X 3 :Y]
                (tset 4 i)))
      [:X nil :Y 3])
  (== (do (var i 0) (fn i++ [] (set i (+ i 1)) i)
          (doto [(pick-values 2 (i++) (select 1 (i++) :X) (values (i++) (i++)))]
                (table.insert i)))
      [1 2 4])
  (== (let [pack (or table.pack #(doto [$...] (tset :n (select :# $...))))
            t (pack (pick-values 3 (pick-values 1 (values :x :y :z))))]
        [t.n ((or _G.unpack table.unpack) t)])
      [3 :x])
  (== (let [pack (or table.pack #(doto [$...] (tset :n (select :# ...))))]
        (pack (pick-values 5 :x (do :y) (do :z))))
      {1 :x 2 :y 3 :z :n 5}))

(fn test-with-open []
  (== (do
        (var fh nil)
        (local (ok msg) (pcall #(with-open [f (io.tmpfile)]
                                  (set fh f)
                                  (error :bork!))))
        [(io.type fh) ok (msg:match :bork!)])
      ["closed file" false "bork!"])
  (== (do
        (var (fh1 fh2) nil)
        [(with-open [f1 (io.tmpfile) f2 (io.tmpfile)]
           (set [fh1 fh2] [f1 f2])
           (f1:write :asdf)
           (f1:seek :set 0)
           (f1:read :*a))
         (io.type fh1)
         (io.type fh2)])
      ["asdf" "closed file" "closed file"])
  (== [(with-open [proc1 (io.popen "echo hi") proc2 (io.popen "echo bye")]
         (values (proc1:read) (proc2:read)))]
      ["hi" "bye"])
  (== (do
        (var fh nil)
        (local (ok msg) (pcall #(with-open [f (io.tmpfile)]
                                  (set fh f)
                                  (error {:bork! :bark!}))))
        [(io.type fh) ok (case msg {:bork! :bark!} msg _ "didn't match")])
      ["closed file" false {:bork! :bark!}]))

(fn test-comment []
  (t.= "--[[ hello world ]]\nreturn nil"
                  (fennel.compile-string "(comment hello world)"))
  (t.= "--[[ \"hello\nworld\" ]]\nreturn nil"
                  (fennel.compile-string "(comment \"hello\nworld\")"))
  (t.= "--[[ \"hello]\\]lol\" ]]\nreturn nil"
                  (fennel.compile-string "(comment \"hello]]lol\")")))

(fn test-nest []
  (let [nested (fennel.dofile "src/fennel.fnl" {:compilerEnv _G})]
    (t.= fennel.version nested.version)))

(fn test-sym []
  (t.= "return \"f_1_auto.foo:bar\""
                  (fennel.compile-string
                   "(eval-compiler (string.format \"%q\" (view `f#.foo:bar)))")))

(fn test-stable-kv-output []
  (let [add-keys "(macro add-keys [t ...]
  (faccumulate [t t i 1 (select :# ...) 2]
    (let [(k v) (select i ...)] (doto t (tset k v)))))"
        cases [["{:a 1 :b 2 :2 :s2 2 :n2 true :btrue :true :strue}"
                "{a = 1, b = 2, [\"2\"] = \"s2\", [2] = \"n2\", [true] = \"btrue\", [\"true\"] = \"strue\"}"
                "original table literal key order should be preserved"]
               [(.. add-keys "\n"
                    "(add-keys {:c 3 :a 1} :b 2 :d 4 :2 :b 2 :b1 [9] :tbl9 true :t :true :t1)")
                "{c = 3, a = 1, [2] = \"b1\", [true] = \"t\", [\"2\"] = \"b\", b = 2, d = 4, [\"true\"] = \"t1\", [{9}] = \"tbl9\"}"
                "added keys should be sorted: numbers>booleans>strings>tables>other"]]]
    (each [_ [input expected msg] (ipairs cases)]
      (t.= (: (fennel.compile-string input) :gsub "^return%s*" "")
           expected msg))))

{: test-booleans
 : test-calculations
 : test-comparisons
 : test-conditionals
 : test-core
 : test-destructuring
 : test-edge
 : test-functions
 : test-hashfn
 : test-if
 : test-pick-values
 : test-values
 : test-with-open
 : test-method-calls
 : test-comment
 : test-nest
 : test-sym
 : test-stable-kv-output
}
