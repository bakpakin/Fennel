(local l (require :test.luaunit))
(local fennel (require :fennel))

(fn test-failures [failures]
  (each [code expected-msg (pairs failures)]
    (let [(ok? msg) (pcall fennel.compileString code
                           {:allowedGlobals ["pairs" "next" "ipairs"]
                            :unfriendly true})]
      (l.assertFalse ok? (.. "Expected compiling " code " to fail."))
      (l.assertStrContains msg expected-msg))))

(fn test-global-fails []
  (test-failures
   {"(fn global [] 1)" "overshadowed"
    "(fn global-caller [] (hey))" "unknown global"
    "(global + 1)" "overshadowed"
    "(global - 1)" "overshadowed"
    "(global // 1)" "overshadowed"
    "(global 48 :forty-eight)" "unable to bind number 48"
    "(global good (fn [] nil)) (good) (BAD)" "BAD"
    "(global let 1)" "overshadowed"
    "(hey)" "unknown global"
    "(let [bl 8 a bcd] nil)" "unknown global"
    "(let [global 1] 1)" "overshadowed"
    "(local a-b 1) (global [a_b] [2])" "global a_b conflicts with local"
    "(local a-b 1) (global a_b 2)" "global a_b conflicts with local"
    "((fn [] (require-macros \"test.macros\") (global x1 (->1 99 (+ 31)))))
      (->1 23 (+ 1))" "unknown global in strict mode"
    ;; strict mode applies to macro modules too
    "(import-macros t :test.bad.unknown-global)" "unknown global in strict mode"}))

(fn test-fn-fails []
  (test-failures
   {"(fn [12])" "expected symbol for function parameter"
    "(fn [:huh] 4)" "expected symbol for function parameter"
    "(fn []\n(for [32 34 32] 21))" "unknown:2:"
    "(fn [] [...])" "unexpected vararg"
    "(fn [false] 4)" "expected symbol for function parameter"
    "(fn [nil] 4)" "expected symbol for function parameter"
    "(fn)" "expected parameters"
    "(lambda x)" "expected arg list"
    "(fn abc:def [x] (+ x 2))" "unexpected multi symbol abc:def"
    "#[$ $...] 1 2 3" "$ and $... in hashfn are mutually exclusive"}))

(fn test-macro-fails []
  (test-failures
   {"(macros {:m (fn [t] `(each [mykey (pairs ,t)] (print mykey)))}) (m [])"
    "tried to bind mykey without gensym"
    "(macros {:m (fn [t] `(fn [xabc] (+ xabc 9)))}) ((m 4))"
    "tried to bind xabc without gensym"
    "(macros {:m (fn [y] `(let [x 1] (+ x ,y)))}) (m 4)"
    "tried to bind x without gensym"
    "(macros {:foo {:bar (fn [] `(print :test))}})"
    "expected each macro to be function"
    "(macro m [] (getmetatable :foo)) (m)"
    "Illegal metatable"
    "(import-macros test :test.macros) (test.asdf)"
    "macro not found in imported macro module"
    ;; macros should shadow locals as values, not just when calling:
    "(let [t {:b 2}] (import-macros t :test.macros) t.b)"
    "tried to reference a macro"
    "(import-macros {: asdf} :test.macros)"
    "macro asdf not found in module test.macros"}))

(fn test-binding-fails []
  (test-failures
   {"(let [:x 1] 1)" "unable to bind"
    "(let [[a & c d] [1 2]] c)" "rest argument before last parameter"
    "(let [b 9\nq (.)] q)" "unknown:2: Compile error in '.': expected table"
    "(let [false 1] 9)" "unable to bind boolean false"
    "(let [next #(next $)] print)" "aliased by a local"
    "(let [nil 1] 9)" "unable to bind"
    "(let [pairs #(pairs $)] pairs)" "aliased by a local"
    "(let [t []] (set t.:x :y))" "malformed multisym: t.:x"
    "(let [t []] (set t:.x :y))" "malformed multisym: t:.x"
    "(let [t []] (set t::x :y))" "malformed multisym: t::x"
    "(let [t {:a 1}] (+ t.a BAD))" "BAD"
    "(let [x 1 y] 8)" "expected even number of name/value bindings"
    "(let [x 1] (set-forcibly! x 2) (set x 3) x)" "expected var"
    "(let [x 1])" "expected body"
    "(local 47 :forty-seven)" "unable to bind number 47"
    "(local a~b 3)" "illegal character: ~"
    "(local ipairs #(ipairs $))" "aliased by a local"
    "(set [a b c] [1 2 3]) (+ a b c)" "expected local"
    "(set a 19)" "error in 'a': expected local"
    "(set)" "Compile error in 'set': expected name and value"
    ;; TODO: this should be an error in 1.0
    ;; "(local abc&d 19)" "illegal character: &"

    "(let [t []] (set t.47 :forty-seven))"
    "can't start multisym segment with a digit: t.47"
    "(let [x {:foo (fn [self] self.bar) :bar :baz}] x:foo)"
    "multisym method calls may only be in call position"
    "(let [x {:y {:foo (fn [self] self.bar) :bar :baz}}] x:y:foo)"
    "method must be last component of multisym: x:y:foo"
    "(set abc:def 2)" "cannot set method sym"}))

(fn test-parse-fails []
  (test-failures
   {"\n\n(+))" "unknown:3: Parse error: unexpected closing delimiter )"
    "(foo:)" "malformed multisym"
    "(foo.bar:)" "malformed multisym"}))

(fn test-core-fails []
  (test-failures
   {"\n\n(let [f (lambda []\n(local))] (f))" "unknown:4: "
    "\n\n(let [x.y 9] nil)" "unknown:3: Compile error in 'let': unexpected multi"
    "\n(when)" "unknown:2: Compile error in 'when'"
    "()" "expected a function, macro, or special"
    "(789)" "cannot call literal value"
    "(do\n\n\n(each \n[x (pairs {})] (when)))" "unknown:5: "
    "(each [k v (pairs {})] (BAD k v))" "BAD"
    "(f" "expected closing delimiter )"
    "(match [1 2 3] [a & b c] nil)" "rest argument before last parameter"
    "(not true false)" "expected one argument"
    "(print @)" "illegal character: @"
    "(x(y))" "expected whitespace before opening delimiter ("
    "(x[1 2])" "expected whitespace before opening delimiter ["
    "(eval-compiler (assert-compile false \"oh no\" 123))" "oh no"
    "(partial)" "expected a function"
    "(#)" "expected one argument"
    ;; PUC is ridiculous in what it accepts in a string
    "\"\\!\"" (if (or (not= _VERSION "Lua 5.1") _G.jit) "Invalid string")
    "(match abc true false def)" "even number of pattern/body pairs"
    ;; validity check on iterator clauses
    "(each [k (do-iter) :igloo 33] nil)" "unexpected iterator clause igloo"
    "(for [i 1 3 2 other-stuff] nil)" "unexpected arguments"
    "(do\n\n\n(each \n[x 34 (pairs {})] 21))"
    "unknown:5: Compile error in 'x': unable to bind number 34"
    "(with-open [(x y z) (values 1 2 3)])"
    "with-open only allows symbols in bindings"}))

(fn test-macro []
  (let [code "(import-macros {: fail-one} :test.macros) (fail-one 1)"
        (ok? msg) (pcall fennel.compileString code)]
    (l.assertStrContains msg "test/macros.fnl:2: oh no")
    ;; sometimes it's "in function f" and sometimes "in upvalue f"
    (l.assertStrMatches msg ".*test/macros.fnl:2: in %w+ 'def'.*")
    (l.assertStrMatches msg ".*test/macros.fnl:6: in %w+ 'abc'.*"))
  (let [(ok? msg) (pcall fennel.eval "(require-macros 100)")]
    (l.assertFalse ok?)
    (l.assertStrMatches msg ".*module name must compile to string.*")))

;; automated tests for suggestions are rudimentary because the usefulness of the
;; output is so subjective. to see a full catalog of suggestions, run the script
;; test/bad/friendly.sh and review that output.
(fn test-suggestions []
  (let [(_ msg) (pcall fennel.dofile "test/bad/set-local.fnl")
        (_ parse-msg) (pcall fennel.dofile "test/bad/odd-table.fnl")
        (_ assert-msg) (pcall fennel.eval
                              "(eval-compiler (assert-compile nil \"bad\" 1))")
        (_ msg4) (pcall fennel.eval "(abc] ;; msg4")
        (_ msg5) (pcall fennel.eval "(let {:a 1}) ;; msg5")]
    ;; show the raw error message
    (l.assertStrContains msg "expected var x")
    ;; offer suggestions
    (l.assertStrContains msg "Try declaring x using var")
    ;; show the code and point out the identifier at fault
    (l.assertStrContains msg "(set x 3)")
    (l.assertStrContains msg "\n     ^")
    ;; parse error
    (l.assertStrContains parse-msg "{:a 1 :b 2 :c}")
    ;; non-table AST in assertion
    (l.assertStrContains assert-msg "bad")
    ;; source should be part of the error message
    (l.assertStrContains msg4 "msg4")
    (l.assertStrContains msg5 "msg5")))

{: test-global-fails
 : test-fn-fails
 : test-binding-fails
 : test-macro-fails
 : test-core-fails
 : test-suggestions
 : test-macro
 : test-parse-fails}
