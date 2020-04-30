;; an assert-compile function which tries to show where the error occurred
;; and what to do about it!

;; TODO: run this in compiler scope so we have access to the real sym?
(fn sym? [s] (-?> (getmetatable s) (. 1) (= "SYMBOL")))

(fn odd-bindings-suggest [[_ _bindings]]
  ["finding where the identifier or value is missing"])

(local suggestions
       {"unexpected multi symbol (.*)"
        ["renaming %s to not have a dot or colon in it"]

        "use of global (.*) is aliased by a local"
        ["renaming local %s to avoid conflict"]

        "local (.*) was overshadowed by a special form or macro"
        ["renaming local %s to avoid conflict"]

        "global (.*) conflicts with local"
        ["renaming local %s to avoid conflict"]

        "expected var (.*)"
        ["declaring %s using var instead of let/local"
         "introducing a new local instead of changing the value of %s"]

        "macro tried to bind (.*) without gensym"
        ["changing to %s# when introducing identifiers inside macros"]

        "unknown global in strict mode: (.*)"
        ["looking to see if there's a typo"
         "using the _G table instead, eg. _G.%s if you really want a global"]

        "expected a function.* to call"
        ["removing the empty parentheses"
         "using square brackets if you want an empty table"]

        "cannot call literal value"
        ["looking to see if there's a typo"
         "looking for a missing function name"]

        "unexpected vararg"
        ["putting ... at the end of the function's parameters to use varargs"]

        "multisym method calls may only be in call position"
        ["using a dot instead of a colon to reference a table's fields"]

        "unused local (.*)"
        ["fixing a typo so %s is used"
         "renaming it to _%s"]

        "expected parameters"
        ["placing function parameters as a list of identifiers in brackets"]

        "unable to bind (.*)"
        ["replacing the %s being bound with an identifier"]

        "expected rest argument before last parameter"
        ["moving & to right before the final identifier when destructuring"]

        "expected vararg as last parameter"
        ["moving the ... argument to the end of the parameter list"]

        "expected symbol for function parameter: (.*)"
        ["changing the %s parameter to an identifier instead of a literal"]

        "could not compile value of type "
        ["debugging the macro you're calling not to return a coroutine or userdata"]

        "expected local"
        ["looking for a typo"
         "looking for a local which is used out of its scope"]

        "expected body expression"
        ["putting some code in the body of this form after the bindings"]

        "expected binding table"
        ["placing a table here in square brackets containing identifiers to bind"]

        "expected even number of name/value bindings"
        odd-bindings-suggest

        "may only be used at compile time"
        ["moving this to inside a macro if you need to manipulate symbols/lists"
         "using square brackets instead of parens to construct a table"]
        })

(fn suggest [msg ast]
  (var suggestion nil)
  (each [pat sug (pairs suggestions)]
    (let [matches [(msg:match pat)]]
      (when (< 0 (# matches))
        (set suggestion (if (= :table (type sug))
                            (let [out []]
                              (each [_ s (ipairs sug)]
                                (table.insert out (s:format (unpack matches))))
                              out)
                            (sug ast matches))))))
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
  (let [{: filename : line : bytestart : byteend} (or (getmetatable ast) ast)
        (ok codeline bol eol) (pcall read-line-from-file filename line)
        suggestions (suggest msg ast)
        out [msg ""]]
    ;; don't assume the file can be read as-is
    (when (and ok codeline)
      (table.insert out codeline))
    (when (and ok codeline bytestart byteend)
      (table.insert out (.. (string.rep " " (- bytestart bol 1)) "^"
                            (string.rep "^" (math.min (- byteend bytestart)
                                                      (- eol bytestart))))))
    (when suggestions
      (each [_ suggestion (ipairs suggestions)]
        (table.insert out (: "* Try %s." :format suggestion))))
    (table.concat out "\n")))

(fn friendly [condition msg ast]
  (when (not condition)
    (let [{: filename : line} (or (getmetatable ast) ast)]
      (error (friendly-msg (: "Compile error in %s:%s\n  %s" :format
                              (or filename "unknown") (or line "?") msg)
                           ast) 0)))
  condition)
