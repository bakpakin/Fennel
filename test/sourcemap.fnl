(local t (require :test.faith))
(local fennel (require :fennel))

(fn test-traceback []
  (let [{: outer} (require :test.mod.tracer)
        traceback (outer)]
    (t.match "tracer.fnl:4:" traceback)
    (t.match "tracer.fnl:9:" traceback)))

;; what a mess!
(fn normalize [tbl nups-51]
  (if (and (= "Lua 5.1" _VERSION) (not _G.jit))
      ;; these don't exist in 5.1
      (set (tbl.nups tbl.nparams tbl.isvararg) nups-51)
      _G.jit nil
      (set tbl.istailcall false))
  (when (= "Lua 5.4" _VERSION)
    (set (tbl.ntransfer tbl.ftransfer) (values 0 0)))
  tbl)

(fn test-getinfo []
  (let [{: outer : info : nest : coro} (fennel.dofile "test/mod/tracer.fnl")]
    (t.= (normalize {:currentline -1
                     :func outer
                     :isvararg false
                     :lastlinedefined 11
                     :linedefined 8
                     :namewhat ""
                     :nparams 1
                     :nups 1
                     :short_src "test/mod/tracer.fnl"
                     :source "@test/mod/tracer.fnl"
                     :what "Fennel"} 1)
         (fennel.getinfo outer))
    (t.= {:activelines {14 true 16 true}
          :lastlinedefined 16
          :linedefined 13
          :short_src "test/mod/tracer.fnl"
          :source "@test/mod/tracer.fnl"
          :what "Fennel"}
         (info))
    (t.= {:linedefined 18
          :lastlinedefined 21
          :short_src "test/mod/tracer.fnl"
          :source "@test/mod/tracer.fnl"
          :what "Fennel"}
         (fennel.getinfo nest "S"))
    (let [c (coroutine.create coro)]
      (coroutine.resume c)
      (t.= (normalize {:currentline 24
                       :func coro
                       :isvararg false
                       :lastlinedefined 25
                       :linedefined 23
                       :namewhat ""
                       :nparams 0
                       :nups (if _G.jit 0 1) ; ???
                       :short_src "test/mod/tracer.fnl"
                       :source "@test/mod/tracer.fnl"
                       :what "Fennel"} 0)
           (fennel.getinfo c 1)))))

{: test-getinfo
 : test-traceback}
