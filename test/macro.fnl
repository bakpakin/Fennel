(local l (require :test.luaunit))
(local fennel (require :fennel))

(fn test-arrows []
  (let [cases {"(-> (+ 85 21) (+ 1) (- 99))" 8
               "(-> 1234 (string.reverse) (string.upper))" "4321"
               "(-> 1234 string.reverse string.upper)" "4321"
               "(->> (+ 85 21) (+ 1) (- 99))" (- 8)
               "(-?> [:a :b] (table.concat \" \"))" "a b"
               "(-?> {:a {:b {:c :z}}} (. :a) (. :b) (. :c))" "z"
               "(-?> {:a {:b {:c :z}}} (. :a) (. :missing) (. :c))" nil
               "(-?>> \" \" (table.concat [:a :b]))" "a b"
               "(-?>> :w (. {:w :x}) (. {:x :missing}) (. {:y :z}))" nil
               "(-?>> :w (. {:w :x}) (. {:x :y}) (. {:y :z}))" "z"}]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code) expected code))))

(fn test-eval-compiler []
  (let [reverse "(eval-compiler
                   (tset _SPECIALS \"reverse-it\" (fn [ast scope parent opts]
                     (tset ast 1 \"do\")
                     (for [i 2 (math.ceil (/ (length ast) 2))]
                       (let [a (. ast i) b (. ast (- (length ast) (- i 2)))]
                         (tset ast (- (length ast) (- i 2)) a)
                         (tset ast i b)))
                     (_SPECIALS.do ast scope parent opts))))
                 (reverse-it 1 2 3 4 5 6)"
        nest-quote "(eval-compiler (set tbl.nest ``nest)) (tostring tbl.nest)"
        env (setmetatable {:tbl {}} {:__index _G})]
    (l.assertEquals (fennel.eval reverse) 1)
    (l.assertEquals (fennel.eval nest-quote {:compiler-env env :env env})
                    "(quote nest)")
    (fennel.eval "(eval-compiler (set _SPECIALS.reverse-it nil))")))

(fn test-import-macros []
  (let [multigensym "(import-macros m :test.macros) (m.multigensym)"
        inc "(import-macros m :test.macros) (var x 1) (m.inc! x 2) (m.inc! x) x"
        inc2 "(import-macros test :test.macros {:inc INC} :test.macros)
              (INC (test.inc 5))"
        rename "(import-macros {:defn1 defn : ->1} :test.macros)
                (defn join [sep ...] (table.concat [...] sep))
                (join :: :num (->1 5 (* 2) (+ 8)))"
        unsandboxed "(import-macros {: unsandboxed} :test.macros)
                     (unsandboxed)"]
    (l.assertEquals (fennel.eval multigensym) 519)
    (l.assertEquals (fennel.eval inc) 4)
    (l.assertEquals (fennel.eval inc2) 7)
    (l.assertEquals (fennel.eval rename) "num:18")
    (l.assertEquals (fennel.eval unsandboxed {:compiler-env _G})
                    "[\"no\" \"sandbox\"]") ))

(fn test-require-macros []
  (let [arrow "(require-macros \"test.macros\") (->1 9 (+ 2) (* 11))"
        defn1 "(require-macros \"test.macros\")
               (defn1 hui [x y] (global z (+ x y))) (hui 8 4) z"]
    (l.assertEquals (fennel.eval arrow) 121)
    (l.assertEquals (fennel.eval defn1) 12)))

(fn test-inline-macros []
  (let [cases {"(macro five [] 5) (five)" 5
               "(macro greet [] :Hi!) (greet)" "Hi!"
               "(macro seq? [expr] (sequence? expr)) (seq? [65])" [65]
               "(macros {:m (fn [y] `(let [xa# 1] (+ xa# ,y)))}) (m 4)" 5
               "(macros {:plus (fn [x y] `(+ ,x ,y))}) (plus 9 9)" 18
               "(macros {:when2 (fn [c val] `(when ,c ,val))})
                (when2 true :when2)" "when2"
               "(macros {:when3 (fn [c val] `(do (when ,c ,val)))})
                (when3 true :when3)" "when3"
               "(macros {:x (fn [] `(fn [...] (+ 1 1)))}) ((x))" 2
               "(macros {:yes (fn [] true) :no (fn [] false)}) [(yes) (no)]"
               [true false]}
        g-using "(macros {:m (fn [x] (set _G.sided x))}) (m 952) _G.sided"]
    (each [code expected (pairs cases)]
      (l.assertEquals (fennel.eval code) expected code))
    (l.assertEquals (fennel.eval g-using {:compiler-env _G}) 952)))

(fn test-macrodebug []
  (let [eval-normalize #(-> (pick-values 1 (fennel.eval $1 $2))
                            (: :gsub "table: 0x[0-9a-f]+" "#<TABLE>")
                            (: :gsub "\n%s*" ""))
        code "(macrodebug (when (= 1 1) (let [x :X] {: x})) true)"
        expected-fennelview "(if (= 1 1) (do (let [x \"X\"] {:x x})))"
        expected-no-fennelview "(if (= 1 1) (do (let #<TABLE> #<TABLE>)))"]
    (l.assertEquals (eval-normalize code) expected-fennelview)
    (let [fennelview package.loaded.fennelview
          fennel-path fennel.path
          package-path package.path]
      (set (package.loaded.fennelview fennel.path package.path)
           (values nil "" ""))
      (l.assertEquals (eval-normalize code) expected-no-fennelview)
      (set (package.loaded.fennelview fennel.path package.path)
           (values fennelview fennel-path package-path)))))

{: test-arrows
 : test-import-macros
 : test-require-macros
 : test-eval-compiler
 : test-inline-macros
 : test-macrodebug}
