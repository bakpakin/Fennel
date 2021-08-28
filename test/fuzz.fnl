(local l (require :test.luaunit))
(local fennel (require :fennel))
(local compiler (require :fennel.compiler))
(local generate (require :test.generate))
(local friend (require :fennel.friend))
(local unpack (or table.unpack _G.unpack))

;; extend the generator function to produce ASTs
(table.insert generate.order 4 :sym)
(table.insert generate.order 1 :list)

(local keywords (icollect [k (pairs (doto (fennel.syntax)
                                      (tset :eval-compiler nil)))] k))

(fn generate.generators.sym []
  (fennel.sym (generate.generators.string)))

(fn generate.generators.list [gen depth]
  (let [f (fennel.sym (. keywords (math.random (length keywords))))
        contents (if (< 0.5 (math.random))
                     (generate.generators.sequence gen depth)
                     [])]
    (fennel.list f (unpack contents))))

(local marker {})

(fn fuzz [verbose?]
  (let [code (fennel.view (generate.generators.list generate.generate 1))
        (ok err) (xpcall #(fennel.compile-string code {:useMetadata true
                                                       :compiler-env :strict})
                         #(if (= $ marker)
                              marker
                              (.. (tostring $) "\n" (debug.traceback))))]
    (if verbose?
        (print code)
        (io.write "."))
    (when (not ok)
      ;; if we get an error, it must come from assert-compile; if we get
      ;; a non-assertion error then it must be a compiler bug!
      (l.assertEquals err marker (.. code "\n" (tostring err))))))

(fn test-fuzz []
  (let [seed (tonumber (or (os.getenv "FUZZ_SEED") (os.time)))
        verbose? (os.getenv "VERBOSE")
        {: assert-compile : parse-error} friend]
    (print (.. "Fuzz testing with FUZZ_SEED=" seed))
    (math.randomseed seed)
    (set friend.assert-compile #(error marker))
    (set friend.parse-error #(error marker))
    (for [_ 1 (tonumber (or (os.getenv "FUZZ_COUNT") 256))]
      (fuzz verbose?))
    (print)
    (set friend.assert-compile assert-compile)
    (set friend.parse-error parse-error)))

{: test-fuzz}
