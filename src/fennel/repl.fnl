;; This module is the read/eval/print loop; for coding Fennel interactively.

;; The most complex thing it does is locals-saving, which allows locals to be
;; preserved in between "chunks"; by default Lua throws away all locals after
;; evaluating each piece of input.

(local utils (require :fennel.utils))
(local parser (require :fennel.parser))
(local compiler (require :fennel.compiler))
(local specials (require :fennel.specials))

(fn default-read-chunk [parser-state]
  (io.write (if (< 0 parser-state.stack-size) ".." ">> "))
  (io.flush)
  (let [input (io.read)]
    (and input (.. input "\n"))))

(fn default-on-values [xs]
  (io.write (table.concat xs "\t"))
  (io.write "\n"))

(fn default-on-error [errtype err lua-source]
  (io.write
   (match errtype
     "Lua Compile" (.. "Bad code generated - likely a bug with the compiler:\n"
                       "--- Generated Lua Start ---\n"
                       lua-source
                       "--- Generated Lua End ---\n")
     "Runtime" (.. (compiler.traceback err 4) "\n")
     _ (: "%s error: %s\n" :format errtype (tostring err)))))

(local save-source
       (table.concat ["local ___i___ = 1"
                      "while true do"
                      " local name, value = debug.getlocal(1, ___i___)"
                      " if(name and name ~= \"___i___\") then"
                      " ___replLocals___[name] = value"
                      " ___i___ = ___i___ + 1"
                      " else break end end"] "\n"))

(fn splice-save-locals [env lua-source]
  (set env.___replLocals___ (or env.___replLocals___ {}))
  (let [spliced-source []
        bind "local %s = ___replLocals___['%s']"]
    (each [line (lua-source:gmatch "([^\n]+)\n?")]
      (table.insert spliced-source line))
    (each [name (pairs env.___replLocals___)]
      (table.insert spliced-source 1 (bind:format name name)))
    (when (and (< 1 (# spliced-source))
               (: (. spliced-source (# spliced-source)) :match "^ *return .*$"))
      (table.insert spliced-source (# spliced-source) save-source))
    (table.concat spliced-source "\n")))

(fn completer [env scope text]
  (let [matches []
        input-fragment (text:gsub ".*[%s)(]+" "")]
    (fn add-partials [input tbl prefix] ; add partial key matches in tbl
      (each [k (utils.allpairs tbl)]
        (let [k (if (or (= tbl env) (= tbl env.___replLocals___))
                    (. scope.unmanglings k)
                    k)]
          (when (and (< (# matches) 2000) ; stop explosion on too many items
                     (= (type k) "string")
                     (= input (k:sub 0 (# input))))
            (table.insert matches (.. prefix k))))))
    (fn add-matches [input tbl prefix] ; add matches, descending into tbl fields
      (let [prefix (if prefix (.. prefix ".") "")]
        (if (not (input:find "%.")) ; no more dots, so add matches
            (add-partials input tbl prefix)
            (let [(head tail) (input:match "^([^.]+)%.(.*)")
                  raw-head (if (or (= tbl env) (= tbl env.___replLocals___))
                               (. scope.manglings head)
                               head)]
              (when (= (type (. tbl raw-head)) "table")
                (add-matches tail (. tbl raw-head) (.. prefix head)))))))

    (add-matches input-fragment (or scope.specials []))
    (add-matches input-fragment (or scope.macros []))
    (add-matches input-fragment (or env.___replLocals___ []))
    (add-matches input-fragment env)
    (add-matches input-fragment (or env._ENV env._G []))
    matches))

(fn repl [options]
  (let [old-root-options utils.root.options
        env (if options.env
                (specials.wrap-env options.env)
                (setmetatable {} {:__index (or _G._ENV _G)}))
        save-locals? (and (not= options.saveLocals false)
                          env.debug env.debug.getlocal)
        opts {}
        _ (each [k v (pairs options)] (tset opts k v))
        read-chunk (or opts.readChunk default-read-chunk)
        on-values (or opts.onValues default-on-values)
        on-error (or opts.onError default-on-error)
        pp (or opts.pp tostring)
        ;; make parser
        (byte-stream clear-stream) (parser.granulate read-chunk)
        chars []
        (read reset) (parser.parser (fn [parser-state]
                                      (let [c (byte-stream parser-state)]
                                        (tset chars (+ (# chars) 1) c)
                                        c)))
        scope (compiler.make-scope)]

    ;; use metadata unless we've specifically disabled it
    (set opts.useMetadata (not= options.useMetadata false))
    (when (= opts.allowedGlobals nil)
      (set opts.allowedGlobals (specials.current-global-names opts.env)))

    (when opts.registerCompleter
      (opts.registerCompleter (partial completer env scope)))

    (fn loop []
      (each [k (pairs chars)] (tset chars k nil))
      (let [(ok parse-ok? x) (pcall read)
            src-string (string.char ((or _G.unpack table.unpack) chars))]
        (set utils.root.options opts)
        (if (not ok)
            (do (on-error "Parse" parse-ok?)
                (clear-stream)
                (reset)
                (loop))
            (when parse-ok? ; if this is false, we got eof
              (match (pcall compiler.compile x {:correlate opts.correlate
                                                :source src-string
                                                :scope scope
                                                :useMetadata opts.useMetadata
                                                :moduleName opts.moduleName
                                                :assert-compile opts.assert-compile
                                                :parse-error opts.parse-error})
                (false msg) (do (clear-stream)
                                (on-error "Compile" msg))
                (true source) (let [source (if save-locals?
                                               (splice-save-locals env source)
                                               source)
                                    (lua-ok? loader) (pcall specials.load-code
                                                            source env)]
                                (if (not lua-ok?)
                                    (do (clear-stream)
                                        (on-error "Lua Compile" loader source))
                                    (match (xpcall #[(loader)]
                                                   (partial on-error "Runtime"))
                                      (true ret)
                                      (do (set env._ (. ret 1))
                                          (set env.__ ret)
                                          (on-values (utils.map ret pp)))))))
              (set utils.root.options old-root-options)
              (loop)))))
    (loop)))
