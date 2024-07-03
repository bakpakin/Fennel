(local t (require :test.faith))
(local fennel (require :fennel))
(local view (require :fennel.view))

(fn c [code]
  (fennel.compileString code {:allowedGlobals false :compiler-env _G}))

(fn v [code]
  (view ((fennel.loadCode (c code) (let [env {:sequence fennel.sequence}]
                                     (set env._G env)
                                     (setmetatable env {:__index _G}))))
        {:one-line? true}))

(fn test-quote []
  (t.= (c "`:abcde") "return \"abcde\"" "simple string quoting")
  (t.= (v "`[1 2 ,(+ 1 2) 4]") "[1 2 3 4]"
                  "unquote inside quote leads to evaluation")
  (t.= (v "(let [a (+ 2 3)] `[:hey ,(+ a a)])") "[\"hey\" 10]"
                  "unquote inside other forms")
  (t.= (v "`[:a :b :c]") "[\"a\" \"b\" \"c\"]"
                  "quoted sequential table")
  (local viewed (v "`{:a 5 :b 9}"))
  (t.is (or (= viewed "{:a 5 :b 9}") (= viewed "{:b 9 :a 5}"))
                (.. "quoted keyed table: " viewed)))

(fn test-quoted-source []
  (c "\n\n(eval-compiler (set _G.source-line (. `abc :line)))")
  (t.= (. _G "source-line") 3 "syms have source data")
  (c "\n(eval-compiler (set _G.source-line (. `abc# :line)))")
  (t.= (. _G "source-line") 2 "autogensyms have source data")
  (c "\n\n\n(eval-compiler (set _G.source-line (. `(abc) :line)))")
  (t.= (. _G "source-line") 4 "lists have source data")
  (let [(_ msg) (pcall c "\n\n\n\n(macro abc [] `(fn [... a#] 1)) (abc)")]
    (t.match "unknown:5" msg "quoted tables have source data")))

(macro not-equal-gensym []
  (let [s (gensym :sym)]
    `(let [,s 10 sym# 20] (and sym# (not= ,s sym#)))))

(fn test-autogensym []
  (t.is (not-equal-gensym)))

{: test-quote
 : test-quoted-source
 : test-autogensym}
