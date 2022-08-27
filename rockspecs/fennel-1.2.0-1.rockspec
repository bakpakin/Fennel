package = "fennel"
local fennel_version = "1.2.0"
version = (fennel_version .. "-1")
source = {url = ("https://fennel-lang.org/downloads/fennel-" .. fennel_version .. ".tar.gz")}
description = {summary = "A lisp that compiles to Lua", detailed = ("Get your parens on--write macros and " .. "homoiconic code on the Lua runtime!"), license = "MIT", homepage = "https://fennel-lang.org/"}
dependencies = {"lua >= 5.1"}
build = {type = "builtin", install = {bin = {fennel = "fennel"}}, modules = {fennel = "fennel.lua"}}
return nil
