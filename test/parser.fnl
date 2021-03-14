(local l (require :test.luaunit))
(local fennel (require :fennel))
(local utils (require :fennel.utils))

(fn == [a b msg]
  (l.assertEquals (fennel.view a) (fennel.view b) msg))

(fn test-basics []
  (let [cases {"\"\\\\\"" "\\"
               "\"abc\n\\240\"" "abc\n\240"
               "\"abc\\\"def\"" "abc\"def"
               "\"abc\\240\"" "abc\240"
               :150_000 150000
               "\"\n5.2\"" "\n5.2"
               ;; leading underscores aren't numbers
               "(let [_0 :zero] _0)" "zero"}
        (amp-ok? amp) ((fennel.parser (fennel.string-stream "&abc ")))]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code) expected code))
    (l.assertTrue amp-ok?)
    (l.assertEquals "&abc" (tostring amp))))

(fn test-comments []
  (let [(ok? ast) ((fennel.parser (fennel.string-stream ";; abc")
                                  "" {:comments true}))]
    (l.assertTable (utils.comment? ast))
    (l.assertEquals ";; abc" (tostring ast)))
  (let [code "{;; one\n1 ;; hey\n2 ;; what\n:is \"up\" ;; here\n}"
        (ok? ast) ((fennel.parser (fennel.string-stream code)
                                  "" {:comments true}))
        mt (getmetatable ast)]
    (== mt.comments
        {:keys {:is [(fennel.comment ";; what")]
                1 [(fennel.comment ";; one")]}
         :values {2 [(fennel.comment ";; hey")]}
         :last [(fennel.comment ";; here")]})
    (l.assertEquals mt.keys [1 :is])
    (l.assertTrue ok?))
  (let [code "{:this table
        ;; has a comment
        ;; with multiple lines in it!!!
        :and \"we don't want to lose the comments\"
        ;; so let's keep them; all the comments are good and we want them
        ;; to be kept
        }"
        (ok? ast) ((fennel.parser (fennel.string-stream code)
                                  "" {:comments true}))]
    (l.assertTrue ok? ast)
    (== (. (getmetatable ast) :comments :keys)
        {:and [(fennel.comment ";; has a comment")
               (fennel.comment ";; with multiple lines in it!!!")]})
    (== (. (getmetatable ast) :comments :last)
        [(fennel.comment (.. ";; so let's keep them; all the comments "
                             "are good and we want them"))
         (fennel.comment ";; to be kept")])))

(fn test-control-codes []
  (for [i 1 31]
    (let [code (.. "\"" (string.char i) (tostring i) "\"")
          expected (.. (string.char i) (tostring i))]
       (l.assertEquals (fennel.eval code) expected
                      (.. "Failed to parse control code " i)))))

(fn test-prefixes []
  (let [code "\n\n`(let\n  ,abc #(+ 2 3))"
        (ok? ast) ((fennel.parser (fennel.string-stream code)))]
    (l.assertEquals ast.line 3)
    (l.assertEquals (. ast 2 2 :line) 4)
    (l.assertEquals (. ast 2 3 :line) 4)))

{: test-basics
 : test-control-codes
 : test-comments
 : test-prefixes}
