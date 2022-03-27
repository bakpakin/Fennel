;; An example of some possible linters using Fennel's --plugin option.

;; The first two linters here can only function on static module
;; use. For instance, this code can be checked because they use static
;; field access on a local directly bound to a require call:

;; (local m (require :mymodule))
;; (print m.field) ; fails if mymodule lacks a :field field
;; (print (m.function 1 2 3)) ; fails unless mymodule.function takes 3 args

;; However, these cannot:

;; (local m (do (require :mymodule)) ; m is not directly bound
;; (print (. m field)) ; not a static field reference
;; (let [f m.function]
;;   (print (f 1 2 3)) ; intermediate local, not a static field call on m

;; Still, pretty neat, huh?

;; This file is provided as an example and is not part of Fennel's public API.

(fn save-require-meta [from to scope]
  "When destructuring, save module name if local is bound to a `require' call.
Doesn't do any linting on its own; just saves the data for other linters."
  (when (and (sym? to) (not (multi-sym? to)) (list? from)
             (sym? (. from 1)) (= :require (tostring (. from 1)))
             (= :string (type (. from 2))))
    (let [meta (. scope.symmeta (tostring to))]
      (set meta.required (tostring (. from 2))))))

(fn check-module-fields [symbol scope]
  "When referring to a field in a local that's a module, make sure it exists."
  (let [[module-local field] (or (multi-sym? symbol) [])
        module-name (-?> scope.symmeta (. (tostring module-local)) (. :required))
        module (and module-name (require module-name))]
    (assert-compile (or (= module nil) (not= (. module field) nil))
                    (string.format "Missing field %s in module %s"
                                   (or field :?) (or module-name :?)) symbol)))

(fn arity-check? [module module-name]
  (or (-?> module getmetatable (. :arity-check?))
      (pcall debug.getlocal #nil 1) ; PUC 5.1 can't use debug.getlocal for this
      ;; I don't love this method of configuration but it gets the job done.
      (match (and module-name os os.getenv (os.getenv "FENNEL_LINT_MODULES"))
        module-pattern (module-name:find module-pattern))))

(fn descend [target [part & parts]]
  (if (= nil part) target
      (= :table (type target)) (match (. target part)
                                 new-target (descend new-target parts))
      target))

(fn min-arity [target last-required name]
  (match (debug.getlocal target last-required)
    localname (if (and (localname:match "^_3f") (< 0 last-required))
                  (min-arity target (- last-required 1))
                  last-required)
    _ last-required))

(fn arity-check-call [[f & args] scope]
  "Perform static arity checks on static function calls in a module."
  (let [last-arg (. args (length args))
        arity (if (: (tostring f) :find ":") ; method
                  (+ (length args) 1)
                  (length args))
        [f-local & parts] (or (multi-sym? f) [])
        module-name (-?> scope.symmeta (. (tostring f-local)) (. :required))
        module (and module-name (require module-name))
        field (table.concat parts ".")
        target (descend module parts)]
    (when (and (arity-check? module module-name) _G.debug _G.debug.getinfo
               module (not (varg? last-arg)) (not (list? last-arg)))
      (assert-compile (= (type target) :function)
                      (string.format "Missing function %s in module %s"
                                     (or field :?) module-name) f)
      (match (_G.debug.getinfo target)
        {: nparams :what "Lua"}
        (let [min (min-arity target nparams f)]
          (assert-compile (<= min arity)
                          (: "Called %s with %s arguments, expected at least %s"
                             :format f arity min) f))))))

(fn check-unused [ast scope]
  (each [symname (pairs scope.symmeta)]
    (assert-compile (or (. scope.symmeta symname :used) (symname:find "^_"))
                    (string.format "unused local %s" (or symname :?)) ast)))

{:destructure save-require-meta
 :symbol-to-expression check-module-fields
 :call arity-check-call
 ;; Note that this will only check unused args inside functions and let blocks,
 ;; not top-level locals of a chunk.
 :fn check-unused
 :do check-unused
 :chunk check-unused
 :name "fennel/linter"
 :versions ["1.0.0" "1.1.0"]}
