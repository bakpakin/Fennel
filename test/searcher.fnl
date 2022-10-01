(local l (require :test.luaunit))
(local fennel (require :fennel))

(fn test-searcher-error-contains-fnl-files []
  (let [(ok error) (pcall require :notreal)]
    (l.assertEquals ok false)
    (l.assertEquals (string.match error :notreal.fnl) :notreal.fnl)))

(fn with-preserve-searchers [f]
  (let [searchers-tbl (or package.searchers package.loaders)
        old-searchers (icollect [_ s (ipairs searchers-tbl)] s)]
    (while (next searchers-tbl) (table.remove searchers-tbl))
    (pcall f)
    (while (next searchers-tbl) (table.remove searchers-tbl))
    (each [_ s (ipairs old-searchers)]
      (table.insert searchers-tbl s))))

(fn test-install []
  (tset package.loaded :test.searcher nil)
  (with-preserve-searchers
   #(do (fennel.install {})
        (l.assertTrue (pcall require :test.searcher)))))

{: test-searcher-error-contains-fnl-files
 : test-install}
