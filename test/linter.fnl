(local l (require :test.luaunit))
(local fennel (require :fennel))
(local linter (fennel.dofile "src/linter.fnl" {:env :_COMPILER}))

(fn test-used []
  "A test for the locals shadowing bug described in
https://todo.sr.ht/~technomancy/fennel/12"
  (let [src "(fn [abc] (let [abc abc] abc))"
        (ok? msg) (pcall fennel.compile-string src {:plugins [linter]})]
    (l.assertTrue ok? msg)))

{: test-used}
