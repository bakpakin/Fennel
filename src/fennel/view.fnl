;; A pretty-printer that outputs tables in Fennel syntax.

(local type-order {:number 1
                   :boolean 2
                   :string 3
                   :table 4
                   :function 5
                   :userdata 6
                   :thread 7})

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

(fn detect-cycle [t seen ?k]
  "Return `true` if table `t` appears in itself."
  (when (= :table (type t))
    (tset seen t true)
    (match (next t ?k)
      (k v) (or (. seen k) (detect-cycle k seen) (. seen v)
                (detect-cycle v seen) (detect-cycle t seen k)))))

(fn visible-cycle? [t options]
  ;; Detect cycle, save table's ID in seen tables, and determine if
  ;; cycle is visible.  Exposed via options table to use in
  ;; __fennelview metamethod implementations
  (and options.detect-cycles? (detect-cycle t {}) (save-table t options.seen)
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
    (if (and (not options.one-line?)
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
        (and id options.detect-cycles?) (.. "@" id "{...}")
        (let [visible-cycle? (visible-cycle? t options)
              id (and visible-cycle? (. options.seen t))
              indent (table-indent indent id)
              slength (if options.utf8? utf8-len #(length $))
              prefix (if visible-cycle? (.. "@" id) "")
              items (icollect [_ [k v] (ipairs kv)]
                      (let [k (pp k options (+ indent 1) true)
                            v (pp v options (+ indent (slength k) 1))]
                        (set multiline?
                             (or multiline? (k:find "\n") (v:find "\n")))
                        (.. k " " v)))]
          (concat-table-lines items options multiline? indent :table prefix
                              false)))))

(fn pp-sequence [t kv options indent]
  (var multiline? false)
  (let [id (. options.seen t)]
    (if (<= options.depth options.level) "[...]"
        (and id options.detect-cycles?) (.. "@" id "[...]")
        (let [visible-cycle? (visible-cycle? t options)
              id (and visible-cycle? (. options.seen t))
              indent (table-indent indent id)
              prefix (if visible-cycle? (.. "@" id) "")
              last-comment? (comment? (. t (length t)))
              items (icollect [_ [_ v] (ipairs kv)]
                      (let [v (pp v options indent)]
                        (set multiline?
                             (or multiline? (v:find "\n") (v:find "^;")))
                        v))]
          (concat-table-lines items options multiline? indent :seq prefix
                              last-comment?)))))

(fn concat-lines [lines options indent force-multi-line?]
  (if (= (length* lines) 0)
      (if options.empty-as-sequence? "[]" "{}")
      (let [oneline (-> (icollect [_ line (ipairs lines)]
                          (line:gsub "^%s+" ""))
                        (table.concat " "))]
        (if (and (not options.one-line?)
                 (or force-multi-line? (oneline:find "\n")
                     (< options.line-length (+ indent (length* oneline)))))
            (table.concat lines (.. "\n" (string.rep " " indent)))
            oneline))))

(fn pp-metamethod [t metamethod options indent]
  (if (<= options.depth options.level)
      (if options.empty-as-sequence? "[...]" "{...}")
      (let [_ (set options.visible-cycle? #(visible-cycle? $ options))
            (lines force-multi-line?) (metamethod t pp options indent)]
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
  (let [x (match (if options.metamethod? (-?> x getmetatable (. :__fennelview)))
            metamethod (pp-metamethod x metamethod options indent)
            _ (match (table-kv-pairs x options)
                (_ :empty) (if options.empty-as-sequence? "[]" "{}")
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
  (s:find "^[-%w?^_!$%&*+./@|<=>]+$"))

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

(fn utf8-escape [str]
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
  (let [output []]
    (while (<= index (length str))
      (let [nexti (or (string.find str "[\128-\255]" index) (+ (length str) 1))
            len (validate-utf8 str nexti)]
        (table.insert output (string.sub str index (+ nexti (or len 0) -1)))
        (when (and (not len) (<= nexti (length str)))
          (table.insert output (string.format "\\%03d" (string.byte str nexti))))
        (set index (if len (+ nexti len) (+ nexti 1)))))
    (table.concat output)))

(fn pp-string [str options indent]
  "This is a more complicated version of string.format %q.
However, we can't use that functionality because it always emits control codes
as numeric escapes rather than letter-based escapes, which is ugly."
  (let [escs (setmetatable {"\a" "\\a"
                            "\b" "\\b"
                            "\f" "\\f"
                            "\v" "\\v"
                            "\r" "\\r"
                            "\t" "\\t"
                            :\ "\\\\"
                            "\"" "\\\""
                            "\n" (if (and options.escape-newlines?
                                          (< (length* str)
                                             (- options.line-length indent)))
                                     "\\n" "\n")}
                           {:__index #(: "\\%03d" :format ($2:byte))})
        str (.. "\"" (str:gsub "[%c\\\"]" escs) "\"")]
    (if options.utf8?
        (utf8-escape str)
        str)))

(fn make-options [t options]
  (let [;; defaults are used when options are not provided
        defaults {:line-length 80
                  :one-line? false
                  :depth 128
                  :detect-cycles? true
                  :empty-as-sequence? false
                  :metamethod? true
                  :prefer-colon? false
                  :escape-newlines? false
                  :utf8? true
                  :max-sparse-gap 10}
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
                         (-?> (getmetatable x) (. :__fennelview))))
                (pp-table x options indent)
                (= tv :number)
                (number->string x)
                (and (= tv :string) (colon-string? x)
                     (if (not= colon? nil) colon?
                         (= :function (type options.prefer-colon?)) (options.prefer-colon? x)
                         options.prefer-colon?))
                (.. ":" x)
                (= tv :string)
                (pp-string x options indent)
                (or (= tv :boolean) (= tv :nil))
                (tostring x)
                (.. "#<" (tostring x) ">")))))

(fn view [x ?options]
  "Return a string representation of x.

Can take an options table with these keys:
* :one-line? (boolean: default: false) keep the output string as a one-liner
* :depth (number, default: 128) limit how many levels to go (default: 128)
* :detect-cycles? (boolean, default: true) don't try to traverse a looping table
* :metamethod? (boolean: default: true) use the __fennelview metamethod if found
* :empty-as-sequence? (boolean, default: false) render empty tables as []
* :line-length (number, default: 80) length of the line at which
  multi-line output for tables is forced
* :escape-newlines? (default: false) emit strings with \\n instead of newline
* :prefer-colon? (default: false) emit strings in colon notation when possible
* :utf8? (boolean, default true) whether to use utf8 module to compute string
  lengths
* :max-sparse-gap (integer, default 10) maximum gap to fill in with nils in
  sparse sequential tables.
* :preprocess (function) if present, called on x (and recursively on each value
  in x), and the result is used for pretty printing; takes the same arguments as
  `fennel.view`

The `__fennelview` metamethod should take the table being serialized as its
first argument, a function as its second argument, options table as third
argument, and current amount of indentation as its last argument:

(fn [t view inspector indent] ...)

`view` function contains a pretty printer, that can be used to serialize
elements stored within the table being serialized.  If your metamethod produces
indented representation, you should pass `indent` parameter to `view` increased
by the amount of additional indentation you've introduced.  This function has
the same interface as `__fennelview` metamethod, but in addition accepts
`colon-string?` as last argument. If `colon?` is `true`, strings will be printed
as colon-strings when possible, and if its value is `false`, strings will be
always printed in double quotes. If omitted or `nil` will default to value of
`:prefer-colon?` option.

`inspector` table contains options described above, and also `visible-cycle?`
function, that takes a table being serialized, detects and saves information
about possible reachable cycle.  Should be used in `__fennelview` to implement
cycle detection.

`__fennelview` metamethod should always return a table of correctly indented
lines when producing multi-line output, or a string when always returning
single-line item.  `fennel.view` will transform your data structure to correct
multi-line representation when needed.  There's no need to concatenate table
manually ever - `fennel.view` will apply general rules for your data structure,
depending on current options.  By default multiline output is produced only when
inner data structures contains newlines, or when returning table of lines as
single line results in width greater than `line-size` option.

Multi-line representation can be forced by returning two values from
`__fennelview` - a table of indented lines as first value, and `true` as second
value, indicating that multi-line representation should be forced.

There's no need to incorporate indentation beyond needed to correctly align
elements within the printed representation of your data structure.  For example,
if you want to print a multi-line table, like this:

@my-table[1
          2
          3]

`__fennelview` should return a sequence of lines:

[\"@my-table[1\"
 \"          2\"
 \"          3]\"]

Note, since we've introduced inner indent string of length 10, when calling
`view` function from within `__fennelview` metamethod, in order to keep inner
tables indented correctly, `indent` must be increased by this amount of extra
indentation.

`view` function also accepts additional boolean argument, which controls if
strings should be printed as a colon-strings when possible.  Set it to `true`
when `view` is being called on the key of a table.

Here's an implementation of such pretty-printer for an arbitrary sequential
table:

(fn pp-doc-example [t view inspector indent]
  (let [lines (icollect [i v (ipairs t)]
                (let [v (view v inspector (+ 10 indent))]
                  (if (= i 1) v
                      (.. \"          \" v))))]
    (doto lines
      (tset 1 (.. \"@my-table[\" (or (. lines 1) \"\")))
      (tset (length lines) (.. (. lines (length lines)) \"]\")))))

Setting table's `__fennelview` metamethod to this function will provide correct
results regardless of nesting:

>> {:my-table (setmetatable [[1 2 3 4 5]
                             {:smalls [6 7 8 9 10 11 12]
                              :bigs [500 1000 2000 3000 4000]}]
                            {:__fennelview pp-doc-example})
    :normal-table [{:c [1 2 3] :d :some-data} 4]}
{:my-table @my-table[[1 2 3 4 5]
                     {:bigs [500 1000 2000 3000 4000]
                      :smalls [6 7 8 9 10 11 12]}]
 :normal-table [{:c [1 2 3] :d \"some-data\"} 4]}

Note that even though we've only indented inner elements of our table
with 10 spaces, the result is correctly indented in terms of outer
table, and inner tables also remain indented correctly.

When using the `:preprocess` option, avoid modifying any tables in-place in the
passed function. Since Lua tables are mutable and provided to `:preprocess`
without copying, any modification done in `:preprocess` will be visible outside
of `fennel.view`."
  (pp x (make-options x ?options) 0))
