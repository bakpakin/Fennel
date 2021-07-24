(local l (require :test.luaunit))
(local fennel (require :fennel))
(local view (require :fennel.view))

(fn test-traceback []
  (let [tracer (fennel.dofile "test/mod/tracer.fnl")
        traceback (tracer)]
    (l.assertStrContains traceback "tracer.fnl:4:")
    (l.assertStrContains traceback "tracer.fnl:9:")))

(fn test-leak []
  (l.assertFalse (pcall fennel.eval "(->1 1 (+ 4))" {:allowedGlobals false})
                 "Expected require-macros not leak into next evaluation."))

(fn test-runtime-quote []
  (l.assertFalse (pcall fennel.eval "`(hey)" {:allowedGlobals false})
                 "Expected quoting lists to fail at runtime.")
  (l.assertFalse (pcall fennel.eval "`[hey]" {:allowedGlobals false})
                 "Expected quoting syms to fail at runtime."))

(fn test-global-mangling []
  (l.assertTrue (pcall fennel.eval "(.. hello-world :w)" {:env {:hello-world "hi"}})
                "Expected global mangling to work."))

(fn test-include []
  (let [expected "foo:FOO-1bar:BAR-2-BAZ-3"
        (ok out) (pcall fennel.dofile "test/mod/foo.fnl")
        (ok2 out2) (pcall fennel.dofile "test/mod/foo2.fnl"
                          {:requireAsInclude true})]
    (l.assertTrue ok "Expected foo to run")
    (l.assertTrue ok2 "Expected foo2 to run")
    (l.assertEquals (and (= :table (type out)) out.result) expected
                    (.. "Expected include to have result: " expected))
    (l.assertFalse out.quux
                   "Expected include not to leak upvalues into included modules")
    (l.assertEquals (view out) (view out2)
                    "Expected requireAsInclude to behave the same as include")
    (l.assertNil _G.quux "Expected include to actually be local")
    (let [spliceOk (pcall fennel.dofile "test/mod/splice.fnl")]
      (l.assertTrue spliceOk "Expected splice to run")
      (l.assertNil _G.q "Expected include to actually be local")))
  (let [code "(local bar (require :test.mod.bar))
              (local baz (require :test.mod.baz))
              (local quux (require :test.mod.quux))
              [bar baz quux]"
        opts {:requireAsInclude true :skipInclude [:test.mod.bar :test.mod.quux]}
        out (fennel.compile-string code opts)
        value (fennel.eval code opts)]
    (l.assertStrContains out "bar = nil")
    (l.assertNotStrContains out "baz = nil")
    (l.assertStrContains out "quux = nil")
    (l.assertNotStrContains out "test.mod.bar")
    (l.assertNotStrContains out "test.mod.quux")
    (l.assertEquals [nil [:BAZ 3] nil] value)))

(fn test-env-iteration []
  (local tbl [])
  (local g {:hello-world "hi"
            :pairs (fn [t] (local mt (getmetatable t))
                     (if (and mt mt.__pairs)
                         (mt.__pairs t)
                         (pairs t)))
            :tbl tbl})
  (set g._G g)
  (fennel.eval "(each [k (pairs _G)] (tset tbl k true))" {:env g})
  (l.assertTrue (. tbl "hello-world")
                "Expected wrapped _G to support env iteration.")
  (var (e k) [])
  (fennel.eval "(global x-x 42)" {:env e})
  (fennel.eval "x-x" {:env e})
  (each [mangled (pairs e)]
    (set k mangled))
  (l.assertEquals (. e k) 42
                  "Expected mangled globals to be kept across eval invocations."))

(fn test-empty-values []
  (l.assertTrue (fennel.eval
                 "(let [a (values)
                        b (values (values))
                        (c d) (values)
                        e (if (values) (values))
                        f (while (values) (values))
                        [g] [(values)]
                        {: h} {:h (values)}]
                    (not (or a b c d e f g h)))")
                "empty (values) should resolve to nil")
  (let [broken-code (fennel.compile "(local [x] (values)) (local {: y} (values))")]
    (l.assertNotNil broken-code "code should compile")
    (l.assertError broken-code "code should fail at runtime")))

(fn test-short-circuit []
  (let [method-code "(var shorted? false)
              (fn set-shorted! [] (set shorted? true) {:f! (fn [])})
              (and false (: (set-shorted!) :f!))
              shorted?"
        comparator-code "(and false (< 1 (error :nein!) 3))"]
    (l.assertFalse (fennel.eval method-code))
    (l.assertFalse (fennel.eval comparator-code))))

{: test-empty-values
 : test-env-iteration
 : test-global-mangling
 : test-include
 : test-leak
 : test-runtime-quote
 : test-traceback
 : test-short-circuit}
