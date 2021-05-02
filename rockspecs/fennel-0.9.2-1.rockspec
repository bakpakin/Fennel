-- -*- lua -*-

package = "fennel"
local fennel_version = "0.9.2"
version = fennel_version .. "-1"

source = {
    -- use URL to a pre-built release archive so the standalone launcher can be used
    url = "https://fennel-lang.org/downloads/fennel-" .. fennel_version .. ".tar.gz",
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
   },
   install = {
       bin = {
           fennel = "fennel"
       },
   }
}
