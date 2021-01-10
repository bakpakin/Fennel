(local l (require :test.luaunit))
(local fennel (require :fennel))
(local view (require :fennelview))
(local generate (fennel.dofile "test/generate.fnl"))

(fn count [t]
  (var c 0)
  (each [_ (pairs t)] (set c (+ c 1)))
  c)

(fn table= [a b deep=]
  (let [miss-a []
        miss-b []]
    (each [k (pairs a)]
      (when (deep= (. a k) (. b k))
        (tset a k nil)
        (tset b k nil)))
    (each [k v (pairs a)]
      (when (not= (type k) :table)
        (tset miss-a (view k) v)))
    (each [k v (pairs b)]
      (when (not= (type k) :table)
        (tset miss-b (view k) v)))
    (or (= (count a) (count b))
        (deep= miss-a miss-b))))

(fn deep= [a b]
  (if (or (not= a a) (not= b b)) true
      (= (type a) (type b) :table) (table= a b deep=)
      (= (tostring a) (tostring b))))

(fn test-fennelview []
  (for [_ 1 16]
    (let [item (generate)
          viewed (view item)
          round-tripped (fennel.eval viewed)]
      ;; you would think assertEquals would work here but it doesn't!
      ;; it is easy to confuse it with randomly generated tables.
      (l.assertTrue (deep= item round-tripped) viewed))))

(fn test-fennelview-userdata-handling []
  (let [view-target {:my-userdata io.stdout}
        expected-with-mt "{:my-userdata \"HI, I AM USERDATA\"}"
        expected-without-mt "^%{%:my%-userdata %#%<file %([x0-9a-f]+%)%>%}$"]
    (l.assertStrContains (view view-target {:one-line? true})
                         expected-without-mt
                         true)
    (tset (getmetatable io.stdout) :__fennelview #"\"HI, I AM USERDATA\"")
    (l.assertEquals (view view-target {:one-line? true})
                    expected-with-mt)
    (tset (getmetatable io.stdout) :__fennelview nil)))

{: test-fennelview : test-fennelview-userdata-handling}
