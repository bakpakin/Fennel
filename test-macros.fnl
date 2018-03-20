;; this module is loaded by the test suite, but these are handy macros to
;; have around so feel free to steal them for your own projects.
{"->" (fn [val ...]
        (each [_ elt (pairs [...])]
          (table.insert elt 2 val)
          (set elt.n (+ 1 elt.n))
          (set val elt))
        val)
 :defn (fn [name args ...]
         (list (sym "set!") name
               (list (sym "fn") args ...)))}
