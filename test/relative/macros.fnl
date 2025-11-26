{:inc (fn [x] (+ x 1))
 :tbl-macro (setmetatable {:sub-macro (fn [] "sub-macro on a callable table macro")}
                          {:__call (fn tbl-macro [_] "callable table macro")}) }
