(local t (require :test.faith))
(local fennel (require :fennel))
(local utils (require :fennel.utils))

(fn == [a b msg]
  (t.= (fennel.view a) (fennel.view b) msg))

(fn test-basics []
  (let [cases {"\"\\\\\"" "\\"
               "\"abc\n\\240\"" "abc\n\240"
               "\"abc\\\"def\"" "abc\"def"
               "\"abc\\240\"" "abc\240"
               :150_000 150000
               "\"\n5.2\"" "\n5.2"
               ;; leading underscores aren't numbers
               "(let [_0 :zero] _0)" "zero"
               ;; backslash+newline becomes just a newline like Lua
               "\"foo\\\nbar\"" "foo\nbar"}
        (amp-ok? amp) ((fennel.parser (fennel.string-stream "&abc ")))]
    (each [code expected (pairs cases)]
      (t.= (fennel.eval code) expected code))
    (t.is amp-ok?)
    (t.= "&abc" (tostring amp))))

(fn test-comments []
  (let [(ok? ast) ((fennel.parser (fennel.string-stream ";; abc")
                                  "" {:comments true}))]
    (t.= :table (type (utils.comment? ast)))
    (t.= ";; abc" (tostring ast)))
  (let [code "{;; one\n1 ;; hey\n2 ;; what\n:is \"up\" ;; here\n}"
        (ok? ast) ((fennel.parser (fennel.string-stream code)
                                  "" {:comments true}))
        mt (getmetatable ast)]
    (== mt.comments
        {:keys {:is [(fennel.comment ";; what")]
                1 [(fennel.comment ";; one")]}
         :values {2 [(fennel.comment ";; hey")]}
         :last [(fennel.comment ";; here")]})
    (t.= mt.keys [1 :is])
    (t.is ok?))
  (let [code (table.concat ["{:this table"
                            ";; has a comment"
                            ";; with multiple lines in it!!!"
                            ":and \"we don't want to lose the comments\""
                            ";; so let's keep em; all the comments are"
                            ": good ; and we want them to be kept"
                            "}"] "\n")
        (ok? ast) ((fennel.parser (fennel.string-stream code)
                                  "" {:comments true}))]
    (t.is ok? ast)
    (== (. (getmetatable ast) :comments :keys)
        {:and [(fennel.comment ";; has a comment")
               (fennel.comment ";; with multiple lines in it!!!")]
         :good [(fennel.comment ";; so let's keep em; all the comments are")]})
    (== (. (getmetatable ast) :comments :last)
        [(fennel.comment "; and we want them to be kept")]))
  (let [(_ ast) ((fennel.parser "(do\n; a\n(print))" "-" {:comments true}))]
    (== ["do" "; a" "(print)"] (icollect [_ x (ipairs ast)] (tostring x)))
    ;; top-level version
    (== ["do" "; a" "(print)"]
        (icollect [_ x (fennel.parser ":do\n; a\n(print)" "-" {:comments true})]
          (tostring x)))))

(fn test-control-codes []
  (for [i 1 31]
    (let [code (.. "\"" (string.char i) (tostring i) "\"")
          expected (.. (string.char i) (tostring i))]
      (t.= (fennel.eval code) expected
           (.. "Failed to parse control code " i)))))

(fn test-prefixes []
  (let [code "\n\n`(let\n  ,abc #(+ 2 3))"
        (ok? ast) ((fennel.parser code))]
    (t.is ok?)
    (t.= ast.line 3)
    (t.= (. ast 2 2 :line) 4)
    (t.= (. ast 2 3 :line) 4)))

(fn line-col [{: line : col}] [line col])

(fn test-source-meta []
  (let [code "\n\n  (  let [x 5 \n        y {:z 66}]\n (+ x y.z))"
        (ok? ast) ((fennel.parser code))
        [let* [_ _ _ tbl]] ast
        [_ seq] ast]
    (t.is ok?)
    (t.= (line-col ast) [3 2] "line and column on lists")
    (t.= (line-col let*) [3 5] "line and column on symbols")
    (t.= (line-col (getmetatable seq)) [3 9]
         "line and column on sequences")
    (t.= (line-col (getmetatable tbl)) [4 10]
         "line and column on tables"))
  (let [code "abc\nxyz"
        parser (fennel.parser code)
        (ok? abc) (parser)
        (ok2? xyz) (parser)]
    (t.is (and ok? ok2?))
    (t.= (tostring abc) (code:sub abc.bytestart abc.byteend))
    (t.= (tostring xyz) (code:sub xyz.bytestart xyz.byteend))
    ;; but wait! sub is tolerant of going on beyond the last byte!
    (t.= (length code) xyz.byteend))
  ;; now let's try that again with tables
  (let [code "[1]\n{a 4} (true)"
        parser (fennel.parser code)
        (ok? seq) (parser)
        (ok2? kv) (parser)
        (ok3? list) (parser)
        seq-source (getmetatable seq)
        kv-source (getmetatable kv)]
    (t.is (and ok? ok2? ok3?))
    (t.= (fennel.view seq) (code:sub seq-source.bytestart seq-source.byteend))
    (t.= (fennel.view kv) (code:sub kv-source.bytestart kv-source.byteend))
    (t.= (fennel.view list) (code:sub list.bytestart list.byteend))
    ;; but wait! sub is tolerant of going on beyond the last byte!
    (t.= (length code) list.byteend)))

(fn test-plugin-hooks []
  (var parse-error-called nil)
  (let [code "(there is a parse error here (((("
        plugin {:versions [(: fennel.version :gsub "-dev" "")]
                :parse-error
                (fn parse-error [msg filename line col source root-reset]
                  (set parse-error-called true))}
        (ok? ok2? ast) (pcall (fennel.parser code "" {:plugins [plugin]}))]
    (t.is (not ok?) "parse error is expected")
    (t.is parse-error-called "plugin wasn't called")))

{: test-basics
 : test-control-codes
 : test-comments
 : test-prefixes
 : test-source-meta
 : test-plugin-hooks}
