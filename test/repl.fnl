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
      (fn opts.onError [e-type e lua-src]
        (table.insert output (.. "error: " e)))
      (fn opts.registerCompleter [x]
        (set repl-complete x))
      (fn opts.pp [x] x)
      (fennel.repl opts)))
  (let [repl-send (coroutine.wrap send)]
    (repl-send)
    (values repl-send repl-complete)))

(fn assert-equal-unordered [a b msg]
  (l.assertEquals (table.sort a) (table.sort b) msg))

(fn test-local-completion []
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
                            "completions on mangled locals do not collide")
    (send "(local dynamic-index (setmetatable {:a 1 :b 2} {:__index #($2:upper)}))")
    (assert-equal-unordered (comp "dynamic-index.") [:dynamic-index.a :dynamic-index.b]
                            "completion doesn't error on table with a fn on mt.__index")
    (let [(ok msg) (pcall send ",complete ]")]
      (l.assertTrue ok "shouldn't kill the repl on a parse error"))))

(fn test-macro-completion []
  (let [(send comp) (wrap-repl)]
    (send "(local mac {:incremented 9 :unsanitary 2})")
    (send "(import-macros mac :test.macros)")
    (let [[c1 c2 c3] (doto (comp "mac.i") table.sort)]
      ;; local should be shadowed!
      (l.assertNotEquals c1 "mac.incremented")
      (l.assertNotEquals c2 "mac.incremented")
      (l.assertNil c3))))

(fn test-method-completion []
  (let [(send comp) (wrap-repl)]
    (send "(local ttt {:abc 12 :fff (fn [] :val) :inner {:foo #:f :fa #:f}})")
    (l.assertEquals (comp "ttt:f") ["ttt:fff"] "method completion works on fns")
    (assert-equal-unordered (comp "ttt.inner.f") ["ttt:foo" "ttt:fa"]
                            "method completion nests")
    (l.assertEquals (comp "ttt:ab") [] "no method completion on numbers")))

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
        send (wrap-repl {:plugins [plugin1 plugin2] :allowedGlobals false})]
    (send ",log :log-me")
    (l.assertEquals logged ["log-me"])
    (send ",set-boo")
    (l.assertEquals (send "boo") ["!!!"])
    (l.assertStrContains (table.concat (send ",help")) "Set boo to")))

(fn test-options []
  ;; ensure options.useBitLib propagates to repl
  (let [send (wrap-repl {:useBitLib true :onError (fn [e] (values :ERROR e))})
        bxor-result (send "(bxor 0 0)")]
    (if _G.jit
      (l.assertEquals bxor-result [:0])
      (l.assertStrContains (. bxor-result 1) "error:.*attempt to index.*global 'bit'"
                           "--use-bit-lib should make bitops fail in non-luajit"))))

(fn test-apropos []
  (local send (wrap-repl))
  (let [res (. (send ",apropos table%.") 1)]
    (each [_ k (ipairs ["table.concat" "table.insert" "table.remove"
                        "table.sort"])]
      (l.assertStrContains res k)))
  (let [res (. (send ",apropos not-found") 1)]
    (l.assertEquals res "" "apropos returns no results for unknown pattern")
    (l.assertEquals
     (doto (icollect [item (res:gmatch "[^%s]+")] item)
       (table.sort))
     []
     "apropos returns no results for unknown pattern"))
  (let [res (. (send ",apropos-doc function") 1)]
    (l.assertStrContains res "partial" "apropos returns matching doc patterns")
    (l.assertStrContains res "pick%-args" "apropos returns matching doc patterns"))
  (let [res (. (send ",apropos-doc \"there's no way this could match\"") 1)]
    (l.assertEquals res "" "apropos returns no results for unknown doc pattern")))

(fn test-byteoffset []
  (let [send (wrap-repl)
        _ (send "(macro b [x] (view (getmetatable x)))")
        _ (send "(macro f [x] (assert-compile false :lol-no x))")
        out (table.concat (send "(b [1])"))
        out2 (table.concat (send "(b [1])"))
        out3 (table.concat (send "   (f [123])"))]
    (l.assertEquals out out2 "lines and byte offsets should be stable")
    (l.assertStrContains out ":bytestart 5")
    (l.assertStrContains out ":byteend 7")
    (l.assertStrContains out3 "   (f [123])\n      ^^^^^")))

;; Skip REPL tests in non-JIT Lua 5.1 only to avoid engine coroutine
;; limitation. Normally we want all tests to run on all versions, but in
;; this case the feature will work fine; we just can't use this method of
;; testing it on PUC 5.1, so skip it.
(if (or (not= _VERSION "Lua 5.1") (= (type _G.jit) "table"))
    {: test-local-completion
     : test-macro-completion
     : test-method-completion
     : test-help
     : test-exit
     : test-reload
     : test-reset
     : test-plugins
     : test-options
     : test-apropos
     : test-byteoffset}
    {})
