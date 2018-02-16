package = "fnl"
version = "scm-0"
source = {
    url = "git://github.com/bakpakin/fnl"
}
description = {
   summary = "Lisp that compiles to Lua",
   detailed = [[
A lisp-like language that compiles to efficient Lua. Combine 
meta-programming with Lua.]],
   homepage = "https://github.com/bakpakin/fnl",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1"
}
build = {
   type = "builtin",
   modules = {
       fnl = "fnl.lua"
   },
   install = {
       bin = {
           "fnl"
       }
   }
}
