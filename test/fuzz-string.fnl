(local fennel (require :fennel))
(local faith (require :test.faith))
(local load (or _G.loadstring load))

(fn lua-string-compiler [str]
  "Baseline implementation we're comparing against."
  ((assert (load (.. "return " str)))))

(fn fennel-string-compiler [str]
  "Our implementation. Round trip through the fennel compiler."
  ((assert (load (pick-values 1 (fennel.compile-string str))))))

(fn fennel-parser [str]
  "Our implementation. Going just through the parser"
  (let [[_ok loaded] [((fennel.parser str))]]
    loaded))

(fn into-single-line-string [str]
  "Gives a string that meets the following conditions:
   * The string is surrounded by \" marks
   * The string has no newlines \\n or carriage returns \\r
   * The string has no unescaped \" marks"
  (.. "\""
      (-> str
        ;; no newlines (so that lua can parse it)
        (: :gsub "[\r\n]" "")
        ;; all quotes must be escaped (so that it doesn't break out early)
        (: :gsub "\\*\""
           ;; make the number of slashes even
           #(when (= (% (length $) 2) 1)
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
                                        ;; you have to do this with floats because lua5.1 can't handle math.random calls with 0xFFFFFFFF
                                        (math.floor (* (math.random) (math.random) 0xFFFFFFFE)))
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

(fn get-string-parse-error [string-to-parse]
  (let [(old-success? old-out-str) (pcall lua-string-compiler string-to-parse)
        (new-success? new-out-str) (pcall fennel-parser string-to-parse)]
    (when (or (not= old-success? new-success?) ;; one accepts string, other rejects
              (and old-success? (not= old-out-str new-out-str))) ;; they both accept, but with different answers
      (.. "discrepancy parsing string: " string-to-parse "\n"
          "LUA:    print(fennel.view(" string-to-parse "))   -- "
          (if old-success? (fennel.view old-out-str)
                           old-out-str) "\n"
          "FENNEL: (print (fennel.view " string-to-parse ")) ;; "
          (if new-success? (fennel.view new-out-str)
                           new-out-str) "\n"))))


(fn test-fuzz-string-1 []
  ;; Comparing Fennel's parser to Lua's.
  ;; We want the same string features as Lua 5.3+/LuaJIT
  ;; Lua 5.2 and 5.1 don't support all the string escape codes,
  ;; so they're not useful as a baseline for this fuzz test.
  (if (or (and (= _VERSION "Lua 5.1") (not (pcall require :jit)))
          (= _VERSION "Lua 5.2"))
      (faith.skip)
      (let [verbose? (os.getenv "VERBOSE")
            seed (os.time)]
        (math.randomseed seed)
        (for [_ 1 (tonumber (or (os.getenv "FUZZ_COUNT") 256))]
          (let [s (generate-random-string)]
            (when verbose? (print s))
            (when (get-string-parse-error s)
              (local minimized (minimize s get-string-parse-error))
              (error (get-string-parse-error minimized))))))))

(fn get-string-compile-error [string-to-parse]
  (let [(old-success? old-out-str) (pcall fennel-string-compiler string-to-parse)
        (new-success? new-out-str) (pcall fennel-parser string-to-parse)]
    (when (or (not= old-success? new-success?) ;; one accepts string, other rejects
              (and old-success? (not= old-out-str new-out-str))) ;; they both accept, but with different answers
      (.. "discrepancy parsing string: " string-to-parse "\n"
          "LUA:    print(fennel.view(" string-to-parse "))   -- "
          (if old-success? (fennel.view old-out-str)
                           old-out-str) "\n"
          "FENNEL: (print (fennel.view " string-to-parse ")) ;; "
          (if new-success? (fennel.view new-out-str)
                           new-out-str) "\n"))))

(fn test-fuzz-string-2 []
  ;; Comparing Fennel's parser to Fennel.
  ;; In Fennel, a string is supposed to evaluate to itself.
  ;; This should work, regardless of Lua version
  (let [verbose? (os.getenv "VERBOSE")
        seed (os.time)]
    (math.randomseed seed)
    (for [_ 1 (tonumber (or (os.getenv "FUZZ_COUNT") 256))]
      (let [s (generate-random-string)]
        (when verbose? (print s))
        (when (get-string-compile-error s)
          (local minimized (minimize s get-string-compile-error))
          (error (get-string-compile-error minimized)))))))


{: test-fuzz-string-1
 : test-fuzz-string-2}
