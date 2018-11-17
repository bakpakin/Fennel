;; A pretty-printer that outputs tables in Fennel syntax.
;; Loosely based on inspect.lua: http://github.com/kikito/inspect.lua

(local quote (fn [str] (.. '"' (: str :gsub '"' '\\"') '"')))

(local short-control-char-escapes
       {"\a" "\\a" "\b" "\\b" "\f" "\\f" "\n" "\\n"
        "\r" "\\r" "\t" "\\t" "\v" "\\v"})

(local long-control-char-esapes
       (let [long {}]
         (for [i 0 31]
           (let [ch (string.char i)]
             (when (not (. short-control-char-escapes ch))
               (tset short-control-char-escapes ch (.. "\\" i))
               (tset long ch (: "\\%03d" :format i)))))
         long))

(fn escape [str]
  (let [str (: str :gsub "\\" "\\\\")
        str (: str :gsub "(%c)%f[0-9]" long-control-char-esapes)]
    (: str :gsub "%c" short-control-char-escapes)))

(fn sequence-key? [k len]
  (and (= (type k) "number")
       (<= 1 k)
       (<= k len)
       (= (math.floor k) k)))

(local type-order {:number 1 :boolean 2 :string 3 :table 4
                   :function 5 :userdata 6 :thread 7})

(fn sort-keys [a b]
  (let [ta (type a) tb (type b)]
    (if (and (= ta tb) (~= ta "boolean")
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

(fn already-visited? [self v] (~= (. self.ids v) nil))

(fn get-id [self v]
  (var id (. self.ids v))
  (when (not id)
    (let [tv (type v)]
      (set id (+ (or (. self.max-ids tv) 0) 1))
      (tset self.max-ids tv id)
      (tset self.ids v id)))
  (tostring id))

(fn put-sequential-table [self t length]
  (puts self "[")
  (set self.level (+ self.level 1))
  (for [i 1 length]
    (puts self " ")
    (put-value self (. t i)))
  (set self.level (- self.level 1))
  (puts self " ]"))

(fn put-key [self k]
  (if (and (= (type k) "string")
           (: k :find "^[-%w?\\^_`!#$%&*+./@~:|<=>]+$"))
      (puts self ":" k)
      (put-value self k)))

(fn put-kv-table [self t]
  (puts self "{")
  (set self.level (+ self.level 1))
  (each [k v (pairs t)]
    (tabify self)
    (put-key self k)
    (puts self " ")
    (put-value self v))
  (set self.level (- self.level 1))
  (tabify self)
  (puts self "}"))

(fn put-table [self t]
  (if (already-visited? self t)
      (puts self "#<table " (get-id self t) ">")
      (>= self.level self.depth)
      (puts self "{...}")
      :else
      (let [(non-seq-keys length) (get-nonsequential-keys t)
            id (get-id self t)]
        (if (> (. self.appearances t) 1)
            (puts self "#<" id ">")
            (and (= (# non-seq-keys) 0) (= (# t) 0))
            (puts self "{}")
            (= (# non-seq-keys) 0)
            (put-sequential-table self t length)
            :else
            (put-kv-table self t)))))

(set put-value (fn [self v]
                 (let [tv (type v)]
                   (if (= tv "string")
                       (puts self (quote (escape v)))
                       (or (= tv "number") (= tv "boolean") (= tv "nil"))
                       (puts self (tostring v))
                       (= tv "table")
                       (put-table self v)
                       :else
                       (puts self "#<" (tostring v) ">")))))



(fn fennelview [root options]
  (let [options (or options {})
        inspector {:appearances (count-table-appearances root {})
                   :depth (or options.depth 128)
                   :level 0 :buffer {} :ids {} :max-ids {}
                   :indent (or options.indent "  ")}]
    (put-value inspector root)
    (table.concat inspector.buffer)))
