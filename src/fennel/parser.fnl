;; This module is responsible for turning bytes of source code into an AST
;; data structure.

(local utils (require :fennel.utils))
(local friend (require :fennel.friend))
(local unpack (or _G.unpack table.unpack))

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
                  (do
                    (set c (getchunk parser-state))
                    (when (or (not c) (= c ""))
                      (set done? true)
                      (lua "return nil"))
                    (set index 2)
                    (c:byte 1)))))
          (fn [] (set c ""))))

(fn string-stream [str]
  "Convert a string into a stream of bytes."
  (let [str (str:gsub "^#![^\n]*\n" "")] ; remove shebang
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

(fn symbolchar? [b]
  (and (> b 32)
       (not (. delims b))
       (not= b 127) ; backspace
       (not= b 34) ; backslash
       (not= b 39) ; single quote
       (not= b 126) ; tilde
       (not= b 59) ; semicolon
       (not= b 44) ; comma
       (not= b 64) ; at
       (not= b 96))) ; backtick

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
  (fn parse-error [msg]
    (let [{: source : unfriendly} (or utils.root.options {})]
      (utils.root.reset)
      (if unfriendly
          (error (string.format "Parse error in %s:%s: %s" (or filename :unknown)
                                (or line "?") msg) 0)
          (friend.parse-error msg (or filename "unknown") (or line "?")
                              byteindex source))))

  (fn parse-stream []
    (var (whitespace-since-dispatch done? retval) true)
    (fn dispatch [v]
      "Dispatch when we complete a value"
      (if (= (# stack) 0)
          (set (retval done? whitespace-since-dispatch) (values v true false))
          (. stack (# stack) "prefix")
          (let [stacktop (. stack (# stack))]
            (tset stack (# stack) nil)
            (dispatch (utils.list (utils.sym stacktop.prefix) v)))
          (do (set whitespace-since-dispatch false)
              (table.insert (. stack (# stack)) v))))

    (fn badend []
      "Throw nice error when we expect more characters but reach end of stream."
      (let [accum (utils.map stack "closer")]
        (parse-error (string.format "expected closing delimiter%s %s"
                                    (or (and (= (# stack) 1) "") "s")
                                    (string.char (unpack accum))))))

    (while true ; main parse loop
      (var b nil)
      (while true ; skip whitespace
        (set b (getb))
        (when (and b (whitespace? b))
          (set whitespace-since-dispatch true))
        (when (or (not b) (not (whitespace? b)))
          (lua "break")))

      (when (not b)
        (when (> (# stack) 0)
          (badend))
        (lua "return nil"))

      (if (= b 59) ; comment
          (while true
            (set b (getb))
            (when (or (not b) (= b 10))
              (lua "break")))
          (= (type (. delims b)) :number) ; opening delimiter
          (do
            (when (not whitespace-since-dispatch)
              (parse-error (.. "expected whitespace before opening delimiter "
                              (string.char b))))
            (table.insert stack (setmetatable {:bytestart byteindex
                                               :closer (. delims b)
                                               :filename filename
                                               :line line}
                                              (getmetatable (utils.list)))))
          (. delims b) ; closing delimiter
          (let [last (. stack (# stack))]
            (when (= (# stack) 0)
              (parse-error (.. "unexpected closing delimiter " (string.char b))))
            (var val nil)
            (when (not= last.closer b)
              (parse-error (.. "mismatched closing delimiter " (string.char b)
                              ", expected " (string.char last.closer))))
            (set last.byteend byteindex) ; set closing byte index
            (if (= b 41)
                (set val last)
                (= b 93)
                (do
                  (set val (utils.sequence (unpack last)))
                  ;; for table literals we can store file/line/offset source
                  ;; data in fields on the table itself, because the AST node
                  ;; *is* the table, and the fields would show up in the
                  ;; compiled output. keep them on the metatable instead.
                  (each [k v (pairs last)]
                    (tset (getmetatable val) k v)))
                (do
                  (when (not= (% (# last) 2) 0)
                    (set byteindex (- byteindex 1))
                    (parse-error "expected even number of values in table literal"))
                  (set val [])
                  (setmetatable val last) ; see note above about source data
                  (for [i 1 (# last) 2]
                    (when (and (= (tostring (. last i)) ":")
                               (utils.sym? (. last (+ i 1)))
                               (utils.sym? (. last i)))
                      (tset last i (tostring (. last (+ i 1)))))
                    (tset val (. last i) (. last (+ i 1))))))
            (tset stack (# stack) nil)
            (dispatch val))
          (= b 34) ; quoted string
          (let [chars [34]]
            (var state "base")
            (tset stack (+ (# stack) 1) {:closer 34})
            (while true
              (set b (getb))
              (tset chars (+ (# chars) 1) b)
              (if (= state "base")
                  (if (= b 92)
                      (set state "backslash")
                      (= b 34)
                      (set state "done"))
                  (set state "base"))
              (when (or (not b) (= state "done"))
                (lua "break")))
            (when (not b)
              (badend))
            (tset stack (# stack) nil)
            (let [raw (string.char (unpack chars))
                  formatted (raw:gsub "[\1-\31]" (fn [c] (.. "\\" (c:byte))))
                  load-fn ((or _G.loadstring load)
                          (string.format "return %s" formatted))]
              (dispatch (load-fn))))
          (. prefixes b)
          (do ; expand prefix byte into wrapping form eg. '`a' into '(quote a)'
            (table.insert stack {:prefix (. prefixes b)})
            (let [nextb (getb)]
              (when (whitespace? nextb)
                (when (not= b 35)
                  (parse-error "invalid whitespace after quoting prefix"))
                (tset stack (# stack) nil)
                (dispatch (utils.sym "#")))
              (ungetb nextb)))
          (or (symbolchar? b) (= b (string.byte "~"))) ; try sym
          (let [chars []
                bytestart byteindex]
            (while true
              (tset chars (+ (# chars) 1) b)
              (set b (getb))
              (when (or (not b) (not (symbolchar? b)))
                (lua "break")))
            (when b
              (ungetb b))
            (local rawstr (string.char (unpack chars)))
            (if (= rawstr "true")
                (dispatch true)
                (= rawstr "false")
                (dispatch false)
                (= rawstr "...")
                (dispatch (utils.varg))
                (rawstr:match "^:.+$")
                (dispatch (rawstr:sub 2))
                ;; for backwards-compatibility, special-case allowance
                ;; of ~= but all other uses of ~ are disallowed
                (and (rawstr:match "^~") (not= rawstr "~="))
                (parse-error "illegal character: ~")
                (let [force-number (rawstr:match "^%d")
                      number-with-stripped-underscores (rawstr:gsub "_" "")]
                  (var x nil)
                  (if force-number
                      (set x (or (tonumber number-with-stripped-underscores)
                                 (parse-error (.. "could not read number \""
                                                 rawstr "\""))))
                      (do
                        (set x (tonumber number-with-stripped-underscores))
                        (when (not x)
                          (if (rawstr:match "%.[0-9]")
                              (do
                                (set byteindex (+ (+ (- byteindex (# rawstr))
                                                     (rawstr:find "%.[0-9]")) 1))
                                (parse-error (.. "can't start multisym segment "
                                                "with a digit: " rawstr)))
                              (and (rawstr:match "[%.:][%.:]")
                                   (not= rawstr "..")
                                   (not= rawstr "$..."))
                              (do
                                (set byteindex (+ (- byteindex (# rawstr)) 1
                                                  (rawstr:find "[%.:][%.:]")))
                                (parse-error (.. "malformed multisym: " rawstr)))
                              (rawstr:match ":.+[%.:]")
                              (do
                                (set byteindex (+ (- byteindex (# rawstr))
                                                  (rawstr:find ":.+[%.:]")))
                                (parse-error (.. "method must be last component "
                                                "of multisym: " rawstr)))
                              (set x (utils.sym rawstr nil {:byteend byteindex
                                                            :bytestart bytestart
                                                            :filename filename
                                                            :line line}))))))
                  (dispatch x))))
          (parse-error (.. "illegal character: " (string.char b))))
      (when done?
        (lua "break")))
    (values true retval))
  (values parse-stream (fn [] (set stack []))))

{: granulate : parser : string-stream}
