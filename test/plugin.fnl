(local fennel (require :fennel))
(local l (require :test.luaunit))

(var ran-require-macros false)

(local plugin
  {:name :test-plugin
   :version fennel.version
   :require-macros (fn [ast scope]
                     (set ran-require-macros true))})

(local options {:plugins [plugin]})

(fn test-require-macros []
  "Check require-macros hook is trigered"
  (let [src "(import-macros m :test.macros)"]
    (l.assertEquals ran-require-macros false)))

{: test-require-macros}
