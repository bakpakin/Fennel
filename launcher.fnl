(local fennel (require :fennel))
(local unpack (or _G.unpack table.unpack))

(local help "
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

  If ~/.fennelrc exists, loads it before launching a repl.")

(local options [])

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

(for [i (# arg) 1 -1]
  (match (. arg i)
    "--no-searcher" (do (set options.no_searcher true)
                        (table.remove arg i))
    "--indent" (do (set options.indent (table.remove arg (+ i 1)))
                   (when (= options.indent "false")
                     (set options.indent false))
                   (table.remove arg i))
    "--add-package-path" (let [entry (table.remove arg (+ i 1))]
                           (set package.path (.. entry ";" package.path))
                           (table.remove arg i))
    "--add-fennel-path" (let [entry (table.remove arg (+ i 1))]
                          (set fennel.path (.. entry ";" fennel.path))
                          (table.remove arg i))
    "--load" (let [file (table.remove arg (+ i 1))]
               (dosafely fennel.dofile file options [])
               (table.remove arg i))
    "--no-fennelrc" (do (set options.fennelrc false)
                        (table.remove arg i))
    "--correlate" (do (set options.correlate true)
                      (table.remove arg i))
    "--check-unused-locals" (do (set options.checkUnusedLocals true)
                                (table.remove arg i))
    "--globals" (do (allow-globals (table.remove arg (+ i 1)))
                    (each [global-name (pairs _G)]
                      (table.insert options.allowedGlobals global-name))
                    (table.remove arg i))
    "--globals-only" (do (allow-globals (table.remove arg (+ i 1)))
                         (table.remove arg i))
    "--require-as-include" (do (set options.requireAsInclude true)
                               (table.remove arg i))
    "--metadata" (do (set options.useMetadata true)
                     (table.remove arg i))
    "--no-metadata" (do (set options.useMetadata false)
                        (table.remove arg i))))

(when (not options.no_searcher)
  (let [opts []]
    (each [k v (pairs options)]
      (tset opts k v))
    (table.insert (or package.loaders package.searchers)
                  (fennel.make_searcher opts))))

(fn try-readline [ok readline]
  (when ok
    (when readline.set_readline_name
      (readline.set_readline_name "fennel"))
    (readline.set_options {:keeplines 1000 :histfile ""})
    (fn opts.readChunk [parser-state]
      (let [prompt (if (< 0 parser-state.stackSize) ".. " ">> ")
            str (readline.readline prompt)]
        (if str (.. str "\n"))))
    (var completer nil)
    (fn opts.registerCompleter [repl-completer]
      (set completer repl-completer))
    (fn repl-completer [text from to]
      (if completer
          (do (readline.set_completion_append_character "")
              (completer (text:sub from to)))
          []))
    (readline.set_complete_function repl-completer)
    readline))

;; TODO: generalize this as a plugin instead of hard-coding it
;; we can't pcall this or we won't be able to use --require-as-include.
(each [k v (pairs (require :fennelfriend))]
  (tset options k v))

(fn load-initfile []
  (let [home (os.getenv "HOME")
        xdg-config-home (or (os.getenv "XDG_CONFIG_HOME") (.. home "/.config"))
        xdg-initfile (.. xdg-config-home "/fennel/fennelrc")
        home-initfile (.. home "/.fennelrc")
        init (io.open xdg-initfile :rb)
        init-filename (if init xdg-initfile home-initfile)
        init (or init (io.open home-initfile :rb))]
    (when init
      (init:close)
      (dosafely fennel.dofile init-filename options [options]))))

(fn repl []
  (let [readline (try-readline (pcall require :readline))]
    (set options.pp (require :fennelview))
    (when (not= false options.fennelrc)
      (load-initfile))
    (print (.. "Welcome to Fennel " fennel.version "!"))
    (when (not= options.useMetadata false)
      (print "Use (doc something) to view documentation."))
    (fennel.repl options)
    (when readline
      (readline.save_history))))

(fn eval [form]
  (print (dosafely fennel.eval (if (= form "-")
                                   (io.stdin:read :*a)
                                   form) options)))

(match arg
  ([] ? (= 0 (# arg))) (repl)
  ["--repl"] (repl)
  ["--compile" & files] (each [_ filename (ipairs files)]
                          (set options.filename filename)
                          (let [f (if (= filename "-")
                                      io.stdin
                                      (assert (io.open filename :rb)))
                                (ok val) (xpcall #(fennel.compileString
                                                   (f:read :*all options))
                                                 fennel.traceback)]
                            (if ok
                                (print val)
                                (do (io.stderr:write (.. val "\n"))
                                    (os.exit 1)))
                            (f:close)))
  ["--eval" form] (eval form)
  ["-e" form] (eval form)
  ["--version"] (print (.. "Fennel " fennel.version))
  ["--help"] (print help)
  ["-h"] (print help)
  ["-" & args] (dosafely fennel.eval (io.stdin:read :*a))
  [filename & args] (dosafely fennel.dofile filename options args))
