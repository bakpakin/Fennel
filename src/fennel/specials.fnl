;; This module contains all the special forms; all built in Fennel constructs
;; which cannot be implemented as macros. It also contains some core compiler
;; functionality which is kept in this module for circularity reasons.

(local {: pack : unpack &as utils} (require :fennel.utils))
(local view (require :fennel.view))
(local parser (require :fennel.parser))
(local compiler (require :fennel.compiler))

(local SPECIALS compiler.scopes.global.specials)

(fn str1 [x] (tostring (. x 1)))

(fn wrap-env [env]
  "Convert a fennel environment table to a Lua environment table.
This means automatically unmangling globals when getting a value,
and mangling values when setting a value. This means the original env
will see its values updated as expected, regardless of mangling rules."
  (setmetatable []
                {:__index (fn [_ key]
                            (if (utils.string? key)
                                (. env (compiler.global-unmangling key))
                                (. env key)))
                 :__newindex (fn [_ key value]
                               (if (utils.string? key)
                                   (tset env (compiler.global-unmangling key)
                                         value)
                                   (tset env key value)))
                 ;; manually in 5.1
                 :__pairs (fn []
                            (values next
                                    (collect [k v (utils.stablepairs env)]
                                      (values (if (utils.string? k)
                                                  (compiler.global-unmangling k)
                                                  k) v))
                                    nil))}))

(fn fennel-module-name [] (or utils.root.options.moduleName :fennel))

(fn current-global-names [?env]
  ;; if there's a metatable on ?env, we need to make sure it's one that has a
  ;; __pairs metamethod, otherwise we give up entirely on globals checking.
  (let [mt (case (getmetatable ?env)
             ;; newer lua versions know about __pairs natively but not 5.1
             {:__pairs mtpairs} (collect [k v (mtpairs ?env)] (values k v))
             nil (or ?env _G))]
    (and mt (icollect [k (utils.stablepairs mt)]
              (compiler.global-unmangling k)))))

(fn load-code [code ?env ?filename]
  "Load Lua code with an environment in all recent Lua versions"
  (let [env (or ?env (rawget _G :_ENV) _G)]
    (case (values (rawget _G :setfenv) (rawget _G :loadstring))
      (setfenv loadstring) (let [f (assert (loadstring code ?filename))]
                             (doto f (setfenv env)))
      _ (assert (load code ?filename :t env)))))

(fn v->docstring [tgt]
  (-> (compiler.metadata:get tgt :fnl/docstring)
      (or "#<undocumented>") (: :gsub "\n$" "") (: :gsub "\n" "\n  ")))

(fn doc* [tgt name]
  "Return a docstring for tgt."
  (assert (= :string (type name)) "name must be a string")
  (if (not tgt)
      (.. name " not found")
      (or (= (type tgt) :function)
          (case (getmetatable tgt) {: __call} (= :function (type __call))))
      (let [elts [name (unpack (or (compiler.metadata:get tgt :fnl/arglist)
                                   ["#<unknown-arguments>"]))]]
        (string.format "(%s)\n  %s" (table.concat elts " ") (v->docstring tgt)))
      (string.format "%s\n  %s" name (v->docstring tgt))))

;; TODO: replace this with using the special fn's own docstring
(fn doc-special [name arglist docstring body-form?]
  "Add a docstring to a special form."
  (tset compiler.metadata (. SPECIALS name)
        {:fnl/arglist arglist :fnl/docstring docstring :fnl/body-form? body-form?}))

(fn compile-do [ast scope parent ?start]
  "Compile a list of forms for side effects."
  (let [start (or ?start 2)
        len (length ast)
        sub-scope (compiler.make-scope scope)]
    (for [i start len]
      (compiler.compile1 (. ast i) sub-scope parent {:nval 0}))))

(fn SPECIALS.do [ast scope parent opts ?start ?chunk ?sub-scope ?pre-syms]
  "Implements a do statement, starting at the 'start'-th element.
By default, start is 2."
  (let [start (or ?start 2)
        sub-scope (or ?sub-scope (compiler.make-scope scope))
        chunk (or ?chunk [])
        len (length ast)
        retexprs {:returned true}]
    (utils.hook :pre-do ast sub-scope)
    (fn compile-body [outer-target outer-tail outer-retexprs]
      (for [i start len]
        (let [subopts {:nval (or (and (not= i len) 0) opts.nval)
                       :tail (or (and (= i len) outer-tail) nil)
                       :target (or (and (= i len) outer-target) nil)}
              _ (utils.propagate-options opts subopts)
              subexprs (compiler.compile1 (. ast i) sub-scope chunk subopts)]
          (when (not= i len)
            (compiler.keep-side-effects subexprs parent nil (. ast i)))))
      (compiler.emit parent chunk ast)
      (compiler.emit parent :end ast)
      (utils.hook :do ast sub-scope)
      (or outer-retexprs retexprs))

    ;; See if we need special handling to get the return values of the do block
    (if (or opts.target (= opts.nval 0) opts.tail)
        (do
          (compiler.emit parent :do ast)
          (compile-body opts.target opts.tail))
        opts.nval
        ;; generate a local target
        (let [syms []]
          (for [i 1 opts.nval]
            (let [s (or (and ?pre-syms (. ?pre-syms i)) (compiler.gensym scope))]
              (tset syms i s)
              (tset retexprs i (utils.expr s :sym))))
          (let [outer-target (table.concat syms ", ")]
            (compiler.emit parent (string.format "local %s" outer-target) ast)
            (compiler.emit parent :do ast)
            (compile-body outer-target opts.tail)))
        ;; we will use an IIFE for the do
        (let [fname (compiler.gensym scope)
              fargs (if scope.vararg "..." "")]
          (compiler.emit parent
                         (string.format "local function %s(%s)" fname fargs) ast)
          (compile-body nil true
                        (utils.expr (.. fname "(" fargs ")") :statement))))))

(doc-special :do ["..."] "Evaluate multiple forms; return last value." true)

;; Helper iterator to deal with (values) in operators
;; When called on an ast like (my-call arg1 arg2 (values arg3 arg4))
;; iter-args will yield arg1, arg2, arg3, then arg4
(fn iter-args [ast]
  (var (ast len i) (values ast (length ast) 1))
  (fn []
    (set i (+ 1 i))
    (while (and (= i len) (utils.call-of? (. ast i) :values))
      (set ast (. ast i))
      (set len (length ast))
      (set i 2))
    (values (. ast i) (= nil (. ast (+ i 1))))))

(fn SPECIALS.values [ast scope parent]
  (let [exprs []]
    (each [subast last? (iter-args ast)]
      (let [subexprs (compiler.compile1 subast scope parent
                                        {:nval (and (not last?) 1)})]
        (table.insert exprs (. subexprs 1))
        (when last?
          (for [j 2 (length subexprs)]
            (table.insert exprs (. subexprs j))))))
    exprs))

(doc-special :values ["..."]
             "Return multiple values from a function. Must be in tail position.")

(fn ->stack [stack tbl]
  ;; append all keys and values of the table to the stack
  (each [k v (pairs tbl)]
    (doto stack (table.insert k) (table.insert v)))
  stack)

(fn literal? [val]
  ;; checks if value doesn't contain any list expr.  Lineriazes nested
  ;; tables into a stack, traversing it unil it meets a list or the
  ;; stack is exhausted.
  (var res true)
  (if (utils.list? val)
      (set res false)
      (utils.table? val)
      (let [stack (->stack [] val)]
        (each [_ elt (ipairs stack)
               :until (not res)]
          (if (utils.list? elt)
              (set res false)
              (utils.table? elt)
              (->stack stack elt)))))
  res)

(fn compile-value [v]
  ;; compiles literal value to a string
  (let [opts {:nval 1 :tail false}
        scope (compiler.make-scope)
        chunk []
        [[v]] (compiler.compile1 v scope chunk opts)]
    v))

(fn insert-meta [meta k v]
  ;; prepares the key and compiles the value if necessary and inserts
  ;; it to the metadata sequence: (insert-meta [] :foo {:bar [1 2 3]})
  ;; produces ["\"foo\"" "{bar = {1, 2, 3}}"]
  (let [view-opts {:escape-newlines? true
                   :line-length math.huge
                   :one-line? true}]
    (compiler.assert
     (= (type k) :string)
     (: "expected string keys in metadata table, got: %s"
        :format (view k view-opts)))
    (compiler.assert
     (literal? v)
     (: "expected literal value in metadata table, got: %s %s"
        :format (view k view-opts) (view v view-opts)))
    (doto meta
      (table.insert (view k))
      (table.insert (if (= :string (type v))
                        (view v view-opts)
                        (compile-value v))))))

(fn insert-arglist [meta arg-list]
  ;; Inserts a properly formatted arglist to the metadata table.  Does
  ;; double viewing to quote the resulting string after first view
  (let [opts {:one-line? true :escape-newlines? true :line-length math.huge}
        view-args (icollect [_ arg (ipairs arg-list)]
                    (view (view arg opts)))]
    (doto meta
      (table.insert "\"fnl/arglist\"")
      (table.insert
       (.. "{" (table.concat view-args ", ") "}")))))

(fn set-fn-metadata [f-metadata parent fn-name]
  (when utils.root.options.useMetadata
    (let [meta-fields []]
      (each [k v (utils.stablepairs f-metadata)]
        (if (= k :fnl/arglist)
            (insert-arglist meta-fields v)
            (insert-meta meta-fields k v)))
      (if (= (type utils.root.options.useMetadata) :string)
          (compiler.emit parent
                         (: "%s:setall(%s, %s)" :format utils.root.options.useMetadata
                            fn-name (table.concat meta-fields ", ")))
          (let [meta-str (: "require(\"%s\").metadata" :format (fennel-module-name))]
            (compiler.emit parent
                           (: "pcall(function() %s:setall(%s, %s) end)" :format
                              meta-str fn-name (table.concat meta-fields ", "))))))))

(fn get-fn-name [ast scope fn-name multi]
  (if (and fn-name (not= (. fn-name 1) :nil))
      (values (if (not multi)
                  (compiler.declare-local fn-name scope ast)
                  (. (compiler.symbol-to-expression fn-name scope) 1))
              (not multi) 3)
      (values nil true 2)))

(fn compile-named-fn [ast f-scope f-chunk parent index fn-name local?
                      arg-name-list f-metadata]
  ;; anonymous functions use this path after a name has been generated
  (utils.hook :pre-fn ast f-scope parent)
  (for [i (+ index 1) (length ast)]
    (compiler.compile1 (. ast i) f-scope f-chunk
                       {:nval (or (and (not= i (length ast)) 0) nil)
                        :tail (= i (length ast))}))
  (compiler.emit parent
                 (string.format (if local? "local function %s(%s)"
                                    "%s = function(%s)")
                                fn-name (table.concat arg-name-list ", "))
                 ast)
  (compiler.emit parent f-chunk ast)
  (compiler.emit parent :end ast)
  (set-fn-metadata f-metadata parent fn-name)
  (utils.hook :fn ast f-scope parent)
  (utils.expr fn-name :sym))

(fn compile-anonymous-fn [ast f-scope f-chunk parent index arg-name-list
                          f-metadata scope]
  ;; TODO: eventually compile this to an actual function value instead of
  ;; binding it to a local and using the symbol. the difficulty here is that
  ;; a function is a chunk with many lines, and the current representation of
  ;; an expr can only be a string, making it difficult to pass around without
  ;; losing line numbering information.
  (let [fn-name (compiler.gensym scope)]
    (compile-named-fn ast f-scope f-chunk parent index fn-name true
                      arg-name-list f-metadata)))

(fn maybe-metadata [ast pred handler mt index]
  ;; check if conditions for metadata literal are met.  The index must
  ;; not be the last in the ast, and the expression at the index must
  ;; conform to pred.  If conditions are met the handler is called
  ;; with metadata table and expression.  Returns metadata table and
  ;; an index.
  (let [index* (+ index 1)
        index*-before-ast-end? (< index* (length ast))
        expr (. ast index*)]
    (if (and index*-before-ast-end? (pred expr))
        (values (handler mt expr) index*)
        (values mt index))))

(fn get-function-metadata [ast arg-list index]
  ;; Get function metadata from ast and put it in a table.  Detects if
  ;; the next expression after the argument list is either a string or
  ;; a table, and copies values into function metadata table.  If it
  ;; is a string, checks if the next one is a table and combines them.
  (->> (values {:fnl/arglist arg-list} index)
       (maybe-metadata ast utils.string?
                       #(doto $1 (tset :fnl/docstring $2)))
       (maybe-metadata ast utils.kv-table?
                       #(collect [k v (pairs $2) :into $1]
                          (values k v)))))

(fn SPECIALS.fn [ast scope parent opts]
  (let [f-scope (doto (compiler.make-scope scope)
                  (tset :vararg false))
        f-chunk []
        fn-sym (utils.sym? (. ast 2))
        multi (and fn-sym (utils.multi-sym? (. fn-sym 1)))
        (fn-name local? index) (get-fn-name ast scope fn-sym multi opts)
        arg-list (compiler.assert (utils.table? (. ast index))
                                  "expected parameters table" ast)]
    (compiler.assert (or (not multi) (not multi.multi-sym-method-call))
                     (.. "unexpected multi symbol " (tostring fn-name)) fn-sym)
    (when (and multi (not (. scope.symmeta (. multi 1)))
               (not (compiler.global-allowed? (. multi 1))))
      (compiler.assert nil (.. "expected local table " (. multi 1)) (. ast 2)))
    (fn destructure-arg [arg]
      (let [raw (utils.sym (compiler.gensym scope))
            declared (compiler.declare-local raw f-scope ast)]
        (compiler.destructure arg raw ast f-scope f-chunk
                              {:declaration true
                               :nomulti true
                               :symtype :arg})
        declared))

    (fn destructure-amp [i]
      (compiler.assert (= i (- (length arg-list) 1))
                       "expected rest argument before last parameter"
                       (. arg-list (+ i 1)) arg-list)
      (set f-scope.vararg true)
      (compiler.destructure (. arg-list (length arg-list)) [(utils.varg)]
                            ast f-scope f-chunk
                            {:declaration true
                             :nomulti true
                             :symtype :arg})
      "...")

    (fn get-arg-name [arg i]
      (if f-scope.vararg nil ; if we already handled & rest
          (utils.varg? arg)
          (do
            (compiler.assert (= arg (. arg-list (length arg-list)))
                             "expected vararg as last parameter" ast)
            (set f-scope.vararg true)
            "...")
          (utils.sym? arg :&) (destructure-amp i)
          (and (utils.sym? arg) (not= (tostring arg) :nil)
               (not (utils.multi-sym? (tostring arg))))
          (compiler.declare-local arg f-scope ast)
          (utils.table? arg) (destructure-arg arg)
          (compiler.assert false
                           (: "expected symbol for function parameter: %s"
                              :format (tostring arg))
                           (. ast index))))

    (let [arg-name-list (icollect [i a (ipairs arg-list)] (get-arg-name a i))
          (f-metadata index) (get-function-metadata ast arg-list index)]
      (if fn-name
          (compile-named-fn ast f-scope f-chunk parent index fn-name local?
                            arg-name-list f-metadata)
          (compile-anonymous-fn ast f-scope f-chunk parent index arg-name-list
                                f-metadata scope)))))

(doc-special :fn [:?name :args :?docstring :...]
             "Function syntax. May optionally include a name and docstring or a metadata table.
If a name is provided, the function will be bound in the current scope.
When called with the wrong number of args, excess args will be discarded
and lacking args will be nil, use lambda for arity-checked functions." true)

;; FORBIDDEN KNOWLEDGE:
;; (lua "print('hello!')") -> prints hello, evaluates to nil
;; (lua "print 'hello!'" "10") -> prints hello, evaluates to the number 10
;; (lua nil "{1,2,3}") -> Evaluates to a table literal
(fn SPECIALS.lua [ast _ parent]
  (compiler.assert (or (= (length ast) 2) (= (length ast) 3))
                   "expected 1 or 2 arguments" ast)
  (when (not= :nil (-?> (utils.sym? (. ast 2)) tostring))
    (table.insert parent {: ast :leaf (tostring (. ast 2))}))
  (when (not= :nil (-?> (utils.sym? (. ast 3)) tostring))
    (tostring (. ast 3))))

(fn dot [ast scope parent]
  (compiler.assert (< 1 (length ast)) "expected table argument" ast)
  (let [len (length ast)
        lhs-node (compiler.macroexpand (. ast 2) scope)
        [lhs] (compiler.compile1 lhs-node scope parent {:nval 1})]
    (if (= len 2)
        (tostring lhs)
        (let [indices []]
          (for [i 3 len]
            (let [index (. ast i)]
              (if (and (utils.string? index)
                       (utils.valid-lua-identifier? index))
                  (table.insert indices (.. "." index))
                  (let [[index] (compiler.compile1 index scope parent {:nval 1})]
                    (table.insert indices (.. "[" (tostring index) "]"))))))
          ;; Extra parens are needed if the target is a literal
          (if (or (not (or (utils.sym? lhs-node)
                           (utils.list? lhs-node)))
                  (= :nil (tostring lhs-node)))
              (.. "(" (tostring lhs) ")" (table.concat indices))
              (.. (tostring lhs) (table.concat indices)))))))

(tset SPECIALS "." dot)

(doc-special "." [:tbl :key1 "..."]
             "Look up key1 in tbl table. If more args are provided, do a nested lookup.")

(fn SPECIALS.global [ast scope parent]
  (compiler.assert (= (length ast) 3) "expected name and value" ast)
  (compiler.destructure (. ast 2) (. ast 3) ast scope parent
                        {:forceglobal true :nomulti true :symtype :global})
  nil)

(doc-special :global [:name :val] "Set name as a global with val. Deprecated.")

(fn SPECIALS.set [ast scope parent]
  (compiler.assert (= (length ast) 3) "expected name and value" ast)
  (compiler.destructure (. ast 2) (. ast 3) ast scope parent
                        {:noundef true :symtype :set})
  nil)

(doc-special :set [:name :val]
             "Set a local variable to a new value. Only works on locals using var.")

(fn set-forcibly!* [ast scope parent]
  (compiler.assert (= (length ast) 3) "expected name and value" ast)
  (compiler.destructure (. ast 2) (. ast 3) ast scope parent
                        {:forceset true :symtype :set})
  nil)

(set SPECIALS.set-forcibly! set-forcibly!*)

(fn local* [ast scope parent opts]
  (compiler.assert (or (= 0 opts.nval) opts.tail) "can't introduce local here" ast)
  (compiler.assert (= (length ast) 3) "expected name and value" ast)
  (compiler.destructure (. ast 2) (. ast 3) ast scope parent
                        {:declaration true :nomulti true :symtype :local})
  nil)

(set SPECIALS.local local*)

(doc-special :local [:name :val] "Introduce new top-level immutable local.")

(fn SPECIALS.var [ast scope parent opts]
  (compiler.assert (or (= 0 opts.nval) opts.tail) "can't introduce var here" ast)
  (compiler.assert (= (length ast) 3) "expected name and value" ast)
  (compiler.destructure (. ast 2) (. ast 3) ast scope parent
                        {:declaration true
                         :isvar true
                         :nomulti true
                         :symtype :var})
  nil)

(doc-special :var [:name :val] "Introduce new mutable local.")

(fn kv? [t] (. (icollect [k (pairs t)] (if (not= :number (type k)) k)) 1))

(fn SPECIALS.let [[_ bindings &as ast] scope parent opts]
  (compiler.assert (and (utils.table? bindings) (not (kv? bindings)))
                   "expected binding sequence" (or bindings (. ast 1)))
  (compiler.assert (= (% (length bindings) 2) 0)
                   "expected even number of name/value bindings" bindings)
  (compiler.assert (<= 3 (length ast)) "expected body expression" (. ast 1))
  ;; we have to gensym the binding for the let body's return value before
  ;; compiling the binding vector, otherwise there's a possibility to conflict
  (let [pre-syms (fcollect [_ 1 (or opts.nval 0)] (compiler.gensym scope))
        sub-scope (compiler.make-scope scope)
        sub-chunk []]
    (for [i 1 (length bindings) 2]
      (compiler.destructure (. bindings i) (. bindings (+ i 1)) ast sub-scope
                            sub-chunk
                            {:declaration true :nomulti true :symtype :let}))
    (SPECIALS.do ast scope parent opts 3 sub-chunk sub-scope pre-syms)))

(doc-special :let [[:name1 :val1 :... :nameN :valN] :...]
             "Introduces a new scope in which a given set of local bindings are used."
             true)

(fn get-prev-line [parent]
  (if (= :table (type parent))
      (get-prev-line (or parent.leaf (. parent (length parent))))
      (or parent "")))

(fn needs-separator? [root prev-line]
  (and (root:match "^%(") prev-line (not (prev-line:find " end$"))))

(fn SPECIALS.tset [ast scope parent]
  (compiler.assert (< 3 (length ast))
                   "expected table, key, and value arguments" ast)
  (compiler.assert (and (not= (type (. ast 2)) "boolean")
                        (not= (type (. ast 2)) "number"))
                   "cannot set field of literal value" ast)
  (let [root (str1 (compiler.compile1 (. ast 2) scope parent {:nval 1}))
        ;; table, string, and varg need to be wrapped
        root (if (root:match "^[.{\"]") (string.format "(%s)" root) root)
        keys (fcollect [i 3 (- (length ast) 1)]
               (str1 (compiler.compile1 (. ast i) scope parent {:nval 1})))
        value (str1 (compiler.compile1 (. ast (length ast)) scope parent {:nval 1}))
        fmtstr (if (needs-separator? root (get-prev-line parent))
                   "do end %s[%s] = %s"
                   "%s[%s] = %s")]
    (compiler.emit parent (fmtstr:format root (table.concat keys "][") value) ast)))

(doc-special :tset [:tbl :key1 "..." :keyN :val]
             "Set the value of a table field. Deprecated in favor of set.")

(fn calculate-if-target [scope opts]
  (if (not (or opts.tail opts.target opts.nval))
      (values :iife true nil)
      (and opts.nval (not= opts.nval 0) (not opts.target))
      (let [accum []
            target-exprs []]
        ;; We need to create a target
        (for [i 1 opts.nval]
          (let [s (compiler.gensym scope)]
            (tset accum i s)
            (tset target-exprs i (utils.expr s :sym))))
        (values :target opts.tail (table.concat accum ", ") target-exprs))
      (values :none opts.tail opts.target)))

;; TODO: refactor; too long!
(fn if* [ast scope parent opts]
  (compiler.assert (< 2 (length ast)) "expected condition and body" ast)

  ;; Remove redundant "true" conditions
  (when (and (= 1 (% (length ast) 2))
             (= (. ast (- (length ast) 1)) true))
    (table.remove ast (- (length ast) 1)))

  ;; Implicit else becomes nil
  (when (= 1 (% (length ast) 2))
    (table.insert ast (utils.sym :nil)))

  (if (= (length ast) 2)
    ;; defer to "do" if all the branches have been deleted
    (SPECIALS.do (utils.list (utils.sym :do) (. ast 2)) scope parent opts)
    (let [do-scope (compiler.make-scope scope)
          branches []
          (wrapper inner-tail inner-target target-exprs) (calculate-if-target
                                                          scope opts)
          body-opts {:nval opts.nval :tail inner-tail :target inner-target}]
      (fn compile-body [i]
        (let [chunk []
              cscope (compiler.make-scope do-scope)]
          (compiler.keep-side-effects (compiler.compile1 (. ast i) cscope chunk
                                                         body-opts)
                                      chunk nil (. ast i))
          {: chunk :scope cscope}))
      (for [i 2 (- (length ast) 1) 2]
        (let [condchunk []
              [cond] (compiler.compile1 (. ast i) do-scope condchunk {:nval 1})
              branch (compile-body (+ i 1))]
          (set branch.cond cond)
          (set branch.condchunk condchunk)
          (set branch.nested (and (not= i 2) (= (next condchunk nil) nil)))
          (table.insert branches branch)))
      ;; Emit code
      (let [else-branch (compile-body (length ast))
            s (compiler.gensym scope)
            buffer []]
        (var last-buffer buffer)
        (for [i 1 (length branches)]
          (let [branch (. branches i)
                fstr (if (not branch.nested) "if %s then" "elseif %s then")
                cond (tostring branch.cond)
                cond-line (fstr:format cond)]
            (if branch.nested
                (compiler.emit last-buffer branch.condchunk ast)
                (each [_ v (ipairs branch.condchunk)]
                  (compiler.emit last-buffer v ast)))
            (compiler.emit last-buffer cond-line ast)
            (compiler.emit last-buffer branch.chunk ast)
            (if (= i (length branches))
                (do
                  (compiler.emit last-buffer :else ast)
                  (compiler.emit last-buffer else-branch.chunk ast)
                  (compiler.emit last-buffer :end ast))
                (not (. (. branches (+ i 1)) :nested))
                (let [next-buffer []]
                  (compiler.emit last-buffer :else ast)
                  (compiler.emit last-buffer next-buffer ast)
                  (compiler.emit last-buffer :end ast)
                  (set last-buffer next-buffer)))))
        ;; Emit if
        (if (= wrapper :iife) ; unavoidable IIFE due to statement/expression
            (let [iifeargs (or (and scope.vararg "...") "")]
              (compiler.emit parent
                             (: "local function %s(%s)" :format (tostring s)
                                iifeargs) ast)
              (compiler.emit parent buffer ast)
              (compiler.emit parent :end ast)
              (utils.expr (: "%s(%s)" :format (tostring s) iifeargs) :statement))
            (= wrapper :none) ; Splice result right into code
            (do
              (for [i 1 (length buffer)]
                (compiler.emit parent (. buffer i) ast))
              {:returned true})
            ;; wrapper is target
            (do
              (compiler.emit parent (: "local %s" :format inner-target) ast)
              (for [i 1 (length buffer)]
                (compiler.emit parent (. buffer i) ast))
              target-exprs))))))

(set SPECIALS.if if*)

(doc-special :if [:cond1 :body1 "..." :condN :bodyN]
             "Conditional form.
Takes any number of condition/body pairs and evaluates the first body where
the condition evaluates to truthy. Similar to cond in other lisps.")

(fn clause? [v]
  (or (utils.string? v) (and (utils.sym? v) (not (utils.multi-sym? v))
                             (: (tostring v) :match "^&(.+)"))))

(fn remove-until-condition [bindings ast]
  (var until nil)
  (for [i (- (length bindings) 1) 3 -1]
    (case (clause? (. bindings i))
      (where (or false nil)) until
      clause (do (compiler.assert (and (= clause :until) (not until))
                                  (.. "unexpected iterator clause: " clause) ast)
                 (table.remove bindings i)
                 (set until (table.remove bindings i)))))
  until)

(fn compile-until [?condition scope chunk]
  (when ?condition
    (let [[condition-lua] (compiler.compile1 ?condition scope chunk {:nval 1})]
      (compiler.emit chunk (: "if %s then break end" :format
                              (tostring condition-lua))
                     (utils.expr ?condition :expression)))))

(fn iterator-bindings [ast]
  (let [bindings (utils.copy ast)
        ?until (remove-until-condition bindings ast)
        iter (table.remove bindings) ; last remaining item is iterator call
        bindings (if (= 1 (length bindings))
                     (or (utils.list? (. bindings 1)) bindings)
                     ;; make this a compiler error in 2.0
                     (do (each [_ b (ipairs bindings)]
                           (when (utils.list? b)
                             (utils.warn "unexpected parens in iterator" b)))
                         bindings))]
    (values bindings iter ?until)))

(fn SPECIALS.each [ast scope parent]
  (compiler.assert (<= 3 (length ast)) "expected body expression" (. ast 1))
  (compiler.assert (utils.table? (. ast 2)) "expected binding table" ast)
  (let [sub-scope (compiler.make-scope scope)
        (binding iter ?until-condition) (iterator-bindings (. ast 2))
        destructures []
        deferred-scope-changes {:manglings {} :symmeta {}}]
    (utils.hook :pre-each ast sub-scope binding iter ?until-condition)
    (fn destructure-binding [v]
      (if (utils.sym? v)
          (compiler.declare-local v sub-scope ast nil deferred-scope-changes)
          (let [raw (utils.sym (compiler.gensym sub-scope))]
            (tset destructures raw v)
            (compiler.declare-local raw sub-scope ast))))

    (let [bind-vars (icollect [_ b (ipairs binding)] (destructure-binding b))
          vals (compiler.compile1 iter scope parent)
          val-names (icollect [_ v (ipairs vals)] (tostring v))
          chunk []]
      (compiler.assert (. bind-vars 1) "expected binding and iterator" ast)
      (compiler.emit parent
                     (: "for %s in %s do" :format (table.concat bind-vars ", ")
                        (table.concat val-names ", ")) ast)
      (each [raw args (utils.stablepairs destructures)]
        (compiler.destructure args raw ast sub-scope chunk
                              {:declaration true :nomulti true :symtype :each}))
      (compiler.apply-deferred-scope-changes sub-scope deferred-scope-changes ast)
      (compile-until ?until-condition sub-scope chunk)
      (compile-do ast sub-scope chunk 3)
      (compiler.emit parent chunk ast)
      (compiler.emit parent :end ast))))

(doc-special :each [[:vals... :iterator] :...]
             "Runs the body once for each set of values provided by the given iterator.
Most commonly used with ipairs for sequential tables or pairs for undefined
order, but can be used with any iterator with any number of values." true)

(fn while* [ast scope parent]
  (let [len1 (length parent)
        condition (. (compiler.compile1 (. ast 2) scope parent {:nval 1}) 1)
        len2 (length parent)
        sub-chunk []]
    (if (not= len1 len2)
        ;; compound condition; move new compilation to subchunk
        (do
          (for [i (+ len1 1) len2]
            (table.insert sub-chunk (. parent i))
            (tset parent i nil))
          (compiler.emit parent "while true do" ast)
          (compiler.emit sub-chunk
                         (: "if not %s then break end" :format (. condition 1))
                         ast))
        ;; simple condition
        (compiler.emit parent (.. "while " (tostring condition) " do") ast))
    (compile-do ast (compiler.make-scope scope) sub-chunk 3)
    (compiler.emit parent sub-chunk ast)
    (compiler.emit parent :end ast)))

(set SPECIALS.while while*)

(doc-special :while [:condition "..."]
             "The classic while loop. Evaluates body until a condition is non-truthy."
             true)

(fn for* [ast scope parent]
  (compiler.assert (utils.table? (. ast 2)) "expected binding table" ast)
  (let [ranges (setmetatable (utils.copy (. ast 2)) (getmetatable (. ast 2)))
        until-condition (remove-until-condition ranges ast)
        binding-sym (table.remove ranges 1)
        sub-scope (compiler.make-scope scope)
        range-args []
        chunk []]
    (compiler.assert (utils.sym? binding-sym)
                     (: "unable to bind %s %s" :format (type binding-sym)
                        (tostring binding-sym)) (. ast 2))
    (compiler.assert (<= 3 (length ast)) "expected body expression" (. ast 1))
    (compiler.assert (<= (length ranges) 3) "unexpected arguments" ranges)
    (compiler.assert (< 1 (length ranges))
                     "expected range to include start and stop" ranges)
    (utils.hook :pre-for ast sub-scope binding-sym)
    (for [i 1 (math.min (length ranges) 3)]
      (tset range-args i (str1 (compiler.compile1 (. ranges i) scope
                                         parent {:nval 1}))))
    (compiler.emit parent
                   (: "for %s = %s do" :format
                      (compiler.declare-local binding-sym sub-scope ast)
                      (table.concat range-args ", ")) ast)
    (compile-until until-condition sub-scope chunk)
    (compile-do ast sub-scope chunk 3)
    (compiler.emit parent chunk ast)
    (compiler.emit parent :end ast)))

(set SPECIALS.for for*)

(doc-special :for [[:index :start :stop :?step] :...]
             "Numeric loop construct.
Evaluates body once for each value between start and stop (inclusive)." true)

(fn method-special-type [ast]
  (if (and (utils.string? (. ast 3))
           (utils.valid-lua-identifier? (. ast 3)))
      :native
      (utils.sym? (. ast 2))
      :nonnative
      :binding))

(fn native-method-call [ast _scope _parent target args]
  "Prefer native Lua method calls when method name is a valid Lua identifier."
  (let [[_ _ method-string] ast
        call-string (if (or (= target.type :literal)
                            (= target.type :varg)
                            (and (= target.type :expression)
                                 ;; This would be easier if target.type
                                 ;; was more specific to lua's grammar rules.
                                 (not (: (. target 1) :match "[%)%]]$"))
                                 (not (: (. target 1) :match "%.[%a_][%w_]*$"))))
                        "(%s):%s(%s)" "%s:%s(%s)")]
    (utils.expr (string.format call-string (tostring target) method-string
                               (table.concat args ", "))
                :statement)))

(fn nonnative-method-call [ast scope parent target args]
  "When we don't have to protect against double-evaluation, it's not so bad."
  (let [method-string (str1 (compiler.compile1 (. ast 3) scope parent {:nval 1}))
        args [(tostring target) (unpack args)]]
    (utils.expr (string.format "%s[%s](%s)" (tostring target) method-string
                               (table.concat args ", "))
                :statement)))

(fn binding-method-call [ast scope parent target args]
  "When double-evaluation is a concern, we have to bind to a local."
  (let [method-string (str1 (compiler.compile1 (. ast 3) scope parent {:nval 1}))
        target-local (compiler.gensym scope :tgt)
        args [target-local (unpack args)]]
    (compiler.emit parent (string.format "local %s = %s" target-local (tostring target)))
    (utils.expr (string.format "(%s)[%s](%s)" target-local method-string
                               (table.concat args ", "))
                :statement)))

(fn method-call [ast scope parent]
  (compiler.assert (< 2 (length ast)) "expected at least 2 arguments" ast)
  (let [[target] (compiler.compile1 (. ast 2) scope parent {:nval 1})
        args []]
    (for [i 4 (length ast)]
      (let [subexprs (compiler.compile1 (. ast i) scope parent
                                        {:nval (if (not= i (length ast)) 1)})]
        (icollect [_ subexpr (ipairs subexprs) &into args]
          (tostring subexpr))))
    (case (method-special-type ast)
        :native (native-method-call ast scope parent target args)
        :nonnative (nonnative-method-call ast scope parent target args)
        ;; When the target is an expression, we can't use the naive
        ;; nonnative-method-call approach, because it will cause the target
        ;; to be evaluated twice. This is fine if it's a symbol but if it's
        ;; the result of a function call, that function could have side-effects.
        ;; See test-short-circuit in test/misc.fnl for an example of the problem.
        :binding (binding-method-call ast scope parent target args))))

(tset SPECIALS ":" method-call)

(doc-special ":" [:tbl :method-name "..."] "Call the named method on tbl with the provided args.
Method name doesn't have to be known at compile-time; if it is, use
(tbl:method-name ...) instead.")

(fn SPECIALS.comment [ast _ parent]
  (let [c (-> (icollect [i elt (ipairs ast)]
                (if (not= i 1) (view elt {:one-line? true})))
              (table.concat " ")
              (: :gsub "%]%]" "]\\]"))]
    (compiler.emit parent (.. "--[[ " c " ]]") ast)))

(doc-special :comment ["..."] "Comment which will be emitted in Lua output." true)

(fn hashfn-max-used [f-scope i max]
  (let [max (if (. f-scope.symmeta (.. "$" i) :used) i max)]
    (if (< i 9)
        (hashfn-max-used f-scope (+ i 1) max)
        max)))

(fn SPECIALS.hashfn [ast scope parent]
  (compiler.assert (= (length ast) 2) "expected one argument" ast)
  (let [f-scope (doto (compiler.make-scope scope)
                  (tset :vararg false)
                  (tset :hashfn true))
        f-chunk []
        name (compiler.gensym scope)
        symbol (utils.sym name)
        args []]
    (compiler.declare-local symbol scope ast)
    (for [i 1 9]
      (tset args i (compiler.declare-local (utils.sym (.. "$" i)) f-scope
                                           ast)))
    ;; recursively walk the AST, transforming $... into ...
    (fn walker [idx node ?parent-node]
      (if (utils.sym? node "$...")
          (do
            (set f-scope.vararg true)
            (if ?parent-node
                (tset ?parent-node idx (utils.varg))
                (utils.varg)))
          (or (and (utils.list? node)
                   (or (not ?parent-node)
                       ;; don't descend into child functions
                       (not (utils.sym? (. node 1) :hashfn))))
              (utils.table? node))))

    (utils.walk-tree ast walker)
    ;; compile body
    (compiler.compile1 (. ast 2) f-scope f-chunk {:tail true})
    (let [max-used (hashfn-max-used f-scope 1 0)]
      (when f-scope.vararg
        (compiler.assert (= max-used 0)
                         "$ and $... in hashfn are mutually exclusive" ast))
      (let [arg-str (if f-scope.vararg
                        (tostring (utils.varg))
                        (table.concat args ", " 1 max-used))]
        (compiler.emit parent
                       (string.format "local function %s(%s)" name arg-str) ast)
        (compiler.emit parent f-chunk ast)
        (compiler.emit parent :end ast)
        (utils.expr name :sym)))))

(doc-special :hashfn ["..."]
             "Function literal shorthand; args are either $... OR $1, $2, etc.")

(fn comparator-special-type [ast]
  (if (= 3 (length ast))
      :native
      (utils.every? [(unpack ast 3 (- (length ast) 1))] utils.idempotent-expr?)
      :idempotent
      :binding))

;; Helper function to improve detection in operator-special
;; Need to check not only certain forms, but also sometimes sub-forms
;; See https://todo.sr.ht/~technomancy/fennel/196
(fn short-circuit-safe? [x scope]
  (if (or (not= :table (type x)) (utils.sym? x) (utils.varg? x))
      true
      (utils.table? x) (accumulate [ok true k v (pairs x) &until (not ok)]
                         (and (short-circuit-safe? v scope)
                              (short-circuit-safe? k scope)))
      (utils.list? x)
      (if (utils.sym? (. x 1))
        (case (str1 x)
          (where (or :fn :hashfn :let :local :var :set :tset :if :each
                     :for :while :do :lua :global)) false
          (where (or "<" ">" "<=" ">=" "=" "not=" "~=")
                 (= (comparator-special-type x) :binding)) false
          (where :pick-values (not= 1 (. x 2))) false
          (where call (. scope.macros call)) false
          (where ":"
                 (= (method-special-type x) :binding)) false
          _ (faccumulate [ok true i 2 (length x) &until (not ok)]
              (short-circuit-safe? (. x i) scope)))
        (accumulate [ok true _ v (ipairs x) &until (not ok)]
          (short-circuit-safe? v scope)))))

(fn operator-special-result [ast zero-arity unary-prefix padded-op operands]
  (case (length operands)
    0 (if zero-arity
          (utils.expr zero-arity :literal)
          (compiler.assert false "Expected more than 0 arguments" ast))
    1 (if unary-prefix
          (.. "(" unary-prefix padded-op (. operands 1) ")")
          (. operands 1))
    _ (.. "(" (table.concat operands padded-op) ")")))

(fn emit-short-circuit-if [ast scope parent name subast accumulator expr-string setter]
  ;; two short-circuits in a row shouldn't emit redundant assignment
  (when (not= accumulator expr-string)
    (compiler.emit parent (string.format setter accumulator expr-string) ast))
  ;; We use an if statement to enforce the short circuiting rules,
  ;; so that when `subast` emits statements, they can be wrapped.
  (compiler.emit parent (: "if %s then" :format
                           (if (= name :and) accumulator (.. "not " accumulator)))
                 subast)
  (let [chunk []] ; body of "if"
    (compiler.compile1 subast scope chunk {:nval 1 :target accumulator})
    (compiler.emit parent chunk))
  (compiler.emit parent :end))

(fn operator-special [name zero-arity unary-prefix ast scope parent]
  (compiler.assert (not (and (= (length ast) 2)
                             (utils.varg? (. ast 2))))
                   "tried to use vararg with operator" ast)
  (let [padded-op (.. " " name " ")]
    (var (operands accumulator) [])
    (when (utils.call-of? (. ast (length ast)) :values)
      (utils.warn "multiple values in operators are deprecated" ast))
    (each [subast (iter-args ast)]
      (if (and (not= nil (next operands))
               (or (= name :or) (= name :and))
               (not (short-circuit-safe? subast scope)))
          ;; Emit an If statement to ensure we short-circuit all side-effects.
          ;; without this (or true (tset t :a 1)) doesn't short circuit:
          ;; See https://todo.sr.ht/~technomancy/fennel/111
          (let [expr-string (table.concat operands padded-op)
                setter (if accumulator "%s = %s" "local %s = %s")]
            ;; store previous stuff into the local
            ;; if there's not yet a local, we need to gensym it
            (when (not accumulator)
              (set accumulator (compiler.gensym scope name)))
            (emit-short-circuit-if ast scope parent name subast accumulator
                                   expr-string setter)
            ;; Previous operands have been emitted, so we start fresh
            (set operands [accumulator]))
          (table.insert operands (str1 (compiler.compile1 subast scope parent
                                                          {:nval 1})))))
    (operator-special-result ast zero-arity unary-prefix padded-op operands)))

(fn define-arithmetic-special [name zero-arity unary-prefix ?lua-name]
  (tset SPECIALS name (partial operator-special (or ?lua-name name) zero-arity
                               unary-prefix))
  (doc-special name [:a :b "..."]
               "Arithmetic operator; works the same as Lua but accepts more arguments."))

(define-arithmetic-special "+" "0" "0")
(define-arithmetic-special ".." "''")
(define-arithmetic-special "^")
(define-arithmetic-special "-" nil "")
(define-arithmetic-special "*" "1" "1")
(define-arithmetic-special "%")
(define-arithmetic-special "/" nil :1)
(define-arithmetic-special "//" nil :1)

(fn SPECIALS.or [ast scope parent]
  (operator-special :or :false nil ast scope parent))

(fn SPECIALS.and [ast scope parent]
  (operator-special :and :true nil ast scope parent))

(doc-special :and [:a :b "..."]
             "Boolean operator; works the same as Lua but accepts more arguments.")

(doc-special :or [:a :b "..."]
             "Boolean operator; works the same as Lua but accepts more arguments.")

(fn bitop-special [native-name lib-name zero-arity unary-prefix ast scope parent]
  (if (= (length ast) 1)
      (compiler.assert zero-arity "Expected more than 0 arguments." ast)
      (let [len (length ast)
            operands []
            padded-native-name (.. " " native-name " ")
            prefixed-lib-name (.. "bit." lib-name)]
        (for [i 2 len]
          (let [subexprs (compiler.compile1 (. ast i) scope parent
                                            {:nval (if (not= i len) 1)})]
            (icollect [_ s (ipairs subexprs) &into operands] (tostring s))))
        (if (= (length operands) 1)
            (if utils.root.options.useBitLib
                (.. prefixed-lib-name "(" unary-prefix ", " (. operands 1) ")")
                (.. "(" unary-prefix padded-native-name (. operands 1) ")"))
            (if utils.root.options.useBitLib
                (.. prefixed-lib-name "(" (table.concat operands ", ") ")")
                (.. "(" (table.concat operands padded-native-name) ")"))))))

(fn define-bitop-special [name zero-arity unary-prefix native]
  (tset SPECIALS name (partial bitop-special native name zero-arity unary-prefix)))

(define-bitop-special :lshift nil :1 "<<")
(define-bitop-special :rshift nil :1 ">>")
(define-bitop-special :band :-1 :-1 "&")
(define-bitop-special :bor :0 :0 "|")
(define-bitop-special :bxor :0 :0 "~")

(doc-special :lshift [:x :n]
             "Bitwise logical left shift of x by n bits.
Only works in Lua 5.3+ or LuaJIT with the --use-bit-lib flag.")

(doc-special :rshift [:x :n]
             "Bitwise logical right shift of x by n bits.
Only works in Lua 5.3+ or LuaJIT with the --use-bit-lib flag.")

(doc-special :band [:x1 :x2 "..."] "Bitwise AND of any number of arguments.
Only works in Lua 5.3+ or LuaJIT with the --use-bit-lib flag.")

(doc-special :bor [:x1 :x2 "..."] "Bitwise OR of any number of arguments.
Only works in Lua 5.3+ or LuaJIT with the --use-bit-lib flag.")

(doc-special :bxor [:x1 :x2 "..."] "Bitwise XOR of any number of arguments.
Only works in Lua 5.3+ or LuaJIT with the --use-bit-lib flag.")

(fn SPECIALS.bnot [ast scope parent]
  (compiler.assert (= (length ast) 2) "expected one argument" ast)
  (let [[value] (compiler.compile1 (. ast 2) scope parent {:nval 1})]
    (if utils.root.options.useBitLib
        (.. "bit.bnot(" (tostring value) ")")
        (.. "~(" (tostring value) ")"))))

(doc-special :bnot [:x] "Bitwise negation; only works in Lua 5.3+ or LuaJIT with the --use-bit-lib flag.")

(doc-special ".." [:a :b "..."]
             "String concatenation operator; works the same as Lua but accepts more arguments.")

(fn native-comparator [op [_ lhs-ast rhs-ast] scope parent]
  "Naively compile a binary comparison to Lua."
  (let [[lhs] (compiler.compile1 lhs-ast scope parent {:nval 1})
        [rhs] (compiler.compile1 rhs-ast scope parent {:nval 1})]
    (string.format "(%s %s %s)" (tostring lhs) op (tostring rhs))))

(fn idempotent-comparator [op chain-op ast scope parent]
  "Compile a multi-arity comparison to a binary Lua comparison. Optimized
  variant for values not at risk of double-eval."
  (let [vals (fcollect [i 2 (length ast)]
               (str1 (compiler.compile1 (. ast i) scope parent {:nval 1})))
        comparisons (fcollect [i 1 (- (length vals) 1)]
                      (string.format "(%s %s %s)"
                                     (. vals i) op (. vals (+ i 1))))
        chain (string.format " %s " (or chain-op :and))]
    (.. "(" (table.concat comparisons chain) ")")))

(fn binding-comparator [op chain-op ast scope parent]
  "Compile a multi-arity comparison to a binary Lua comparison."
  (let [binding-left []
        binding-right []
        vals []
        chain (string.format " %s " (or chain-op :and))]
    (for [i 2 (length ast)]
      (let [compiled (str1 (compiler.compile1 (. ast i) scope parent {:nval 1}))]
        (if (or (utils.idempotent-expr? (. ast i)) (= i 2) (= i (length ast)))
          (table.insert vals compiled)
          (let [my-sym (compiler.gensym scope)]
            (table.insert binding-left my-sym)
            (table.insert binding-right compiled)
            (table.insert vals my-sym)))))
    (compiler.emit parent (string.format "local %s = %s"
                                         (table.concat binding-left ", ")
                                         (table.concat binding-right ", ")
                                         ast))
    (.. "("
        (table.concat
          (fcollect [i 1 (- (length vals) 1)]
            (string.format "(%s %s %s)" (. vals i) op (. vals (+ i 1))))
          chain)
        ")")))

(fn define-comparator-special [name ?lua-op ?chain-op]
  (let [op (or ?lua-op name)]
    (fn opfn [ast scope parent]
      (compiler.assert (< 2 (length ast)) "expected at least two arguments" ast)
      (case (comparator-special-type ast)
          :native (native-comparator op ast scope parent)
          :idempotent (idempotent-comparator op ?chain-op ast scope parent)
          :binding (binding-comparator op ?chain-op ast scope parent)
          _ (error "internal compiler error. please report this to the fennel devs.")))

    (tset SPECIALS name opfn))
  (doc-special name [:a :b "..."]
               "Comparison operator; works the same as Lua but accepts more arguments."))

(define-comparator-special ">")
(define-comparator-special "<")
(define-comparator-special ">=")
(define-comparator-special "<=")
(define-comparator-special "=" "==")
(define-comparator-special :not= "~=" :or)

(fn define-unary-special [op ?realop]
  (fn opfn [ast scope parent]
    (compiler.assert (= (length ast) 2) "expected one argument" ast)
    (let [tail (compiler.compile1 (. ast 2) scope parent {:nval 1})]
      (.. (or ?realop op) (str1 tail))))

  (tset SPECIALS op opfn))

(define-unary-special :not "not ")
(doc-special :not [:x] "Logical operator; works the same as Lua.")
(define-unary-special :length "#")
(doc-special :length [:x] "Returns the length of a table or string.")

;; backwards-compatibility aliases
(tset SPECIALS "~=" (. SPECIALS :not=))
(set SPECIALS.# (. SPECIALS :length))

(fn compile-time? [scope]
  (or (= scope compiler.scopes.compiler)
      (and scope.parent (compile-time? scope.parent))))

(fn SPECIALS.quote [ast scope parent]
  (compiler.assert (= (length ast) 2) "expected one argument" ast)
  (compiler.do-quote (. ast 2) scope parent (not (compile-time? scope))))

(doc-special :quote [:x]
             "Quasiquote the following form. Only works in macro/compiler scope.")

;; This is the compile-env equivalent of package.loaded. It's used by
;; require-macros and import-macros, but also by require when used from within
;; default compiler scope.
(local macro-loaded {})

(fn safe-getmetatable [tbl]
  (let [mt (getmetatable tbl)]
    ;; we can't let the string metatable leak
    (assert (not= mt (getmetatable "")) "Illegal metatable access!")
    mt))

;; not 100% convinced on this yet...
;; (fn safe-open [filename ?mode]
;;   (assert (or (= nil ?mode) (?mode:find "^r"))
;;           (.. "unsafe file mode: " (tostring ?mode)))
;;   (assert (not (or (filename:find "^/") (filename:find "%.%.")))
;;           (.. "unsafe file name: " filename))
;;   (io.open filename ?mode))

;; Circularity
(var safe-require nil)

(fn safe-compiler-env []
  {:table (utils.copy table)
   :math (utils.copy math)
   :string (utils.copy string)
   :pairs utils.stablepairs
   ;; :io {:open safe-open}
   : ipairs : select : tostring : tonumber :bit (rawget _G :bit)
   : pcall : xpcall : next : print : type : assert : error
   : setmetatable :getmetatable safe-getmetatable :require safe-require
   :rawlen (rawget _G :rawlen) : rawget : rawset : rawequal : _VERSION
   :utf8 (-?> (rawget _G :utf8) (utils.copy))}) ; lua >= 5.3

(fn combined-mt-pairs [env]
  (let [combined {}
        {: __index} (getmetatable env)]
    (when (= :table (type __index))
      (each [k v (pairs __index)]
        (tset combined k v)))
    (each [k v (values next env nil)]
      (tset combined k v))
    (values next combined nil)))

(fn make-compiler-env [ast scope parent ?opts]
  (let [provided (case (or ?opts utils.root.options)
                   {:compiler-env :strict} (safe-compiler-env)
                   {: compilerEnv} compilerEnv
                   {: compiler-env} compiler-env
                   _ (safe-compiler-env))
        env {:_AST ast
             :_CHUNK parent
             :_IS_COMPILER true
             :_SCOPE scope
             :_SPECIALS compiler.scopes.global.specials
             :_VARARG (utils.varg) ; don't use this!
             : macro-loaded
             : pack : unpack
             :assert-compile compiler.assert
             : view
             : fennel-module-name
             :version utils.version
             ;; AST functions
             :ast-source utils.ast-source
             :list utils.list :list? utils.list? :table? utils.table?
             :sequence utils.sequence :sequence? utils.sequence?
             :sym utils.sym :sym? utils.sym? :multi-sym? utils.multi-sym?
             :comment utils.comment :comment? utils.comment? :varg? utils.varg?
             ;; scoping functions
             :gensym (fn [base]
                       (utils.sym (compiler.gensym (or compiler.scopes.macro
                                                       scope)
                                                   base)))
             :get-scope (fn []
                          compiler.scopes.macro)
             :in-scope? (fn [symbol]
                          (compiler.assert compiler.scopes.macro
                                           "must call from macro" ast)
                          (. compiler.scopes.macro.manglings
                             (tostring symbol)))
             :macroexpand (fn [form]
                            (compiler.assert compiler.scopes.macro
                                             "must call from macro" ast)
                            (compiler.macroexpand form
                                                  compiler.scopes.macro))}]
    (set env._G env)
    (setmetatable env
                  {:__index provided
                   :__newindex provided
                   :__pairs combined-mt-pairs})))

;; search-module uses package.config to process package.path (windows compat)
(local [dirsep pathsep pathmark]
       (icollect [c (string.gmatch (or package.config "") "([^\n]+)")] c))
(local pkg-config {:dirsep (or dirsep "/")
                   :pathmark (or pathmark "?")
                   :pathsep (or pathsep ";")})

(fn escapepat [str]
  "Escape a string for safe use in a Lua pattern."
  (string.gsub str "[^%w]" "%%%1"))

(fn search-module [modulename ?pathstring]
  (let [pathsepesc (escapepat pkg-config.pathsep)
        pattern (: "([^%s]*)%s" :format pathsepesc pathsepesc)
        no-dot-module (modulename:gsub "%." pkg-config.dirsep)
        fullpath (.. (or ?pathstring utils.fennel-module.path)
                     pkg-config.pathsep)]
    (fn try-path [path]
      (let [filename (path:gsub (escapepat pkg-config.pathmark) no-dot-module)]
        (case (io.open filename)
          file (do
                 (file:close)
                 filename)
          _ (values nil (.. "no file '" filename "'")))))

    (fn find-in-path [start ?tried-paths]
      (case (fullpath:match pattern start)
        path (case (try-path path)
               filename filename
               (nil error) (find-in-path (+ start (length path) 1)
                                         (doto (or ?tried-paths []) (table.insert error))))
        _ (values nil
                  ;; Before Lua 5.4 it was necessary to prepend a \n\t to the
                  ;; error message. In newer versions doing so causes an empty
                  ;; line before Fennel's error message.
                  (let [tried-paths (table.concat (or ?tried-paths []) "\n\t")]
                    (if (< _VERSION "Lua 5.4")
                      (.. "\n\t" tried-paths)
                      tried-paths)))))

    (find-in-path 1)))

(fn make-searcher [?options]
  "This will allow regular `require` to work with Fennel:
table.insert(package.loaders or package.searchers, fennel.searcher)"
  (fn [module-name]
    (let [opts (utils.copy utils.root.options)]
      (each [k v (pairs (or ?options {}))]
        (tset opts k v))
      (set opts.module-name module-name)
      (case (search-module module-name)
        filename (values (partial utils.fennel-module.dofile filename opts)
                         filename)
        (nil error) error))))

;; If the compiler sandbox is disabled, we need to splice in the searcher
;; so macro modules can load other macro modules in compiler env.
(fn dofile-with-searcher [fennel-macro-searcher filename opts ...]
  (let [searchers (or package.loaders package.searchers {})
        _ (table.insert searchers 1 fennel-macro-searcher)
        m (utils.fennel-module.dofile filename opts ...)]
    (table.remove searchers 1)
    m))

(fn fennel-macro-searcher [module-name]
  (let [opts (doto (utils.copy utils.root.options)
               (tset :module-name module-name)
               (tset :env :_COMPILER)
               (tset :requireAsInclude false)
               (tset :allowedGlobals nil))]
    (case (search-module module-name utils.fennel-module.macro-path)
      filename (values (if (= opts.compiler-env _G)
                           (partial dofile-with-searcher fennel-macro-searcher
                                    filename opts)
                           (partial utils.fennel-module.dofile filename opts))
                       filename))))

(fn lua-macro-searcher [module-name]
  (case (search-module module-name package.path)
    filename (let [code (with-open [f (io.open filename)] (assert (f:read :*a)))
                   chunk (load-code code (make-compiler-env) filename)]
               (values chunk filename))))

(local macro-searchers [fennel-macro-searcher lua-macro-searcher])

(fn search-macro-module [modname n]
  (case (. macro-searchers n)
    f (case (f modname)
        (loader ?filename) (values loader ?filename)
        _ (search-macro-module modname (+ n 1)))))

(fn sandbox-fennel-module [modname]
  "Let limited Fennel module thru with safe fields."
  (if (or (= modname :fennel.macros)
          (and package package.loaded
               (= :table (type (. package.loaded modname)))
               (= (. package.loaded modname :metadata) compiler.metadata)))
      ;; should never be needed to use view thru here since it's global in
      ;; macro scope, but it's not obvious, so allow this to be used as well.
      ;; can't read metadata from sandbox, but need to be able to set it.
      {: view :metadata {:setall (fn [_ ...] (compiler.metadata:setall ...))}}))

(set safe-require (fn [modname]
                    "This is a replacement for require for use in macro contexts.
It ensures that compile-scoped modules are loaded differently from regular
modules in the compiler environment."
                    (or (. macro-loaded modname) (sandbox-fennel-module modname)
                        (let [(loader filename) (search-macro-module modname 1)]
                          (compiler.assert loader (.. modname " module not found."))
                          (tset macro-loaded modname (loader modname filename))
                          (. macro-loaded modname)))))

(fn add-macros [macros* ast scope]
  (compiler.assert (utils.table? macros*) "expected macros to be table" ast)
  (each [k v (pairs macros*)]
    (compiler.assert (= (type v) :function)
                     "expected each macro to be function" ast)
    (compiler.check-binding-valid (utils.sym k) scope ast {:macro? true})
    (tset scope.macros k v)))

(fn resolve-module-name [{: filename 2 second} _scope _parent opts]
  ;; Compile module path to resolve real module name.  Allows using
  ;; (.. ... :.foo.bar) expressions and self-contained
  ;; statement-expressions in `require`, `include`, `require-macros`,
  ;; and `import-macros`.
  (let [filename (or filename (and (utils.table? second) second.filename))
        module-name utils.root.options.module-name
        modexpr (compiler.compile second opts)
        modname-chunk (load-code modexpr)]
    (modname-chunk module-name filename)))

(fn SPECIALS.require-macros [ast scope parent ?real-ast]
  (compiler.assert (= (length ast) 2) "Expected one module name argument"
                   (or ?real-ast ast)) ; real-ast comes from import-macros
  (let [modname (resolve-module-name ast scope parent {})]
    (compiler.assert (utils.string? modname)
                     "module name must compile to string" (or ?real-ast ast))
    (when (not (. macro-loaded modname))
      (let [(loader filename) (search-macro-module modname 1)]
        (compiler.assert loader (.. modname " module not found.") ast)
        (tset macro-loaded modname
              (compiler.assert (utils.table? (loader modname filename))
                               "expected macros to be table" (or ?real-ast ast)))))
    ;; if we're called from import-macros, return the modname, else add them
    ;; to scope directly
    (if (= :import-macros (str1 ast))
        (. macro-loaded modname)
        (add-macros (. macro-loaded modname) ast scope))))

(doc-special :require-macros [:macro-module-name]
             "Load given module and use its contents as macro definitions in current scope.
Deprecated.")

(fn emit-included-fennel [src path opts sub-chunk]
  "Emit Fennel code in src into sub-chunk."
  (let [subscope (compiler.make-scope utils.root.scope.parent)
        forms []]
    (when utils.root.options.requireAsInclude
      (set subscope.specials.require compiler.require-include))
    ;; parse Fennel src into table of exprs to know which expr is the tail
    (each [_ val (parser.parser (parser.string-stream src) path)]
      (table.insert forms val))
    ;; Compile the forms into sub-chunk; compiler.compile1 is necessary
    ;; for all nested includes to be emitted in the same root chunk
    ;; in the top-level module.
    (for [i 1 (length forms)]
      (let [subopts (if (= i (length forms)) {:tail true} {:nval 0})]
        (utils.propagate-options opts subopts)
        (compiler.compile1 (. forms i) subscope sub-chunk subopts)))))

(fn include-path [ast opts path mod fennel?]
  "Helper function for include once we have determined the path to use."
  (tset utils.root.scope.includes mod :fnl/loading)
  (let [src (with-open [f (assert (io.open path))]
              (: (assert (f:read :*all)) :gsub "[\r\n]*$" ""))
        ;; splice in source and memoize it in compiler AND package.preload
        ;; so we can include it again without duplication, even in runtime
        ret (utils.expr (.. "require(\"" mod "\")") :statement)
        target (: "package.preload[%q]" :format mod)
        preload-str (.. target " = " target " or function(...)")
        (temp-chunk sub-chunk) (values [] [])]
    (compiler.emit temp-chunk preload-str ast)
    (compiler.emit temp-chunk sub-chunk)
    (compiler.emit temp-chunk :end ast)
    ;; Splice temp-chunk to the end of the root chunk
    (each [_ v (ipairs temp-chunk)]
      (table.insert utils.root.chunk v))
    ;; For fennel source, compile sub-chunk AFTER splicing into start of
    ;; root chunk.
    (if fennel?
        (emit-included-fennel src path opts sub-chunk)
        ;; For Lua source, simply emit src into the loaders's body
        (compiler.emit sub-chunk src ast))
    ;; Put in cache and return
    (tset utils.root.scope.includes mod ret)
    ret))

(fn include-circular-fallback [mod modexpr fallback ast]
  "If a circular include is detected, fall back to require if possible."
  (when (= (. utils.root.scope.includes mod) :fnl/loading) ; circular include
    (compiler.assert fallback "circular include detected" ast)
    (fallback modexpr)))

(fn SPECIALS.include [ast scope parent opts]
  (compiler.assert (= (length ast) 2) "expected one argument" ast)
  (let [modexpr (case (pcall resolve-module-name ast scope parent opts)
                  ;; if we're in a dofile and not a require, then module-name
                  ;; will be nil and we will not be able to successfully
                  ;; compile relative requires into includes, but we can still
                  ;; emit a runtime relative require.
                  (true modname) (utils.expr (string.format "%q" modname) :literal)
                  _ (. (compiler.compile1 (. ast 2) scope parent {:nval 1}) 1))]
    (if (or (not= modexpr.type :literal) (not= (: (. modexpr 1) :byte) 34))
        (if opts.fallback
            (opts.fallback modexpr)
            (compiler.assert false "module name must be string literal" ast))
        (let [mod ((load-code (.. "return " (. modexpr 1))))
              oldmod utils.root.options.module-name
              _ (set utils.root.options.module-name mod)
              res (or (and (utils.member? mod (or utils.root.options.skipInclude []))
                           (opts.fallback modexpr true))
                      (include-circular-fallback mod modexpr opts.fallback ast)
                      (. utils.root.scope.includes mod) ; check cache
                      ;; Find path to Fennel or Lua source; preferring Fennel
                      (case (search-module mod)
                        fennel-path (include-path ast opts fennel-path mod true)
                        _ (let [lua-path (search-module mod package.path)]
                            (if lua-path (include-path ast opts lua-path mod false)
                                opts.fallback (opts.fallback modexpr)
                                (compiler.assert false (.. "module not found " mod) ast)))))]
          (set utils.root.options.module-name oldmod)
          res))))

(doc-special :include [:module-name-literal]
             "Like require but load the target module during compilation and embed it in the
Lua output. The module must be a string literal and resolvable at compile time.")

(fn eval-compiler* [ast scope parent]
  (let [env (make-compiler-env ast scope parent)
        opts (utils.copy utils.root.options)]
    (set opts.scope (compiler.make-scope compiler.scopes.compiler))
    (set opts.allowedGlobals (current-global-names env))
    ((assert (load-code (compiler.compile ast opts) (wrap-env env)))
     opts.module-name ast.filename)))

(fn SPECIALS.macros [ast scope parent]
  (compiler.assert (= (length ast) 2) "Expected one table argument" ast)
  (let [macro-tbl (eval-compiler* (. ast 2) scope parent)]
    (compiler.assert (utils.table? macro-tbl) "Expected one table argument" ast)
    (add-macros macro-tbl ast scope)))

(doc-special :macros
             ["{:macro-name-1 (fn [...] ...) ... :macro-name-N macro-body-N}"]
             "Define all functions in the given table as macros local to the current scope.")

(fn SPECIALS.tail! [ast scope parent opts]
  (compiler.assert (= (length ast) 2) "Expected one argument" ast)
  (let [call (utils.list? (compiler.macroexpand (. ast 2) scope))
        callee (tostring (and call (utils.sym? (. call 1))))]
    ;; callee won't ever be a macro because we've already macroexpanded
    (compiler.assert (and call (not (. scope.specials callee)))
                     "Expected a function call as argument" ast)
    (compiler.assert opts.tail "Must be in tail position" ast)
    (compiler.compile1 call scope parent opts)))

(doc-special :tail! ["body"]
             "Assert that the body being called is in tail position.")

(fn SPECIALS.pick-values [ast scope parent]
  (let [n (. ast 2)
        vals (utils.list (utils.sym :values) (unpack ast 3))]
    (compiler.assert (and (= :number (type n)) (<= 0 n) (= n (math.floor n)))
                     (.. "Expected n to be an integer >= 0, got " (tostring n)))
    (if (= 1 n)
        ;; n = 1 can be simplified to (<expr>) in lua output
        (let [[[expr]] (compiler.compile1 vals scope parent {:nval 1})]
          [(.. "(" expr ")")])
        (= 0 n)
        (do
          (for [i 3 (length ast)]
            (-> (compiler.compile1 (. ast i) scope parent {:nval 0})
                (compiler.keep-side-effects parent nil (. ast i))))
          [])
        (let [syms (fcollect [_ 1 n &into (utils.list)]
                     (utils.sym (compiler.gensym scope :pv)))]
          ;; Declare exactly n temp bindings for supplied values without `let`
          (compiler.destructure syms vals ast scope parent
                                {:nomulti true :noundef true
                                 :symtype :pv :declaration true})
          syms))))

(doc-special :pick-values ["n" "..."]
             "Evaluate to exactly n values.\n\nFor example,
  (pick-values 2 ...)
expands to
  (let [(_0_ _1_) ...]
    (values _0_ _1_))")

(fn SPECIALS.eval-compiler [ast scope parent]
  (let [old-first (. ast 1)]
    (tset ast 1 (utils.sym :do))
    (let [val (eval-compiler* ast scope parent)]
      (tset ast 1 old-first)
      val)))

(doc-special :eval-compiler ["..."]
             "Evaluate the body at compile-time. Use the macro system instead if possible."
             true)

(fn SPECIALS.unquote [ast]
  (compiler.assert false "tried to use unquote outside quote" ast))

(doc-special :unquote ["..."] "Evaluate the argument even if it's in a quoted form.")

{:doc doc*
 : current-global-names
 : load-code
 : macro-loaded
 : macro-searchers
 : make-compiler-env
 : search-module
 : make-searcher
 : get-function-metadata
 : wrap-env}
