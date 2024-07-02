(local fennel (require :fennel))
(local faith (require :test.faith))

(fn lua-parser [str]
  "Baseline implementation we're comparing against.
   Should give the same results as fennel-parser when called on single-line strings"
  ((assert (load (.. "return " str)))))

(fn fennel-parser [str]
  "Our implementation.
   Should give the same results as lua-parser when called on single-line-strings"
  ((fennel.parser str)))

(fn into-single-line-string [str]
  "Gives a string that meets the following conditions:
   * The string is surrounded by \" marks
   * The string has no newlines \\n or carriage returns \\r
   * The string has no unescaped \" marks"
  (.. "\""
      (-> str
        (: :gsub "\n" "")
        (: :gsub "\r" "")
        (: :gsub "\\*\""
           ;; If the length is odd, we need to delete a character
           ;; to make sure the quote doesn't end the string early.
           #(if (= (% (length $) 2) 1)
              ($:sub 2))))
      "\""))

(fn generate-random-string []
  "generate a random single-line string to be parsed by lua or fennel"
  (into-single-line-string
    (table.concat
      (fcollect [_ 1 (math.random 20)]
        (if (< (math.random) 0.5)
            (let [c "{}\t'\"uxabfnrtv0123456789 "
                  n (math.random (length c))]
              (c:sub n n))
            (< (math.random) 0.5)
            (string.char (math.random 0 255))
            (< (math.random) 0.5)
            (.. "\\u{" (if (< (math.random) 0.9)
                         ;; valid
                         (string.format "%x"
                                        ;; weighted toward 0
                                        (math.random 0 (math.random 1 0xFFFFFFFF)))
                         ;; invalid
                         (table.concat
                           (fcollect [_ 0 (math.random 10)]
                              (string.char (math.random 0 255)))))
                "}")
            (< (math.random) 0.5)
            (.. "\\" (math.random 300))
            (< (math.random) 0.5)
            " "
            "\\")))))

(local remove-size [8 2 1])
(fn minimize [str still-has-property?]
  "repeatedly find smaller and smaller `str` where (still-has-property? str)"
  (case (faccumulate [reduced nil
                      i 2 (- (length str) 1)
                      &until reduced]
              (accumulate [reduced nil
                           _ num-to-remove (ipairs remove-size)
                           &until reduced]
                (let [reduced (into-single-line-string
                                (.. (str:sub 2 (- i 1))
                                    (str:sub (+ i num-to-remove) -2)))]
                  (if (still-has-property? reduced) reduced))))
        better (minimize better still-has-property?)
        _ str))

(fn get-error [string-to-parse]
  (let [(old-success? old-out-str) (pcall lua-parser string-to-parse)
        (new-success? s2 new-out-str) (pcall fennel-parser string-to-parse)]
    (when (or (not= old-success? new-success?) ;; one accepts string, other rejects
              (and old-success? (not= old-out-str new-out-str))) ;; they both accept, but with different answers
      (.. "discrepancy parsing string: " string-to-parse "\n"
          "LUA:    print(fennel.view(" string-to-parse "))   -- "
          (if old-success? (fennel.view old-out-str)
                           old-out-str) "\n"
          "FENNEL: (print (fennel.view " string-to-parse ")) ;; "
          (if new-success? (fennel.view new-out-str)
                           (s2:gsub "\n.*" ""))))))


(fn test-fuzz-string []
  ;; We want the same string features as Lua 5.3+/LuaJIT
  (if (not (or (= _VERSION "Lua 5.4")
               (= _VERSION "Lua 5.3")
               (pcall require :jit)))
      (faith.skip)
      (let [verbose? (os.getenv "VERBOSE")]
        (for [_ 1 (tonumber (or (os.getenv "FUZZ_COUNT") 256))]
          (let [s (generate-random-string)]
            (when verbose? (print s))
            (when (get-error s)
              (local minimized (minimize s get-error))
              (error (get-error minimized))))))))

{: test-fuzz-string}
