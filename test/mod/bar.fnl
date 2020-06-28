(local bar [:BAR 2])
(each [_ v (ipairs (include :baz))]
  (table.insert bar v))
bar
