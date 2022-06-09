(local l (require :test.luaunit))

;; These are the slowest tests, so for now we just have a basic sanity check
;; to ensure that it compiles and can evaluate math.

(local *testall* (os.getenv :FNL_TESTALL)) ; set by `make testall`

(fn file-exists? [filename]
  (let [f (io.open filename)]
    (when f (f:close) true)))

(λ peval [code ...]
  (let [cmd [(string.format "./fennel --eval %q" code) ...]
        proc (io.popen (table.concat cmd " "))
        output (: (proc:read :*a) :gsub "\n$" "")]
    (values (proc:close) output))) ; proc:close gives exit status

(fn test-cli []
  ;; skip this if we haven't compiled the CLI
  (when (file-exists? "./fennel")
    (l.assertEquals [(peval "(+ 1 2 3)")] [true "6"])))

(fn test-lua-flag []
  ;; skip this when cli is not compiled or not running tests with `make testall`
  (when (and *testall* (file-exists? :./fennel))
    (let [;; running io.popen for all 20 combinations of lua versions is slow,
          ;; so we'll just pick the next one in the list after host-lua
          host-lua (match _VERSION
                          "Lua 5.1" (if _G.jit :luajit :lua5.1)
                          _ (.. :lua (_VERSION:sub 5)))
          lua-exec ((fn pick-lua [lua-vs i lua-v]
                      (if (= host-lua lua-v)
                        (. lua-vs (+ 1 (% i (# lua-vs)))) ; circular next
                        (pick-lua lua-vs (next lua-vs i))))
                    [:lua5.1 :lua5.2 :lua5.3 :lua5.4 :luajit])
          run #(pick-values 2 (peval $ (: "--lua %q" :format lua-exec)))]
      (l.assertEquals [(run "(match (_VERSION:sub 5)
                              :5.1 (if _G.jit :luajit :lua5.1)
                              v-num (.. :lua v-num))")]
                      [true lua-exec]
                      (.. "should execute code in Lua runtime: " lua-exec))
      (l.assertEquals
        [(run "(print :test) (os.exit 1 true)")]
        ;; pcall in Lua 5.1 doesn't give status with (proc:close)
        {1 (if (= _VERSION "Lua 5.1") true nil) 2 "test"}
        (.. "errors should cause failing exit status with --lua " lua-exec)))))

{: test-cli : test-lua-flag}
