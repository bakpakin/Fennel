;; this module is loaded by the test suite.
{"->1" (fn [val ...]
        (var x val)
        (each [_ elt (ipairs [...])]
          (table.insert elt 2 x)
          (set x elt))
        x)
 :defn1 (fn [name args ...]
          (assert (sym? name) "defn1: function names must be symbols")
          `(global ,name (fn ,args ,...)))}
