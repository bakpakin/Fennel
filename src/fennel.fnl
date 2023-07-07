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

(fn eval-env [env opts]
  (if (= env :_COMPILER)
      (let [env (specials.make-compiler-env nil compiler.scopes.compiler {} opts)]
        ;; re-enable globals-checking; previous globals-checking below doesn't
        ;; work on the compiler env because of the sandbox.
        (when (= opts.allowedGlobals nil)
          (set opts.allowedGlobals (specials.current-global-names env)))
        (specials.wrap-env env))
      (and env (specials.wrap-env env))))

(fn eval-opts [options str]
  (let [opts (utils.copy options)]
    ;; eval and dofile are considered "live" entry points, so we can assume
    ;; that the globals available at compile time are a reasonable allowed list
    (when (= opts.allowedGlobals nil)
      (set opts.allowedGlobals (specials.current-global-names opts.env)))
    ;; if the code doesn't have a filename attached, save the source in order
    ;; to provide targeted error messages.
    (when (and (not opts.filename) (not opts.source))
      (set opts.source str))
    (when (= opts.env :_COMPILER)
      (set opts.scope (compiler.make-scope compiler.scopes.compiler)))
    opts))

(fn eval [str ?options ...]
  (let [opts (eval-opts ?options str)
        env (eval-env opts.env opts)
        lua-source (compiler.compile-string str opts)
        loader (specials.load-code lua-source env
                                   (if opts.filename
                                       (.. "@" opts.filename)
                                       str))]
    (set opts.filename nil)
    (loader ...)))

(fn dofile* [filename ?options ...]
  (let [opts (utils.copy ?options)
        f (assert (io.open filename :rb))
        source (assert (f:read :*all) (.. "Could not read " filename))]
    (f:close)
    (set opts.filename filename)
    (eval source opts ...)))

(fn syntax []
  "Return a table describing the callable forms known by Fennel."
  (let [body? [:when :with-open :collect :icollect :fcollect :lambda :λ
               :macro :match :match-try :case :case-try :accumulate
               :faccumulate :doto]
        binding? [:collect :icollect :fcollect :each :for :let :with-open
                  :accumulate :faccumulate]
        define? [:fn :lambda :λ :var :local :macro :macros :global]
        out {}]
    (each [k v (pairs compiler.scopes.global.specials)]
      (let [metadata (or (. compiler.metadata v) {})]
        (tset out k {:special? true :body-form? metadata.fnl/body-form?
                     :binding-form? (utils.member? k binding?)
                     :define? (utils.member? k define?)})))
    (each [k v (pairs compiler.scopes.global.macros)]
      (tset out k {:macro? true :body-form? (utils.member? k body?)
                   :binding-form? (utils.member? k binding?)
                   :define? (utils.member? k define?)}))
    (each [k v (pairs _G)]
      (match (type v)
        :function (tset out k {:global? true :function? true})
        :table (do
                 (each [k2 v2 (pairs v)]
                   (when (and (= :function (type v2)) (not= k :_G))
                     (tset out (.. k "." k2) {:function? true :global? true})))
                 (tset out k {:global? true}))))
    out))

;; The public API module we export:
(local mod {;; AST functions
            :list utils.list
            :list? utils.list?
            :sym utils.sym
            :sym? utils.sym?
            :multi-sym? utils.multi-sym?
            :sequence utils.sequence
            :sequence? utils.sequence?
            :table? utils.table?
            :comment utils.comment
            :comment? utils.comment?
            :varg utils.varg
            :varg? utils.varg?
            ;; parsing
            :sym-char? parser.sym-char?
            :parser parser.parser
            ;; compiling
            :compile compiler.compile
            :compile-string compiler.compile-string
            :compile-stream compiler.compile-stream
            ;; running code
            : eval
            : repl
            : view
            :dofile dofile*
            :load-code specials.load-code
            ;; examining
            :doc specials.doc
            :metadata compiler.metadata
            :traceback compiler.traceback
            :version utils.version
            :runtime-version utils.runtime-version
            :ast-source utils.ast-source
            ;; finding code
            :path utils.path
            :macro-path utils.macro-path
            :macro-loaded specials.macro-loaded
            :macro-searchers specials.macro-searchers
            :search-module specials.search-module
            :make-searcher specials.make-searcher
            :searcher (specials.make-searcher)
            : syntax
            ;; deprecated; you probably don't want these
            :gensym compiler.gensym
            :scope compiler.make-scope
            :mangle compiler.global-mangling
            :unmangle compiler.global-unmangling
            :compile1 compiler.compile1
            :string-stream parser.string-stream
            :granulate parser.granulate
            ;; backwards-compatibility aliases
            :loadCode specials.load-code
            :make_searcher specials.make-searcher
            :makeSearcher specials.make-searcher
            :searchModule specials.search-module
            :macroPath utils.macro-path
            :macroSearchers specials.macro-searchers
            :macroLoaded specials.macro-loaded
            :compileStream compiler.compile-stream
            :compileString compiler.compile-string
            :stringStream parser.string-stream
            :runtimeVersion utils.runtime-version})

(fn mod.install [?opts]
  (table.insert (or package.searchers package.loaders)
                (specials.make-searcher ?opts))
  mod)

;; This is bad; we have a circular dependency between the specials section and
;; the evaluation section due to require-macros/import-macros, etc. For now
;; stash it in the utils table, but we should untangle it
(set utils.fennel-module mod)

(macro embed-src [filename]
  `(eval-compiler
     (let [FENNEL_SRC# (and (= :table (type os)) os.getenv
                            (os.getenv :FENNEL_SRC))
           root# (if FENNEL_SRC# (.. FENNEL_SRC# :/) "")]
       (with-open [f# (assert (io.open (.. root# ,filename)))]
         (.. "[===[" (f#:read :*all) "]===]")))))

;; Load the built-in macros from macros.fnl and match.fnl
(let [module-name :fennel.macros
      _ (tset package.preload module-name #mod)
      env (doto (specials.make-compiler-env nil compiler.scopes.compiler {})
            (tset :utils utils) ; for import-macros to propagate compile opts
            (tset :fennel mod))
      built-ins (eval (embed-src :src/fennel/macros.fnl)
                      {: env
                       :scope compiler.scopes.compiler
                       :useMetadata true
                       :filename :src/fennel/macros.fnl
                       :moduleName module-name})
      _ (each [k v (pairs built-ins)] (tset compiler.scopes.global.macros k v))
      match-macros (eval (embed-src :src/fennel/match.fnl)
                         {: env
                          :scope compiler.scopes.compiler
                          :allowedGlobals false
                          :useMetadata true
                          :filename :src/fennel/match.fnl
                          :moduleName module-name})]
  (each [k v (pairs match-macros)] (tset compiler.scopes.global.macros k v))
  (tset package.preload module-name nil))

mod
