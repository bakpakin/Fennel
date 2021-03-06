(local l (require :test.luaunit))
(local fennel (require :fennel))

(fn == [code expected]
  (l.assertEquals (fennel.eval code) expected))

(fn test-each []
  (== "(each [x (pairs [])] nil)" nil)
  (== "(let [t {:a 1 :b 2} t2 {}]
         (each [k v (pairs t)]
         (tset t2 k v))
         (+ t2.a t2.b))" 3)
  (== "(var t 0) (local (f s v) (pairs [1 2 3]))
       (each [_ x (values f (doto s (table.remove 1)))] (set t (+ t x))) t" 5)
  (== "(var t 0) (local (f s v) (pairs [1 2 3]))
       (each [_ x (values f s v)] (set t (+ t x))) t" 6)
  (== "(var x 0) (while (< x 7) (set x (+ x 1))) x" 7))

(fn test-for []
  (== "(for [y 0 2] nil)" nil)
  (== "(var x 0) (for [y 1 20 2] (set x (+ x 1))) x" 10)
  (== "(var x 0) (for [y 1 5] (set x (+ x 1))) x" 5))

(fn test-comprehensions []
  (== "(collect [k v (pairs {:apple :red :orange :orange})]
         (values (.. :color- v) (.. :fruit- k)))"
      {:color-red :fruit-apple :color-orange :fruit-orange})
  (== "(collect [k v (pairs {:foo 3 :bar 4 :baz 5 :qux 6})]
         (when (> v 4) (values k (+ v 1))))"
      {:baz 6 :qux 7})
  (== "(icollect [_ v (ipairs [1 2 3 4 5 6])]
         (when (= 0 (% v 2)) (* v v)))"
      [4 16 36])
  (== "(icollect [num (string.gmatch \"24,58,1999\" \"%d+\")]
         (tonumber num))"
      [24 58 1999]))

(fn test-conditions []
  (== "(var x 0) (for [i 1 10 :until (= i 5)] (set x i)) x" 4)
  (== "(var x 0) (each [_ i (ipairs [1 2 3]) :until (< 2 x)] (set x i)) x" 3)
  (== "(icollect [_ i (ipairs [4 5 6]) :until (= i 5)] i)" [4])
  (== "(collect [i x (pairs [4 5 6]) :until (= x 6)] (values i x))" [4 5]))

{: test-each
 : test-for
 : test-comprehensions
 : test-conditions}
