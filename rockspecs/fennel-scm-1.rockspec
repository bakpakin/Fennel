package = "fennel"
version = "scm-1"
source = {
    url = "git://github.com/bakpakin/Fennel"
}
description = {
   summary = "Lisp that compiles to Lua",
   detailed = [[
A lisp-like language that compiles to efficient Lua. Combine
meta-programming with Lua.]],
   homepage = "https://fennel-lang.org/",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1"
}
build = {
   type = "builtin",
   modules = {
       fennel = "fennel.lua",
       fennelview = "fennelview.fnl",
   },
   install = {
       bin = {
           "fennel"
       }
   }
}
