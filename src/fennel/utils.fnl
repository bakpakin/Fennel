;; This module contains mostly general-purpose table-related functionality that
;; you might expect to see in a standard library in most langugaes, as well as
;; the definitions of several core compiler types. It could be split into two
;; distinct modules along those lines.

(local view (require :fennel.view))

(local version :1.3.1)

;;; Lua VM detection helper functions

(fn luajit-vm? []
  ;; Heuristic for detecting jit module from LuaJIT VM
  (and (not= nil _G.jit) (= (type _G.jit) :table) (not= nil _G.jit.on)
       (not= nil _G.jit.off) (= (type _G.jit.version_num) :number)))

(fn luajit-vm-version []
  ;; Use more recent Apple naming scheme
  (let [jit-os (if (= _G.jit.os :OSX) :macOS _G.jit.os)]
    (.. _G.jit.version " " jit-os "/" _G.jit.arch)))

(fn fengari-vm? []
  ;; Heuristic for detecting fengari module from Fengari VM
  (and (not= nil _G.fengari) (= (type _G.fengari) :table) (not= nil _G.fengari.VERSION)
       (= (type _G.fengari.VERSION_NUM) :number)))

(fn fengari-vm-version []
  (.. _G.fengari.RELEASE " (" _VERSION ")"))

(fn lua-vm-version []
  (if (luajit-vm?) (luajit-vm-version)
      (fengari-vm?) (fengari-vm-version)
      (.. "PUC " _VERSION)))

(fn runtime-version [?as-table]
  (if ?as-table
      {:fennel version
       :lua (lua-vm-version)}
      (.. "Fennel " version " on " (lua-vm-version))))

;;; General-purpose helper functions

(fn warn [message]
  (when (and _G.io _G.io.stderr)
    (_G.io.stderr:write (: "--WARNING: %s\n" :format (tostring message)))))

;; if utf8-aware len is available, use it, otherwise use bytes
(local len (match (pcall require :utf8)
             (true utf8) utf8.len
             _ string.len))

;; The following sort comparator is used for stablepairs below.
;; Need more than (< (tostring ) (tostring )) due to edge cases like {"1" x 1 y}
(local kv-order {:number 1 :boolean 2 :string 3 :table 4})
(fn kv-compare [a b]
  (case (values (type a) (type b))
    (where (or (:number :number) (:string :string))) (< a b)
    (where (a-t b-t) (not= a-t b-t)) (< (or (. kv-order a-t) 5)
                                        (or (. kv-order b-t) 5))
    _ (< (tostring a) (tostring b))))

(fn add-stable-keys [succ prev-key src ?pred]
  (var first prev-key)
  (let [last (accumulate [prev prev-key _ k (ipairs src)]
               ;; Skip any keys we've already seen, or that fail ?pred
               (if (or (= prev k) (not= (. succ k) nil)
                       (and ?pred (not (?pred k))))
                 prev
                 (if (= first nil) (do (set first k) k)
                     (not= prev nil) (do (tset succ prev k) k)
                     k)))]
    (values succ last first)))

(fn stablepairs [t]
  "Like pairs, but gives consistent ordering every time. On 5.1, 5.2, and LuaJIT
  pairs is already stable, but on 5.3+ every run gives different ordering. Gives
  the same order as parsed in the AST when present in the metatable."
  (let [mt-keys (?. (getmetatable t) :keys)
        ;; Generate a table of successor keys to guarantee stable order.
        ;; First, use order from the :keys mt, but only for keys present in t
        (succ prev first-mt) (add-stable-keys {} nil (or mt-keys []) #(. t $))
        ;; Sort any keys unspecified by :keys metatable
        pairs-keys (doto (icollect [k (pairs t)] k) (table.sort kv-compare))
        (succ _ first-after-mt) (add-stable-keys succ prev pairs-keys)
        first (if (= first-mt nil) first-after-mt first-mt)]
    (fn stablenext [tbl key]
      (case (if (= key nil) first (. succ key))
        next-key (-?>> (. tbl next-key) (values next-key))))

    (values stablenext t nil)))

(fn get-in [tbl path ?fallback]
  (assert (and (= :table (type tbl))) "get-in expects path to be a table")
  (if (= 0 (length path))
    ?fallback
    (match (accumulate [t tbl _ k (ipairs path) :until (= nil t)]
             (match (type t) :table (. t k)))
      res res
      _ ?fallback)))

;; Note: the collect/icollect macros mostly make map/kvmap obsolete.

(fn map [t f ?out]
  "Map function f over sequential table t, removing values where f returns nil.
Optionally takes a target table to insert the mapped values into."
  (let [out (or ?out [])
        f (if (= (type f) :function)
              f
              #(. $ f))]
    (each [_ x (ipairs t)]
      (match (f x)
        v (table.insert out v)))
    out))

(fn kvmap [t f ?out]
  "Map function f over key/value table t, similar to above, but it can return a
sequential table if f returns a single value or a k/v table if f returns two.
Optionally takes a target table to insert the mapped values into."
  (let [out (or ?out [])
        f (if (= (type f) :function)
              f
              #(. $ f))]
    (each [k x (stablepairs t)]
      (match (f k x)
        (key value) (tset out key value)
        (value) (table.insert out value)))
    out))

(fn copy [from ?to]
  "Returns a shallow copy of its table argument. Returns an empty table on nil."
  (collect [k v (pairs (or from [])) :into (or ?to {})]
    (values k v)))

(fn member? [x tbl ?n]
  (match (. tbl (or ?n 1))
    x true
    nil nil
    _ (member? x tbl (+ (or ?n 1) 1))))

(fn maxn [tbl]
  (accumulate [max 0 k (pairs tbl)]
    (if (= :number (type k)) (math.max max k) max)))

(fn every? [t predicate]
  (accumulate [result true
               _ item (ipairs t)
               :until (not result)]
    (predicate item)))

(fn allpairs [tbl]
  "Like pairs, but if the table has an __index metamethod, it will recurisvely
traverse upwards, skipping duplicates, to iterate all inherited properties"
  (assert (= (type tbl) :table) "allpairs expects a table")
  (var t tbl)
  (let [seen []]
    (fn allpairs-next [_ state]
      (let [(next-state value) (next t state)]
        (if (. seen next-state)
            (allpairs-next nil next-state)
            next-state
            (do
              (tset seen next-state true)
              (values next-state value))
            (match (getmetatable t)
              {: __index} (when (= :table (type __index))
                            (set t __index)
                            (allpairs-next t))))))

    allpairs-next))

;;; AST functions

;; AST nodes tend to be implemented as tables with specific "marker" metatables
;; set on them; they have constructor functions which set the metatables and
;; predicate functions which check the metatables. The fact that they use
;; metatables should be considered an implementation detail. String and number
;; literals are represented literally, and "regular" key/value tables are
;; represented without a marker metatable since their metatables are needed to
;; store file/line source data.

(fn deref [self]
  "Get the name of a symbol."
  (. self 1))

;; haven't defined sym yet; circularity is needed here
(var nil-sym nil)

;; the tostring2 argument is passed in by fennelview; this lets us use the same
;; function for regular tostring as for fennelview. when called from fennelview
;; the list's contents will also show as being fennelviewed.
(fn list->string [self ?view ?options ?indent]
  (let [safe []
        view (if ?view #(?view $ ?options ?indent) view)
        max (maxn self)]
    (for [i 1 max]
      (tset safe i (or (and (= (. self i) nil) nil-sym) (. self i))))
    (.. "(" (table.concat (map safe view) " " 1 max) ")")))

(fn comment-view [c]
  (values c true))

(fn sym= [a b]
  (and (= (deref a) (deref b)) (= (getmetatable a) (getmetatable b))))

(fn sym< [a b]
  (< (. a 1) (tostring b)))

(local symbol-mt {1 :SYMBOL
                  :__fennelview deref
                  :__tostring deref
                  :__eq sym=
                  :__lt sym<})

(local expr-mt {1 :EXPR :__tostring (fn [x] (tostring (deref x)))})
(local list-mt {1 :LIST :__fennelview list->string :__tostring list->string})
(local comment-mt {1 :COMMENT
                   :__fennelview comment-view
                   :__tostring deref
                   :__eq sym=
                   :__lt sym<})

(local sequence-marker [:SEQUENCE])
(local varg-mt {1 :VARARG :__fennelview deref :__tostring deref})

(local getenv (or (and os os.getenv) #nil))

(fn debug-on? [flag]
  (let [level (or (getenv :FENNEL_DEBUG) "")]
    (or (= level :all) (level:find flag))))

(fn list [...]
  "Create a new list. Lists are a compile-time construct in Fennel; they are
represented as tables with a special marker metatable. They only come from
the parser, and they represent code which comes from reading a paren form;
they are specifically not cons cells."
  (setmetatable [...] list-mt))

(fn sym [str ?source]
  "Create a new symbol. Symbols are a compile-time construct in Fennel and are
not exposed outside the compiler. Second optional argument is a table describing
where the symbol came from; should be a table with filename, line, bytestart,
and byteend fields."
  (setmetatable (collect [k v (pairs (or ?source [])) :into [str]]
                  (if (= (type k) :string) (values k v)))
                symbol-mt))

(set nil-sym (sym :nil))

(fn sequence [...]
  "Create a new sequence. Sequences are tables that come from the parser when
it encounters a form with square brackets. They are treated as regular tables
except when certain macros need to look for binding forms, etc specifically."
  ;; can't use SEQUENCE-MT directly as the sequence metatable like we do with
  ;; the other types without giving up the ability to set source metadata
  ;; on a sequence, (which we need for error reporting) so embed a marker
  ;; value in the metatable instead.
  (setmetatable [...] {:sequence sequence-marker
                       :__fennelview
                       (fn [seq view inspector indent]
                         (let [opts (doto inspector
                                      (tset :empty-as-sequence?
                                            {:once true :after inspector.empty-as-sequence?})
                                      (tset :metamethod?
                                            {:once false :after inspector.metamethod?}))]
                           (view seq opts indent)))}))

(fn expr [strcode etype]
  "Create a new expression. etype should be one of:
  :literal literals like numbers, strings, nil, true, false
  :expression Complex strings of Lua code, may have side effects, etc
              but is an expression
  :statement Same as expression, but is also a valid statement (function calls)
  :vargs variable arguments (multivalue arg) symbol
  :sym symbol reference"
  (setmetatable {:type etype 1 strcode} expr-mt))

(fn comment* [contents ?source]
  (let [{: filename : line} (or ?source [])]
    (setmetatable {1 contents : filename : line} comment-mt)))

(fn varg [?source]
  (setmetatable (collect [k v (pairs (or ?source [])) :into ["..."]]
                  (if (= (type k) :string) (values k v)))
                varg-mt))

(fn expr? [x]
  "Checks if an object is an expression. Returns the object if it is."
  (and (= (type x) :table) (= (getmetatable x) expr-mt) x))

(fn varg? [x]
  "Checks if an object is the varg symbol. Returns the object if is."
  (and (= (type x) :table) (= (getmetatable x) varg-mt) x))

(fn list? [x]
  "Checks if an object is a list. Returns the object if is."
  (and (= (type x) :table) (= (getmetatable x) list-mt) x))

(fn sym? [x ?name]
  "Checks if an object is a symbol. Returns the object if it is.
When given a second string argument, will check that the sym's name matches it."
  (and (= (type x) :table) (= (getmetatable x) symbol-mt)
       (or (= nil ?name) (= (. x 1) ?name)) x))

(fn sequence? [x]
  "Checks if an object is a sequence (created with a [] literal)"
  (let [mt (and (= (type x) :table) (getmetatable x))]
    (and mt (= mt.sequence sequence-marker) x)))

(fn comment? [x]
  (and (= (type x) :table) (= (getmetatable x) comment-mt) x))

(fn table? [x]
  "Checks if an object any kind of table, EXCEPT list/symbol/varg/comment."
  (and (= (type x) :table) (not (varg? x)) (not= (getmetatable x) list-mt)
       (not= (getmetatable x) symbol-mt) (not (comment? x)) x))

(fn kv-table? [t]
  "Checks if t is an associative table and not empty"
  (when (table? t)
    (let [(nxt t k) (pairs t)
          len (length t)
          next-state (if (= 0 len) k len)]
      (and (not= nil (nxt t next-state)) t))))

(fn string? [x] (= (type x) :string))

(fn multi-sym? [str]
  "Returns a table containing the symbol's segments if passed a multi-sym.
A multi-sym refers to a table field reference like tbl.x or access.channel:deny.
Returns nil if passed something other than a multi-sym."
  (if (sym? str) (multi-sym? (tostring str))
      (not= (type str) :string) false
      (and (or (: str :match "%.") (: str :match ":"))
           (not (str:match "%.%."))
           (not= (str:byte) (string.byte "."))
           (not= (str:byte (- 1)) (string.byte "."))
           (let [parts []]
             (each [part (str:gmatch "[^%.%:]+[%.%:]?")]
                   (let [last-char (part:sub (- 1))]
                     (when (= last-char ":")
                       (set parts.multi-sym-method-call true))
                     (if (or (= last-char ":") (= last-char "."))
                       (tset parts (+ (length parts) 1) (part:sub 1 (- 2)))
                       (tset parts (+ (length parts) 1) part))))
             (and (< 0 (length parts))
                  parts)))))

(fn quoted? [symbol]
  symbol.quoted)

(fn idempotent-expr? [x]
  "Checks if an object is an idempotent expression. Returns the object if it is."
  (or (= (type x) :string)
      (= (type x) :integer)
      (= (type x) :number)
      (and (sym? x)
           (not (multi-sym? x)))))

(fn ast-source [ast]
  "Get a table for the given ast which includes file/line info, if possible."
  (if (or (table? ast) (sequence? ast)) (or (getmetatable ast) {})
      (= :table (type ast)) ast
      {}))

;;; Other

(fn walk-tree [root f ?custom-iterator]
  "Walks a tree (like the AST), invoking f(node, idx, parent) on each node.
When f returns a truthy value, recursively walks the children."
  (fn walk [iterfn parent idx node]
    (when (f idx node parent)
      (each [k v (iterfn node)]
        (walk iterfn node k v))))

  (walk (or ?custom-iterator pairs) nil nil root)
  root)

(local lua-keywords {:and true
                     :break true
                     :do true
                     :else true
                     :elseif true
                     :end true
                     :false true
                     :for true
                     :function true
                     :if true
                     :in true
                     :local true
                     :nil true
                     :not true
                     :or true
                     :repeat true
                     :return true
                     :then true
                     :true true
                     :until true
                     :while true
                     :goto true})

(fn valid-lua-identifier? [str]
  (and (str:match "^[%a_][%w_]*$") (not (. lua-keywords str))))

(local propagated-options [:allowedGlobals
                           :indent
                           :correlate
                           :useMetadata
                           :env
                           :compiler-env
                           :compilerEnv])

(fn propagate-options [options subopts]
  "Certain options should always get propagated onwards when a function that
has options calls down into compile."
  (each [_ name (ipairs propagated-options)]
    (tset subopts name (. options name)))
  subopts)

(local root {:chunk nil :scope nil :options nil :reset (fn [])})

(fn root.set-reset [{: chunk : scope : options : reset}]
  (fn root.reset []
    (set (root.chunk root.scope root.options root.reset)
         (values chunk scope options reset))))

(local warned {})

(fn check-plugin-version [{: name : versions &as plugin}]
  (when (and (not (member? (version:gsub "-dev" "") (or versions [])))
             (not (. warned plugin)))
    (tset warned plugin true)
    (warn (string.format "plugin %s does not support Fennel version %s"
                         (or name :unknown) version))))

(fn hook-opts [event ?options ...]
  "Side-effecting plugins should return nil. In the event that a plugin handler
returns non-nil it will be used as the value of the call and further plugin
handlers will be skipped."
  (let [plugins (or (?. ?options :plugins)
                    (?. root.options :plugins))]
    (when plugins
      (accumulate [result nil
                   _ plugin (ipairs plugins)
                   :until result]
        (do
          (check-plugin-version plugin)
          (match (. plugin event)
            f (f ...)))))))


(fn hook [event ...]
  "Call the relevant compiler plugin hooks for a given event"
  (hook-opts event root.options ...))

{: warn
 : allpairs
 : stablepairs
 : copy
 : get-in
 : kvmap
 : map
 : walk-tree
 : member?
 : maxn
 : every?
 : list
 : sequence
 : sym
 : varg
 : expr
 :comment comment*
 : comment?
 : expr?
 : list?
 : multi-sym?
 : sequence?
 : sym?
 : table?
 : kv-table?
 : varg?
 : quoted?
 : string?
 : idempotent-expr?
 : valid-lua-identifier?
 : lua-keywords
 : hook
 : hook-opts
 : propagate-options
 : root
 : debug-on?
 : ast-source
 : version
 : runtime-version
 : len
 :path (table.concat [:./?.fnl :./?/init.fnl (getenv :FENNEL_PATH)] ";")
 :macro-path (table.concat [:./?.fnl :./?/init-macros.fnl :./?/init.fnl
                            (getenv :FENNEL_MACRO_PATH)] ";")}
