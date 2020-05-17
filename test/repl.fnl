(local l (require :test.luaunit))
(local fennel (require :fennel))

(fn wrap-repl []
  (var repl-complete nil)
  (fn send []
    (var output [])
    (fennel.repl {:readChunk (fn []
                               (let [chunk (coroutine.yield output)]
                                 (set output [])
                                 (and chunk (.. chunk "\n"))))
                  :onValues #(table.insert output $)
                  :registerCompleter #(set repl-complete $)
                  :pp #$}))
  (local repl-send (coroutine.wrap send))
  (repl-send)
  (values repl-send repl-complete))

(fn assert-equal-unordered [a b msg]
  (l.assertEquals (table.sort a) (table.sort b) msg))

(fn test-completion []
  ;; Skip REPL tests in non-JIT Lua 5.1 only to avoid engine coroutine
  ;; limitation. Normally we want all tests to run on all versions, but in
  ;; this case the feature will work fine; we just can't use this method of
  ;; testing it on PUC 5.1, so skip it.
  (when (or (not= _VERSION "Lua 5.1") (= (type _G.jit) "table"))
    (let [(send comp) (wrap-repl)]
      (send "(local [foo foo-ba* moe-larry] [1 2 {:*curly* \"Why soitenly\"}])")
      (send "(local [!x-y !x_y] [1 2])")
      (assert-equal-unordered (comp "foo") ["foo" "foo-ba*"]
                              "local completion works & accounts for mangling")
      (assert-equal-unordered (comp "moe-larry") ["moe-larry.*curly*"]
                              (.. "completion traverses tables without mangling"
                                  " keys when input is \"tbl-var.\""))
      (assert-equal-unordered (send "(values !x-y !x_y)") [[1 2]]
                              "mangled locals do not collide")
      (assert-equal-unordered (comp "!x") ["!x_y" "!x-y"]
                              "completions on mangled locals do not collide"))))

{: test-completion}
