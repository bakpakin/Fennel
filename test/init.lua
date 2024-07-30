local t = require("test.faith")

-- Ensure we don't accidentally set globals when loading or running the compiler
setmetatable(_G, {__newindex=function(_, k) error("set global "..k) end})

local oldfennel = require("bootstrap.fennel")
local opts = {useMetadata = true, correlate = true}
oldfennel.dofile("src/fennel.fnl", {compilerEnv=_G}).install(opts)

local modules = {"test.core", "test.mangling", "test.quoting", "test.bit",
                 "test.fennelview", "test.parser", "test.failures", "test.repl",
                 "test.cli", "test.macro", "test.linter", "test.loops",
                 "test.misc", "test.searcher", "test.api", "test.sourcemap"}

if(#arg ~= 0 and arg[1] ~= "--eval") then modules = arg end

t.run(modules,{hooks={exit=dofile("test/irc.lua")}})
