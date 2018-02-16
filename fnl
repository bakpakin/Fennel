#!/usr/bin/env lua

package.path = arg[0]:match("(.-)[^\\/]+$") .. "?.lua;" .. package.path
local fnl = require('fnl')

if arg[1] == "--repl" then
    print("Welcome to fnl!")
    fnl.repl()
elseif arg[1] == "--compile" then
    local f = assert(io.open(arg[2], "rb"))
    print(fnl.compile(f:read("*all")))
    f:close()
elseif #arg == 1 then
    local f = assert(io.open(arg[1], "rb"))
    fnl.eval(f:read("*all"))
    f:close()
else
    print [[
Usage: fnl --options scripts

  --repl    :  Launch a repl
  --compile :  Compile a file and write the Lua to stdout]]
end
