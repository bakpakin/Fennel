(macro abc [x]
  `(let [y 2]
     ,x))

(let [xyz 123]
  (abc xyz))
