;; This module contains functions that handle errors during parsing and
;; compilation and attempt to enrich them by suggesting fixes.
;; It can be disabled to fall back to the regular terse errors.

(local utils (require :fennel.utils))
(local (utf8-ok? utf8) (pcall require :utf8))

(local suggestions
       {"unexpected multi symbol (.*)" ["removing periods or colons from %s"]
        "use of global (.*) is aliased by a local" ["renaming local %s"
                                                    "refer to the global using _G.%s instead of directly"]
        "local (.*) was overshadowed by a special form or macro" ["renaming local %s"]
        "global (.*) conflicts with local" ["renaming local %s"]
        "expected var (.*)" ["declaring %s using var instead of let/local"
                             "introducing a new local instead of changing the value of %s"]
        "expected macros to be table" ["ensuring your macro definitions return a table"]
        "expected each macro to be function" ["ensuring that the value for each key in your macros table contains a function"
                                              "avoid defining nested macro tables"]
        "macro not found in macro module" ["checking the keys of the imported macro module's returned table"]
        "macro tried to bind (.*) without gensym" ["changing to %s# when introducing identifiers inside macros"]
        "unknown identifier in strict mode: (.*)" ["looking to see if there's a typo"
                                                   "using the _G table instead, eg. _G.%s if you really want a global"
                                                   "moving this code to somewhere that %s is in scope"
                                                   "binding %s as a local in the scope of this code"]
        "expected a function.* to call" ["removing the empty parentheses"
                                         "using square brackets if you want an empty table"]
        "cannot call literal value" ["checking for typos"
                                     "checking for a missing function name"]
        "unexpected vararg" ["putting \"...\" at the end of the fn parameters if the vararg was intended"]
        "multisym method calls may only be in call position" ["using a period instead of a colon to reference a table's fields"
                                                              "putting parens around this"]
        "unused local (.*)" ["renaming the local to _%s if it is meant to be unused"
                             "fixing a typo so %s is used"
                             "disabling the linter which checks for unused locals"]
        "expected parameters" ["adding function parameters as a list of identifiers in brackets"]
        "unable to bind (.*)" ["replacing the %s with an identifier"]
        "expected rest argument before last parameter" ["moving & to right before the final identifier when destructuring"]
        "expected vararg as last parameter" ["moving the \"...\" to the end of the parameter list"]
        "expected symbol for function parameter: (.*)" ["changing %s to an identifier instead of a literal value"]
        "could not compile value of type " ["debugging the macro you're calling to return a list or table"]
        "expected local" ["looking for a typo"
                          "looking for a local which is used out of its scope"]
        "expected body expression" ["putting some code in the body of this form after the bindings"]
        "expected binding and iterator" ["making sure you haven't omitted a local name or iterator"]
        "expected binding sequence" ["placing a table here in square brackets containing identifiers to bind"]
        "expected even number of name/value bindings" ["finding where the identifier or value is missing"]
        "may only be used at compile time" ["moving this to inside a macro if you need to manipulate symbols/lists"
                                            "using square brackets instead of parens to construct a table"]
        "unexpected closing delimiter (.)" ["deleting %s"
                                            "adding matching opening delimiter earlier"]
        "mismatched closing delimiter (.), expected (.)" ["replacing %s with %s"
                                                          "deleting %s"
                                                          "adding matching opening delimiter earlier"]
        "expected even number of values in table literal" ["removing a key"
                                                           "adding a value"]
        "expected whitespace before opening delimiter" ["adding whitespace"]
        "invalid character: (.)" ["deleting or replacing %s"
                                  "avoiding reserved characters like \", \\, ', ~, ;, @, `, and comma"]
        "could not read number (.*)" ["removing the non-digit character"
                                      "beginning the identifier with a non-digit if it is not meant to be a number"]
        "can't start multisym segment with a digit" ["removing the digit"
                                                     "adding a non-digit before the digit"]
        "malformed multisym" ["ensuring each period or colon is not followed by another period or colon"]
        "method must be last component" ["using a period instead of a colon for field access"
                                         "removing segments after the colon"
                                         "making the method call, then looking up the field on the result"]
        "$ and $... in hashfn are mutually exclusive" ["modifying the hashfn so it only contains $... or $, $1, $2, $3, etc"]
        "tried to reference a macro at runtime" ["renaming the macro so as not to conflict with locals"]
        "tried to reference a special form at runtime" ["wrapping the special in a function if you need it to be first class"]
        "missing subject" ["adding an item to operate on"]
        "expected even number of pattern/body pairs" ["checking that every pattern has a body to go with it"
                                                      "adding _ before the final body"]
        "expected at least one pattern/body pair" ["adding a pattern and a body to execute when the pattern matches"]

        "unexpected arguments" ["removing an argument"
                                "checking for typos"]
        "unexpected iterator clause" ["removing an argument"
                                      "checking for typos"]})

(local unpack (or table.unpack _G.unpack))

(fn suggest [msg]
  (var suggestion nil)
  (each [pat sug (pairs suggestions)]
    (let [matches [(msg:match pat)]]
      (when (< 0 (length matches))
        (set suggestion (if (= :table (type sug))
                            (let [out []]
                              (each [_ s (ipairs sug)]
                                (table.insert out (s:format (unpack matches))))
                              out)
                            (sug matches))))))
  suggestion)

(fn read-line [filename line ?source]
  (if ?source
      (let [matcher (string.gmatch (.. ?source "\n") "(.-)(\r?\n)")]
        (for [_ 2 line] (matcher))
        (matcher))
      (with-open [f (assert (io.open filename))]
        (for [_ 2 line] (f:read))
        (f:read))))

(fn sub [str start end]
  "Try to take the substring based on characters, not bytes."
  (if (< end start) ""
      utf8-ok?
      (string.sub str (utf8.offset str start)
                  (- (or (utf8.offset str (+ end 1)) (+ (utf8.len str) 1)) 1))
      (string.sub str start (math.min end (str:len)))))

(fn highlight-line [codeline col ?endcol]
  (let [endcol (or ?endcol col)
        eol (if utf8-ok? (utf8.len codeline) (string.len codeline))]
    (.. (sub codeline 1 col) "\027[7m"
        (sub codeline (+ col 1) (+ endcol 1))
        "\027[0m" (sub codeline (+ endcol 2) eol))))

(fn friendly-msg [msg {: filename : line : col : endcol} source]
  (let [(ok codeline) (pcall read-line filename line source)
        out [msg ""]]
    ;; don't assume the file can be read as-is
    ;; (when (not ok) (print :err codeline))
    (when (and ok codeline)
      (if col
          (table.insert out (highlight-line codeline col endcol))
          (table.insert out codeline)))
    (each [_ suggestion (ipairs (or (suggest msg) []))]
      (table.insert out (: "* Try %s." :format suggestion)))
    (table.concat out "\n")))

(fn assert-compile [condition msg ast source]
  "A drop-in replacement for the internal assert-compile with friendly messages."
  (when (not condition)
    (let [{: filename : line : col} (utils.ast-source ast)]
      (error (friendly-msg (: "Compile error in %s:%s:%s\n  %s" :format
                              ;; still need fallbacks because backtick erases
                              ;; source and macros can generate source-less ast
                              (or filename :unknown) (or line "?")
                              (or col "?") msg)
                           (utils.ast-source ast) source) 0)))
  condition)

(fn parse-error [msg filename line col source]
  "A drop-in replacement for the internal parse-error with friendly messages."
  (error (friendly-msg (: "Parse error in %s:%s:%s\n  %s" :format
                          filename line col msg)
                       {: filename : line : col} source) 0))

{: assert-compile : parse-error}
