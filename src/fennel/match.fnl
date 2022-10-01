;;; Pattern matching
;; This is separated out so we can use the "core" macros during the
;; implementation of pattern matching.

(fn match-values [vals pattern unifications match-pattern]
  (let [condition `(and)
        bindings []]
    (each [i pat (ipairs pattern)]
      (let [(subcondition subbindings) (match-pattern [(. vals i)] pat
                                                      unifications)]
        (table.insert condition subcondition)
        (each [_ b (ipairs subbindings)]
          (table.insert bindings b))))
    (values condition bindings)))

(fn match-table [val pattern unifications match-pattern]
  (let [condition `(and (= (_G.type ,val) :table))
        bindings []]
    (each [k pat (pairs pattern)]
      (if (= pat `&)
          (let [rest-pat (. pattern (+ k 1))
                rest-val `(select ,k ((or table.unpack _G.unpack) ,val))
                subcondition (match-table `(pick-values 1 ,rest-val)
                                          rest-pat unifications match-pattern)]
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
                                                          unifications)]
            (table.insert condition subcondition)
            (each [_ b (ipairs subbindings)]
              (table.insert bindings b)))))
    (values condition bindings)))

(fn match-pattern [vals pattern unifications]
  "Take the AST of values and a single pattern and returns a condition
to determine if it matches as well as a list of bindings to
introduce for the duration of the body if it does match."
  ;; we have to assume we're matching against multiple values here until we
  ;; know we're either in a multi-valued clause (in which case we know the #
  ;; of vals) or we're not, in which case we only care about the first one.
  (let [[val] vals]
    (if (or (and (sym? pattern) ; unification with outer locals (or nil)
                 (not= "_" (tostring pattern)) ; never unify _
                 (or (in-scope? pattern) (= :nil (tostring pattern))))
            (and (multi-sym? pattern) (in-scope? (. (multi-sym? pattern) 1))))
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
        ;; guard clause
        (and (list? pattern) (= (. pattern 2) `?))
        (let [(pcondition bindings) (match-pattern vals (. pattern 1)
                                                   unifications)
              condition `(and ,(unpack pattern 3))]
          (values `(and ,pcondition
                        (let ,bindings
                          ,condition)) bindings))
        ;; multi-valued patterns (represented as lists)
        (list? pattern)
        (match-values vals pattern unifications match-pattern)
        ;; table patterns
        (= (type pattern) :table)
        (match-table val pattern unifications match-pattern)
        ;; literal value
        (values `(= ,val ,pattern) []))))

(fn match-condition [vals clauses]
  "Construct the actual `if` AST for the given match values and clauses."
  (when (not= 0 (% (length clauses) 2)) ; treat odd final clause as default
    (table.insert clauses (length clauses) (sym "_")))
  (let [out `(if)]
    (for [i 1 (length clauses) 2]
      (let [pattern (. clauses i)
            body (. clauses (+ i 1))
            (condition bindings) (match-pattern vals pattern {})]
        (table.insert out condition)
        (table.insert out `(let ,bindings
                             ,body))))
    out))

(fn match-val-syms [clauses]
  "How many multi-valued clauses are there? return a list of that many gensyms."
  (let [syms (list (gensym))]
    (for [i 1 (length clauses) 2]
      (let [clause (if (and (list? (. clauses i)) (= `? (. clauses i 2)))
                       (. clauses i 1)
                       (. clauses i))]
        (if (list? clause)
            (each [valnum (ipairs clause)]
              (if (not (. syms valnum))
                  (tset syms valnum (gensym)))))))
    syms))

(fn match* [val ...]
  ;; Old implementation of match macro, which doesn't directly support
  ;; `where' and `or'. New syntax is implemented in `match-where',
  ;; which simply generates old syntax and feeds it to `match*'.
  (let [clauses [...]
        vals (match-val-syms clauses)]
    ;; protect against multiple evaluation of the value, bind against as
    ;; many values as we ever match against in the clauses.
    (list `let [vals val] (match-condition vals clauses))))

;; Construction of old match syntax from new syntax

(fn partition-2 [seq]
  ;; Partition `seq` by 2.
  ;; If `seq` has odd amount of elements, the last one is dropped.
  ;;
  ;; Input: [1 2 3 4 5]
  ;; Output: [[1 2] [3 4]]
  (let [firsts []
        seconds []
        res []]
    (for [i 1 (length seq) 2]
      (let [first (. seq i)
            second (. seq (+ i 1))]
        (table.insert firsts (if (not= nil first) first `nil))
        (table.insert seconds (if (not= nil second) second `nil))))
    (each [i v1 (ipairs firsts)]
      (let [v2 (. seconds i)]
        (if (not= nil v2)
            (table.insert res [v1 v2]))))
    res))

(fn transform-or [[_ & pats] guards]
  ;; Transforms `(or pat pats*)` lists into match `guard` patterns.
  ;;
  ;; (or pat1 pat2), guard => [(pat1 ? guard) (pat2 ? guard)]
  (let [res []]
    (each [_ pat (ipairs pats)]
      (table.insert res (list pat `? (unpack guards))))
    res))

(fn transform-cond [cond]
  ;; Transforms `where` cond into sequence of `match` guards.
  ;;
  ;; pat => [pat]
  ;; (where pat guard) => [(pat ? guard)]
  ;; (where (or pat1 pat2) guard) => [(pat1 ? guard) (pat2 ? guard)]
  (if (and (list? cond) (= (. cond 1) `where))
      (let [second (. cond 2)]
        (if (and (list? second) (= (. second 1) `or))
            (transform-or second [(unpack cond 3)])
            :else
            [(list second `? (unpack cond 3))]))
      :else
      [cond]))

(fn match-where [val ...]
  "Perform pattern matching on val. See reference for details.

Syntax:

(match data-expression
  pattern body
  (where pattern guard guards*) body
  (where (or pattern patterns*) guard guards*) body)"
  (assert (not= val nil) "missing subject")
  (assert (= 0 (math.fmod (select :# ...) 2))
          "expected even number of pattern/body pairs")
  (assert (not= 0 (select :# ...))
          "expected at least one pattern/body pair")
  (let [conds-bodies (partition-2 [...])
        match-body []]
    (each [_ [cond body] (ipairs conds-bodies)]
      (each [_ cond (ipairs (transform-cond cond))]
        (table.insert match-body cond)
        (table.insert match-body body)))
    (match* val (unpack match-body))))

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

{:match match-where
 :match-try match-try*}
