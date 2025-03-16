;; This is the core compiler module responsible for taking a parsed AST
;; and turning it into Lua code. Main entry points are `compile` (which
;; takes an AST), `compile-stream` and `compile-string`.

(local {: unpack &as utils} (require :fennel.utils))
(local parser (require :fennel.parser))
(local friend (require :fennel.friend))
(local view (require :fennel.view))

(local scopes {:global nil :compiler nil :macro nil})

(fn make-scope [?parent]
  "Create a new Scope, optionally under a parent scope.
Scopes are compile time constructs that are responsible for keeping track of
local variables, name mangling, and macros.  They are accessible to user code
via the 'eval-compiler' special form (may change). They use metatables to
implement nesting. "
  (let [parent (or ?parent scopes.global)]
    {:includes (setmetatable [] {:__index (and parent parent.includes)})
     :macros (setmetatable [] {:__index (and parent parent.macros)})
     :manglings (setmetatable [] {:__index (and parent parent.manglings)})
     :specials (setmetatable [] {:__index (and parent parent.specials)})
     :symmeta (setmetatable [] {:__index (and parent parent.symmeta)})
     :gensym-base (setmetatable [] {:__index (and parent parent.gensym-base)})
     :unmanglings (setmetatable [] {:__index (and parent parent.unmanglings)})
     :gensyms (setmetatable [] {:__index (and parent parent.gensyms)})
     :autogensyms (setmetatable [] {:__index (and parent parent.autogensyms)})
     :vararg (and parent parent.vararg)
     :depth (if parent (+ (or parent.depth 0) 1) 0)
     :hashfn (and parent parent.hashfn)
     :refedglobals {}
     : parent}))

(fn assert-msg [ast msg]
  (let [ast-tbl (if (= :table (type ast)) ast {})
        m (getmetatable ast)
        filename (or (and m m.filename) ast-tbl.filename :unknown)
        line (or (and m m.line) ast-tbl.line "?")
        col (or (and m m.col) ast-tbl.col "?")
        target (tostring (or (utils.sym? (. ast-tbl 1)) (. ast-tbl 1) "()"))]
    (string.format "%s:%s:%s: Compile error in '%s': %s"
                   filename line col target msg)))

;; If you add new calls to this function, please update fennel.friend
;; as well to add suggestions for how to fix the new error!
(fn assert-compile [condition msg ast ?fallback-ast]
  "Assert a condition and raise a compile error with line numbers.
The ast arg should be unmodified so that its first element is the form called."
  (when (not condition)
    (let [{: source : unfriendly : error-pinpoint} (or utils.root.options {})
          ;; allow a fallback AST when the form itself has no source data
          ast (if (next (utils.ast-source ast)) ast (or ?fallback-ast {}))]
      ;; allow plugins to override assert-compile
      (when (= nil (utils.hook :assert-compile condition msg ast
                               utils.root.reset))
        (utils.root.reset)
        (if unfriendly
            ;; if we use regular `assert' we can't set level to 0
            (error (assert-msg ast msg) 0)
            (friend.assert-compile condition msg ast source {: error-pinpoint})))))
  condition)

(set scopes.global (make-scope))
(set scopes.global.vararg true)
(set scopes.compiler (make-scope scopes.global))
(set scopes.macro scopes.global)

(local serialize-subst-digits {"\\7" "\\a" "\\8" "\\b" "\\9" "\\t"
                               "\\10" "\\n" "\\11" "\\v" "\\12" "\\f"
                               "\\13" "\\r"})

(fn serialize-string [str]
  (-> (string.format "%q" str)
      (string.gsub "\\\n" "\\n") ; keep it as one line
      (string.gsub "\\..?" serialize-subst-digits)
      (string.gsub "[\128-\255]" #(.. "\\" ($:byte)))))

(fn global-mangling [str]
  "Turn a global symbol into a Lua-friendly expression."
  (if (utils.valid-lua-identifier? str) str
      ;; TODO: default to true in 2.0
      (= (?. utils.root.options :global-mangle) false) (: "_G[%q]" :format str)
      (.. :__fnl_global__ (str:gsub "[^%w]" #(string.format "_%02x" ($:byte))))))

(fn global-unmangling [identifier]
  "Reverse a global mangling.
Takes a Lua identifier and returns the Fennel symbol string that created it."
  (case (string.match identifier "^__fnl_global__(.*)$")
    rest (pick-values 1 (rest:gsub "_[%da-f][%da-f]"
                                   #(string.char (tonumber ($:sub 2) 16))))
    _ identifier))

(fn global-allowed? [name]
  "If there's a provided list of allowed globals, don't let references thru that
aren't on the list. This list is set at the compiler entry points of compile
and compile-stream."
  (let [allowed (?. utils.root.options :allowedGlobals)]
    (or (not allowed) (utils.member? name allowed))))

(fn unique-mangling [original mangling scope append]
  (if (. scope.unmanglings mangling)
      (unique-mangling original (.. original append) scope (+ append 1))
      mangling))

(fn apply-deferred-scope-changes [scope deferred-scope-changes ast]
  "Calling this function will mean that further compilation in scope will use
these new manglings instead of the current manglings."
  (each [raw mangled (pairs deferred-scope-changes.manglings)]
    (assert-compile (not (. scope.refedglobals mangled))
                    (.. "use of global " raw " is aliased by a local") ast)
    (tset scope.manglings raw mangled))
  (each [raw symmeta (pairs deferred-scope-changes.symmeta)]
    (tset scope.symmeta raw symmeta)))

(fn combine-parts [parts scope]
  "Combine parts of a symbol."
  (var ret (or (. scope.manglings (. parts 1)) (global-mangling (. parts 1))))
  (for [i 2 (length parts)]
    (if (utils.valid-lua-identifier? (. parts i))
        (if (and parts.multi-sym-method-call (= i (length parts)))
            (set ret (.. ret ":" (. parts i)))
            (set ret (.. ret "." (. parts i))))
        (set ret (.. ret "[" (serialize-string (. parts i)) "]"))))
  ret)

(fn root-scope [scope]
  (or (and utils.root utils.root.scope)
      (and scope.parent (root-scope scope.parent)) scope))

(fn next-append [root-scope*]
  (set root-scope*.gensym-append (+ (or root-scope*.gensym-append 0) 1))
  (.. "_" root-scope*.gensym-append "_"))

(fn gensym [scope ?base ?suffix]
  "Generates a unique symbol in the scope."
  (let [root-scope* (root-scope scope)]
    (var mangling (.. (or ?base "") (next-append root-scope*) (or ?suffix "")))
    (while (. scope.unmanglings mangling)
      (set mangling (.. (or ?base "") (next-append root-scope*) (or ?suffix ""))))
    (when (and ?base (< 0 (length ?base)))
      (tset scope.gensym-base mangling ?base))
    (tset scope.gensyms mangling true)
    mangling))

(fn combine-auto-gensym [parts first]
  (tset parts 1 first)
  (let [last (table.remove parts)
        last2 (table.remove parts)
        last-joiner (or (and parts.multi-sym-method-call ":") ".")]
    (table.insert parts (.. last2 last-joiner last))
    (table.concat parts ".")))

(fn autogensym [base scope]
  "Generates a unique symbol in the scope based on the base name. Calling
repeatedly with the same base and same scope will return existing symbol
rather than generating new one."
  (case (utils.multi-sym? base)
    parts (combine-auto-gensym parts (autogensym (. parts 1) scope))
    _ (or (. scope.autogensyms base)
          (let [mangling (gensym scope (base:sub 1 -2) :auto)]
            (tset scope.autogensyms base mangling)
            mangling))))

(fn check-binding-valid [symbol scope ast ?opts]
  "Check to see if a symbol will be overshadowed by a special.
?opts table accepts :macro? property that skips shadowing checks"
  (let [name (tostring symbol)
        macro? (?. ?opts :macro?)]
    ;; we can't block in the parser because & is still ok in symbols like &as
    (assert-compile (not= "&" (name:match "[&.:]")) "invalid character: &" symbol)
    (assert-compile (not (name:find "^%.")) "invalid character: ." symbol)
    (assert-compile (not (or (. scope.specials name)
                             (and (not macro?) (. scope.macros name))))
                    (: "local %s was overshadowed by a special form or macro"
                       :format name) ast)
    (assert-compile (not (utils.quoted? symbol))
                    (string.format "macro tried to bind %s without gensym" name)
                    symbol)))

(fn declare-local [symbol scope ast ?var? ?deferred-scope-changes]
  "Declare a local symbol.
If ?deferred-scope-changes is provided, the local won't be in scope until
the deferred changes are applied with (apply-deferred-scope-changes)."
  (check-binding-valid symbol scope ast)
  (assert-compile (not (utils.multi-sym? symbol))
                  (.. "unexpected multi symbol " (tostring symbol)) ast)
  (let [str (tostring symbol)
        ;; Mapping mangling to a valid Lua identifier
        raw (if (or (utils.lua-keyword? str) (str:match "^%d"))
                (.. "_" str)
                str)
        mangling (-> raw
                     (string.gsub "-" "_")
                     (string.gsub "[^%w_]" #(string.format "_%02x" ($:byte))))
        unique (unique-mangling mangling mangling scope 0)]
    (tset scope.unmanglings unique (or (. scope.gensym-base str) str))
    (let [target (or ?deferred-scope-changes scope)]
      (tset target.manglings str unique)
      (tset target.symmeta str {:var ?var? : symbol}))
    unique))

(fn hashfn-arg-name [name multi-sym-parts scope]
  (if (not scope.hashfn) nil
      (= name "$") :$1
      multi-sym-parts (do
                        (when (and multi-sym-parts
                                   (= (. multi-sym-parts 1) "$"))
                          (tset multi-sym-parts 1 :$1))
                        (table.concat multi-sym-parts "."))))

(fn symbol-to-expression [symbol scope ?reference?]
  "Convert symbol to Lua code. Will only work for local symbols
if they have already been declared via declare-local"
  (utils.hook :symbol-to-expression symbol scope ?reference?)
  (let [name (. symbol 1)
        multi-sym-parts (utils.multi-sym? name)
        name (or (hashfn-arg-name name multi-sym-parts scope) name)]
    (let [parts (or multi-sym-parts [name])
          etype (or (and (< 1 (length parts)) :expression) :sym)
          local? (. scope.manglings (. parts 1))]
      (when (and local? (. scope.symmeta (. parts 1)))
        (tset scope.symmeta (. parts 1) :used true)
        (set symbol.referent (. scope.symmeta (. parts 1) :symbol)))
      (assert-compile (not (. scope.macros (. parts 1)))
                      (.. "tried to reference a macro without calling it") symbol)
      (assert-compile (or (not (. scope.specials (. parts 1)))
                          (= :require (. parts 1)))
                      (.. "tried to reference a special form without calling it") symbol)
      ;; if it's a reference and not a symbol which introduces a new binding
      ;; then we need to check for allowed globals
      (assert-compile (or (not ?reference?) local? (= :_ENV (. parts 1))
                          (global-allowed? (. parts 1)))
                      (.. "unknown identifier: " (tostring (. parts 1))) symbol)
      (when (and (?. utils.root.options :allowedGlobals)
                 (not local?) scope.parent)
        (tset scope.parent.refedglobals (. parts 1) true))
      (utils.expr (combine-parts parts scope) etype))))

(fn emit [chunk out ?ast]
  "Emit Lua code."
  (if (= (type out) :table)
      (table.insert chunk out)
      (table.insert chunk {:ast ?ast :leaf out})))

(fn peephole [chunk]
  "Do some peephole optimization."
  (if chunk.leaf chunk
      (and (<= 3 (length chunk)) (= (. chunk (- (length chunk) 2) :leaf) :do)
           (not (. chunk (- (length chunk) 1) :leaf))
           (= (. chunk (length chunk) :leaf) :end))
      (let [kid (peephole (. chunk (- (length chunk) 1)))
            new-chunk {:ast chunk.ast}]
        (for [i 1 (- (length chunk) 3)]
          (table.insert new-chunk (peephole (. chunk i))))
        (for [i 1 (length kid)]
          (table.insert new-chunk (. kid i)))
        new-chunk)
      (icollect [_ x (ipairs chunk)] (peephole x))))

(fn flatten-chunk-correlated [main-chunk options]
  "Correlate line numbers in input with line numbers in output."
  (fn flatten [chunk out last-line file]
    (var last-line last-line)
    (if chunk.leaf
        (tset out last-line (.. (or (. out last-line) "") " " chunk.leaf))
        (each [_ subchunk (ipairs chunk)]
          (when (or subchunk.leaf (next subchunk)) ; ignore empty chunks
            ;; don't increase line unless it's from the same file
            (let [source (utils.ast-source subchunk.ast)]
              (when (= file source.filename)
                (set last-line (math.max last-line (or source.line 0))))
              (set last-line (flatten subchunk out last-line file))))))
    last-line)

  (let [out []
        last (flatten main-chunk out 1 options.filename)]
    (for [i 1 last]
      (when (= (. out i) nil)
        (tset out i "")))
    (table.concat out "\n")))

(fn flatten-chunk [file-sourcemap chunk tab depth]
  "Flatten a tree of indented Lua source code lines. Tab is used to indent."
  (if chunk.leaf
      (let [{: filename : line : endline} (utils.ast-source chunk.ast)]
        (if (= "end" chunk.leaf)
            (table.insert file-sourcemap [filename (or endline line)])
            (table.insert file-sourcemap [filename line]))
        chunk.leaf)
      (let [tab (case tab
                  true "  "
                  false ""
                  tab tab
                  nil "")]
        (table.concat (icollect [_ c (ipairs chunk)]
                        (when (or c.leaf (next c))
                          (let [sub (flatten-chunk file-sourcemap c tab
                                                   (+ depth 1))]
                            (if (< 0 depth)
                                (.. tab (sub:gsub "\n" (.. "\n" tab)))
                                sub)))) "\n"))))

;; Some global state for all fennel sourcemaps. For the time being, this seems
;; the easiest way to store the source maps.  Sourcemaps are stored with source
;; being mapped as the key, prepended with '@' if it is a filename (like
;; debug.getinfo returns for source).  The value is an array of mappings for
;; each line.
(local sourcemap [])

(fn make-short-src [source]
  (let [source (source:gsub "\n" " ")]
    (if (<= (length source) 49)
        (.. "[fennel \"" source "\"]")
        (.. "[fennel \"" (source:sub 1 46) "...\"]"))))

(fn flatten [chunk options]
  "Return Lua source and source map table."
  (let [chunk (peephole chunk)
        indent (or options.indent "  ")]
    (if options.correlate
        (values (flatten-chunk-correlated chunk options) [])
        (let [file-sourcemap {}
              src (flatten-chunk file-sourcemap chunk indent 0)]
          (set file-sourcemap.short_src (or options.filename
                                            (make-short-src (or options.source src))))
          (set file-sourcemap.key (if options.filename (.. "@" options.filename) src))
          (tset sourcemap file-sourcemap.key file-sourcemap)
          (values src file-sourcemap)))))

(fn make-metadata []
  "Make module-wide state table for metadata."
  (setmetatable [] {:__index {:get (fn [self tgt ?key]
                                     (when (. self tgt)
                                       (if (not= nil ?key)
                                           (. (. self tgt) ?key)
                                           (. self tgt))))
                              :set (fn [self tgt key value]
                                     (tset self tgt (or (. self tgt) []))
                                     (tset (. self tgt) key value)
                                     tgt)
                              :setall (fn [self tgt ...]
                                        (let [kv-len (select "#" ...)
                                              kvs [...]]
                                          (when (not= (% kv-len 2) 0)
                                            (error "metadata:setall() expected even number of k/v pairs"))
                                          (tset self tgt (or (. self tgt) []))
                                          (for [i 1 kv-len 2]
                                            (tset (. self tgt) (. kvs i)
                                                  (. kvs (+ i 1))))
                                          tgt))}
                    :__mode :k}))

(fn exprs1 [exprs]
  "Convert expressions to Lua string."
  (table.concat (icollect [_ e (ipairs exprs)] (tostring e)) ", "))

(fn keep-side-effects [exprs chunk ?start ast]
  "Compile side effects for a chunk."
  (for [j (or ?start 1) (length exprs)]
    (let [subexp (. exprs j)]
      ;; Avoid the rogue 'nil' expression (nil is usually a literal,
      ;; but becomes an expression if a special form returns 'nil')
      (if (and (= subexp.type :expression) (not= (. subexp 1) :nil))
          (emit chunk (: "do local _ = %s end" :format (tostring subexp)) ast)
          (= subexp.type :statement)
          (let [code (tostring subexp)
                disambiguated (if (= (code:byte) 40) (.. "do end " code) code)]
            (emit chunk disambiguated ast))))))

(fn handle-compile-opts [exprs parent opts ast]
  "Does some common handling of returns and register targets for special
forms. Also ensures a list expression has an acceptable number of expressions
if opts contains the nval option."
  (when opts.nval
    (let [n opts.nval
          len (length exprs)]
      (when (not= n len)
        (if (< n len)
            (do
              ;; drop extra
              (keep-side-effects exprs parent (+ n 1) ast)
              (for [i (+ n 1) len]
                (tset exprs i nil)))
            (for [i (+ (length exprs) 1) n] ; pad with nils
              (tset exprs i (utils.expr :nil :literal)))))))
  (when opts.tail
    (emit parent (string.format "return %s" (exprs1 exprs)) ast))
  (when opts.target
    (let [result (exprs1 exprs)]
      (emit parent
            (string.format "%s = %s" opts.target (if (= result "") :nil result))
            ast)))
  (if (or opts.tail opts.target)
      ;; Prevent statements and expression from being used twice if they
      ;; have side-effects. Since if the target or tail options are set,
      ;; the expressions are already emitted, we should not return them. This
      ;; is fine, as when these options are set, the caller doesn't need the
      ;; result anyways.
      {:returned true}
      (doto exprs (tset :returned true))))

(fn find-macro [ast scope]
  (let [macro* (-?>> (utils.sym? (. ast 1)) (tostring) (. scope.macros))
        multi-sym-parts (utils.multi-sym? (. ast 1))]
    (if (and (not macro*) multi-sym-parts)
        (let [nested-macro (utils.get-in scope.macros multi-sym-parts)]
          (assert-compile (or (not (. scope.macros (. multi-sym-parts 1)))
                              (= (type nested-macro) :function))
                          "macro not found in imported macro module" ast)
          nested-macro)
        macro*)))

(fn propagate-trace-info [{: filename : line : bytestart : byteend} _index node]
  "The stack trace info should be based on the macro caller, not the macro AST."
  (let [src (utils.ast-source node)]
    (when (and (= :table (type node)) (not= filename src.filename))
      (set (src.filename src.line src.from-macro?) (values filename line true))
      (set (src.bytestart src.byteend) (values bytestart byteend))))
  (= :table (type node)))

(fn quote-literal-nils [index node parent]
  "Replaces literal `nil` values with quoted version."
  (when (and parent (utils.list? parent))
    (for [i 1 (utils.maxn parent)]
      (when (= nil (. parent i))
        (tset parent i (utils.sym "nil")))))
  (values index node parent))

(fn built-in? [m]
  (accumulate [found? false _ f (pairs scopes.global.macros) :until found?]
    (= f m)))

(fn macroexpand* [ast scope ?once]
  "Expand macros in the ast. Only do one level if once is true."
  (case (if (utils.list? ast) (find-macro ast scope))
    false ast
    macro* (let [old-scope scopes.macro
                 _ (set scopes.macro scope)
                 ;; TODO: we want to pass a traceback level, but it only
                 ;; supports trimming the trace from the wrong direction.
                 (ok transformed) (xpcall #(macro* (unpack ast 2))
                                          (if (built-in? macro*)
                                              tostring
                                              debug.traceback))]
             (utils.walk-tree transformed
                              #(propagate-trace-info ast (quote-literal-nils $...)))
             (set scopes.macro old-scope)
             (assert-compile ok transformed ast)
             (utils.hook :macroexpand ast transformed scope)
             (if (or ?once (not transformed))
                 transformed
                 (macroexpand* transformed scope)))
    _ ast))

(fn compile-special [ast scope parent opts special]
  (let [exprs (or (special ast scope parent opts) (utils.expr :nil :literal))
        ;; Be very accepting of strings or expressions as well as lists
        ;; or expressions
        exprs (if (not= :table (type exprs))
                  (utils.expr exprs :expression)
                  exprs)
        exprs (if (utils.expr? exprs) [exprs] exprs)]
    ;; Unless the special form explicitly handles the target, tail,
    ;; and nval properties, (indicated via the 'returned' flag),
    ;; handle these options.
    (if (not exprs.returned) (handle-compile-opts exprs parent opts ast)
        (or opts.tail opts.target) {:returned true}
        exprs)))

(fn callable? [[call-ast] ctype callee]
  (if (= :literal ctype) (= "\"" (string.sub callee 1 1))
      (or (utils.sym? call-ast) (utils.list? call-ast))))

(fn compile-function-call [ast scope parent opts compile1 len]
  (let [{1 callee :type ctype} (. (compile1 (. ast 1) scope parent {:nval 1}) 1)
        fargs []]
    (assert-compile (callable? ast ctype callee)
                    (.. "cannot call literal value " (tostring (. ast 1))) ast)
    (for [i 2 len]
      (let [subexprs (compile1 (. ast i) scope parent
                               {:nval (if (not= i len) 1)})]
        (table.insert fargs (. subexprs 1))
        (if (= i len)
            ;; Add multivalues to function args
            (for [j 2 (length subexprs)]
              (table.insert fargs (. subexprs j)))
            ;; Emit sub expression only for side effects
            (keep-side-effects subexprs parent 2 (. ast i)))))
    ;; ("a")() is valid Lua call, "a"() isn't
    (let [pat (if (= :literal ctype) "(%s)(%s)" "%s(%s)")
          call (string.format pat (tostring callee) (exprs1 fargs))]
      (handle-compile-opts [(utils.expr call :statement)] parent opts ast))))

(fn compile-call [ast scope parent opts compile1]
  (utils.hook :call ast scope)
  (let [len (length ast)
        first (. ast 1)
        multi-sym-parts (utils.multi-sym? first)
        special (and (utils.sym? first) (. scope.specials (tostring first)))]
    (assert-compile (< 0 len) "expected a function, macro, or special to call"
                    ast)
    (if special
        (compile-special ast scope parent opts special)
        (and multi-sym-parts multi-sym-parts.multi-sym-method-call)
        (let [table-with-method (table.concat [(unpack multi-sym-parts 1
                                                       (- (length multi-sym-parts)
                                                          1))]
                                              ".")
              method-to-call (. multi-sym-parts (length multi-sym-parts))
              new-ast (utils.list (utils.sym ":" ast)
                                  (utils.sym table-with-method ast)
                                  method-to-call (select 2 (unpack ast)))]
          (compile1 new-ast scope parent opts))
        (compile-function-call ast scope parent opts compile1 len))))

(fn compile-varg [ast scope parent opts]
  (assert-compile scope.vararg (if scope.hashfn
                                   "use $... in hashfn"
                                   "unexpected vararg") ast)
  (handle-compile-opts [(utils.expr "..." :varg)] parent opts ast))

(fn compile-sym [ast scope parent opts]
  (let [multi-sym-parts (utils.multi-sym? ast)]
    (assert-compile (not (and multi-sym-parts
                              multi-sym-parts.multi-sym-method-call))
                    "multisym method calls may only be in call position" ast)
    ;; Handle nil as special symbol - it resolves to the nil literal
    ;; rather than being unmangled. Alternatively, we could remove it
    ;; from the lua keywords table.
    (let [e (if (= (. ast 1) :nil)
                (utils.expr :nil :literal)
                (symbol-to-expression ast scope true))]
      (handle-compile-opts [e] parent opts ast))))

(local view-opts
  (let [nan (tostring (/ 0 0))]
    {:infinity "(1/0)"
     :negative-infinity "(-1/0)"
     ;; byte 45 is -
     :nan (if (= 45 (nan:byte)) "(- (0/0))" "(0/0)")
     :negative-nan (if (= 45 (nan:byte)) "(0/0)" "(- (0/0))")}))

(fn compile-scalar [ast _scope parent opts]
  (let [compiled (case (type ast)
                   :nil :nil
                   :boolean (tostring ast)
                   :string (serialize-string ast)
                   :number (view ast view-opts))]
    (handle-compile-opts [(utils.expr compiled :literal)] parent opts)))

(fn compile-table [ast scope parent opts compile1]
  (fn escape-key [k]
    (if (and (= (type k) :string) (utils.valid-lua-identifier? k))
        k
        (let [[compiled] (compile1 k scope parent {:nval 1})]
          (.. "[" (tostring compiled) "]"))))

  (let [keys []
        buffer (icollect [i elem (ipairs ast)]
                 (let [nval (and (not= nil (. ast (+ i 1))) 1)]
                   (tset keys i true)
                   (exprs1 (compile1 elem scope parent {: nval}))))]

    (icollect [k (utils.stablepairs ast) :into buffer]
      (if (not (. keys k)) ; not part of the sequence section above
          (let [[v] (compile1 (. ast k) scope parent {:nval 1})]
            (string.format "%s = %s" (escape-key k) (tostring v)))))

    (handle-compile-opts [(utils.expr (.. "{" (table.concat buffer ", ") "}")
                                      :expression)]
                         parent opts ast)))

(fn compile1 [ast scope parent ?opts]
  "Compile an AST expression in the scope into parent, a tree of lines that is
eventually compiled into Lua code. Also returns some information about the
evaluation of the compiled expression, which can be used by the calling
function. Macros are resolved here, as well as special forms in that order.

* the `ast` param is the root AST to compile
* the `scope` param is the scope in which we are compiling
* the `parent` param is the table of lines that we are compiling into.
add lines to parent by appending {:ast ... :leaf ...} elements. Add indented
blocks by appending tables of more lines.
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
  (let [opts (or ?opts [])
        ast (macroexpand* ast scope)]
    (if (utils.list? ast)
        (compile-call ast scope parent opts compile1)
        (utils.varg? ast)
        (compile-varg ast scope parent opts)
        (utils.sym? ast)
        (compile-sym ast scope parent opts)
        (= (type ast) :table)
        (compile-table ast scope parent opts compile1)
        (or (= (type ast) :nil) (= (type ast) :boolean) (= (type ast) :number)
            (= (type ast) :string))
        (compile-scalar ast scope parent opts)
        (assert-compile false
                        (.. "could not compile value of type " (type ast)) ast))))

;; You may be tempted to clean up and refactor this function because it's so
;; huge and stateful but it really needs to get replaced; it is too tightly
;; coupled to the way the compiler outputs Lua; it should be split into general
;; data-driven parts vs Lua-emitting parts.
(fn destructure [to from ast scope parent opts]
  "Implements destructuring for forms like let, bindings, etc.
  Takes a number of opts to control behavior.
  * var: Whether or not to mark symbols as mutable
  * declaration: begin each assignment with 'local' in output
  * nomulti: disallow multisyms in the destructuring. for (local) and (global)
  * noundef: Don't set undefined bindings. (set)
  * forceglobal: Don't allow local bindings
  * symtype: the type of syntax calling the destructuring, for lua output names"
  (let [opts (or opts {})
        {: isvar : declaration : forceglobal : forceset : symtype} opts
        symtype (.. "_" (or symtype :dst))
        setter (if declaration "local %s = %s" "%s = %s")
        deferred-scope-changes {:manglings {} :symmeta {}}]
    (fn getname [symbol ast]
      "Get Lua source for symbol, and check for errors"
      (let [raw (. symbol 1)]
        (assert-compile (not (and opts.nomulti (utils.multi-sym? raw)))
                        (.. "unexpected multi symbol " raw) ast)
        (if declaration
            ;; Technically this is too early to declare the local, so we provide a
            ;; deferred-scope-changes table so we can add the symbol to the scope later
            ;; see https://todo.sr.ht/~technomancy/fennel/12
            (declare-local symbol scope symbol isvar deferred-scope-changes)
            (let [parts (or (utils.multi-sym? raw) [raw])
                  [first] parts
                  meta (. scope.symmeta first)]
              (assert-compile (not (raw:find ":")) "cannot set method sym" symbol)
              (when (and (= (length parts) 1) (not forceset))
                (assert-compile (not (and forceglobal meta))
                                (string.format "global %s conflicts with local"
                                               (tostring symbol))
                                symbol)
                (assert-compile (not (and meta (not meta.var)))
                                (.. "expected var " raw) symbol))
              (assert-compile (or meta (not opts.noundef)
                                  (and scope.hashfn (= :$ first))
                                  (global-allowed? first))
                              (.. "expected local " first) symbol)
              (when forceglobal
                (assert-compile (not (. scope.symmeta (. scope.unmanglings raw)))
                                (.. "global " raw " conflicts with local")
                                symbol)
                (tset scope.manglings raw (global-mangling raw))
                (tset scope.unmanglings (global-mangling raw) raw)
                (when (?. utils.root.options :allowedGlobals)
                  (table.insert (?. utils.root.options :allowedGlobals) raw)))
              (. (symbol-to-expression symbol scope) 1)))))

    (fn compile-top-target [lvalues]
      "Compile the outer most form. We can generate better Lua in this case."
      ;; Calculate initial rvalue
      (let [inits (icollect [_ l (ipairs lvalues)]
                    (if (. scope.manglings l) l :nil))
            init (table.concat inits ", ")
            lvalue (table.concat lvalues ", ")
            plast (. parent (length parent))]
        (var plen (length parent))
        (local ret (compile1 from scope parent {:target lvalue}))
        (when declaration
          ;; A single leaf emitted at the end of the parent chunk means a
          ;; simple assignment a = x was emitted, and we can just splice
          ;; "local " onto the front of it. However, we can't just check
          ;; based on plen, because some forms (such as include) insert new
          ;; chunks at the top of the parent chunk rather than just at the
          ;; end; this loop checks for this occurrence and updates plen to be
          ;; the index of the last thing in the parent before compiling the
          ;; new value.
          (for [pi plen (length parent)]
            (when (= (. parent pi) plast)
              (set plen pi)))
          (if (and (= (length parent) (+ plen 1))
                   (. (. parent (length parent)) :leaf))
              (tset (. parent (length parent)) :leaf
                    (.. "local " (. (. parent (length parent)) :leaf)))
              (= init :nil)
              (table.insert parent (+ plen 1) {: ast :leaf (.. "local " lvalue)})
              (table.insert parent (+ plen 1)
                            {: ast :leaf (.. "local " lvalue " = " init)})))
        ret))

    (fn destructure-sym [left rightexprs up1 top?]
      (let [lname (getname left up1)]
        (check-binding-valid left scope left)
        (if top?
            (compile-top-target [lname])
            (emit parent (setter:format lname (exprs1 rightexprs)) left))))

    (fn dynamic-set-target [[_ target & keys]]
      (assert-compile (utils.sym? target) "dynamic set needs symbol target" ast)
      ;; symbol-to-expression validates target against scope.manglings, allowed
      ;; globals, and exceptions like $, $1...$9 in hashfn, so we omit here
      (assert-compile (next keys) "dynamic set needs at least one key" ast)
      (let [keys (icollect [_ k (ipairs keys)]
                   (tostring (. (compile1 k scope parent {:nval 1}) 1)))]
        (string.format "%s[%s]" (tostring (symbol-to-expression target scope true))
                       (table.concat keys "]["))))

    (fn destructure-values [left rightexprs up1 destructure1 top?]
      (let [(left-names tables) (values [] [])]
        (each [i name (ipairs left)]
          (if (utils.sym? name) ; binding directly to a name
              (table.insert left-names (getname name up1))
              (utils.call-of? name ".")
              (table.insert left-names (dynamic-set-target name))
              (let [symname (gensym scope symtype)]
                ;; further destructuring of tables inside values
                (table.insert left-names symname)
                (tset tables i [name (utils.expr symname :sym)]))))
        (assert-compile (. left 1) "must provide at least one value" left)
        (if top?
            (compile-top-target left-names)
            ;; TODO: this is dumb, why does it need to be a special case here?
            (utils.expr? rightexprs)
            (emit parent (setter:format (table.concat left-names ",")
                                        (exprs1 rightexprs)) left)
            (let [names (table.concat left-names ",")
                  target (if declaration (.. "local " names) names)]
              (emit parent (compile1 rightexprs scope parent {: target}) left)))
        ;; recurse if left-side tables found
        (each [_ pair (utils.stablepairs tables)]
          (destructure1 (. pair 1) [(. pair 2)] left))))

    ;; TODO: remove in 2.0
    (local unpack-fn "function (t, k)
                        return ((getmetatable(t) or {}).__fennelrest
                                or function (t, k) return {(table.unpack or unpack)(t, k)} end)(t, k)
                      end")

    (local unpack-ks "function (t, e)
                        local rest = {}
                        for k, v in pairs(t) do
                          if not e[k] then rest[k] = v end
                        end
                        return rest
                      end")

    (fn destructure-kv-rest [s v left excluded-keys destructure1]
      (let [exclude-str (table.concat
                         (icollect [_ k (ipairs excluded-keys)]
                           (string.format "[%s] = true" (serialize-string k)))
                         ", ")
            subexpr (-> (.. "(" unpack-ks ")(%s, {%s})")
                        (string.gsub "\n%s*" " ")
                        (string.format s exclude-str)
                        (utils.expr :expression))]
        (destructure1 v [subexpr] left)))

    (fn destructure-rest [s k left destructure1]
      (let [unpack-str (.. "(" unpack-fn ")(%s, %s)")
            formatted (string.format (string.gsub unpack-str "\n%s*" " ") s k)
            subexpr (utils.expr formatted :expression)]
        (assert-compile (and (utils.sequence? left)
                             (let [next-symbol (. left (+ k 2))]
                               (or (= nil next-symbol)
                                   (utils.sym? next-symbol "&as"))))
                        "expected rest argument before last parameter"
                        left)
        (destructure1 (. left (+ k 1)) [subexpr] left)))

    (fn optimize-table-destructure? [left right]
      (and (utils.sequence? left) (utils.sequence? right)
           (accumulate [all (next left) _ d (ipairs left) &until (not all)]
             (or (and (utils.sym? d) (not (: (tostring d) :find "^&")))
                 (and (utils.list? d) (utils.sym? (. d 1) "."))))))

    (fn destructure-table [left rightexprs top? destructure1 up1]
      (assert-compile (and (= :table (type rightexprs))
                           (not (utils.sym? rightexprs :nil)))
                      "could not destructure literal" left)

      (if (optimize-table-destructure? left rightexprs)
          (destructure-values (utils.list (unpack left))
                              (utils.list (utils.sym :values)
                                          (unpack rightexprs))
                              up1 destructure1)
          (let [right (case (if top?
                                 (exprs1 (compile1 from scope parent))
                                 (exprs1 rightexprs))
                        "" :nil
                        right right)
                s (if (utils.sym? rightexprs) right (gensym scope symtype))
                excluded-keys []]
            (when (not (utils.sym? rightexprs))
              (emit parent (string.format "local %s = %s" s right) left))
            (each [k v (utils.stablepairs left)]
              (when (not (and (= :number (type k))
                              (: (tostring (. left (- k 1))) :find "^&")))
                (if (and (utils.sym? k) (= (tostring k) "&"))
                    (destructure-kv-rest s v left excluded-keys destructure1)

                    (and (utils.sym? v) (= (tostring v) "&"))
                    (destructure-rest s k left destructure1)

                    (and (utils.sym? k) (= (tostring k) :&as))
                    (destructure-sym v [(utils.expr (tostring s))] left)

                    (and (utils.sequence? left) (= (tostring v) :&as))
                    (let [(_ next-sym trailing) (select k (unpack left))]
                      (assert-compile (= nil trailing)
                                      "expected &as argument before last parameter"
                                      left)
                      (destructure-sym next-sym [(utils.expr (tostring s))] left))

                    (let [key (if (= (type k) :string) (serialize-string k) k)
                          subexpr (utils.expr (: "%s[%s]" :format s key) :expression)]
                      (when (= (type k) :string) (table.insert excluded-keys k))
                      (destructure1 v subexpr left))))))))

    (fn destructure1 [left rightexprs up1 top?]
      "Recursive auxiliary function"
      (if (and (utils.sym? left) (not= (. left 1) :nil))
          (destructure-sym left rightexprs up1 top?)
          (utils.table? left)
          (destructure-table left rightexprs top? destructure1 up1)
          (utils.call-of? left ".")
          (destructure-values [left] rightexprs up1 destructure1)
          (utils.list? left)
          (do (assert-compile top? "can't nest multi-value destructuring" left)
              (destructure-values left rightexprs up1 destructure1 true))
          (assert-compile false
                          (string.format "unable to bind %s %s" (type left)
                                         (tostring left))
                          (or (and (= (type (. up1 2)) :table) (. up1 2)) up1)))
      (and top? {:returned true}))

    (let [ret (destructure1 to from ast true)]
      (utils.hook :destructure from to scope opts)
      (apply-deferred-scope-changes scope deferred-scope-changes ast)
      ret)))

(fn require-include [ast scope parent opts]
  (fn opts.fallback [e no-warn]
    (when (not no-warn)
      (utils.warn (: "include module not found, falling back to require: %s"
                     :format (tostring e)) ast))
    (utils.expr (string.format "require(%s)" (tostring e)) :statement))

  (scopes.global.specials.include ast scope parent opts))

(fn compile-asts [asts options]
  (let [opts (utils.copy options)
        scope (if (= :_COMPILER opts.scope) scopes.compiler
                  opts.scope opts.scope
                  (make-scope scopes.global))
        chunk []]
    (when opts.requireAsInclude
      (set scope.specials.require require-include))
    (when opts.assertAsRepl
      (set scope.macros.assert scope.macros.assert-repl))
    (utils.root:set-reset)
    (set (utils.root.chunk utils.root.scope utils.root.options)
         (values chunk scope opts))
    (for [i 1 (length asts)]
      (let [exprs (compile1 (. asts i) scope chunk
                            {:nval (or (and (< i (length asts)) 0) nil)
                             :tail (= i (length asts))})]
        (keep-side-effects exprs chunk nil (. asts i))
        (when (= i (length asts))
          (utils.hook :chunk (. asts i) scope))))
    (utils.root.reset)
    (flatten chunk opts)))

(fn compile-stream [stream ?opts]
  (let [opts (or ?opts {})
        asts (icollect [_ ast (parser.parser stream opts.filename opts)] ast)]
    (compile-asts asts opts)))

(fn compile-string [str ?opts]
  (compile-stream (parser.string-stream str ?opts) ?opts))

(fn compile [from ?opts]
  (case (type from)
    :userdata (compile-stream #(-?> (from:read 1) (: :byte)) ?opts)
    :function (compile-stream from ?opts)
    _ (compile-asts [from] ?opts)))

(fn traceback-frame [info]
  (if (and (= info.what :C) info.name)
      (string.format "\t[C]: in function '%s'" info.name)
      (= info.what :C)
      "\t[C]: in ?"
      (let [remap (. sourcemap info.source)]
        (when (and remap (. remap info.currentline))
          ;; And some global info
          (set info.short_src
               (if (not= (or (. remap info.currentline 1) :unknown) :unknown)
                   (. sourcemap (.. "@" (. remap info.currentline 1))
                      :short_src)
                   remap.short_src))
          ;; Overwrite info with values from the mapping
          (set info.currentline (or (. remap info.currentline 2) -1)))
        (if (= info.what :Lua)
            (string.format "\t%s:%d: in function %s" info.short_src
                           info.currentline
                           (if info.name (.. "'" info.name "'") "?"))
            (= info.short_src "(tail call)")
            "  (tail call)"
            (string.format "\t%s:%d: in main chunk" info.short_src
                           info.currentline)))))

(local lua-getinfo debug.getinfo)

(fn traceback [?msg ?start]
  "A custom traceback function for Fennel that looks similar to debug.traceback.
Use with xpcall to produce fennel specific stacktraces. Skips frames from the
compiler by default; these can be re-enabled with export FENNEL_DEBUG=trace."
  (case (type ?msg)
    (where (or :nil :string))
    (let [msg (or ?msg "")]
      (if (and (or (msg:find "^%g+:%d+:%d+ Compile error:.*")
                   (msg:find "^%g+:%d+:%d+ Parse error:.*"))
               (not (utils.debug-on? :trace)))
          msg        ; skip the trace because it's compiler internals.
          (let [lines []]
            (if (or (msg:find "^%g+:%d+:%d+ Compile error:")
                    (msg:find "^%g+:%d+:%d+ Parse error:"))
                (table.insert lines msg)
                (let [newmsg (msg:gsub "^[^:]*:%d+:%s+" "runtime error: ")]
                  (table.insert lines newmsg)))
            (table.insert lines "stack traceback:")
            (var (done? level) (values false (or ?start 2)))
            ;; This would be cleaner factored out into its own recursive
            ;; function, but that would interfere with the traceback itself!
            (while (not done?)
              (case (lua-getinfo level :Sln)
                nil (set done? true)
                info (table.insert lines (traceback-frame info)))
              (set level (+ level 1)))
            (table.concat lines "\n"))))
    _ ?msg))

(fn getinfo [thread-or-level ...]
  ;; if we're given a level, we have to add 1 because fennel.getinfo
  ;; itself is on the stack. but if we're given a coro AND a level
  ;; then no level manipulation is necessary.
  (let [thread-or-level (if (= :number (type thread-or-level))
                            (+ 1 thread-or-level)
                            thread-or-level)
        info (lua-getinfo thread-or-level ...)
        mapped (and info (. sourcemap info.source))]
    (when mapped
      (each [_ key (ipairs [:currentline :linedefined :lastlinedefined])]
        (let [mapped-value (?. mapped (. info key) 2)]
          (when (and (. info key) mapped-value)
            (tset info key mapped-value))))
      (when info.activelines
        (set info.activelines (collect [line (pairs info.activelines)]
                                (. mapped line 2) true)))
      (when (= info.what "Lua")
        (set info.what "Fennel")))
    info))

(fn mixed-concat [t joiner]
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

;; TODO: too long
(fn do-quote [form scope parent runtime?]
  "Expand a quoted form into a data literal, evaluating unquote"
  (fn quote-all [form discard-non-numbers]
    (collect [k v (utils.stablepairs form)]
      (if (= (type k) :number)
          (values k (do-quote v scope parent runtime?))
          (not discard-non-numbers)
          (values (do-quote k scope parent runtime?)
                  (do-quote v scope parent runtime?)))))

  (if (utils.varg? form)
      (do
        (assert-compile (not runtime?)
                        "quoted ... may only be used at compile time" form)
        :_VARARG)
      (utils.sym? form) ; symbol
      (let [filename (if form.filename (string.format "%q" form.filename) :nil)
            symstr (tostring form)]
        (assert-compile (not runtime?)
                        "symbols may only be used at compile time" form)
        ;; We should be able to use "%q" for this but Lua 5.1 throws an error
        ;; when you try to format nil, because it's extremely bad.
        (if (or (symstr:find "#$") (symstr:find "#[:.]")) ; autogensym
            (string.format "_G.sym('%s', {filename=%s, line=%s})"
                           (autogensym symstr scope) filename
                           (or form.line :nil))
            ;; prevent non-gensymed symbols from being bound as an identifier
            (string.format "_G.sym('%s', {quoted=true, filename=%s, line=%s})"
                           symstr filename (or form.line :nil))))
      (utils.call-of? form :unquote)
      (let [res (unpack (compile1 (. form 2) scope parent))]
        (. res 1))
      (utils.list? form)
      (let [mapped (quote-all form true)
            filename (if form.filename (string.format "%q" form.filename) :nil)]
        (assert-compile (not runtime?) "lists may only be used at compile time"
                        form)
        ;; Constructing a list and then adding file/line data to it triggers a
        ;; bug where it changes the value of # for lists that contain nils in
        ;; them; constructing the list all in one go with the source data and
        ;; contents is how we construct lists in the parser and works around
        ;; this problem; allowing # to work in a way that lets us see the nils.
        (string.format (.. "setmetatable({filename=%s, line=%s, bytestart=%s, %s}"
                           ", getmetatable(_G.list()))")
                       filename (or form.line :nil) (or form.bytestart :nil)
                       (mixed-concat mapped ", ")))
      (utils.sequence? form)
      (let [mapped-str (mixed-concat (quote-all form) ", ")
            source (getmetatable form)
            filename (if source.filename (: "%q" :format source.filename) :nil)]
        (if runtime?
            (string.format "{%s}" mapped-str)
            ;; need to preserve the sequence marker in the metatable here
            (string.format "setmetatable({%s}, {filename=%s, line=%s, sequence=%s})"
                           mapped-str filename (or source.line :nil)
                           "(getmetatable(_G.sequence()))['sequence']")))
      (= (type form) :table) ; table
      (let [source (getmetatable form)
            filename (if source.filename (string.format "%q" source.filename)
                         :nil)]
        (string.format "setmetatable({%s}, {filename=%s, line=%s})"
                       (mixed-concat (quote-all form) ", ") filename
                       (if source source.line :nil)))
      (= (type form) :string)
      (serialize-string form)
      (tostring form)))

{: compile
 : compile1
 : compile-stream
 : compile-string
 : check-binding-valid
 : emit
 : destructure
 : require-include
 : autogensym
 : gensym
 : do-quote
 : global-mangling
 : global-unmangling
 : global-allowed?
 : apply-deferred-scope-changes
 :macroexpand macroexpand*
 : declare-local
 : make-scope
 : keep-side-effects
 : symbol-to-expression
 ;; general
 :assert assert-compile
 : scopes
 : traceback
 : getinfo
 :metadata (make-metadata)
 : sourcemap}
