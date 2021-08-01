(when true (table.concat [] :yes))
(local q (include "test.mod.quux"))

(setmetatable {:myfn (fn [a b c] (print a b c))}
              {:arity-check? true})
