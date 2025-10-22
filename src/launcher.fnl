;; This is the command-line entry point for Fennel.

(local fennel (require :fennel))
(local {: pack : unpack} (require :fennel.utils))

(local help "Usage: fennel [FLAG] [FILE]

Run Fennel, a Lisp programming language for the Lua runtime.

  --repl                   : Command to launch an interactive REPL session
  -c, --compile FILES      : Command to AOT compile files, writing Lua to stdout
  -e, --eval SOURCE        : Command to evaluate source code and print result

  --correlate              : Make Lua output line numbers try to match Fennel's
  -l, --load FILE          : Load the specified FILE before executing command
  --no-compiler-sandbox    : Don't limit compiler environment to minimal sandbox
  --compile-binary FILE    : Compile FILE to standalone binary OUT
      OUT LUA_LIB LUA_DIR
  --compile-binary --help  : Display further help for compiling binaries
  --add-package-path PATH  : Add PATH to package.path for finding Lua modules
  --add-package-cpath PATH : Add PATH to package.cpath for finding Lua modules
  --add-fennel-path PATH   : Add PATH to fennel.path for finding Fennel modules
  --add-macro-path PATH    : Add PATH to fennel.macro-path for macro modules
  --globals G1[,G2...]     : Allow these globals in addition to standard ones
  --globals-only G1[,G2]   : Same as above, but exclude standard ones
  --assert-as-repl         : Replace assert calls with assert-repl
  --require-as-include     : Inline required modules in the output
  --to-be-closed           : Use to-be-closed vars in with-open (Lua 5.4+ only)
  --lambda-as-fn           : Replace lambda function definitions with fn
  --skip-include M1[,M2]   : Omit certain modules from output when included
  --use-bit-lib            : Use LuaJITs bit library instead of operators
  --metadata               : Enable function metadata, even in compiled output
  --no-metadata            : Disable function metadata, even in REPL
  --lua LUA_EXE            : Run in a child process with LUA_EXE
  --plugin FILE            : Activate the compiler plugin in FILE
  --raw-errors             : Disable friendly compile error reporting
  --no-searcher            : Skip installing package.searchers entry
  --no-fennelrc            : Skip loading ~/.fennelrc when launching REPL
  --keywords K1[,K2...]    : Treat these symbols as reserved Lua keywords

  -h, --help               : Display this text
  -v, --version            : Show version

Globals are not checked when doing AOT (ahead-of-time) compilation unless
the --globals-only or --globals flag is provided. Use --globals \"*\" to disable
strict globals checking in other contexts.

Metadata is typically considered a development feature and is not recommended
for production. It is used for docstrings and enabled by default in the REPL.

When not given a command, runs the file given as the first argument.
When given neither command nor file, launches a REPL.

Use the NO_COLOR environment variable to disable escape codes in error messages.

If ~/.fennelrc exists, it will be loaded before launching a REPL.")

(local options {:plugins [] :keywords {}})

(fn dosafely [f ...]
  (let [args [...]
        result (pack (xpcall #(f (unpack args)) fennel.traceback))]
    (when (not (. result 1))
      (io.stderr:write (.. (tostring (. result 2)) "\n"))
      (os.exit 1))
    (unpack result 2 result.n)))

(fn allow-globals [names actual-globals]
  (if (= names "*")
      (set options.allowedGlobals false)
      (do
        (set options.allowedGlobals (icollect [g (names:gmatch "([^,]+),?")] g))
        (each [global-name (pairs actual-globals)]
          (table.insert options.allowedGlobals global-name)))))

(fn handle-load [i]
  (let [file (table.remove arg (+ i 1))]
    (dosafely fennel.dofile file options)
    (table.remove arg i)))

(fn handle-lua [i]
  (table.remove arg i) ; remove the --lua flag from args
  (let [tgt-lua (table.remove arg i)
        cmd [(string.format "%s %s" tgt-lua (or (. arg 0) "fennel"))]]
    (for [i 1 (length arg)] ; quote args to prevent shell escapes when executing
      (table.insert cmd (string.format "%q" (. arg i))))
    (when (= nil (. arg -1))
      (io.stderr:write
       "WARNING: --lua argument only works from script, not binary.\n"))
    (case (os.execute (table.concat cmd " "))
      (where (or (true :exit) 0)) (os.exit 0)
      _ (os.exit 1))))

;; check for --lua first to ensure its child process retains all flags
(for [i (length arg) 1 -1]
  (case (. arg i)
    :--lua (handle-lua i)))

(fn load-plugin [filename]
  (let [opts {:env :_COMPILER :compiler-env _G :useMetadata true}]
    (if (= ".lua" (filename:sub -4))
        ((fennel.load-code (: (assert (io.open filename :rb)) :read :*a)
                           ((. (require :fennel.specials) :make-compiler-env)
                            nil (fennel.scope) nil opts)
                           filename))
        (fennel.dofile filename opts))))

(let [commands {:--repl true
               :--compile true :-c true
               :--compile-binary true
               :--eval true :-e true
               :--version true :-v true
               :--help true :-h true
               "-" true}]
  (var i 1)
  (while (and (. arg i) (not options.ignore-options))
    (case (. arg i)
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
      :--add-package-cpath (let [entry (table.remove arg (+ i 1))]
                             (set package.cpath (.. entry ";" package.cpath))
                             (table.remove arg i))
      :--add-fennel-path (let [entry (table.remove arg (+ i 1))]
                          (set fennel.path (.. entry ";" fennel.path))
                          (table.remove arg i))
      :--add-macro-path (let [entry (table.remove arg (+ i 1))]
                          (set fennel.macro-path (.. entry ";" fennel.macro-path))
                          (table.remove arg i))
      :--load (handle-load i)
      :-l (handle-load i)
      :--no-fennelrc (do
                      (set options.fennelrc false)
                      (table.remove arg i))
      :--correlate (do
                    (set options.correlate true)
                    (table.remove arg i))
      :--globals (do
                  (allow-globals (table.remove arg (+ i 1)) _G)
                  (table.remove arg i))
      :--globals-only (do
                        (allow-globals (table.remove arg (+ i 1)) {})
                        (table.remove arg i))
      :--require-as-include (do
                              (set options.requireAsInclude true)
                              (table.remove arg i))
      :--to-be-closed (do
                        (set options.toBeClosed true)
                        (table.remove arg i))
      :--assert-as-repl (do
                          (set options.assertAsRepl true)
                          (table.remove arg i))
      :--lambda-as-fn (do
                        (set options.lambdaAsFn true)
                        (table.remove arg i))
      :--skip-include (let [skip-names (table.remove arg (+ i 1))
                            skip (icollect [m (skip-names:gmatch "([^,]+)")] m)]
                        (set options.skipInclude skip)
                        (table.remove arg i))
      :--use-bit-lib (do
                      (set options.useBitLib true)
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
      :--raw-errors (do
                      (set options.unfriendly true)
                      (table.remove arg i))
      :--plugin (let [plugin (load-plugin (table.remove arg (+ i 1)))]
                  (table.insert options.plugins 1 plugin)
                  (table.remove arg i))
      :--keywords (do
                    (each [keyword (string.gmatch (table.remove arg (+ i 1)) "[^,]+")]
                      (tset options.keywords keyword true))
                    (table.remove arg i))
      _ (do
          (when (not (. commands (. arg i)))
            (set options.ignore-options true)
            (set i (+ i 1)))
          (set i (+ i 1))))))

(local searcher-opts {})

(when (not options.no-searcher)
  (each [k v (pairs options)]
    (tset searcher-opts k v))
  (table.insert (or package.loaders package.searchers)
                (fennel.make-searcher searcher-opts)))

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
  (let [readline? (and (not= "dumb" (os.getenv "TERM"))
                       (pcall require :readline))
        welcome [(.. "Welcome to " (fennel.runtime-version) "!")
                 "Use ,help to see available commands."]]
    (set searcher-opts.useMetadata (not= false options.useMetadata))
    (when (not= false options.fennelrc)
      (set options.fennelrc load-initfile))
    (when (and (not readline?) (not= "dumb" (os.getenv "TERM")))
      (table.insert welcome (.. "Try installing readline via luarocks for a "
                                "better repl experience.")))
    (set options.message (table.concat welcome "\n"))
    (fennel.repl options)))

(fn eval [form]
  (print (dosafely fennel.eval (if (= form "-")
                                   (io.stdin:read :*a)
                                   form) options)))

(fn compile [files]
  (each [_ filename (ipairs files)]
    (set options.filename filename)
    (let [f (if (= filename "-")
                io.stdin
                (assert (io.open filename :rb)))]
      (case (xpcall #(fennel.compile-string (f:read :*a) options)
                     fennel.traceback)
        (true val) (print val)
        (_ msg) (do
                  (io.stderr:write (.. msg "\n"))
                  (os.exit 1)))
      (f:close))))

(match arg
  ([] ? (= 0 (length arg))) (repl)
  [:--repl] (repl)
  [:--compile & files] (compile files)
  [:-c & files] (compile files)
  [:--compile-binary filename out static-lua lua-include-dir & args]
  (let [bin (require :fennel.binary)]
    (set options.filename filename)
    (set options.requireAsInclude true)
    (bin.compile filename out static-lua lua-include-dir options args))
  [:--compile-binary] (let [cmd (or (. arg 0) "fennel")]
                        (print (: (. (require :fennel.binary) :help)
                                  :format cmd cmd cmd)))
  [:--eval form] (eval form)
  [:-e form] (eval form)
  ([a] ? (or (= a :-v) (= a :--version)))
  (print (fennel.runtime-version))
  [:--help] (print help)
  [:-h] (print help)
  ["-"] (dosafely fennel.eval (io.stdin:read :*a))
  [filename & args] (do
                      (tset arg -2 (. arg -1))
                      (tset arg -1 (. arg 0))
                      (tset arg 0 (table.remove arg 1))
                      (dosafely fennel.dofile filename options (unpack args))))
