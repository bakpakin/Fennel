;; this module is loaded by the test suite, but these are handy macros to
;; have around so feel free to steal them for your own projects.
{"->" (fn [val ...]
        (var x val)
        (each [_ elt (pairs [...])]
          (table.insert elt 2 x)
          (set elt.n (+ 1 elt.n))
          (set x elt))
        x)
 :defn (fn [name args ...]
         (list (sym "global") name
               (list (sym "fn") args ...)))}
