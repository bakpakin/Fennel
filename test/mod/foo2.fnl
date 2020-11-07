(local foo [:FOO 1])
(local quux (require :test.mod.quux))
(local bar (require :test.mod.bar))
{:result (.. "foo:" (table.concat foo "-") "bar:" (table.concat bar "-"))
 : quux}
