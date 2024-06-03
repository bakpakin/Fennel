package = "fennel"
version = "scm-2"
source = {
    url = "git://github.com/bakpakin/Fennel",
}
description = {
   summary = "Lisp that compiles to Lua",
   detailed = [[
A lisp-like language that compiles to efficient Lua. Combine
meta-programming with Lua.]],
   homepage = "https://fennel-lang.org/",
   license = "MIT",
}
dependencies = {
   "lua >= 5.1"
}
build = {
   type = "make",
   build_variables = {
       -- Warning: variable CFLAGS was not passed in build_variables
       CFLAGS = "$(CFLAGS)",
       LUA = "$(LUA)",
   },
   install_variables = {
       PREFIX = "$(PREFIX)",
       BINDIR = "$(BINDIR)",
       LUA_LIB_DIR = "$(LUADIR)",
       MAN_DIR = "$(PREFIX)",
   },
}
