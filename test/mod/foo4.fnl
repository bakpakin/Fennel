(local foo [:FOO 1])
(local quux (include (.. :test :.mod.quux)))
(local bar (include (.. :test :.mod :.bar)))
{:result (.. "foo:" (table.concat foo "-") "bar:" (table.concat bar "-"))
 : quux}
