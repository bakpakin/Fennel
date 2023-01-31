(local l (require :test.luaunit))
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

(fn test-seq-comments []
  ;; a sequence containing a comment as its last item should have its closing
  ;; delimiter on a new line.
  (let [(_ok? ast) ((fennel.parser (fennel.string-stream "(print [1\n;hi\n])")
                                   "" {:comments true}))]
    (l.assertEquals (view ast) "(print [1\n ;hi\n ])"))
  ;; a sequence containing a comment should print on multiple lines.
  (let [(_ok? ast) ((fennel.parser (fennel.string-stream "(print [1;hi\n2])")
                                   "" {:comments true}))]
    (l.assertEquals (view ast) "(print [1\n ;hi\n 2])")))

(fn test-once-skip-opts []
  (l.assertEquals (view "a" {:prefer-colon? {:once true}}) ":a")
  (l.assertEquals (view ["a"] {:prefer-colon? {:once true}}) "[\"a\"]")
  (l.assertEquals (view ["a" ["b"] "c"]
                        {:prefer-colon? {:once true :after {:once true}}})
                  "[:a [\"b\"] :c]")
  (l.assertEquals (view ["a" ["b" ["c"]] "d"]
                        {:prefer-colon? {:once true :after {:once true :after {:once true}}}})
                  "[:a [:b [\"c\"]] :d]")
  (l.assertEquals (view ["a" ["b" ["c" ["d"] "e"] "f"] "g"]
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
    (l.assertEquals (view (vector)) "[]")
    (l.assertEquals (view (vector [])) "[{}]")
    (l.assertEquals (view (vector (vector))) "[[]]")))

(fn test-fennelview []
  (let [cases {"((require :fennel.view) \"123\")"
               "\"123\""
               "((require :fennel.view) \"123 \\\"456\\\" 789\")"
               "\"123 \\\"456\\\" 789\""
               "((require :fennel.view) 123)"
               "123"
               "((require :fennel.view) 2.4)"
               "2.4"
               "((require :fennel.view) [] {:empty-as-sequence? true})"
               "[]"
               "((require :fennel.view) [])"
               "{}"
               "((require :fennel.view) [1 2 3])"
               "[1 2 3]"
               "((require :fennel.view) {:a 1 \"a b\" 2})"
               "{:a 1 \"a b\" 2}"
               "((require :fennel.view) [])"
               "{}"
               "((require :fennel.view) [] {:empty-as-sequence? true})"
               "[]"
               "((require :fennel.view) [1 2 3])"
               "[1 2 3]"
               "((require :fennel.view) [0 1 2 3 4 5 6 7 8 9 10] {:line-length 5})"
               "[0\n 1\n 2\n 3\n 4\n 5\n 6\n 7\n 8\n 9\n 10]"
               "((require :fennel.view) {:a 1 \"a b\" 2})"
               "{:a 1 \"a b\" 2}"
               "((require :fennel.view) {:a 1 :b 52} {:line-length 1})"
               "{:a 1\n :b 52}"
               "((require :fennel.view) {:a 1 :b 5} {:one-line? true :line-length 1})"
               "{:a 1 :b 5}"
               ;; nesting
               "((require :fennel.view) (let [t {}] [t t]) {:detect-cycles? false})"
               "[{} {}]"
               "((require :fennel.view) (let [t {}] [t t]))"
               "[{} {}]"
               "((require :fennel.view) [{}])"
               "[{}]"
               "((require :fennel.view) {[{}] []})"
               "{[{}] {}}"
               "((require :fennel.view) {[[]] {[[]] [[[]]]}} {:empty-as-sequence? true})"
               "{[[]] {[[]] [[[]]]}}"
               "((require :fennel.view) [1 2 [3 4]] {:line-length 7})"
               "[1\n 2\n [3 4]]"
               "((require :fennel.view) {[1] [2 [3]] :data {4 {:data 5} 6 [0 1 2 3]}} {:line-length 15})"
               "{:data [nil\n        nil\n        nil\n        {:data 5}\n        nil\n        [0\n         1\n         2\n         3]]\n [1] [2 [3]]}"
               "((require :fennel.view) {{:a 1} {:b 2 :c 3}})"
               "{{:a 1} {:b 2 :c 3}}"
               "((require :fennel.view) [{:aaa [1 2 3]}] {:line-length 0})"
               "[{:aaa [1\n        2\n        3]}]"
               "((require :fennel.view) {:a [1 2 3 4 5 6 7] :b [1 2 3 4 5 6 7] :c [1 2 3 4 5 6 7] :d [1 2 3 4 5 6 7]})"
               "{:a [1 2 3 4 5 6 7] :b [1 2 3 4 5 6 7] :c [1 2 3 4 5 6 7] :d [1 2 3 4 5 6 7]}"
               "((require :fennel.view) {:a [1 2] :b [1 2] :c [1 2] :d [1 2]} {:line-length 0})"
               "{:a [1\n     2]\n :b [1\n     2]\n :c [1\n     2]\n :d [1\n     2]}"
               "((require :fennel.view)  {:a [1 2 3 4 5 6 7 8] :b [1 2 3 4 5 6 7 8] :c [1 2 3 4 5 6 7 8] :d [1 2 3 4 5 6 7 8]})"
               "{:a [1 2 3 4 5 6 7 8]\n :b [1 2 3 4 5 6 7 8]\n :c [1 2 3 4 5 6 7 8]\n :d [1 2 3 4 5 6 7 8]}"
               ;; sparse tables
               "((require :fennel.view) {0 1})"
               "{0 1}"
               "((require :fennel.view) {-2 1})"
               "{-2 1}"
               "((require :fennel.view) {-2 1 1 -2})"
               "{-2 1 1 -2}"
               "((require :fennel.view) {1 1 5 5})"
               "[1 nil nil nil 5]"
               "((require :fennel.view) {1 1 15 5})"
               "{1 1 15 5}"
               "((require :fennel.view) {1 1 15 15} {:one-line? true :max-sparse-gap 1000})"
               "[1 nil nil nil nil nil nil nil nil nil nil nil nil nil 15]"
               "((require :fennel.view) {1 1 3 3} {:max-sparse-gap 1})"
               "{1 1 3 3}"
               "((require :fennel.view) {1 1 3 3} {:max-sparse-gap 0})"
               "{1 1 3 3}"
               "((require :fennel.view) {1 1 5 5 :n 5})"
               "{1 1 5 5 :n 5}"
               "((require :fennel.view) [1 nil 2 nil nil 3 nil nil nil])"
               "[1 nil 2 nil nil 3]"
               "((require :fennel.view) [nil nil nil nil nil 1])"
               "[nil nil nil nil nil 1]"
               "((require :fennel.view) {10 1})"
               "[nil nil nil nil nil nil nil nil nil 1]"
               "((require :fennel.view) {11 1})"
               "{11 1}"
               ;; Unicode
               "((require :fennel.view) \"ваыв\")"
               "\"ваыв\""
               "((require :fennel.view) {[1] [2 [3]] :ваыв {4 {:ваыв 5} 6 [0 1 2 3]}} {:line-length 15})"
               "{\"ваыв\" [nil\n         nil\n         nil\n         {\"ваыв\" 5}\n         nil\n         [0\n          1\n          2\n          3]]\n [1] [2 [3]]}"
               ;; the next one may look incorrect in some editors, but is actually correct
               "((require :fennel.view) {:ǍǍǍ {} :ƁƁƁ {:ǍǍǍ {} :ƁƁƁ {}}} {:line-length 1})"
               "{\"ƁƁƁ\" {\"ƁƁƁ\" {}\n        \"ǍǍǍ\" {}}\n \"ǍǍǍ\" {}}"
               ;; cycles
               "(local t1 {}) (tset t1 :t1 t1) ((require :fennel.view) t1)"
               "@1{:t1 @1{...}}"
               "(local t1 {}) (tset t1 t1 t1) ((require :fennel.view) t1)"
               "@1{@1{...} @1{...}}"
               "(local v1 []) (table.insert v1 v1) ((require :fennel.view) v1)"
               "@1[@1[...]]"
               "(local t1 {}) (local t2 {:t1 t1}) (tset t1 :t2 t2) ((require :fennel.view) t1)"
               "@1{:t2 {:t1 @1{...}}}"
               "(local t1 {:a 1 :c 2}) (local v1 [1 2 3]) (tset t1 :b v1) (table.insert v1 2 t1) ((require :fennel.view) t1 {:line-length 1})"
               "@1{:a 1\n   :b [1\n       @1{...}\n       2\n       3]\n   :c 2}"
               "(local v1 [1 2 3]) (local v2 [1 2 v1]) (local v3 [1 2 v2]) (table.insert v1 v2) (table.insert v1 v3) ((require :fennel.view) v1 {:line-length 1})"
               "@1[1\n   2\n   3\n   @2[1\n      2\n      @1[...]]\n   [1\n    2\n    @2[...]]]"
               "(local v1 []) (table.insert v1 v1) ((require :fennel.view) v1 {:detect-cycles? false :one-line? true :depth 10})"
               "[[[[[[[[[[...]]]]]]]]]]"
               "(local t1 []) (tset t1 t1 t1) ((require :fennel.view) t1 {:detect-cycles? false :one-line? true :depth 4})"
               "{{{{...} {...}} {{...} {...}}} {{{...} {...}} {{...} {...}}}}"
               ;; sorry :)
               "(local v1 []) (local v2 [v1]) (local v3 [v1 v2]) (local v4 [v2 v3]) (local v5 [v3 v4]) (local v6 [v4 v5]) (local v7 [v5 v6]) (local v8 [v6 v7]) (local v9 [v7 v8]) (local v10 [v8 v9]) (local v11 [v9 v10]) (table.insert v1 v2) (table.insert v1 v3) (table.insert v1 v4) (table.insert v1 v5) (table.insert v1 v6) (table.insert v1 v7) (table.insert v1 v8) (table.insert v1 v9) (table.insert v1 v10) (table.insert v1 v11) ((require :fennel.view) v1)"
               "@1[@2[@1[...]]\n   @3[@1[...] @2[...]]\n   @4[@2[...] @3[...]]\n   @5[@3[...] @4[...]]\n   @6[@4[...] @5[...]]\n   @7[@5[...] @6[...]]\n   @8[@6[...] @7[...]]\n   @9[@7[...] @8[...]]\n   @10[@8[...] @9[...]]\n   [@9[...] @10[...]]]"
               "(local v1 []) (local v2 [v1]) (local v3 [v1 v2]) (local v4 [v2 v3]) (local v5 [v3 v4]) (local v6 [v4 v5]) (local v7 [v5 v6]) (local v8 [v6 v7]) (local v9 [v7 v8]) (local v10 [v8 v9]) (local v11 [v9 v10]) (table.insert v1 v2) (table.insert v1 v3) (table.insert v1 v4) (table.insert v1 v5) (table.insert v1 v6) (table.insert v1 v7) (table.insert v1 v8) (table.insert v1 v9) (table.insert v1 v10) (table.insert v1 v11) (table.insert v2 v11) ((require :fennel.view) v1)"
               "@1[@2[@1[...]\n      @3[@4[@5[@6[@7[@1[...] @2[...]] @8[@2[...] @7[...]]]\n               @9[@8[...] @6[...]]]\n            @10[@9[...] @5[...]]]\n         @11[@10[...] @4[...]]]]\n   @7[...]\n   @8[...]\n   @6[...]\n   @9[...]\n   @5[...]\n   @10[...]\n   @4[...]\n   @11[...]\n   @3[...]]"
               ;; __fennelview metamethod test
               "(fn pp-list [x pp opts indent] (values (icollect [i v (ipairs x)] (let [v (pp v opts (+ 1 indent) true)] (values (if (= i 1) (.. \"(\" v) (= i (length x)) (.. \" \" v \")\") (.. \" \" v))))) true)) (local l1 (setmetatable [1 2 3] {:__fennelview pp-list})) ((require :fennel.view) l1)"
               "(1\n 2\n 3)"
               "(fn pp-list [x pp opts indent] (values (icollect [i v (ipairs x)] (let [v (pp v opts (+ 1 indent) true)] (values (if (= i 1) (.. \"(\" v) (= i (length x)) (.. \" \" v \")\") (.. \" \" v))))) true)) (local l1 (setmetatable [1 2 3] {:__fennelview pp-list})) ((require :fennel.view) [l1])"
               "[(1\n  2\n  3)]"
               "(fn pp-list [x pp opts indent] (values (icollect [i v (ipairs x)] (let [v (pp v opts (+ 1 indent) true)] (values (if (= i 1) (.. \"(\" v) (= i (length x)) (.. \" \" v \")\") (.. \" \" v))))) true)) (local l1 (setmetatable [1 2 3] {:__fennelview pp-list})) ((require :fennel.view) [1 l1 2])"
               "[1\n (1\n  2\n  3)\n 2]"
               "(fn pp-list [x pp opts indent] (values (icollect [i v (ipairs x)] (let [v (pp v opts (+ 1 indent) true)] (values (if (= i 1) (.. \"(\" v) (= i (length x)) (.. \" \" v \")\") (.. \" \" v))))) true)) (local l1 (setmetatable [1 2 3] {:__fennelview pp-list})) ((require :fennel.view) [[1 l1 2]])"
               "[[1\n  (1\n   2\n   3)\n  2]]"
               "(fn pp-list [x pp opts indent] (values (icollect [i v (ipairs x)] (let [v (pp v opts (+ 1 indent) true)] (values (if (= i 1) (.. \"(\" v) (= i (length x)) (.. \" \" v \")\") (.. \" \" v))))) true)) (local l1 (setmetatable [1 2 3] {:__fennelview pp-list})) ((require :fennel.view) {:abc [l1]})"
               "{:abc [(1\n        2\n        3)]}"
               "(fn pp-list [x pp opts indent] (values (icollect [i v (ipairs x)] (let [v (pp v opts (+ 1 indent) true)] (values (if (= i 1) (.. \"(\" v) (= i (length x)) (.. \" \" v \")\") (.. \" \" v))))) true)) (local l1 (setmetatable [1 2 3] {:__fennelview pp-list})) ((require :fennel.view) l1 {:one-line? true})"
               "(1 2 3)"
               "(fn pp-list [x pp opts indent] (values (icollect [i v (ipairs x)] (let [v (pp v opts (+ 1 indent) true)] (values (if (= i 1) (.. \"(\" v) (= i (length x)) (.. \" \" v \")\") (.. \" \" v))))) true)) (local l1 (setmetatable [1 2 3] {:__fennelview pp-list})) ((require :fennel.view) [l1] {:one-line? true})"
               "[(1 2 3)]"
               "(fn pp-list [x pp opts indent] (values (icollect [i v (ipairs x)] (let [v (pp v opts (+ 1 indent) true)] (values (if (= i 1) (.. \"(\" v) (= i (length x)) (.. \" \" v \")\") (.. \" \" v))))) true)) (local l1 (setmetatable [1 2 3] {:__fennelview pp-list})) ((require :fennel.view) {:abc [l1]} {:one-line? true})"
               "{:abc [(1 2 3)]}"
               "(fn pp-list [x pp opts indent] (values (icollect [i v (ipairs x)] (let [v (pp v opts (+ 1 indent) true)] (values (if (= i 1) (.. \"(\" v) (= i (length x)) (.. \" \" v \")\") (.. \" \" v))))) true)) (local l1 (setmetatable [1 2 3] {:__fennelview pp-list})) (local l2 (setmetatable [\"a\" \"a b\" [1 2 3] {:a l1 :b []}] {:__fennelview pp-list})) ((require :fennel.view) l2)"
               "(:a\n \"a b\"\n [1 2 3]\n {:a (1\n      2\n      3)\n  :b {}})"
               "(fn pp-list [x pp opts indent] (values (icollect [i v (ipairs x)] (let [v (pp v opts (+ 1 indent) true)] (values (if (= i 1) (.. \"(\" v) (= i (length x)) (.. \" \" v \")\") (.. \" \" v))))) true)) (local l1 (setmetatable [1 2 3] {:__fennelview pp-list})) (local l2 (setmetatable [\"a\" \"a b\" [1 2 3] {:a l1 :b []}] {:__fennelview pp-list})) ((require :fennel.view) {:list l2})"
               "{:list (:a\n        \"a b\"\n        [1 2 3]\n        {:a (1\n             2\n             3)\n         :b {}})}"
               "(fn pp-list [x pp opts indent] (values (icollect [i v (ipairs x)] (let [v (pp v opts (+ 1 indent) true)] (values (if (= i 1) (.. \"(\" v) (= i (length x)) (.. \" \" v \")\") (.. \" \" v))))) true)) (local l1 (setmetatable [1 2 3] {:__fennelview pp-list})) (local l2 (setmetatable [\"a\" \"a b\" [1 2 3] {:a l1 :b []}] {:__fennelview pp-list})) ((require :fennel.view) [l2])"
               "[(:a\n  \"a b\"\n  [1 2 3]\n  {:a (1\n       2\n       3)\n   :b {}})]"
               "(fn pp-list [x pp opts indent] (values (icollect [i v (ipairs x)] (let [v (pp v opts (+ 1 indent) true)] (values (if (= i 1) (.. \"(\" v) (= i (length x)) (.. \" \" v \")\") (.. \" \" v))))) true)) (local l1 (setmetatable [1 2 3] {:__fennelview pp-list})) (local l2 (setmetatable [\"a\" \"a b\" [1 2 3] {:a l1 :b []}] {:__fennelview pp-list})) ((require :fennel.view) {:abc [l1]})"
               "{:abc [(1\n        2\n        3)]}"
               "(fn pp-list [x pp opts indent] (values (icollect [i v (ipairs x)] (let [v (pp v opts (+ 1 indent) true)] (values (if (= i 1) (.. \"(\" v) (= i (length x)) (.. \" \" v \")\") (.. \" \" v))))) true)) (local l1 (setmetatable [1 2 3] {:__fennelview pp-list})) (local l2 (setmetatable [\"a\" \"a b\" [1 2 3] {:a l1 :b []}] {:__fennelview pp-list})) ((require :fennel.view) l1 {:one-line? true})"
               "(1 2 3)"
               "(fn pp-list [x pp opts indent] (values (icollect [i v (ipairs x)] (let [v (pp v opts (+ 1 indent) true)] (values (if (= i 1) (.. \"(\" v) (= i (length x)) (.. \" \" v \")\") (.. \" \" v))))) true)) (local l1 (setmetatable [1 2 3] {:__fennelview pp-list})) (local l2 (setmetatable [\"a\" \"a b\" [1 2 3] {:a l1 :b []}] {:__fennelview pp-list})) ((require :fennel.view) [l1] {:one-line? true})"
               "[(1 2 3)]"
               "(fn pp-list [x pp opts indent] (values (icollect [i v (ipairs x)] (let [v (pp v opts (+ 1 indent) true)] (values (if (= i 1) (.. \"(\" v) (= i (length x)) (.. \" \" v \")\") (.. \" \" v))))) true)) (local l1 (setmetatable [1 2 3] {:__fennelview pp-list})) (local l2 (setmetatable [\"a\" \"a b\" [1 2 3] {:a l1 :b []}] {:__fennelview pp-list})) ((require :fennel.view) {:abc [l1]} {:one-line? true})"
               "{:abc [(1 2 3)]}"
               ;; ensure it works on lists/syms inside compiler
               "(eval-compiler
                  (set _G.out ((require :fennel.view) '(a {} [1 2]))))
                _G.out"
               "(a {} [1 2])"
               ;; ensure that `__fennelview' has higher priority than `:prefer-colon?'
               "(local styles (setmetatable [:colon :quote :depends]
                                            {:__fennelview
                                             #(icollect [_ s (ipairs $1)]
                                                ($2 s $3 $4 (when (not= s :depends) (= s :colon))))}))
                (local fennel (require :fennel))
                (fennel.view [(fennel.view styles)
                              (fennel.view styles {:prefer-colon? true})
                              (fennel.view styles {:prefer-colon? false})]
                             {:one-line? true})"
               "[\":colon \\\"quote\\\" \\\"depends\\\"\" \":colon \\\"quote\\\" :depends\" \":colon \\\"quote\\\" \\\"depends\\\"\"]"
               ;; :preprocess
               "((require :fennel.view) [1 2 3] {:preprocess (fn [x] x)})"
               "[1 2 3]"
               "((require :fennel.view) [1 2 3] {:preprocess (fn [x] (if (= (type x) :number) (+ x 1) x))})"
               "[2 3 4]"
               "((require :fennel.view) [[] [1] {:x [] [] [2]}] {:preprocess (fn [x] (if (and (= (type x) :table) (= (next x) nil)) :empty-table x))})"
               "[\"empty-table\" [1] {:x \"empty-table\" :empty-table [2]}]"
               ;; correct metamethods
               "((require :fennel.view) (setmetatable {} {:__pairs #(values next {:a :b} nil)}))" "{:a \"b\"}"}]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code {:correlate true :compiler-env _G})
                      expected code))
    (let [mt (setmetatable [] {:__fennelview (fn [] "META")})]
      (l.assertEquals (fennel.view mt) "META"))))

{: test-generated
 : test-newline
 : test-fennelview
 : test-fennelview-userdata-handling
 : test-cycles
 : test-escapes
 : test-gaps
 : test-utf8
 : test-seq-comments
 : test-once-skip-opts}
