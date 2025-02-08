(local t (require :test.faith))
(local {: view &as fennel} (require :fennel))
(local {: generate} (fennel.dofile "test/generate.fnl"))

(fn count [t] (accumulate [c 0 _ (pairs t)] (+ c 1)))

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

(fn pp-list [x pp opts indent]
  (values (icollect [i v (ipairs x)]
            (let [v (pp v opts (+ 1 indent) true)]
              (if (= i 1) (.. "(" v)
                  (= i (length x)) (.. " " v ")")
                  (.. " " v))))
          true))

(fn test-generated []
  (for [_ 1 16]
    (let [item (generate 1)
          viewed (view item)
          round-tripped (fennel.eval viewed)]
      ;; you would think assertEquals would work here but it doesn't!
      ;; it is easy to confuse it with randomly generated tables.
      (t.is (deep= item round-tripped) viewed))))

(fn test-userdata-handling []
  (let [view-target {:my-userdata io.stdout}
        expected-with-mt "{:my-userdata \"HI, I AM USERDATA\"}"
        expected-without-mt "^%{%:my%-userdata %#%<file %([x0-9a-f]+%)%>%}$"]
    (t.match expected-without-mt (view view-target {:one-line? true}) true)
    (tset (getmetatable io.stdout) :__fennelview #"\"HI, I AM USERDATA\"")
    (t.= (view view-target {:one-line? true})
         expected-with-mt)
    (tset (getmetatable io.stdout) :__fennelview nil)))

(fn test-ast []
  (let [l1 (fennel.list 1 2 3)]
    (t.= "[[1 (1 2 3) 2]]" (view [[1 l1 2]]))
    (t.= "(a {} [1 2])" (eval-compiler (view (view '(a {} [1 2])))))
    (t.= "{:abc [(1 2 3)]}" (view {:abc [l1]}))
    (t.= "[(1 2 3)]" (view [l1] {:one-line? true}))
    (t.= "{:abc [(1 2 3)]}"
         (view {:abc [(fennel.list 1 2 3)]} {:one-line? true}))
    (t.= "[(\"a\" \"a b\" [1 2 3] {:a (1 2 3) :b {}})]"
         (let [l2 (fennel.list "a" "a b" [1 2 3] {:a l1 :b []})]
           (view [l2])))))

(fn test-numbers []
  (t.= "123" (view 123))
  (t.= "2.4" (view 2.4))
  (t.= "1e+308" (view (fennel.eval (string.rep "9" 308))))
  (t.= ".inf" (view (fennel.eval (string.rep "9" 309))))
  (t.= ".inf" (view (fennel.eval "(/ 1 0)")))
  (t.= "-.inf" (view (fennel.eval "(/ -1 0)")))
  (t.= ".inf" (view (fennel.eval ".inf")))
  (t.= "-.inf" (view (fennel.eval "-.inf")))
  (t.= ".nan" (view (fennel.eval ".nan")))
  (t.match ":pi 3.1415926" (fennel.view math)))

(fn test-cycles []
  (let [t1 {:a 1 :b 2}
        t2 {:tbl [1 :b] :foo 19}
        sparse [:abc]]
    (set t1.t t1)
    (tset t2.tbl 3 t2)
    (tset sparse 4 sparse)
    (t.= (view t1) "@1{:a 1 :b 2 :t @1{...}}")
    (t.= (view t2) "@1{:foo 19 :tbl [1 \"b\" @1{...}]}")
    (t.= (view sparse {:max-sparse-gap 10}) "@1[\"abc\" nil nil @1[...]]")
    (t.= "@1[@1[...]]" (let [v1 []]
                         (table.insert v1 v1)
                         (view v1)))
    (t.= "@1{:t1 @1{...}}" (let [t1 {}]
                             (set t1.t1 t1)
                             (view t1)))
    (t.= "@1{:t2 {:t1 @1{...}}}" (let [t1 {}
                                       t2 {:t1 t1}]
                                   (set t1.t2 t2)
                                   (view t1)))
    (t.= "@1{@1{...} @1{...}}" (let [t1 {}] (tset t1 t1 t1) (view t1)))
    (t.= "[[[[[[[[[[...]]]]]]]]]]" (let [v1 []]
                                     (table.insert v1 v1)
                                     (view v1 {:detect-cycles? false
                                               :one-line? true
                                               :depth 10}))))
  (t.= "@1[1
   2
   3
   @2[1
      2
      @1[...]]
   [1
    2
    @2[...]]]"
       (let [v1 [1 2 3]
             v2 [1 2 v1]
             v3 [1 2 v2]]
         (table.insert v1 v2)
         (table.insert v1 v3)
         (view v1 {:line-length 1})))
  (t.= "{{{{...} {...}} {{...} {...}}} {{{...} {...}} {{...} {...}}}}"
       (let [t1 []]
         (tset t1 t1 t1)
         (view t1 {:detect-cycles? false :one-line? true :depth 4})))
  (let [v1 []
        v2 [v1]
        v3 [v1 v2]
        v4 [v2 v3]
        v5 [v3 v4]
        v6 [v4 v5]
        v7 [v5 v6]
        v8 [v6 v7]
        v9 [v7 v8]
        v10 [v8 v9]
        v11 [v9 v10]]
    (table.insert v1 v2)
    (table.insert v1 v3)
    (table.insert v1 v4)
    (table.insert v1 v5)
    (table.insert v1 v6)
    (table.insert v1 v7)
    (table.insert v1 v8)
    (table.insert v1 v9)
    (table.insert v1 v10)
    (table.insert v1 v11)
    (t.= "@1[@2[@1[...]]
   @3[@1[...] @2[...]]
   @4[@2[...] @3[...]]
   @5[@3[...] @4[...]]
   @6[@4[...] @5[...]]
   @7[@5[...] @6[...]]
   @8[@6[...] @7[...]]
   @9[@7[...] @8[...]]
   @10[@8[...] @9[...]]
   [@9[...] @10[...]]]"
         (view v1))
    (table.insert v2 v11)
    (t.= "@1[@2[@1[...]
      @3[@4[@5[@6[@7[@1[...] @2[...]] @8[@2[...] @7[...]]]
               @9[@8[...] @6[...]]]
            @10[@9[...] @5[...]]]
         @11[@10[...] @4[...]]]]
   @7[...]
   @8[...]
   @6[...]
   @9[...]
   @5[...]
   @10[...]
   @4[...]
   @11[...]
   @3[...]]"
         (view v1))))

(fn test-newline []
  (let [s "hello\nworld!\n"]
    (t.= (view s) "\"hello\nworld!\n\"")
    (t.= (view s {:escape-newlines? true})
         "\"hello\\nworld!\\n\"")))

(fn test-escapes []
  (t.= (view ["\a" "\t"]) "[\"\\a\" \"\\t\"]")
  (t.= (view "[\7-\13]") "\"[\\a-\\r]\"")
  (t.= (view (string.char 27)) "\"\\027\""
       "view should default string escapes to decimal")
  (t.= (view ["\027" "\a"] {:byte-escape #(: "\\x%2x" :format $)})
       "[\"\\x1b\" \"\\a\"]")
  (t.= (view ["\027" "\a"] {:byte-escape #(: "\\%03o" :format $)})
       "[\"\\033\" \"\\a\"]"))

(fn test-gaps []
  (t.= "{1 1 3 3}" (view {1 1 3 3}))
  (t.= (view {967216353 788}) "{967216353 788}"))

(fn test-utf8 []
  (when _G.utf8
    ;; make sure everything produced is valid utf-8
    (for [_ 1 100]
      (var x [])
      (for [_ 1 100]
        (table.insert x (string.char (math.random 0 255))))
      (set x (view (table.concat x)))
      (t.is (_G.utf8.len x) (.. "invalid utf-8: " x "\"")))
    ;; make sure valid utf-8 doesn't get escaped
    (for [_ 1 100]
      (let [x []]
        (for [_ 1 100]
          (table.insert x (_G.utf8.char (if (= 0 (math.random 0 1))
                                            (math.random 0x80 0xd7ff)
                                            (math.random 0xe000 0x10ffff)))))
        (t.not-match "\\" (view (table.concat x)))))
    ;; validate utf-8 length
    ;; this one is a little weird. since the only place utf-8 length is
    ;; exposed is within the indentation code, we have to generate some
    ;; fixed-size string to put in an object, then verify the output's
    ;; length to be another fixed size.
    (for [_ 1 100]
      (let [x ["æ"]]
        (for [_ 1 100]
          (table.insert x (_G.utf8.char (if (= 0 (math.random 0 1))
                                            (math.random 0x80 0xd7ff)
                                            (math.random 0xe000 0x10ffff)))))
        (t.= (_G.utf8.len (view {(table.concat x) [1 2]})) 217)))))

(fn test-seq-comments []
  ;; a sequence containing a comment as its last item should have its closing
  ;; delimiter on a new line.
  (let [(_ok? ast) ((fennel.parser (fennel.string-stream "(print [1\n;hi\n])")
                                   "" {:comments true}))]
    (t.= (view ast) "(print [1\n ;hi\n ])"))
  ;; a sequence containing a comment should print on multiple lines.
  (let [(_ok? ast) ((fennel.parser (fennel.string-stream "(print [1;hi\n2])")
                                   "" {:comments true}))]
    (t.= (view ast) "(print [1\n ;hi\n 2])")))

(fn test-once-skip-opts []
  (t.= (view "a" {:prefer-colon? {:once true}}) ":a")
  (t.= (view ["a"] {:prefer-colon? {:once true}}) "[\"a\"]")
  (t.= (view ["a" ["b"] "c"]
             {:prefer-colon? {:once true :after {:once true}}})
       "[:a [\"b\"] :c]")
  (t.= (view ["a" ["b" ["c"]] "d"]
             {:prefer-colon? {:once true :after {:once true :after {:once true}}}})
       "[:a [:b [\"c\"]] :d]")
  (t.= (view ["a" ["b" ["c" ["d"] "e"] "f"] "g"]
             {:prefer-colon? {:once true :after {:once true :after {:once true}}}})
       "[:a [:b [\"c\" [\"d\"] \"e\"] :f] :g]")
  (let [vector (fn [...]
                 (->> {:__fennelview
                       (fn [t view opts indent]
                         (view t (doto opts
                                   (tset :metamethod?
                                         {:once false :after opts.metamethod?})
                                   (tset :empty-as-sequence?
                                         {:once true :after opts.empty-as-sequence?}))
                               indent))}
                      (setmetatable [...])))]
    (t.= (view (vector)) "[]")
    (t.= (view (vector [])) "[{}]")
    (t.= (view (vector (vector))) "[[]]")))

(fn test-strings []
  (t.= "\"123\"" (view "123"))
  (t.= "\"123 \\\"456\\\" 789\"" (view "123 \"456\" 789"))
  (t.= "\"ваыв\"" (view "ваыв")))

(fn test-sequence []
  (t.= "{}" (view []))
  (t.= "[]" (view [] {:empty-as-sequence? true}))
  (t.= "[1 2 3]" (view [1 2 3]))
  (t.= "[0\n 1\n 2\n 3\n 4\n 5\n 6\n 7\n 8\n 9\n 10]"
       (view [0 1 2 3 4 5 6 7 8 9 10] {:line-length 5}))
  (t.= "[1 2 3]" (view [1 2 3] {:preprocess (fn [x] x)}))
  (t.= "{:a [1
     2]
 :b [1
     2]
 :c [1
     2]
 :d [1
     2]}" (view {:a [1 2] :b [1 2] :c [1 2] :d [1 2]} {:line-length 0}))
  (t.= "[2 3 4]"
       (view [1 2 3]
             {:preprocess (fn [x] (if (= (type x) :number) (+ x 1) x))})))

(fn test-kv-table []
  (t.= "{:a 1 \"a b\" 2}" (view {:a 1 "a b" 2}))
  (t.= "{:a 1\n :b 52}" (view {:a 1 :b 52} {:line-length 1}))
  (t.= "{:a 1 :b 5}" (view {:a 1 :b 5} {:one-line? true :line-length 1}))
  (t.= "{1 1 15 5}" (view {1 1 15 5}))
  (t.= "[{}]" (view [{}]))
  (t.= "[{} {}]" (view (let [t {}] [t t]) {:detect-cycles? false}))
  (t.= "{[[]] {[[]] [[[]]]}}" (view {[[]] {[[]] [[[]]]}}
                                    {:empty-as-sequence? true}))
  (t.= "[1\n 2\n [3 4]]" (view [1 2 [3 4]] {:line-length 7}))
  (t.= "{{:a 1} {:b 2 :c 3}}" (view {{:a 1} {:b 2 :c 3}}))
  (t.= "{-2 1}" (view {-2 1}))
  (t.= "{\"ваыв\" {4 {\"ваыв\" 5}
         6 \"aoeuaoeu\"}
 [1] [2 [3]]}"
       (view {[1] [2 [3]] :ваыв {4 {:ваыв 5} 6 :aoeuaoeu}}
             {:line-length 15}))
  (t.= "{:a [1 2 3 4 5 6 7] :b [1 2 3 4 5 6 7] :c [1 2 3 4 5 6 7] :d [1 2 3 4 5 6 7]}"
       (view {:a [1 2 3 4 5 6 7]
              :b [1 2 3 4 5 6 7]
              :c [1 2 3 4 5 6 7]
              :d [1 2 3 4 5 6 7]}))
  (t.= "[{:aaa [1
        2
        3]}]"
       (view [{:aaa [1 2 3]}] {:line-length 0}))
  (t.= "@1{:a 1
   :b [1
       @1{...}
       2
       3]
   :c 2}" (let [t1 {:a 1 :c 2}
                v1 [1 2 3]]
            (set t1.b v1)
            (table.insert v1 2 t1)
            (view t1 {:line-length 1})))
  (t.= "{0 1}" (view {0 1}))
  (t.= "{-2 1 1 -2}" (view {-2 1 1 -2}))
  (t.= "[1 nil nil nil 5]" (view {1 1 5 5} {:max-sparse-gap 5}))
  (t.= "{:a \"b\"}"
       (view (setmetatable {} {:__pairs #(values next {:a :b} nil)})))
  (t.= "{11 1}" (view {11 1}))
  (t.= "{:a [1 2 3 4 5 6 7 8]
 :b [1 2 3 4 5 6 7 8]
 :c [1 2 3 4 5 6 7 8]
 :d [1 2 3 4 5 6 7 8]}"
       (view  {:a [1 2 3 4 5 6 7 8]
               :b [1 2 3 4 5 6 7 8]
               :c [1 2 3 4 5 6 7 8]
               :d [1 2 3 4 5 6 7 8]}))
  (t.= "{\"ƁƁƁ\" {\"ƁƁƁ\" {}
        \"ǍǍǍ\" {}}
 \"ǍǍǍ\" {}}"
       (view {:ǍǍǍ {}
              :ƁƁƁ {:ǍǍǍ {} :ƁƁƁ {}}}
             {:line-length 1}))
  (t.= "{1 1 5 5 :n 5}" (view {1 1 5 5 :n 5}))
  (t.= "{1 \"a\" 1.2345 \"combination on my luggage\"}"
       (view {1 :a 1.2345 "combination on my luggage"})))

(fn test-metamethod []
  (let [mt (setmetatable [] {:__fennelview (fn [] "META")})]
    (t.= (view mt) "META"))
  (t.= "(:a
 \"a b\"
 [1 2 3]
 {:a (1
      2
      3)
  :b {}})"
       (let [l1 (setmetatable [1 2 3] {:__fennelview pp-list})
             l2 (setmetatable ["a" "a b" [1 2 3] {:a l1 :b []}]
                              {:__fennelview pp-list})]
         (view l2)))
  (t.= (.. "[\":colon \\\"quote\\\" \\\"depends\\\"\" \":colon "
           "\\\"quote\\\" :depends\" \":colon \\\"quote\\\" \\\"depends\\\"\"]")
       (let [styles (setmetatable [:colon :quote :depends]
                                  {:__fennelview
                                   #(icollect [_ s (ipairs $1)]
                                      ($2 s $3 $4 (when (not= s :depends)
                                                    (= s :colon))))})]
         (view [(view styles)
                (view styles {:prefer-colon? true})
                (view styles {:prefer-colon? false})]
               {:one-line? true})))
  (t.= "[\"empty-table\" [1] {:x \"empty-table\" :empty-table [2]}]"
       (view [[] [1] {:x [] [] [2]}]
             {:preprocess (fn [x] (if (and (= (type x) :table) (= (next x) nil))
                                      :empty-table x))})))

(fn test-colon []
  (t.= "{\"@foo.bar\" 42}" (view {"@foo.bar" 42})))

{: test-numbers
 : test-strings
 : test-sequence
 : test-kv-table
 : test-generated
 : test-newline
 : test-metamethod
 : test-userdata-handling
 : test-ast
 : test-cycles
 : test-escapes
 : test-gaps
 : test-utf8
 : test-colon
 : test-seq-comments
 : test-once-skip-opts}
