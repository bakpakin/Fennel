;; These macros are awkward because their definition cannot rely on the any
;; built-in macros, only special forms. (no when, no icollect, etc)

(fn copy [t]
  (let [out []]
    (each [_ v (ipairs t)] (table.insert out v))
    (setmetatable out (getmetatable t))))

(fn ->* [val ...]
  "Thread-first macro.
Take the first value and splice it into the second form as its first argument.
The value of the second form is spliced into the first arg of the third, etc."
  (var x val)
  (each [_ e (ipairs [...])]
    (let [elt (if (list? e) (copy e) (list e))]
      (table.insert elt 2 x)
      (set x elt)))
  x)

(fn ->>* [val ...]
  "Thread-last macro.
Same as ->, except splices the value into the last position of each form
rather than the first."
  (var x val)
  (each [_ e (ipairs [...])]
    (let [elt (if (list? e) (copy e) (list e))]
      (table.insert elt x)
      (set x elt)))
  x)

(fn -?>* [val ?e ...]
  "Nil-safe thread-first macro.
Same as -> except will short-circuit with nil when it encounters a nil value."
  (if (= nil ?e)
      val
      (let [el (if (list? ?e) (copy ?e) (list ?e))
            tmp (gensym)]
        (table.insert el 2 tmp)
        `(let [,tmp ,val]
           (if (not= nil ,tmp)
               (-?> ,el ,...)
               ,tmp)))))

(fn -?>>* [val ?e ...]
  "Nil-safe thread-last macro.
Same as ->> except will short-circuit with nil when it encounters a nil value."
  (if (= nil ?e)
      val
      (let [el (if (list? ?e) (copy ?e) (list ?e))
            tmp (gensym)]
        (table.insert el tmp)
        `(let [,tmp ,val]
           (if (not= ,tmp nil)
               (-?>> ,el ,...)
               ,tmp)))))

(fn ?dot [tbl ...]
  "Nil-safe table look up.
Same as . (dot), except will short-circuit with nil when it encounters
a nil value in any of subsequent keys."
  (let [head (gensym :t)
        lookups `(do
                   (var ,head ,tbl)
                   ,head)]
    (each [_ k (ipairs [...])]
      ;; Kinda gnarly to reassign in place like this, but it emits the best lua.
      ;; With this impl, it emits a flat, concise, and readable set of ifs
      (table.insert lookups (# lookups) `(if (not= nil ,head)
                                           (set ,head (. ,head ,k)))))
    lookups))

(fn doto* [val ...]
  "Evaluate val and splice it into the first argument of subsequent forms."
  (assert (not= val nil) "missing subject")
  (let [rebind? (or (not (sym? val))
                    (multi-sym? val))
        name (if rebind? (gensym)            val)
        form (if rebind? `(let [,name ,val]) `(do))]
    (each [_ elt (ipairs [...])]
      (let [elt (if (list? elt) (copy elt) (list elt))]
        (table.insert elt 2 name)
        (table.insert form elt)))
    (table.insert form name)
    form))

(fn when* [condition body1 ...]
  "Evaluate body for side-effects only when condition is truthy."
  (assert body1 "expected body")
  `(if ,condition
       (do
         ,body1
         ,...)))

(fn with-open* [closable-bindings ...]
  "Like `let`, but invokes (v:close) on each binding after evaluating the body.
The body is evaluated inside `xpcall` so that bound values will be closed upon
encountering an error before propagating it."
  (let [bodyfn `(fn []
                  ,...)
        closer `(fn close-handlers# [ok# ...]
                  (if ok# ... (error ... 0)))
        traceback `(. (or package.loaded.fennel debug) :traceback)]
    (for [i 1 (length closable-bindings) 2]
      (assert (sym? (. closable-bindings i))
              "with-open only allows symbols in bindings")
      (table.insert closer 4 `(: ,(. closable-bindings i) :close)))
    `(let ,closable-bindings
       ,closer
       (close-handlers# (_G.xpcall ,bodyfn ,traceback)))))

(fn extract-into [iter-tbl]
  (var (into iter-out found?) (values [] (copy iter-tbl)))
  (for [i (length iter-tbl) 2 -1]
    (let [item (. iter-tbl i)]
      (if (or (= `&into item)
              (= :into  item))
          (do
            (assert (not found?) "expected only one &into clause")
            (set found? true)
            (set into (. iter-tbl (+ i 1)))
            (table.remove iter-out i)
            (table.remove iter-out i)))))
  (assert (or (not found?) (sym? into) (table? into) (list? into))
          "expected table, function call, or symbol in &into clause")
  (values into iter-out))

(fn collect* [iter-tbl key-expr value-expr ...]
  "Return a table made by running an iterator and evaluating an expression that
returns key-value pairs to be inserted sequentially into the table.  This can
be thought of as a table comprehension. The body should provide two expressions
(used as key and value) or nil, which causes it to be omitted.

For example,
  (collect [k v (pairs {:apple \"red\" :orange \"orange\"})]
    (values v k))
returns
  {:red \"apple\" :orange \"orange\"}

Supports an &into clause after the iterator to put results in an existing table.
Supports early termination with an &until clause."
  (assert (and (sequence? iter-tbl) (<= 2 (length iter-tbl)))
          "expected iterator binding table")
  (assert (not= nil key-expr) "expected key and value expression")
  (assert (= nil ...)
          "expected 1 or 2 body expressions; wrap multiple expressions with do")
  (let [kv-expr (if (= nil value-expr) key-expr `(values ,key-expr ,value-expr))
        (into iter) (extract-into iter-tbl)]
    `(let [tbl# ,into]
       (each ,iter
         (match ,kv-expr
           (k# v#) (tset tbl# k# v#)))
       tbl#)))

(fn seq-collect [how iter-tbl value-expr ...]
  "Common part between icollect and fcollect for producing sequential tables.

Iteration code only deffers in using the for or each keyword, the rest
of the generated code is identical."
  (assert (not= nil value-expr) "expected table value expression")
  (assert (= nil ...)
          "expected exactly one body expression. Wrap multiple expressions in do")
  (let [(into iter) (extract-into iter-tbl)]
    `(let [tbl# ,into]
       ;; believe it or not, using a var here has a pretty good performance
       ;; boost: https://p.hagelb.org/icollect-performance.html
       (var i# (length tbl#))
       (,how ,iter
             (let [val# ,value-expr]
               (when (not= nil val#)
                 (set i# (+ i# 1))
                 (tset tbl# i# val#))))
       tbl#)))

(fn icollect* [iter-tbl value-expr ...]
  "Return a sequential table made by running an iterator and evaluating an
expression that returns values to be inserted sequentially into the table.
This can be thought of as a table comprehension. If the body evaluates to nil
that element is omitted.

For example,
  (icollect [_ v (ipairs [1 2 3 4 5])]
    (when (not= v 3)
      (* v v)))
returns
  [1 4 16 25]

Supports an &into clause after the iterator to put results in an existing table.
Supports early termination with an &until clause."
  (assert (and (sequence? iter-tbl) (<= 2 (length iter-tbl)))
          "expected iterator binding table")
  (seq-collect 'each iter-tbl value-expr ...))

(fn fcollect* [iter-tbl value-expr ...]
  "Return a sequential table made by advancing a range as specified by
for, and evaluating an expression that returns values to be inserted
sequentially into the table.  This can be thought of as a range
comprehension. If the body evaluates to nil that element is omitted.

For example,
  (fcollect [i 1 10 2]
    (when (not= i 3)
      (* i i)))
returns
  [1 25 49 81]

Supports an &into clause after the range to put results in an existing table.
Supports early termination with an &until clause."
  (assert (and (sequence? iter-tbl) (< 2 (length iter-tbl)))
          "expected range binding table")
  (seq-collect 'for iter-tbl value-expr ...))

(fn accumulate* [iter-tbl body ...]
  "Accumulation macro.

It takes a binding table and an expression as its arguments.  In the binding
table, the first form starts out bound to the second value, which is an initial
accumulator. The rest are an iterator binding table in the format `each` takes.

It runs through the iterator in each step of which the given expression is
evaluated, and the accumulator is set to the value of the expression. It
eventually returns the final value of the accumulator.

For example,
  (accumulate [total 0
               _ n (pairs {:apple 2 :orange 3})]
    (+ total n))
returns 5"
  (assert (and (sequence? iter-tbl) (<= 4 (length iter-tbl)))
          "expected initial value and iterator binding table")
  (assert (not= nil body) "expected body expression")
  (assert (= nil ...)
          "expected exactly one body expression. Wrap multiple expressions with do")
  (let [accum-var (. iter-tbl 1)
        accum-init (. iter-tbl 2)]
    `(do
       (var ,accum-var ,accum-init)
       (each ,[(unpack iter-tbl 3)]
         (set ,accum-var ,body))
       ,(if (list? accum-var)
            (list (sym :values) (unpack accum-var))
            accum-var))))

(fn double-eval-safe? [x type]
  (or (= :number type) (= :string type) (= :boolean type)
      (and (sym? x) (not (multi-sym? x)))))

(fn partial* [f ...]
  "Return a function with all arguments partially applied to f."
  (assert f "expected a function to partially apply")
  (let [bindings []
        args []]
    (each [_ arg (ipairs [...])]
      (if (double-eval-safe? arg (type arg))
        (table.insert args arg)
        (let [name (gensym)]
          (table.insert bindings name)
          (table.insert bindings arg)
          (table.insert args name))))
    (let [body (list f (unpack args))]
      (table.insert body _VARARG)
      ;; only use the extra let if we need double-eval protection
      (if (= 0 (length bindings))
          `(fn [,_VARARG] ,body)
          `(let ,bindings
             (fn [,_VARARG] ,body))))))

(fn pick-args* [n f]
  "Create a function of arity n that applies its arguments to f.

For example,
  (pick-args 2 func)
expands to
  (fn [_0_ _1_] (func _0_ _1_))"
  (if (and _G.io _G.io.stderr)
      (_G.io.stderr:write
       "-- WARNING: pick-args is deprecated and will be removed in the future.\n"))
  (assert (and (= (type n) :number) (= n (math.floor n)) (<= 0 n))
          (.. "Expected n to be an integer literal >= 0, got " (tostring n)))
  (let [bindings []]
    (for [i 1 n]
      (tset bindings i (gensym)))
    `(fn ,bindings
       (,f ,(unpack bindings)))))

(fn pick-values* [n ...]
  "Evaluate to exactly n values.

For example,
  (pick-values 2 ...)
expands to
  (let [(_0_ _1_) ...]
    (values _0_ _1_))"
  (assert (and (= :number (type n)) (<= 0 n) (= n (math.floor n)))
          (.. "Expected n to be an integer >= 0, got " (tostring n)))
  (let [let-syms (list)
        let-values (if (= 1 (select "#" ...)) ... `(values ,...))]
    (for [i 1 n]
      (table.insert let-syms (gensym)))
    (if (= n 0) `(values)
        `(let [,let-syms ,let-values]
           (values ,(unpack let-syms))))))

(fn lambda* [...]
  "Function literal with nil-checked arguments.
Like `fn`, but will throw an exception if a declared argument is passed in as
nil, unless that argument's name begins with a question mark."
  (let [args [...]
        has-internal-name? (sym? (. args 1))
        arglist (if has-internal-name? (. args 2) (. args 1))
        docstring-position (if has-internal-name? 3 2)
        has-docstring? (and (< docstring-position (length args))
                            (= :string (type (. args docstring-position))))
        arity-check-position (- 4 (if has-internal-name? 0 1)
                                (if has-docstring? 0 1))
        empty-body? (< (length args) arity-check-position)]
    (fn check! [a]
      (if (table? a)
          (each [_ a (pairs a)]
            (check! a))
          (let [as (tostring a)]
            (and (not (as:match "^?")) (not= as "&") (not= as "_")
                 (not= as "...") (not= as "&as")))
          (table.insert args arity-check-position
                        `(_G.assert (not= nil ,a)
                                    ,(: "Missing argument %s on %s:%s" :format
                                        (tostring a)
                                        (or a.filename :unknown)
                                        (or a.line "?"))))))

    (assert (= :table (type arglist)) "expected arg list")
    (each [_ a (ipairs arglist)]
      (check! a))
    (if empty-body?
        (table.insert args (sym :nil)))
    `(fn ,(unpack args))))

(fn macro* [name ...]
  "Define a single macro."
  (assert (sym? name) "expected symbol for macro name")
  (local args [...])
  `(macros {,(tostring name) (fn ,(unpack args))}))

(fn macrodebug* [form return?]
  "Print the resulting form after performing macroexpansion.
With a second argument, returns expanded form as a string instead of printing."
  (let [handle (if return? `do `print)]
    `(,handle ,(view (macroexpand form _SCOPE)))))

(fn import-macros* [binding1 module-name1 ...]
  "Bind a table of macros from each macro module according to a binding form.
Each binding form can be either a symbol or a k/v destructuring table.
Example:
  (import-macros mymacros                 :my-macros    ; bind to symbol
                 {:macro1 alias : macro2} :proj.macros) ; import by name"
  (assert (and binding1 module-name1 (= 0 (% (select "#" ...) 2)))
          "expected even number of binding/modulename pairs")
  (for [i 1 (select "#" binding1 module-name1 ...) 2]
    ;; delegate the actual loading of the macros to the require-macros
    ;; special which already knows how to set up the compiler env and stuff.
    ;; this is weird because require-macros is deprecated but it works.
    (let [(binding modname) (select i binding1 module-name1 ...)
          scope (get-scope)
          ;; if the module-name is an expression (and not just a string) we
          ;; patch our expression to have the correct source filename so
          ;; require-macros can pass it down when resolving the module-name.
          expr `(import-macros ,modname)
          filename (if (list? modname) (. modname 1 :filename) :unknown)
          _ (tset expr :filename filename)
          macros* (_SPECIALS.require-macros expr scope {} binding)]
      (if (sym? binding)
          ;; bind whole table of macros to table bound to symbol
          (tset scope.macros (. binding 1) macros*)
          ;; 1-level table destructuring for importing individual macros
          (table? binding)
          (each [macro-name [import-key] (pairs binding)]
            (assert (= :function (type (. macros* macro-name)))
                    (.. "macro " macro-name " not found in module "
                        (tostring modname)))
            (tset scope.macros import-key (. macros* macro-name))))))
  nil)

;;; Pattern matching

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
  (if (not= 0 (% (length clauses) 2)) ; treat odd final clause as default
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

{:-> ->*
 :->> ->>*
 :-?> -?>*
 :-?>> -?>>*
 :?. ?dot
 :doto doto*
 :when when*
 :with-open with-open*
 :collect collect*
 :icollect icollect*
 :fcollect fcollect*
 :accumulate accumulate*
 :partial partial*
 :lambda lambda*
 :pick-args pick-args*
 :pick-values pick-values*
 :macro macro*
 :macrodebug macrodebug*
 :import-macros import-macros*
 :match match-where
 :match-try match-try*}
