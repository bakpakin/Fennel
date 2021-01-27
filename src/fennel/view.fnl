;; A pretty-printer that outputs tables in Fennel syntax.

(local type-order {:number 1 :boolean 2 :string 3 :table 4
                   :function 5 :userdata 6 :thread 7})

(fn sort-keys [[a] [b]]
  ;; Sort keys depending on the `type-order`.
  (let [ta (type a) tb (type b)]
    (if (and (= ta tb)
             (or (= ta "string") (= ta "number")))
        (< a b)
        (let [dta (. type-order ta)
              dtb (. type-order tb)]
          (if (and dta dtb) (< dta dtb)
              dta true
              dtb false
              (< ta tb))))))

(fn table-kv-pairs [t]
  ;; Return table of tables with first element representing key and second
  ;; element representing value.  Second value indicates table type, which is
  ;; either sequential or associative.

  ;; [:a :b :c] => [[1 :a] [2 :b] [3 :c]]
  ;; {:a 1 :b 2} => [[:a 1] [:b 2]]
  (var assoc? false)
  (var i 1)
  (let [kv []
        insert table.insert]
    (each [k v (pairs t)]
      (when (or (not= (type k) :number)
                (not= k i))
        (set assoc? true))
      (set i (+ i 1))
      (insert kv [k v]))
    (table.sort kv sort-keys)
    (if (= (length kv) 0)
        (values kv :empty)
        (values kv (if assoc? :table :seq)))))

(fn count-table-appearances [t appearances]
  (when (= (type t) :table)
    (if (not (. appearances t))
        (do (tset appearances t 1)
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
  ;; Return `true` if table `t` appears in itself.
  (let [seen (or seen {})]
    (tset seen t true)
    (each [k v (pairs t)]
      (when (and (= (type k) :table)
                 (or (. seen k) (detect-cycle k seen)))
        (lua "return true"))
      (when (and (= (type v) :table)
                 (or (. seen v) (detect-cycle v seen)))
        (lua "return true")))))

(fn visible-cycle? [t options]
  ;; Detect cycle, save table's ID in seen tables, and determine if
  ;; cycle is visible.  Exposed via options table to use in
  ;; __fennelview metamethod implementations
  (and options.detect-cycles?
       (detect-cycle t)
       (save-table t options.seen)
       (< 1 (or (. options.appearances t) 0))))

(fn table-indent [t indent id]
  ;; When table contains cycles, it is printed with a prefix before opening
  ;; delimiter.  Prefix has a variable length, as it contains `id` of the table
  ;; and fixed part of `2` characters `@` and either `[` or `{` depending on
  ;; `t`type.  If `t` has visible cycles, we need to increase indent by the size
  ;; of the prefix.
  (let [opener-length (if id
                          (+ (length (tostring id)) 2)
                          1)]
    (+ indent opener-length)))

(local pp {})

(fn concat-table-lines
  [elements options multiline? indent table-type prefix]
  (let [indent-str (.. "\n" (string.rep " " indent))
        open (.. (or prefix "") (if (= :seq table-type) "[" "{"))
        close (if (= :seq table-type) "]" "}")
        oneline (.. open (table.concat elements " ") close)]
    (if (and (not options.one-line?)
             (or multiline?
                 (> (+ indent (length oneline)) options.line-length)))
        (.. open (table.concat elements indent-str) close)
        oneline)))

(fn pp-associative [t kv options indent key?]
  (var multiline? false)
  (let [id (. options.seen t)]
    (if (>= options.level options.depth) "{...}"
        (and id options.detect-cycles?) (.. "@" id "{...}")
        (let [visible-cycle? (visible-cycle? t options)
              id (and visible-cycle? (. options.seen t))
              indent (table-indent t indent id)
              slength (or (and options.utf8? (-?> (rawget _G :utf8) (. :len)))
                          #(length $))
              prefix (if visible-cycle? (.. "@" id) "")
              elements (icollect [_ [k v] (pairs kv)]
                         (let [k (pp.pp k options (+ indent 1) true)
                               v (pp.pp v options (+ indent (slength k) 1))]
                           (set multiline? (or multiline? (k:find "\n") (v:find "\n")))
                           (.. k " " v)))]
          (concat-table-lines
           elements options multiline? indent :table prefix)))))

(fn pp-sequence [t kv options indent]
  (var multiline? false)
  (let [id (. options.seen t)]
    (if (>= options.level options.depth) "[...]"
        (and id options.detect-cycles?) (.. "@" id "[...]")
        (let [visible-cycle? (visible-cycle? t options)
              id (and visible-cycle? (. options.seen t))
              indent (table-indent t indent id)
              prefix (if visible-cycle? (.. "@" id) "")
              elements (icollect [_ [_ v] (pairs kv)]
                         (let [v (pp.pp v options indent)]
                           (set multiline? (or multiline? (v:find "\n")))
                           v))]
          (concat-table-lines
           elements options multiline? indent :seq prefix)))))

(fn concat-lines [lines options indent force-multi-line?]
  (if (= (length lines) 0)
      (if options.empty-as-sequence? "[]" "{}")
      (let [oneline (-> (icollect [_ line (ipairs lines)]
                          (line:gsub "^%s+" ""))
                        (table.concat " "))]
        (if (and (not options.one-line?)
                 (or force-multi-line?
                     (oneline:find "\n")
                     (> (+ indent (length oneline)) options.line-length)))
            (table.concat lines (.. "\n" (string.rep " " indent)))
            oneline))))

(fn pp-metamethod [t metamethod options indent]
  (if (>= options.level options.depth)
      (if options.empty-as-sequence? "[...]" "{...}")
      (let [_ (set options.visible-cycle? #(visible-cycle? $ options))
            (lines force-multi-line?) (metamethod t pp.pp options indent)]
        (set options.visible-cycle? nil)
        (match (type lines)
          :string lines ;; TODO: assuming that result is already a single line. Maybe warn?
          :table  (concat-lines lines options indent force-multi-line?)
          _ (error "Error: __fennelview metamethod must return a table of lines")))))

(fn pp-table [x options indent]
  ;; Generic table pretty-printer.  Supports associative and
  ;; sequential tables, as well as tables, that contain __fennelview
  ;; metamethod.
  (set options.level (+ options.level 1))
  (let [x (match (if options.metamethod? (-?> x getmetatable (. :__fennelview)))
            metamethod (pp-metamethod x metamethod options indent)
            _ (match (table-kv-pairs x)
                (_ :empty) (if options.empty-as-sequence? "[]" "{}")
                (kv :table) (pp-associative x kv options indent)
                (kv :seq) (pp-sequence x kv options indent)))]
    (set options.level (- options.level 1))
    x))



(fn number->string [n]
  ;; Transform number to a string without depending on correct `os.locale`
  (pick-values 1
    (-> n
        tostring
        (string.gsub "," "."))))

(fn colon-string? [s]
  ;; Test if given string is valid colon string.
  (s:find "^[-%w?\\^_!$%&*+./@:|<=>]+$"))



(fn make-options [t options]
  (let [;; defaults are used when options are not provided
        defaults {:line-length 80
                  :one-line? false
                  :depth 128
                  :detect-cycles? true
                  :empty-as-sequence? false
                  :metamethod? true
                  :utf8? true}
        ;; overrides can't be accessed via options
        overrides {:level 0
                   :appearances (count-table-appearances t {})
                   :seen {:len 0}}]
    (each [k v (pairs (or options {}))]
      (tset defaults k v))
    (each [k v (pairs overrides)]
      (tset defaults k v))
    defaults))

(fn pp.pp [x options indent key?]
  ;; main serialization loop, entry point is defined below
  (let [indent (or indent 0)
        options (or options (make-options x))
        tv (type x)]
    (if (or (= tv :table)
            (and (= tv :userdata)
                 (-?> (getmetatable x) (. :__fennelview))))
        (pp-table x options indent)
        (= tv :number)
        (number->string x)
        (and (= tv :string) key? (colon-string? x))
        (.. ":" x)
        (= tv :string)
        (string.format "%q" x)
        (or (= tv :boolean) (= tv :nil))
        (tostring x)
        (.. "#<" (tostring x) ">"))))

(fn view [x options]
  "Return a string representation of x.

Can take an options table with these keys:
* :one-line? (boolean: default: false) keep the output string as a one-liner
* :depth (number, default: 128) limit how many levels to go (default: 128)
* :detect-cycles? (boolean, default: true) don't try to traverse a looping table
* :metamethod? (boolean: default: true) use the __fennelview metamethod if found
* :empty-as-sequence? (boolean, default: false) render empty tables as []
* :line-length (number, default: 80) length of the line at which
  multi-line output for tables is forced
* :utf8? (boolean, default true) whether to use utf8 module to compute string
  lengths

The `__fennelview` metamethod should take the table being serialized as its
first argument, a function as its second argument, options table as third
argument, and current amount of indentation as its last argument:

(fn [t view inspector indent] ...)

`view` function contains pretty printer, that can be used to serialize elements
stored within the table being serialized.  If your metamethod produces indented
representation, you should pass `indent` parameter to `view` increased by the
amount of addition indentation you've introduced.

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

Note that even though we've only indented inner elements of our table with 10
spaces, the result is correctly indented in terms of outer table, and inner
tables also remain indented correctly."
  (pp.pp x (make-options x options) 0))
