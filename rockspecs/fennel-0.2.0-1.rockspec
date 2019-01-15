package = "fennel"
version = "0.2.0-1"
source = {
    url = "git://github.com/bakpakin/Fennel",
    tag = "0.2.0"
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
       fennelview = "fennelview.fnl.lua"
   },
   install = {
       bin = {
           "fennel"
       }
   }
}
