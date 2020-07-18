(local l (require :test.luaunit))

(local fennel (require :fennel))

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
  (let [expected "foo:FOO-1bar:BAR-2-BAZ-3"]
    (var (ok out) (pcall fennel.dofile "test/mod/foo.fnl"))
    (l.assertTrue ok "Expected foo to run")
    (set out (or out []))
    (l.assertEquals out.result expected
                    (.. "Expected include to have result: " expected))
    (l.assertFalse out.quux
                   "Expected include not to leak upvalues into included modules")
    (l.assertNil _G.quux "Expected include to actually be local")
    (let [spliceOk (pcall fennel.dofile "test/mod/splice.fnl")]
      (l.assertTrue spliceOk "Expected splice to run")
      (l.assertNil _G.q "Expected include to actually be local"))))

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

{: test-empty-values
 : test-env-iteration
 : test-global-mangling
 : test-include
 : test-leak
 : test-runtime-quote}

