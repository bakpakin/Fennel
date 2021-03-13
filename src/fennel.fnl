;; Copyright © 2016-2021 Calvin Rose and contributors
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

;; This module ties everything else together; it's the public interface of
;; the compiler. All other modules should be considered implementation details
;; subject to change.

(local utils (require :fennel.utils))
(local parser (require :fennel.parser))
(local compiler (require :fennel.compiler))
(local specials (require :fennel.specials))
(local repl (require :fennel.repl))
(local view (require :fennel.view))

(fn eval-env [env]
  ;; This is ... not great. Should we expose make-compiler-env in the API?
  ;; Don't use this; it's subject to change in future versions!
  (if (= env :_COMPILER)
      (let [env (specials.make-compiler-env nil compiler.scopes.compiler {})
            mt (getmetatable env)]
        ;; remove sandboxing; linting won't work with it
        (set mt.__index _G)
        (specials.wrap-env env))
      (and env (specials.wrap-env env))))

(fn eval-opts [options str]
  (let [opts (utils.copy options)]
    ;; eval and dofile are considered "live" entry points, so we can assume
    ;; that the globals available at compile time are a reasonable allowed list
    ;; UNLESS there's a metatable on env, in which case we can't assume that
    ;; pairs will return all the effective globals; for instance openresty
    ;; sets up _G in such a way that all the globals are available thru
    ;; the __index meta method, but as far as pairs is concerned it's empty.
    (when (and (= opts.allowedGlobals nil) (not (getmetatable opts.env)))
      (set opts.allowedGlobals (specials.current-global-names opts.env)))
    ;; if the code doesn't have a filename attached, save the source in order
    ;; to provide targeted error messages.
    (when (and (not opts.filename) (not opts.source))
      (set opts.source str))
    opts))

(fn eval [str options ...]
  (let [opts (eval-opts options str)
        env (eval-env opts.env)
        lua-source (compiler.compile-string str opts)
        loader (specials.load-code lua-source env
                                   (if opts.filename
                                       (.. "@" opts.filename)
                                       str))]
    (set opts.filename nil)
    (loader ...)))

(fn dofile* [filename options ...]
  (let [opts (utils.copy options)
        f (assert (io.open filename :rb))
        source (assert (f:read :*all) (.. "Could not read " filename))]
    (f:close)
    (set opts.filename filename)
    (eval source opts ...)))

;; The public API module we export:
(local mod {:list utils.list
            :list? utils.list?
            :sym utils.sym
            :sym? utils.sym?
            :sequence utils.sequence
            :sequence? utils.sequence?
            :comment utils.comment
            :comment? utils.comment?
            :varg utils.varg
            :path utils.path
            :sym-char? parser.sym-char?
            :parser parser.parser
            :granulate parser.granulate
            :string-stream parser.string-stream
            :compile compiler.compile
            :compile-string compiler.compile-string
            :compile-stream compiler.compile-stream
            :compile1 compiler.compile1
            :traceback compiler.traceback
            :mangle compiler.global-mangling
            :unmangle compiler.global-unmangling
            :metadata compiler.metadata
            :scope compiler.make-scope
            :gensym compiler.gensym
            :load-code specials.load-code
            :macro-loaded specials.macro-loaded
            :search-module specials.search-module
            :make-searcher specials.make-searcher
            :makeSearcher specials.make-searcher
            :searcher (specials.make-searcher)
            :doc specials.doc
            : view
            : eval
            :dofile dofile*
            :version :0.8.2-dev
            : repl
            ;; backwards-compatibility aliases
            :loadCode specials.load-code
            :make_searcher specials.make-searcher
            :searchModule specials.search-module
            :macroLoaded specials.macro-loaded
            :compileStream compiler.compile-stream
            :compileString compiler.compile-string
            :stringStream parser.string-stream})

;; This is bad; we have a circular dependency between the specials section and
;; the evaluation section due to require-macros/import-macros, etc. For now
;; stash it in the utils table, but we should untangle it
(set utils.fennel-module mod)

;; Load the built-in macros from macros.fnl.
(let [builtin-macros (eval-compiler
                       (with-open [f (assert (io.open :src/fennel/macros.fnl))]
                         (.. "[===[" (f:read :*all) "]===]")))
      module-name :fennel.macros
      _ (tset package.preload module-name #mod)
      env (doto (specials.make-compiler-env nil compiler.scopes.compiler {})
            (tset :utils utils) ; for import-macros to propagate compile opts
            (tset :fennel mod))
      built-ins (eval builtin-macros
                      {: env
                       :scope compiler.scopes.compiler
                       :allowedGlobals false
                       :useMetadata true
                       :filename :src/fennel/macros.fnl
                       :moduleName module-name})]
  (each [k v (pairs built-ins)]
    (tset compiler.scopes.global.macros k v))
  (set compiler.scopes.global.macros.λ compiler.scopes.global.macros.lambda)
  (tset package.preload module-name nil))

mod
