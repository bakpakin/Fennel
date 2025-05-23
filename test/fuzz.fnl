(local t (require :test.faith))
(local fennel (require :fennel))
(local generate (require :test.generate))
(local friend (require :fennel.friend))
(local unpack (or table.unpack _G.unpack))

;; extend the generator function to produce ASTs
(table.insert generate.order 4 :sym)
(table.insert generate.order 1 :list)

(local keywords (icollect [k (pairs (doto (fennel.syntax)
                                      (tset :eval-compiler nil)
                                      (tset :lua nil)
                                      (tset :macros nil)))] k))

(fn generate.generators.sym []
  (case (: (generate.generators.string) :gsub "."
           (fn [c] (if (not (fennel.sym-char? c)) "")))
    "" (generate.generators.sym)
    name (fennel.sym name)))

(fn generate.generators.list [gen depth]
  (let [f (fennel.sym (. keywords (math.random (length keywords))))
        contents (if (< 0.5 (math.random))
                     (generate.generators.sequence gen depth)
                     [])]
    (fennel.list f (unpack contents))))

(local marker {})

(fn fuzz [verbose? seed]
  (let [code (fennel.view (generate.generators.list generate.generate 1))
        (ok err) (xpcall #(fennel.compile-string code {:useMetadata true
                                                       :compiler-env :strict})
                         #(if (= $ marker)
                              marker
                              (.. (tostring $) "\n" (debug.traceback))))]
    (when verbose?
      (print code))
    (if (not ok)
      ;; if we get an error, it must come from assert-compile; if we get
      ;; a non-assertion error then it must be a compiler bug!
      (t.= err marker (.. code "\n" (tostring err) "\nSeed: " seed))
      (let [(ok2 err2) ((or _G.loadstring load) err)]
        ;; if we get an err2, it must mean that fennel's output isn't valid Lua
        ;; If fennel emits code, it should be valid Lua!
        (when (not ok2)
          (error (.. (tostring err2) "\n" code "\n" (tostring err) "\nSeed: " seed)))))))

(fn test-fuzz []
  (let [verbose? (os.getenv "VERBOSE")
        {: assert-compile : parse-error} friend
        seed (os.time)]
    (math.randomseed seed)
    (set friend.assert-compile #(error marker))
    (set friend.parse-error #(error marker))
    (for [_ 1 (tonumber (or (os.getenv "FUZZ_COUNT") 256))]
      (fuzz verbose? seed))
    (set friend.assert-compile assert-compile)
    (set friend.parse-error parse-error)))

{: test-fuzz}
