(local t (require :test.faith))
(local fennel (require :fennel))
(local view (require :fennel.view))

(macro v [expr] (view expr))
(macro peval [expr ?opts]
  `(pcall fennel.eval (v ,expr) ,?opts))

(fn c [code]
  (fennel.compileString code {:allowedGlobals false :compiler-env _G}))

(fn cv [code]
  (view ((fennel.loadCode (c code) (let [env {:sequence fennel.sequence}]
                                     (set env._G env)
                                     (setmetatable env {:__index _G}))))
        {:one-line? true}))

(fn test-quote []
  (t.= (c "`:abcde") "return \"abcde\"" "simple string quoting")
  (t.= (cv "`[1 2 ,(+ 1 2) 4]") "[1 2 3 4]"
                  "unquote inside quote leads to evaluation")
  (t.= (cv "(let [a (+ 2 3)] `[:hey ,(+ a a)])") "[\"hey\" 10]"
                  "unquote inside other forms")
  (t.= (cv "`[:a :b :c]") "[\"a\" \"b\" \"c\"]"
                  "quoted sequential table")
  (local viewed (cv "`{:a 5 :b 9}"))
  (t.is (or (= viewed "{:a 5 :b 9}") (= viewed "{:b 9 :a 5}"))
                (.. "quoted keyed table: " viewed))


  ;; make sure shadowing the macro env in a macro body doesn't break anything
  (let [shadow-scope (fennel.scope)
        _ (fennel.compile-string
            (v (macro shadow-macro [name args ...]
                 (let [g (. (getmetatable _G) :__index)
                       shadow-bind []]
                   (each [k (pairs _G)]
                     (when (and (= :string (type k)) (not= k :_G) (= nil (. g k))
                                ;; `comment` shadows a special form
                                (not= :comment k))
                       (table.insert shadow-bind (sym k))
                       (table.insert shadow-bind true)))
                   `(macro ,name ,args (let ,shadow-bind ,...)))))
            {:scope shadow-scope})
        (ok res) (peval (do (shadow-macro m [v] `(do ,v))
                            (shadow-macro n [v] `[,v])
                            (shadow-macro o [v] `(let [x# ,v] x#))
                            [(m :a) (n :b) (o :c)])
                        {:scope (fennel.scope shadow-scope)})]
    (t.is ok (: "shadowing the compiler env in a macro doesn't break quoting\n%s"
                :format (tostring res)))
    (t.= [:a [:b] :c] res
         "shadowing the compiler env in a macro doesn't break quoting")))

(fn test-quoted-source []
  (t.= "return 3" (c "\n\n(eval-compiler (. `abc :line))")
       "syms have source data")
  (t.= "return 2" (c "\n(eval-compiler (. `abc# :line))")
       "autogensyms have source data")
  (t.= "return 4" (c "\n\n\n(eval-compiler (. `(abc) :line))")
       "lists have source data")
  (let [(_ msg) (pcall c "\n\n\n\n(macro abc [] `(fn [... a#] 1)) (abc)")]
    (t.match "unknown:5" msg "quoted tables have source data"))
  ;; runtime quoting
  (t.= "return {\"foo\", \"x\", table.unpack({1, 2, 3}), \"y\"}"
       (c "`[:foo :x ,(table.unpack [1 2 3]) :y]")))

(macro not-equal-gensym []
  (let [s (gensym :sym)]
    `(let [,s 10 sym# 20] (and sym# (not= ,s sym#)))))

(fn test-autogensym []
  (t.is (not-equal-gensym)))

{: test-quote
 : test-quoted-source
 : test-autogensym}
