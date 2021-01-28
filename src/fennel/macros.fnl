;; This module contains all the built-in Fennel macros. Unlike all the other
;; modules that are loaded by the old bootstrap compiler, this runs in the
;; compiler scope of the version of the compiler being defined.

;; The code for these macros is somewhat idiosyncratic because it cannot use any
;; macros which have not yet been defined.

;; TODO: some of these macros modify their arguments; we should stop doing that,
;; but in a way that preserves file/line metadata.

(fn ->* [val ...]
  "Thread-first macro.
Take the first value and splice it into the second form as its first argument.
The value of the second form is spliced into the first arg of the third, etc."
  (var x val)
  (each [_ e (ipairs [...])]
    (let [elt (if (list? e) e (list e))]
      (table.insert elt 2 x)
      (set x elt)))
  x)

(fn ->>* [val ...]
  "Thread-last macro.
Same as ->, except splices the value into the last position of each form
rather than the first."
  (var x val)
  (each [_ e (pairs [...])]
    (let [elt (if (list? e) e (list e))]
      (table.insert elt x)
      (set x elt)))
  x)

(fn -?>* [val ...]
  "Nil-safe thread-first macro.
Same as -> except will short-circuit with nil when it encounters a nil value."
  (if (= 0 (select "#" ...))
      val
      (let [els [...]
            e (table.remove els 1)
            el (if (list? e) e (list e))
            tmp (gensym)]
        (table.insert el 2 tmp)
        `(let [,tmp ,val]
           (if ,tmp
               (-?> ,el ,(unpack els))
               ,tmp)))))

(fn -?>>* [val ...]
  "Nil-safe thread-last macro.
Same as ->> except will short-circuit with nil when it encounters a nil value."
  (if (= 0 (select "#" ...))
      val
      (let [els [...]
            e (table.remove els 1)
            el (if (list? e) e (list e))
            tmp (gensym)]
        (table.insert el tmp)
        `(let [,tmp ,val]
           (if ,tmp
               (-?>> ,el ,(unpack els))
               ,tmp)))))

(fn doto* [val ...]
  "Evaluates val and splices it into the first argument of subsequent forms."
  (let [name (gensym)
        form `(let [,name ,val])]
    (each [_ elt (pairs [...])]
      (table.insert elt 2 name)
      (table.insert form elt))
    (table.insert form name)
    form))

(fn when* [condition body1 ...]
  "Evaluate body for side-effects only when condition is truthy."
  (assert body1 "expected body")
  `(if ,condition
       (do ,body1 ,...)))

(fn with-open* [closable-bindings ...]
  "Like `let`, but invokes (v:close) on each binding after evaluating the body.
The body is evaluated inside `xpcall` so that bound values will be closed upon
encountering an error before propagating it."
  (let [bodyfn    `(fn [] ,...)
        closer `(fn close-handlers# [ok# ...] (if ok# ...
                                                  (error ... 0)))
        traceback `(. (or package.loaded.fennel debug) :traceback)]
    (for [i 1 (# closable-bindings) 2]
      (assert (sym? (. closable-bindings i))
              "with-open only allows symbols in bindings")
      (table.insert closer 4 `(: ,(. closable-bindings i) :close)))
    `(let ,closable-bindings ,closer
          (close-handlers# (xpcall ,bodyfn ,traceback)))))

(fn collect* [iter-tbl key-value-expr ...]
  "Returns a table made by running an iterator and evaluating an expression
that returns key-value pairs to be inserted sequentially into the table.
This can be thought of as a \"table comprehension\". The provided key-value
expression must return either 2 values, or nil.

For example,
  (collect [k v (pairs {:apple \"red\" :orange \"orange\"})]
    (values v k))
returns
  {:red \"apple\" :orange \"orange\"}"
  (assert (and (sequence? iter-tbl) (>= (length iter-tbl) 2))
          "expected iterator binding table")
  (assert (not= nil key-value-expr)
          "expected key-value expression")
  (assert (= nil ...)
          "expected exactly one body expression. Wrap multiple expressions with do")
  `(let [tbl# {}]
     (each ,iter-tbl
       (match ,key-value-expr
         (k# v#) (tset tbl# k# v#)))
     tbl#))

(fn icollect* [iter-tbl value-expr ...]
  "Returns a sequential table made by running an iterator and evaluating an
expression that returns values to be inserted sequentially into the table.
This can be thought of as a \"list comprehension\".

For example,
  (icollect [_ v (ipairs [1 2 3 4 5])] (when (> v 2) (* v v)))
returns
  [9 16 25]"
  (assert (and (sequence? iter-tbl) (>= (length iter-tbl) 2))
          "expected iterator binding table")
  (assert (not= nil value-expr)
          "expected table value expression")
  (assert (= nil ...)
          "expected exactly one body expression. Wrap multiple expressions with do")
  `(let [tbl# []]
     (each ,iter-tbl
       (tset tbl# (+ (length tbl#) 1) ,value-expr))
     tbl#))

(fn partial* [f ...]
  "Returns a function with all arguments partially applied to f."
  (let [body (list f ...)]
    (table.insert body _VARARG)
    `(fn [,_VARARG] ,body)))

(fn pick-args* [n f]
  "Creates a function of arity n that applies its arguments to f.

For example,
  (pick-args 2 func)
expands to
  (fn [_0_ _1_] (func _0_ _1_))"
  (assert (and (= (type n) :number) (= n (math.floor n)) (>= n 0))
          "Expected n to be an integer literal >= 0.")
  (let [bindings []]
    (for [i 1 n] (tset bindings i (gensym)))
    `(fn ,bindings (,f ,(unpack bindings)))))

(fn pick-values* [n ...]
  "Like the `values` special, but emits exactly n values.

For example,
  (pick-values 2 ...)
expands to
  (let [(_0_ _1_) ...]
    (values _0_ _1_))"
  (assert (and (= :number (type n)) (>= n 0) (= n (math.floor n)))
          "Expected n to be an integer >= 0")
  (let [let-syms   (list)
        let-values (if (= 1 (select :# ...)) ... `(values ,...))]
    (for [i 1 n] (table.insert let-syms (gensym)))
    (if (= n 0) `(values)
        `(let [,let-syms ,let-values] (values ,(unpack let-syms))))))

(fn lambda* [...]
  "Function literal with arity checking.
Will throw an exception if a declared argument is passed in as nil, unless
that argument name begins with ?."
  (let [args [...]
        has-internal-name? (sym? (. args 1))
        arglist (if has-internal-name? (. args 2) (. args 1))
        docstring-position (if has-internal-name? 3 2)
        has-docstring? (and (> (# args) docstring-position)
                            (= :string (type (. args docstring-position))))
        arity-check-position (- 4 (if has-internal-name? 0 1)
                                (if has-docstring? 0 1))
        empty-body? (< (# args) arity-check-position)]
    (fn check! [a]
      (if (table? a)
          (each [_ a (pairs a)]
            (check! a))
          (let [as (tostring a)]
            (and (not (as:match "^?")) (not= as "&") (not= as "_") (not= as "...")))
          (table.insert args arity-check-position
                        `(assert (not= nil ,a)
                                 (string.format "Missing argument %s on %s:%s"
                                                ,(tostring a)
                                                ,(or a.filename "unknown")
                                                ,(or a.line "?"))))))
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
  `(macros { ,(tostring name) (fn ,(unpack args))}))

(fn macrodebug* [form return?]
  "Print the resulting form after performing macroexpansion.
With a second argument, returns expanded form as a string instead of printing."
  (let [handle (if return? `do `print)]
    `(,handle ,(view (macroexpand form _SCOPE)))))

(fn import-macros* [binding1 module-name1 ...]
  "Binds a table of macros from each macro module according to a binding form.
Each binding form can be either a symbol or a k/v destructuring table.
Example:
  (import-macros mymacros                 :my-macros    ; bind to symbol
                 {:macro1 alias : macro2} :proj.macros) ; import by name"
  (assert (and binding1 module-name1 (= 0 (% (select :# ...) 2)))
          "expected even number of binding/modulename pairs")
  (for [i 1 (select :# binding1 module-name1 ...) 2]
    (let [(binding modname) (select i binding1 module-name1 ...)
          ;; generate a subscope of current scope, use require-macros
          ;; to bring in macro module. after that, we just copy the
          ;; macros from subscope to scope.
          scope (get-scope)
          subscope (fennel.scope scope)]
      (_SPECIALS.require-macros `(require-macros ,modname) subscope {} ast)
      (if (sym? binding)
          ;; bind whole table of macros to table bound to symbol
          (do (tset scope.macros (. binding 1) {})
              (each [k v (pairs subscope.macros)]
                (tset (. scope.macros (. binding 1)) k v)))

          ;; 1-level table destructuring for importing individual macros
          (table? binding)
          (each [macro-name [import-key] (pairs binding)]
            (assert (= :function (type (. subscope.macros macro-name)))
                    (.. "macro " macro-name " not found in module "
                        (tostring modname)))
            (tset scope.macros import-key (. subscope.macros macro-name))))))
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
  (let [condition `(and (= (type ,val) :table))
        bindings []]
    (each [k pat (pairs pattern)]
      (if (and (sym? pat) (= "&" (tostring pat)))
          (do (assert (not (. pattern (+ k 2)))
                      "expected rest argument before last parameter")
              (table.insert bindings (. pattern (+ k 1)))
              (table.insert bindings [`(select ,k ((or table.unpack
                                                       _G.unpack)
                                                   ,val))]))
          (and (= :number (type k))
               (= "&" (tostring (. pattern (- k 1)))))
          nil ; don't process the pattern right after &; already got it
          (let [subval `(. ,val ,k)
                (subcondition subbindings) (match-pattern [subval] pat
                                                          unifications)]
            (table.insert condition subcondition)
            (each [_ b (ipairs subbindings)]
              (table.insert bindings b)))))
    (values condition bindings)))

(fn match-pattern [vals pattern unifications]
  "Takes the AST of values and a single pattern and returns a condition
to determine if it matches as well as a list of bindings to
introduce for the duration of the body if it does match."
  ;; we have to assume we're matching against multiple values here until we
  ;; know we're either in a multi-valued clause (in which case we know the #
  ;; of vals) or we're not, in which case we only care about the first one.
  (let [[val] vals]
    (if (or (and (sym? pattern) ; unification with outer locals (or nil)
                 (not= :_ (tostring pattern)) ; never unify _
                 (or (in-scope? pattern)
                     (= :nil (tostring pattern))))
            (and (multi-sym? pattern)
                 (in-scope? (. (multi-sym? pattern) 1))))
        (values `(= ,val ,pattern) [])
        ;; unify a local we've seen already
        (and (sym? pattern) (. unifications (tostring pattern)))
        (values `(= ,(. unifications (tostring pattern)) ,val) [])
        ;; bind a fresh local
        (sym? pattern)
        (let [wildcard? (: (tostring pattern) :find "^_")]
          (if (not wildcard?) (tset unifications (tostring pattern) val))
          (values (if (or wildcard? (string.find (tostring pattern) "^?"))
                      true `(not= ,(sym :nil) ,val))
                  [pattern val]))
        ;; guard clause
        (and (list? pattern) (sym? (. pattern 2)) (= :? (tostring (. pattern 2))))
        (let [(pcondition bindings) (match-pattern vals (. pattern 1)
                                                   unifications)
              condition `(and ,pcondition)]
          (for [i 3 (# pattern)] ; splice in guard clauses
            (table.insert condition (. pattern i)))
          (values `(let ,bindings ,condition) bindings))

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
      (table.insert clauses (length clauses) (sym :_)))
  (let [out `(if)]
    (for [i 1 (length clauses) 2]
      (let [pattern (. clauses i)
            body (. clauses (+ i 1))
            (condition bindings) (match-pattern vals pattern {})]
        (table.insert out condition)
        (table.insert out `(let ,bindings ,body))))
    out))

(fn match-val-syms [clauses]
  "How many multi-valued clauses are there? return a list of that many gensyms."
  (let [syms (list (gensym))]
    (for [i 1 (length clauses) 2]
      (if (list? (. clauses i))
          (each [valnum (ipairs (. clauses i))]
            (if (not (. syms valnum))
                (tset syms valnum (gensym))))))
    syms))

(fn match* [val ...]
  "Perform pattern matching on val. See reference for details."
  (let [clauses [...]
        vals (match-val-syms clauses)]
    ;; protect against multiple evaluation of the value, bind against as
    ;; many values as we ever match against in the clauses.
    (list `let [vals val]
          (match-condition vals clauses))))

{:-> ->* :->> ->>* :-?> -?>* :-?>> -?>>*
 :doto doto* :when when* :with-open with-open*
 :collect collect* :icollect icollect*
 :partial partial* :lambda lambda*
 :pick-args pick-args* :pick-values pick-values*
 :macro macro* :macrodebug macrodebug* :import-macros import-macros*
 :match match*}
