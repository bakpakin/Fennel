#!/usr/bin/env lua

-- This is the old version of the launcher wrapper script; we keep it around
-- for bootstraping purposes to avoid chicken/egg problems using launcher.fnl
-- to compile Fennel itself. In general there is no need to keep this file in
-- sync with launcher.fnl; changes for new features should just go there.

local fennel_dir = arg[0]:match("(.-)[^\\/]+$")
package.path = fennel_dir .. "?.lua;" .. package.path
local fennel = require('fennel')
local unpack = unpack or table.unpack

local help = [[
Usage: fennel [FLAG] [FILE]

Run fennel, a lisp programming language for the Lua runtime.

  --repl                  : Command to launch an interactive repl session
  --compile FILES         : Command to compile files and write Lua to stdout
  --eval SOURCE (-e)      : Command to evaluate source code and print the result

  --no-searcher           : Skip installing package.searchers entry
  --indent VAL            : Indent compiler output with VAL
  --add-package-path PATH : Add PATH to package.path for finding Lua modules
  --add-fennel-path  PATH : Add PATH to fennel.path for finding Fennel modules
  --globals G1[,G2...]    : Allow these globals in addition to standard ones
  --globals-only G1[,G2]  : Same as above, but exclude standard ones
  --check-unused-locals   : Raise error when compiling code with unused locals
  --require-as-include    : Inline required modules in the output
  --metadata              : Enable function metadata, even in compiled output
  --no-metadata           : Disable function metadata, even in REPL
  --correlate             : Make Lua output line numbers match Fennel input
  --load FILE (-l)        : Load the specified FILE before executing the command
  --no-fennelrc           : Skip loading ~/.fennelrc when launching repl

  --help (-h)             : Display this text
  --version (-v)          : Show version

  Metadata is typically considered a development feature and is not recommended
  for production. It is used for docstrings and enabled by default in the REPL.

  When not given a command, runs the file given as the first argument.
  When given neither command nor file, launches a repl.

  If ~/.fennelrc exists, loads it before launching a repl.]]

local options = {}

local function dosafe(filename, opts, args)
    local ok, val = xpcall(function()
        return fennel.dofile(filename, opts, unpack(args))
    end, fennel.traceback)
    if not ok then
        io.stderr:write(val .. "\n")
        os.exit(1)
    end
    return val
end

local function allowGlobals(globalNames)
    options.allowedGlobals = {}
    for g in globalNames:gmatch("([^,]+),?") do
        table.insert(options.allowedGlobals, g)
    end
end

for i=#arg, 1, -1 do
    if arg[i] == "--no-searcher" then
        options.no_searcher = true
        table.remove(arg, i)
    elseif arg[i] == "--indent" then
        options.indent = table.remove(arg, i+1)
        if options.indent == "false" then options.indent = false end
        table.remove(arg, i)
    elseif arg[i] == "--add-package-path" then
        local entry = table.remove(arg, i+1)
        package.path = entry .. ";" .. package.path
        table.remove(arg, i)
    elseif arg[i] == "--add-fennel-path" then
        local entry = table.remove(arg, i+1)
        fennel.path = entry .. ";" .. fennel.path
        table.remove(arg, i)
    elseif arg[i] == "--load" or arg[i] == "-l" then
        local file = table.remove(arg, i+1)
        dosafe(file, options, {})
        table.remove(arg, i)
    elseif arg[i] == "--no-fennelrc" then
        options.fennelrc = false
        table.remove(arg, i)
    elseif arg[i] == "--correlate" then
        options.correlate = true
        table.remove(arg, i)
    elseif arg[i] == "--check-unused-locals" then
        options.checkUnusedLocals = true
        table.remove(arg, i)
    elseif arg[i] == "--globals" then
        allowGlobals(table.remove(arg, i+1))
        for globalName in pairs(_G) do
            table.insert(options.allowedGlobals, globalName)
        end
        table.remove(arg, i)
    elseif arg[i] == "--globals-only" then
        allowGlobals(table.remove(arg, i+1))
        table.remove(arg, i)
    elseif arg[i] == "--require-as-include" then
        options.requireAsInclude = true
        table.remove(arg, i)
    elseif arg[i] == "--metadata" then
        options.useMetadata = true
        table.remove(arg, i)
    elseif arg[i] == "--no-metadata" then
        options.useMetadata = false
        table.remove(arg, i)
    end
end

if not options.no_searcher then
    local opts = {}
    for k,v in pairs(options) do opts[k] = v end
    table.insert((package.loaders or package.searchers), fennel.make_searcher(opts))
end

-- Try to load readline library
local function tryReadline(opts)
    local readline_ok, readline = pcall(require, "readline")
    if readline_ok then
        if readline.set_readline_name then -- added as of readline.lua 2.6-0
            readline.set_readline_name('fennel')
        end
        readline.set_options({
            keeplines = 1000, histfile = '', })
        function opts.readChunk(parserState)
            local prompt = parserState.stackSize > 0 and '.. ' or '>> '
            local str = readline.readline(prompt)
            if str then
                return str .. "\n"
            end
        end

        -- completer is registered by the repl, until then returns empty list
        local completer
        function opts.registerCompleter(replCompleter)
          completer = replCompleter
        end
        local function replCompleter(text, from, to)
          if completer then
            -- stop completed syms from adding extra space on match
            readline.set_completion_append_character('')
            return completer(text:sub(from, to))
          else
            return {}
          end
        end
        readline.set_complete_function(replCompleter)
        return readline
      end
end

-- TODO: generalize this instead of hardcoding it
local fok, friendly = pcall(fennel.dofile, fennel_dir .. "fennelfriend.fnl", options)
if fok then
    options["assert-compile"] = friendly["assert-compile"]
    options["parse-error"] = friendly["parse-error"]
end

if arg[1] == "--repl" or #arg == 0 then
    local ppok, pp = pcall(fennel.dofile, fennel_dir .. "fennelview.fnl", options)
    if ppok then
        options.pp = pp
    else
        ppok, pp = pcall(require, "fennelview")
        if ppok then
            options.pp = pp
        end
    end

    local readline = tryReadline(options)

    if options.fennelrc ~= false then
        local home = os.getenv("HOME")
        local xdg_config_home = os.getenv("XDG_CONFIG_HOME") or home .. "/.config"
        local xdg_initfile = xdg_config_home .. "/fennel/fennelrc"
        local home_initfile = home .. "/.fennelrc"
        local init, initFilename = io.open(xdg_initfile, "rb"), xdg_initfile
        if not init then
            init, initFilename = io.open(home_initfile, "rb"), home_initfile
        end

        if init then
            init:close()
            -- pass in options so fennerlrc can make changes to it
            dosafe(initFilename, options, {options})
        end
    end

    print("Welcome to Fennel " .. fennel.version .. "!")
    if options.useMetadata ~= false then
        print("Use (doc something) to view documentation.")
    end
    fennel.repl(options)
    -- if readline loaded, persist history (noop if histfile == '')
    if readline then readline.save_history() end
elseif arg[1] == "--compile" then
    for i = 2, #arg do
        local f = arg[i] == "-" and io.stdin or assert(io.open(arg[i], "rb"))
        options.filename=arg[i]
        local ok, val = xpcall(function()
            return fennel.compileString(f:read("*all"), options)
        end, fennel.traceback)
        if ok then
            print(val)
        else
            io.stderr:write(val .. "\n")
            os.exit(1)
        end
        f:close()
    end
elseif arg[1] == "--eval" or arg[1] == "-e" then
   if arg[2] and arg[2] ~= "-" then
      print(fennel.eval(arg[2], options))
   else
      local source = io.stdin:read("*a")
      print(fennel.eval(source, options))
   end
elseif arg[1] == "--version" or arg[1] == "-v" then
    print("Fennel " .. fennel.version)
elseif #arg >= 1 and arg[1] ~= "--help" and arg[1] ~= "-h" then
    local filename = table.remove(arg, 1) -- let the script have remaining args
    if filename == "-" then
       local source = io.stdin:read("*a")
       fennel.eval(source, options)
    else
       dosafe(filename, options, arg)
    end
else
    print(help)
end
