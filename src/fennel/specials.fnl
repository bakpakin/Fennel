(local utils (require "fennel.utils"))
(local parser (require "fennel.parser"))
(local compiler (require "fennel.compiler"))
(local unpack (or _G.unpack table.unpack))

(local SPECIALS compiler.scopes.global.specials)

(fn wrapEnv [env]
  "Convert a fennel environment table to a Lua environment table.
This means automatically unmangling globals when getting a value,
and mangling values when setting a value. This means the original env
will see its values updated as expected, regardless of mangling rules."
  (setmetatable
   [] {:__index (fn [_ key]
                  (if (= (type key) "string")
                      (. env (compiler.globalUnmangling key))
                      (. env key)))
       :__newindex (fn [_ key value]
                     (if (= (type key) "string")
                         (tset env (compiler.globalMangling key) value)
                         (tset env key value)))
       ;; checking the __pairs metamethod won't work automatically in Lua 5.1
       ;; sadly, but it's important for 5.2+ and can be done manually in 5.1
       :__pairs (fn []
                  (fn putenv [k v]
                    (values (if (= (type k) "string")
                                (compiler.globalUnmangling k) k) v))
                  (values next (utils.kvmap env putenv) nil))}))

(fn currentGlobalNames [env]
  (utils.kvmap (or env _G) compiler.globalUnmangling))

(fn loadCode [code environment filename]
  "Load code with an environment in all recent Lua versions"
  (let [environment (or (or environment _ENV) _G)]

    (if (and _G.setfenv _G.loadstring)
        (let [f (assert (_G.loadstring code filename))]
          (_G.setfenv f environment)
          f)
        (assert (load code filename "t" environment)))))

(fn doc* [tgt name]
  "Return a docstring for tgt."
  (if (not tgt)
      (.. name " not found")
      (let [docstring (: (: (or (: compiler.metadata "get" tgt "fnl/docstring")
                                "#<undocumented>") :gsub "\n$" "")
                         :gsub "\n" "\n  ")]
        (if (= (type tgt) "function")
            (let [arglist (table.concat (or (: compiler.metadata "get"
                                               tgt "fnl/arglist")
                                            ["#<unknown-arguments>"]) " ")]
              (string.format "(%s%s%s)\n  %s" name
                             (if (> (# arglist) 0) " " "") arglist docstring))
            (string.format "%s\n  %s" name docstring)))))

;; TODO: replace this with using the special fn's own docstring
(fn docSpecial [name arglist docstring]
  "Add a docstring to a special form."
  (tset compiler.metadata (. SPECIALS name) {:fnl/arglist arglist
                                             :fnl/docstring docstring}))

(fn compileDo [ast scope parent start]
  "Compile a list of forms for side effects."
  (let [start (or start 2)
        len (# ast)
        subScope (compiler.makeScope scope)]
    (for [i start len]
      (compiler.compile1 (. ast i) subScope parent {:nval 0}))))

(fn SPECIALS.do [ast scope parent opts start chunk subScope preSyms]
  "Implements a do statement, starting at the 'start'-th element.
By default, start is 2."
  (let [start (or start 2)
        subScope (or subScope (compiler.makeScope scope))
        chunk (or chunk [])
        len (# ast)]
    (var outerTarget opts.target)
    (var outerTail opts.tail)
    (var retexprs {:returned true})

    ;; See if we need special handling to get the return values of the do block
    (if (and (not outerTarget)
             (not= opts.nval 0)
             (not outerTail))
        (if opts.nval
            ;; generate a local target
            (let [syms []]
              (for [i 1 opts.nval 1]
                (local s (or (and preSyms (. preSyms i)) (compiler.gensym scope)))
                (tset syms i s)
                (tset retexprs i (utils.expr s "sym")))
              (set outerTarget (table.concat syms ", "))
              (compiler.emit parent (: "local %s" :format outerTarget) ast)
              (compiler.emit parent "do" ast))
            ;; we will use an IIFE for the do
            (let [fname (compiler.gensym scope)
                  fargs (or (and scope.vararg "...") "")]
              (compiler.emit parent (: "local function %s(%s)" :format
                                       fname fargs) ast)
              (set retexprs (utils.expr (.. fname "(" fargs ")") "statement"))
              (set outerTail true)
              (set outerTarget nil)))
        (compiler.emit parent "do" ast))
    ;; Compile the body
    (if (< len start)
        ;; In the unlikely event we do a do with no arguments
        (compiler.compile1 nil subScope chunk {:tail outerTail
                                               :target outerTarget})
        ;; There will be side-effects
        (for [i start len]
          (let [subopts {:nval (or (and (not= i len) 0) opts.nval)
                         :tail (or (and (= i len) outerTail) nil)
                         :target (or (and (= i len) outerTarget) nil)}]
            (utils.propagateOptions opts subopts)
            (local subexprs (compiler.compile1 (. ast i) subScope chunk subopts))
            (when (not= i len)
              (compiler.keepSideEffects subexprs parent nil (. ast i))))))
    (compiler.emit parent chunk ast)
    (compiler.emit parent "end" ast)
    retexprs))

(docSpecial "do" ["..."] "Evaluate multiple forms; return last value.")

(fn SPECIALS.values [ast scope parent]
  "Unlike most expressions and specials, 'values' resolves with multiple
values, one for each argument, allowing multiple return values. The last
expression can return multiple arguments as well, allowing for more than
the number of expected arguments."
  (let [len (# ast)
        exprs []]
    (for [i 2 len]
      (let [subexprs (compiler.compile1 (. ast i) scope parent
                                        {:nval (and (not= i len) 1)})]
        (tset exprs (+ (# exprs) 1) (. subexprs 1))
        (when (= i len)
          (for [j 2 (# subexprs) 1]
            (tset exprs (+ (# exprs) 1) (. subexprs j))))))
    exprs))

(docSpecial "values" ["..."]
            "Return multiple values from a function. Must be in tail position.")

(fn SPECIALS.fn [ast scope parent]
  (var (index fnName isLocalFn docstring) (values 2 (utils.isSym (. ast 2))))
  (let [fScope (doto (compiler.makeScope scope)
                 (tset :vararg false))
        fChunk []
        multi (and fnName (utils.isMultiSym (. fnName 1)))]
    (compiler.assert (or (not multi) (not multi.multiSymMethodCall))
                     (.. "unexpected multi symbol " (tostring fnName))
                     (. ast index))

    (if (and fnName (not= (. fnName 1) "nil"))
        (do (set isLocalFn (not multi))
            (if isLocalFn
                (set fnName (compiler.declareLocal fnName [] scope ast))
                (set fnName (. (compiler.symbolToExpression fnName scope) 1)))
            (set index (+ index 1)))
        (do (set isLocalFn true)
            (set fnName (compiler.gensym scope))))

    (let [argList (compiler.assert (utils.isTable (. ast index))
                                   "expected parameters"
                                   (if (= (type (. ast index)) "table")
                                       (. ast index) ast))]
      (fn getArgName [i name]
        (if (utils.isVarg name)
            (do (compiler.assert (= i (# argList))
                                 "expected vararg as last parameter" (. ast 2))
                (set fScope.vararg true)
                "...")
            (and (utils.isSym name)
                 (not= (utils.deref name) "nil")
                 (not (utils.isMultiSym (utils.deref name))))
            (compiler.declareLocal name [] fScope ast)
            (utils.isTable name)
            (let [raw (utils.sym (compiler.gensym scope))
                  declared (compiler.declareLocal raw [] fScope ast)]
              (compiler.destructure name raw ast fScope fChunk {:declaration true
                                                                :nomulti true})
              declared)
            (compiler.assert false
                             (: "expected symbol for function parameter: %s"
                                :format (tostring name)) (. ast 2))))
      (local argNameList (utils.kvmap argList getArgName))
      (when (and (= (type (. ast (+ index 1))) "string") (< (+ index 1) (# ast)))
        (set index (+ index 1))
        (set docstring (. ast index)))

      (for [i (+ index 1) (# ast) 1]
        (compiler.compile1 (. ast i) fScope fChunk
                           {:nval (or (and (not= i (# ast)) 0) nil)
                            :tail (= i (# ast))}))
      (if isLocalFn
          (compiler.emit parent (: "local function %s(%s)" :format
                                   fnName (table.concat argNameList ", ")) ast)
          (compiler.emit parent (: "%s = function(%s)" :format
                                   fnName (table.concat argNameList ", ")) ast))
      (compiler.emit parent fChunk ast)
      (compiler.emit parent "end" ast)
      (when utils.root.options.useMetadata
        ;; TODO: show destructured args properly instead of replacing
        (let [args (utils.map argList (fn [v] (if (utils.isTable v)
                                                  "\"#<table>\""
                                                  (: "\"%s\"" :format
                                                     (tostring v)))))
              metaFields ["\"fnl/arglist\"" (.. "{" (table.concat args ", ") "}")]]
          (when docstring
            (table.insert metaFields "\"fnl/docstring\"")
            (table.insert metaFields (.. "\"" (-> docstring
                                                  (: :gsub "%s+$" "")
                                                  (: :gsub "\\" "\\\\")
                                                  (: :gsub "\n" "\\n")
                                                  (: :gsub "\"" "\\\"")) "\"")))
          (let [metaStr (: "require(\"%s\").metadata"
                           :format (or utils.root.options.moduleName "fennel"))]
            (compiler.emit parent (: "pcall(function() %s:setall(%s, %s) end)"
                                     :format metaStr fnName
                                     (table.concat metaFields ", ")))))))
    (utils.expr fnName "sym")))

(docSpecial "fn" ["name?" "args" "docstring?" "..."]
            (.. "Function syntax. May optionally include a name and docstring.
If a name is provided, the function will be bound in the current scope.
When called with the wrong number of args, excess args will be discarded
and lacking args will be nil, use lambda for arity-checked functions."))

;; FORBIDDEN KNOWLEDGE:
;; (lua "print('hello!')") -> prints hello, evaluates to nil
;; (lua "print 'hello!'" "10") -> prints hello, evaluates to the number 10
;; (lua nil "{1,2,3}") -> Evaluates to a table literal
(fn SPECIALS.lua [ast _ parent]
  (compiler.assert (or (= (# ast) 2) (= (# ast) 3))
                   "expected 1 or 2 arguments" ast)
  (when (not= (. ast 2) nil)
    (table.insert parent {:ast ast :leaf (tostring (. ast 2))}))
  (when (= (# ast) 3)
    (tostring (. ast 3))))

(fn SPECIALS.doc [ast scope parent]
  (assert utils.root.options.useMetadata
          "can't look up doc with metadata disabled.")
  (compiler.assert (= (# ast) 2) "expected one argument" ast)
  (let [target (utils.deref (. ast 2))
        specialOrMacro (or (. scope.specials target) (. scope.macros target))]
    (if specialOrMacro
        (: "print([[%s]])" :format (doc* specialOrMacro target))
        (let [value (tostring (. (compiler.compile1 (. ast 2)
                                                    scope parent {:nval 1}) 1))]
          ;; need to require here since the metadata is stored in the module
          ;; and we need to make sure we look it up in the same module it was
          ;; declared from.
          (: "print(require('%s').doc(%s, '%s'))" :format
             (or utils.root.options.moduleName "fennel") value
             (tostring (. ast 2)))))))

(docSpecial
 "doc" ["x"]
 "Print the docstring and arglist for a function, macro, or special form.")

(fn dot [ast scope parent]
  "Table lookup; equivalent to tbl[] in Lua."
  (compiler.assert (< 1 (# ast)) "expected table argument" ast)
  (let [len (# ast)
        lhs (compiler.compile1 (. ast 2) scope parent {:nval 1})]
    (if (= len 2)
        (tostring (. lhs 1))
        (let [indices []]
          (for [i 3 len 1]
            (var index (. ast i))
            (if (and (= (type index) "string")
                     (utils.isValidLuaIdentifier index))
                (table.insert indices (.. "." index))
                (do
                  (set index (. (compiler.compile1 index scope parent {:nval 1})
                                1))
                  (table.insert indices (.. "[" (tostring index) "]")))))
          ;; Extra parens are needed for table literals.
          (if (utils.isTable (. ast 2))
              (.. "(" (tostring (. lhs 1)) ")" (table.concat indices))
              (.. (tostring (. lhs 1)) (table.concat indices)))))))

(tset SPECIALS "." dot)

(docSpecial
 "." ["tbl" "key1" "..."]
 "Look up key1 in tbl table. If more args are provided, do a nested lookup.")

(fn SPECIALS.global [ast scope parent]
  (compiler.assert (= (# ast) 3) "expected name and value" ast)
  (compiler.destructure (. ast 2) (. ast 3) ast scope parent {:forceglobal true
                                                              :nomulti true}))

(docSpecial "global" ["name" "val"] "Set name as a global with val.")

(fn SPECIALS.set [ast scope parent]
  (compiler.assert (= (# ast) 3) "expected name and value" ast)
  (compiler.destructure (. ast 2) (. ast 3) ast scope parent {:noundef true}))

(docSpecial
 "set" ["name" "val"]
 "Set a local variable to a new value. Only works on locals using var.")

(fn set-forcibly!* [ast scope parent]
  (compiler.assert (= (# ast) 3) "expected name and value" ast)
  (compiler.destructure (. ast 2) (. ast 3) ast scope parent {:forceset true}))
(tset SPECIALS :set-forcibly! set-forcibly!*)

(fn local* [ast scope parent]
  (compiler.assert (= (# ast) 3) "expected name and value" ast)
  (compiler.destructure (. ast 2) (. ast 3) ast scope parent {:declaration true
                                                              :nomulti true}))
(tset SPECIALS "local" local*)

(docSpecial "local" ["name" "val"] "Introduce new top-level immutable local.")

(fn SPECIALS.var [ast scope parent]
  (compiler.assert (= (# ast) 3) "expected name and value" ast)
  (compiler.destructure (. ast 2) (. ast 3) ast scope parent {:declaration true
                                                              :isvar true
                                                              :nomulti true}))

(docSpecial "var" ["name" "val"] "Introduce new mutable local.")

;; TODO: replace this with a macro emitting do+local
(fn SPECIALS.let [ast scope parent opts]
  (let [bindings (. ast 2)
        preSyms []]
    (compiler.assert (or (utils.isList bindings) (utils.isTable bindings))
                     "expected binding table" ast)
    (compiler.assert (= (% (# bindings) 2) 0)
                     "expected even number of name/value bindings" (. ast 2))
    (compiler.assert (>= (# ast) 3) "expected body expression" (. ast 1))
    ;; we have to gensym the binding for the let body's return value before
    ;; compiling the binding vector, otherwise there's a possibility to conflict
    (for [_ 1 (or opts.nval 0) 1]
      (table.insert preSyms (compiler.gensym scope)))
    (let [subScope (compiler.makeScope scope)
          subChunk []]
      (for [i 1 (# bindings) 2]
        (compiler.destructure (. bindings i) (. bindings (+ i 1))
                              ast subScope subChunk {:declaration true
                                                     :nomulti true}))
      (SPECIALS.do ast scope parent opts 3 subChunk subScope preSyms))))

(docSpecial
 "let" ["[name1 val1 ... nameN valN]" "..."]
 "Introduces a new scope in which a given set of local bindings are used.")

(fn SPECIALS.tset [ast scope parent]
  "For setting items in a table."
  (compiler.assert (> (# ast) 3) "expected table, key, and value arguments" ast)
  (let [root (. (compiler.compile1 (. ast 2) scope parent {:nval 1}) 1)
        keys []]
    (for [i 3 (- (# ast) 1) 1]
      (let [key (. (compiler.compile1 (. ast i) scope parent {:nval 1}) 1)]
        (tset keys (+ (# keys) 1) (tostring key))))
    (let [value (. (compiler.compile1 (. ast (# ast)) scope parent {:nval 1}) 1)
          rootstr (tostring root)
          ;; Prefix 'do end ' so parens are not ambiguous (grouping or fn call?)
          fmtstr (if (: rootstr :match "^{") "do end (%s)[%s] = %s" "%s[%s] = %s")]
      (compiler.emit parent (: fmtstr :format (tostring root)
                               (table.concat keys "][") (tostring value)) ast))))

(docSpecial
 "tset" ["tbl" "key1" "..." "keyN" "val"]
 "Set the value of a table field. Can take additional keys to set
nested values, but all parents must contain an existing table.")

(fn if* [ast scope parent opts]
  (let [doScope (compiler.makeScope scope)
        branches []
        hasElse (and (> (# ast) 3) (= (% (# ast) 2) 0))]
    (var elseBranch nil)
    ;; Calculate some external stuff. Optimizes for tail calls and what not
    (var (wrapper innerTail innerTarget targetExprs) (values))
    (if (or opts.tail opts.target opts.nval)
        (if (and opts.nval (not= opts.nval 0) (not opts.target))
            (let [accum []]
              ;; We need to create a target
              (set targetExprs [])
              (for [i 1 opts.nval 1]
                (let [s (compiler.gensym scope)]
                  (tset accum i s)
                  (tset targetExprs i (utils.expr s "sym"))))
              (set (wrapper innerTail innerTarget)
                   (values "target" opts.tail (table.concat accum ", "))))
            (set (wrapper innerTail innerTarget)
                 (values "none" opts.tail opts.target)))
        (set (wrapper innerTail innerTarget) (values "iife" true nil)))

    ;; compile bodies and conditions
    (local bodyOpts {:nval opts.nval :tail innerTail :target innerTarget})
    (fn compileBody [i]
      (let [chunk []
            cscope (compiler.makeScope doScope)]
        (compiler.keepSideEffects (compiler.compile1 (. ast i) cscope chunk
                                                     bodyOpts) chunk nil
                                                     (. ast i))
        {:chunk chunk :scope cscope}))

    (for [i 2 (- (# ast) 1) 2]
      (let [condchunk []
            res (compiler.compile1 (. ast i) doScope condchunk {:nval 1})
            cond (. res 1)
            branch (compileBody (+ i 1))]
        (set branch.cond cond)
        (set branch.condchunk condchunk)
        (set branch.nested (and (not= i 2) (= (next condchunk nil) nil)))
        (table.insert branches branch)))

    (when hasElse
      (set elseBranch (compileBody (# ast))))

    ;; Emit code
    (let [s (compiler.gensym scope)
          buffer []]
      (var lastBuffer buffer)
      (for [i 1 (# branches)]
        (let [branch (. branches i)
              fstr (if (not branch.nested) "if %s then" "elseif %s then")
              cond (tostring branch.cond)
              condLine (if (and (= cond :true) branch.nested (= i (# branches)))
                           :else
                           (: fstr :format cond))]
          (if branch.nested
              (compiler.emit lastBuffer branch.condchunk ast)
              (each [_ v (ipairs branch.condchunk)]
                (compiler.emit lastBuffer v ast)))
          (compiler.emit lastBuffer condLine ast)
          (compiler.emit lastBuffer branch.chunk ast)
          (if (= i (# branches))
              (do
                (if hasElse
                    (do (compiler.emit lastBuffer "else" ast)
                        (compiler.emit lastBuffer elseBranch.chunk ast))
                    ;; TODO: Consolidate use of condLine ~= "else" with hasElse
                    (and innerTarget (not= condLine "else"))
                    (do (compiler.emit lastBuffer "else" ast)
                        (compiler.emit lastBuffer (: "%s = nil" :format
                                                     innerTarget) ast)))
                (compiler.emit lastBuffer "end" ast))
              (not (. (. branches (+ i 1)) "nested"))
              (let [nextBuffer []]
                (compiler.emit lastBuffer "else" ast)
                (compiler.emit lastBuffer nextBuffer ast)
                (compiler.emit lastBuffer "end" ast)
                (set lastBuffer nextBuffer)))))
      (if (= wrapper "iife")
          (let [iifeargs (or (and scope.vararg "...") "")]
            (compiler.emit parent (: "local function %s(%s)" :format
                                     (tostring s) iifeargs) ast)
            (compiler.emit parent buffer ast)
            (compiler.emit parent "end" ast)
            (utils.expr (: "%s(%s)" :format (tostring s) iifeargs) :statement))
          (= wrapper "none") ; Splice result right into code
          (do (for [i 1 (# buffer) 1]
                (compiler.emit parent (. buffer i) ast))
              {:returned true})
          ;; wrapper is target
          (do (compiler.emit parent (: "local %s" :format innerTarget) ast)
              (for [i 1 (# buffer) 1]
                (compiler.emit parent (. buffer i) ast))
              targetExprs)))))

(tset SPECIALS "if" if*)

(docSpecial
 "if" ["cond1" "body1" "..." "condN" "bodyN"]
 "Conditional form.
Takes any number of condition/body pairs and evaluates the first body where
the condition evaluates to truthy. Similar to cond in other lisps.")

(fn SPECIALS.each [ast scope parent]
  (compiler.assert (>= (# ast) 3) "expected body expression" (. ast 1))
  (let [binding (compiler.assert (utils.isTable (. ast 2))
                                 "expected binding table" ast)
        iter (table.remove binding (# binding)) ; last item is iterator call
        destructures []
        newManglings []
        subScope (compiler.makeScope scope)]

    (fn destructureBinding [v]
      (if (utils.isSym v)
          (compiler.declareLocal v [] subScope ast newManglings)
          (let [raw (utils.sym (compiler.gensym subScope))]
            (tset destructures raw v)
            (compiler.declareLocal raw [] subScope ast))))

    (let [bindVars (utils.map binding destructureBinding)
          vals (compiler.compile1 iter subScope parent)
          valNames (utils.map vals tostring)
          chunk []]
      (compiler.emit parent (: "for %s in %s do" :format
                               (table.concat bindVars ", ")
                               (table.concat valNames ", ")) ast)
      (each [raw args (utils.stablepairs destructures)]
        (compiler.destructure args raw ast subScope chunk {:declaration true
                                                           :nomulti true}))
      (compiler.applyManglings subScope newManglings ast)
      (compileDo ast subScope chunk 3)
      (compiler.emit parent chunk ast)
      (compiler.emit parent "end" ast))))

(docSpecial
 "each" ["[key value (iterator)]" "..."]
 "Runs the body once for each set of values provided by the given iterator.
Most commonly used with ipairs for sequential tables or pairs for  undefined
order, but can be used with any iterator.")

(fn while* [ast scope parent]
  (let [len1 (# parent)
        condition (. (compiler.compile1 (. ast 2) scope parent {:nval 1}) 1)
        len2 (# parent)
        subChunk []]
    (if (not= len1 len2)
        ;; compound condition; move new compilation to subchunk
        (do
          (for [i (+ len1 1) len2 1]
            (tset subChunk (+ (# subChunk) 1) (. parent i))
            (tset parent i nil))
          (compiler.emit parent "while true do" ast)
          (compiler.emit subChunk (: "if not %s then break end"
                                     :format (. condition 1)) ast))
        ;; simple condition
        (compiler.emit parent (.. "while " (tostring condition) " do") ast))
    (compileDo ast (compiler.makeScope scope) subChunk 3)
    (compiler.emit parent subChunk ast)
    (compiler.emit parent "end" ast)))

(tset SPECIALS "while" while*)

(docSpecial
 "while" ["condition" "..."]
 "The classic while loop. Evaluates body until a condition is non-truthy.")

(fn for* [ast scope parent]
  (let [ranges (compiler.assert (utils.isTable (. ast 2))
                                "expected binding table" ast)
        bindingSym (table.remove (. ast 2) 1)
        subScope (compiler.makeScope scope)
        rangeArgs []
        chunk []]
    (compiler.assert (utils.isSym bindingSym)
                     (: "unable to bind %s %s" :format
                        (type bindingSym) (tostring bindingSym)) (. ast 2))
    (compiler.assert (>= (# ast) 3)
                     "expected body expression" (. ast 1))
    (for [i 1 (math.min (# ranges) 3) 1]
      (tset rangeArgs i (tostring (. (compiler.compile1 (. ranges i) subScope
                                                        parent {:nval 1}) 1))))
    (compiler.emit parent (: "for %s = %s do" :format
                             (compiler.declareLocal bindingSym [] subScope ast)
                             (table.concat rangeArgs ", ")) ast)
    (compileDo ast subScope chunk 3)
    (compiler.emit parent chunk ast)
    (compiler.emit parent "end" ast)))
(tset SPECIALS "for" for*)

(docSpecial
 "for" ["[index start stop step?]" "..."]
 "Numeric loop construct.
Evaluates body once for each value between start and stop (inclusive).")

(fn once [val ast scope parent]
  (if (or (= val.type "statement") (= val.type "expression"))
      (let [s (compiler.gensym scope)]
        (compiler.emit parent (: "local %s = %s" :format s (tostring val)) ast)
        (utils.expr s "sym"))
      val))

(fn method-call [ast scope parent]
  (compiler.assert (>= (# ast) 3) "expected at least 2 arguments" ast)
  ;; Compile object
  (var objectexpr (. (compiler.compile1 (. ast 2) scope parent {:nval 1}) 1))
  (var (methodident methodstring) false)
  (if (and (= (type (. ast 3)) "string") (utils.isValidLuaIdentifier (. ast 3)))
      (do
        (set methodident true)
        (set methodstring (. ast 3)))
      (do
        (set methodstring (tostring (. (compiler.compile1 (. ast 3) scope parent
                                                          {:nval 1}) 1)))
        (set objectexpr (once objectexpr (. ast 2) scope parent))))
  (let [args []] ; compile arguments
    (for [i 4 (# ast) 1]
      (let [subexprs (compiler.compile1 (. ast i) scope parent
                                        {:nval (if (not= i (# ast)) 1 nil)})]
        (utils.map subexprs tostring args)))
    (var fstring nil)
    (if (not methodident)
        (do ; make object the first argument
          (table.insert args 1 (tostring objectexpr))
          (set fstring (if (= objectexpr.type "sym")
                           "%s[%s](%s)"
                           "(%s)[%s](%s)")))
        (or (= objectexpr.type "literal") (= objectexpr.type "expression"))
        (set fstring "(%s):%s(%s)")
        (set fstring "%s:%s(%s)"))
    (utils.expr (: fstring :format (tostring objectexpr) methodstring
                   (table.concat args ", ")) "statement")))

(tset SPECIALS ":" method-call)

(docSpecial
 ":" ["tbl" "method-name" "..."]
 "Call the named method on tbl with the provided args.
Method name doesn't have to be known at compile-time; if it is, use
(tbl:method-name ...) instead.")

(fn SPECIALS.comment [ast _ parent]
  (let [els []]
    (for [i 2 (# ast) 1]
      (tset els (+ (# els) 1) (: (tostring (. ast i)) :gsub "\n" " ")))
    (compiler.emit parent (.. "-- " (table.concat els " ")) ast)))

(docSpecial "comment" ["..."] "Comment which will be emitted in Lua output.")

(fn SPECIALS.hashfn [ast scope parent]
  (compiler.assert (= (# ast) 2) "expected one argument" ast)
  (let [fScope (doto (compiler.makeScope scope)
                 (tset :vararg false)
                 (tset :hashfn true))
        fChunk []
        name (compiler.gensym scope)
        symbol (utils.sym name)]
    (compiler.declareLocal symbol [] scope ast)
    (var args [])
    (for [i 1 9]
      (tset args i (compiler.declareLocal (utils.sym (.. "$" i)) [] fScope ast)))

    ;; recursively walk the AST, transforming $... into ...
    (fn walker [idx node parentNode]
      (if (and (utils.isSym node) (= (utils.deref node) "$..."))
          (do
            (tset parentNode idx (utils.varg))
            (set fScope.vararg true))
          (or (utils.isList node) (utils.isTable node))))
    (utils.walkTree (. ast 2) walker)
    ;; compile body
    (compiler.compile1 (. ast 2) fScope fChunk {:tail true})
    (var maxUsed 0)
    (for [i 1 9 1]
      (when (. (. fScope.symmeta (.. "$" i)) "used")
        (set maxUsed i)))
    (when fScope.vararg
      (compiler.assert (= maxUsed 0)
                       "$ and $... in hashfn are mutually exclusive" ast)
      (set args [(utils.deref (utils.varg))])
      (set maxUsed 1))
    (local argStr (table.concat args ", " 1 maxUsed))
    (compiler.emit parent (: "local function %s(%s)" :format name argStr) ast)
    (compiler.emit parent fChunk ast)
    (compiler.emit parent "end" ast)
    (utils.expr name "sym")))

(docSpecial "hashfn" ["..."]
            "Function literal shorthand; args are either $... OR $1, $2, etc.")

(fn defineArithmeticSpecial [name zeroArity unaryPrefix luaName]
  (let [paddedOp (.. " " (or luaName name) " ")]
    (tset SPECIALS name
          (fn [ast scope parent]
            (local len (# ast))
            (if (= len 1)
                (do
                  (compiler.assert (not= zeroArity nil)
                                   "Expected more than 0 arguments" ast)
                  (utils.expr zeroArity "literal"))
                (let [operands []]
                  (for [i 2 len 1]
                    (let [subexprs (compiler.compile1 (. ast i) scope parent
                                                      {:nval (if (= i 1) 1)})]
                      (utils.map subexprs tostring operands)))
                  (if (= (# operands) 1)
                      (if unaryPrefix
                          (.. "(" unaryPrefix paddedOp (. operands 1) ")")
                          (. operands 1))
                      (.. "(" (table.concat operands paddedOp) ")")))))))
  (docSpecial name ["a" "b" "..."]
              "Arithmetic operator; works the same as Lua but accepts more arguments."))

(defineArithmeticSpecial "+" "0")
(defineArithmeticSpecial ".." "''")
(defineArithmeticSpecial "^")
(defineArithmeticSpecial "-" nil "")
(defineArithmeticSpecial "*" "1")
(defineArithmeticSpecial "%")
(defineArithmeticSpecial "/" nil "1")
(defineArithmeticSpecial "//" nil "1")
(defineArithmeticSpecial "lshift" nil "1" "<<")
(defineArithmeticSpecial "rshift" nil "1" ">>")
(defineArithmeticSpecial "band" "0" "0" "&")
(defineArithmeticSpecial "bor" "0" "0" "|")
(defineArithmeticSpecial "bxor" "0" "0" "~")

(docSpecial "lshift" ["x" "n"]
            "Bitwise logical left shift of x by n bits; only works in Lua 5.3+.")
(docSpecial "rshift" ["x" "n"]
            "Bitwise logical right shift of x by n bits; only works in Lua 5.3+.")
(docSpecial "band" ["x1" "x2"]
            "Bitwise AND of arguments; only works in Lua 5.3+.")
(docSpecial "bor" ["x1" "x2"]
            "Bitwise OR of arguments; only works in Lua 5.3+.")
(docSpecial "bxor" ["x1" "x2"]
            "Bitwise XOR of arguments; only works in Lua 5.3+.")

(defineArithmeticSpecial "or" "false")
(defineArithmeticSpecial "and" "true")

(docSpecial "and" ["a" "b" "..."]
            "Boolean operator; works the same as Lua but accepts more arguments.")
(docSpecial "or" ["a" "b" "..."]
            "Boolean operator; works the same as Lua but accepts more arguments.")
(docSpecial ".." ["a" "b" "..."]
            "String concatenation operator; works the same as Lua but accepts more arguments.")

(fn defineComparatorSpecial [name realop chainOp]
  (let [op (or realop name)]
    (fn opfn [ast scope parent]
      (local len (# ast))
      (compiler.assert (> len 2) "expected at least two arguments" ast)
      (local lhs (. (compiler.compile1 (. ast 2) scope parent {:nval 1}) 1))
      (var lastval (. (compiler.compile1 (. ast 3) scope parent {:nval 1}) 1))
      (when (> len 3) ; avoid double-eval by adding locals for side-effects
        (set lastval (once lastval (. ast 3) scope parent)))
      (var out (: "(%s %s %s)" :format (tostring lhs) op (tostring lastval)))
      (when (> len 3)
        (for [i 4 len] ; variadic comparison
          (let [nextval (once (. (compiler.compile1 (. ast i)
                                                    scope parent
                                                    {:nval 1}) 1)
                              (. ast i) scope parent)]
            (set out (: (.. out " %s (%s %s %s)") :format (or chainOp "and")
                        (tostring lastval) op (tostring nextval)))
            (set lastval nextval)))
        (set out (.. "(" out ")")))
      out)
    (tset SPECIALS name opfn))
  (docSpecial name ["a" "b" "..."]
     "Comparison operator; works the same as Lua but accepts more arguments."))

(defineComparatorSpecial ">")
(defineComparatorSpecial "<")
(defineComparatorSpecial ">=")
(defineComparatorSpecial "<=")
(defineComparatorSpecial "=" "==")
(defineComparatorSpecial "not=" "~=" "or")
(tset SPECIALS "~=" (. SPECIALS "not=")) ; backwards-compatible alias

(fn defineUnarySpecial [op realop]
  (fn opfn [ast scope parent]
    (compiler.assert (= (# ast) 2) "expected one argument" ast)
    (let [tail (compiler.compile1 (. ast 2) scope parent {:nval 1})]
      (.. (or realop op) (tostring (. tail 1)))))
  (tset SPECIALS op opfn))

(defineUnarySpecial "not" "not ")
(docSpecial "not" ["x"] "Logical operator; works the same as Lua.")
(defineUnarySpecial "bnot" "~")
(docSpecial "bnot" ["x"] "Bitwise negation; only works in Lua 5.3+.")
(defineUnarySpecial "length" "#")
(docSpecial "length" ["x"] "Returns the length of a table or string.")

(tset SPECIALS "#" (. SPECIALS "length")) ; backwards-compatible alias

(fn SPECIALS.quote [ast scope parent]
  (compiler.assert (= (# ast) 2) "expected one argument")
  (var (runtime thisScope) (values true scope))
  (while thisScope
    (set thisScope thisScope.parent)
    (when (= thisScope compiler.scopes.compiler)
      (set runtime false)))
  (compiler.doQuote (. ast 2) scope parent runtime))

(docSpecial "quote" ["x"]
            "Quasiquote the following form. Only works in macro/compiler scope.")

(fn makeCompilerEnv [ast scope parent]
  (setmetatable {:_AST ast ; state of compiler
                 :_CHUNK parent
                 :_IS_COMPILER true
                 :_SCOPE scope
                 :_SPECIALS compiler.scopes.global.specials
                 :_VARARG (utils.varg)

                 ;; Useful for macros and meta programming. All of
                 ;; Fennel can be accessed via fennel.myfun, for example
                 ;; (fennel.eval "(print 1)").

                 :fennel utils.fennelModule
                 :unpack unpack

                 ;; AST functions
                 :list utils.list
                 :list? utils.isList
                 :multi-sym? utils.isMultiSym
                 :sequence utils.sequence
                 :sequence? utils.isSequence
                 :sym utils.sym
                 :sym? utils.isSym
                 :table? utils.isTable
                 :varg? utils.isVarg

                 ;; scoping functions
                 :gensym (fn [] (utils.sym (compiler.gensym
                                            (or compiler.scopes.macro scope))))
                 :get-scope (fn [] compiler.scopes.macro)
                 :in-scope? (fn [symbol]
                              (compiler.assert compiler.scopes.macro
                                               "must call from macro" ast)
                              (. compiler.scopes.macro.manglings
                                 (tostring symbol)))
                 :macroexpand
                 (fn [form]
                   (compiler.assert compiler.scopes.macro
                                    "must call from macro" ast)
                   (compiler.macroexpand form compiler.scopes.macro))}
                {:__index (or _ENV _G)}))

;; have searchModule use package.config to process package.path (windows compat)
(local cfg (string.gmatch package.config "([^\n]+)"))
(local (dirsep pathsep pathmark)
       (values (or (cfg) "/") (or (cfg) ";") (or (cfg) "?")))
(local pkgConfig {:dirsep dirsep
                  :pathmark pathmark
                  :pathsep pathsep})

(fn escapepat [str]
  "Escape a string for safe use in a Lua pattern."
  (string.gsub str "[^%w]" "%%%1"))

(fn searchModule [modulename pathstring]
  (let [pathsepesc (escapepat pkgConfig.pathsep)
        pathsplit (string.format "([^%s]*)%s" pathsepesc pathsepesc)
        nodotModule (: modulename :gsub "%." pkgConfig.dirsep)]
    (each [path (string.gmatch (.. (or pathstring utils.fennelModule.path)
                                   pkgConfig.pathsep) pathsplit)]
      (let [filename (: path :gsub (escapepat pkgConfig.pathmark) nodotModule)
            filename2 (: path :gsub (escapepat pkgConfig.pathmark) modulename)
            file (or (io.open filename) (io.open filename2))]
        (when file
          (file:close)
          (lua "return filename"))))))

(fn macroGlobals [env globals]
  (let [allowed (currentGlobalNames env)]
    (each [_ k (pairs (or globals []))]
      (table.insert allowed k))
    allowed))

(fn addMacros [macros* ast scope]
  (compiler.assert (utils.isTable macros*) "expected macros to be table" ast)
  (each [k v (pairs macros*)]
    (compiler.assert (= (type v) "function")
                     "expected each macro to be function" ast)
    (tset scope.macros k v)))

(fn loadMacros [modname ast scope parent]
  (let [filename (compiler.assert (searchModule modname)
                                  (.. modname " module not found.") ast)
        env (makeCompilerEnv ast scope parent)
        globals (macroGlobals env (currentGlobalNames))]
    (utils.fennelModule.dofile filename {:allowedGlobals globals
                                         :env env
                                         :useMetadata utils.root.options.useMetadata
                                         :scope compiler.scopes.compiler})))

(local macroLoaded [])

(fn SPECIALS.require-macros [ast scope parent]
  (compiler.assert (= (# ast) 2) "Expected one module name argument" ast)
  (let [modname (. ast 2)]
    (when (not (. macroLoaded modname))
      (tset macroLoaded modname (loadMacros modname ast scope parent)))
    (addMacros (. macroLoaded modname) ast scope parent)))

(docSpecial
 "require-macros" ["macro-module-name"]
 "Load given module and use its contents as macro definitions in current scope.
Macro module should return a table of macro functions with string keys.
Consider using import-macros instead as it is more flexible.")

(fn SPECIALS.include [ast scope parent opts]
  (compiler.assert (= (# ast) 2) "expected one argument" ast)
  (let [modexpr (. (compiler.compile1 (. ast 2) scope parent {:nval 1}) 1)]
    (when (or (not= modexpr.type "literal") (not= (: (. modexpr 1) "byte") 34))
      (if opts.fallback
          (lua "return opts.fallback(modexpr)")
          (compiler.assert false
                           "module name must resolve to string literal" ast)))
    (let [mod ((loadCode (.. "return " (. modexpr 1))))]
      (when (. utils.root.scope.includes mod) ; check cache
        (lua "return utils.root.scope.includes[mod]"))

      ;; find path to source
      (var path (searchModule mod))
      (var isFennel true)
      (when (not path)
        (set isFennel false)
        (set path (searchModule mod package.path))
        (when (not path)
          (if opts.fallback
              (lua "return opts.fallback(modexpr)")
              (compiler.assert false (.. "module not found " mod) ast))))

      ;; read source
      (let [f (io.open path)
            s (: (: f "read" "*all") :gsub "[\r\n]*$" "")
            _ (: f "close")

            ;; splice in source and memoize it in compiler AND package.preload
            ;; so we can include it again without duplication, even in runtime
            ret (utils.expr (.. "require(\"" mod "\")") "statement")
            target (: "package.preload[%q]" :format mod)
            preloadStr (.. target " = " target " or function(...)")
            (tempChunk subChunk) (values [] [])]
        (compiler.emit tempChunk preloadStr ast)
        (compiler.emit tempChunk subChunk)
        (compiler.emit tempChunk "end" ast)
        ;; Splice tempChunk to begining of root chunk
        (each [i v (ipairs tempChunk)]
          (table.insert utils.root.chunk i v))

        ;; For fennel source, compile subChunk AFTER splicing into start of
        ;; root chunk.
        (if isFennel
            (let [subscope (compiler.makeScope utils.root.scope.parent)
                  forms []]
              (when utils.root.options.requireAsInclude
                (set subscope.specials.require compiler.requireInclude))
              ;; parse Fennel src into table of exprs to know which expr is
              ;; the tail
              (each [_ val (parser.parser (parser.stringStream s) path)]
                (table.insert forms val))
              ;; Compile the forms into subChunk; compiler.compile1 is
              ;; necessary for all nested includes to be emitted in
              ;; the same root chunk in the top-level module
              (for [i 1 (# forms)]
                (let [subopts (or (and (= i (# forms)) {:nval 1
                                                        :tail true}) {:nval 0})]
                  (utils.propagateOptions opts subopts)
                  (compiler.compile1 (. forms i) subscope subChunk subopts))))
            ;; For Lua source, simply emit src into the loaders's body
            (compiler.emit subChunk s ast))

        ;; Put in cache and return
        (tset utils.root.scope.includes mod ret)
        ret))))

(docSpecial
 "include" ["module-name-literal"]
 "Like require but load the target module during compilation and embed it in the
Lua output. The module must be a string literal and resolvable at compile time.")

(fn evalCompiler [ast scope parent]
  (let [scope (compiler.makeScope compiler.scopes.compiler)
        luasrc (compiler.compile ast {:useMetadata utils.root.options.useMetadata
                                   :scope scope})
        loader (loadCode luasrc (wrapEnv (makeCompilerEnv ast scope parent)))]
    (loader)))

(fn SPECIALS.macros [ast scope parent]
  (compiler.assert (= (# ast) 2) "Expected one table argument" ast)
  (addMacros (evalCompiler (. ast 2) scope parent) ast scope parent))

(docSpecial
 "macros" ["{:macro-name-1 (fn [...] ...) ... :macro-name-N macro-body-N}"]
 "Define all functions in the given table as macros local to the current scope.")

(fn SPECIALS.eval-compiler [ast scope parent]
  (let [oldFirst (. ast 1)]
    (tset ast 1 (utils.sym "do"))
    (let [val (evalCompiler ast scope parent)]
      (tset ast 1 oldFirst)
      val)))

(docSpecial
 "eval-compiler" ["..."]
 "Evaluate the body at compile-time. Use the macro system instead if possible.")

{:doc doc*
 : currentGlobalNames
 : loadCode
 : macroLoaded
 : makeCompilerEnv
 : searchModule
 : wrapEnv}

