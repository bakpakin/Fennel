(local t (require :test.faith))
(local fennel (require :fennel))
(local view (require :fennel.view))

(fn test-leak []
  (t.is (not (pcall fennel.eval "(->1 1 (+ 4))" {:allowedGlobals false}))
        "Expected require-macros not leak into next evaluation."))

(fn test-runtime-quote []
  (t.is (not (pcall fennel.eval "`(hey)" {:allowedGlobals false}))
        "Expected quoting lists to fail at runtime.")
  (t.is (not (pcall fennel.eval "`[hey]" {:allowedGlobals false}))
        "Expected quoting syms to fail at runtime."))

(fn test-global-mangling []
  (t.is (pcall fennel.eval "(.. hello-world :w)" {:env {:hello-world "hi"}})
                "Expected global mangling to work."))

(fn test-include []
  (tset package.preload :test.mod.quux nil)
  (let [stderr io.stderr
        ;; disable warnings because these are supposed to fall back
        _ (set io.stderr nil)
        expected "foo:FOO-1bar:BAR-2-BAZ-3"
        (ok out) (pcall fennel.dofile "test/mod/foo.fnl")
        (ok2 out2) (pcall fennel.dofile "test/mod/foo2.fnl"
                          {:requireAsInclude true})
        (ok3 out3) (pcall fennel.dofile "test/mod/foo3.fnl"
                          {:requireAsInclude true})
        (ok4 out4) (pcall fennel.dofile "test/mod/foo4.fnl")
        (ok5 out5) (pcall fennel.dofile "test/mod/foo5.fnl"
                          {:requireAsInclude true}
                          :test)
        (ok6 out6) (pcall fennel.dofile "test/mod/foo6.fnl"
                          {:requireAsInclude true}
                          :test)
        (ok6-2 out6-2) (pcall fennel.dofile "test/mod/foo6-2.fnl"
                              {:requireAsInclude true}
                              :test)]
    (t.is ok (: "Expected foo to run but it failed with error %s" :format (tostring out)))
    (t.is ok2 (: "Expected foo2 to run but it failed with error %s" :format (tostring out2)))
    (t.is ok3 (: "Expected foo3 to run but it failed with error %s" :format (tostring out3)))
    (t.is ok4 (: "Expected foo4 to run but it failed with error %s" :format (tostring out4)))
    (t.is ok5 (: "Expected foo5 to run but it failed with error %s" :format (tostring out5)))
    (t.is ok6 (: "Expected foo6 to run but it failed with error %s" :format (tostring out6)))
    (t.is ok6-2 (: "Expected foo6 to run but it failed with error %s" :format (tostring out6-2)))
    (t.= expected (and (= :table (type out)) out.result)
         (.. "Expected include to have result: " expected))
    (t.= [:FOO 1] out.quux
         "Expected include to expose upvalues into included modules")
    (t.= (view out) (view out2)
         "Expected requireAsInclude to behave the same as include")
    (t.= (view out) (view out3)
         "Expected requireAsInclude to behave the same as include when given an expression")
    (t.= (view out) (view out4)
         "Expected include to work when given an expression")
    (t.= (view out) (view out5)
         "Expected relative requireAsInclude to work when given a ...")
    (t.= (view out) (view out6)
         "Expected relative requireAsInclude to work with nested modules")
    (t.= (view out) (view out6-2)
         "Expected relative requireAsInclude to work with nested modules")
    (t.= nil _G.quux "Expected include to actually be local")
    (let [spliceOk (pcall fennel.dofile "test/mod/splice.fnl")]
      (t.is spliceOk "Expected splice to run")
      (t.= nil _G.q "Expected include to actually be local"))
    (set io.stderr stderr))
  (let [stderr io.stderr
        stderr-fail false
        _ (set io.stderr {:write #(do (set-forcibly! stderr-fail $2) nil)})
        code "(local (bar-ok bar) (pcall #(require :test.mod.bar)))
              (local baz (require :test.mod.baz))
              (local (quux-ok quux) (pcall #(require :test.mod.quuuuuuux)))
              [(when bar-ok bar) baz (when quux-ok quux)]"
        opts {:requireAsInclude true :skipInclude [:test.mod.bar :test.mod.quuuuuuux]}
        out (fennel.compile-string code opts)
        value (fennel.eval code opts)]
    (t.match "baz = require%(\"test.mod.baz\"%)" out)
    (t.match "bar = pcall" out)
    (t.match "quux = pcall" out)
    (t.not-match "baz = nil" out)
    (t.= stderr-fail false)
    (t.= value [[:BAR 2 :BAZ 3] [:BAZ 3] nil])
    (set io.stderr stderr)))

(fn test-env-iteration []
  (let [tbl []
        g {:hello-world "hi"
           :pairs (fn [t] (local mt (getmetatable t))
                    (if (and mt mt.__pairs)
                        (mt.__pairs t)
                        (pairs t)))
           :tbl tbl}
        e []]
    (set g._G g)
    (fennel.eval "(each [k (pairs _G)] (tset tbl k true))" {:env g})
    (t.is (. tbl "hello-world")
          "Expected wrapped _G to support env iteration.")
    (var k [])
    (fennel.eval "(global x-x 42)" {:env e})
    (fennel.eval "x-x" {:env e})
    (each [mangled (pairs e)]
      (set k mangled))
    (t.= (. e k) 42
         "Expected mangled globals to be kept across eval invocations.")))

(fn test-empty-values []
  (t.is (fennel.eval
                 "(let [a (values)
                        b (values (values))
                        (c d) (values)
                        e (if (values) (values))
                        f (while (values) (values))
                        [g] [(values)]
                        {: h} {:h (values)}]
                    (not (or a b c d e f g h)))")
                "empty (values) should resolve to nil")
  (t.= (fennel.eval "(select :# (values))") 0)
  (t.= (fennel.eval "(select :# (#(values)))") 0)
  (let [broken-code (fennel.compile "(local [x] (values)) (local {: y} (values))")]
    (t.is broken-code "code should compile")
    (t.error "attempt to call a string" broken-code "should fail at runtime")))

(fn test-short-circuit []
  (let [method-code "(var shorted? false)
              (fn set-shorted! [] (set shorted? true) {:f! (fn [])})
              (and false (: (set-shorted!) :f!))
              shorted?"
        comparator-code "(and false (< 1 (error :nein!) 3))"]
    (t.is (not (fennel.eval method-code)))
    (t.is (not (fennel.eval comparator-code)))))

(fn test-precedence []
  (let [bomb (setmetatable {} {:__add #(= $2 false)})]
    (t.is (fennel.eval "(+ x (<= 1 5 3))" {:env {:x bomb : _G}})
          "n-ary comparators should ignore operators precedence")))

(fn test-table []
  (let [code "{:transparent 0 :sky 0 :sun 1 :stem 2 :cloud 3 :star 3 :moon 3
 :cloud-2 4 :gray 4 :rain 5 :butterfly-body 6 :bee-body-1 6 :white 3
 :butterfly-eye 7 :bee-body-2 7 :dying-plant 7 8 8 9 9}"
        tbl (fennel.eval code)]
    (t.= (. tbl 8) 8)))

(fn test-multisyms []
  (t.is (pcall fennel.eval "(let [x {:0 #$1 :& #$1}] (x:0) (x:&) (x.0) (x.&))" {:allowedGlobals false})
        "Expected to be able to use multisyms with digits and & in their second part"))

(fn test-strings []
  ;; need bs var in order to test effectively while testing on escape issues
  ;; that may be broken in the self-hosetd fennel verfsion
  (let [bs (string.char 92)] ; backslash
    (macro compile-string [...]
      `(-> (fennel.compile-string ,...)
           (: :gsub "^return " "")
           (: :gsub "^\"([^\"]+)\"$" "%1")))
    (t.= "\\r\\n" (compile-string "\"\r\n\"")
         "expected compiling newlines to preserve backslash")
    (t.= (.. bs "127") (compile-string (.. "\"" bs "127\""))
         (.. "expected " bs "<digit> to output the byte for 3-digit escapes"))
    (t.= (.. bs bs "12") (compile-string (.. "\"" bs bs "12\""))
         (.. "expected even # of " bs "'s not to escape what follows"))))

{: test-empty-values
 : test-env-iteration
 : test-global-mangling
 : test-include
 : test-leak
 : test-table
 : test-runtime-quote
 : test-short-circuit
 : test-precedence
 : test-multisyms
 : test-strings}
