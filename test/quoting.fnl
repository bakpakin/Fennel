(local l (require :test.luaunit))
(local fennel (require :fennel))
(local view (require :fennel.view))

(fn c [code]
  (fennel.compileString code {:allowedGlobals false :compiler-env _G}))

(fn v [code]
  (view ((fennel.loadCode (c code) (setmetatable {:sequence fennel.sequence}
                                                 {:__index _G})))
        {:one-line? true}))

(fn test-quote []
  (l.assertEquals (c "`:abcde") "return \"abcde\"" "simple string quoting")
  (l.assertEquals (c ",a") "return unquote(a)"
                  "unquote outside quote is simply passed thru")
  (l.assertEquals (v "`[1 2 ,(+ 1 2) 4]") "[1 2 3 4]"
                  "unquote inside quote leads to evaluation")
  (l.assertEquals (v "(let [a (+ 2 3)] `[:hey ,(+ a a)])") "[\"hey\" 10]"
                  "unquote inside other forms")
  (l.assertEquals (v "`[:a :b :c]") "[\"a\" \"b\" \"c\"]"
                  "quoted sequential table")
  (local viewed (v "`{:a 5 :b 9}"))
  (l.assertTrue (or (= viewed "{:a 5 :b 9}") (= viewed "{:b 9 :a 5}"))
                (.. "quoted keyed table: " viewed)))

(fn test-quoted-source []
  (c "\n\n(eval-compiler (set _G.source-line (. `abc :line)))")
  (l.assertEquals (. _G "source-line") 3 "syms have source data")
  (c "\n(eval-compiler (set _G.source-line (. `abc# :line)))")
  (l.assertEquals (. _G "source-line") 2 "autogensyms have source data")
  (c "\n\n\n(eval-compiler (set _G.source-line (. `(abc) :line)))")
  (l.assertEquals (. _G "source-line") 4 "lists have source data")
  (local (_ msg) (pcall c "\n\n\n\n(macro abc [] `(fn [... a#] 1)) (abc)"))
  (l.assertStrContains msg "unknown:5" "quoted tables have source data"))

(macro not-equal-gensym []
  (let [s (gensym :sym)]
    `(let [,s 10 sym# 20] (and sym# (not= ,s sym#)))))

(fn test-autogensym []
  (l.assertTrue (not-equal-gensym)))

{: test-quote
 : test-quoted-source
 : test-autogensym}
