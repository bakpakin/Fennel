;; an assert-compile function which tries to show where the error occurred
;; and what to do about it!

(local suggestions
       {"did not expect multi symbol (.*)"
        "rename %s to not have a dot or colon in it"

        "use of global (.*) is aliased by a local"
        "rename local %s to avoid conflict"

        "(.*) may be overshadowed by a special form or macro"
        "rename local %s to avoid conflict"

        "global (.*) conflicts with local"
        "rename local %s to avoid conflict"

        "expected global, found local"
        "rename local to avoid conflict"

        "expected var (.*)"
        "declare %s using var instead of let/local"

        "macro tried to bind (.*) without gensym"
        "add # after any identifiers introduced inside macros to avoid conflict"

        "unknown global in strict mode: (.*)"
        "this probably a typo! If not, try using the _G table instead, eg. _G.%s"

        "expected a function.* to call"
        "remove the empty parentheses or use square brackets for an empty table"

        "cannot call literal value"
        "probably a typo or missing function name"

        "unexpected vararg"
        "to use varargs, you must put ... at the end of the function's parameters"

        "multisym method calls may only be in call position"
        "use a dot instead of a colon to reference a table's fields"

        "unused local (.*)"
        "either fix a typo so %s is used, or rename the local to start with _"

        "expected parameters"
        "place parameters in function as a list of identifiers in brackets"

        "unable to bind"
        "replace string/number literal being bound with an identifier"

        "expected rest argument in final position"
        "when destructuring, move & to right before the final identifier"

        "expected vararg as last parameter"
        "move the ... argument to the end of the parameter list"

        "expected symbol for function parameter: (.*)"
        "parameter %s can't be a literal value; change it to an identifier"

        "could not compile value of type "
        (.. "you're probably calling a macro that returns a coroutine or "
            "userdata?\nYou'll need to debug your macro")

        ;; no idea how to trigger this one
        ;; "expected local"

        ;; skipping special forms for now...
        })

(fn suggest [msg _ast]
  (var suggestion nil)
  (each [pat sug (pairs suggestions)]
    (let [matches [(msg:match pat)]]
      (when (< 0 (# matches))
        (set suggestion (sug:format (unpack matches))))))
  suggestion)

(fn read-line-from-file [filename line]
  (var bytes 0)
  (let [f (assert (io.open filename))
        _ (for [_ 1 (- line 1)]
            (set bytes (+ bytes 1 (# (f:read)))))
        codeline (f:read)
        eol (+ bytes (# codeline))]
    (f:close)
    (values codeline bytes eol)))

(fn friendly-msg [msg ast]
  (let [{: filename : line : bytestart : byteend} ast
        (ok codeline bol eol) (pcall read-line-from-file filename line)
        suggestion (suggest msg ast)
        out [msg ""]]
    ;; don't assume the file can be read as-is
    (when (and ok codeline)
      (table.insert out codeline))
    (when (and ok codeline bytestart byteend)
      (table.insert out (.. (string.rep " " (- bytestart bol 1)) "^"
                            (string.rep "^" (math.min (- byteend bytestart)
                                                      (- eol bytestart))))))
    (when suggestion
      (table.insert out (: "Fix: %s." :format suggestion)))
    (table.concat out "\n")))

(fn friendly [condition msg ast]
  (when (not condition)
    (error (friendly-msg (: "Compile error in %s:%s: %s" :format
                            (or ast.filename "unknown") (or ast.line "?") msg)
                         ast) 0))
  condition)
