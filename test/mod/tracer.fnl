(local fennel (require :fennel))

(fn inner []
  (let [t (fennel.traceback)]
    nil ; don't put traceback in tail call
    t))

(fn outer []
  (let [t (inner)]
    nil
    t))
