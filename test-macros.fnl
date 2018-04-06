;; this module is loaded by the test suite, but these are handy macros to
;; have around so feel free to steal them for your own projects.
{"->1" (fn [val ...]
        (var x val)
        (each [_ elt (ipairs [...])]
          (table.insert elt 2 x)
          (set x elt))
        x)
 :defn1 (fn [name args ...]
         (assert (sym? name) "defn: function names must be symbols")
         (list (sym "global") name
               (list (sym "fn") args ...)))}
