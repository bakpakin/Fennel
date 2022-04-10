(global package :fennel)

(local fennel-version (eval-compiler (os.getenv "VERSION")))

(global version (.. fennel-version "-1"))

(global source {:url (.. "https://fennel-lang.org/downloads/fennel-"
                         fennel-version :.tar.gz)})

(global description {:summary "A lisp that compiles to Lua"
                     :detailed (.. "Get your parens on--write macros and "
                                   "homoiconic code on the Lua runtime!")
                     :license :MIT
                     :homepage "https://fennel-lang.org/"})

(global dependencies ["lua >= 5.1"])

(global build {:type :builtin
               :install {:bin {:fennel "fennel"}}
               :modules {:fennel "fennel.lua"}})
