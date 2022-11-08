;;; Pattern matching
;; This is separated out so we can use the "core" macros during the
;; implementation of pattern matching.

(fn without-multival [opts]
  (if opts.multival?
    (let [copy {}]
      (each [k v (pairs opts)]
        (tset copy k v))
      (tset copy :multival? nil)
      copy)
    opts))

(fn match-values [vals pattern unifications match-pattern opts]
  (let [condition `(and)
        bindings []]
    (each [i pat (ipairs pattern)]
      (let [(subcondition subbindings) (match-pattern [(. vals i)] pat
                                                      unifications (without-multival opts))]
        (table.insert condition subcondition)
        (each [_ b (ipairs subbindings)]
          (table.insert bindings b))))
    (values condition bindings)))

(fn match-table [val pattern unifications match-pattern opts]
  (let [condition `(and (= (_G.type ,val) :table))
        bindings []]
    (each [k pat (pairs pattern)]
      (if (= pat `&)
          (let [rest-pat (. pattern (+ k 1))
                rest-val `(select ,k ((or table.unpack _G.unpack) ,val))
                subcondition (match-table `(pick-values 1 ,rest-val)
                                          rest-pat unifications match-pattern
                                          (without-multival opts))]
            (if (not (sym? rest-pat))
                (table.insert condition subcondition))
            (assert (= nil (. pattern (+ k 2)))
                    "expected & rest argument before last parameter")
            (table.insert bindings rest-pat)
            (table.insert bindings [rest-val]))
          (= k `&as)
          (do
            (table.insert bindings pat)
            (table.insert bindings val))
          (and (= :number (type k)) (= `&as pat))
          (do
            (assert (= nil (. pattern (+ k 2)))
                    "expected &as argument before last parameter")
            (table.insert bindings (. pattern (+ k 1)))
            (table.insert bindings val))
          ;; don't process the pattern right after &/&as; already got it
          (or (not= :number (type k)) (and (not= `&as (. pattern (- k 1)))
                                           (not= `& (. pattern (- k 1)))))
          (let [subval `(. ,val ,k)
                (subcondition subbindings) (match-pattern [subval] pat
                                                          unifications
                                                          (without-multival opts))]
            (table.insert condition subcondition)
            (each [_ b (ipairs subbindings)]
              (table.insert bindings b)))))
    (values condition bindings)))

(fn match-guard [vals condition guards unifications match-pattern opts]
  (if (= 0 (length guards))
    (match-pattern vals condition unifications opts)
    (let [(pcondition bindings) (match-pattern vals condition unifications opts)
          condition `(and ,(unpack guards))]
       (values `(and ,pcondition
                     (let ,bindings
                       ,condition)) bindings))))

(fn symbols-in-pattern [pattern]
  "gives the set of symbols inside a pattern"
  (if (list? pattern)
      (let [result {}]
        (each [_ child-pattern (ipairs pattern)]
          (each [name symbol (pairs (symbols-in-pattern child-pattern))]
            (tset result name symbol)))
        result)
      (sym? pattern)
      (if (and (not= pattern `or)
               (not= pattern `where)
               (not= pattern `?)
               (not= pattern `nil))
          {(tostring pattern) pattern}
          {})
      (= (type pattern) :table)
      (let [result {}]
        (each [key-pattern value-pattern (pairs pattern)]
          (each [name symbol (pairs (symbols-in-pattern key-pattern))]
            (tset result name symbol))
          (each [name symbol (pairs (symbols-in-pattern value-pattern))]
            (tset result name symbol)))
        result)
      {}))

(fn symbols-in-every-pattern [pattern-list unification?]
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
      (if (not (and unification? (in-scope? symbol)))
        symbol))))

(fn match-or [vals pattern guards unifications match-pattern opts]
  ;; if guards is present, this is a (where (or)) shape
  (let [bindings (symbols-in-every-pattern [(unpack pattern 2)] opts.unification?)]
    (if (= 0 (length bindings))
      ;; no bindings special case generates simple code
      (let [condition
            (fcollect [i 2 (length pattern) &into `(or)]
              (let [subpattern (. pattern i)
                    (subcondition subbindings) (match-pattern vals subpattern unifications opts)]
                subcondition))]
        (values
          (if (= 0 (length guards))
            condition
            `(and ,condition ,(unpack guards)))
          []))
      ;; case with bindings is handled specially, and returns three values instead of two
      (let [matched? (gensym :matched?)
            bindings-two (icollect [_ binding (ipairs bindings)]
                           (gensym (tostring binding)))
            the-actual-body `(if)]
        (for [i 2 (length pattern)]
          (let [subpattern (. pattern i)
                (subcondition subbindings) (match-guard vals subpattern guards {} match-pattern opts)]
            (table.insert the-actual-body subcondition)
            (table.insert the-actual-body `(let ,subbindings (values true ,(unpack bindings))))))
        (values matched?
                [`(,(unpack bindings)) `(values ,(unpack bindings-two))]
                [`(,matched? ,(unpack bindings-two)) the-actual-body])))))

(fn match-pattern [vals pattern unifications opts top-level?]
  "Take the AST of values and a single pattern and returns a condition
to determine if it matches as well as a list of bindings to
introduce for the duration of the body if it does match."

  ;; This function returns the following values (multival):
  ;; a "condition", which is an expression that determines whether the
  ;;   pattern should match,
  ;; a "bindings", which bind all of the symbols used in a pattern
  ;; an optional "pre-bindings", which is a list of bindings that happen
  ;;   before the condition and bindings are evaluated. These should only
  ;;   come from a (match-or). In this case there should be no recursion:
  ;;   the call stack should be match-condition > match-pattern > match-or 

  ;; we have to assume we're matching against multiple values here until we
  ;; know we're either in a multi-valued clause (in which case we know the #
  ;; of vals) or we're not, in which case we only care about the first one.
  (let [[val] vals]
    (if (or (and (sym? pattern) ; unification with outer locals (or nil)
                 (not= "_" (tostring pattern)) ; never unify _
                 (or (and opts.unification? (in-scope? pattern)) (= :nil (tostring pattern))))
            (and (multi-sym? pattern) opts.unification? (in-scope? (. (multi-sym? pattern) 1))))
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

        ;; where-or clause
        (and (list? pattern) (= (. pattern 1) `where) (list? (. pattern 2)) (= (. pattern 2 1) `or))
        (do
          (assert-compile top-level? "can't nest (where) pattern" pattern)
          (match-or vals (. pattern 2) [(unpack pattern 3)] unifications match-pattern opts))
        ;; or clause
        (and (list? pattern) (= (. pattern 1) `or))
        (do
          (assert-compile top-level? "can't nest (or) pattern" pattern)
          (match-or vals pattern [] unifications match-pattern opts))
        ;; where clause
        (and (list? pattern) (= (. pattern 1) `where))
        (do
          (assert-compile top-level? "can't nest (where) pattern" pattern)
          (match-guard vals (. pattern 2) [(unpack pattern 3)] unifications match-pattern opts))
        ;; guard clause
        (and (list? pattern) (= (. pattern 2) `?))
        (match-guard vals (. pattern 1) [(unpack pattern 3)] unifications match-pattern opts)
        ;; multi-valued patterns (represented as lists)
        (list? pattern)
        (do
          (assert-compile opts.multival? "can't nest multi-value destructuring" pattern)
          (match-values vals pattern unifications match-pattern opts))
        ;; table patterns
        (= (type pattern) :table)
        (match-table val pattern unifications match-pattern opts)
        ;; literal value
        (values `(= ,val ,pattern) []))))

(fn match-condition [vals clauses unification?]
  "Construct the actual `if` AST for the given match values and clauses."
  (when (not= 0 (% (length clauses) 2)) ; treat odd final clause as default
    (table.insert clauses (length clauses) (sym "_")))
  (let [out `(if)]
    (var tail out)
    (for [i 1 (length clauses) 2]
      (let [pattern (. clauses i)
            body (. clauses (+ i 1))
            (condition bindings pre-bindings) (match-pattern vals pattern {} {:multival? true : unification?} true)]
        (when pre-bindings
          (if (. tail 2)
            (let [newtail `()]
              (table.insert tail newtail)
              (set tail newtail)))
          (let [newtail `(if)]
            (tset tail 1 `let)
            (tset tail 2 pre-bindings)
            (tset tail 3 newtail)
            (set tail newtail)))
        (table.insert tail condition)
        (table.insert tail `(let ,bindings
                              ,body))))
    out))

(fn count-match-multival [pattern]
  (if (and (list? pattern) (= (. pattern 2) `?))
      (count-match-multival (. pattern 1))
      (and (list? pattern) (= (. pattern 1) `where))
      (count-match-multival (. pattern 2))
      (and (list? pattern) (= (. pattern 1) `or))
      (accumulate [longest 0
                   _ child-pattern (ipairs pattern)]
        (math.max longest (count-match-multival child-pattern)))
      (list? pattern)
      (length pattern)
      1))

(fn match-val-syms [clauses]
  "What is the length of the largest multi-valued clause? return a list of that many gensyms."
  (let [patterns (fcollect [i 1 (length clauses) 2]
                   (. clauses i))
        sym-count (accumulate [longest 0
                               _ pattern (ipairs patterns)]
                    (math.max longest (count-match-multival pattern)))]
    (fcollect [i 1 sym-count &into (list)]
      (gensym))))

(fn match* [val ...]
  "Perform pattern matching on val. See reference for details.

Syntax:

(match data-expression
  pattern body
  (where pattern guards*) body
  (or pattern patterns*) body
  (where (or pattern patterns*) guards*) body
  ;; legacy:
  (pattern ? guards*) body)"
  (assert (not= val nil) "missing subject")
  (assert (= 0 (math.fmod (select :# ...) 2))
          "expected even number of pattern/body pairs")
  (assert (not= 0 (select :# ...))
          "expected at least one pattern/body pair")
  (let [clauses [...]
        vals (match-val-syms clauses)]
    ;; protect against multiple evaluation of the value, bind against as
    ;; many values as we ever match against in the clauses.
    (list `let [vals val] (match-condition vals clauses true))))

(fn matchless* [val ...]
  "Perform pattern matching on val, without unifying on variables in local scope. See reference for details.

Syntax:

(match data-expression
  pattern body
  (where pattern guards*) body
  (or pattern patterns*) body
  (where (or pattern patterns*) guards*) body
  ;; legacy:
  (pattern ? guards*) body)"
  (assert (not= val nil) "missing subject")
  (assert (= 0 (math.fmod (select :# ...) 2))
          "expected even number of pattern/body pairs")
  (assert (not= 0 (select :# ...))
          "expected at least one pattern/body pair")
  (let [clauses [...]
        vals (match-val-syms clauses)]
    ;; protect against multiple evaluation of the value, bind against as
    ;; many values as we ever match against in the clauses.
    (list `let [vals val] (match-condition vals clauses false))))

(fn match-try-step [expr else pattern body ...]
  (if (= nil pattern body)
      expr
      ;; unlike regular match, we can't know how many values the value
      ;; might evaluate to, so we have to capture them all in ... via IIFE
      ;; to avoid double-evaluation.
      `((fn [...]
          (match ...
            ,pattern ,(match-try-step body else ...)
            ,(unpack else)))
        ,expr)))

(fn match-try* [expr pattern body ...]
  "Perform chained pattern matching for a sequence of steps which might fail.

The values from the initial expression are matched against the first pattern.
If they match, the first body is evaluated and its values are matched against
the second pattern, etc.

If there is a (catch pat1 body1 pat2 body2 ...) form at the end, any mismatch
from the steps will be tried against these patterns in sequence as a fallback
just like a normal match. If there is no catch, the mismatched values will be
returned as the value of the entire expression."
  (let [clauses [pattern body ...]
        last (. clauses (length clauses))
        catch (if (= `catch (and (= :table (type last)) (. last 1)))
                 (let [[_ & e] (table.remove clauses)] e) ; remove `catch sym
                 [`_# `...])]
    (assert (= 0 (math.fmod (length clauses) 2))
            "expected every pattern to have a body")
    (assert (= 0 (math.fmod (length catch) 2))
            "expected every catch pattern to have a body")
    (match-try-step expr catch (unpack clauses))))

{:match match*
 :matchless matchless*
 :match-try match-try*}
