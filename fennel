#!/usr/bin/env lua

package.path = arg[0]:match("(.-)[^\\/]+$") .. "?.lua;" .. package.path
local fennel = require('fennel')

local help = [[
Usage: fennel [FLAG] [FILE]

  --repl          :  Launch an interactive repl session
  --compile FILES :  Compile files and write their Lua to stdout
  --help          :  Display this text

  When not given a flag, runs the file given as the first argument.]]

local flags = {"--accurate"}
local options = {}
for _, flag in pairs(flags) do
    for i = #arg, 1, -1 do
        if arg[i] == flag then
            table.remove(arg, i)
            options[flag:gsub("[-][-]", "")] = true
        end
    end
end

if arg[1] == "--repl" or #arg == 0 then
    print("Welcome to fennel!")
    fennel.repl()
elseif arg[1] == "--compile" then
    for i = 2, #arg do
        local f = assert(io.open(arg[i], "rb"))
        options.filename=arg[i]
        local ok, val = pcall(fennel.compileString, f:read("*all"), options)
        print(val)
        if(not ok) then os.exit(1) end
        f:close()
    end
elseif #arg >= 1 and arg[1] ~= "--help" then
    local filename = table.remove(arg, 1) -- let the script have remaining args
    local ok, val = pcall(fennel.dofile, filename, { accurate=true })
    if(not ok) then
        print(val)
        os.exit(1)
    end
else
    print(help)
end
