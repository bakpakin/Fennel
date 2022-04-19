(local l (require :luaunit))
(local fennel (require :fennel))

(macro == [form expected ?opts]
  `(let [(ok# val#) (pcall fennel.eval ,(view form) ,?opts)]
     (l.assertTrue ok# val#)
     (l.assertEquals val# ,expected)))

(fn test-each []
  (== (each [x (pairs [])] nil) nil)
  (== (let [t {:a 1 :b 2} t2 {}]
        (each [k v (pairs t)]
          (tset t2 k v))
        (+ t2.a t2.b)) 3)
  (== (do (var t 0) (local (f s v) (pairs [1 2 3]))
          (each [_ x (values f (doto s (table.remove 1)))] (set t (+ t x))) t) 5)
  (== (do (var t 0) (local (f s v) (pairs [1 2 3]))
          (each [_ x (values f s v)] (set t (+ t x))) t) 6)
  (== (do (var x 0) (while (< x 7) (set x (+ x 1))) x) 7))

(fn test-for []
  (== (for [y 0 2] nil) nil)
  (== (do (var x 0) (for [y 1 20 2] (set x (+ x 1))) x) 10)
  (== (do (var x 0) (for [y 1 5] (set x (+ x 1))) x) 5))

(fn test-comprehensions []
  (== (collect [k v (pairs {:a 1 :b 2 :c 3})] v k)
      [:a :b :c])
  (== (collect [k v (pairs {:apple :red :orange :orange})]
        (values (.. :color- v) (.. :fruit- k)))
      {:color-red :fruit-apple :color-orange :fruit-orange})
  (== (collect [k v (pairs {:foo 3 :bar 4 :baz 5 :qux 6})]
        (if (> v 4) (values k (+ v 1))))
      {:baz 6 :qux 7})
  (== (collect [k v (pairs {:neon :lights}) :into {:shimmering-neon :lights}]
        (values k (v:upper)))
      {:neon "LIGHTS" :shimmering-neon "lights"})
  (== (icollect [_ v (ipairs [1 2 3 4 5 6])]
        (if (= 0 (% v 2)) (* v v)))
      [4 16 36])
  (== (icollect [num (string.gmatch "24,58,1999" "%d+")]
        (tonumber num))
      [24 58 1999])
  (== (icollect [_ x (ipairs [2 3]) :into [11]] (* x 11))
      [11 22 33])
  (== (let [xs [11]] (icollect [_ x (ipairs [2 3]) :into xs] (* x 11)))
      [11 22 33])
  (let [code "(icollect [_ x (ipairs [2 3]) :into \"oops\"] x)"
        (ok? msg) (pcall fennel.compileString code)]
    (l.assertFalse ok?)
    (l.assertStrContains msg ":into clause"))
  (let [code "(icollect [_ x (ipairs [2 3]) :into 2] x)"
        (ok? msg) (pcall fennel.compileString code)]
    (l.assertFalse ok?)
    (l.assertStrContains msg ":into clause"))
  (== (do (macro twice [expr] `(do ,expr ,expr))
          (twice (icollect [i v (ipairs [:a :b :c])] v)))
      [:a :b :c]))

(fn test-accumulate []
  (== (do (var x true)
          (let [y (accumulate [state :init
                               _ _ (pairs {})]
                    (do (set x false)
                        :update))]
            [x y]))
      [true :init])
  (== (accumulate [s :fen
                   _ c (ipairs [:n :e :l :o]) :until (>= c :o)]
        (.. s c))
      "fennel")
  (== (accumulate [n 0 _ _ (pairs {:one 1 :two nil :three 3})]
        (+ n 1))
      2)
  (== (accumulate [yes? true
                   _ s (ipairs [:yes :no :yes])]
        (and yes? (string.match s :yes)))
      nil)
  (== (let [(a b) (accumulate [(x y) (values 8 2) _ (ipairs [1])] (values y x))]
        (+ a b)) 10)
  (== (do (macro twice [expr] `(do ,expr ,expr))
          (twice (accumulate [s "" _ v (ipairs [:a :b])] (.. s v))))
      :ab))

(fn test-conditions []
  (== (do (var x 0) (for [i 1 10 :until (= i 5)] (set x i)) x) 4)
  (== (do (var x 0) (each [_ i (ipairs [1 2 3]) :until (< 2 x)] (set x i)) x) 3)
  (== (icollect [_ i (ipairs [4 5 6]) :until (= i 5)] i) [4])
  (== (collect [i x (pairs [4 5 6]) :until (= x 6)] (values i x)) [4 5])
  (== (icollect [i x (pairs [4 5 6]) :into [3] :until (= x 6)] x) [3 4 5]))

{: test-each
 : test-for
 : test-comprehensions
 : test-accumulate
 : test-conditions}
