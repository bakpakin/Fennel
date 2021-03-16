;; this module is loaded by the test suite.

(fn def [] (error "oh no") 32)
(fn abc [] (def) 1)

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
                   (+ (x#:abc) y#.one)))
 :unsandboxed (fn [] (view [:no :sandbox]))
 :fail-one (fn [x] (when (= x 1) (abc)) true)}
