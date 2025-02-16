-- Just a tiny shim to allow AOT
-- This is only used to bootstrap the main compiler.
local fennel = dofile("bootstrap/fennel.lua")

local opts = {
   ["compiler-env"]=_G,
   allowedGlobals={},
   useMetadata=false,
   filename=assert(arg[1]),
}

for k in pairs(_G) do table.insert(opts.allowedGlobals, k) end

for i=2,#arg do
   if arg[i] == "--require-as-include" then opts.requireAsInclude = true end
   if arg[i] == "--macro" then
      opts.useMetadata = "utils['fennel-module'].metadata"
      opts.scope = "_COMPILER"
      opts.allowedGlobals = false
   end
end

local f = assert(io.open(opts.filename))
local compile = function() return fennel.compileString(f:read("*a"), opts) end
local ok, val = xpcall(compile, fennel.traceback)

if(ok) then
   print(val)
else
   io.stderr:write(val)
   io.stderr:write("\n")
   os.exit(1)
end
