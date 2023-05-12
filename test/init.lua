local t = require("test.faith")
local oldfennel = require("bootstrap.fennel")
local opts = {useMetadata = true, correlate = true}
oldfennel.dofile("src/fennel.fnl", {compilerEnv=_G}).install(opts)

_G.tbl = {}

local modules = {"test.core", "test.mangling", "test.quoting", "test.bit",
                 "test.fennelview", "test.parser", "test.failures", "test.repl",
                 "test.cli", "test.macro", "test.linter", "test.loops",
                 "test.misc", "test.searcher", "test.api"}

if(#arg ~= 0) then modules = arg end

t.run(modules,{exit=dofile("test/irc.lua")})
