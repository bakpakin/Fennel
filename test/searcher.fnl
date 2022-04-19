(local l (require :luaunit))
(local fennel (require :fennel))

(fn test-searcher-error-contains-fnl-files []
  (let [(ok error) (pcall require :notreal)]
    (l.assertEquals ok false)
    (l.assertEquals (string.match error :notreal.fnl) :notreal.fnl)))

{: test-searcher-error-contains-fnl-files}
