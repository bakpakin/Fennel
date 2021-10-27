-- This is a bootstrap copy of the launcher. It was generated between 0.10.0
-- and 1.0.0. It's included in order to avoid the chicken/egg problem of
-- self-hosting the compiler written in Fennel.

local fennel_dir = arg[0]:match("(.-)[^\\/]+$")
package.path = fennel_dir .. "?.lua;" .. package.path
local fennel = require('fennel')

local unpack = (table.unpack or _G.unpack)
local help = "\nUsage: fennel [FLAG] [FILE]\n\nRun fennel, a lisp programming language for the Lua runtime.\n\n  --repl                  : Command to launch an interactive repl session\n  --compile FILES (-c)    : Command to AOT compile files, writing Lua to stdout\n  --eval SOURCE (-e)      : Command to evaluate source code and print the result\n\n  --no-searcher           : Skip installing package.searchers entry\n  --indent VAL            : Indent compiler output with VAL\n  --add-package-path PATH : Add PATH to package.path for finding Lua modules\n  --add-fennel-path  PATH : Add PATH to fennel.path for finding Fennel modules\n  --globals G1[,G2...]    : Allow these globals in addition to standard ones\n  --globals-only G1[,G2]  : Same as above, but exclude standard ones\n  --require-as-include    : Inline required modules in the output\n  --skip-include M1[,M2]  : Omit certain modules from output when included\n  --use-bit-lib           : Use LuaJITs bit library instead of operators\n  --metadata              : Enable function metadata, even in compiled output\n  --no-metadata           : Disable function metadata, even in REPL\n  --correlate             : Make Lua output line numbers match Fennel input\n  --load FILE (-l)        : Load the specified FILE before executing the command\n  --lua LUA_EXE           : Run in a child process with LUA_EXE\n  --no-fennelrc           : Skip loading ~/.fennelrc when launching repl\n  --raw-errors            : Disable friendly compile error reporting\n  --plugin FILE           : Activate the compiler plugin in FILE\n  --compile-binary FILE\n      OUT LUA_LIB LUA_DIR : Compile FILE to standalone binary OUT\n  --compile-binary --help : Display further help for compiling binaries\n  --no-compiler-sandbox   : Do not limit compiler environment to minimal sandbox\n\n  --help (-h)             : Display this text\n  --version (-v)          : Show version\n\nGlobals are not checked when doing AOT (ahead-of-time) compilation unless\nthe --globals-only or --globals flag is provided. Use --globals \"*\" to disable\nstrict globals checking in other contexts.\n\nMetadata is typically considered a development feature and is not recommended\nfor production. It is used for docstrings and enabled by default in the REPL.\n\nWhen not given a command, runs the file given as the first argument.\nWhen given neither command nor file, launches a repl.\n\nIf ~/.fennelrc exists, it will be loaded before launching a repl."
local options = {plugins = {}}
local function dosafely(f, ...)
  local args = {...}
  local _1_, _2_ = nil, nil
  local function _3_()
    return f(unpack(args))
  end
  _1_, _2_ = xpcall(_3_, fennel.traceback)
  if ((_1_ == true) and (nil ~= _2_)) then
    local val = _2_
    return val
  elseif (true and (nil ~= _2_)) then
    local _ = _1_
    local msg = _2_
    do end (io.stderr):write((msg .. "\n"))
    return os.exit(1)
  end
end
local function allow_globals(global_names, globals)
  if (global_names == "*") then
    options.allowedGlobals = false
    return nil
  else
    do
      local tbl_13_auto = {}
      for g in global_names:gmatch("([^,]+),?") do
        tbl_13_auto[(#tbl_13_auto + 1)] = g
      end
      options.allowedGlobals = tbl_13_auto
    end
    for global_name in pairs(globals) do
      table.insert(options.allowedGlobals, global_name)
    end
    return nil
  end
end
local function handle_load(i)
  local file = table.remove(arg, (i + 1))
  dosafely(fennel.dofile, file, options)
  return table.remove(arg, i)
end
local function handle_lua(i)
  table.remove(arg, i)
  local tgt_lua = table.remove(arg, i)
  local cmd = {string.format("%s %s", tgt_lua, arg[0])}
  for i0 = 1, #arg do
    table.insert(cmd, string.format("%q", arg[i0]))
  end
  local ok = os.execute(table.concat(cmd, " "))
  local _6_
  if ok then
    _6_ = 0
  else
    _6_ = 1
  end
  return os.exit(_6_, true)
end
for i = #arg, 1, -1 do
  local _8_ = arg[i]
  if (_8_ == "--lua") then
    handle_lua(i)
  end
end
for i = #arg, 1, -1 do
  local _10_ = arg[i]
  if (_10_ == "--no-searcher") then
    options["no-searcher"] = true
    table.remove(arg, i)
  elseif (_10_ == "--indent") then
    options.indent = table.remove(arg, (i + 1))
    if (options.indent == "false") then
      options.indent = false
    end
    table.remove(arg, i)
  elseif (_10_ == "--add-package-path") then
    local entry = table.remove(arg, (i + 1))
    package.path = (entry .. ";" .. package.path)
    table.remove(arg, i)
  elseif (_10_ == "--add-fennel-path") then
    local entry = table.remove(arg, (i + 1))
    fennel.path = (entry .. ";" .. fennel.path)
    table.remove(arg, i)
  elseif (_10_ == "--load") then
    handle_load(i)
  elseif (_10_ == "-l") then
    handle_load(i)
  elseif (_10_ == "--no-fennelrc") then
    options.fennelrc = false
    table.remove(arg, i)
  elseif (_10_ == "--correlate") then
    options.correlate = true
    table.remove(arg, i)
  elseif (_10_ == "--check-unused-locals") then
    options.checkUnusedLocals = true
    table.remove(arg, i)
  elseif (_10_ == "--globals") then
    allow_globals(table.remove(arg, (i + 1)), _G)
    table.remove(arg, i)
  elseif (_10_ == "--globals-only") then
    allow_globals(table.remove(arg, (i + 1)), {})
    table.remove(arg, i)
  elseif (_10_ == "--require-as-include") then
    options.requireAsInclude = true
    table.remove(arg, i)
  elseif (_10_ == "--skip-include") then
    local skip_names = table.remove(arg, (i + 1))
    local skip
    do
      local tbl_13_auto = {}
      for m in skip_names:gmatch("([^,]+)") do
        tbl_13_auto[(#tbl_13_auto + 1)] = m
      end
      skip = tbl_13_auto
    end
    options.skipInclude = skip
    table.remove(arg, i)
  elseif (_10_ == "--use-bit-lib") then
    options.useBitLib = true
    table.remove(arg, i)
  elseif (_10_ == "--metadata") then
    options.useMetadata = true
    table.remove(arg, i)
  elseif (_10_ == "--no-metadata") then
    options.useMetadata = false
    table.remove(arg, i)
  elseif (_10_ == "--no-compiler-sandbox") then
    options["compiler-env"] = _G
    table.remove(arg, i)
  elseif (_10_ == "--raw-errors") then
    options.unfriendly = true
    table.remove(arg, i)
  elseif (_10_ == "--plugin") then
    local opts = {env = "_COMPILER", useMetadata = true, ["compiler-env"] = _G}
    local plugin = fennel.dofile(table.remove(arg, (i + 1)), opts)
    table.insert(options.plugins, 1, plugin)
    table.remove(arg, i)
  end
end
local searcher_opts = {}
if not options["no-searcher"] then
  for k, v in pairs(options) do
    searcher_opts[k] = v
  end
  table.insert((package.loaders or package.searchers), fennel["make-searcher"](searcher_opts))
end
local function try_readline(ok, readline)
  if ok then
    if readline.set_readline_name then
      readline.set_readline_name("fennel")
    end
    readline.set_options({keeplines = 1000, histfile = ""})
    options.readChunk = function(parser_state)
      local prompt
      if (0 < parser_state["stack-size"]) then
        prompt = ".. "
      else
        prompt = ">> "
      end
      local str = readline.readline(prompt)
      if str then
        return (str .. "\n")
      end
    end
    local completer = nil
    options.registerCompleter = function(repl_completer)
      completer = repl_completer
      return nil
    end
    local function repl_completer(text, from, to)
      if completer then
        readline.set_completion_append_character("")
        return completer(text:sub(from, to))
      else
        return {}
      end
    end
    readline.set_complete_function(repl_completer)
    return readline
  end
end
local function load_initfile()
  local home = (os.getenv("HOME") or "/")
  local xdg_config_home = (os.getenv("XDG_CONFIG_HOME") or (home .. "/.config"))
  local xdg_initfile = (xdg_config_home .. "/fennel/fennelrc")
  local home_initfile = (home .. "/.fennelrc")
  local init = io.open(xdg_initfile, "rb")
  local init_filename
  if init then
    init_filename = xdg_initfile
  else
    init_filename = home_initfile
  end
  local init0 = (init or io.open(home_initfile, "rb"))
  if init0 then
    init0:close()
    return dosafely(fennel.dofile, init_filename, options, options, fennel)
  end
end
local function repl()
  local readline = (("dumb" ~= os.getenv("TERM")) and try_readline(pcall(require, "readline")))
  searcher_opts.useMetadata = (false ~= options.useMetadata)
  options.pp = require("fennel.view")
  if (false ~= options.fennelrc) then
    load_initfile()
  end
  print(("Welcome to Fennel " .. fennel.version .. " on " .. _VERSION .. "!"))
  print("Use ,help to see available commands.")
  if (not readline and ("dumb" ~= os.getenv("TERM"))) then
    print("Try installing readline via luarocks for a better repl experience.")
  end
  fennel.repl(options)
  if readline then
    return readline.save_history()
  end
end
local function eval(form)
  local _24_
  if (form == "-") then
    _24_ = (io.stdin):read("*a")
  else
    _24_ = form
  end
  return print(dosafely(fennel.eval, _24_, options))
end
local function compile(files)
  for _, filename in ipairs(files) do
    options.filename = filename
    local f
    if (filename == "-") then
      f = io.stdin
    else
      f = assert(io.open(filename, "rb"))
    end
    do
      local _27_, _28_ = nil, nil
      local function _29_()
        return fennel["compile-string"](f:read("*a"), options)
      end
      _27_, _28_ = xpcall(_29_, fennel.traceback)
      if ((_27_ == true) and (nil ~= _28_)) then
        local val = _28_
        print(val)
      elseif (true and (nil ~= _28_)) then
        local _0 = _27_
        local msg = _28_
        do end (io.stderr):write((msg .. "\n"))
        os.exit(1)
      end
    end
    f:close()
  end
  return nil
end
local _31_ = arg
local function _32_(...)
  return (0 == #arg)
end
if ((_G.type(_31_) == "table") and _32_(...)) then
  return repl()
elseif ((_G.type(_31_) == "table") and ((_31_)[1] == "--repl")) then
  return repl()
elseif ((_G.type(_31_) == "table") and ((_31_)[1] == "--compile")) then
  local files = {select(2, (table.unpack or _G.unpack)(_31_))}
  return compile(files)
elseif ((_G.type(_31_) == "table") and ((_31_)[1] == "-c")) then
  local files = {select(2, (table.unpack or _G.unpack)(_31_))}
  return compile(files)
elseif ((_G.type(_31_) == "table") and ((_31_)[1] == "--compile-binary") and (nil ~= (_31_)[2]) and (nil ~= (_31_)[3]) and (nil ~= (_31_)[4]) and (nil ~= (_31_)[5])) then
  local filename = (_31_)[2]
  local out = (_31_)[3]
  local static_lua = (_31_)[4]
  local lua_include_dir = (_31_)[5]
  local args = {select(6, (table.unpack or _G.unpack)(_31_))}
  local bin = require("fennel.binary")
  options.filename = filename
  options.requireAsInclude = true
  return bin.compile(filename, out, static_lua, lua_include_dir, options, args)
elseif ((_G.type(_31_) == "table") and ((_31_)[1] == "--compile-binary")) then
  return print((require("fennel.binary")).help)
elseif ((_G.type(_31_) == "table") and ((_31_)[1] == "--eval") and (nil ~= (_31_)[2])) then
  local form = (_31_)[2]
  return eval(form)
elseif ((_G.type(_31_) == "table") and ((_31_)[1] == "-e") and (nil ~= (_31_)[2])) then
  local form = (_31_)[2]
  return eval(form)
else
  local function _33_(...)
    local a = (_31_)[1]
    return ((a == "-v") or (a == "--version"))
  end
  if (((_G.type(_31_) == "table") and (nil ~= (_31_)[1])) and _33_(...)) then
    local a = (_31_)[1]
    return print(("Fennel " .. fennel.version .. " on " .. _VERSION))
  elseif ((_G.type(_31_) == "table") and ((_31_)[1] == "--help")) then
    return print(help)
  elseif ((_G.type(_31_) == "table") and ((_31_)[1] == "-h")) then
    return print(help)
  elseif ((_G.type(_31_) == "table") and ((_31_)[1] == "-")) then
    local args = {select(2, (table.unpack or _G.unpack)(_31_))}
    return dosafely(fennel.eval, (io.stdin):read("*a"))
  elseif ((_G.type(_31_) == "table") and (nil ~= (_31_)[1])) then
    local filename = (_31_)[1]
    local args = {select(2, (table.unpack or _G.unpack)(_31_))}
    arg[-2] = arg[-1]
    arg[-1] = arg[0]
    arg[0] = table.remove(arg, 1)
    return dosafely(fennel.dofile, filename, options, unpack(args))
  end
end
