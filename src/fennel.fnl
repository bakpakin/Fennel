;; Copyright © 2016-2020 Calvin Rose and contributors
;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to
;; deal in the Software without restriction, including without limitation the
;; rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
;; sell copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions: The above copyright
;; notice and this permission notice shall be included in all copies or
;; substantial portions of the Software.  THE SOFTWARE IS PROVIDED "AS IS",
;; WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
;; TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
;; LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
;; CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
;; SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

(local utils (require :fennel.utils))
(local parser (require :fennel.parser))
(local compiler (require :fennel.compiler))
(local specials (require :fennel.specials))
(local repl (require :fennel.repl))

(fn eval [str options ...]
  ;; eval and dofile are considered "live" entry points, so we can assume
  ;; that the globals available at compile time are a reasonable allowed list
  ;; UNLESS there's a metatable on env, in which case we can't assume that
  ;; pairs will return all the effective globals; for instance openresty
  ;; sets up _G in such a way that all the globals are available thru
  ;; the __index meta method, but as far as pairs is concerned it's empty.
  (let [opts (utils.copy options)
        _ (when (and (= opts.allowedGlobals nil)
                     (not (getmetatable opts.env)))
            (set opts.allowedGlobals (specials.currentGlobalNames opts.env)))
        env (and opts.env (specials.wrapEnv opts.env))
        lua-source (compiler.compileString str opts)
        loader (specials.loadCode lua-source env
                                  (if opts.filename
                                      (.. "@" opts.filename) str))]
    (set opts.filename nil)
    (loader ...)))

(fn dofile* [filename options ...]
  (let [opts (utils.copy options)
        f (assert (io.open filename :rb))
        source (f:read :*all)]
    (f:close)
    (set opts.filename filename)
    (eval source opts ...)))

;; The public API module we export:
(local mod {:list utils.list
            :sym utils.sym
            :varg utils.varg
            :path utils.path

            :parser parser.parser
            :granulate parser.grandulate
            :stringStream parser.stringStream

            :compile compiler.compile
            :compileString compiler.compileString
            :compileStream compiler.compileStream
            :compile1 compiler.compile1
            :traceback compiler.traceback
            :mangle compiler.globalMangling
            :unmangle compiler.globalUnmangling
            :metadata compiler.metadata
            :scope compiler.makeScope
            :gensym compiler.gensym

            :loadCode specials.loadCode
            :macroLoaded specials.macroLoaded
            :searchModule specials.searchModule
            :makeSearcher specials.makeSearcher
            :make_searcher specials.makeSearcher ; backwards-compatibility alias
            :searcher (specials.makeSearcher)
            :doc specials.doc

            :eval eval
            :dofile dofile*
            :version "0.5.0-dev"

            :repl repl})

;; This is bad; we have a circular dependency between the specials section and
;; the evaluation section due to require-macros/import-macros, etc. For now
;; stash it in the utils table, but we should untangle it
(set utils.fennelModule mod)

;; Load the built-in macros from macros.fnl.
(let [builtin-macros (eval-compiler
                       (with-open [f (assert (io.open "src/fennel/macros.fnl"))]
                         (.. "[===[" (f:read "*all") "]===]")))
      module-name "fennel.macros"
      _ (tset package.preload module-name #mod)
      env (specials.makeCompilerEnv nil compiler.scopes.compiler {})
      built-ins (eval builtin-macros {:env env
                                      :scope compiler.scopes.compiler
                                      :allowedGlobals false
                                      :useMetadata true
                                      :filename "src/fennel/macros.fnl"
                                      :moduleName module-name})]
  (each [k v (pairs built-ins)]
    (tset compiler.scopes.global.macros k v))
  (set compiler.scopes.global.macros.λ compiler.scopes.global.macros.lambda)
  (tset package.preload module-name nil))

mod
