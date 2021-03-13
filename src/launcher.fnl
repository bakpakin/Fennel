;; This is the command-line entry point for Fennel.

(local fennel (require :fennel))
(local unpack (or table.unpack _G.unpack))

(local help "
Usage: fennel [FLAG] [FILE]

Run fennel, a lisp programming language for the Lua runtime.

  --repl                  : Command to launch an interactive repl session
  --compile FILES         : Command to AOT compile files, writing Lua to stdout
  --eval SOURCE (-e)      : Command to evaluate source code and print the result

  --no-searcher           : Skip installing package.searchers entry
  --indent VAL            : Indent compiler output with VAL
  --add-package-path PATH : Add PATH to package.path for finding Lua modules
  --add-fennel-path  PATH : Add PATH to fennel.path for finding Fennel modules
  --globals G1[,G2...]    : Allow these globals in addition to standard ones
  --globals-only G1[,G2]  : Same as above, but exclude standard ones
  --require-as-include    : Inline required modules in the output
  --metadata              : Enable function metadata, even in compiled output
  --no-metadata           : Disable function metadata, even in REPL
  --correlate             : Make Lua output line numbers match Fennel input
  --load FILE (-l)        : Load the specified FILE before executing the command
  --lua LUA_EXE           : Run in a child process with LUA_EXE
  --no-fennelrc           : Skip loading ~/.fennelrc when launching repl
  --plugin FILE           : Activate the compiler plugin in FILE
  --compile-binary FILE
      OUT LUA_LIB LUA_DIR : Compile FILE to standalone binary OUT
  --compile-binary --help : Display further help for compiling binaries
  --no-compiler-sandbox   : Do not limit compiler environment to minimal sandbox

  --help (-h)             : Display this text
  --version (-v)          : Show version

  Globals are not checked when doing AOT (ahead-of-time) compilation unless
  the --globals-only flag is provided.

  Metadata is typically considered a development feature and is not recommended
  for production. It is used for docstrings and enabled by default in the REPL.

  When not given a command, runs the file given as the first argument.
  When given neither command nor file, launches a repl.

  If ~/.fennelrc exists, loads it before launching a repl.")

(local options {:plugins []})

(fn dosafely [f ...]
  (let [args [...]
        (ok val) (xpcall #(f (unpack args)) fennel.traceback)]
    (when (not ok)
      (io.stderr:write (.. val "\n"))
      (os.exit 1))
    val))

(fn allow-globals [global-names]
  (set options.allowedGlobals [])
  (each [g (global-names:gmatch "([^,]+),?")]
    (table.insert options.allowedGlobals g)))

(fn handle-load [i]
  (let [file (table.remove arg (+ i 1))]
    (dosafely fennel.dofile file options)
    (table.remove arg i)))

(fn handle-lua [i]
  (table.remove arg i) ; remove the --lua flag from args
  (let [tgt-lua (table.remove arg i)
        cmd [(string.format "%s %s" tgt-lua (. arg 0))]]
    (for [i 1 (length arg)] ; quote args to prevent shell escapes when executing
      (table.insert cmd (string.format "%q" (. arg i))))
    (let [ok (os.execute (table.concat cmd " "))]
      (os.exit (if ok 0 1) true))))

;; check for --lua first to ensure its child process retains all flags
(for [i (length arg) 1 -1]
  (match (. arg i)
    :--lua (handle-lua i)))

(for [i (length arg) 1 -1]
  (match (. arg i)
    :--no-searcher (do
                     (set options.no-searcher true)
                     (table.remove arg i))
    :--indent (do
                (set options.indent (table.remove arg (+ i 1)))
                (when (= options.indent :false)
                  (set options.indent false))
                (table.remove arg i))
    :--add-package-path (let [entry (table.remove arg (+ i 1))]
                          (set package.path (.. entry ";" package.path))
                          (table.remove arg i))
    :--add-fennel-path (let [entry (table.remove arg (+ i 1))]
                         (set fennel.path (.. entry ";" fennel.path))
                         (table.remove arg i))
    :--load (handle-load i)
    :-l (handle-load i)
    :--no-fennelrc (do
                     (set options.fennelrc false)
                     (table.remove arg i))
    :--correlate (do
                   (set options.correlate true)
                   (table.remove arg i))
    :--check-unused-locals (do
                             (set options.checkUnusedLocals true)
                             (table.remove arg i))
    :--globals (do
                 (allow-globals (table.remove arg (+ i 1)))
                 (each [global-name (pairs _G)]
                   (table.insert options.allowedGlobals global-name))
                 (table.remove arg i))
    :--globals-only (do
                      (allow-globals (table.remove arg (+ i 1)))
                      (table.remove arg i))
    :--require-as-include (do
                            (set options.requireAsInclude true)
                            (table.remove arg i))
    :--metadata (do
                  (set options.useMetadata true)
                  (table.remove arg i))
    :--no-metadata (do
                     (set options.useMetadata false)
                     (table.remove arg i))
    :--no-compiler-sandbox (do
                             (set options.compiler-env _G)
                             (table.remove arg i))
    :--plugin (let [plugin (fennel.dofile (table.remove arg (+ i 1))
                                          {:env :_COMPILER :useMetadata true})]
                (table.insert options.plugins 1 plugin)
                (table.remove arg i))))

(local searcher-opts {})

(when (not options.no-searcher)
  (each [k v (pairs options)]
    (tset searcher-opts k v))
  (table.insert (or package.loaders package.searchers)
                (fennel.make-searcher searcher-opts)))

(fn try-readline [ok readline]
  (when ok
    (when readline.set_readline_name
      (readline.set_readline_name :fennel))
    (readline.set_options {:keeplines 1000 :histfile ""})

    (fn options.readChunk [parser-state]
      (let [prompt (if (< 0 parser-state.stack-size) ".. " ">> ")
            str (readline.readline prompt)]
        (if str (.. str "\n"))))

    (var completer nil)

    (fn options.registerCompleter [repl-completer]
      (set completer repl-completer))

    (fn repl-completer [text from to]
      (if completer
          (do
            (readline.set_completion_append_character "")
            (completer (text:sub from to)))
          []))

    (readline.set_complete_function repl-completer)
    readline))

(fn load-initfile []
  (let [home (or (os.getenv :HOME) "/")
        xdg-config-home (or (os.getenv :XDG_CONFIG_HOME) (.. home :/.config))
        xdg-initfile (.. xdg-config-home :/fennel/fennelrc)
        home-initfile (.. home :/.fennelrc)
        init (io.open xdg-initfile :rb)
        init-filename (if init xdg-initfile home-initfile)
        init (or init (io.open home-initfile :rb))]
    (when init
      (init:close)
      (dosafely fennel.dofile init-filename options options fennel))))

(fn repl []
  (let [readline (try-readline (pcall require :readline))]
    (set searcher-opts.useMetadata (not= false options.useMetadata))
    (set options.pp (require :fennel.view))
    (when (not= false options.fennelrc)
      (load-initfile))
    (print (.. "Welcome to Fennel " fennel.version " on " _VERSION "!"))
    (print "Use ,help to see available commands.")
    (when (not readline)
      (print "Try installing readline via luarocks for a better repl experience."))
    (fennel.repl options)
    (when readline
      (readline.save_history))))

(fn eval [form]
  (print (dosafely fennel.eval (if (= form "-")
                                   (io.stdin:read :*a)
                                   form) options)))

(match arg
  ([] ? (= 0 (length arg))) (repl)
  [:--repl] (repl)
  [:--compile & files] (each [_ filename (ipairs files)]
                         (set options.filename filename)
                         (let [f (if (= filename "-")
                                     io.stdin
                                     (assert (io.open filename :rb)))
                               (ok val) (xpcall #(fennel.compile-string (f:read :*a)
                                                                        options)
                                                fennel.traceback)]
                           (if ok
                               (print val)
                               (do
                                 (io.stderr:write (.. val "\n"))
                                 (os.exit 1)))
                           (f:close)))
  [:--compile-binary filename out static-lua lua-include-dir & args]
  (let [bin (require :fennel.binary)]
    (set options.filename filename)
    (set options.requireAsInclude true)
    (bin.compile filename out static-lua lua-include-dir options args))
  [:--compile-binary] (print (. (require :fennel.binary) :help))
  [:--eval form] (eval form)
  [:-e form] (eval form)
  [:--version] (print (.. "Fennel " fennel.version " on " _VERSION))
  [:--help] (print help)
  [:-h] (print help)
  ["-" & args] (dosafely fennel.eval (io.stdin:read :*a))
  [filename & args] (do
                      (tset arg -2 (. arg -1))
                      (tset arg -1 (. arg 0))
                      (tset arg 0 (table.remove arg 1))
                      (dosafely fennel.dofile filename options (unpack args))))
