(local l (require :test.luaunit))
(local fennel (require :fennel))
(local utils (require :fennel.utils))

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
      (l.assertEquals (fennel.eval code {:correlate true}) expected code))
    (l.assertTrue amp-ok?)
    (l.assertEquals "&abc" (tostring amp))))

(fn test-comments []
  (let [(ok ast) ((fennel.parser (fennel.string-stream ";; abc")
                                 "" {:comments true}))]
    (l.assertTable (utils.comment? ast))
    (l.assertEquals ";; abc" (tostring ast))))

{: test-basics
 : test-comments}
