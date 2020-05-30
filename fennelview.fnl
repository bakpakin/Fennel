;; A pretty-printer that outputs tables in Fennel syntax.
;; Loosely based on inspect.lua: http://github.com/kikito/inspect.lua

(fn view-quote [str] (.. "\"" (: str :gsub "\"" "\\\"") "\""))

(local short-control-char-escapes
       {"\a" "\\a" "\b" "\\b" "\f" "\\f" "\n" "\\n"
        "\r" "\\r" "\t" "\\t" "\v" "\\v"})

(local long-control-char-escapes
       (let [long {}]
         (for [i 0 31]
           (let [ch (string.char i)]
             (when (not (. short-control-char-escapes ch))
               (tset short-control-char-escapes ch (.. "\\" i))
               (tset long ch (: "\\%03d" :format i)))))
         long))

(fn escape [str]
  (-> str
      (: :gsub "\\" "\\\\")
      (: :gsub "(%c)%f[0-9]" long-control-char-escapes)
      (: :gsub "%c" short-control-char-escapes)))

(fn sequence-key? [k len]
  (and (= (type k) "number")
       (<= 1 k)
       (<= k len)
       (= (math.floor k) k)))

(local type-order {:number 1 :boolean 2 :string 3 :table 4
                   :function 5 :userdata 6 :thread 7})

(fn sort-keys [a b]
  (let [ta (type a) tb (type b)]
    (if (and (= ta tb) (not= ta "boolean")
             (or (= ta "string") (= ta "number")))
        (< a b)
        (let [dta (. type-order a)
              dtb (. type-order b)]
          (if (and dta dtb)
              (< dta dtb)
              dta true
              dtb false
              :else (< ta tb))))))

(fn get-sequence-length [t]
  (var len 1)
  (each [i (ipairs t)] (set len i))
  len)

(fn get-nonsequential-keys [t]
  (let [keys {}
        sequence-length (get-sequence-length t)]
    (each [k (pairs t)]
      (when (not (sequence-key? k sequence-length))
        (table.insert keys k)))
    (table.sort keys sort-keys)
    (values keys sequence-length)))

(fn count-table-appearances [t appearances]
  (if (= (type t) "table")
      (when (not (. appearances t))
        (tset appearances t 1)
        (each [k v (pairs t)]
          (count-table-appearances k appearances)
          (count-table-appearances v appearances)))
      (when (and t (= t t)) ; no nans please
        (tset appearances t (+ (or (. appearances t) 0) 1))))
  appearances)



(var put-value nil) ; mutual recursion going on; defined below

(fn puts [self ...]
  (each [_ v (ipairs [...])]
    (table.insert self.buffer v)))

(fn tabify [self] (puts self "\n" (: self.indent :rep self.level)))

(fn already-visited? [self v] (not= (. self.ids v) nil))

(fn get-id [self v]
  (var id (. self.ids v))
  (when (not id)
    (let [tv (type v)]
      (set id (+ (or (. self.max-ids tv) 0) 1))
      (tset self.max-ids tv id)
      (tset self.ids v id)))
  (tostring id))

(fn put-sequential-table [self t len]
  (puts self "[")
  (set self.level (+ self.level 1))
  (for [i 1 len]
    (when (< 1 i (+ 1 len))
      (puts self " "))
    (put-value self (. t i)))
  (set self.level (- self.level 1))
  (puts self "]"))

(fn put-key [self k]
  (if (and (= (type k) "string")
           (: k :find "^[-%w?\\^_!$%&*+./@:|<=>]+$"))
      (puts self ":" k)
      (put-value self k)))

(fn put-kv-table [self t ordered-keys]
  (puts self "{")
  (set self.level (+ self.level 1))
  ;; first, output sorted nonsequential keys
  (each [_ k (ipairs ordered-keys)]
    (tabify self)
    (put-key self k)
    (puts self " ")
    (put-value self (. t k)))
  ;; next, output any sequential keys
  (each [i v (ipairs t)]
    (tabify self)
    (put-key self i)
    (puts self " ")
    (put-value self v))
  (set self.level (- self.level 1))
  (tabify self)
  (puts self "}"))

(fn put-table [self t]
  (let [metamethod (and self.metamethod? (-?> t getmetatable (. :__fennelview)))]
    (if (and (already-visited? self t) self.detect-cycles?)
        (puts self "#<table " (get-id self t) ">")
        (>= self.level self.depth)
        (puts self "{...}")
        metamethod
        (puts self (metamethod t self.fennelview))
        :else
        (let [(non-seq-keys len) (get-nonsequential-keys t)
              id (get-id self t)]
          ;; fancy metatable stuff can result in self.appearances not including
          ;; a table, so if it's not found, assume we haven't seen it; we can't
          ;; do cycle detection in that case.
          (if (and (< 1 (or (. self.appearances t) 0)) self.detect-cycles?)
              (puts self "#<table" id ">")
              (and (= (length non-seq-keys) 0) (= (length t) 0))
              (puts self "{}")
              (= (length non-seq-keys) 0)
              (put-sequential-table self t len)
              :else
              (put-kv-table self t non-seq-keys))))))

(set put-value (fn [self v]
                 (let [tv (type v)]
                   (if (= tv "string")
                       (puts self (view-quote (escape v)))
                       (or (= tv "number") (= tv "boolean") (= tv "nil"))
                       (puts self (tostring v))
                       (= tv "table")
                       (put-table self v)
                       :else
                       (puts self "#<" (tostring v) ">")))))



(fn one-line [str]
  ;; save return value as local to ignore gsub's extra return value
  (let [ret (-> str
                (: :gsub "\n" " ")
                (: :gsub "%[ " "[") (: :gsub " %]" "]")
                (: :gsub "%{ " "{") (: :gsub " %}" "}")
                (: :gsub "%( " "(") (: :gsub " %)" ")"))]
    ret))

(fn fennelview [x options]
  "Return a string representation of x.

Can take an options table with these keys:
* :one-line (boolean: default: false) keep the output string as a one-liner
* :depth (number, default: 128) limit how many levels to go (default: 128)
* :indent (string, default: \"  \") use this string to indent each level
* :detect-cycles? (boolean, default: true) don't try to traverse a looping table
* :metamethod? (boolean: default: true) use the __fennelview metamethod if found

The __fennelview metamethod should take the table being serialized as its first
argument and a function as its second arg which can be used on table elements to
continue the fennelview process on them.
"
  (let [options (or options {})
        inspector {:appearances (count-table-appearances x {})
                   :depth (or options.depth 128)
                   :level 0 :buffer {} :ids {} :max-ids {}
                   :indent (or options.indent (if options.one-line "" "  "))
                   :detect-cycles? (not (= false options.detect-cycles?))
                   :metamethod? (not (= false options.metamethod?))
                   :fennelview #(fennelview $1 options)}]
    (put-value inspector x)
    (let [str (table.concat inspector.buffer)]
      (if options.one-line (one-line str) str))))
