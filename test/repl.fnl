(local l (require :test.luaunit))
(local fennel (require :fennel))

(fn wrap-repl [options]
  (var repl-complete nil)
  (fn send []
    (var output [])
    (let [opts (or options {})]
      (fn opts.readChunk []
        (let [chunk (coroutine.yield output)]
          (set output [])
          (and chunk (.. chunk "\n"))))
      (fn opts.onValues [x]
        (table.insert output (table.concat x "\t")))
      (fn opts.registerCompleter [x]
        (set repl-complete x))
      (fn opts.pp [x] x)
      (fennel.repl opts)))
  (let [repl-send (coroutine.wrap send)]
    (repl-send)
    (values repl-send repl-complete)))

(fn assert-equal-unordered [a b msg]
  (l.assertEquals (table.sort a) (table.sort b) msg))

(fn test-completion []
  (let [(send comp) (wrap-repl)]
    (send "(local [foo foo-ba* moe-larry] [1 2 {:*curly* \"Why soitenly\"}])")
    (send "(local [!x-y !x_y] [1 2])")
    (assert-equal-unordered (comp "foo") ["foo" "foo-ba*"]
                            "local completion works & accounts for mangling")
    (assert-equal-unordered (comp "moe-larry") ["moe-larry.*curly*"]
                            (.. "completion traverses tables without mangling"
                                " keys when input is \"tbl-var.\""))
    (assert-equal-unordered (send "(values !x-y !x_y)") [[1 2]]
                            "mangled locals do not collide")
    (assert-equal-unordered (comp "!x") ["!x_y" "!x-y"]
                            "completions on mangled locals do not collide")))

(fn test-help []
  (let [send (wrap-repl)
        help (table.concat (send ",help"))]
    (l.assertStrContains help "Show this message")
    (l.assertStrContains help "enter code to be evaluated")))

(fn test-exit []
  (let [send (wrap-repl)
        _ (send ",exit")
        (ok? msg) (pcall send ":more")]
    (l.assertFalse ok?)
    (l.assertEquals msg "cannot resume dead coroutine")))

(var dummy-module nil)

(fn dummy-loader [module-name]
  (if (= :dummy module-name)
      #dummy-module))

(fn test-reload []
  (set dummy-module {:dummy :first-load})
  (table.insert (or package.searchers package.loaders) dummy-loader)
  (let [dummy (require :dummy)
        dummy-first-contents dummy.dummy
        send (wrap-repl)]
    (set dummy-module {:dummy :reloaded})
    (send ",reload dummy")
    (l.assertEquals :first-load dummy-first-contents)
    (l.assertEquals :reloaded dummy.dummy)))

(fn test-reset []
  (let [send (wrap-repl)
        _ (send "(local abc 123)")
        abc (table.concat (send "abc"))
        _ (send ",reset")
        abc2 (table.concat (send "abc"))]
    (l.assertEquals abc "123")
    (l.assertEquals abc2 "")))

(fn set-boo [env]
  "Set boo to exclaimation points."
  (tset env :boo "!!!"))

(fn test-plugins []
  (let [logged []
        plugin1 {:repl-command-log #(table.insert logged (select 2 ($2)))}
        plugin2 {:repl-command-log #(error "p1 should handle this!")
                 :repl-command-set-boo set-boo}
        send (wrap-repl {:plugins [plugin1 plugin2]})]
    (send ",log :log-me")
    (l.assertEquals logged ["log-me"])
    (send ",set-boo")
    (l.assertEquals (send "boo") ["!!!"])
    (l.assertStrContains (table.concat (send ",help")) "Set boo to")))

;; Skip REPL tests in non-JIT Lua 5.1 only to avoid engine coroutine
;; limitation. Normally we want all tests to run on all versions, but in
;; this case the feature will work fine; we just can't use this method of
;; testing it on PUC 5.1, so skip it.
(if (or (not= _VERSION "Lua 5.1") (= (type _G.jit) "table"))
    {: test-completion
     : test-help
     : test-exit
     : test-reload
     : test-reset
     : test-plugins}
    {})
