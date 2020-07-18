(fn stablepairs [t]
  "Like pairs, but gives consistent ordering every time. On 5.1, 5.2, and LuaJIT
  pairs is already stable, but on 5.3 every run gives different ordering."
  (let [keys []
        succ []]
    (each [k (pairs t)]
      (table.insert keys k))
    (table.sort keys (fn [a b] (< (tostring a) (tostring b))))
    (each [i k (ipairs keys)]
      (tset succ k (. keys (+ i 1))))
    (fn stablenext [tbl idx]
      (if (= idx nil)
          (values (. keys 1) (. tbl (. keys 1)))
          (values (. succ idx) (. tbl (. succ idx)))))
    (values stablenext t nil)))

(fn map [t f out]
  "Map function f over sequential table t, removing values where f returns nil.
Optionally takes a target table to insert the mapped values into."
  (let [out (or out [])
        f (if (= (type f) "function")
              f
              (let [s f] (fn [x] (. x s))))]
    (each [_ x (ipairs t)]
      (match (f x)
        v (table.insert out v)))
    out))

(fn kvmap [t f out]
  "Map function f over key/value table t, similar to above, but it can return a
sequential table if f returns a single value or a k/v table if f returns two.
Optionally takes a target table to insert the mapped values into."
  (let [out (or out [])
        f (if (= (type f) "function")
              f
              (let [s f] (fn [x] (. x s))))]
    (each [k x (stablepairs t)]
      (let [(korv v) (f k x)]
        (when (and korv (not v))
          (table.insert out korv))
        (when (and korv v)
          (tset out korv v))))
    out))

(fn copy [from]
  "Returns a shallow copy of its table argument. Returns an empty table on nil."
  (let [to []]
    (each [k v (pairs (or from []))]
      (tset to k v))
    to))

(fn allpairs [tbl]
  "Like pairs, but if the table has an __index metamethod, it will recurisvely
traverse upwards, skipping duplicates, to iterate all inherited properties"
  (assert (= (type tbl) "table") "allpairs expects a table")
  (var t tbl)
  (let [seen []]
    (fn allpairsNext [_ state]
      (let [(nextState value) (next t state)]
        (if (. seen nextState)
            (allpairsNext nil nextState)
            nextState
            (do (tset seen nextState true)
                (values nextState value))
            (let [meta (getmetatable t)]
              (when (and meta meta.__index)
                (set t meta.__index)
                (allpairsNext t))))))
    allpairsNext))

(fn deref [self]
  "Get the name of a symbol."
  (. self 1))

(var nilSym nil) ; haven't defined sym yet; create this later

(fn listToString [self tostring2]
  (var (safe max) (values [] 0))
  (each [k (pairs self)]
    (when (and (= (type k) "number") (> k max))
      (set max k)))
  (for [i 1 max 1]
    (tset safe i (or (and (= (. self i) nil) nilSym) (. self i))))
  (.. "(" (table.concat (map safe (or tostring2 tostring)) " " 1 max) ")"))

(local SYMBOL_MT {1 "SYMBOL" :__fennelview deref :__tostring deref})
(local EXPR_MT {1 "EXPR" :__tostring deref})
(local LIST_MT {1 "LIST" :__fennelview listToString :__tostring listToString})
(local SEQUENCE_MARKER ["SEQUENCE"])
(local VARARG (setmetatable ["..."]
                            {1 "VARARG" :__fennelview deref :__tostring deref}))

(local getenv (or (and os os.getenv) (fn [] nil)))

(fn debugOn [flag]
  (let [level (or (getenv "FENNEL_DEBUG") "")]
    (or (= level "all") (: level "find" flag))))

(fn list [...]
  "Create a new list. Lists are a compile-time construct in Fennel; they are
represented as tables with a special marker metatable. They only come from
the parser, and they represent code which comes from reading a paren form;
they are specifically not cons cells."
  (setmetatable [...] LIST_MT))

(fn sym [str scope source]
  "Create a new symbol. Symbols are a compile-time construct in Fennel and are
not exposed outside the compiler. Symbols have source data describing what
file, line, etc that they came from."
  (let [s {:scope scope 1 str}]
    (each [k v (pairs (or source []))]
      (when (= (type k) "string")
        (tset s k v)))
    (setmetatable s SYMBOL_MT)))

(set nilSym (sym "nil"))

(fn sequence [...]
  "Create a new sequence. Sequences are tables that come from the parser when
it encounters a form with square brackets. They are treated as regular tables
except when certain macros need to look for binding forms, etc specifically."
  ;; can't use SEQUENCE_MT directly as the sequence metatable like we do with
  ;; the other types without giving up the ability to set source metadata
  ;; on a sequence, (which we need for error reporting) so embed a marker
  ;; value in the metatable instead.
  (setmetatable [...] {:sequence SEQUENCE_MARKER}))

(fn expr [strcode etype]
  "Create a new expression. etype should be one of:
  :literal literals like numbers, strings, nil, true, false
  :expression Complex strings of Lua code, may have side effects, etc
              but is an expression
  :statement Same as expression, but is also a valid statement (function calls)
  :vargs varargs symbol
  :sym symbol reference"
  (setmetatable {:type etype 1 strcode} EXPR_MT))

(fn varg [] VARARG)

;; TODO: rename these to expr?, varg?, etc once all callers are fennelized
(fn isExpr [x]
  "Checks if an object is an expression. Returns the object if it is."
  (and (= (type x) "table") (= (getmetatable x) EXPR_MT) x))

(fn isVarg [x]
  "Checks if an object is the vararg symbol. Returns the object if is."
  (and (= x VARARG) x))

(fn isList [x]
  "Checks if an object is a list. Returns the object if is."
  (and (= (type x) "table") (= (getmetatable x) LIST_MT) x))

(fn isSym [x]
  "Checks if an object is a symbol. Returns the object if it is."
  (and (= (type x) "table") (= (getmetatable x) SYMBOL_MT) x))

(fn isTable [x]
  "Checks if an object any kind of table, EXCEPT list or symbol or vararg."
  (and (= (type x) "table")
       (not= x VARARG)
       (not= (getmetatable x) LIST_MT)
       (not= (getmetatable x) SYMBOL_MT)
       x))

(fn isSequence [x]
  "Checks if an object is a sequence (created with a [] literal)"
  (let [mt (and (= (type x) "table") (getmetatable x))]
    (and mt (= mt.sequence SEQUENCE_MARKER) x)))

(fn isMultiSym [str]
  "A multi symbol is a symbol that is actually composed of two or more symbols
using dot syntax. The main differences from normal symbols is that they can't
be declared local, and they may have side effects on invocation (metatables)."
  (if (isSym str) (isMultiSym (tostring str))
      (not= (type str) "string") false
      (let [parts []]
        (each [part (str:gmatch "[^%.%:]+[%.%:]?")]
          (local lastChar (: part "sub" (- 1)))
          (when (= lastChar ":")
            (set parts.multiSymMethodCall true))
          (if (or (= lastChar ":") (= lastChar "."))
              (tset parts (+ (# parts) 1) (: part "sub" 1 (- 2)))
              (tset parts (+ (# parts) 1) part)))
        (and (> (# parts) 0) (or (: str "match" "%.") (: str "match" ":"))
             (not (: str "match" "%.%."))
             (not= (: str "byte") (string.byte "."))
             (not= (: str "byte" (- 1)) (string.byte "."))
             parts))))

(fn isQuoted [symbol] symbol.quoted)

(fn walkTree [root f customIterator]
  "Walks a tree (like the AST), invoking f(node, idx, parent) on each node.
When f returns a truthy value, recursively walks the children."
  (fn walk [iterfn parent idx node]
    (when (f idx node parent)
      (each [k v (iterfn node)]
        (walk iterfn node k v))))
  (walk (or customIterator pairs) nil nil root)
  root)

(local luaKeywords ["and" "break" "do" "else" "elseif" "end" "false" "for"
                    "function" "if" "in" "local" "nil" "not" "or" "repeat"
                    "return" "then" "true" "until" "while"])

(each [i v (ipairs luaKeywords)]
  (tset luaKeywords v i))

(fn isValidLuaIdentifier [str]
  (and (str:match "^[%a_][%w_]*$") (not (. luaKeywords str))))

(local propagatedOptions [:allowedGlobals :indent :correlate :useMetadata :env])

(fn propagateOptions [options subopts]
  "Certain options should always get propagated onwards when a function that
has options calls down into compile."
  (each [_ name (ipairs propagatedOptions)]
    (tset subopts name (. options name)))
  subopts)

(local root {:chunk nil :scope nil :options nil :reset (fn [])})

(fn root.setReset [root]
  (let [{: chunk : scope : options : reset} root]
    (fn root.reset []
      #(set (root.chunk root.scope root.options root.reset)
            (values chunk scope options reset)))))

{;; general table functions
 : allpairs : stablepairs : copy : kvmap : map : walkTree

 ;; AST functions
 : list : sequence : sym : varg : deref : expr : isQuoted
 : isExpr : isList : isMultiSym : isSequence : isSym : isTable : isVarg

 ;; other
 : isValidLuaIdentifier : luaKeywords
 : propagateOptions : root : debugOn
 :path (table.concat (doto ["./?.fnl" "./?/init.fnl"]
                       (table.insert (getenv "FENNEL_PATH"))) ";")}
