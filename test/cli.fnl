(local t (require :test.faith))

(macro v [form] (view form))

;; These are the slowest tests, so for now we just have a basic sanity check
;; to ensure that it compiles and can evaluate math.

(local test-all? (os.getenv :FNL_TESTALL)) ; set by `make testall`

(local host-lua (match _VERSION
                  "Lua 5.1" (if _G.jit :luajit :lua5.1)
                  _ (.. :lua (_VERSION:sub 5))))

(fn file-exists? [filename]
  (let [f (io.open filename)]
    (when f (f:close) true)))

(λ peval [code ...]
  (let [cmd [(string.format "%s fennel --eval %q" host-lua code) ...]
        proc (io.popen (table.concat cmd " "))
        output (: (proc:read :*a) :gsub "\n$" "")]
    (values (proc:close) output))) ; proc:close gives exit status on 5.2+

(fn test-cli []
  ;; skip this if we haven't compiled the CLI or on Windows
  (when (and (file-exists? "fennel") (= "/" (package.config:sub 1 1)))
    (t.= [true "1\tnil\t2\tnil\tnil"]
         [(peval (v (values 1 nil 2 nil nil)))])))

(fn test-lua-flag []
  ;; skip this when cli is not compiled or not running tests with `make testall`
  (when (and test-all? (file-exists? "fennel"))
    (let [;; running io.popen for all 20 combinations of lua versions is slow,
          ;; so we'll just pick the next one in the list after host-lua
          lua-exec ((fn pick-lua [lua-vs i lua-v]
                      (if (= host-lua lua-v)
                          (. lua-vs (+ 1 (% i (# lua-vs)))) ; circular next
                          (pick-lua lua-vs (next lua-vs i))))
                    [:lua5.1 :lua5.2 :lua5.3 :lua5.4 :luajit])
          run #(pick-values 2 (peval $ (: "--lua %q" :format lua-exec)))]
      (t.= [true lua-exec]
           [(run (v (match (_VERSION:sub 5)
                      :5.1 (if _G.jit :luajit :lua5.1)
                      v-num (.. :lua v-num))))]
           (.. "should execute code in Lua runtime: " lua-exec))
      (let [(success? output) (run (v (do (print :test) (os.exit 1 true))))]
        (t.= "test" output)
        ;; pcall in Lua 5.1 doesn't give status with (proc:close)
        (t.= (if (= _VERSION "Lua 5.1") true nil)
             success?
             (.. "errors should cause failing exit status with --lua "
                 lua-exec))))))

(fn test-args []
  (when (and test-all? (file-exists? "fennel"))
    (t.= [true "-l"] [(peval  "(. arg 3)" "-l")])))

{: test-cli
 : test-lua-flag
 : test-args}
