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
      (if (or (sym? item "&into") (= :into item))
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
         (let [(k# v#) ,kv-expr]
           (if (and (not= k# nil) (not= v# nil))
             (tset tbl# k# v#))))
       tbl#)))

(fn seq-collect [how iter-tbl value-expr ...]
  "Common part between icollect and fcollect for producing sequential tables.

Iteration code only differs in using the for or each keyword, the rest
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

(fn accumulate-impl [for? iter-tbl body ...]
  (assert (and (sequence? iter-tbl) (<= 4 (length iter-tbl)))
          "expected initial value and iterator binding table")
  (assert (not= nil body) "expected body expression")
  (assert (= nil ...)
          "expected exactly one body expression. Wrap multiple expressions with do")
  (let [[accum-var accum-init] iter-tbl
        iter (sym (if for? "for" "each"))] ; accumulate or faccumulate?
    `(do
       (var ,accum-var ,accum-init)
       (,iter ,[(unpack iter-tbl 3)]
              (set ,accum-var ,body))
       ,(if (list? accum-var)
          (list (sym :values) (unpack accum-var))
          accum-var))))

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
  (accumulate-impl false iter-tbl body ...))

(fn faccumulate* [iter-tbl body ...]
  "Identical to accumulate, but after the accumulator the binding table is the
same as `for` instead of `each`. Like collect to fcollect, will iterate over a
numerical range like `for` rather than an iterator."
  (accumulate-impl true iter-tbl body ...))

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
        args-len (length args)
        has-internal-name? (sym? (. args 1))
        arglist (if has-internal-name? (. args 2) (. args 1))
        metadata-position (if has-internal-name? 3 2)
        has-metadata? (and (< metadata-position args-len)
                           (or (= :string (type (. args metadata-position)))
                               (utils.kv-table? (. args metadata-position))))
        arity-check-position (- 4 (if has-internal-name? 0 1)
                                (if has-metadata? 0 1))
        empty-body? (< args-len arity-check-position)]
    (fn check! [a]
      (if (table? a)
          (each [_ a (pairs a)] (check! a))
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
    (each [_ a (ipairs arglist)] (check! a))
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
 :faccumulate faccumulate*
 :partial partial*
 :lambda lambda*
 :λ lambda*
 :pick-args pick-args*
 :pick-values pick-values*
 :macro macro*
 :macrodebug macrodebug*
 :import-macros import-macros*}
