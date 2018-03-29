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

(local escape (fn [str]
                (let [str (: str :gsub "\\" "\\\\")
                      str (: str :gsub "(%c)%f[0-9]" long-control-char-esapes)]
                  (: str :gsub "%c" short-control-char-escapes))))

(local sequence-key? (fn [k len]
                       (and (= (type k) "number")
                            (<= 1 k)
                            (<= k len)
                            (= (math.floor k) k))))

(local type-order {:number 1 :boolean 2 :string 3 :table 4
                   :function 5 :userdata 6 :thread 7})

(local sort-keys (fn [a b]
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
                               :else (< ta tb)))))))

(local get-sequence-length
       (fn [t]
         (var len 1)
         (each [i (ipairs t)] (set len i))
         len))

(local get-nonsequential-keys
       (fn [t]
         (let [keys {}
               sequence-length (get-sequence-length t)]
           (each [k (pairs t)]
             (when (not (sequence-key? k sequence-length))
               (table.insert keys k)))
           (table.sort keys sort-keys)
           (values keys sequence-length))))

(local count-table-appearances
       (fn recur [t appearances]
         (if (= (type t) "table")
             (when (not (. appearances t))
               (tset appearances t 1)
               (each [k v (pairs t)]
                 (recur k appearances)
                 (recur v appearances)))
             (when (and t (= t t)) ; no nans please
               (tset appearances t (+ (or (. appearances t) 0) 1))))
         appearances))



(var put-value nil) ; mutual recursion going on; defined below

(local puts (fn [self ...]
              (each [_ v (ipairs [...])]
                (table.insert self.buffer v))))

(local tabify (fn [self] (puts self "\n" (: self.indent :rep self.level))))

(local already-visited? (fn [self v] (~= (. self.ids v) nil)))

(local get-id (fn [self v]
                (var id (. self.ids v))
                (when (not id)
                  (let [tv (type v)]
                    (set id (+ (or (. self.max-ids tv) 0) 1))
                    (tset self.max-ids tv id)
                    (tset self.ids v id)))
                (tostring id)))

(local put-sequential-table (fn [self t length]
                              (puts self "[")
                              (set self.level (+ self.level 1))
                              (for [i 1 length]
                                (puts self " ")
                                (put-value self (. t i)))
                              (set self.level (- self.level 1))
                              (puts self " ]")))

(local put-key (fn [self k]
                 (if (and (= (type k) "string") (not (: k :find "%W")))
                     (puts self ":" k)
                     (put-value self k))))

(local put-kv-table (fn [self t]
                      (puts self "{")
                      (set self.level (+ self.level 1))
                      (each [k v (pairs t)]
                        (tabify self)
                        (put-key self k)
                        (puts self " ")
                        (put-value self v))
                      (set self.level (- self.level 1))
                      (tabify self)
                      (puts self "}")))

(local put-table (fn [self t]
                   (if (already-visited? self t)
                       (puts self "#<table " (get-id self t) ">")
                       (>= self.level self.depth)
                       (puts self "{...}")
                       :else
                       (let [(non-seq-keys length) (get-nonsequential-keys t)
                             id (get-id self t)]
                         (if (> (. self.appearances t) 1)
                             (puts self "#<" id ">")
                             (= (# non-seq-keys) 0)
                             (put-sequential-table self t length)
                             :else
                             (put-kv-table self t))))))

(set put-value (fn [self v]
                 (let [tv (type v)]
                   (if (= tv "string")
                       (puts self (quote (escape v)))
                       (or (= tv "number") (= tv "boolean") (= tv "nil"))
                       (puts self (tostring v))
                       (= tv "table")
                       (put-table self v)
                       :else
                       (puts self "#<" tv " " (get-id self v) ">")))))



(fn [root options]
  (let [options (or options {})
        inspector {:appearances (count-table-appearances root {})
                   :depth (or options.depth 128)
                   :level 0 :buffer {} :ids {} :max-ids {}
                   :indent (or options.indent "  ")}]
    (put-value inspector root)
    (table.concat inspector.buffer)))
