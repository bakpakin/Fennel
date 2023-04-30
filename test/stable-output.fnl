(local l (require :test.luaunit))

(local lua-exe (. arg -1))

(fn file-exists? [filename]
  (let [f (io.open filename)]
    (when f (f:close) true)))

(λ pcompile [code]
  (let [run-arg "(let [out ((. (require :fennel) :compile-string) (. arg 3))] (print out))"
        proc (io.popen (: "%q ./fennel -e '%s' %q" :format lua-exe run-arg code))
        output (proc:read :*a)]
    (values (proc:close) output))) ; proc:close gives exit status

(λ pcompile-line [code]
  (let [(ok out) (pcompile code)]
   (values ok (pick-values 1 (out:gsub "^return%s*([^\r\n]+).*" "%1")))))

(fn test-stable-kv-output []
  (let [add-keys "(macro add-keys [t ...]
  (faccumulate [t t i 1 (select :# ...) 2]
    (let [(k v) (select i ...)] (doto t (tset k v)))))"
        cases [["{:a 1 :b 2 :2 :s2 2 :n2 true :btrue :true :strue}"
                "{a = 1, b = 2, [\"2\"] = \"s2\", [2] = \"n2\", [true] = \"btrue\", [\"true\"] = \"strue\"}"
                "original table literal key order should be preserved"]
               [(.. add-keys "\n"
                    "(add-keys {:c 3 :a 1} :b 2 :d 4 :2 :b 2 :b1 [9] :tbl9 true :t :true :t1)")
                "{c = 3, a = 1, [2] = \"b1\", [true] = \"t\", [\"2\"] = \"b\", b = 2, d = 4, [\"true\"] = \"t1\", [{9}] = \"tbl9\"}"
                "added keys should be sorted: numbers>booleans>strings>tables>other"]]]
    (each [_ [input expected msg] (ipairs cases)]
      (l.assertEquals [(pcompile-line input)] [true expected] msg))))

{: test-stable-kv-output}
