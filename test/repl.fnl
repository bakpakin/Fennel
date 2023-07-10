(local t (require :test.faith))
(local fennel (require :fennel))
(local specials (require :fennel.specials))

;; allow inputs to be structured as a form but converted to a string
(macro v [form] (view form))

(fn wrap-repl [options]
  (var repl-complete nil)
  (fn send []
    (let [output []
          opts (collect [k x (pairs (or options {})) :into {:useMetadata true}]
                 (values k x))]
      (fn opts.readChunk []
        (while (= "" (. output 1))
          (table.remove output 1))
        (let [chunk (coroutine.yield (table.concat output "\n"))]
          (while (. output 1) (table.remove output))
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

(fn assert-equal-unordered [a b ...]
  (t.= (table.sort a) (table.sort b) (table.concat [...] " ")))

(fn test-sym-completion []
  (let [(send comp) (wrap-repl {:env (collect [k x (pairs _G)] (values k x))})]
    ;; if not deduped, causes a duplication error completing foo
    (send (v (global foo :DUPE)))
    (send (v (local [foo foo-ba* moe-larry] [1 2 {:*curly* "Why soitenly"}])))
    (send (v (local [!x-y !x_y] [1 2])))
    (assert-equal-unordered (comp "foo") ["foo" "foo-ba*"]
                            "local completion works & accounts for mangling")
    (assert-equal-unordered (comp "moe-larry") ["moe-larry.*curly*"]
                            "completion traverses tables without mangling"
                            "keys when input is \"tbl-var.\"")
    (t.= "1\t2" (send (v (values !x-y !x_y)))
         "mangled locals do not collide")
    (assert-equal-unordered (comp "!x") ["!x_y" "!x-y"]
                            "completions on mangled locals do not collide")
    (send (v (local dynamic-index
                    (setmetatable {:a 1 :b 2} {:__index #($2:upper)}))))
    (assert-equal-unordered (comp "dynamic-index.")
                            [:dynamic-index.a :dynamic-index.b]
                            "completion doesn't error on table with a fn"
                            "on mt.__index")
    (send (v (global global-is-nil nil)))
    (send (v (tset _G :global-is-not-nil-unscoped :NOT-NIL)))
    (assert-equal-unordered (comp :global-is-n) [:global-is-nil
                                                 :global-not-nil-unscoped]
                            "completion includes repl-scoped nil globals"
                            "and unscoped non-nil globals")
    (send (v (local val-is-nil nil)))
    (send (v (lua "local val-is-nil-unscoped = nil")))
    (t.= (comp :val-is-ni) [:val-is-nil]
         "completion includes repl-scoped locals with nil values")
    (send (v (global shadowed-is-nil nil)))
    (send (v (local shadowed-nil nil)))
    (t.= (comp :shadowed-is-n) [:shadowed-is-nil]
         "completion includes repl-scoped shadowed variables only once")
    (t.is (pcall send ",complete ]")
          "shouldn't kill the repl on a parse error")))

(fn test-macro-completion []
  (let [(send comp) (wrap-repl {:scope (fennel.scope)})]
    (send (v (local mac {:incremented 9 :unsanitary 2})))
    (send (v (import-macros mac :test.macros)))
    (let [[c1 c2 c3] (doto (comp "mac.i") table.sort)]
      ;; local should be shadowed!
      (t.not= c1 "mac.incremented")
      (t.not= c2 "mac.incremented")
      (t.= nil c3))))

(fn test-method-completion []
  (let [(send comp) (wrap-repl)]
    (send (v (local ttt {:abc 12 :fff (fn [] :val) :inner {:foo #:f :fa #:f}})))
    (t.= (comp "ttt:f") ["ttt:fff"] "method completion works on fns")
    (assert-equal-unordered (comp "ttt.inner.f") ["ttt:foo" "ttt:fa"]
                            "method completion nests")
    (t.= (comp "ttt:ab") [] "no method completion on numbers")))

(fn test-help []
  (let [send (wrap-repl)
        help (send ",help")]
    (t.match "Show this message" help)
    (t.match "enter code to be evaluated" help)))

(fn test-exit []
  (let [send (wrap-repl)
        _ (send ",exit")
        (ok? msg) (pcall send ":more")]
    (t.is (not ok?))
    (t.= msg "cannot resume dead coroutine")))

(fn test-reload []
  (set package.loaded.dummy nil)
  (let [modules {:dummy {:dummy :first-load}}]
    (fn dummy-loader [module-name]
      (if (= :dummy module-name)
          #modules.dummy))
    (table.insert (or package.searchers package.loaders) dummy-loader)
    (let [dummy (require :dummy)
          dummy-first-contents dummy.dummy
          send (wrap-repl)]
      (t.= :first-load dummy-first-contents)
      (set modules.dummy {:dummy :reloaded})
      (send ",reload dummy")
      (table.remove (or package.searchers package.loaders))
      (t.= :reloaded dummy.dummy)
      (t.match "module 'lmao' not found" (send ",reload lmao")))))

(fn test-reload-macros []
  (let [send (wrap-repl)]
    (tset fennel.macro-loaded :test/macros {:inc #(error :lol)})
    (t.is (not (pcall fennel.eval "(import-macros m :test/macros) (m.inc 1)")))
    (send ",reload test/macros")
    (t.is (pcall fennel.eval
                         "(import-macros m :test/macros) (m.inc 1)"))
    (tset fennel.macro-loaded :test/macros nil)))

(fn test-reset []
  (let [send (wrap-repl)
        _ (send (v (local abc 123)))
        abc (send "abc")
        _ (send ",reset")
        abc2 (send "abc")]
    (t.= abc "123")
    (t.= abc2 "")))

(fn test-find []
  (let [send (wrap-repl)
        _ (send (v (local f (require :fennel))))
        result (send ",find f.view")
        err (send ",find f.viewwwww")]
    (t.is (or (string.match result "fennel.lua:[0-9]+$")
              ;; running tests from script
              (string.match result "fennel:[0-9]+$")
              ;; running tests from compiled binary
              (string.match result "src.launcher"))
          (.. "Expected to find f.view in fennel but got " result))
    (t.= "error: Unknown value" err)))

(fn test-compile []
  (let [send (wrap-repl)
        result (send ",compile (fn abc [] (+ 43 9))")
        f "local function abc()\n  return (43 + 9)\nend\nreturn abc"
        err (send ",compile (fn ]")]
    (t.= f result)
    (t.= "error: Couldn't parse input." err)))

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
    (t.= ["log-me"] logged)
    (send ",set-boo")
    (t.= "!!!" (send "boo"))
    (t.match "Set boo to" (send ",help"))))

(fn test-options []
  ;; ensure options.useBitLib propagates to repl
  (let [send (wrap-repl {:useBitLib true :onError (fn [e] (values :ERROR e))})
        bxor-result (send (v (bxor 0 0)))]
    (if _G.jit
      (t.= bxor-result :0)
      (t.match "error:.*attempt to index.*global 'bit'" bxor-result
               "--use-bit-lib should make bitops fail in non-luajit"))))

(fn test-apropos []
  (let [send (wrap-repl)]
    (let [res (send ",apropos table%.")]
      (each [_ k (ipairs ["table.concat" "table.insert" "table.remove"
                          "table.sort"])]
        (t.match k res)))
    (let [res (send ",apropos not-found")]
      (t.= res "" "apropos returns no results for unknown pattern")
      (t.= (doto (icollect [item (res:gmatch "[^%s]+")] item)
             (table.sort))
           []
           "apropos returns no results for unknown pattern"))
    (let [res (send ",apropos-doc function")]
      (t.match "partial" res "apropos returns matching doc patterns")
      (t.match "pick%-args" res "apropos returns matching doc patterns"))
    (let [res (send ",apropos-doc \"there's no way this could match\"")]
      (t.= res "" "apropos returns no results for unknown doc pattern"))))

(fn test-byteoffset []
  (let [send (wrap-repl)
        _ (send (v (macro b [x]
                     (view (doto (getmetatable x) (tset :__fennelview nil))))))
        _ (send (v (macro f [x] (assert-compile false :lol-no x))))
        out (send "(b [1])")
        out2 (send "(b [1])")]
    (t.= out out2 "lines and byte offsets should be stable")
    (t.match ":bytestart 5" out)
    (t.match ":byteend 7" out)
    (t.match "   %(f \027%[7m%[123%]\027%[0m%)" (send "   (f [123])"))))

(fn test-code []
  (let [(send comp) (wrap-repl)]
    (send (v (local {: foo} (require :test.mod.foo7))))
    ;; repro case for https://todo.sr.ht/~technomancy/fennel/85
    (t.= (send (v (foo))) :foo)
    (t.= (comp "fo") [:for :foo])))

(fn test-error-handling []
  (let [(send comp) (wrap-repl)]
    ;; we get the source in the error message
    (t.match "%(let \027" (send "(let a)"))
    ;; repeated errors still get it
    (t.match "%(let \027" (send "(let b)"))
    (set _G.dbg true)
    ;; repl commands don't mess it up
    (send ",complete l")
    (t.match "%(let \027" (send "(let c)"))
    ;; parser errors should be properly displayed, albeit without ^ at position
    (t.match "invalid character: @" (send "(print @)"))))

(fn test-locals-saving []
  (let [(send comp) (wrap-repl)]
    (send (v (local x-y 5)))
    (send (v (let [x-y 55] nil)))
    (send (v (fn abc [] nil)))
    (t.= (send (v x-y)) :5)
    (t.= (send (v (type abc))) "function"))
  (let [(send comp) (wrap-repl {:correlate true})]
    (send (v (local x 1)))
    (t.= (send "x") :1))
  ;; now let's try with an env
  (let [(send comp) (wrap-repl {:env {: debug}})]
    (send (v (local xyz 55)))
    (t.= (send "xyz") :55)))

(fn test-docstrings []
  (let [send (wrap-repl)]
    (tset fennel.macro-loaded :test.macros nil)
    (t.= (.. "(doto val ...)\n  Evaluate val and splice it into the first "
             "argument of subsequent forms.")
         (send ",doc doto")
         "docstrings for built-in macros")
    (t.= "(table.concat #<unknown-arguments>)\n  #<undocumented>"
         (send ",doc table.concat")
         "docstrings for built-in Lua functions")
    (t.= "foo.bar not found" (send ",doc foo.bar"))
    (t.= "(bork) not found" (send ",doc (bork)"))
    (send (v (fn ew [] "so \"gross\" \\\"I\\\" can't" 1)))
    (t.= "(ew)\n  so \"gross\" \\\"I\\\" can't"
         (send ",doc ew")
         "docstrings should be auto-escaped")
    (send (v (fn foo [a] :C 1)))
    (t.= "(foo a)\n  C"
         (send ",doc foo")
         "for named functions, doc shows name, args invocation, docstring")
    (send (v (fn foo! [[] {} {:x []} [{}]] 1)))
    (t.= "(foo! [] {} {:x []} [{}])\n  #<undocumented>"
         (send ",doc foo!")
         "empty tables in arglist printed as defined")
    (send (v (fn foo! [-kebab- {:x x}] 1)))
    (t.= "(foo! -kebab- {:x x})\n  #<undocumented>"
         (send ",doc foo!")
         "fn-name and args pretty-printing")
    (send (v (fn foo! [-kebab- [a b {: x} [x y]]] 1)))
    (t.= "(foo! -kebab- [a b {:x x} [x y]])\n  #<undocumented>"
         (send ",doc foo!")
         "fn-name and args deep pretty-printing 1")
    (send (v (fn foo! [-kebab- [a b {"a b c" a-b-c} [x y]]] 1)))
    (t.= "(foo! -kebab- [a b {\"a b c\" a-b-c} [x y]])\n  #<undocumented>"
         (send ",doc foo!")
         "fn-name and args deep pretty-printing 2")
    (send (v (fn foo! [-kebab- [a b {"a \"b\" c" a-b-c} [x y]]] 1)))
    (t.= "(foo! -kebab- [a b {\"a \\\"b\\\" c\" a-b-c} [x y]])
  #<undocumented>"
         (send " ,doc foo!")
         "fn-name and args deep pretty-printing 3")
    (send (v (fn foo! [-kebab- [a b {"a \"b \\\"c\\\" d\" e" a-b-c-d-e}
                                [x y]]] 1)))
    (t.= (.. "(foo! -kebab- [a b "
             "{\"a \\\"b \\\\\\\"c\\\\\\\" d\\\" e\" a-b-c-d-e} [x y]])"
             "\n  #<undocumented>")
         (send ",doc foo!")
         "fn-name and args deep pretty-printing 4")
    (send (v (fn ml [] "a
      multiline
      docstring" :result)))
    (t.= "(ml)\n  a\n        multiline\n        docstring"
         (send ",doc ml")
         "multiline docstrings work correctly")
    (t.= "(generate depth ?choice)\n  Generate a random piece of data."
         (send "(local fennel (require :fennel))
                (local {: generate}
                       (fennel.dofile \"test/generate.fnl\"
                                      {:useMetadata true}))
                ,doc generate")
         "docstrings from required module.")
    (send (v (macro abc [x y z] "this is a macro." :123)))
    (t.= "(abc x y z)\n  this is a macro."
         (send ",doc abc")
         "docstrings for user-defined macros")
    (send (v (macro ten [] "[ten]" 10)))
    (t.= "(ten)\n  [ten]"
         (send ",doc ten")
         "macro docstrings with brackets")
    (send (v (λ foo [] :D 1)))
    (t.= "(foo)\n  D"
         (send ",doc foo")
         ",doc fnname for named lambdas appear like named functions")
    (send (v (fn foo [...] {:fnl/arglist [a b c] :fnl/docstring "D"} 1)))
    (t.= "(foo a b c)\n  D"
         (send " ,doc foo")
         ",doc arglist should be taken from function metadata table")
    (send (v (fn foo [...] {:fnl/arglist [a b c]} 1)))
    (t.= "(foo a b c)\n  #<undocumented>"
         (send ",doc foo")
         ",doc arglist should be taken from function metadata table")
    (send (v (fn foo [...] {:fnl/docstring "D"} 1)))
    (t.= "(foo ...)\n  D"
         (send ",doc foo")
         ",doc arglist should be taken from function metadata table")
    (send (v (fn foo [...]
               {:fnl/arglist [([a]) ([a b])]
                :fnl/docstring "clojure-like multiarity arglist"} 1)))
    (t.= "(foo ([a]) ([a b]))\n  clojure-like multiarity arglist"
         (send ",doc foo")
         ",doc arglist should support lists")
    (send (v (macro boo [] '(fn foo [...] {:fnl/dostring "D"} 1))))
    (t.= "(fn foo [...] {:fnl/dostring \"D\"} 1)"
         (send "(macrodebug (boo) true)")
         "metadata table should be left as is if it contains invalid keys")
    (send (v (macro boo [] '(fn foo [...] {:fnl/arlist [a b c]} 1))))
    (t.= "(fn foo [...] {:fnl/arlist [a b c]} 1)"
         (send "(macrodebug (boo) true)")
         "metadata table should be left as is if it contains invalid keys")
    (send (v (fn foo! [...] {:fnl/arglist [[] {} {:x []} [{}]]} 1)))
    (t.= "(foo! [] {} {:x []} [{}])\n  #<undocumented>"
         (send ",doc foo!")
         "empty tables in arglist printed as defined in metadata table")
    (send (v (macro boo [] '(fn foo [...] [] 1))))
    (t.= "(fn foo [...] {} 1)"
         (send "(macrodebug (boo) true)")
         "non-metadata tables are not removed")
    (send (v (macro boo [] (let [mt [1 2 3]] '(fn foo [...] ,mt 1)))))
    (t.= "(fn foo [...] [1 2 3] 1)"
         (send "(macrodebug (boo) true)")
         "non-static non-metadata tables are not removed")
    (send (v (import-macros m :test.macros)))
    (t.= "(m.inc n)\n  Increments n by 1"
         (send ",doc m.inc")
         ",doc should work on macro tables")))

(fn test-no-undocumented []
  (let [send (wrap-repl)
        undocumented-ok? {:lua true "#" true
                          :set-forcibly! true
                          :reverse-it true}
        {: _SPECIALS} (specials.make-compiler-env)]
    (each [name (pairs _SPECIALS)]
      (when (not (. undocumented-ok? name))
        (let [docstring (send (: ",doc %s" :format name))]
          (t.= :string (type docstring))
          (t.not-match "undocumented" docstring
                       (.. "Missing docstring for " name)))))))

(fn test-custom-metadata []
  (let [send (wrap-repl)]
    (send (v (local {: view : metadata} (require :fennel))))
    (macro s [...] `(send (v (do ,...))))
    (t.= "\"some-data\""
         (s (fn foo [] {:foo :some-data} nil)
            (view (metadata:get foo :foo)))
         "expected ordinary string metadata to work")
    (t.= "[\"seq\"]"
         (s (fn bar [] {:bar [:seq]} nil)
            (view (metadata:get bar :bar)))
         "expected sequential table metadata to work")
    (t.= "{:table \"table\"}"
         (s (fn baz [] {:baz {:table :table}} nil)
            (view (metadata:get baz :baz)))
         "expected associative table metadata to work")
    (t.= "{:compound [\"seq\" {:table \"table\"}]}"
         (s (fn qux [] {:qux {:compound [:seq {:table :table}]}} nil)
            (view (metadata:get qux :qux)))
         "expected compound metadata to work")
    (t.= "[\"some-data\" \"docs\"]"
         (s (fn quux [] "docs" {:foo :some-data} nil)
            (view [(metadata:get quux :foo)
                   (metadata:get quux :fnl/docstring)]))
         "expected combined docstring and ordinary string metadata to work")
    (t.= "[\"x\" \"y\" \"z\"]"
         (s (λ a-lambda [x ...] {:fnl/arglist [x y z]} nil)
            (view (metadata:get a-lambda :fnl/arglist)))
         "expected lambda metadata literal to work")
    (t.= "[[\"x\" \"y\" \"z\"] \"docs\"]"
         (s (λ b-lambda [] "docs" {:fnl/arglist [x y z]} nil)
            (view [(metadata:get b-lambda :fnl/arglist)
                   (metadata:get b-lambda :fnl/docstring)]))
         "expected combined docstring and ordinary string metadata to work")
    (t.= "{:fnl/arglist [\"x\"]}"
         (s (fn whole [x] nil)
            (view (metadata:get whole)))
         "expected whole metadata table when no key is asked")))

(fn test-custom-metadata-failing []
  (let [send (wrap-repl)]
    (send (v (local {: view : metadata} (require :fennel))))
    (t.match "expected literal value in metadata table, got: \"foo\" %(fn "
             (send (v (fn foo [] {:foo (fn [] nil)} nil)))
             "lists are not allowed as metadata fields")
    (t.match "expected literal value in metadata table, got: \"foo\" %[%(fn "
             (send (v (fn foo [] {:foo [(fn [] nil)]} nil)))
             "nested lists are not allowed as metadata fields")
    (t.match "expected literal value in metadata table, got: \"foo\" {:foo "
             (send (v (fn foo [] {:foo {:foo [(fn [] nil)]}} nil)))
             "nested lists as values are not allowed as metadata fields")
    (t.match "expected literal value in metadata table, got: \"foo\" {%[%(fn "
             (send (v (fn foo [] {:foo {[(fn [] nil)] :foo}} nil)))
             "nested lists as values are not allowed as metadata fields")))

(fn test-long-string []
  (let [send (wrap-repl)
        long (fcollect [_ 1 8000 :into [":"]] "-")
        back (send (table.concat long))]
    (t.= 8000 (length back))))

(fn test-decorating-repl []
  ;; overriding REPL methods from within the REPL via decoration.
  (let [send (wrap-repl)]
    (send (v (let [readChunk ___repl___.readChunk]
               (fn ___repl___.readChunk [parser-state]
                 (string.format "(- %s)" (readChunk parser-state))))))
    (t.= (send (v (+ 1 2 3)))
         "-6" "expected the result to be negated by the new readChunk")
    (send (v (let [onValues ___repl___.onValues]
               (fn ___repl___.onValues [vals]
                 (onValues (icollect [_ v (ipairs vals)]
                             (.. "res: " v)))))))
    (t.= (send (v (+ 1 2 3 4)))
         "res: -10" "expected result to include \"res: \" preffix")
    (send (v (fn ___repl___.onError [errtype err lua-source] nil)))
    (t.= (send (v (error :foo))) "" "expected error to be ignored")))

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
     : test-find
     : test-compile
     : test-plugins
     : test-options
     : test-apropos
     : test-byteoffset
     : test-error-handling
     : test-code
     : test-locals-saving
     : test-docstrings
     : test-no-undocumented
     : test-custom-metadata
     : test-custom-metadata-failing
     : test-long-string
     : test-decorating-repl}
    {})
