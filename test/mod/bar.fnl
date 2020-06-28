(local bar [:BAR 2])
(each [_ v (ipairs (include :test.mod.baz))]
  (table.insert bar v))
bar
