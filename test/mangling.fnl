(local l (require :test.luaunit))
(local fennel (require :fennel))

(local mangling-tests {:3 "__fnl_global__3"
                       :a "a"
                       :a-b-c "__fnl_global__a_2db_2dc"
                       :a_3 "a_3"
                       :a_b-c "__fnl_global__a_5fb_2dc"})

(fn test-mangling []
  (each [k v (pairs mangling-tests)]
    (let [manglek (fennel.mangle k)
          unmanglev (fennel.unmangle v)]
      (l.assertEquals v manglek)
      (l.assertEquals k unmanglev))))

{: test-mangling}

