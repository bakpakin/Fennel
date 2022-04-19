(local l (require :luaunit))

;; These are the slowest tests, so for now we just have a basic sanity check
;; to ensure that it compiles and can evaluate math.

(fn file-exists? [filename]
  (let [f (io.open filename)]
    (if f
        (do (f:close) true)
        false)))

(fn test-cli []
  ;; skip this if we haven't compiled the CLI
  (when (file-exists? "fennel")
    (l.assertEquals "6\n" (: (io.popen "./fennel --eval \"(+ 1 2 3)\"")
                             :read :*a))))

{: test-cli}
