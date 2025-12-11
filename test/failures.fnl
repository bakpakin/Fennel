(local t (require :test.faith))
(local fennel (require :fennel))
(local friend (require :fennel.friend))

;; This can only be used to assert failures on special forms; macros will be
;; expanded before this code ever sees it.
(macro assert-fail [form expected]
  `(let [(ok# msg#) (pcall fennel.compile-string (macrodebug ,form true)
                           {:allowedGlobals ["pairs" "next" "ipairs" "_G" "print"]
                            :correlate true
                            :warn #nil})]
     (t.is (not ok#) (.. "Expected failure: " ,(tostring form)))
     (t.match ,expected msg#)))

;; use this only when you can't use the above macro
(fn test-failures [failures]
  (each [code expected-msg (pairs failures)]
    (let [(ok? msg) (pcall fennel.compile-string code
                           {:allowedGlobals ["pairs" "next" "ipairs" "_G"]
                            :unfriendly true :correlate true
                            :warn #nil})]
      (t.is (not ok?) (.. "Expected compiling " code " to fail."))
      (t.is (msg:find expected-msg 1 true)
            (.. "Expected to find\n" (fennel.view expected-msg)
                "\n    in\n" (fennel.view msg))))))

(fn test-names []
  (assert-fail (local + 6) "overshadowed by a special form")
  (assert-fail (macro comment [] "wat") "overshadowed by a special form")
  (assert-fail (do each) "tried to reference a special form"))

(fn test-global-fails []
  (assert-fail (fn global [] 1) "overshadowed")
  (assert-fail (fn global-caller [] (hey)) "unknown identifier")
  (assert-fail (global 48 :forty-eight) "unable to bind number 48")
  (assert-fail (do (global good (fn [] nil)) (good) (BAD)) "BAD")
  (assert-fail (global let 1) "tried to reference a special form")
  (assert-fail (hey) "unknown identifier")
  (assert-fail (let [bl 8 a bcd] nil) "unknown identifier")
  (assert-fail (let [global 1] 1) "overshadowed")
  (assert-fail (do (local a-b 1) (global [a_b] [2]))
               "global a_b conflicts with local")
  (assert-fail (do (local a-b 1) (global a_b 2))
               "global a_b conflicts with local")
  (assert-fail (do ((fn []
                      (require-macros :test.macros)
                      (global x1 (->1 99 (+ 31)))))
                   (->1 23 (+ 1)))
               "unknown identifier")
  ;; strict mode applies to macro modules too
  (test-failures {"(import-macros t :test.bad.unknown-global)"
                  "unknown identifier"}))

(fn test-fn-fails []
  (assert-fail (fn [12]) "expected symbol for function parameter")
  (assert-fail (fn [:huh] 4) "expected symbol for function parameter")
  (assert-fail (fn [] [...]) "unexpected vararg")
  (assert-fail (fn [false] 4) "expected symbol for function parameter")
  (assert-fail (fn [nil] 4) "expected symbol for function parameter")
  (assert-fail (fn) "expected parameters")
  (assert-fail (fn abc:def [x] (+ x 2)) "unexpected multi symbol abc:def")
  (assert-fail #[$ $...] "$ and $... in hashfn are mutually exclusive")
  (assert-fail #(values ...) "use $... in hashfn")
  (assert-fail (fn [a & b c] nil)
               "expected rest argument before last parameter")
  (assert-fail (fn [...] (+ ...)) "tried to use vararg with operator")
  (assert-fail (fn eugh.lol []) "expected local table eugh")
  (test-failures {"(lambda x)" "expected arg list"
                  "(fn [a & {3 3}] nil)" "unable to bind number 3"}))

(fn test-macro-fails []
  (test-failures
   {"(macros {:m (fn [t] `(each [mykey (pairs ,t)] (print mykey)))}) (m [])"
    "tried to bind mykey without gensym"
    "(macros {:m (fn [t] `(fn [xabc] (+ xabc 9)))}) ((m 4))"
    "tried to bind xabc without gensym"
    "(macros {:m (fn [y] `(let [x 1] (+ x ,y)))}) (m 4)"
    "tried to bind x without gensym"
    "(macros {:foo {:bar (fn [] `(print :test))}})"
    "expected each macro to be function or callable table"
    "(macro m [] (getmetatable :foo)) (m)"
    "Illegal metatable"
    "(import-macros test :test.macros) (test.asdf)"
    "macro not found, or not callable, in macro table"
    "(macros {:M (setmetatable {:foo #:YES} {:__call (fn [$ ...] ($.foo ...))})}) (M.bar 1)"
    "macro not found, or not callable, in macro table"
    ;; macros should shadow locals as values, not just when calling:
    "(let [t {:b 2}] (import-macros t :test.macros) t.b)"
    "tried to reference a macro"
    "(import-macros {: asdf} :test.macros)"
    "macro asdf not found in module test.macros"
    "(import-macros m :test.bad.macro-no-return-table)"
    "expected macros to be table"
    "(macros {:noop #nil} {:identity #$})" "Expected one table argument"
    "(macro xyz [t] ,t)" "tried to use unquote outside quote"
    "(macros (do :BORK))" "Expected one table argument"}))

(fn test-binding-fails []
  (assert-fail (let [x {:foo (fn [self] self.bar) :bar :baz}] x:foo)
               "multisym method calls may only be in call position")
  (assert-fail (local () 1) "at least one value")
  (assert-fail (set abc:def 2) "cannot set method sym")
  (assert-fail (let [nil 1] 9) "unable to bind")
  (assert-fail (let [[a & c d] [1 2]] c)
               "rest argument before last parameter")
  (assert-fail (local abc&d 19) "invalid character: &")
  (assert-fail (set a 19) "expected local a")
  (assert-fail (set a.b 2) "expected local a")
  (assert-fail (let [pairs #(pairs $)] pairs) "aliased by a local")
  (assert-fail (let [x 1] (set-forcibly! x 2) (set x 3) x) "expected var")
  (assert-fail (set) "Compile error: expected name and value")
  (assert-fail (do (set [a b c] [1 2 3]) (+ a b c)) "expected local")
  (assert-fail (let [:x 1] 1) "unable to bind")
  (assert-fail (let [next #(next $)] print) "aliased by a local")
  (assert-fail (let [x 1 y] 8) "expected even number of name/value bindings")
  (assert-fail (let [false 1] 9) "unable to bind boolean false")
  (assert-fail (let [b 9 q (.)] q) "Compile error: expected table")
  (assert-fail (local ipairs #(ipairs $)) "aliased by a local")
  (assert-fail (let [x 1]) "expected body")
  (assert-fail (let [t {:a 1}] (+ t.a BAD)) "BAD")
  (assert-fail (local 47 :forty-seven) "unable to bind number 47")
  (assert-fail (set (. 98 1) true) "needs symbol target")
  (assert-fail (do (var t {}) (set (. t) true)) "needs at least one key")
  (assert-fail (set (. FAKEGLOBAL :x) true) "unknown identifier")
  (assert-fail (set [(. FAKEGLOBAL :x)] [true]) "unknown identifier")
  (assert-fail (let [{: x &as foo} 8] 42) "could not destructure literal")
  (assert-fail (let [{: x &as foo} nil] 42) "could not destructure literal")
  (assert-fail (let [[first &as list & rest] []]  true) "&as argument before last parameter")
  (assert-fail (let [[first "&as" list] []]  true) "unable to bind string")
  (assert-fail (let [{(+ 1 1) v} {}] true) "expected key to be a literal")
  (test-failures {"(local a~b 3)" "invalid character: ~"
                  "(let [t []] (set t.:x :y))" "malformed multisym: t.:x"
                  "(let [t []] (set t::x :y))" "malformed multisym: t::x"
                  "(let [t []] (set t:.x :y))" "malformed multisym: t:.x"
                  "(let [x {:y {:foo (fn [self] self.bar) :bar :baz}}] x:y:foo)"
                  "method must be last component of multisym: x:y:foo"}))

(fn parse-fail [code]
  #(each [p (assert (fennel.parser code))] (assert p)))

(fn test-parse-fails []
  (t.error "malformed multisym" (parse-fail "(foo:)"))
  (t.error "malformed multisym" (parse-fail "(foo.bar:)"))
  (t.error "unknown:3:0: Parse error: expected closing delimiter %)"
           (parse-fail "(do\n\n"))
  (t.error "unknown:3:3: Parse error: unexpected closing delimiter %)"
           (parse-fail "\n\n(+))"))
  (t.error "mismatched closing delimiter }, expected %]"
           (parse-fail "(fn \n[})")))

(fn test-core-fails []
  (test-failures
   {"\n\n(let [f (lambda []\n(local))] (f))" "unknown:4:0: "
    "\n\n(let [x.y 9] nil)" "unknown:3:0: Compile error in 'let': unexpected multi"
    "\n(when)" "unknown:2:0: Compile error in 'when'"
    "()" "expected a function, macro, or special"
    "(789)" "cannot call literal value"
    "(do\n\n\n(each \n[x (pairs {})] (when)))" "unknown:5:15: "
    "(each [k v (pairs {})] (BAD k v))" "BAD"
    "(f" "expected closing delimiter )"
    "(match [1 2 3] [a & b c] nil)" "rest argument before last parameter"
    "(not true false)" "expected one argument"
    "(print @)" "invalid character: @"
    "(x(y))" "expected whitespace before opening delimiter ("
    "(x[1 2])" "expected whitespace before opening delimiter ["
    "(eval-compiler (assert-compile false \"oh no\" 123))" "oh no"
    "(partial)" "expected a function"
    "(#)" "expected one argument"
    "\"\\!\"" "invalid escape sequence"
    "(doto)" "missing subject"
    ;; validity check on iterator clauses
    "(each [k (do-iter) :igloo 33] nil)" "unexpected iterator clause: igloo"
    ;; "(each [(i x) y (do-iter)] (print x))" "unexpected bindings in iterator"
    ;; "(each [i x (y) (do-iter)] (print x))" "unexpected bindings in iterator"
    "(for [i 1 3 2 other-stuff] nil)" "unexpected arguments"
    "(do\n\n\n(each \n[x 34 (pairs {})] 21))"
    "unknown:5:0: Compile error in 'x': unable to bind number 34"
    "(faccumulate [a {} 1 2 3] (print a))"
    "unknown:1:0: Compile error in '1': unable to bind number 1"
    "(with-open [(x y z) (values 1 2 3)])"
    "with-open only allows symbols in bindings"
    "([])" "cannot call literal value table"
    "(let [((x)) 1] (do))" "can't nest multi-value destructuring"
    "(tail! (if false (print :one) (print :two)))"
    "Expected a function call as argument"
    "(tail! [])"
    "Expected a function call as argument"
    "(do (tail! (print :x)) (print :y))"
    "Must be in tail position"
    "((values))" "cannot call literal value"}))

(fn test-match-fails []
  (test-failures
   {"(match :hey true false def)" "even number of pattern/body pairs"
    "(match :hey)" "at least one pattern/body pair"
    "(match)" "missing subject"
    "(match :subject ((pattern)) :body)" "can't nest multi-value destructuring"
    "(match :subject [(pattern)] :body)" "can't nest multi-value destructuring"
    "(match :subject (where (where pattern)) :body)" "can't nest (where) pattern"
    ;; (where (or)) shape is allowed
    "(match :subject (where (or (where pattern))) :body)" "can't nest (where) pattern" ;; perhaps this should be allowed in the future
    "(match :subject [(where pattern)] :body)" "can't nest (where) pattern"
    "(match :subject ((where pattern)) :body)" "can't nest (where) pattern"
    "(match :subject (or :subject x) :body)" "(or) must be used in (where) patterns"
    "(case :subject (= x) :body)" "(=) must be used in (where) patterns"
    "(match :subject [(or pattern)] :body)" "can't nest (or) pattern"
    "(match :subject ((or pattern)) :body)" "can't nest (or) pattern"
    "(match [1] (where (or [_ a] [a b]) b) :body)" "unknown identifier"
    "(match [1] (where (or [_ a] [a b])) b)" "unknown identifier"}))

(fn test-macro []
  (tset fennel.macro-loaded :test.macros nil)
  (let [code "(import-macros {: fail-one} :test.macros) (fail-one 1)"
        (ok? msg) (pcall fennel.compile-string code {:correlate true})]
    (t.is (not ok?))
    (t.match "test.macros.fnl:3: oh no" msg)
    ;; sometimes it's "in function f" and sometimes "in upvalue f"
    (t.match ".*test.macros.fnl:3: in %w+ 'def'.*" msg)
    (t.match ".*test.macros.fnl:4: in %w+ 'abc'.*" msg)
    (t.not-match "fennel.compiler" msg))
  (let [(ok? msg) (pcall fennel.eval "(require-macros 100)")]
    (t.is (not ok?))
    (t.match ".*module name must compile to string.*" msg)))

(fn no-codes [s] (s:gsub "\027%[[0-9]m" ""))

;; automated tests for suggestions are rudimentary because the usefulness of the
;; output is so subjective. to see a full catalog of suggestions, run the script
;; test/bad/friendly.sh and review that output.
(fn test-suggestions []
  (let [(_ msg) (pcall fennel.dofile "test/bad/set-local.fnl")
        (_ parse-msg) (pcall fennel.dofile "test/bad/odd-table.fnl")
        (_ assert-msg) (pcall fennel.eval
                              "(eval-compiler (assert-compile nil \"bad\" 1))")
        (_ msg4) (pcall fennel.eval "(abc] ;; msg4")
        (_ msg5) (pcall fennel.eval "(let {:a 1}) ;; msg5")
        (_ msg6) (pcall fennel.eval "(for [:abc \n \"def t\"] nil)")
        (_ msg7) (pcall fennel.eval "(match) ;; msg7")
        (_ msg-custom-pinpoint) (pcall fennel.eval "(asdf 123)"
                                       {:error-pinpoint [">>>" "<<<"]})
        (_ msg-custom-pinpoint2) (pcall fennel.eval "(asdf]"
                                        {:error-pinpoint [">>>" "<<<"]})
        (_ msg-custom-pinpoint3) (pcall fennel.eval
                                        "(icollect [_ _ \n(pairs [])]\n)"
                                        {:error-pinpoint [">>>" "<<<"]})]
    ;; use the standard prefix
    (t.match "^%S+:%d+:%d+: Compile error: .+" msg)
    (t.match "^%S+:%d+:%d+: Parse error: .+" parse-msg)
    ;; show the raw error message
    (t.match "expected var x" msg)
    ;; offer suggestions
    (t.match "Try declaring x using var" msg)
    ;; show the code and point out the identifier at fault
    (t.match "(set x 3)" (no-codes msg))
    ;; parse error
    (t.match "{:a 1 :b 2 :c}" (no-codes parse-msg))
    ;; non-table AST in assertion
    (t.match "bad" assert-msg)
    ;; source should be part of the error message
    (t.match "msg4" msg4)
    (t.match "msg5" msg5)
    (t.match "unable to bind string abc" msg6)
    (t.match "msg7" msg7)
    ;; custom error pinpointing works
    (t.match ">>>asdf<<<" msg-custom-pinpoint)
    (t.match ">>>]<<<" msg-custom-pinpoint2)
    (t.match ">>>%(icollect" msg-custom-pinpoint3)))

(fn doer []
  ;; this plugin does not detach in subsequent tests, so we must check that
  ;; it only fires once, exactly for our specific test.
  ;; https://github.com/bakpakin/Fennel/pull/427#issuecomment-1138286136
  (var fired-once false)
  (fn [ast]
    (when (not fired-once)
      (set fired-once true)
      (friend.assert-compile false "test-macro-traces plugin failed successfully" ast))))

(fn test-macro-traces []
  ;; we want to trigger an error from inside a built-in macro and make sure we
  ;; don't get built-in macro trace info in the error messages.
  (let [(_ err) (pcall fennel.eval "\n\n(match 5 b (print 5))"
                       {:plugins [{:plugin-from :test-macro-traces
                                   :do (doer)
                                   :versions [(fennel.version:gsub "-dev" "")]}]
                        :filename "matcher.fnl"})]
    (t.match "matcher.fnl:3" err))
  (let [(_ err) (pcall fennel.eval "(match 5 b)")]
    (t.not-match "fennel.compiler.macroexpand" err)))

;; This does not prevent:
;; (print (local abc :def)) (can't rely on nval)
;; (if (fn abc []) :yes :no) (can't prevent function from being constructed)
(fn test-disallow-locals []
  (assert-fail (print (local xaby 10) xaby) "can't introduce local here")
  (assert-fail (if (var x 10) (print x) (print x)) "can't introduce var")
  (assert-fail (print (local abc :def)) "can't introduce local here")
  (assert-fail (or (local x 10) x) "can't introduce local"))

(fn test-parse-warnings []
  (let [warnings []]
    ((fennel.parser "\n\n(print\"\"token\"\")"
                    "filename.fnl"
                    {:warn #(table.insert warnings {:message $1 :line $4 :col $5})}))
    ;; specifically interested in the line and column numbers
    (t.= [{:message "expected whitespace before string" :line 3 :col 6}
          {:message "expected whitespace before token" :line 3 :col 8}
          {:message "expected whitespace before string" :line 3 :col 13}]
         warnings))
  (let [warnings []]
    ((fennel.parser "(do\n  (\"string\":sub 1 1)\n  (\"string\"false)\n  (\"string\"0))"
                    "filename.fnl"
                    {:warn #(table.insert warnings {:message $1 :line $4 :col $5})}))
    (t.= [{:message "expected whitespace before token" :line 2 :col 11}
          {:message "expected whitespace before token" :line 3 :col 11}
          {:message "expected whitespace before token" :line 4 :col 11}]
         warnings)))

{: test-global-fails
 : test-fn-fails
 : test-binding-fails
 : test-macro-fails
 : test-match-fails
 : test-core-fails
 : test-suggestions
 : test-macro
 : test-parse-fails
 : test-macro-traces
 : test-disallow-locals
 : test-names
 : test-parse-warnings}
