;; This module is responsible for turning bytes of source code into an AST
;; data structure.

(local {: unpack &as utils} (require :fennel.utils))
(local friend (require :fennel.friend))

(fn granulate [getchunk]
  "Convert a stream of chunks to a stream of bytes.
Also returns a second function to clear the buffer in the byte stream."
  (var (c index done?) (values "" 1 false))
  (values (fn [parser-state]
            (when (not done?)
              (if (<= index (length c))
                  (let [b (c:byte index)]
                    (set index (+ index 1))
                    b)
                  (case (getchunk parser-state)
                    input (do (set (c index) (values input 2))
                              (c:byte))
                    _ (set done? true)))))
          #(set c "")))

(fn string-stream [str ?options]
  "Convert a string into a stream of bytes."
  (let [str (str:gsub "^#!" ";;")] ; replace shebang with comment
    (when ?options (set ?options.source str))
    (var index 1)
    (fn []
      (let [r (str:byte index)]
        (set index (+ index 1))
        r))))

;; Table of delimiter bytes - (, ), [, ], {, }
;; Opener keys have closer as the value; closers keys have true as their value.
(local delims {40 41 41 true 91 93 93 true 123 125 125 true})

;; fnlfmt: skip
(fn sym-char? [b]
  (let [b (if (= :number (type b)) b (string.byte b))]
    (and (< 32 b)
         (not (. delims b))
         (not= b 127) ; backspace
         (not= b 34) ; double quote
         (not= b 39) ; single quote
         (not= b 126) ; tilde
         (not= b 59) ; semicolon
         (not= b 44) ; comma
         (not= b 64) ; at
         (not= b 96)))) ; backtick


;; prefix chars substituted while reading
(local prefixes {35 :hashfn
                 ;; non-backtick quote
                 39 :quote
                 44 :unquote
                 96 :quote})

;; NaN parsing is tricky, because in PUC Lua 0/0 is -nan not nan
(local (nan negative-nan)
  (if (= 45 (string.byte (tostring (/ 0 0)))) ; -
      (values (- (/ 0 0)) (/ 0 0))
      (values (/ 0 0) (- (/ 0 0)))))

(fn char-starter? [b] (or (< 1 b 127) (< 192 b 247)))

(local escapes {:a "\a" :b "\b" :f "\f" :n "\n" :r "\r" :t "\t" :v "\v"
                "\\" "\\" "\"" "\"" "'" "'" "\n" "\n"})

(fn parser-fn [getbyte filename {: source : unfriendly : comments &as options}]
  (var stack []) ; stack of unfinished values
  ;; Provide one character buffer and keep track of current line and byte index
  (var (line byteindex col prev-col lastb) (values 1 0 0 0 nil))

  (fn ungetb [ub]
    (when (char-starter? ub)
      (set col (- col 1)))
    (when (= ub 10)
      (set (line col) (values (- line 1) prev-col)))
    (set byteindex (- byteindex 1))
    (set lastb ub))

  (fn getb []
    (var r nil)
    (if lastb
        (set (r lastb) (values lastb nil))
        (set r (getbyte {:stack-size (length stack)})))
    (when r
      (set byteindex (+ byteindex 1)))
    (when (and r (char-starter? r))
      (set col (+ col 1)))
    (when (= r 10)
      (set (line col prev-col) (values (+ line 1) 0 col)))
    r)

  (fn warn [...] ((or options.warn utils.warn) ...))

  (fn whitespace? [b] (or (= b 32) (<= 9 b 13) (?. options.whitespace b)))

  ;; If you add new calls to this function, please update fennel.friend as well
  ;; to add suggestions for how to fix the new error!
  (fn parse-error [msg ?col-adjust]
    (let [endcol (and ?col-adjust col)
          col (+ col (or ?col-adjust -1))]
      ;; allow plugins to override parse-error
      (when (= nil (utils.hook-opts :parse-error options msg filename
                               (or line "?") col
                               source utils.root.reset))
        (utils.root.reset)
        (if unfriendly
            (error (string.format "%s:%s:%s: Parse error: %s"
                                  filename (or line "?") col msg) 0)
            (friend.parse-error msg filename (or line "?") col endcol
                                source options)))))

  (fn parse-stream []
    (var (whitespace-since-dispatch done? retval) true)

    (fn set-source-fields [source]
      (set (source.byteend source.endcol source.endline)
           (values byteindex (- col 1) line)))

    (fn dispatch [v ?source ?raw]
      (set whitespace-since-dispatch false)
      (let [v (case (utils.hook-opts :parse-form options v ?source ?raw stack)
                hookv hookv
                _ v)]
        (case (. stack (length stack))
          nil (set (retval done?) (values v true))
          {: prefix} (let [source (doto (table.remove stack) set-source-fields)
                           list (utils.list (utils.sym prefix source) v)]
                       (dispatch (utils.copy source list)))
          top (table.insert top v))))

    (fn badend []
      "Throw nice error when we expect more characters but reach end of stream."
      (let [closers (icollect [_ {: closer} (ipairs stack)] closer)]
        (parse-error (string.format "expected closing delimiter%s %s"
                                    (if (= (length stack) 1) "" :s)
                                    (string.char (unpack closers))) 0)))

    (fn skip-whitespace [b close-table]
      (if (and b (whitespace? b))
          (do
            (set whitespace-since-dispatch true)
            (skip-whitespace (getb) close-table))
          (and (not b) (next stack))
          (do (badend)
              ;; if we are at the end of the file and missing closers,
              ;; just pretend the closers all exist
              (for [i (length stack) 2 -1]
                (close-table (. stack i :closer)))
              (. stack 1 :closer))
          b))

    (fn parse-comment [b contents]
      (if (and b (not= 10 b))
          (parse-comment (getb) (doto contents (table.insert (string.char b))))
          comments
          (do (ungetb 10)
              (dispatch (utils.comment (table.concat contents)
                                       {: line : filename})))))

    (fn open-table [b]
      (when (not whitespace-since-dispatch)
        (parse-error (.. "expected whitespace before opening delimiter "
                         (string.char b))))
      (table.insert stack {:bytestart byteindex :closer (. delims b)
                           : filename : line :col (- col 1)}))

    (fn close-list [list]
      (dispatch (setmetatable list (getmetatable (utils.list)))))

    (fn close-sequence [tbl]
      (let [mt (getmetatable (utils.sequence))]
        ;; for table literals we can't store file/line/offset source
        ;; data in fields on the table itself, because the AST node
        ;; *is* the table, and the fields would show up in the
        ;; compiled output. keep them on the metatable instead.
        (each [k v (pairs tbl)]
          (when (not= :number (type k))
            (tset mt k v)
            (tset tbl k nil)))
        (dispatch (setmetatable tbl mt))))

    (fn add-comment-at [comments index node]
      (case (. comments index)
        existing (table.insert existing node)
        _ (tset comments index [node])))

    (fn next-noncomment [tbl i]
      (if (utils.comment? (. tbl i)) (next-noncomment tbl (+ i 1))
          (utils.sym? (. tbl i) ":") (tostring (. tbl (+ i 1)))
          (. tbl i)))

    (fn extract-comments [tbl]
      "Comment nodes can't be stored inside k/v tables; pull them out for later"
      ;; every comment either preceeds a key, preceeds a value, or is at the end
      (let [comments {:keys {}
                      :values {}
                      :last []}]
        (while (utils.comment? (. tbl (length tbl)))
          (table.insert comments.last 1 (table.remove tbl)))
        (var last-key? false)
        (each [i node (ipairs tbl)]
          (if (not (utils.comment? node))
              (set last-key? (not last-key?))
              last-key?
              (add-comment-at comments.values (next-noncomment tbl i) node)
              (add-comment-at comments.keys (next-noncomment tbl i) node)))
        ;; strip out the comments in a second pass; if we did it in the first
        ;; pass we wouldn't be able to distinguish key-attached vs val-attached
        (for [i (length tbl) 1 -1]
          (when (utils.comment? (. tbl i))
            (table.remove tbl i)))
        comments))

    (fn close-curly-table [tbl]
      (let [comments (extract-comments tbl)
            keys []
            val {}]
        (when (not= (% (length tbl) 2) 0)
          (set byteindex (- byteindex 1))
          (parse-error "expected even number of values in table literal"))
        (setmetatable val tbl) ; see note above about source data
        (for [i 1 (length tbl) 2]
          (when (and (= (tostring (. tbl i)) ":") (utils.sym? (. tbl (+ i 1)))
                     (utils.sym? (. tbl i)))
            (tset tbl i (tostring (. tbl (+ i 1)))))
          (tset val (. tbl i) (. tbl (+ i 1)))
          (table.insert keys (. tbl i)))
        (set tbl.comments comments)
        ;; save off the key order so the table can be reconstructed in order
        (set tbl.keys keys)
        (dispatch val)))

    (fn close-table [b]
      (let [top (table.remove stack)]
        (when (= top nil)
          (parse-error (.. "unexpected closing delimiter " (string.char b))))
        (when (and top.closer (not= top.closer b))
          (parse-error (.. "mismatched closing delimiter " (string.char b)
                           ", expected " (string.char top.closer))))
        (set-source-fields top)
        (if (= b 41) (close-list top)
            (= b 93) (close-sequence top)
            (close-curly-table top))))

    (fn bitrange [codepoint low high]
      (% (math.floor (/ codepoint (^ 2 low))) (math.floor (^ 2 (- high low)))))

    (fn encode-utf8 [codepoint-str]
      ;; codepoint-str format is "u{hexidecimal digits}"
      ;; so we need to substring just the interesting parts
      (case (tonumber (codepoint-str:sub 4 -2) 16)
        codepoint (if _G.utf8 (_G.utf8.char codepoint)
                      (<= 0        codepoint 0x7F)
                      (string.char codepoint)
                      (<= 0x80     codepoint 0x7FF)
                      (string.char (+ 0xC0 (bitrange codepoint 6 11))
                                   (+ 0x80 (bitrange codepoint 0 6)))
                      (<= 0x800    codepoint 0xFFFF)
                      (string.char (+ 0xE0 (bitrange codepoint 12 16))
                                   (+ 0x80 (bitrange codepoint 6 12))
                                   (+ 0x80 (bitrange codepoint 0 6)))
                      (<= 0x10000  codepoint 0x1FFFFF)
                      (string.char (+ 0xF0 (bitrange codepoint 18 21))
                                   (+ 0x80 (bitrange codepoint 12 18))
                                   (+ 0x80 (bitrange codepoint 6 12))
                                   (+ 0x80 (bitrange codepoint 0 6)))
                      ;; These are past the range of valid unicode,
                      ;; but we parse them anyway to match Lua
                      (<= 0x20000  codepoint 0x3FFFFFF)
                      (string.char (+ 0xF8 (bitrange codepoint 24 26))
                                   (+ 0x80 (bitrange codepoint 18 24))
                                   (+ 0x80 (bitrange codepoint 12 18))
                                   (+ 0x80 (bitrange codepoint 6 12))
                                   (+ 0x80 (bitrange codepoint 0 6)))
                      (<= 0x400000 codepoint 0x7FFFFFFF)
                      (string.char (+ 0xFC (bitrange codepoint 30 31))
                                   (+ 0x80 (bitrange codepoint 24 30))
                                   (+ 0x80 (bitrange codepoint 18 24))
                                   (+ 0x80 (bitrange codepoint 12 18))
                                   (+ 0x80 (bitrange codepoint 6 12))
                                   (+ 0x80 (bitrange codepoint 0 6)))
                      (parse-error (.. "utf8 value too large: " codepoint-str)))
        _ (parse-error (.. "Illegal string: " codepoint-str))))

    (fn parse-string-loop [chars b state]
      (when b
        (table.insert chars (string.char b)))
      (let [state (case [state b]
                    [:base 92] :backslash
                    [:base 34] :done
                    _ :base)]
        (if (and b (not= state :done))
            (parse-string-loop chars (getb) state)
            b)))

    (fn expand-str [str]
      (let [result []]
        (var i 1)
        (while (<= i (length str))
          (let [(add-to-i add-to-result) (case (str:match "^[^\\]+" i)
                                           text (values (length text) text)
                                           ;; literal escape code
                                           _ (case (. escapes (str:match "^\\(.?)" i))
                                               escape (values 2 escape)
                                               ;; the windows version of \<newline>
                                               _ (if (= "\\\r\n" (str:sub i (+ i 2)))
                                                   (values 3 "\r\n")
                                                   ;; hex escape code
                                                   (case (str:match "^\\x(%x%x)" i)
                                                     hex-code (values 4 (string.char (tonumber hex-code 16)))
                                                     ;; unicode esape code
                                                     _ (case (str:match "^\\u{%x+}" i)
                                                         unicode-escape (values (length unicode-escape) (encode-utf8 unicode-escape))
                                                         ;; whitespace escape code
                                                         _ (case (str:find "^\\z%s*" i)
                                                             (_ j) (values (+ (- j i) 1) "")
                                                             ;; decimal escape code
                                                             _ (case (str:match "^\\(%d%d?%d?)" i)
                                                                 digits (let [byte (tonumber digits 10)]
                                                                          (when (< 255 byte)
                                                                            (parse-error "invalid decimal escape"))
                                                                          (values (+ (length digits) 1) (string.char byte)))
                                                                 ;; unknown escape code
                                                                 _ (parse-error "invalid escape sequence"))))))))]
            (table.insert result add-to-result)
            (set i (+ i add-to-i))))
        (table.concat result)))

    (fn parse-string [source]
      (when (not whitespace-since-dispatch)
        (warn "expected whitespace before string" nil filename line (- col 1)))
      (table.insert stack {:closer 34})
      (let [chars ["\""]]
        (when (not (parse-string-loop chars (getb) :base))
          (badend))
        (table.remove stack)
        (let [raw (table.concat chars)
              expanded (expand-str (raw:sub 2 -2))]
          (dispatch expanded source raw))))

    (fn parse-prefix [b]
      "expand prefix byte into wrapping form eg. '`a' into '(quote a)'"
      (table.insert stack {:prefix (. prefixes b) : filename : line
                           :bytestart byteindex :col (- col 1)})
      (let [nextb (getb)
            trailing-whitespace? (or (whitespace? nextb) (= true (. delims nextb)))]
        (when (and trailing-whitespace? (not= b 35))
          (parse-error "invalid whitespace after quoting prefix"))
        (ungetb nextb)
        (when (and trailing-whitespace? (= b 35))
          (let [source (table.remove stack)]
            (set-source-fields source)
            (dispatch (utils.sym "#" source))))))

    (fn parse-sym-loop [chars b]
      (if (and b (sym-char? b))
          (do
            (table.insert chars (string.char b))
            (parse-sym-loop chars (getb)))
          (do
            (when b
              (ungetb b))
            chars)))

    (fn parse-number [rawstr source]
      ;; numbers can have underscores in the middle or end, but not at the start
      (let [trimmed (and (not (rawstr:find "^_")) (rawstr:gsub "_" ""))]
        (if (or (= trimmed "nan") (= trimmed "-nan")) false ; 5.1 is weird
            (rawstr:match "^%d")
            (do
              (dispatch (or (tonumber trimmed)
                            (parse-error (.. "could not read number \"" rawstr
                                             "\"") (- (length rawstr))))
                        source rawstr)
              true)
            (case (tonumber trimmed)
              x (do
                  (dispatch x source rawstr)
                  true)
              _ false))))

    (fn check-malformed-sym [rawstr]
      ;; for backwards-compatibility, special-case allowance of ~= but
      ;; all other uses of ~ are disallowed
      (fn col-adjust [pat] (- (rawstr:find pat) (utils.len rawstr) 1))
      (if (and (rawstr:match "^~") (not= rawstr "~="))
          (parse-error "invalid character: ~")
          (and (rawstr:match "[%.:][%.:]") (not= rawstr "..")
               (not= rawstr "$..."))
          (parse-error (.. "malformed multisym: " rawstr)
                       (col-adjust "[%.:][%.:]"))
          (and (not= rawstr ":") (rawstr:match ":$"))
          (parse-error (.. "malformed multisym: " rawstr)
                       (col-adjust ":$"))
          (rawstr:match ":.+[%.:]")
          (parse-error (.. "method must be last component of multisym: " rawstr)
                       (col-adjust ":.+[%.:]")))
      (when (not whitespace-since-dispatch)
        (warn "expected whitespace before token" nil filename line (+ col (col-adjust "^"))))
      rawstr)

    (fn parse-sym [b]                   ; not just syms actually...
      (let [source {:bytestart byteindex : filename : line :col (- col 1)}
            rawstr (table.concat (parse-sym-loop [(string.char b)] (getb)))]
        (set-source-fields source)
        (if (= rawstr :true)
            (dispatch true source)
            (= rawstr :false)
            (dispatch false source)
            (= rawstr "...")
            (dispatch (utils.varg source))
            (or (= rawstr ".inf") (= rawstr "+.inf"))
            (dispatch (/ 1 0) source rawstr)
            (= rawstr "-.inf")
            (dispatch (/ -1 0) source rawstr)
            (or (= rawstr ".nan") (= rawstr "+.nan"))
            (dispatch nan source rawstr)
            (= rawstr "-.nan")
            (dispatch negative-nan source rawstr)
            (rawstr:match "^:.+$")
            (dispatch (rawstr:sub 2) source rawstr)
            (not (parse-number rawstr source))
            (dispatch (utils.sym (check-malformed-sym rawstr) source)))))

    (fn parse-loop [b]
      (if (not b) nil
          (= b 59) (parse-comment (getb) [";"])
          (= (type (. delims b)) :number) (open-table b)
          (. delims b) (close-table b)
          (= b 34) (parse-string {:bytestart byteindex : filename : line : col})
          (. prefixes b) (parse-prefix b)
          (or (sym-char? b) (= b (string.byte "~"))) (parse-sym b)
          (not (utils.hook-opts :illegal-char options b getb ungetb dispatch))
          (parse-error (.. "invalid character: " (string.char b))))
      (if (not b) nil ; EOF
          done? (values true retval)
          (parse-loop (skip-whitespace (getb) close-table))))

    (parse-loop (skip-whitespace (getb) close-table)))

  (values parse-stream #(set (stack line byteindex col lastb)
                             (values [] 1 0 0 (and (not= lastb 10) lastb)))))

(fn parser [stream-or-string ?filename ?options]
  "Returns an iterator fn which parses string-or-stream and returns AST nodes.
On success, returns true and the AST node. Returns nil when it reaches the end."
  (let [filename (or ?filename :unknown)
        options (or ?options utils.root.options {})]
    ;; it's really easy to accidentally pass an options table here because all
    ;; the other fennel functions take the options table as the second arg!
    (assert (= :string (type filename))
            "expected filename as second argument to parser")
    (if (= :string (type stream-or-string))
        (parser-fn (string-stream stream-or-string options) filename options)
        (parser-fn stream-or-string filename options))))

{: granulate : parser : string-stream : sym-char?}
