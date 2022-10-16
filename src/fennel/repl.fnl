;; This module is the read/eval/print loop; for coding Fennel interactively.

;; The most complex thing it does is locals-saving, which allows locals to be
;; preserved in between "chunks"; by default Lua throws away all locals after
;; evaluating each piece of input.

(local utils (require :fennel.utils))
(local parser (require :fennel.parser))
(local compiler (require :fennel.compiler))
(local specials (require :fennel.specials))
(local view (require :fennel.view))
(local unpack (or table.unpack _G.unpack))

(fn default-read-chunk [parser-state]
  (io.write (if (< 0 parser-state.stack-size) ".." ">> "))
  (io.flush)
  (let [input (io.read)]
    (and input (.. input "\n"))))

(fn default-on-values [xs]
  (io.write (table.concat xs "\t"))
  (io.write "\n"))

;; fnlfmt: skip
(fn default-on-error [errtype err lua-source]
  (io.write
   (match errtype
     "Lua Compile" (.. "Bad code generated - likely a bug with the compiler:\n"
                       "--- Generated Lua Start ---\n"
                       lua-source
                       "--- Generated Lua End ---\n")
     "Runtime" (.. (compiler.traceback (tostring err) 4) "\n")
     _ (: "%s error: %s\n" :format errtype (tostring err)))))

(local save-source " ___replLocals___['%s'] = %s")

(fn splice-save-locals [env lua-source scope]
  (let [spliced-source []
        bind "local %s = ___replLocals___['%s']"]
    (each [line (lua-source:gmatch "([^\n]+)\n?")]
      (table.insert spliced-source line))
    (each [name (pairs env.___replLocals___)]
      (table.insert spliced-source 1 (bind:format name name)))
    (when (and (< 1 (length spliced-source))
               (: (. spliced-source (length spliced-source)) :match
                  "^ *return .*$"))
      (each [_ name (pairs scope.manglings)]
        (table.insert spliced-source (length spliced-source)
                      (save-source:format name name))))
    (table.concat spliced-source "\n")))

(fn completer [env scope text]
  (let [max-items 2000 ; to stop explosion on too mny items
        seen {}
        matches []
        input-fragment (text:gsub ".*[%s)(]+" "")]
    (var stop-looking? false)

    (fn add-partials [input tbl prefix] ; add partial key matches in tbl
      ;; When matching on global env or repl locals, iterate *manglings* to include nils
      (local scope-first? (or (= tbl env) (= tbl env.___replLocals___)))
      (icollect [k is-mangled (utils.allpairs (if scope-first? scope.manglings tbl))
                :into matches :until (<= max-items (length matches))]
        (let [lookup-k (if scope-first? is-mangled k)]
          (when (and (= (type k) :string) (= input (k:sub 0 (length input)))
                     ;; manglings iterated for globals & locals, but should only match once
                     (not (. seen k))
                     ;; only match known  functions when we encounter a method call
                     (or (not= ":" (prefix:sub -1)) (= :function (type (. tbl lookup-k)))))
            (tset seen k true)
            (.. prefix k)))))

    (fn descend [input tbl prefix add-matches method?]
      (let [splitter (if method? "^([^:]+):(.*)" "^([^.]+)%.(.*)")
            (head tail) (input:match splitter)
            raw-head (or (. scope.manglings head) head)]
        (when (= (type (. tbl raw-head)) :table)
          (set stop-looking? true)
          (if method?
              (add-partials tail (. tbl raw-head) (.. prefix head ":"))
              (add-matches tail (. tbl raw-head) (.. prefix head))))))

    (fn add-matches [input tbl prefix]
      (let [prefix (if prefix (.. prefix ".") "")]
        (if (and (not (input:find "%.")) (input:find ":")) ; found a method call
            (descend input tbl prefix add-matches true)
            (not (input:find "%.")) ; done descending; add matches
            (add-partials input tbl prefix)
            (descend input tbl prefix add-matches false))))

    (each [_ source (ipairs [scope.specials scope.macros
                             (or env.___replLocals___ []) env env._G])
           :until stop-looking?]
      (add-matches input-fragment source))
    matches))

(local commands {})

(fn command? [input]
  (input:match "^%s*,"))

(fn command-docs []
  (table.concat (icollect [name f (pairs commands)]
                  (: "  ,%s - %s" :format name
                     (or (compiler.metadata:get f :fnl/docstring) :undocumented)))
                "\n"))

;; fnlfmt: skip
(fn commands.help [_ _ on-values]
  "Show this message."
  (on-values [(.. "Welcome to Fennel.
This is the REPL where you can enter code to be evaluated.
You can also run these repl commands:

" (command-docs) "
  ,exit - Leave the repl.

Use ,doc something to see descriptions for individual macros and special forms.

For more information about the language, see https://fennel-lang.org/reference")]))

;; Can't rely on metadata being enabled at load time for Fennel's own internals.
(compiler.metadata:set commands.help :fnl/docstring "Show this message.")

(fn reload [module-name env on-values on-error]
  ;; Sandbox the reload inside the limited environment, if present.
  (match (pcall (specials.load-code "return require(...)" env) module-name)
    (true old) (let [_ (tset package.loaded module-name nil)
                     (ok new) (pcall require module-name)
                     ;; keep the old module if reload failed
                     new (if (not ok)
                             (do
                               (on-values [new])
                               old)
                             new)]
                 (tset specials.macro-loaded module-name nil)
                 ;; if the module isn't a table then we can't make changes
                 ;; which affect already-loaded code, but if it is then we
                 ;; should splice new values into the existing table and
                 ;; remove values that are gone.
                 (when (and (= (type old) :table) (= (type new) :table))
                   (each [k v (pairs new)]
                     (tset old k v))
                   (each [k (pairs old)]
                     (when (= nil (. new k))
                       (tset old k nil)))
                   (tset package.loaded module-name old))
                 (on-values [:ok]))
    (false msg) (if (. specials.macro-loaded module-name)
                    (tset specials.macro-loaded module-name nil)
                    ;; only show the error if it's not found in package.loaded
                    ;; AND macro-loaded
                    (on-error :Runtime (pick-values 1 (msg:gsub "\n.*" ""))))))

(fn run-command [read on-error f]
  (match (pcall read)
    (true true val) (f val)
    false (on-error :Parse "Couldn't parse input.")))

(fn commands.reload [env read on-values on-error]
  (run-command read on-error #(reload (tostring $) env on-values on-error)))

(compiler.metadata:set commands.reload :fnl/docstring
                       "Reload the specified module.")

(fn commands.reset [env _ on-values]
  (set env.___replLocals___ {})
  (on-values [:ok]))

(compiler.metadata:set commands.reset :fnl/docstring
                       "Erase all repl-local scope.")

(fn commands.complete [env read on-values on-error scope chars]
  (run-command read on-error
               #(on-values (completer env scope (-> (string.char (unpack chars))
                                                    (: :gsub ",complete +" "")
                                                    (: :sub 1 -2))))))

(compiler.metadata:set commands.complete :fnl/docstring
                       "Print all possible completions for a given input symbol.")

(fn apropos* [pattern tbl prefix seen names]
  ;; package.loaded can contain modules with dots in the names.  Such
  ;; names are renamed to contain / instead of a dot.
  (each [name subtbl (pairs tbl)]
    (when (and (= :string (type name))
               (not= package subtbl))
      (match (type subtbl)
        :function (when (: (.. prefix name) :match pattern)
                    (table.insert names (.. prefix name)))
        :table (when (not (. seen subtbl))
                 (apropos* pattern subtbl
                           (.. prefix (name:gsub "%." "/") ".")
                           (doto seen (tset subtbl true))
                           names)))))
  names)

(fn apropos [pattern]
  ;; _G. part is stripped from patterns to provide more stable output.
  ;; The order we traverse package.loaded is arbitrary, so we may see
  ;; top level functions either as is or under the _G module.
  (let [names (apropos* pattern package.loaded "" {} [])]
    (icollect [_ name (ipairs names)]
      (name:gsub "^_G%." ""))))

(fn commands.apropos [_env read on-values on-error _scope]
  (run-command read on-error #(on-values (apropos (tostring $)))))

(compiler.metadata:set commands.apropos :fnl/docstring
                       "Print all functions matching a pattern in all loaded modules.")

(fn apropos-follow-path [path]
  ;; Follow path to the target based on apropos path format
  (let [paths (icollect [p (path:gmatch "[^%.]+")] p)]
    (var tgt package.loaded)
    (each [_ path (ipairs paths)
           :until (= nil tgt)]
      (set tgt (. tgt (pick-values 1 (path:gsub "%/" ".")))))
    tgt))

(fn apropos-doc [pattern]
  "Search function documentations for a given pattern."
  (icollect [_ path (ipairs (apropos ".*"))]
    (let [tgt (apropos-follow-path path)]
      (when (= :function (type tgt))
        (match (compiler.metadata:get tgt :fnl/docstring)
          docstr (and (docstr:match pattern) path))))))

(fn commands.apropos-doc [_env read on-values on-error _scope]
  (run-command read on-error #(on-values (apropos-doc (tostring $)))))

(compiler.metadata:set commands.apropos-doc :fnl/docstring
                       "Print all functions that match the pattern in their docs")

(fn apropos-show-docs [on-values pattern]
  "Print function documentations for a given function pattern."
  (each [_ path (ipairs (apropos pattern))]
    (let [tgt (apropos-follow-path path)]
      (when (and (= :function (type tgt))
                 (compiler.metadata:get tgt :fnl/docstring))
        (on-values (specials.doc tgt path))
        (on-values)))))

(fn commands.apropos-show-docs [_env read on-values on-error]
  (run-command read on-error #(apropos-show-docs on-values (tostring $))))

(compiler.metadata:set commands.apropos-show-docs :fnl/docstring
                       "Print all documentations matching a pattern in function name")

(fn resolve [identifier {: ___replLocals___ &as env} scope]
  (let [e (setmetatable {} {:__index #(or (. ___replLocals___ $2) (. env $2))})]
    (match (pcall compiler.compile-string (tostring identifier) {: scope})
      (true code) ((specials.load-code code e)))))

(fn commands.find [env read on-values on-error scope]
  (run-command read on-error
               #(match (-?> (utils.sym? $) (resolve env scope) (debug.getinfo))
                  {:what "Lua" : source :linedefined line :short_src src}
                  (let [fnlsrc (?. compiler.sourcemap source line 2)]
                    (on-values [(string.format "%s:%s" src (or fnlsrc line))]))
                   nil (on-error :Repl "Unknown value")
                   _ (on-error :Repl "No source info"))))

(compiler.metadata:set commands.find :fnl/docstring
                       "Print the filename and line number for a given function")

(fn commands.doc [env read on-values on-error scope]
  (run-command read on-error
               #(let [name (tostring $)
                      path (or (utils.multi-sym? name) [name])
                      (ok? target) (pcall #(or (utils.get-in scope.specials path)
                                               (utils.get-in scope.macros path)
                                               (resolve name env scope)))]
                  (if ok?
                      (on-values [(specials.doc target name)])
                      (on-error :Repl "Could not resolve value for docstring lookup")))))

(compiler.metadata:set commands.doc :fnl/docstring
                       "Print the docstring and arglist for a function, macro, or special form.")

(fn commands.compile [env read on-values on-error scope]
  (run-command read on-error
               #(let  [allowedGlobals (specials.current-global-names env)
                       (ok? result) (pcall compiler.compile
                                           $ {: env : scope : allowedGlobals})]
                  (if ok?
                      (on-values [result])
                      (on-error :Repl (.. "Error compiling expression: " result))))))

(compiler.metadata:set commands.compile :fnl/docstring
                       "compiles the expression into lua and prints the result.")

(fn load-plugin-commands [plugins]
  (each [_ plugin (ipairs (or plugins []))]
    (each [name f (pairs plugin)]
      ;; first function to provide a command should win
      (match (name:match "^repl%-command%-(.*)")
        cmd-name (tset commands cmd-name (or (. commands cmd-name) f))))))

(fn run-command-loop [input read loop env on-values on-error scope chars]
  (let [command-name (input:match ",([^%s/]+)")]
    (match (. commands command-name)
      command (command env read on-values on-error scope chars)
      _ (when (not= :exit command-name)
          (on-values ["Unknown command" command-name])))
    (when (not= :exit command-name)
      (loop))))

(fn try-readline! [opts ok readline]
  (when ok
    (when readline.set_readline_name
      (readline.set_readline_name :fennel))
    ;; set_options returns current options so we can preserve whatever was
    ;; already set in the .fennelrc file
    (let [rl-opts (collect [k v (pairs (readline.set_options {}))
                            :into {:keeplines 1000 :histfile ""}]
                    (values k v))]
      (readline.set_options rl-opts))

    (fn opts.readChunk [parser-state]
      (let [prompt (if (< 0 parser-state.stack-size) ".. " ">> ")
            str (readline.readline prompt)]
        (if str (.. str "\n"))))

    (var completer nil)

    (fn opts.registerCompleter [repl-completer]
      (set completer repl-completer))

    (fn repl-completer [text from to]
      (if completer
          (do
            (readline.set_completion_append_character "")
            (completer (text:sub from to)))
          []))

    (readline.set_complete_function repl-completer)
    readline))

(fn should-use-readline? [opts]
  (and (not= "dumb" (os.getenv "TERM"))
       (not opts.readChunk)
       (not opts.registerCompleter)))

(fn repl [?options]
  (let [old-root-options utils.root.options
        opts (or (and ?options (utils.copy ?options)) {})
        readline (and (should-use-readline? opts)
                      (try-readline! opts (pcall require :readline)))
        env (specials.wrap-env (or opts.env (rawget _G :_ENV) _G))
        save-locals? (not= opts.saveLocals false)
        read-chunk (or opts.readChunk default-read-chunk)
        on-values (or opts.onValues default-on-values)
        on-error (or opts.onError default-on-error)
        pp (or opts.pp view)
        (byte-stream clear-stream) (parser.granulate read-chunk)
        chars []
        (read reset) (parser.parser (fn [parser-state]
                                      (let [c (byte-stream parser-state)]
                                        (table.insert chars c)
                                        c)))]
    (set (opts.env opts.scope) (values env (compiler.make-scope)))
    ;; use metadata unless we've specifically disabled it
    (set opts.useMetadata (not= opts.useMetadata false))
    (when (= opts.allowedGlobals nil)
      (set opts.allowedGlobals (specials.current-global-names env)))
    (when opts.registerCompleter
      (opts.registerCompleter (partial completer env opts.scope)))
    (load-plugin-commands opts.plugins)

    (when save-locals?
      (fn newindex [t k v] (when (. opts.scope.unmanglings k) (rawset t k v)))
      (set env.___replLocals___ (setmetatable {} {:__newindex newindex})))

    (fn print-values [...]
      (let [vals [...]
            out []]
        (set (env._ env.__) (values (. vals 1) vals))
        ;; utils.map won't work here because of sparse tables
        (for [i 1 (select "#" ...)]
          (table.insert out (pp (. vals i))))
        (on-values out)))

    (fn loop []
      (each [k (pairs chars)]
        (tset chars k nil))
      (reset)
      (let [(ok not-eof? x) (pcall read)
            src-string (string.char (unpack chars))]
        (if (not ok)
            (do
              (on-error :Parse not-eof?)
              (clear-stream)
              (loop))
            (command? src-string)
            (run-command-loop src-string read loop env on-values on-error
                              opts.scope chars)
            (when not-eof?
              (match (pcall compiler.compile x (doto opts
                                                 (tset :source src-string)))
                (false msg) (do
                              (clear-stream)
                              (on-error :Compile msg))
                (true src) (let [src (if save-locals?
                                         (splice-save-locals env src opts.scope)
                                         src)]
                             (match (pcall specials.load-code src env)
                               (false msg) (do
                                             (clear-stream)
                                             (on-error "Lua Compile" msg src))
                               (_ chunk) (xpcall #(print-values (chunk))
                                                 (partial on-error :Runtime)))))
              (set utils.root.options old-root-options)
              (loop)))))

    (loop)
    (when readline
      (readline.save_history))))
