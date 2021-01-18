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
              (if (<= index (# c))
                  (let [b (c:byte index)]
                    (set index (+ index 1))
                    b)
                  (match (getchunk parser-state)
                    (char ? (not= char "")) (do (set c char)
                                                (set index 2)
                                                (c:byte))
                    _ (set done? true)))))
          (fn [] (set c ""))))

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
(local delims {40 41 41 true
               91 93 93 true
               123 125 125 true})

(fn whitespace? [b]
  (or (= b 32) (and (>= b 9) (<= b 13))))

(fn sym-char? [b]
  (let [b (if (= :number (type b)) b (string.byte b))]
    (and (> b 32)
         (not (. delims b))
         (not= b 127) ; backspace
         (not= b 34) ; backslash
         (not= b 39) ; single quote
         (not= b 126) ; tilde
         (not= b 59) ; semicolon
         (not= b 44) ; comma
         (not= b 64) ; at
         (not= b 96)))) ; backtick

;; prefix chars substituted while reading
(local prefixes {35 "hashfn" ; #
                 39 "quote" ; '
                 44 "unquote" ; ,
                 96 "quote"}); `

(fn parser [getbyte filename options]
  "Parse one value given a function that returns sequential bytes.
Will throw an error as soon as possible without getting more bytes on bad input.
Returns if a value was read, and then the value read. Will return nil when input
stream is finished."
  (var stack []) ; stack of unfinished values
  ;; Provide one character buffer and keep track of current line and byte index
  (var line 1)
  (var byteindex 0)
  (var lastb nil)

  (fn ungetb [ub]
    (when (= ub 10)
      (set line (- line 1)))
    (set byteindex (- byteindex 1))
    (set lastb ub))

  (fn getb []
    (var r nil)
    (if lastb
        (set (r lastb) (values lastb nil))
        (set r (getbyte {:stack-size (# stack)})))
    (set byteindex (+ byteindex 1))
    (when (= r 10)
      (set line (+ line 1)))
    r)

  ;; If you add new calls to this function, please update fennel.friend as well
  ;; to add suggestions for how to fix the new error!
  (fn parse-error [msg byteindex-override]
    (let [{: source : unfriendly} (or options utils.root.options {})]
      (utils.root.reset)
      (if unfriendly
          (error (string.format "Parse error in %s:%s: %s" (or filename :unknown)
                                (or line "?") msg) 0)
          (friend.parse-error msg (or filename "unknown") (or line "?")
                              (or byteindex-override byteindex) source))))

  (fn parse-stream []
    (var (whitespace-since-dispatch done? retval) true)
    (fn dispatch [v]
      "Dispatch when we complete a value"
      (match (. stack (# stack))
        nil (set (retval done? whitespace-since-dispatch) (values v true false))
        {: prefix} (do (table.remove stack)
                       (dispatch (utils.list (utils.sym prefix) v)))
        top (do (set whitespace-since-dispatch false)
                (table.insert top v))))

    (fn badend []
      "Throw nice error when we expect more characters but reach end of stream."
      (let [accum (utils.map stack "closer")]
        (parse-error (string.format "expected closing delimiter%s %s"
                                    (if (= (# stack) 1) "" "s")
                                    (string.char (unpack accum))))))

    (fn skip-whitespace [b]
      (if (and b (whitespace? b))
          (do (set whitespace-since-dispatch true)
              (skip-whitespace (getb)))
          (and (not b) (> (# stack) 0))
          (badend)
          b))

    (fn parse-comment [b contents]
      (if (and b (not= 10 b))
          (parse-comment (getb) (doto contents (table.insert (string.char b))))
          (and options options.comments)
          (dispatch (utils.comment (table.concat contents)))
          b))

    (fn open-table [b]
      (when (not whitespace-since-dispatch)
        (parse-error (.. "expected whitespace before opening delimiter "
                         (string.char b))))
      (table.insert stack {:bytestart byteindex :closer (. delims b)
                           :filename filename :line line}))

    (fn close-list [list]
      (dispatch (setmetatable list (getmetatable (utils.list)))))

    (fn close-sequence [tbl]
      (let [val (utils.sequence (unpack tbl))]
        ;; for table literals we can store file/line/offset source
        ;; data in fields on the table itself, because the AST node
        ;; *is* the table, and the fields would show up in the
        ;; compiled output. keep them on the metatable instead.
        (each [k v (pairs tbl)]
          (tset (getmetatable val) k v))
        (dispatch val)))

    (fn close-curly-table [tbl]
      (let [val []] ; a {} table
        (when (not= (% (# tbl) 2) 0)
          (set byteindex (- byteindex 1))
          (parse-error "expected even number of values in table literal"))
        (setmetatable val tbl) ; see note above about source data
        (for [i 1 (# tbl) 2]
          (when (and (= (tostring (. tbl i)) ":")
                     (utils.sym? (. tbl (+ i 1)))
                     (utils.sym? (. tbl i)))
            (tset tbl i (tostring (. tbl (+ i 1)))))
          (tset val (. tbl i) (. tbl (+ i 1))))
        (dispatch val)))

    (fn close-table [b]
      (let [top (table.remove stack)]
        (when (= top nil)
          (parse-error (.. "unexpected closing delimiter " (string.char b))))
        (when (not= top.closer b)
          (parse-error (.. "mismatched closing delimiter " (string.char b)
                           ", expected " (string.char top.closer))))
        (set top.byteend byteindex) ; set closing byte index
        (if (= b 41) (close-list top)
            (= b 93) (close-sequence top)
            (close-curly-table top))))

    (fn parse-string-loop [chars b state]
      (table.insert chars b)
      (let [state (match [state b]
                    [:base 92] :backslash
                    [:base 34] :done
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
              formatted (raw:gsub "[\7-\13]" escape-char)
              load-fn ((or (rawget _G :loadstring) load) (.. "return " formatted))]
          (dispatch (load-fn)))))

    (fn parse-prefix [b]
      "expand prefix byte into wrapping form eg. '`a' into '(quote a)'"
      (table.insert stack {:prefix (. prefixes b)})
      (let [nextb (getb)]
        (when (whitespace? nextb)
          (when (not= b 35)
            (parse-error "invalid whitespace after quoting prefix"))
          (table.remove stack)
          (dispatch (utils.sym "#")))
        (ungetb nextb)))

    (fn parse-sym-loop [chars b]
      (if (and b (sym-char? b))
          (do (table.insert chars b)
              (parse-sym-loop chars (getb)))
          (do (when b (ungetb b))
              chars)))

    (fn parse-number [rawstr]
      ;; numbers can have underscores in the middle or end, but not at the start
      (let [number-with-stripped-underscores (and (not (rawstr:find "^_"))
                                                  (rawstr:gsub "_" ""))]
        (if (rawstr:match "^%d")
            (do (dispatch (or (tonumber number-with-stripped-underscores)
                              (parse-error (.. "could not read number \""
                                               rawstr "\""))))
                true)
            (match (tonumber number-with-stripped-underscores)
              x (do (dispatch x) true)
              _ false))))

    (fn check-malformed-sym [rawstr]
      ;; for backwards-compatibility, special-case allowance of ~= but
      ;; all other uses of ~ are disallowed
      (if (and (rawstr:match "^~") (not= rawstr "~="))
          (parse-error "illegal character: ~")
          (rawstr:match "%.[0-9]")
          (parse-error (.. "can't start multisym segment "
                           "with a digit: " rawstr)
                       (+ (+ (- byteindex (# rawstr))
                             (rawstr:find "%.[0-9]")) 1))
          (and (rawstr:match "[%.:][%.:]")
               (not= rawstr "..") (not= rawstr "$..."))
          (parse-error (.. "malformed multisym: " rawstr)
                       (+ (- byteindex (# rawstr)) 1
                          (rawstr:find "[%.:][%.:]")))
          (rawstr:match ":.+[%.:]")
          (parse-error (.. "method must be last component "
                           "of multisym: " rawstr)
                       (+ (- byteindex (# rawstr))
                          (rawstr:find ":.+[%.:]")))))

    (fn parse-sym [b] ; not just syms actually...
      (let [bytestart byteindex
            rawstr (string.char (unpack (parse-sym-loop [b] (getb))))]
        (if (= rawstr "true")
            (dispatch true)
            (= rawstr "false")
            (dispatch false)
            (= rawstr "...")
            (dispatch (utils.varg))
            (rawstr:match "^:.+$")
            (dispatch (rawstr:sub 2))
            (parse-number rawstr) nil
            (check-malformed-sym rawstr) nil
            (dispatch (utils.sym rawstr nil {:byteend byteindex
                                             :bytestart bytestart
                                             :filename filename
                                             :line line})))))

    (fn parse-loop [b]
      (if (not b) nil
          (= b 59) (parse-comment (getb) [";"])
          (= (type (. delims b)) :number) (open-table b)
          (. delims b) (close-table b)
          (= b 34) (parse-string b)
          (. prefixes b) (parse-prefix b)
          (or (sym-char? b) (= b (string.byte "~"))) (parse-sym b)
          (parse-error (.. "illegal character: " (string.char b))))

      (if (not b) nil ; EOF
          done? (values true retval)
          (parse-loop (skip-whitespace (getb)))))

    (parse-loop (skip-whitespace (getb))))
  (values parse-stream (fn [] (set stack []))))

{: granulate : parser : string-stream : sym-char?}
