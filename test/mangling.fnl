(local t (require :test.faith))
(local fennel (require :fennel))

(local mangling-tests {:3 "__fnl_global__3"
                       :a "a"
                       :a-b-c "__fnl_global__a_2db_2dc"
                       :a_3 "a_3"
                       :a_b-c "__fnl_global__a_5fb_2dc"
                       :break "__fnl_global__break"})

(fn test-mangling []
  (each [k v (pairs mangling-tests)]
    (let [manglek (fennel.mangle k)
          unmanglev (fennel.unmangle v)]
      (t.= v manglek)
      (t.= k unmanglev)))
  ;; adding an env for evaluation causes global mangling rules to apply
  (t.is (fennel.eval "(global mangled-name true) mangled-name"
                             {:env {}})))

{: test-mangling}

