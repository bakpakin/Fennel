(local l (require :test.luaunit))
(local fennel (require :fennel))

(local failures {
  "\n\n(+))" "unknown:3: unexpected closing delimiter )"
  "\n\n(let [f (lambda []\n(local))] (f))" "4: expected name and value"
  "\n\n(let [x.y 9] nil)" "unknown:3: unexpected multi"
  "\n(when)" "Compile error in 'when' unknown:2"
  "((fn [] (require-macros \"test.macros\") (global x1 (->1 99 (+ 31)))))
      (->1 23 (+ 1))" "unknown global in strict mode"
  "()" "expected a function, macro, or special"
  "(789)" "cannot call literal value"
  "(do\n\n\n(each \n[x (pairs {})] (when)))" "when' unknown:5:"
  "(do\n\n\n(each \n[x 34 (pairs {})] 21))" "5: unable to bind number 34"
  "(each [k v (pairs {})] (BAD k v))" "BAD"
  "(f" "unknown:1: expected closing delimiter )"
  "(fn [12])" "expected symbol for function parameter"
  "(fn [:huh] 4)" "expected symbol for function parameter"
  "(fn []\n(for [32 34 32] 21))" "2: unable to bind number"
  "(fn [] [...])" "unexpected vararg"
  "(fn [false] 4)" "expected symbol for function parameter"
  "(fn [nil] 4)" "expected symbol for function parameter"
  "(fn global [] 1)" "overshadowed"
  "(fn global-caller [] (hey))" "unknown global"
  "(fn)" "expected parameters"
  "(global + 1)" "overshadowed"
  "(global - 1)" "overshadowed"
  "(global // 1)" "overshadowed"
  "(global 48 :forty-eight)" "unable to bind number 48"
  "(global good (fn [] nil)) (good) (BAD)" "BAD"
  "(global let 1)" "overshadowed"
  "(hey)" "unknown global"
  "(lambda x)" "expected arg list"
  "(let [:x 1] 1)" "unable to bind"
  "(let [[a & c d] [1 2]] c)" "rest argument before last parameter"
  "(let [b 9\nq (.)] q)" "2: expected table argument"
  "(let [bl 8 a bcd] nil)" "unknown global"
  "(let [false 1] 9)" "unable to bind boolean false"
  "(let [global 1] 1)" "overshadowed"
  "(let [next #(next $)] print)" "aliased by a local"
  "(let [nil 1] 9)" "unable to bind"
  "(let [pairs #(pairs $)] pairs)" "aliased by a local"
  "(let [t []] (set t.47 :forty-seven))" "can't start multisym segment with a digit: t.47"
  "(let [t []] (set t.:x :y))" "malformed multisym: t.:x"
  "(let [t []] (set t:.x :y))" "malformed multisym: t:.x"
  "(let [t []] (set t::x :y))" "malformed multisym: t::x"
  "(let [t {:a 1}] (+ t.a BAD))" "BAD"
  "(let [x 1 y] 8)" "expected even number of name/value bindings"
  "(let [x 1] (set-forcibly! x 2) (set x 3) x)" "expected var"
  "(let [x 1])" "expected body"
  "(let [x {:foo (fn [self] self.bar) :bar :baz}] x:foo)" "multisym method calls may only be in call position"
  "(let [x {:y {:foo (fn [self] self.bar) :bar :baz}}] x:y:foo)" "method must be last component of multisym: x:y:foo"
  "(local 47 :forty-seven)" "unable to bind number 47"
  "(local a-b 1) (global [a_b] [2])" "global a_b conflicts with local"
  "(local a-b 1) (global a_b 2)" "global a_b conflicts with local"
  "(local a~b 3)" "illegal character: ~"
  "(local ipairs #(ipairs $))" "aliased by a local"
  "(macros {:m (fn [t] `(each [mykey (pairs ,t)] (print mykey)))}) (m [])" "tried to bind mykey without gensym"
  "(macros {:m (fn [t] `(fn [xabc] (+ xabc 9)))}) ((m 4))" "tried to bind xabc without gensym"
  "(macros {:m (fn [y] `(let [x 1] (+ x ,y)))}) (m 4)" "tried to bind x without gensym"
  "(match [1 2 3] [a & b c] nil)" "rest argument before last parameter"
  "(not true false)" "expected one argument"
  "(print @)" "illegal character: @"
  ;; TODO: this should be an error in 1.0
  ;; "(local abc&d 19)" "illegal character: &"
  "(set [a b c] [1 2 3]) (+ a b c)" "expected local"
  "(set a 19)" "error in 'a' unknown:1: expected local"
  "(set)" "Compile error in 'set' unknown:1: expected name and value"
  "(x(y))" "expected whitespace before opening delimiter ("
  "(x[1 2])" "expected whitespace before opening delimiter ["
  "(fn abc:def [x] (+ x 2))" "unexpected multi symbol abc:def"
  "(macros {:foo {:bar (fn [] `(print :test))}})" "expected each macro to be function"
  "(macro m [] (getmetatable :foo)) (m)" "Illegal metatable"
  "(import-macros test :test.macros) (test.asdf)" "macro not found in imported macro module"
  "(import-macros {: asdf} :test.macros)" "macro asdf not found in module test.macros"
  "(with-open [(x y z) (values 1 2 3)])" "with-open only allows symbols in bindings"
  "#[$ $...] 1 2 3" "$ and $... in hashfn are mutually exclusive"
  "(eval-compiler (assert-compile false \"oh no\" 123))" "oh no"
  "(partial)" "expected a function"
  "(#)" "expected one argument"
  "\"\\!\"" "Invalid string"
})

(fn test-failures []
  (each [code expected-msg (pairs failures)]
    (let [(ok? msg) (pcall fennel.compileString code
                           {:allowedGlobals ["pairs" "next" "ipairs"]
                            :unfriendly true})]
      (l.assertFalse ok? (.. "Expected compiling " code " to fail."))
      (l.assertStrContains msg expected-msg))))

(fn test-macro []
  (let [code "(import-macros {: fail-one} :test.macros) (fail-one 1)"
        (ok? msg) (pcall fennel.compileString code)]
    (l.assertStrContains msg "test/macros.fnl:2: oh no")
    ;; sometimes it's "in function f" and sometimes "in upvalue f"
    (l.assertStrMatches msg ".*test/macros.fnl:2: in %w+ 'def'.*")
    (l.assertStrMatches msg ".*test/macros.fnl:6: in %w+ 'abc'.*")))

;; automated tests for suggestions are rudimentary because the usefulness of the
;; output is so subjective. to see a full catalog of suggestions, run the script
;; test/bad/friendly.sh and review that output.
(fn test-suggestions []
  (let [(_ msg) (pcall fennel.dofile "test/bad/set-local.fnl")
        (_ parse-msg) (pcall fennel.dofile "test/bad/odd-table.fnl")
        (_ assert-msg) (pcall fennel.eval
                              "(eval-compiler (assert-compile nil \"bad\" 1))")
        (_ msg4) (pcall fennel.eval "(abc] ;; msg4")
        (_ msg5) (pcall fennel.eval "(let) ;; msg5")]
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

{: test-failures : test-suggestions : test-macro}
