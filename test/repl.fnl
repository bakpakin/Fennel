(local l (require :luaunit))
(local fennel (require :fennel))
(local specials (require :fennel.specials))

;; TODO: stop using code in strings here

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
        (when (not= :function (type (. x 1)))
          (table.insert output (table.concat x "\t"))))
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

(fn test-sym-completion []
  (let [(send comp) (wrap-repl {:env (collect [k v (pairs _G)] (values k v))})]
    ;; if not deduped, causes a duplication error completing foo
    (send "(global foo :DUPE)")
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
    (send "(global global-is-nil nil) (tset _G :global-is-not-nil-unscoped :NOT-NIL)")
    (assert-equal-unordered (comp :global-is-n) [:global-is-nil :global-not-nil-unscoped]
                            "completion includes repl-scoped nil globals & unscoped non-nil globals")
    (send "(local val-is-nil nil) (lua \"local val-is-nil-unscoped = nil\")")
    (l.assertEquals (comp :val-is-ni) [:val-is-nil]
                    "completion includes repl-scoped locals with nil values")
    (send "(global shadowed-is-nil nil) (local shadowed-nil nil)")
    (l.assertEquals (comp :shadowed-is-n) [:shadowed-is-nil]
                    "completion includes repl-scoped shadowed variables only once")
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
    (l.assertEquals :reloaded dummy.dummy)
    (l.assertStrContains (. (send ",reload lmao") 1)
                         "module 'lmao' not found")))

(fn test-reload-macros []
  (let [send (wrap-repl)]
    (tset fennel.macro-loaded :test/macros {:inc #(error :lol)})
    (l.assertFalse (pcall fennel.eval
                          "(import-macros m :test/macros) (m.inc 1)"))
    (send ",reload test/macros")
    (l.assertTrue (pcall fennel.eval
                         "(import-macros m :test/macros) (m.inc 1)"))
    (tset fennel.macro-loaded :test/macros nil)))

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
        plugin1 {:repl-command-log #(table.insert logged (select 2 ($2)))
                 :versions [(fennel.version:gsub "-dev" "")]}
        plugin2 {:repl-command-log #(error "p1 should handle this!")
                 :repl-command-set-boo set-boo
                 :versions [(fennel.version:gsub "-dev" "")]}
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

(fn test-code []
  (let [(send comp) (wrap-repl)]
    (send "(local {: foo} (require :test.mod.foo7))")
    ;; repro case for https://todo.sr.ht/~technomancy/fennel/85
    (l.assertEquals (send "(foo)") [:foo])
    (l.assertEquals (comp "fo") [:for :foo])))

(fn test-source-offset []
  (let [(send comp) (wrap-repl)]
    ;; we get the source in the error message
    (l.assertStrContains (. (send "(let a)") 1) "(let a)\n     ^")
    ;; repeated errors still get it
    (l.assertStrContains (. (send "(let b)") 1) "(let b)\n     ^")
    (set _G.dbg true)
    ;; repl commands don't mess it up
    (send ",complete l")
    (l.assertStrContains (. (send "(let c)") 1) "(let c)\n     ^")))

(fn test-locals-saving []
  (let [(send comp) (wrap-repl)]
    (send "(local x-y 5)")
    (send "(let [x-y 55] nil)")
    (send "(fn abc [] nil)")
    (l.assertEquals (send "x-y") [:5])
    (l.assertEquals (send "(type abc)") ["function"]))
  ;; now let's try with an env
  (let [(send comp) (wrap-repl {:env {: debug}})]
    (send "(local xyz 55)")
    (l.assertEquals (send "xyz") [:55])))

(local doc-cases
       [[",doc doto" "(doto val ...)\n  Evaluate val and splice it into the first argument of subsequent forms." "docstrings for built-in macros" ]
        [",doc table.concat"  "(table.concat #<unknown-arguments>)\n  #<undocumented>" "docstrings for built-in Lua functions" ]
        [",doc foo.bar" "error: Could not resolve value for docstring lookup"]
        [",doc (bork)" "error: Could not resolve value for docstring lookup"]
        ;; ["(fn ew [] \"so \\\"gross\\\" \\\\\\\"I\\\\\\\" can't even\" 1) ,doc ew"  "(ew)\n  so \"gross\" \\\"I\\\" can't even" "docstrings should be auto-escaped" ]
        ["(fn foo [a] :C 1) ,doc foo"  "(foo a)\n  C" "for named functions, doc shows name, args invocation, docstring" ]
        ["(fn foo! [-kebab- {:x x}] 1) ,doc foo!"  "(foo! -kebab- {:x x})\n  #<undocumented>" "fn-name and args pretty-printing" ]
        ["(fn foo! [-kebab- [a b {: x} [x y]]] 1) ,doc foo!"  "(foo! -kebab- [a b {:x x} [x y]])\n  #<undocumented>" "fn-name and args deep pretty-printing" ]
        ["(fn foo! [-kebab- [a b {\"a b c\" a-b-c} [x y]]] 1) ,doc foo!"  "(foo! -kebab- [a b {\"a b c\" a-b-c} [x y]])\n  #<undocumented>" "fn-name and args deep pretty-printing" ]
        ["(fn foo! [-kebab- [a b {\"a \\\"b\\\" c\" a-b-c} [x y]]] 1) ,doc foo!"  "(foo! -kebab- [a b {\"a \\\"b\\\" c\" a-b-c} [x y]])\n  #<undocumented>" "fn-name and args deep pretty-printing" ]
        ["(fn foo! [-kebab- [a b {\"a \\\"b \\\\\\\"c\\\\\\\" d\\\" e\" a-b-c-d-e} [x y]]] 1) ,doc foo!"  "(foo! -kebab- [a b {\"a \\\"b \\\\\"c\\\\\" d\\\" e\" a-b-c-d-e} [x y]])\n  #<undocumented>" "fn-name and args deep pretty-printing" ]
        ["(fn ml [] \"a\nmultiline\ndocstring\" :result) ,doc ml"  "(ml)\n  a\n  multiline\n  docstring" "multiline docstrings work correctly" ]
        ["(local fennel (require :fennel)) (local {: generate} (fennel.dofile \"test/generate.fnl\" {:useMetadata true})) ,doc generate"  "(generate depth ?choice)\n  Generate a random piece of data." "docstrings from required module." ]
        ["(macro abc [x y z] \"this is a macro.\" :123) ,doc abc"  "(abc x y z)\n  this is a macro." "docstrings for user-defined macros" ]
        ["(macro ten [] \"[ten]\" 10) ,doc ten" "(ten)\n  [ten]" "macro docstrings with brackets"]
        ["(λ foo [] :D 1) ,doc foo"  "(foo)\n  D" ",doc fnname for named lambdas appear like named functions" ]
        ["(fn foo [...] {:fnl/arglist [a b c] :fnl/docstring \"D\"} 1) ,doc foo"  "(foo a b c)\n  D" ",doc arglist should be taken from function metadata table" ]])

(fn test-docstrings []
  (let [send (wrap-repl)]
    (each [_ [code expected msg] (ipairs doc-cases)]
      (l.assertEquals (table.concat (send code)) expected msg))))

(fn test-no-undocumented []
  (let [send (wrap-repl)
        undocumented-ok? {:lua true "#" true :set-forcibly! true}
        {: _SPECIALS} (specials.make-compiler-env)]
    (each [name (pairs _SPECIALS)]
      (when (not (. undocumented-ok? name))
        (let [[docstring] (send (: ",doc %s" :format name))]
          (l.assertString docstring)
          (l.assertNil (docstring:find "undocumented")
                       (.. "Missing docstring for " name)))))))

;; Skip REPL tests in non-JIT Lua 5.1 only to avoid engine coroutine
;; limitation. Normally we want all tests to run on all versions, but in
;; this case the feature will work fine; we just can't use this method of
;; testing it on PUC 5.1, so skip it.
(if (or (not= _VERSION "Lua 5.1") (= (type _G.jit) "table"))
    {: test-sym-completion
     : test-macro-completion
     : test-method-completion
     : test-help
     : test-exit
     : test-reload
     : test-reload-macros
     : test-reset
     : test-plugins
     : test-options
     : test-apropos
     : test-byteoffset
     : test-source-offset
     : test-code
     : test-locals-saving
     : test-docstrings
     : test-no-undocumented}
    {})
