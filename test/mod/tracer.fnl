(local fennel (require :fennel))

(fn inner []
  (let [t (fennel.traceback)]
    nil ; don't put traceback in tail call
    t))

(fn outer [_arg]
  (let [t (inner)]
    nil
    t))

(fn info []
  (let [data (fennel.getinfo 1 :LS)]
    ;; don't TCO me bro
    data))

(fn nest []
  (if (= 2 (+ 1 1))
      (if :hey
          (table.concat []))))

(fn coro []
  (coroutine.yield)
  (print :haha))

{: outer : info : nest : coro}
