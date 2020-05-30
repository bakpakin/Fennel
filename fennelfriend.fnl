;; an assert-compile function which tries to show where the error occurred
;; and what to do about it!

(fn ast-source [ast]
  (let [m (getmetatable ast)]
    (if (and m m.filename m.line m) m ast)))

(local suggestions
       {"unexpected multi symbol (.*)"
        ["removing periods or colons from %s"]

        "use of global (.*) is aliased by a local"
        ["renaming local %s"]

        "local (.*) was overshadowed by a special form or macro"
        ["renaming local %s"]

        "global (.*) conflicts with local"
        ["renaming local %s"]

        "expected var (.*)"
        ["declaring %s using var instead of let/local"
         "introducing a new local instead of changing the value of %s"]

        "expected macros to be table"
        ["ensuring your macro definitions return a table"]

        "expected each macro to be function"
        ["ensuring that the value for each key in your macros table contains a function"
         "avoid defining nested macro tables"]

        "macro not found in macro module"
        ["checking the keys of the imported macro module's returned table"]

        "macro tried to bind (.*) without gensym"
        ["changing to %s# when introducing identifiers inside macros"]

        "unknown global in strict mode: (.*)"
        ["looking to see if there's a typo"
         "using the _G table instead, eg. _G.%s if you really want a global"
         "moving this code to somewhere that %s is in scope"
         "binding %s as a local in the scope of this code"]

        "expected a function.* to call"
        ["removing the empty parentheses"
         "using square brackets if you want an empty table"]

        "cannot call literal value"
        ["checking for typos"
         "checking for a missing function name"]

        "unexpected vararg"
        ["putting \"...\" at the end of the fn parameters if the vararg was intended"]

        "multisym method calls may only be in call position"
        ["using a period instead of a colon to reference a table's fields"
         "putting parens around this"]

        "unused local (.*)"
        ["fixing a typo so %s is used"
         "renaming the local to _%s"]

        "expected parameters"
        ["adding function parameters as a list of identifiers in brackets"]

        "unable to bind (.*)"
        ["replacing the %s with an identifier"]

        "expected rest argument before last parameter"
        ["moving & to right before the final identifier when destructuring"]

        "expected vararg as last parameter"
        ["moving the \"...\" to the end of the parameter list"]

        "expected symbol for function parameter: (.*)"
        ["changing %s to an identifier instead of a literal value"]

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
        ["finding where the identifier or value is missing"]

        "may only be used at compile time"
        ["moving this to inside a macro if you need to manipulate symbols/lists"
         "using square brackets instead of parens to construct a table"]

        "unexpected closing delimiter (.)"
        ["deleting %s"
         "adding matching opening delimiter earlier"]

        "mismatched closing delimiter (.), expected (.)"
        ["replacing %s with %s"
         "deleting %s"
         "adding matching opening delimiter earlier"]

        "expected even number of values in table literal"
        ["removing a key"
         "adding a value"]

        "expected whitespace before opening delimiter"
        ["adding whitespace"]

        "illegal character: (.)"
        ["deleting or replacing %s"
         "avoiding reserved characters like \", \\, ', ~, ;, @, `, and comma"]

        "could not read number (.*)"
        ["removing the non-digit character"
         "beginning the identifier with a non-digit if it is not meant to be a number"]

        "can't start multisym segment with a digit"
        ["removing the digit"
         "adding a non-digit before the digit"]

        "malformed multisym"
        ["ensuring each period or colon is not followed by another period or colon"]

        "method must be last component"
        ["using a period instead of a colon for field access"
         "removing segments after the colon"
         "making the method call, then looking up the field on the result"]})

(local unpack (or _G.unpack table.unpack))

(fn suggest [msg]
  (var suggestion nil)
  (each [pat sug (pairs suggestions)]
    (let [matches [(msg:match pat)]]
      (when (< 0 (# matches))
        (set suggestion (if (= :table (type sug))
                            (let [out []]
                              (each [_ s (ipairs sug)]
                                (table.insert out (s:format (unpack matches))))
                              out)
                            (sug matches))))))
  suggestion)

(fn read-line-from-file [filename line]
  (var bytes 0)
  (let [f (assert (io.open filename))
        _ (for [_ 1 (- line 1)]
            (set bytes (+ bytes 1 (# (f:read)))))
        codeline (f:read)]
    (f:close)
    (values codeline bytes)))

(fn read-line-from-source [source line]
  (var (lines bytes codeline) (values 0 0))
  (each [this-line (string.gmatch (.. source "\n") "(.-)\r?\n")]
    (set lines (+ lines 1))
    (when (= lines line)
      (set codeline this-line)
      (lua :break))
    (set bytes (+ bytes 1 (# this-line))))
  (values codeline bytes))

(fn read-line [filename line source]
  (if source
      (read-line-from-source source line)
      (read-line-from-file filename line)))

(fn friendly-msg [msg {: filename : line : bytestart : byteend} source]
  (let [(ok codeline bol eol) (pcall read-line filename line source)
        suggestions (suggest msg)
        out [msg ""]]
    ;; don't assume the file can be read as-is
    ;; (when (not ok) (print :err codeline))
    (when (and ok codeline)
      (table.insert out codeline))
    (when (and ok codeline bytestart byteend)
      (table.insert out (.. (string.rep " " (- bytestart bol 1)) "^"
                            (string.rep "^" (math.min (- byteend bytestart)
                                                      (- (+ bol (# codeline))
                                                         bytestart))))))
    (when (and ok codeline bytestart (not byteend))
      (table.insert out (.. (string.rep "-" (- bytestart bol 1)) "^"))
      (table.insert out ""))
    (when suggestions
      (each [_ suggestion (ipairs suggestions)]
        (table.insert out (: "* Try %s." :format suggestion))))
    (table.concat out "\n")))

(fn assert-compile [condition msg ast source]
  "A drop-in replacement for the internal assertCompile with friendly messages."
  (when (not condition)
    (let [{: filename : line} (ast-source ast)]
      (error (friendly-msg (: "Compile error in %s:%s\n  %s" :format
                              ;; still need fallbacks because backtick erases
                              ;; source data, and vararg has no source data
                              (or filename :unknown) (or line :?) msg)
                           (ast-source ast) source) 0)))
  condition)

(fn parse-error [msg filename line bytestart source]
  "A drop-in replacement for the internal parseError with friendly messages."
  (error (friendly-msg (: "Parse error in %s:%s\n  %s" :format filename line msg)
                       {: filename : line : bytestart} source) 0))

{: assert-compile : parse-error}
