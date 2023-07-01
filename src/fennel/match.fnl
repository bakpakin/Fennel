;;; Pattern matching
;; This is separated out so we can use the "core" macros during the
;; implementation of pattern matching.

(fn copy [t] (collect [k v (pairs t)] k v))

(fn with [opts k]
  (doto (copy opts) (tset k true)))

(fn without [opts k]
  (doto (copy opts) (tset k nil)))

(fn case-values [vals pattern unifications case-pattern opts]
  (let [condition `(and)
        bindings []]
    (each [i pat (ipairs pattern)]
      (let [(subcondition subbindings) (case-pattern [(. vals i)] pat
                                                      unifications (without opts :multival?))]
        (table.insert condition subcondition)
        (icollect [_ b (ipairs subbindings) &into bindings] b)))
    (values condition bindings)))

(fn case-table [val pattern unifications case-pattern opts]
  (let [condition `(and (= (_G.type ,val) :table))
        bindings []]
    (each [k pat (pairs pattern)]
      (if (sym? pat :&)
          (let [rest-pat (. pattern (+ k 1))
                rest-val `(select ,k ((or table.unpack _G.unpack) ,val))
                subcondition (case-table `(pick-values 1 ,rest-val)
                                          rest-pat unifications case-pattern
                                          (without opts :multival?))]
            (if (not (sym? rest-pat))
                (table.insert condition subcondition))
            (assert (= nil (. pattern (+ k 2)))
                    "expected & rest argument before last parameter")
            (table.insert bindings rest-pat)
            (table.insert bindings [rest-val]))
          (sym? k :&as)
          (do
            (table.insert bindings pat)
            (table.insert bindings val))
          (and (= :number (type k)) (sym? pat :&as))
          (do
            (assert (= nil (. pattern (+ k 2)))
                    "expected &as argument before last parameter")
            (table.insert bindings (. pattern (+ k 1)))
            (table.insert bindings val))
          ;; don't process the pattern right after &/&as; already got it
          (or (not= :number (type k)) (and (not (sym? (. pattern (- k 1)) :&as))
                                           (not (sym? (. pattern (- k 1)) :&))))
          (let [subval `(. ,val ,k)
                (subcondition subbindings) (case-pattern [subval] pat
                                                          unifications
                                                          (without opts :multival?))]
            (table.insert condition subcondition)
            (icollect [_ b (ipairs subbindings) &into bindings] b))))
    (values condition bindings)))

(fn case-guard [vals condition guards unifications case-pattern opts]
  (if (= 0 (length guards))
    (case-pattern vals condition unifications opts)
    (let [(pcondition bindings) (case-pattern vals condition unifications opts)
          condition `(and ,(unpack guards))]
       (values `(and ,pcondition
                     (let ,bindings
                       ,condition)) bindings))))

(fn symbols-in-pattern [pattern]
  "gives the set of symbols inside a pattern"
  (if (list? pattern)
      (if (or (sym? (. pattern 1) :where)
              (sym? (. pattern 1) :=))
          (symbols-in-pattern (. pattern 2))
          (sym? (. pattern 2) :?)
          (symbols-in-pattern (. pattern 1))
          (let [result {}]
            (each [_ child-pattern (ipairs pattern)]
              (collect [name symbol (pairs (symbols-in-pattern child-pattern)) &into result]
                name symbol))
            result))
      (sym? pattern)
      (if (and (not (sym? pattern :or))
               (not (sym? pattern :nil)))
          {(tostring pattern) pattern}
          {})
      (= (type pattern) :table)
      (let [result {}]
        (each [key-pattern value-pattern (pairs pattern)]
          (collect [name symbol (pairs (symbols-in-pattern key-pattern)) &into result]
            name symbol)
          (collect [name symbol (pairs (symbols-in-pattern value-pattern)) &into result]
            name symbol))
        result)
      {}))

(fn symbols-in-every-pattern [pattern-list infer-unification?]
  "gives a list of symbols that are present in every pattern in the list"
  (let [?symbols (accumulate [?symbols nil
                              _ pattern (ipairs pattern-list)]
                   (let [in-pattern (symbols-in-pattern pattern)]
                     (if ?symbols
                       (do
                         (each [name symbol (pairs ?symbols)]
                           (when (not (. in-pattern name))
                             (tset ?symbols name nil)))
                         ?symbols)
                       in-pattern)))]
    (icollect [_ symbol (pairs (or ?symbols {}))]
      (if (not (and infer-unification?
                    (in-scope? symbol)))
        symbol))))

(fn case-or [vals pattern guards unifications case-pattern opts]
  (let [pattern [(unpack pattern 2)]
        bindings (symbols-in-every-pattern pattern opts.infer-unification?)] ;; TODO opts.infer-unification instead of opts.unification?
    (if (= 0 (length bindings))
      ;; no bindings special case generates simple code
      (let [condition
            (icollect [i subpattern (ipairs pattern) &into `(or)]
              (let [(subcondition subbindings) (case-pattern vals subpattern unifications opts)]
                subcondition))]
        (values
          (if (= 0 (length guards))
            condition
            `(and ,condition ,(unpack guards)))
          []))
      ;; case with bindings is handled specially, and returns three values instead of two
      (let [matched? (gensym :matched?)
            bindings-mangled (icollect [_ binding (ipairs bindings)]
                               (gensym (tostring binding)))
            pre-bindings `(if)]
        (each [i subpattern (ipairs pattern)]
          (let [(subcondition subbindings) (case-guard vals subpattern guards {} case-pattern opts)]
            (table.insert pre-bindings subcondition)
            (table.insert pre-bindings `(let ,subbindings
                                          (values true ,(unpack bindings))))))
        (values matched?
                [`(,(unpack bindings)) `(values ,(unpack bindings-mangled))]
                [`(,matched? ,(unpack bindings-mangled)) pre-bindings])))))

(fn case-pattern [vals pattern unifications opts top-level?]
  "Take the AST of values and a single pattern and returns a condition
to determine if it matches as well as a list of bindings to
introduce for the duration of the body if it does match."

  ;; This function returns the following values (multival):
  ;; a "condition", which is an expression that determines whether the
  ;;   pattern should match,
  ;; a "bindings", which bind all of the symbols used in a pattern
  ;; an optional "pre-bindings", which is a list of bindings that happen
  ;;   before the condition and bindings are evaluated. These should only
  ;;   come from a (case-or). In this case there should be no recursion:
  ;;   the call stack should be case-condition > case-pattern > case-or
  ;;
  ;; Here are the expected flags in the opts table:
  ;;   :infer-unification? boolean - if the pattern should guess when to unify  (ie, match -> true, case -> false)
  ;;   :multival? boolean - if the pattern can contain multivals  (in order to disallow patterns like [(1 2)])
  ;;   :in-where? boolean - if the pattern is surrounded by (where)  (where opts into more pattern features)
  ;;   :legacy-guard-allowed? boolean - if the pattern should allow `(a ? b) patterns

  ;; we have to assume we're matching against multiple values here until we
  ;; know we're either in a multi-valued clause (in which case we know the #
  ;; of vals) or we're not, in which case we only care about the first one.
  (let [[val] vals]
    (if (and (sym? pattern)
             (or (sym? pattern :nil)
                 (and opts.infer-unification?
                      (in-scope? pattern)
                      (not (sym? pattern :_)))
                 (and opts.infer-unification?
                      (multi-sym? pattern)
                      (in-scope? (. (multi-sym? pattern) 1)))))
        (values `(= ,val ,pattern) [])
        ;; unify a local we've seen already
        (and (sym? pattern) (. unifications (tostring pattern)))
        (values `(= ,(. unifications (tostring pattern)) ,val) [])
        ;; bind a fresh local
        (sym? pattern)
        (let [wildcard? (: (tostring pattern) :find "^_")]
          (if (not wildcard?) (tset unifications (tostring pattern) val))
          (values (if (or wildcard? (string.find (tostring pattern) "^?")) true
                      `(not= ,(sym :nil) ,val)) [pattern val]))
        ;; opt-in unify with (=)
        (and (list? pattern)
             (sym? (. pattern 1) :=)
             (sym? (. pattern 2)))
        (let [bind (. pattern 2)]
          (assert-compile (= 2 (length pattern)) "(=) should take only one argument" pattern)
          (assert-compile (not opts.infer-unification?) "(=) cannot be used inside of match" pattern)
          (assert-compile opts.in-where? "(=) must be used in (where) patterns" pattern)
          (assert-compile (and (sym? bind) (not (sym? bind :nil)) "= has to bind to a symbol" bind))
          (values `(= ,val ,bind) []))
        ;; where-or clause
        (and (list? pattern) (sym? (. pattern 1) :where) (list? (. pattern 2)) (sym? (. pattern 2 1) :or))
        (do
          (assert-compile top-level? "can't nest (where) pattern" pattern)
          (case-or vals (. pattern 2) [(unpack pattern 3)] unifications case-pattern (with opts :in-where?)))
        ;; where clause
        (and (list? pattern) (sym? (. pattern 1) :where))
        (do
          (assert-compile top-level? "can't nest (where) pattern" pattern)
          (case-guard vals (. pattern 2) [(unpack pattern 3)] unifications case-pattern (with opts :in-where?)))
        ;; or clause (not allowed on its own)
        (and (list? pattern) (sym? (. pattern 1) :or))
        (do
          (assert-compile top-level? "can't nest (or) pattern" pattern)
          ;; This assertion can be removed to make patterns more permissive
          (assert-compile false "(or) must be used in (where) patterns" pattern)
          (case-or vals pattern [] unifications case-pattern opts))
        ;; guard clause
        (and (list? pattern) (sym? (. pattern 2) :?))
        (do
          (assert-compile opts.legacy-guard-allowed? "legacy guard clause not supported in case" pattern)
          (case-guard vals (. pattern 1) [(unpack pattern 3)] unifications case-pattern opts))
        ;; multi-valued patterns (represented as lists)
        (list? pattern)
        (do
          (assert-compile opts.multival? "can't nest multi-value destructuring" pattern)
          (case-values vals pattern unifications case-pattern opts))
        ;; table patterns
        (= (type pattern) :table)
        (case-table val pattern unifications case-pattern opts)
        ;; literal value
        (values `(= ,val ,pattern) []))))

(fn add-pre-bindings [out pre-bindings]
  "Decide when to switch from the current `if` AST to a new one"
  (if pre-bindings
      ;; `out` no longer needs to grow.
      ;; Instead, a new tail `if` AST is introduced, which is where the rest of
      ;; the clauses will get appended. This way, all future clauses have the
      ;; pre-bindings in scope.
      (let [tail `(if)]
        (table.insert out true)
        (table.insert out `(let ,pre-bindings ,tail))
        tail)
      ;; otherwise, keep growing the current `if` AST.
      out))

(fn case-condition [vals clauses match?]
  "Construct the actual `if` AST for the given match values and clauses."
  ;; root is the original `if` AST.
  ;; out is the `if` AST that is currently being grown.
  (let [root `(if)]
    (faccumulate [out root
                  i 1 (length clauses) 2]
      (let [pattern (. clauses i)
            body (. clauses (+ i 1))
            (condition bindings pre-bindings) (case-pattern vals pattern {}
                                                            {:multival? true
                                                             :infer-unification? match?
                                                             :legacy-guard-allowed? match?}
                                                            true)
            out (add-pre-bindings out pre-bindings)]
        ;; grow the `if` AST by one extra condition
        (table.insert out condition)
        (table.insert out `(let ,bindings
                            ,body))
        out))
    root))

(fn count-case-multival [pattern]
  "Identify the amount of multival values that a pattern requires."
  (if (and (list? pattern) (sym? (. pattern 2) :?))
      (count-case-multival (. pattern 1))
      (and (list? pattern) (sym? (. pattern 1) :where))
      (count-case-multival (. pattern 2))
      (and (list? pattern) (sym? (. pattern 1) :or))
      (accumulate [longest 0
                   _ child-pattern (ipairs pattern)]
        (math.max longest (count-case-multival child-pattern)))
      (list? pattern)
      (length pattern)
      1))

(fn case-count-syms [clauses]
  "Find the length of the largest multi-valued clause"
  (let [patterns (fcollect [i 1 (length clauses) 2]
                   (. clauses i))]
    (accumulate [longest 0
                 _ pattern (ipairs patterns)]
      (math.max longest (count-case-multival pattern)))))

(fn case-impl [match? val ...]
  "The shared implementation of case and match."
  (assert (not= val nil) "missing subject")
  (assert (= 0 (math.fmod (select :# ...) 2))
          "expected even number of pattern/body pairs")
  (assert (not= 0 (select :# ...))
          "expected at least one pattern/body pair")
  (let [clauses [...]
        vals-count (case-count-syms clauses)
        skips-multiple-eval-protection? (and (= vals-count 1) (sym? val) (not (multi-sym? val)))]
    (if skips-multiple-eval-protection?
      (case-condition (list val) clauses match?)
      ;; protect against multiple evaluation of the value, bind against as
      ;; many values as we ever match against in the clauses.
      (let [vals (fcollect [i 1 vals-count &into (list)] (gensym))]
        (list `let [vals val] (case-condition vals clauses match?))))))

(fn case* [val ...]
  "Perform pattern matching on val. See reference for details.

Syntax:

(case data-expression
  pattern body
  (where pattern guards*) body
  (or pattern patterns*) body
  (where (or pattern patterns*) guards*) body
  ;; legacy:
  (pattern ? guards*) body)"
  (case-impl false val ...))

(fn match* [val ...]
  "Perform pattern matching on val, automatically unifying on variables in
local scope. See reference for details.

Syntax:

(match data-expression
  pattern body
  (where pattern guards*) body
  (or pattern patterns*) body
  (where (or pattern patterns*) guards*) body
  ;; legacy:
  (pattern ? guards*) body)"
  (case-impl true val ...))

(fn case-try-step [how expr else pattern body ...]
  (if (= nil pattern body)
      expr
      ;; unlike regular match, we can't know how many values the value
      ;; might evaluate to, so we have to capture them all in ... via IIFE
      ;; to avoid double-evaluation.
      `((fn [...]
          (,how ...
            ,pattern ,(case-try-step how body else ...)
            ,(unpack else)))
        ,expr)))

(fn case-try-impl [how expr pattern body ...]
  (let [clauses [pattern body ...]
        last (. clauses (length clauses))
        catch (if (sym? (and (= :table (type last)) (. last 1)) :catch)
                 (let [[_ & e] (table.remove clauses)] e) ; remove `catch sym
                 [`_# `...])]
    (assert (= 0 (math.fmod (length clauses) 2))
            "expected every pattern to have a body")
    (assert (= 0 (math.fmod (length catch) 2))
            "expected every catch pattern to have a body")
    (case-try-step how expr catch (unpack clauses))))

(fn case-try* [expr pattern body ...]
  "Perform chained pattern matching for a sequence of steps which might fail.

The values from the initial expression are matched against the first pattern.
If they match, the first body is evaluated and its values are matched against
the second pattern, etc.

If there is a (catch pat1 body1 pat2 body2 ...) form at the end, any mismatch
from the steps will be tried against these patterns in sequence as a fallback
just like a normal match. If there is no catch, the mismatched values will be
returned as the value of the entire expression."
  (case-try-impl `case expr pattern body ...))

(fn match-try* [expr pattern body ...]
  "Perform chained pattern matching for a sequence of steps which might fail.

The values from the initial expression are matched against the first pattern.
If they match, the first body is evaluated and its values are matched against
the second pattern, etc.

If there is a (catch pat1 body1 pat2 body2 ...) form at the end, any mismatch
from the steps will be tried against these patterns in sequence as a fallback
just like a normal match. If there is no catch, the mismatched values will be
returned as the value of the entire expression."
  (case-try-impl `match expr pattern body ...))

{:case case*
 :case-try case-try*
 :match match*
 :match-try match-try*}
