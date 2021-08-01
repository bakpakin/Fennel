(local l (require :test.luaunit))
(local fennel (require :fennel))
(local linter (fennel.dofile "src/linter.fnl" {:env :_COMPILER}))
(local options {:plugins [linter] :compilerEnv :strict})

(fn test-used []
  "A test for the locals shadowing bug described in
https://todo.sr.ht/~technomancy/fennel/12"
  (let [src "(fn [abc] (let [abc abc] abc))"
        (ok? msg) (pcall fennel.compile-string src options)]
    (l.assertTrue ok? msg)))

(fn test-arity-check []
  (let [src "(let [s (require :test.mod.splice)] (s.myfn 1))"
        ok? (pcall fennel.compile-string src options)]
    (l.assertFalse ok?)))

(fn test-missing-fn []
  (let [src "(let [s (require :test.mod.splice)] (s.missing-fn))"
        ok? (pcall fennel.compile-string src options)]
    (l.assertFalse ok?)))

{: test-used
 : test-arity-check
 : test-missing-fn}
