(local utils (require "fennel.utils"))
(local parser (require "fennel.parser"))
(local unpack (or _G.unpack table.unpack))

(local scopes [])

(fn makeScope [parent]
  "Create a new Scope, optionally under a parent scope.
Scopes are compile time constructs that are responsible for keeping track of
local variables, name mangling, and macros.  They are accessible to user code
via the 'eval-compiler' special form (may change). They use metatables to
implement nesting. "
  (let [parent (or parent scopes.global)]
    {:includes (setmetatable [] {:__index (and parent parent.includes)})
     :macros (setmetatable [] {:__index (and parent parent.macros)})
     :manglings (setmetatable [] {:__index (and parent parent.manglings)})
     :refedglobals (setmetatable [] {:__index (and parent parent.refedglobals)})
     :specials (setmetatable [] {:__index (and parent parent.specials)})
     :symmeta (setmetatable [] {:__index (and parent parent.symmeta)})
     :unmanglings (setmetatable [] {:__index (and parent parent.unmanglings)})

     :autogensyms []
     :vararg (and parent parent.vararg)
     :depth (if parent (+ (or parent.depth 0) 1) 0)
     :hashfn (and parent parent.hashfn)
     :parent parent}))

;; If you add new calls to this function, please update fennelfriend.fnl
;; as well to add suggestions for how to fix the new error.
(fn assertCompile [condition msg ast]
  "Assert a condition and raise a compile error with line numbers.
The ast arg should be unmodified so that its first element is the form called."
  (match (and utils.root.options (. utils.root.options "assert-compile"))
    override (do (when (not condition) ; don't make custom handlers deal with
                   (utils.root.reset)) ; resetting root; it's error-prone
                 (override condition msg ast
                           (and utils.root.options utils.root.options.source))))
  (when (not condition)
    (utils.root.reset)
    (let [m (getmetatable ast)
          filename (or (and m m.filename) ast.filename "unknown")
          line (or (and m m.line) ast.line "?")
          target (tostring (if (utils.isSym (. ast 1))
                               (utils.deref (. ast 1))
                               (or (. ast 1) "()")))]
      ;; if we use regular `assert' we can't provide the `level' argument of 0
      (error (string.format "Compile error in '%s' %s:%s: %s"
                            target filename line msg) 0)))
  condition)

(set scopes.global (makeScope))
(set scopes.global.vararg true)
(set scopes.compiler (makeScope scopes.global))
(set scopes.macro scopes.global)

;; Allow printing a string to Lua, also keep as 1 line.
(local serializeSubst {"\a" "\\a" "\b" "\\b" "\t" "\\t"
                       "\n" "n" "\v" "\\v" "\f" "\\f"})

(fn serializeString [str]
  (-> (: "%q" :format str)
      (: :gsub "." serializeSubst)
      (: :gsub "[€-ÿ]" #(.. "\\" (: $ "byte")))))

(fn globalMangling [str]
  "Mangler for global symbols. Does not protect against collisions,
but makes them unlikely. This is the mangling that is exposed to to the world."
  (if (utils.isValidLuaIdentifier str)
      str
      (.. "__fnl_global__"
          (: str :gsub "[^%w]" #(: "_%02x" :format (: $ "byte"))))))

(fn globalUnmangling [identifier]
  "Reverse a global mangling.
Takes a Lua identifier and returns the Fennel symbol string that created it."
  (match (: identifier "match" "^__fnl_global__(.*)$")
    rest (pick-values 1 (: rest :gsub "_[%da-f][%da-f]"
                           #(string.char (tonumber (: $ "sub" 2) 16))))
    _ identifier))

(var allowedGlobals nil)

(fn globalAllowed [name]
  "If there's a provided list of allowed globals, don't let references thru that
aren't on the list. This list is set at the compiler entry points of compile
and compileStream."
  (var found? (not allowedGlobals))
  (if (not allowedGlobals)
      true
      (do (each [_ g (ipairs allowedGlobals)]
            (when (= g name)
              (set found? true)))
          found?)))

(fn localMangling [str scope ast tempManglings]
  "Creates a symbol from a string by mangling it. ensures that the generated
symbol is unique if the input string is unique in the scope."
  (var append 0)
  (var mangling str)
  (assertCompile (not (utils.isMultiSym str))
                 (.. "unexpected multi symbol " str) ast)
  ;; Mapping mangling to a valid Lua identifier
  (when (or (. utils.luaKeywords mangling) (: mangling "match" "^%d"))
    (set mangling (.. "_" mangling)))
  (set mangling (-> mangling
                    (: :gsub "-" "_")
                    (: :gsub "[^%w_]" #(: "_%02x" :format (: $ "byte")))))
  ;; Prevent name collisions with existing symbols
  (let [raw mangling]
    (while (. scope.unmanglings mangling)
      (set mangling (.. raw append))
      (set append (+ append 1)))
    (tset scope.unmanglings mangling str)
    (let [manglings (or tempManglings scope.manglings)]
      (tset manglings str mangling))
    mangling))

(fn applyManglings [scope newManglings ast]
  "Calling this function will mean that further compilation in scope will use
these new manglings instead of the current manglings."
  (each [raw mangled (pairs newManglings)]
    (assertCompile (not (. scope.refedglobals mangled))
                   (.. "use of global " raw " is aliased by a local") ast)
    (tset scope.manglings raw mangled)))

(fn combineParts [parts scope]
  "Combine parts of a symbol."
  (var ret (or (. scope.manglings (. parts 1)) (globalMangling (. parts 1))))
  (for [i 2 (# parts) 1]
    (if (utils.isValidLuaIdentifier (. parts i))
        (if (and parts.multiSymMethodCall (= i (# parts)))
            (set ret (.. ret ":" (. parts i)))
            (set ret (.. ret "." (. parts i))))
        (set ret (.. ret "[" (serializeString (. parts i)) "]"))))
  ret)

(fn gensym [scope base]
  "Generates a unique symbol in the scope."
  (var (append mangling) (values 0 (.. (or base "") "_0_")))
  (while (. scope.unmanglings mangling)
    (set mangling (.. (or base "") "_" append "_"))
    (set append (+ append 1)))
  (tset scope.unmanglings mangling true)
  mangling)

(fn autogensym [base scope]
  "Generates a unique symbol in the scope based on the base name. Calling
repeatedly with the same base and same scope will return existing symbol
rather than generating new one."
  (match (utils.isMultiSym base)
    parts (do (tset parts 1 (autogensym (. parts 1) scope))
              (table.concat parts (or (and parts.multiSymMethodCall ":") ".")))
    _ (or (. scope.autogensyms base)
          (let [mangling (gensym scope (: base "sub" 1 (- 2)))]
            (tset scope.autogensyms base mangling)
            mangling))))

(fn checkBindingValid [symbol scope ast]
  "Check to see if a symbol will be overshadowed by a special."
  (let [name (utils.deref symbol)]
    (assertCompile (not (or (. scope.specials name) (. scope.macros name)))
                   (: "local %s was overshadowed by a special form or macro"
                      :format name) ast)
    (assertCompile (not (utils.isQuoted symbol))
                   (: "macro tried to bind %s without gensym" :format name)
                   symbol)))

(fn declareLocal [symbol meta scope ast tempManglings]
  "Declare a local symbol"
  (checkBindingValid symbol scope ast)
  (let [name (utils.deref symbol)]
    (assertCompile (not (utils.isMultiSym name))
                   (.. "unexpected multi symbol " name) ast)
    (tset scope.symmeta name meta)
    (localMangling name scope ast tempManglings)))

(fn symbolToExpression [symbol scope isReference]
  "Convert symbol to Lua code. Will only work for local symbols
if they have already been declared via declareLocal"
  (var name (. symbol 1))
  (let [multiSymParts (utils.isMultiSym name)]
    (when scope.hashfn
      (when (= name "$") (set name "$1"))
      (when multiSymParts
        (when (= (. multiSymParts 1) "$")
          (tset multiSymParts 1 "$1")
          (set name (table.concat multiSymParts ".")))))
    (let [parts (or multiSymParts [name])
          etype (or (and (> (# parts) 1) "expression") "sym")
          isLocal (. scope.manglings (. parts 1))]
      (when (and isLocal (. scope.symmeta (. parts 1)))
        (tset (. scope.symmeta (. parts 1)) "used" true))
      ;; if it's a reference and not a symbol which introduces a new binding
      ;; then we need to check for allowed globals
      (assertCompile (or (not isReference) isLocal (globalAllowed (. parts 1)))
                     (.. "unknown global in strict mode: " (. parts 1)) symbol)
      (when (not isLocal)
        (tset utils.root.scope.refedglobals (. parts 1) true))
      (utils.expr (combineParts parts scope) etype))))

(fn emit [chunk out ast]
  "Emit Lua code."
  (if (= (type out) "table")
      (table.insert chunk out)
      (table.insert chunk {:ast ast :leaf out})))

(fn peephole [chunk]
  "Do some peephole optimization."
  (if chunk.leaf chunk
      (and (>= (# chunk) 3)
           (= (. (. chunk (- (# chunk) 2)) "leaf") "do")
           (not (. (. chunk (- (# chunk) 1)) "leaf"))
           (= (. (. chunk (# chunk)) "leaf") "end"))
      (let [kid (peephole (. chunk (- (# chunk) 1)))
            newChunk {:ast chunk.ast}]
        (for [i 1 (- (# chunk) 3) 1]
          (table.insert newChunk (peephole (. chunk i))))
        (for [i 1 (# kid) 1]
          (table.insert newChunk (. kid i)))
        newChunk)
      (utils.map chunk peephole)))

(fn flattenChunkCorrelated [mainChunk]
  "Correlate line numbers in input with line numbers in output."
  (fn flatten [chunk out lastLine file]
    (var last-line lastLine)
    (if chunk.leaf
        (tset out last-line (.. (or (. out last-line) "") " " chunk.leaf))
        (each [_ subchunk (ipairs chunk)]
          (when (or subchunk.leaf (> (# subchunk) 0)) ; ignore empty chunks
            ;; don't increase line unless it's from the same file
            (when (and subchunk.ast (= file subchunk.ast.file))
              (set last-line (math.max last-line (or subchunk.ast.line 0))))
            (set last-line (flatten subchunk out last-line file)))))
    last-line)
  (let [out []
        last (flatten mainChunk out 1 mainChunk.file)]
    (for [i 1 last]
      (when (= (. out i) nil)
        (tset out i "")))
    (table.concat out "\n")))

(fn flattenChunk [sm chunk tab depth]
  "Flatten a tree of indented Lua source code lines.
Tab is what is used to indent a block."
  (if chunk.leaf
      (let [code chunk.leaf
            info chunk.ast]
        (when sm
          (tset sm (+ (# sm) 1) (or (and info info.line) (- 1))))
        code)
      (let [tab (match tab
                  true "  " false "" tab tab nil "")]
        (fn parter [c]
          (when (or c.leaf (> (# c) 0))
            (var sub (flattenChunk sm c tab (+ depth 1)))
            (when (> depth 0)
              (set sub (.. tab (: sub :gsub "\n" (.. "\n" tab)))))
            sub))
        (table.concat (utils.map chunk parter) "\n"))))

;; Some global state for all fennel sourcemaps. For the time being, this seems
;; the easiest way to store the source maps.  Sourcemaps are stored with source
;; being mapped as the key, prepended with '@' if it is a filename (like
;; debug.getinfo returns for source).  The value is an array of mappings for
;; each line.
(local fennelSourcemap [])

(fn makeShortSrc [source]
  (let [source (: source :gsub "\n" " ")]
    (if (<= (# source) 49)
        (.. "[fennel \"" source "\"]")
        (.. "[fennel \"" (: source "sub" 1 46) "...\"]"))))

(fn flatten [chunk options]
  "Return Lua source and source map table."
  (let [chunk (peephole chunk)]
    (if options.correlate
        (values (flattenChunkCorrelated chunk) [])
        (let [sm []
              ret (flattenChunk sm chunk options.indent 0)]
          (when sm
            (var (key short_src) nil)
            (if options.filename
                (do
                  (set short_src options.filename)
                  (set key (.. "@" short_src)))
                (do
                  (set key ret)
                  (set short_src (makeShortSrc (or options.source ret)))))
            (set sm.short_src short_src)
            (set sm.key key)
            (tset fennelSourcemap key sm))
          (values ret sm)))))

(fn makeMetadata []
  "Make module-wide state table for metadata."
  (setmetatable
   [] {:__index {:get (fn [self tgt key]
                        (when (. self tgt)
                          (. (. self tgt) key)))
                 :set (fn [self tgt key value]
                        (tset self tgt (or (. self tgt) []))
                        (tset (. self tgt) key value)
                        tgt)
                 :setall (fn [self tgt ...]
                           (let [kvLen (select "#" ...)
                                 kvs [...]]
                             (when (not= (% kvLen 2) 0)
                               (error "metadata:setall() expected even number of k/v pairs"))
                             (tset self tgt (or (. self tgt) []))
                             (for [i 1 kvLen 2]
                               (tset (. self tgt) (. kvs i) (. kvs (+ i 1))))
                             tgt))}
       :__mode "k"}))

(fn exprs1 [exprs]
  "Convert expressions to Lua string."
  (table.concat (utils.map exprs 1) ", "))

(fn keepSideEffects [exprs chunk start ast]
  "Compile side effects for a chunk."
  (let [start (or start 1)]
    (for [j start (# exprs) 1]
      (let [se (. exprs j)]
        ;; Avoid the rogue 'nil' expression (nil is usually a literal,
        ;; but becomes an expression if a special form returns 'nil')
        (if (and (= se.type "expression") (not= (. se 1) "nil"))
            (emit chunk (: "do local _ = %s end" :format (tostring se)) ast)
            (= se.type "statement")
            (let [code (tostring se)]
              (emit chunk (or (and (= (: code "byte") 40)
                                   (.. "do end " code)) code) ast)))))))

(fn handleCompileOpts [exprs parent opts ast]
  "Does some common handling of returns and register targets for special
forms. Also ensures a list expression has an acceptable number of expressions
if opts contains the nval option."
  (when opts.nval
    (let [n opts.nval
          len (# exprs)]
      (when (not= n len)
        (if (> len n)
            (do ; drop extra
              (keepSideEffects exprs parent (+ n 1) ast)
              (for [i (+ n 1) len 1]
                (tset exprs i nil)))
            (for [i (+ (# exprs) 1) n 1] ; pad with nils
              (tset exprs i (utils.expr "nil" "literal")))))))
  (when opts.tail
    (emit parent (: "return %s" :format (exprs1 exprs)) ast))
  (when opts.target
    (var result (exprs1 exprs))
    (when (= result "")
      (set result "nil"))
    (emit parent (: "%s = %s" :format opts.target result) ast))
  (if (or opts.tail opts.target)
      ;; Prevent statements and expression from being used twice if they
      ;; have side-effects. Since if the target or tail options are set,
      ;; the expressions are already emitted, we should not return them. This
      ;; is fine, as when these options are set, the caller doesn't need the
      ;; result anyways.
      []
      exprs))
(fn macroexpand* [ast scope once]
  "Expand macros in the ast. Only do one level if once is true."
  (if (not (utils.isList ast)) ; bail early if not a list
      ast
      (let [multiSymParts (utils.isMultiSym (. ast 1))]
        (var macro* (and (utils.isSym (. ast 1))
                         (. scope.macros (utils.deref (. ast 1)))))
        (when (and (not macro*) multiSymParts)
          (var inMacroModule nil)
          (set macro* scope.macros)
          (for [i 1 (# multiSymParts) 1]
            (set macro* (and (utils.isTable macro*)
                             (. macro* (. multiSymParts i))))
            (when macro*
              (set inMacroModule true)))
          (assertCompile (or (not inMacroModule) (= (type macro*) "function"))
                         "macro not found in imported macro module" ast))
        (if (not macro*)
            ast
            (let [oldScope scopes.macro
                  _ (set scopes.macro scope)
                  (ok transformed) (pcall macro* (unpack ast 2))]
              (set scopes.macro oldScope)
              (assertCompile ok transformed ast)
              (if (or once (not transformed))
                  transformed
                  (macroexpand* transformed scope)))))))

(fn compile1 [ast scope parent opts]
  "Compile an AST expression in the scope into parent, a tree of lines that is
eventually compiled into Lua code. Also returns some information about the
evaluation of the compiled expression, which can be used by the calling
function. Macros are resolved here, as well as special forms in that order.

* the `ast` param is the root AST to compile
* the `scope` param is the scope in which we are compiling
* the `parent` param is the table of lines that we are compiling into.
add lines to parent by appending strings. Add indented blocks by appending
tables of more lines.
* the `opts` param contains info about where the form is being compiled

Fields of `opts` include:
  target: mangled name of symbol(s) being compiled to.
     Could be one variable, 'a', or a list, like 'a, b, _0_'.
  tail: boolean indicating tail position if set. If set, form will generate
     a return instruction.
  nval: The number of values to compile to if it is known to be a fixed value.

In Lua, an expression can evaluate to 0 or more values via multiple returns. In
many cases, Lua will drop extra values and convert a 0 value expression to
nil. In other cases, Lua will use all of the values in an expression, such as
in the last argument of a function call. Nval is an option passed to compile1
to say that the resulting expression should have at least n values. It lets us
generate better code, because if we know we are only going to use 1 or 2 values
from an expression, we can create 1 or 2 locals to store intermediate results
rather than turn the expression into a closure that is called immediately,
which we have to do if we don't know."
  (let [opts (or opts [])
        ;; expand any top-level macros before parsing and emitting Lua
        ast (macroexpand* ast scope)]
    (var exprs [])
    (if (utils.isList ast) ; function call or special form
        (let [len (# ast)
              first (. ast 1)
              multiSymParts (utils.isMultiSym first)
              special (and (utils.isSym first)
                           (. scope.specials (utils.deref first)))]
          (assertCompile (> (# ast) 0)
                         "expected a function, macro, or special to call" ast)
          (if special
              (do
                (set exprs (or (special ast scope parent opts)
                               (utils.expr "nil" "literal")))
                ;; Be very accepting of strings or expressions as well as lists
                ;; or expressions
                (when (= (type exprs) "string")
                  (set exprs (utils.expr exprs "expression")))
                (when (utils.isExpr exprs)
                  (set exprs [exprs]))
                ;; Unless the special form explicitly handles the target, tail,
                ;; and nval properties, (indicated via the 'returned' flag),
                ;; handle these options.
                (if (not exprs.returned)
                    (set exprs (handleCompileOpts exprs parent opts ast))
                    (or opts.tail opts.target)
                    (set exprs [])))
              (and multiSymParts multiSymParts.multiSymMethodCall)
              (let [tableWithMethod (table.concat
                                     [(unpack multiSymParts 1 (- (# multiSymParts) 1))]
                                     ".")
                    methodToCall (. multiSymParts (# multiSymParts))
                    newAST (utils.list (utils.sym ":" scope)
                                       (utils.sym tableWithMethod scope)
                                       methodToCall)]
                (for [i 2 len 1]
                  (tset newAST (+ (# newAST) 1) (. ast i)))
                (set exprs (compile1 newAST scope parent opts)))
              (let [fargs []] ; regular function call
                (var fcallee (. (compile1 (. ast 1) scope parent {:nval 1}) 1))
                (assertCompile (not= fcallee.type "literal")
                               (.. "cannot call literal value "
                                   (tostring (. ast 1))) ast)
                (set fcallee (tostring fcallee))
                (for [i 2 len 1]
                  (let [subexprs (compile1 (. ast i) scope parent
                                           {:nval (or (and (not= i len) 1) nil)})]
                    (tset fargs (+ (# fargs) 1) (or (. subexprs 1)
                                                    (utils.expr "nil" "literal")))
                    (if (= i len)
                        ;; Add sub expressions to function args
                        (for [j 2 (# subexprs) 1]
                          (tset fargs (+ (# fargs) 1) (. subexprs j)))
                        ;; Emit sub expression only for side effects
                        (keepSideEffects subexprs parent 2 (. ast i)))))
                (let [call (: "%s(%s)" :format (tostring fcallee) (exprs1 fargs))]
                  (set exprs (handleCompileOpts [(utils.expr call "statement")]
                                                parent opts ast))))))
        (utils.isVarg ast)
        (do
          (assertCompile scope.vararg "unexpected vararg" ast)
          (set exprs (handleCompileOpts [(utils.expr "..." "varg")]
                                        parent opts ast)))
        (utils.isSym ast)
        (let [multiSymParts (utils.isMultiSym ast)]
          (var e nil)
          (assertCompile (not (and multiSymParts multiSymParts.multiSymMethodCall))
                         "multisym method calls may only be in call position" ast)
          ;; Handle nil as special symbol - it resolves to the nil literal
          ;; rather than being unmangled. Alternatively, we could remove it
          ;; from the lua keywords table.
          (if (= (. ast 1) "nil")
              (set e (utils.expr "nil" "literal"))
              (set e (symbolToExpression ast scope true)))
          (set exprs (handleCompileOpts [e] parent opts ast)))
        (or (= (type ast) "nil") (= (type ast) "boolean"))
        (set exprs (handleCompileOpts [(utils.expr (tostring ast) "literal")]
                                      parent opts))
        (= (type ast) "number")
        (do
          (local n (: "%.17g" :format ast))
          (set exprs (handleCompileOpts [(utils.expr n "literal")] parent opts)))
        (= (type ast) "string")
        (do
          (local s (serializeString ast))
          (set exprs (handleCompileOpts [(utils.expr s "literal")] parent opts)))
        (= (type ast) "table")
        (let [buffer []]
          (for [i 1 (# ast) 1] ; write numeric keyed values
            (let [nval (and (not= i (# ast)) 1)]
              (tset buffer (+ (# buffer) 1)
                    (exprs1 (compile1 (. ast i) scope parent {:nval nval})))))
          (fn writeOtherValues [k]
            (when (or (not= (type k) "number")
                      (not= (math.floor k) k)
                      (< k 1) (> k (# ast)))
              (if (and (= (type k) "string") (utils.isValidLuaIdentifier k))
                  [k k]
                  (let [[compiled] (compile1 k scope parent {:nval 1})
                        kstr (.. "[" (tostring compiled) "]")]
                    [kstr k]))))
          (let [keys (doto (utils.kvmap ast writeOtherValues)
                       (table.sort (fn [a b] (< (. a 1) (. b 1)))))]
            (utils.map keys (fn [k]
                              (let [v (tostring (. (compile1 (. ast (. k 2))
                                                             scope parent
                                                             {:nval 1}) 1))]
                                (: "%s = %s" :format (. k 1) v)))
                       buffer))
          (set exprs (handleCompileOpts
                      [(utils.expr (.. "{" (table.concat buffer ", ") "}")
                                   "expression")] parent opts ast)))
        (assertCompile false
                       (.. "could not compile value of type " (type ast)) ast))
    (set exprs.returned true)
    exprs))

(fn destructure [to from ast scope parent opts]
  "Implements destructuring for forms like let, bindings, etc.
  Takes a number of opts to control behavior.
  * var: Whether or not to mark symbols as mutable
  * declaration: begin each assignment with 'local' in output
  * nomulti: disallow multisyms in the destructuring. for (local) and (global)
  * noundef: Don't set undefined bindings. (set)
  * forceglobal: Don't allow local bindings"
  (let [opts (or opts {})
        {: isvar : declaration : nomulti : noundef : forceglobal : forceset} opts
        setter (if declaration "local %s = %s" "%s = %s")
        newManglings []]

    (fn getname [symbol up1]
      "Get Lua source for symbol, and check for errors"
      (let [raw (. symbol 1)]
        (assertCompile (not (and nomulti (utils.isMultiSym raw)))
                       (.. "unexpected multi symbol " raw) up1)
        (if declaration
            (declareLocal symbol {:var isvar} scope symbol newManglings)
            (let [parts (or (utils.isMultiSym raw) [raw])
                  meta (. scope.symmeta (. parts 1))]
              (when (and (= (# parts) 1) (not forceset))
                (assertCompile (not (and forceglobal meta))
                               (: "global %s conflicts with local"
                                  :format (tostring symbol)) symbol)
                (assertCompile (not (and meta (not meta.var)))
                               (.. "expected var " raw) symbol)
                (assertCompile (or meta (not noundef))
                               (.. "expected local " (. parts 1)) symbol))
              (when forceglobal
                (assertCompile (not (. scope.symmeta (. scope.unmanglings raw)))
                               (.. "global " raw " conflicts with local") symbol)
                (tset scope.manglings raw (globalMangling raw))
                (tset scope.unmanglings (globalMangling raw) raw)
                (when allowedGlobals
                  (table.insert allowedGlobals raw)))
              (. (symbolToExpression symbol scope) 1)))))

    (fn compileTopTarget [lvalues]
      "Compile the outer most form. We can generate better Lua in this case."
      ;; Calculate initial rvalue
      (let [inits (utils.map lvalues #(if (. scope.manglings $) $ "nil"))
            init (table.concat inits ", ")
            lvalue (table.concat lvalues ", ")]
        (var (plen plast) (values (# parent) (. parent (# parent))))
        (local ret (compile1 from scope parent {:target lvalue}))
        (when declaration
          ;; A single leaf emitted at the end of the parent chunk means a
          ;; simple assignment a = x was emitted, and we can just splice
          ;; "local " onto the front of it. However, we can't just check
          ;; based on plen, because some forms (such as include) insert new
          ;; chunks at the top of the parent chunk rather than just at the
          ;; end; this loop checks for this occurance and updates plen to be
          ;; the index of the last thing in the parent before compiling the
          ;; new value.
          (for [pi plen (# parent)]
            (when (= (. parent pi) plast)
              (set plen pi)))
          (if (and (= (# parent) (+ plen 1)) (. (. parent (# parent)) "leaf"))
              (tset (. parent (# parent)) :leaf
                    (.. "local " (. (. parent (# parent)) "leaf")))
              (table.insert parent (+ plen 1)
                            {:ast ast :leaf (.. "local " lvalue " = " init)})))
        ret))

    (fn destructure1 [left rightexprs up1 top]
      "Recursive auxiliary function"
      (if (and (utils.isSym left) (not= (. left 1) "nil"))
          (let [lname (getname left up1)]
            (checkBindingValid left scope left)
            (if top
                (compileTopTarget [lname])
                (emit parent (: setter :format lname (exprs1 rightexprs)) left)))
          (utils.isTable left) ; table destructuring
          (let [s (gensym scope)]
            (var right (if top
                           (exprs1 (compile1 from scope parent))
                           (exprs1 rightexprs)))
            (when (= right "")
              (set right "nil"))
            (emit parent (: "local %s = %s" :format s right) left)
            (each [k v (utils.stablepairs left)]
              (if (and (utils.isSym (. left k)) (= (. (. left k) 1) "&"))
                  (do
                    (assertCompile (and (= (type k) "number")
                                        (not (. left (+ k 2))))
                                   "expected rest argument before last parameter"
                                   left)
                    (let [formatted (: "{(table.unpack or unpack)(%s, %s)}" :format s k)
                          subexpr (utils.expr formatted "expression")]
                      (destructure1 (. left (+ k 1)) [subexpr] left)
                      (lua "return")))
                  (do ; TODO: yikes
                    (when (and (utils.isSym k)
                               (= (tostring k) ":")
                               (utils.isSym v))
                      (set-forcibly! k (tostring v)))
                    (when (not= (type k) "number")
                      (set-forcibly! k (serializeString k)))
                    (let [subexpr (utils.expr (: "%s[%s]" :format s k)
                                              "expression")]
                      (destructure1 v [subexpr] left))))))
          (utils.isList left) ;; values destructuring
          (let [(leftNames tables) (values [] [])]
            (each [i name (ipairs left)]
              (var symname nil)
              (if (utils.isSym name) ; binding directly to a name
                  (set symname (getname name up1))
                  (do ; further destructuring of tables inside values
                    (set symname (gensym scope))
                    (tset tables i [name (utils.expr symname "sym")])))
              (table.insert leftNames symname))
            (if top
                (compileTopTarget leftNames)
                (let [lvalue (table.concat leftNames ", ")
                      setting (: setter :format lvalue (exprs1 rightexprs))]
                  (emit parent setting left)))
            ;; recurse if left-side tables found
            (each [_ pair (utils.stablepairs tables)]
              (destructure1 (. pair 1) [(. pair 2)] left)))
          (assertCompile false (: "unable to bind %s %s" :format
                                  (type left) (tostring left))
                         (or (and (= (type (. up1 2)) "table") (. up1 2)) up1)))
      (when top
        {:returned true}))

    (let [ret (destructure1 to nil ast true)]
      (applyManglings scope newManglings ast)
      ret)))

(fn requireInclude [ast scope parent opts]
  (fn opts.fallback [e]
    (utils.expr (: "require(%s)" :format (tostring e)) "statement"))
  (scopes.global.specials.include ast scope parent opts))

(fn compileStream [strm options]
  (let [opts (utils.copy options)
        oldGlobals allowedGlobals
        scope (or opts.scope (makeScope scopes.global))
        vals []
        chunk []]
    (utils.root:setReset)
    (set allowedGlobals opts.allowedGlobals)
    (when (= opts.indent nil)
      (set opts.indent "  "))
    (when opts.requireAsInclude
      (set scope.specials.require requireInclude))
    (each [ok val (parser.parser strm opts.filename opts)]
      (tset vals (+ (# vals) 1) val))
    (set (utils.root.chunk utils.root.scope utils.root.options)
         (values chunk scope opts))
    (for [i 1 (# vals) 1]
      (let [exprs (compile1 (. vals i) scope chunk
                            {:nval (or (and (< i (# vals)) 0) nil)
                             :tail (= i (# vals))})]
        (keepSideEffects exprs chunk nil (. vals i))))
    (set allowedGlobals oldGlobals)
    (utils.root.reset)
    (flatten chunk opts)))

(fn compileString [str opts]
  (let [opts (or opts [])
        oldSource opts.source]
    (set opts.source str) ; used by fennelfriend
    (let [ast (compileStream (parser.stringStream str) opts)]
      (set opts.source oldSource)
      ast)))

(fn compile [ast opts]
  (let [opts (utils.copy opts)
        oldGlobals allowedGlobals
        chunk []
        scope (or opts.scope (makeScope scopes.global))]
    (utils.root:setReset)
    (set allowedGlobals opts.allowedGlobals)
    (when (= opts.indent nil)
      (set opts.indent "  "))
    (when opts.requireAsInclude
      (set scope.specials.require requireInclude))
    (set (utils.root.chunk utils.root.scope utils.root.options)
         (values chunk scope opts))
    (let [exprs (compile1 ast scope chunk {:tail true})]
      (keepSideEffects exprs chunk nil ast)
      (set allowedGlobals oldGlobals)
      (utils.root.reset)
      (flatten chunk opts))))

(fn traceback-frame [info]
  (if (and (= info.what "C") info.name)
      (: "  [C]: in function '%s'" :format info.name)
      (= info.what "C")
      "  [C]: in ?"
      (let [remap (. fennelSourcemap info.source)]
        (when (and remap (. remap info.currentline))
          ;; And some global info
          (set info.short_src remap.short_src)
          ;; Overwrite info with values from the mapping
          ;; (mapping is now just integer, but may
          ;; eventually be a table)
          (set info.currentline (. remap info.currentline)))
        (if (= info.what "Lua")
            (: "  %s:%d: in function %s"
               :format info.short_src info.currentline
               (if info.name (.. "'" info.name "'") "?"))
            (= info.short_src "(tail call)")
            "  (tail call)"
            (: "  %s:%d: in main chunk"
               :format info.short_src info.currentline)))))

(fn traceback [msg start]
  "A custom traceback function for Fennel that looks similar to debug.traceback.
Use with xpcall to produce fennel specific stacktraces. Skips frames from the
compiler by default; these can be re-enabled with export FENNEL_DEBUG=trace."
  (let [msg (or msg "")]
    (if (and (or (: msg :find "^Compile error") (: msg :find "^Parse error"))
             (not (utils.debugOn "trace")))
        msg ; skip the trace because it's compiler internals.
        (let [lines []]
          (if (or (msg:find "^Compile error") (msg:find "^Parse error"))
              (table.insert lines msg)
              (let [newmsg (msg:gsub "^[^:]*:%d+:%s+" "runtime error: ")]
                (table.insert lines newmsg)))
          (table.insert lines "stack traceback:")
          (var (done? level) (values false (or start 2)))
          ;; This would be cleaner factored out into its own recursive
          ;; function, but that would interfere with the traceback itself!
          (while (not done?)
            (match (debug.getinfo level "Sln")
              nil (set done? true)
              info (table.insert lines (traceback-frame info)))
            (set level (+ level 1)))
          (table.concat lines "\n")))))

(fn entryTransform [fk fv]
  "Make a transformer for key / value table pairs, preserving all numeric keys"
  (fn [k v] (if (= (type k) "number")
                (values k (fv v))
                (values (fk k) (fv v)))))

(fn no [] "Consume everything and return nothing." nil)

(fn mixedConcat [t joiner]
  (let [seen []]
    (var (ret s) (values "" ""))
    (each [k v (ipairs t)]
      (table.insert seen k)
      (set ret (.. ret s v))
      (set s joiner))
    (each [k v (utils.stablepairs t)]
      (when (not (. seen k))
        (set ret (.. ret s "[" k "]" "=" v))
        (set s joiner)))
    ret))

(fn doQuote [form scope parent runtime]
  "Expand a quoted form into a data literal, evaluating unquote"
  (fn q [x] (doQuote x scope parent runtime))
  (if (utils.isVarg form) ; vararg
      (do
        (assertCompile (not runtime)
                       "quoted ... may only be used at compile time" form)
        "_VARARG")
      (utils.isSym form) ; symbol
      (let [filename (if form.filename (: "%q" :format form.filename) :nil)
            symstr (utils.deref form)]
        (assertCompile (not runtime)
                       "symbols may only be used at compile time" form)
        ;; We should be able to use "%q" for this but Lua 5.1 throws an error
        ;; when you try to format nil, because it's extremely bad.
        (if (or (: symstr "find" "#$") (: symstr "find" "#[:.]")) ; autogensym
            (: "sym('%s', nil, {filename=%s, line=%s})"
               :format (autogensym symstr scope) filename (or form.line :nil))
            ;; prevent non-gensymed symbols from being bound as an identifier
            (: "sym('%s', nil, {quoted=true, filename=%s, line=%s})"
               :format symstr filename (or form.line :nil))))
      (and (utils.isList form) ; unquote
           (utils.isSym (. form 1))
           (= (utils.deref (. form 1)) :unquote))
      (let [payload (. form 2)
            res (unpack (compile1 payload scope parent))]
        (. res 1))
      (utils.isList form) ; list
      (let [mapped (utils.kvmap form (entryTransform no q))
            filename (if form.filename (: "%q" :format form.filename) :nil)]
        (assertCompile (not runtime)
                       "lists may only be used at compile time" form)
        ;; Constructing a list and then adding file/line data to it triggers a
        ;; bug where it changes the value of # for lists that contain nils in
        ;; them; constructing the list all in one go with the source data and
        ;; contents is how we construct lists in the parser and works around
        ;; this problem; allowing # to work in a way that lets us see the nils.
        (: (.. "setmetatable({filename=%s, line=%s, bytestart=%s, %s}"
               ", getmetatable(list()))")
           :format filename (or form.line :nil) (or form.bytestart :nil)
           (mixedConcat mapped ", ")))
      (= (type form) "table") ; table
      (let [mapped (utils.kvmap form (entryTransform q q))
            source (getmetatable form)
            filename (if source.filename (: "%q" :format source.filename) :nil)]
        (: "setmetatable({%s}, {filename=%s, line=%s})"
           :format (mixedConcat mapped ", ") filename
           (if source source.line :nil)))
      (= (type form) "string")
      (serializeString form)
      (tostring form)))

{;; compiling functions
 : compile : compile1 : compileStream : compileString : emit : destructure
 : requireInclude

 ;; AST functions
 : autogensym : gensym : doQuote : globalMangling : globalUnmangling
 : applyManglings :macroexpand macroexpand*

 ;; scope functions
 : declareLocal : makeScope : keepSideEffects : symbolToExpression

 ;; general
 :assert assertCompile : scopes : traceback :metadata (makeMetadata)
 }
