;; this module is loaded by the test suite.
{"->1" (fn [val ...]
        (var x val)
        (each [_ elt (ipairs [...])]
          (table.insert elt 2 x)
          (set x elt))
        x)
 :defn1 (fn [name args ...]
          (assert (sym? name) "defn1: function names must be symbols")
          `(global ,name (fn ,args ,...)))
 :inc   (fn [n] (if (not (list? n)) `(+ ,n 1)
                    `(let [num# ,n] (+ num# 1))))
 :inc! (fn [a ?n] `(set ,a (+ ,a (or ,?n 1))))
 :multigensym (fn []
                `(let [x# {:abc (fn [] 518)}
                       y# {:one 1}]
                   (+ (x#:abc) y#.one)))}
