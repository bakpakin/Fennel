(local t (require :test.faith))
(local fennel (require :fennel))

(macro == [form expected]
  `(let [(ok# val#) (pcall fennel.eval ,(view form)
                           {:useBitLib (not= nil _G.bit)})]
     (t.is ok# val#)
     (t.= ,expected val#)))

(fn test-shifts []
  (== (lshift 33 2) 132)
  (== (lshift 1) 2)
  (== (rshift 33 2) 8)
  (let [(ok? msg) (pcall fennel.compileString "(lshift)")]
    (t.is (not ok?))
    (t.match "Expected more than 0 arguments" msg)))

(fn test-ops []
  ;; multiple args
  (== (band 0x16 0xd) 0x4)
  (== (band 0xff 0x91) 0x91)
  (== (bor 0x1 0x2 0x4 0x8) 0xf)
  (== (bxor 0x2 0xf0) 0xf2)
  ;; one arg
  (== (bxor 1) 1)
  (== (bor 0x33) 0x33)
  (== (band 0x93) 0x93)
  (== (bnot 26) -27)
  ;; no args
  (== (band) -1)
  (== (bor) 0)
  (== (bxor) 0))

;; skip the test on PUC 5.1 and 5.2
(if (or (rawget _G :jit) (not (_VERSION:find "5%.[12]")))
    {: test-shifts
     : test-ops}
    {})
