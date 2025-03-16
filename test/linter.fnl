(local t (require :test.faith))
(local fennel (require :fennel))
(local linter (fennel.dofile "src/linter.fnl" {:env :_COMPILER :compilerEnv _G}))
(local options {:plugins [linter]})

(fn test-used []
  "A test for the locals shadowing bug described in
https://todo.sr.ht/~technomancy/fennel/12"
  (let [src "(fn [abc] (let [abc abc] abc))"
        (ok? msg) (pcall fennel.compile-string src options)]
    (t.is ok? msg)))

(fn test-arity-check []
  (let [src "(let [s (require :test.mod.splice)] (s.myfn 1))"
        ok? (pcall fennel.compile-string src options)]
    (when (not= _VERSION "Lua 5.1") ; debug.getinfo nparams was added in 5.2
      (t.is (not ok?)))))

(fn test-missing-fn []
  (let [src "(let [s (require :test.mod.splice)] (s.missing-fn))"
        ok? (pcall fennel.compile-string src options)]
    (t.is (not ok?))))

(fn test-var-never-set []
  (t.is (not (pcall fennel.compile-string "(var x 1) (+ x 9)" options)))
  (t.is (pcall fennel.compile-string "(var x 1) (set x 9)" options)))

(fn teardown []
  (let [utils (require :fennel.utils)]
    (set utils.root.options.plugins {})))

{: test-used
 : test-arity-check
 : test-missing-fn
 : test-var-never-set
 : teardown}
