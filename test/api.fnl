(local l (require :luaunit))

(local expected {
  :comment         "function"
  :comment?        "function"
  :compile         "function"
  :compile-stream  "function"
  :compile-string  "function"
  :doc             "function"
  :dofile          "function"
  :eval            "function"
  :list            "function"
  :list?           "function"
  :load-code       "function"
  :macro-loaded    "table"
  :macro-path      "string"
  :macro-searchers "table"
  :make-searcher   "function"
  :metadata        "table"
  :parser          "function"
  :path            "string"
  :repl            "function"
  :runtime-version "function"
  :search-module   "function"
  :searcher        "function"
  :sequence        "function"
  :sequence?       "function"
  :sym             "function"
  :sym-char?       "function"
  :sym?            "function"
  :syntax          "function"
  :traceback       "function"
  :varg            "function"
  :varg?           "function"
  :version         "string"
  :view            "function"})

(local expected-aliases {
  :compileStream  "function"
  :compileString  "function"
  :loadCode       "function"
  :macroLoaded    "table"
  :macroPath      "string"
  :macroSearchers "table"
  :makeSearcher   "function"
  :runtimeVersion "function"
  :searchModule   "function"})

(local expected-deprecations {
  :compile1      "function"
  :gensym        "function"
  :granulate     "function"
  :make_searcher "function"
  :mangle        "function"
  :scope         "function"
  :string-stream "function"
  :stringStream  "function"
  :unmangle      "function"})

(fn test-api-exposure []
  (let [fennel (require :fennel) current {}]

    (each [key value (pairs fennel)]
      (tset current key (type value)))

    (each [key kind (pairs expected)]
      (l.assertNotNil (. fennel key) (.. "expect fennel." key " to exists"))
      (l.assertEquals
        (type (. fennel key)) kind
        (.. "expect fennel." key " to be \"" kind "\"")))

    (each [key kind (pairs expected-aliases)]
      (l.assertNotNil (. fennel key) (.. "expect alias fennel." key " to exists"))
      (l.assertEquals
        (type (. fennel key)) kind
        (.. "expect alias fennel." key " to be \"" kind "\"")))

    (each [key kind (pairs expected-deprecations)]
      (l.assertNotNil (. fennel key) (.. "expect deprecated fennel." key " to exists"))
      (l.assertEquals
        (type (. fennel key)) kind
        (.. "expect deprecated fennel." key " to be \"" kind "\"")))

    (each [key value (pairs fennel)]
      (l.assertNotNil
        (or (. expected key)
            (. expected-aliases key)
            (. expected-deprecations key))
        (.. "fennel." key " not expected to be in the public api")))))

{: test-api-exposure}
