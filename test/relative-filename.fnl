(require-macros ((fn [mod fname]
                   ;; this expression is evaluated by the compiler with
                   ;; the current module and filename injected via ...
                   ;; mod name is this module
                   (assert (= mod :test.relative-filename))
                   ;; filename is this file
                   (assert (= fname :./test/relative-filename.fnl)
                           "filename was incorrect")
                   ;; return a good value as we are not testing this.
                   (values :test.relative.macros)) ...))

(import-macros {:inc i-inc} ((fn [mod fname]
                               (assert (= mod :test.relative-filename))
                               (assert (= fname :./test/relative-filename.fnl)
                                       "filename was incorrect")
                               ;; return a good value as we are not testing this.
                               (values :test.relative.macros)) ...))
(+ (i-inc 0) (inc 0))
