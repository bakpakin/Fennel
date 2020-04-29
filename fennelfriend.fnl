;; an assert-compile function which tries to show where the error occurred

(fn read-line-from-file [filename line]
  (var bytes 0)
  (let [f (assert (io.open filename))
        _ (for [_ 1 (- line 1)]
            (set bytes (+ bytes 1 (# (f:read)))))
        codeline (f:read)
        eol (+ bytes (# codeline))]
    (f:close)
    (values codeline bytes eol)))

(fn friendly-msg [msg {: filename : line : bytestart : byteend}]
  (let [(ok codeline bol eol) (pcall read-line-from-file filename line)]
    ;; don't assume the file can be read as-is
    (if (and ok codeline bytestart byteend)
        (.. msg "\n" codeline "\n"
            (string.rep " " (- bytestart bol))
            (string.rep "^" (math.min (- byteend bytestart)
                                      (- eol bytestart))))
        (and ok codeline) (.. msg "\n" codeline)
        msg)))

(fn friendly [condition msg ast]
  (when (not condition)
    (error (friendly-msg (: "Compile error in `%s' %s:%s: %s" :format
                            (. ast 1) (or ast.filename "unknown") (or ast.line "?")
                            msg) ast) 0))
  condition)
