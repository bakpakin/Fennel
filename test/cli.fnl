(local l (require :test.luaunit))

;; These are the slowest tests, so for now we just have a basic sanity check
;; to ensure that it compiles and can evaluate math.

(fn test-cli []
  (l.assertEquals "6\n"
                  (: (io.popen "./fennel --eval \"(+ 1 2 3)\"") :read :*a)))

{: test-cli}
