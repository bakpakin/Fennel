;; This module is responsible for turning bytes of source code into an AST
;; data structure.

(local utils (require :fennel.utils))
(local friend (require :fennel.friend))
(local unpack (or table.unpack _G.unpack))

(fn granulate [getchunk]
  "Convert a stream of chunks to a stream of bytes.
Also returns a second function to clear the buffer in the byte stream"
  (var (c index done?) (values "" 1 false))
  (values (fn [parser-state]
            (when (not done?)
              (if (<= index (length c))
                  (let [b (c:byte index)]
                    (set index (+ index 1))
                    b)
                  (match (getchunk parser-state)
                    (char ? (not= char "")) (do
                                              (set c char)
                                              (set index 2)
                                              (c:byte))
                    _ (set done? true))))) #(set c "")))

(fn string-stream [str]
  "Convert a string into a stream of bytes."
  (let [str (str:gsub "^#!" ";;")] ; replace shebang with comment
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
         (not= b 34) ; backslash
         (not= b 39) ; single quote
         (not= b 126) ; tilde
         (not= b 59) ; semicolon
         (not= b 44) ; comma
         (not= b 64) ; at
         (not= b 96) ; backtick
         )))

;; prefix chars substituted while reading
(local prefixes {35 :hashfn
                 ;; non-backtick quote
                 39 :quote
                 44 :unquote
                 96 :quote})

(fn char-starter? [b] (or (< 1 b 127) (< 192 b 247)))

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
    (set byteindex (+ byteindex 1))
    (when (and r (char-starter? r))
      (set col (+ col 1)))
    (when (= r 10)
      (set (line col prev-col) (values (+ line 1) 0 col)))
    r)

  (fn whitespace? [b] (or (= b 32) (<= 9 b 13) (?. options.whitespace b)))

  ;; If you add new calls to this function, please update fennel.friend as well
  ;; to add suggestions for how to fix the new error!
  (fn parse-error [msg ?col-adjust]
    (let [col (+ col (or ?col-adjust -1))]
      ;; allow plugins to override parse-error
      (when (= nil (utils.hook-opts :parse-error options msg filename
                               (or line "?") col
                               source utils.root.reset))
        (utils.root.reset)
        (if (or unfriendly (not _G.io) (not _G.io.read))
            (error (string.format "%s:%s:%s Parse error: %s"
                                  filename (or line "?") col msg) 0)
            (friend.parse-error msg filename (or line "?") col source)))))

  (fn parse-stream []
    (var (whitespace-since-dispatch done? retval) true)

    (fn set-source-fields [source]
      (set (source.byteend source.endcol) (values byteindex (- col 1))))

    (fn dispatch [v]
      "Dispatch when we complete a value"
      (match (. stack (length stack))
        nil (set (retval done? whitespace-since-dispatch) (values v true false))
        {: prefix} (let [source (doto (table.remove stack) set-source-fields)
                         list (utils.list (utils.sym prefix source) v)]
                     (each [k v (pairs source)]
                       (tset list k v))
                     (dispatch list))
        top (do
              (set whitespace-since-dispatch false)
              (table.insert top v))))

    (fn badend []
      "Throw nice error when we expect more characters but reach end of stream."
      (let [accum (utils.map stack :closer)]
        (parse-error (string.format "expected closing delimiter%s %s"
                                    (if (= (length stack) 1) "" :s)
                                    (string.char (unpack accum))))))

    (fn skip-whitespace [b]
      (if (and b (whitespace? b))
          (do
            (set whitespace-since-dispatch true)
            (skip-whitespace (getb)))
          (and (not b) (< 0 (length stack)))
          (badend)
          b))

    (fn parse-comment [b contents]
      (if (and b (not= 10 b))
          (parse-comment (getb) (doto contents (table.insert (string.char b))))
          comments
          (do (ungetb 10)
              (dispatch (utils.comment (table.concat contents)
                                       {:line (- line 1) :filename filename})))))

    (fn open-table [b]
      (when (not whitespace-since-dispatch)
        (parse-error (.. "expected whitespace before opening delimiter "
                         (string.char b))))
      (table.insert stack {:bytestart byteindex :closer (. delims b)
                           : filename : line :col (- col 1)}))

    (fn close-list [list]
      (dispatch (setmetatable list (getmetatable (utils.list)))))

    (fn close-sequence [tbl]
      (let [val (utils.sequence (unpack tbl))]
        ;; for table literals we can't store file/line/offset source
        ;; data in fields on the table itself, because the AST node
        ;; *is* the table, and the fields would show up in the
        ;; compiled output. keep them on the metatable instead.
        (each [k v (pairs tbl)]
          (tset (getmetatable val) k v))
        (dispatch val)))

    (fn add-comment-at [comments index node]
      (match (. comments index)
        existing (table.insert existing node)
        _ (tset comments index [node])))

    (fn next-noncomment [tbl i]
      (if (utils.comment? (. tbl i))
          (next-noncomment tbl (+ i 1))
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

    (fn parse-string-loop [chars b state]
      (table.insert chars b)
      (let [state (match [state b]
                    [:base 92] :backslash
                    [:base 34] :done
                    [:backslash 10] (do
                                      (table.remove chars (- (length chars) 1))
                                      :base)
                    _ :base)]
        (if (and b (not= state :done))
            (parse-string-loop chars (getb) state)
            b)))

    (fn escape-char [c]
      (. {7 "\\a" 8 "\\b" 9 "\\t" 10 "\\n" 11 "\\v" 12 "\\f" 13 "\\r"} (c:byte)))

    (fn parse-string []
      (table.insert stack {:closer 34})
      (let [chars [34]]
        (when (not (parse-string-loop chars (getb) :base))
          (badend))
        (table.remove stack)
        (let [raw (string.char (unpack chars))
              formatted (raw:gsub "[\a-\r]" escape-char)]
          (match ((or (rawget _G :loadstring) load) (.. "return " formatted))
            load-fn (dispatch (load-fn))
            nil (parse-error (.. "Invalid string: " raw))))))

    (fn parse-prefix [b]
      "expand prefix byte into wrapping form eg. '`a' into '(quote a)'"
      (table.insert stack {:prefix (. prefixes b) : filename : line
                           :bytestart byteindex :col (- col 1)})
      (let [nextb (getb)]
        (when (or (whitespace? nextb) (= true (. delims nextb)))
          (when (not= b 35)
            (parse-error "invalid whitespace after quoting prefix"))
          (table.remove stack)
          (dispatch (utils.sym "#")))
        (ungetb nextb)))

    (fn parse-sym-loop [chars b]
      (if (and b (sym-char? b))
          (do
            (table.insert chars b)
            (parse-sym-loop chars (getb)))
          (do
            (when b
              (ungetb b))
            chars)))

    (fn parse-number [rawstr]
      ;; numbers can have underscores in the middle or end, but not at the start
      (let [number-with-stripped-underscores (and (not (rawstr:find "^_"))
                                                  (rawstr:gsub "_" ""))]
        (if (rawstr:match "^%d")
            (do
              (dispatch (or (tonumber number-with-stripped-underscores)
                            (parse-error (.. "could not read number \"" rawstr
                                             "\""))))
              true)
            (match (tonumber number-with-stripped-underscores)
              x (do
                  (dispatch x)
                  true)
              _ false))))

    (fn check-malformed-sym [rawstr]
      ;; for backwards-compatibility, special-case allowance of ~= but
      ;; all other uses of ~ are disallowed
      (fn col-adjust [pat] (- (rawstr:find pat) (utils.len rawstr) 1))
      (if (and (rawstr:match "^~") (not= rawstr "~="))
          (parse-error "invalid character: ~")
          (rawstr:match "%.[0-9]")
          (parse-error (.. "can't start multisym segment with a digit: " rawstr)
                       (col-adjust "%.[0-9]"))
          (and (rawstr:match "[%.:][%.:]") (not= rawstr "..")
               (not= rawstr "$..."))
          (parse-error (.. "malformed multisym: " rawstr)
                       (col-adjust "[%.:][%.:]"))
          (and (not= rawstr ":") (rawstr:match ":$"))
          (parse-error (.. "malformed multisym: " rawstr)
                       (col-adjust ":$"))
          (rawstr:match ":.+[%.:]")
          (parse-error (.. "method must be last component of multisym: " rawstr)
                       (col-adjust ":.+[%.:]"))
          rawstr))

    (fn parse-sym [b] ; not just syms actually...
      (let [source {:bytestart byteindex : filename : line :col (- col 1)}
            rawstr (string.char (unpack (parse-sym-loop [b] (getb))))]
        (set-source-fields source)
        (if (= rawstr :true)
            (dispatch true)
            (= rawstr :false)
            (dispatch false)
            (= rawstr "...")
            (dispatch (utils.varg source))
            (rawstr:match "^:.+$")
            (dispatch (rawstr:sub 2))
            (not (parse-number rawstr))
            (dispatch (utils.sym (check-malformed-sym rawstr) source)))))

    (fn parse-loop [b]
      (if (not b) nil
          (= b 59) (parse-comment (getb) [";"])
          (= (type (. delims b)) :number) (open-table b)
          (. delims b) (close-table b)
          (= b 34) (parse-string b)
          (. prefixes b) (parse-prefix b)
          (or (sym-char? b) (= b (string.byte "~"))) (parse-sym b)
          (not (utils.hook-opts :illegal-char options b getb ungetb dispatch))
          (parse-error (.. "invalid character: " (string.char b))))
      (if (not b) nil ; EOF
          done? (values true retval)
          (parse-loop (skip-whitespace (getb)))))

    (parse-loop (skip-whitespace (getb))))

  (values parse-stream #(set (stack line byteindex col lastb) (values [] 1 0 0 nil))))

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
        (parser-fn (string-stream stream-or-string) filename options)
        (parser-fn stream-or-string filename options))))

{: granulate : parser : string-stream : sym-char?}
