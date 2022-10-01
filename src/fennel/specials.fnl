;; This module contains all the special forms; all built in Fennel constructs
;; which cannot be implemented as macros. It also contains some core compiler
;; functionality which is kept in this module for circularity reasons.

(local utils (require :fennel.utils))
(local view (require :fennel.view))
(local parser (require :fennel.parser))
(local compiler (require :fennel.compiler))
(local unpack (or table.unpack _G.unpack))

(local SPECIALS compiler.scopes.global.specials)

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
                            (fn putenv [k v]
                              (values (if (utils.string? k)
                                          (compiler.global-unmangling k)
                                          k)
                                      v))

                            (values next (utils.kvmap env putenv) nil))}))

(fn current-global-names [?env]
  ;; if there's a metatable on ?env, we need to make sure it's one that has a
  ;; __pairs metamethod, otherwise we give up entirely on globals checking.
  (let [mt (match (getmetatable ?env)
             ;; newer lua versions know about __pairs natively but not 5.1
             {:__pairs mtpairs} (collect [k v (mtpairs ?env)] (values k v))
             nil (or ?env _G))]
    (and mt (utils.kvmap mt compiler.global-unmangling))))

(fn load-code [code ?env ?filename]
  "Load Lua code with an environment in all recent Lua versions"
  (let [env (or ?env (rawget _G :_ENV) _G)]
    (match (values (rawget _G :setfenv) (rawget _G :loadstring))
      (setfenv loadstring) (let [f (assert (loadstring code ?filename))]
                             (doto f (setfenv env)))
      _ (assert (load code ?filename :t env)))))

(fn doc* [tgt name]
  "Return a docstring for tgt."
  (if (not tgt)
      (.. name " not found")
      (let [docstring (-> (: compiler.metadata :get tgt :fnl/docstring)
                          (or "#<undocumented>")
                          (: :gsub "\n$" "")
                          (: :gsub "\n" "\n  "))
            mt (getmetatable tgt)]
        (if (or (= (type tgt) :function)
                (and (= (type mt) :table) (= (type (. mt :__call)) :function)))
            (let [arglist (table.concat (or (: compiler.metadata :get tgt
                                               :fnl/arglist)
                                            ["#<unknown-arguments>"])
                                        " ")]
              (string.format "(%s%s%s)\n  %s" name
                             (if (< 0 (length arglist)) " " "") arglist
                             docstring))
            (string.format "%s\n  %s" name docstring)))))

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
    (fn compile-body [outer-target outer-tail outer-retexprs]
      (if (< len start)
          ;; In the unlikely event we do a do with no arguments
          (compiler.compile1 nil sub-scope chunk
                             {:tail outer-tail :target outer-target})
          ;; There will be side-effects
          (for [i start len]
            (let [subopts {:nval (or (and (not= i len) 0) opts.nval)
                           :tail (or (and (= i len) outer-tail) nil)
                           :target (or (and (= i len) outer-target) nil)}
                  _ (utils.propagate-options opts subopts)
                  subexprs (compiler.compile1 (. ast i) sub-scope chunk subopts)]
              (when (not= i len)
                (compiler.keep-side-effects subexprs parent nil (. ast i))))))
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

(fn SPECIALS.values [ast scope parent]
  "Unlike most expressions and specials, 'values' resolves with multiple
values, one for each argument, allowing multiple return values. The last
expression can return multiple arguments as well, allowing for more than
the number of expected arguments."
  (let [len (length ast)
        exprs []]
    (for [i 2 len]
      (let [subexprs (compiler.compile1 (. ast i) scope parent
                                        {:nval (and (not= i len) 1)})]
        (table.insert exprs (. subexprs 1))
        (when (= i len)
          (for [j 2 (length subexprs)]
            (table.insert exprs (. subexprs j))))))
    exprs))

(doc-special :values ["..."]
             "Return multiple values from a function. Must be in tail position.")

;; TODO: use view here?
(fn deep-tostring [x key?]
  "Tostring for literal tables created with {}, [] or ().
Recursively transforms tables into one-line string representation.
Main purpose to print function argument list in docstring."
  (if (utils.list? x)
      (.. "(" (table.concat (icollect [_ v (ipairs x)]
                              (deep-tostring v))
                            " ") ")")
      (utils.sequence? x)
      (.. "[" (table.concat (icollect [_ v (ipairs x)]
                              (deep-tostring v))
                            " ") "]")
      (utils.table? x)
      (.. "{" (table.concat (icollect [k v (utils.stablepairs x)]
                              (.. (deep-tostring k true) " "
                                  (deep-tostring v)))
                            " ") "}")
      (and key? (utils.string? x) (x:find "^[-%w?\\^_!$%&*+./@:|<=>]+$"))
      (.. ":" x)
      (utils.string? x)
      (-> (string.format "%q" x)
          (: :gsub "\\\"" "\\\\\"")
          (: :gsub "\"" "\\\""))
      (tostring x)))

(fn set-fn-metadata [arg-list docstring parent fn-name]
  (when utils.root.options.useMetadata
    (let [args (utils.map arg-list #(: "\"%s\"" :format (deep-tostring $)))
          meta-fields ["\"fnl/arglist\"" (.. "{" (table.concat args ", ") "}")]]
      (when docstring
        (table.insert meta-fields "\"fnl/docstring\"")
        (table.insert meta-fields (.. "\""
                                      (-> docstring
                                          (: :gsub "%s+$" "")
                                          (: :gsub "\\" "\\\\")
                                          (: :gsub "\n" "\\n")
                                          (: :gsub "\"" "\\\""))
                                      "\"")))
      (let [meta-str (: "require(\"%s\").metadata" :format
                        (or utils.root.options.moduleName :fennel))]
        (compiler.emit parent
                       (: "pcall(function() %s:setall(%s, %s) end)" :format
                          meta-str fn-name (table.concat meta-fields ", ")))))))

(fn get-fn-name [ast scope fn-name multi]
  (if (and fn-name (not= (. fn-name 1) :nil))
      (values (if (not multi)
                  (compiler.declare-local fn-name [] scope ast)
                  (. (compiler.symbol-to-expression fn-name scope) 1))
              (not multi) 3)
      (values nil true 2)))

(fn compile-named-fn [ast f-scope f-chunk parent index fn-name local?
                      arg-name-list f-metadata]
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
  (set-fn-metadata f-metadata.fnl/arglist f-metadata.fnl/docstring
                   parent fn-name)
  (utils.hook :fn ast f-scope)
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

(fn get-function-metadata [ast arg-list index]
  ;; Get function metadata from ast and put it in a table.  Detects if
  ;; the next expression after a argument list is either a string or a
  ;; table, and copies values into function metadata table.
  (let [f-metadata {:fnl/arglist arg-list}
        index* (+ index 1)
        expr (. ast index*)]
    (if (and (utils.string? expr)
             (< index* (length ast)))
        (values (doto f-metadata
                  (tset :fnl/docstring expr))
                index*)
        (and (utils.table? expr)
             (< index* (length ast)))
        (values (collect [k v (pairs expr) :into f-metadata]
                  (values k v))
                index*)
        (values f-metadata index))))

(fn SPECIALS.fn [ast scope parent]
  (let [f-scope (doto (compiler.make-scope scope)
                  (tset :vararg false))
        f-chunk []
        fn-sym (utils.sym? (. ast 2))
        multi (and fn-sym (utils.multi-sym? (. fn-sym 1)))
        (fn-name local? index) (get-fn-name ast scope fn-sym multi)
        arg-list (compiler.assert (utils.table? (. ast index))
                                  "expected parameters table" ast)]
    (compiler.assert (or (not multi) (not multi.multi-sym-method-call))
                     (.. "unexpected multi symbol " (tostring fn-name)) fn-sym)

    (fn get-arg-name [arg]
      (if (utils.varg? arg)
          (do
            (compiler.assert (= arg (. arg-list (length arg-list)))
                             "expected vararg as last parameter" ast)
            (set f-scope.vararg true)
            "...")
          (and (utils.sym? arg) (not= (tostring arg) :nil)
               (not (utils.multi-sym? (tostring arg))))
          (compiler.declare-local arg [] f-scope ast)
          (utils.table? arg)
          (let [raw (utils.sym (compiler.gensym scope))
                declared (compiler.declare-local raw [] f-scope ast)]
            (compiler.destructure arg raw ast f-scope f-chunk
                                  {:declaration true
                                   :nomulti true
                                   :symtype :arg})
            declared)
          (compiler.assert false
                           (: "expected symbol for function parameter: %s"
                              :format (tostring arg))
                           (. ast index))))

    (let [arg-name-list (utils.map arg-list get-arg-name)
          (f-metadata index) (get-function-metadata ast arg-list index)]
      (if fn-name
          (compile-named-fn ast f-scope f-chunk parent index fn-name local?
                            arg-name-list f-metadata)
          (compile-anonymous-fn ast f-scope f-chunk parent index arg-name-list
                                f-metadata scope)))))

(doc-special :fn [:name? :args :docstring? "..."]
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
  "Table lookup; equivalent to tbl[] in Lua."
  (compiler.assert (< 1 (length ast)) "expected table argument" ast)
  (let [len (length ast)
        [lhs] (compiler.compile1 (. ast 2) scope parent {:nval 1})]
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
          ;; Extra parens are needed unless the target is a table literal
          (if (or (: (tostring lhs) :find "[{\"0-9]") (= :nil (tostring lhs)))
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

(doc-special :global [:name :val] "Set name as a global with val.")

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

(tset SPECIALS :set-forcibly! set-forcibly!*)

(fn local* [ast scope parent]
  (compiler.assert (= (length ast) 3) "expected name and value" ast)
  (compiler.destructure (. ast 2) (. ast 3) ast scope parent
                        {:declaration true :nomulti true :symtype :local})
  nil)

(tset SPECIALS :local local*)

(doc-special :local [:name :val] "Introduce new top-level immutable local.")

(fn SPECIALS.var [ast scope parent]
  (compiler.assert (= (length ast) 3) "expected name and value" ast)
  (compiler.destructure (. ast 2) (. ast 3) ast scope parent
                        {:declaration true
                         :isvar true
                         :nomulti true
                         :symtype :var})
  nil)

(doc-special :var [:name :val] "Introduce new mutable local.")

(fn kv? [t] (. (icollect [k (pairs t)] (if (not= :number (type k)) k)) 1))

(fn SPECIALS.let [ast scope parent opts]
  (let [bindings (. ast 2)
        pre-syms []]
    (compiler.assert (and (utils.table? bindings) (not (kv? bindings)))
                     "expected binding sequence" bindings)
    (compiler.assert (= (% (length bindings) 2) 0)
                     "expected even number of name/value bindings" (. ast 2))
    (compiler.assert (<= 3 (length ast)) "expected body expression" (. ast 1))
    ;; we have to gensym the binding for the let body's return value before
    ;; compiling the binding vector, otherwise there's a possibility to conflict
    (for [_ 1 (or opts.nval 0)]
      (table.insert pre-syms (compiler.gensym scope)))
    (let [sub-scope (compiler.make-scope scope)
          sub-chunk []]
      (for [i 1 (length bindings) 2]
        (compiler.destructure (. bindings i) (. bindings (+ i 1)) ast sub-scope
                              sub-chunk
                              {:declaration true :nomulti true :symtype :let}))
      (SPECIALS.do ast scope parent opts 3 sub-chunk sub-scope pre-syms))))

(doc-special :let ["[name1 val1 ... nameN valN]" "..."]
             "Introduces a new scope in which a given set of local bindings are used."
             true)

(fn get-prev-line [parent]
  (if (= :table (type parent))
      (get-prev-line (or parent.leaf (. parent (length parent))))
      (or parent "")))

(fn disambiguate? [rootstr parent]
  (or (rootstr:match "^{")
      (match (get-prev-line parent)
        prev-line (prev-line:match "%)$"))))

(fn SPECIALS.tset [ast scope parent]
  "For setting items in a table."
  (compiler.assert (< 3 (length ast))
                   "expected table, key, and value arguments" ast)
  (let [root (. (compiler.compile1 (. ast 2) scope parent {:nval 1}) 1)
        keys []]
    (for [i 3 (- (length ast) 1)]
      (let [[key] (compiler.compile1 (. ast i) scope parent {:nval 1})]
        (table.insert keys (tostring key))))
    (let [value (. (compiler.compile1 (. ast (length ast)) scope parent
                                      {:nval 1}) 1)
          rootstr (tostring root)
          fmtstr (if (disambiguate? rootstr parent)
                     "do end (%s)[%s] = %s"
                     "%s[%s] = %s")]
      (compiler.emit parent
                     (: fmtstr :format rootstr (table.concat keys "][")
                        (tostring value)) ast))))

(doc-special :tset [:tbl :key1 "..." :keyN :val]
             "Set the value of a table field. Can take additional keys to set
nested values, but all parents must contain an existing table.")

(fn calculate-target [scope opts]
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
  (let [do-scope (compiler.make-scope scope)
        branches []
        (wrapper inner-tail inner-target target-exprs) (calculate-target scope
                                                                         opts)
        body-opts {:nval opts.nval :tail inner-tail :target inner-target}]
    (fn compile-body [i]
      (let [chunk []
            cscope (compiler.make-scope do-scope)]
        (compiler.keep-side-effects (compiler.compile1 (. ast i) cscope chunk
                                                       body-opts)
                                    chunk nil (. ast i))
        {: chunk :scope cscope}))

    ;; Implicit else becomes nil
    (when (= 1 (% (length ast) 2))
      (table.insert ast (utils.sym :nil)))

    (for [i 2 (- (length ast) 1) 2]
      (let [condchunk []
            res (compiler.compile1 (. ast i) do-scope condchunk {:nval 1})
            cond (. res 1)
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
              cond-line (: fstr :format cond)]
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
      (if (= wrapper :iife)
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
            target-exprs)))))

(tset SPECIALS :if if*)

(doc-special :if [:cond1 :body1 "..." :condN :bodyN]
             "Conditional form.
Takes any number of condition/body pairs and evaluates the first body where
the condition evaluates to truthy. Similar to cond in other lisps.")

(fn remove-until-condition [bindings]
  (let [last-item (. bindings (- (length bindings) 1))]
    (when (or (and (utils.sym? last-item) (= (tostring last-item) :&until))
              (=  :until last-item))
      (table.remove bindings (- (length bindings) 1))
      (table.remove bindings))))

(fn compile-until [condition scope chunk]
  (when condition
    (let [[condition-lua] (compiler.compile1 condition scope chunk {:nval 1})]
      (compiler.emit chunk (: "if %s then break end" :format
                              (tostring condition-lua))
                     (utils.expr condition :expression)))))

(fn SPECIALS.each [ast scope parent]
  (compiler.assert (<= 3 (length ast)) "expected body expression" (. ast 1))
  (let [binding (compiler.assert (utils.table? (. ast 2))
                                 "expected binding table" ast)
        _ (compiler.assert (<= 2 (length binding))
                           "expected binding and iterator" binding)
        until-condition (remove-until-condition binding)
        iter (table.remove binding (length binding))
        ;; last item is iterator call
        destructures []
        new-manglings []
        sub-scope (compiler.make-scope scope)]
    (fn destructure-binding [v]
      (compiler.assert (not (utils.string? v))
                       (.. "unexpected iterator clause " (tostring v)) binding)
      (if (utils.sym? v)
          (compiler.declare-local v [] sub-scope ast new-manglings)
          (let [raw (utils.sym (compiler.gensym sub-scope))]
            (tset destructures raw v)
            (compiler.declare-local raw [] sub-scope ast))))

    (let [bind-vars (utils.map binding destructure-binding)
          vals (compiler.compile1 iter scope parent)
          val-names (utils.map vals tostring)
          chunk []]
      (compiler.emit parent
                     (: "for %s in %s do" :format (table.concat bind-vars ", ")
                        (table.concat val-names ", ")) ast)
      (each [raw args (utils.stablepairs destructures)]
        (compiler.destructure args raw ast sub-scope chunk
                              {:declaration true :nomulti true :symtype :each}))
      (compiler.apply-manglings sub-scope new-manglings ast)
      (compile-until until-condition sub-scope chunk)
      (compile-do ast sub-scope chunk 3)
      (compiler.emit parent chunk ast)
      (compiler.emit parent :end ast))))

(doc-special :each ["[key value (iterator)]" "..."]
             "Runs the body once for each set of values provided by the given iterator.
Most commonly used with ipairs for sequential tables or pairs for  undefined
order, but can be used with any iterator." true)

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

(tset SPECIALS :while while*)

(doc-special :while [:condition "..."]
             "The classic while loop. Evaluates body until a condition is non-truthy."
             true)

(fn for* [ast scope parent]
  (let [ranges (compiler.assert (utils.table? (. ast 2))
                                "expected binding table" ast)
        until-condition (remove-until-condition (. ast 2))
        binding-sym (table.remove (. ast 2) 1)
        sub-scope (compiler.make-scope scope)
        range-args []
        chunk []]
    (compiler.assert (utils.sym? binding-sym)
                     (: "unable to bind %s %s" :format (type binding-sym)
                        (tostring binding-sym)) (. ast 2))
    (compiler.assert (<= 3 (length ast)) "expected body expression" (. ast 1))
    (compiler.assert (<= (length ranges) 3) "unexpected arguments" (. ranges 4))
    (for [i 1 (math.min (length ranges) 3)]
      (tset range-args i (tostring (. (compiler.compile1 (. ranges i) scope
                                                         parent {:nval 1}) 1))))
    (compiler.emit parent
                   (: "for %s = %s do" :format
                      (compiler.declare-local binding-sym [] sub-scope ast)
                      (table.concat range-args ", ")) ast)
    (compile-until until-condition sub-scope chunk)
    (compile-do ast sub-scope chunk 3)
    (compiler.emit parent chunk ast)
    (compiler.emit parent :end ast)))

(tset SPECIALS :for for*)

(doc-special :for ["[index start stop step?]" "..."]
             "Numeric loop construct.
Evaluates body once for each value between start and stop (inclusive)." true)

(fn native-method-call [ast _scope _parent target args]
  "Prefer native Lua method calls when method name is a valid Lua identifier."
  (let [[_ _ method-string] ast
        call-string (if (or (= target.type :literal)
                            (= target.type :varg)
                            (= target.type :expression))
                        "(%s):%s(%s)" "%s:%s(%s)")]
    (utils.expr (string.format call-string (tostring target) method-string
                               (table.concat args ", "))
                :statement)))

(fn nonnative-method-call [ast scope parent target args]
  "When we don't have to protect against double-evaluation, it's not so bad."
  (let [method-string (tostring (. (compiler.compile1 (. ast 3) scope parent
                                                      {:nval 1})
                                   1))
        args [(tostring target) (unpack args)]]
    (utils.expr (string.format "%s[%s](%s)" (tostring target) method-string
                               (table.concat args ", "))
                :statement)))

(fn double-eval-protected-method-call [ast scope parent target args]
  "When double-evaluation is a concern, we have to wrap an IIFE."
  (let [method-string (tostring (. (compiler.compile1 (. ast 3) scope parent
                                                      {:nval 1})
                                   1))
        call "(function(tgt, m, ...) return tgt[m](tgt, ...) end)(%s, %s)"]
    (table.insert args 1 method-string)
    (utils.expr (string.format call (tostring target) (table.concat args ", "))
                :statement)))

(fn method-call [ast scope parent]
  (compiler.assert (< 2 (length ast)) "expected at least 2 arguments" ast)
  (let [[target] (compiler.compile1 (. ast 2) scope parent {:nval 1})
        args []]
    (for [i 4 (length ast)]
      (let [subexprs (compiler.compile1 (. ast i) scope parent
                                        {:nval (if (not= i (length ast)) 1)})]
        (utils.map subexprs tostring args)))
    (if (and (utils.string? (. ast 3))
             (utils.valid-lua-identifier? (. ast 3)))
        (native-method-call ast scope parent target args)
        (= target.type :sym)
        (nonnative-method-call ast scope parent target args)
        ;; When the target is an expression, we can't use the naive
        ;; nonnative-method-call approach, because it will cause the target
        ;; to be evaluated twice. This is fine if it's a symbol but if it's
        ;; the result of a function call, that function could have side-effects.
        ;; See test-short-circuit in test/misc.fnl for an example of the problem.
        (double-eval-protected-method-call ast scope parent target args))))

(tset SPECIALS ":" method-call)

(doc-special ":" [:tbl :method-name "..."] "Call the named method on tbl with the provided args.
Method name doesn't have to be known at compile-time; if it is, use
(tbl:method-name ...) instead.")

(fn SPECIALS.comment [ast _ parent]
  (let [els []]
    (for [i 2 (length ast)]
      (table.insert els (view (. ast i) {:one-line? true})))
    (compiler.emit parent (.. "--[[ " (table.concat els " ") " ]]") ast)))

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
    (compiler.declare-local symbol [] scope ast)
    (for [i 1 9]
      (tset args i (compiler.declare-local (utils.sym (.. "$" i)) [] f-scope
                                           ast)))
    ;; recursively walk the AST, transforming $... into ...

    (fn walker [idx node parent-node]
      (if (and (utils.sym? node) (= (tostring node) "$..."))
          (do
            (tset parent-node idx (utils.varg))
            (set f-scope.vararg true))
          (or (utils.list? node) (utils.table? node))))

    (utils.walk-tree (. ast 2) walker)
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

;; Spice in a do to trigger an IIFE to ensure we short-circuit certain
;; side-effects. without this (or true (tset t :a 1)) doesn't short circuit:
;; https://todo.sr.ht/~technomancy/fennel/111
(fn maybe-short-circuit-protect [ast i name {:macros mac}]
  (let [call (and (utils.list? ast) (tostring (. ast 1)))]
    (if (and (or (= :or name) (= :and name)) (< 1 i)
             ;; dangerous specials (or a macro which could be anything)
             (or (. mac call) (= :set call) (= :tset call) (= :global call)))
        (utils.list (utils.sym :do) ast)
        ast)))

(fn arithmetic-special [name zero-arity unary-prefix ast scope parent]
  (let [len (length ast) operands []
        padded-op (.. " " name " ")]
    (for [i 2 len]
      (let [subast (maybe-short-circuit-protect (. ast i) i name scope)
            subexprs (compiler.compile1 subast scope parent)]
        (if (= i len)
            ;; last arg gets all its exprs but everyone else only gets one
            (utils.map subexprs tostring operands)
            (table.insert operands (tostring (. subexprs 1))))))
    (match (length operands)
      0 (utils.expr (doto zero-arity
                      (compiler.assert "Expected more than 0 arguments" ast))
                    :literal)
      1 (if unary-prefix
            (.. "(" unary-prefix padded-op (. operands 1) ")")
            (. operands 1))
      _ (.. "(" (table.concat operands padded-op) ")"))))

(fn define-arithmetic-special [name zero-arity unary-prefix ?lua-name]
  (tset SPECIALS name (partial arithmetic-special (or ?lua-name name) zero-arity
                               unary-prefix))
  (doc-special name [:a :b "..."]
               "Arithmetic operator; works the same as Lua but accepts more arguments."))

(define-arithmetic-special "+" :0)
(define-arithmetic-special ".." "''")
(define-arithmetic-special "^")
(define-arithmetic-special "-" nil "")
(define-arithmetic-special "*" :1)
(define-arithmetic-special "%")
(define-arithmetic-special "/" nil :1)
(define-arithmetic-special "//" nil :1)

(fn SPECIALS.or [ast scope parent]
  (arithmetic-special :or :false nil ast scope parent))

(fn SPECIALS.and [ast scope parent]
  (arithmetic-special :and :true nil ast scope parent))

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
            (utils.map subexprs tostring operands)))
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
(define-bitop-special :band :0 :0 "&")
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

(doc-special ".." [:a :b "..."]
             "String concatenation operator; works the same as Lua but accepts more arguments.")

(fn native-comparator [op [_ lhs-ast rhs-ast] scope parent]
  "Naively compile a binary comparison to Lua."
  (let [[lhs] (compiler.compile1 lhs-ast scope parent {:nval 1})
        [rhs] (compiler.compile1 rhs-ast scope parent {:nval 1})]
    (string.format "(%s %s %s)" (tostring lhs) op (tostring rhs))))

(fn double-eval-protected-comparator [op chain-op ast scope parent]
  "Compile a multi-arity comparison to a binary Lua comparison."
  (let [arglist []
        comparisons []
        vals []
        chain (string.format " %s " (or chain-op :and))]
    (for [i 2 (length ast)]
      (table.insert arglist (tostring (compiler.gensym scope)))
      (table.insert vals (tostring (. (compiler.compile1 (. ast i) scope parent
                                                         {:nval 1})
                                      1))))
    (for [i 1 (- (length arglist) 1)]
      (table.insert comparisons
                    (string.format "(%s %s %s)" (. arglist i) op
                                   (. arglist (+ i 1)))))
    ;; The function call here introduces some overhead, but it is the only way
    ;; to compile this safely while preventing both double-evaluation of
    ;; side-effecting values and early evaluation of values which should never
    ;; happen in the case of a short-circuited call. See test-short-circuit in
    ;; test/misc.fnl for an example of the problem.
    (string.format "(function(%s) return %s end)(%s)"
                   (table.concat arglist ",") (table.concat comparisons chain)
                   (table.concat vals ","))))

(fn define-comparator-special [name ?lua-op ?chain-op]
  (let [op (or ?lua-op name)]
    (fn opfn [ast scope parent]
      (compiler.assert (< 2 (length ast)) "expected at least two arguments" ast)
      (if (= 3 (length ast))
          (native-comparator op ast scope parent)
          (double-eval-protected-comparator op ?chain-op ast scope parent)))

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
      (.. (or ?realop op) (tostring (. tail 1)))))

  (tset SPECIALS op opfn))

(define-unary-special :not "not ")
(doc-special :not [:x] "Logical operator; works the same as Lua.")
(define-unary-special :bnot "~")
(doc-special :bnot [:x] "Bitwise negation; only works in Lua 5.3+ or LuaJIT with the --use-bit-lib flag.")
(define-unary-special :length "#")
(doc-special :length [:x] "Returns the length of a table or string.")

;; backwards-compatibility aliases
(tset SPECIALS "~=" (. SPECIALS :not=))
(tset SPECIALS "#" (. SPECIALS :length))

(fn SPECIALS.quote [ast scope parent]
  (compiler.assert (= (length ast) 2) "expected one argument" ast)
  (var (runtime this-scope) (values true scope))
  (while this-scope
    (set this-scope this-scope.parent)
    (when (= this-scope compiler.scopes.compiler)
      (set runtime false)))
  (compiler.do-quote (. ast 2) scope parent runtime))

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

;; Circularity
(var safe-require nil)

(fn safe-compiler-env []
  {:table (utils.copy table)
   :math (utils.copy math)
   :string (utils.copy string)
   :pairs utils.stablepairs
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
  (let [provided (match (or ?opts utils.root.options)
                   {:compiler-env :strict} (safe-compiler-env)
                   {: compilerEnv} compilerEnv
                   {: compiler-env} compiler-env
                   _ (safe-compiler-env false))
        env {:_AST ast
             :_CHUNK parent
             :_IS_COMPILER true
             :_SCOPE scope
             :_SPECIALS compiler.scopes.global.specials
             :_VARARG (utils.varg) ; don't use this!
             : macro-loaded
             : unpack
             :assert-compile compiler.assert
             : view
             :version utils.version
             :metadata compiler.metadata
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
                   :pathmark (or pathmark ";")
                   :pathsep (or pathsep "?")})

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
      (let [filename (path:gsub (escapepat pkg-config.pathmark) no-dot-module)
            filename2 (: path :gsub (escapepat pkg-config.pathmark) modulename)]
        (match (or (io.open filename) (io.open filename2))
          file (do
                 (file:close)
                 filename)
          _ (values nil (.. "no file '" filename "'")))))

    (fn find-in-path [start ?tried-paths]
      (match (fullpath:match pattern start)
        path (match (try-path path)
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
      (match (search-module module-name)
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
    (match (search-module module-name utils.fennel-module.macro-path)
      filename (values (if (= opts.compiler-env _G)
                           (partial dofile-with-searcher fennel-macro-searcher
                                    filename opts)
                           (partial utils.fennel-module.dofile filename opts))
                       filename))))

(fn lua-macro-searcher [module-name]
  (match (search-module module-name package.path)
    filename (let [code (with-open [f (io.open filename)] (assert (f:read :*a)))
                   chunk (load-code code (make-compiler-env) filename)]
               (values chunk filename))))

(local macro-searchers [fennel-macro-searcher lua-macro-searcher])

(fn search-macro-module [modname n]
  (match (. macro-searchers n)
    f (match (f modname)
        (loader ?filename) (values loader ?filename)
        _ (search-macro-module modname (+ n 1)))))

(fn sandbox-fennel-module [modname]
  "Let limited Fennel module thru with safe fields."
  ;; TODO: why fennel.macros here? should never be required.
  (if (or (= modname :fennel.macros)
          (and package package.loaded
               (= :table (type (. package.loaded modname)))
               (= (. package.loaded modname :metadata) compiler.metadata)))
      ;; should never be needed to use view thru here since it's global in
      ;; macro scope, but it's not obvious, so allow this to be used as well.
      {:metadata compiler.metadata : view}))

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
    (if (= :import-macros (tostring (. ast 1)))
        (. macro-loaded modname)
        (add-macros (. macro-loaded modname) ast scope parent))))

(doc-special :require-macros [:macro-module-name]
             "Load given module and use its contents as macro definitions in current scope.
Macro module should return a table of macro functions with string keys.
Consider using import-macros instead as it is more flexible.")

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
  (let [modexpr (match (pcall resolve-module-name ast scope parent opts)
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
                      ;; Find path to Fennel or Lua source; prefering Fennel
                      (match (search-module mod)
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
    ((load-code (compiler.compile ast opts) (wrap-env env)) opts.module-name
                                                            ast.filename)))

(fn SPECIALS.macros [ast scope parent]
  (compiler.assert (= (length ast) 2) "Expected one table argument" ast)
  (add-macros (eval-compiler* (. ast 2) scope parent) ast scope parent))

(doc-special :macros
             ["{:macro-name-1 (fn [...] ...) ... :macro-name-N macro-body-N}"]
             "Define all functions in the given table as macros local to the current scope.")

(fn SPECIALS.eval-compiler [ast scope parent]
  (let [old-first (. ast 1)]
    (tset ast 1 (utils.sym :do))
    (let [val (eval-compiler* ast scope parent)]
      (tset ast 1 old-first)
      val)))

(doc-special :eval-compiler ["..."]
             "Evaluate the body at compile-time. Use the macro system instead if possible."
             true)

{:doc doc*
 : current-global-names
 : load-code
 : macro-loaded
 : macro-searchers
 : make-compiler-env
 : search-module
 : make-searcher
 : wrap-env}
