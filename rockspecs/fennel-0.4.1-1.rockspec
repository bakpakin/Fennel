-- -*- lua -*-

package = "fennel"
version = "0.4.1-1"
source = {
    url = "git+https://github.com/bakpakin/Fennel",
    tag = "0.4.1"
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
       fennelview = "fennelview.lua",
       fennelfriend = "fennelfriend.lua",
       fennelbinary = "fennelbinary.fnl"
   },
   install = {
       bin = {
           -- use the old launcher for now; once we have a chance to mess about
           -- with the build we can try compiling the new launcher with the
           -- old; ideally during packaging time we would compile the bin/fennel
           -- script, but luarocks docs do not explain how to do this.
           fennel = "old_launcher.lua"
       }
   }
}
