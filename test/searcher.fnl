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
    (let [res [(pcall f)]]
      (while (next searchers-tbl) (table.remove searchers-tbl))
      (each [_ s (ipairs old-searchers)]
        (table.insert searchers-tbl s))
      ((or _G.unpack table.unpack) res))))

(fn test-install []
  (tset package.loaded :test.searcher nil)
  (t.is (with-preserve-searchers
          #(do (fennel.install {})
               (pcall require :test.searcher))))
  (t.is (with-preserve-searchers
          #(do (fennel.install {:path "test/?.fnl"})
               (pcall require :searcher))))
  nil)

(fn test-searcher []
  (t.= "./test/searcher.fnl" (fennel.search-module "test/searcher"))
  (t.= "./src/fennel.fnl" (fennel.search-module "src.fennel"))
  (t.= nil (fennel.search-module "test.bad.with.dots")))

{: test-searcher-error-contains-fnl-files
 : test-install
 : test-searcher}
