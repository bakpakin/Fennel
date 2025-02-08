(local t (require :test.faith))
(local fennel (require :fennel))

(fn test-searcher-error-contains-fnl-files []
  (let [(ok error) (pcall require :notreal)]
    (t.= ok false)
    (t.= (string.match error :notreal.fnl) :notreal.fnl)))

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
        (t.is (pcall require :test.searcher)))))

(fn test-searcher []
  (t.= "./test/searcher.fnl" (fennel.search-module "test/searcher"))
  (t.= "./src/fennel.fnl" (fennel.search-module "src.fennel"))
  (t.= nil (fennel.search-module "test.bad.with.dots")))

{: test-searcher-error-contains-fnl-files
 : test-install
 : test-searcher}
