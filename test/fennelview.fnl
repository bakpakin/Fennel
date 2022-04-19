(local l (require :luaunit))
(local fennel (require :fennel))
(local view (require :fennel.view))
(local {: generate} (fennel.dofile "test/generate.fnl"))

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

(fn test-generated []
  (for [_ 1 16]
    (let [item (generate 1)
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

(fn test-cycles []
  (let [t {:a 1 :b 2}
        t2 {:tbl [1 :b] :foo 19}
        sparse [:abc]]
    (set t.t t)
    (tset t2.tbl 3 t2)
    (tset sparse 4 sparse)
    (l.assertEquals (view t) "@1{:a 1 :b 2 :t @1{...}}")
    (l.assertEquals (view t2) "@1{:foo 19 :tbl [1 \"b\" @1{...}]}")
    (l.assertEquals (view sparse) "@1[\"abc\" nil nil @1[...]]")))

(fn test-newline []
  (let [s "hello\nworld!\n"]
    (l.assertEquals (view s) "\"hello\nworld!\n\"")
    (l.assertEquals (view s {:escape-newlines? true})
                    "\"hello\\nworld!\\n\"")))

(fn test-escapes []
  (l.assertEquals (view ["\a" "\t"]) "[\"\\a\" \"\\t\"]")
  (l.assertEquals (view "[\7-\13]") "\"[\\a-\\r]\""))

(fn test-gaps []
  (l.assertEquals (view {967216353 788}) "{967216353 788}"))

(fn test-utf8 []
  (when _G.utf8
    ;; make sure everything produced is valid utf-8
    (for [i 1 100]
      (var x [])
      (for [j 1 100]
        (table.insert x (string.char (math.random 0 255))))
      (set x (view (table.concat x)))
      (l.assertNotIsNil (_G.utf8.len x)
                        (.. "invalid utf-8: " x "\"")))
    ;; make sure valid utf-8 doesn't get escaped
    (for [i 1 100]
      (var x [])
      (for [j 1 100]
        (table.insert x (_G.utf8.char (if (= 0 (math.random 0 1))
                                       (math.random 0x80 0xd7ff)
                                       (math.random 0xe000 0x10ffff)))))
      (l.assertNotStrContains (view (table.concat x)) "\\"))
    ;; validate utf-8 length
    ;; this one is a little weird. since the only place utf-8 length is
    ;; exposed is within the indentation code, we have to generate some
    ;; fixed-size string to put in an object, then verify the output's
    ;; length to be another fixed size.
    (for [i 1 100]
      (var x ["æ"])
      (for [j 1 100]
        (table.insert x (_G.utf8.char (if (= 0 (math.random 0 1))
                                       (math.random 0x80 0xd7ff)
                                       (math.random 0xe000 0x10ffff)))))
      (l.assertEquals (_G.utf8.len (view {(table.concat x) [1 2]})) 217))))

{: test-generated
 : test-newline
 : test-fennelview-userdata-handling
 : test-cycles
 : test-escapes
 : test-gaps
 : test-utf8}
