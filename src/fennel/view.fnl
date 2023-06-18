;; A pretty-printer that outputs tables in Fennel syntax.

(local type-order {:number 1
                   :boolean 2
                   :string 3
                   :table 4
                   :function 5
                   :userdata 6
                   :thread 7})

(local default-opts {:one-line? false
                     :detect-cycles? true
                     :empty-as-sequence? false
                     :metamethod? true
                     :prefer-colon? false
                     :escape-newlines? false
                     :utf8? true
                     :line-length 80
                     :depth 128
                     :max-sparse-gap 10})

;; Pairs, ipairs and length functions that respect metamethods

(local lua-pairs pairs)
(local lua-ipairs ipairs)

(fn pairs [t]
  (match (getmetatable t)
    {:__pairs p} (p t)
    _ (lua-pairs t)))

(fn ipairs [t]
  (match (getmetatable t)
    {:__ipairs i} (i t)
    _ (lua-ipairs t)))

(fn length* [t]
  (match (getmetatable t)
    {:__len l} (l t)
    _ (length t)))

(fn get-default [key]
  (match (. default-opts key)
    nil (error (: "option '%s' doesn't have a default value, use the :after key to set it"
                  :format (tostring key)))
    v v))

(fn getopt [options key]
  "Get an option with the respect to `:once` syntax."
  (case (. options key)
    {:once val*} val*
    ?val ?val))

(fn normalize-opts [options]
  "Prepare options for a nested invocation of the pretty printer."
  (collect [k v (pairs options)]
    (->> (match v
           {:after val} val
           (where {} v.once) (get-default k)
           _ v)
         (values k))))

(fn sort-keys [[a] [b]]
  ;; Sort keys depending on the `type-order`.
  (let [ta (type a)
        tb (type b)]
    (if (and (= ta tb) (or (= ta :string) (= ta :number)))
        (< a b)
        (let [dta (. type-order ta)
              dtb (. type-order tb)]
          (if (and dta dtb) (< dta dtb)
              dta true
              dtb false
              (< ta tb))))))

(fn max-index-gap [kv]
  ;; Find the largest gap between neighbor items
  (var gap 0)
  (when (< 0 (length* kv))
    (var i 0)
    (each [_ [k] (ipairs kv)]
      (when (< gap (- k i))
        (set gap (- k i)))
      (set i k)))
  gap)

(fn fill-gaps [kv]
  ;; Fill gaps in sequential kv-table
  ;; [[1 "a"] [4 "d"]] => [[1 "a"] [2] [3] [4 "d"]]
  (let [missing-indexes []]
    (var i 0)
    (each [_ [j] (ipairs kv)]
      (set i (+ i 1))
      (while (< i j)
        (table.insert missing-indexes i)
        (set i (+ i 1))))
    (each [_ k (ipairs missing-indexes)]
      (table.insert kv k [k]))))

(fn table-kv-pairs [t options]
  ;; Return table of tables with first element representing key and second
  ;; element representing value.  Second value indicates table type, which is
  ;; either sequential or associative.
  ;; [:a :b :c] => [[1 :a] [2 :b] [3 :c]]
  ;; {:a 1 :b 2} => [[:a 1] [:b 2]]
  (var assoc? false)
  (let [kv []
        insert table.insert]
    (each [k v (pairs t)]
      (when (or (not= (type k) :number)
                (< k 1))
        (set assoc? true))
      (insert kv [k v]))
    (table.sort kv sort-keys)
    (when (not assoc?)
      (if (< options.max-sparse-gap (max-index-gap kv))
          (set assoc? true)
          (fill-gaps kv)))
    (if (= (length* kv) 0)
        (values kv :empty)
        (values kv (if assoc? :table :seq)))))

(fn count-table-appearances [t appearances]
  (when (= (type t) :table)
    (if (not (. appearances t))
        (do
          (tset appearances t 1)
          (each [k v (pairs t)]
            (count-table-appearances k appearances)
            (count-table-appearances v appearances)))
        (tset appearances t (+ (or (. appearances t) 0) 1))))
  appearances)

(fn save-table [t seen]
  ;; Save table `t` in `seen` storing `t` as key, and its index as an id.
  (let [seen (or seen {:len 0})
        id (+ seen.len 1)]
    (when (not (. seen t))
      (tset seen t id)
      (set seen.len id))
    seen))

(fn detect-cycle [t seen]
  "Return `true` if table `t` appears in itself."
  (when (= :table (type t))
    (tset seen t true)
    (accumulate [res nil
                 k v (pairs t)
                 :until res]
      (or (. seen k) (detect-cycle k seen)
          (. seen v) (detect-cycle v seen)))))

(fn visible-cycle? [t options]
  ;; Detect cycle, save table's ID in seen tables, and determine if
  ;; cycle is visible.  Exposed via options table to use in
  ;; __fennelview metamethod implementations
  (and (getopt options :detect-cycles?) (detect-cycle t {}) (save-table t options.seen)
       (< 1 (or (. options.appearances t) 0))))

(fn table-indent [indent id]
  ;; When table contains cycles, it is printed with a prefix before opening
  ;; delimiter.  Prefix has a variable length, as it contains `id` of the table
  ;; and fixed part of `2` characters `@` and either `[` or `{` depending on
  ;; `t`type.  If `t` has visible cycles, we need to increase indent by the size
  ;; of the prefix.
  (let [opener-length (if id
                          (+ (length* (tostring id)) 2)
                          1)]
    (+ indent opener-length)))

;; forward declaration for recursive pretty printer
(var pp nil)

(fn concat-table-lines [elements
                        options
                        multiline?
                        indent
                        table-type
                        prefix
                        last-comment?]
  (let [indent-str (.. "\n" (string.rep " " indent))
        open (.. (or prefix "") (if (= :seq table-type) "[" "{"))
        close (if (= :seq table-type) "]" "}")
        oneline (.. open (table.concat elements " ") close)]
    (if (and (not (getopt options :one-line?))
             (or multiline?
                 (< options.line-length (+ indent (length* oneline)))
                 last-comment?))
        (.. open (table.concat elements indent-str)
            (if last-comment? indent-str "") close)
        oneline)))

;; this will only produce valid answers for valid utf-8 data, since it just
;; counts the amount of initial utf-8 bytes in a given string. we can do this
;; because we only run this on validated and escaped strings.
(fn utf8-len [x]
  (accumulate [n 0 _ (string.gmatch x "[%z\001-\127\192-\247]")] (+ n 1)))

;; an alternative to `utils.comment?` to avoid a depedency cycle.
(fn comment? [x]
  (if (= :table (type x))
      (let [fst (. x 1)]
        (and (= :string (type fst)) (not= nil (fst:find "^;"))))
      false))

(fn pp-associative [t kv options indent]
  (var multiline? false)
  (let [id (. options.seen t)]
    (if (<= options.depth options.level) "{...}"
        (and id (getopt options :detect-cycles?)) (.. "@" id "{...}")
        (let [visible-cycle? (visible-cycle? t options)
              id (and visible-cycle? (. options.seen t))
              indent (table-indent indent id)
              slength (if (getopt options :utf8?) utf8-len #(length $))
              prefix (if visible-cycle? (.. "@" id) "")
              items (let [options (normalize-opts options)]
                      (icollect [_ [k v] (ipairs kv)]
                        (let [k (pp k options (+ indent 1) true)
                              v (pp v options (+ indent (slength k) 1))]
                          (set multiline?
                               (or multiline? (k:find "\n") (v:find "\n")))
                          (.. k " " v))))]
          (concat-table-lines items options multiline? indent :table prefix
                              false)))))

(fn pp-sequence [t kv options indent]
  (var multiline? false)
  (let [id (. options.seen t)]
    (if (<= options.depth options.level) "[...]"
        (and id (getopt options :detect-cycles?)) (.. "@" id "[...]")
        (let [visible-cycle? (visible-cycle? t options)
              id (and visible-cycle? (. options.seen t))
              indent (table-indent indent id)
              prefix (if visible-cycle? (.. "@" id) "")
              last-comment? (comment? (. t (length t)))
              items (let [options (normalize-opts options)]
                      (icollect [_ [_ v] (ipairs kv)]
                        (let [v (pp v options indent)]
                          (set multiline?
                               (or multiline? (v:find "\n") (v:find "^;")))
                          v)))]
          (concat-table-lines items options multiline? indent :seq prefix
                              last-comment?)))))

(fn concat-lines [lines options indent force-multi-line?]
  (if (= (length* lines) 0)
      (if (getopt options :empty-as-sequence?) "[]" "{}")
      (let [oneline (-> (icollect [_ line (ipairs lines)]
                          (line:gsub "^%s+" ""))
                        (table.concat " "))]
        (if (and (not (getopt options :one-line?))
                 (or force-multi-line? (oneline:find "\n")
                     (< options.line-length (+ indent (length* oneline)))))
            (table.concat lines (.. "\n" (string.rep " " indent)))
            oneline))))

(fn pp-metamethod [t metamethod options indent]
  (if (<= options.depth options.level)
      (if (getopt options :empty-as-sequence?) "[...]" "{...}")
      (let [_ (set options.visible-cycle? #(visible-cycle? $ options))
            (lines force-multi-line?)
            (let [options (normalize-opts options)]
              (metamethod t pp options indent))]
        (set options.visible-cycle? nil)
        ;; TODO: assuming that a string result is already a single line
        (match (type lines)
          :string lines
          :table (concat-lines lines options indent force-multi-line?)
          _ (error "__fennelview metamethod must return a table of lines")))))

(fn pp-table [x options indent]
  ;; Generic table pretty-printer.  Supports associative and
  ;; sequential tables, as well as tables, that contain __fennelview
  ;; metamethod.
  (set options.level (+ options.level 1))
  (let [x (match (if (getopt options :metamethod?) (-?> x getmetatable (. :__fennelview)))
            metamethod (pp-metamethod x metamethod options indent)
            _ (match (table-kv-pairs x options)
                (_ :empty) (if (getopt options :empty-as-sequence?) "[]" "{}")
                (kv :table) (pp-associative x kv options indent)
                (kv :seq) (pp-sequence x kv options indent)))]
    (set options.level (- options.level 1))
    x))

(fn number->string [n]
  ;; Transform number to a string without depending on correct `os.locale`
  (pick-values 1 (-> n
                     tostring
                     (string.gsub "," "."))))

(fn colon-string? [s]
  ;; Test if given string is valid colon string.
  (s:find "^[-%w?^_!$%&*+./|<=>]+$"))

(local utf8-inits
  [{:min-byte 0x00 :max-byte 0x7f
    :min-code 0x00 :max-code 0x7f
    :len 1}
   {:min-byte 0xc0 :max-byte 0xdf
    :min-code 0x80 :max-code 0x7ff
    :len 2}
   {:min-byte 0xe0 :max-byte 0xef
    :min-code 0x800 :max-code 0xffff
    :len 3}
   {:min-byte 0xf0 :max-byte 0xf7
    :min-code 0x10000 :max-code 0x10ffff
    :len 4}])

;; for control chars and UTF8 escaping, use to Lua's default decimal escape
(fn default-byte-escape [byte _options]
  (: "\\%03d" :format byte))

(fn utf8-escape [str options]
  ;; return nil if invalid utf8, if not return the length
  ;; TODO: use native utf8 library if possible
  (fn validate-utf8 [str index]
    (let [inits utf8-inits
          byte (string.byte str index)
          init (accumulate [ret nil
                            _ init (ipairs inits)
                            :until ret]
                 (and byte
                      (<= init.min-byte byte init.max-byte)
                      init))
          code (and init
                    (do
                      (var code (if init (- byte init.min-byte) nil))
                      (for [i (+ index 1) (+ index init.len -1)]
                        (let [byte (string.byte str i)]
                          (set code (and byte
                                         code
                                         (<= 0x80 byte 0xbf)
                                         (+ (* code 64) (- byte 0x80))))))
                      code))]
      (if (and code
               (<= init.min-code code init.max-code)
               ;; surrogate pairs disallowed
               (not (<= 0xd800 code 0xdfff)))
          init.len)))
  (var index 1)
  (let [output []
        byte-escape (or (getopt options :byte-escape) default-byte-escape)]
    (while (<= index (length str))
      (let [nexti (or (string.find str "[\128-\255]" index) (+ (length str) 1))
            len (validate-utf8 str nexti)]
        (table.insert output (string.sub str index (+ nexti (or len 0) -1)))
        (when (and (not len) (<= nexti (length str)))
          (table.insert output (byte-escape (str:byte nexti) options)))
        (set index (if len (+ nexti len) (+ nexti 1)))))
    (table.concat output)))

(fn pp-string [str options indent]
  "This is a more complicated version of string.format %q.
However, we can't use that functionality because it always emits control codes
as numeric escapes rather than letter-based escapes, which is ugly."
  (let [len (length* str)
        esc-newline? (or (< len 2) (and (getopt options :escape-newlines?)
                                        (< len (- options.line-length indent))))
        byte-escape (or (getopt options :byte-escape) default-byte-escape)
        escs (setmetatable {"\a" "\\a"
                            "\b" "\\b"
                            "\f" "\\f"
                            "\v" "\\v"
                            "\r" "\\r"
                            "\t" "\\t"
                            :\ "\\\\"
                            "\"" "\\\""
                            "\n" (if esc-newline? "\\n" "\n")}
                           {:__index #(byte-escape ($2:byte) options)})
        str (.. "\"" (str:gsub "[%c\\\"]" escs) "\"")]
    (if (getopt options :utf8?)
        (utf8-escape str options)
        str)))

(fn make-options [t options]
  (let [;; defaults are used when options are not provided
        defaults (collect [k v (pairs default-opts)]
                   (values k v))
        ;; overrides can't be accessed via options
        overrides {:level 0
                   :appearances (count-table-appearances t {})
                   :seen {:len 0}}]
    (each [k v (pairs (or options {}))]
      (tset defaults k v))
    (each [k v (pairs overrides)]
      (tset defaults k v))
    defaults))

(set pp (fn [x options indent colon?]
          ;; main serialization loop, entry point is defined below
          (let [indent (or indent 0)
                options (or options (make-options x))
                x (if options.preprocess (options.preprocess x options) x)
                tv (type x)]
            (if (or (= tv :table)
                    (and (= tv :userdata)
                         ;; ensure x is a table, not just non-nil to prevent
                         ;; {:__metatable true} edge case seen in e.g. pandoc-lua
                         (case (getmetatable x) {: __fennelview} __fennelview)))
                (pp-table x options indent)
                (= tv :number)
                (number->string x)
                (and (= tv :string) (colon-string? x)
                     (if (not= colon? nil) colon?
                         (= :function (type options.prefer-colon?)) (options.prefer-colon? x)
                         (getopt options :prefer-colon?)))
                (.. ":" x)
                (= tv :string)
                (pp-string x options indent)
                (or (= tv :boolean) (= tv :nil))
                (tostring x)
                (.. "#<" (tostring x) ">")))))

(fn view [x ?options]
  "Return a string representation of x.

Can take an options table with these keys:
* :one-line? (default: false) keep the output string as a one-liner
* :depth (number, default: 128) limit how many levels to go (default: 128)
* :detect-cycles? (default: true) don't try to traverse a looping table
* :metamethod? (default: true) use the __fennelview metamethod if found
* :empty-as-sequence? (default: false) render empty tables as []
* :line-length (number, default: 80) length of the line at which
  multi-line output for tables is forced
* :escape-newlines? (default: false) emit strings with \\n instead of newline
* :prefer-colon? (default: false) emit strings in colon notation when possible
* :utf8? (default: true) whether to use utf8 module to compute string lengths
* :max-sparse-gap (integer, default 10) maximum gap to fill in with nils in
  sparse sequential tables.
* :preprocess (function) if present, called on x (and recursively on each value
  in x), and the result is used for pretty printing; takes the same arguments as
  `fennel.view`

All options can be set to `{:once some-value}` to force their value to be
`some-value` but only for the current level. After that, such option is reset
to its default value.  Alternatively, `{:once value :after other-value}` can
be used, with the difference that after first use, the options will be set to
`other-value` instead of the default value.

You can set a `__fennelview` metamethod on a table to override its serialization
behavior; see the API reference for details."
  (pp x (make-options x ?options) 0))
