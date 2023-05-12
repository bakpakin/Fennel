(local fennel (require :fennel))

;;; helper functions

(local unpack (or table.unpack _G.unpack))

(local now (or (and (pcall require :socket) package.loaded.socket.gettime)
               (and (pcall require :posix) package.loaded.posix.gettimeofday
                    (fn []
                      (let [t (package.loaded.posix.gettimeofday)]
                        (+ t.sec (/ t.usec 1000000))))) os.time))

(fn result-table [name]
  {:started-at (now) :err [] :fail [] : name :pass [] :skip []
   :ran 0 :tests [] :failed-modules []})

(fn combine-results [to from]
  (each [_ s (ipairs [:pass :fail :skip :err])]
    (each [name val (pairs (. from s))]
      (tset (. to s) (.. from.name "." name) val))))

(fn fn? [v] (= (type v) :function))

(fn count [t] (accumulate [c 0 _ (pairs t)] (+ c 1)))

(fn fail->string [{: name : line : reason : msg} name]
  (string.format "FAIL: %s:%s:\n  %s%s\n"
                 (or name "(unknown)") line (or reason "")
                 (or (and msg (.. " - " (tostring msg))) "")))

(fn err->string [{: msg} name]
  (or msg (string.format "ERROR (in %s, couldn't get traceback)"
                         (or name "(unknown)"))))

(fn get-line [start]
  (let [traceback (fennel.traceback nil start)
        (_ _ line) (traceback:find "\n[^0-9]+:([0-9]+):")]
    (or line "?")))

;;; assertions

;; while I'd prefer to remove all top-level state, this one is difficult
;; because it has to be set by every assertion, and the assertion functions
;; themselves do not have access to any stateful arguments given that they
;; are called directly from user code.
(var checked nil)

(macro wrap [flag msg ...]
  `(do (set ,(sym :checked) (+ ,(sym :checked) 1))
       (when (not ,flag)
         (error {:char "F" :type :fail :tostring fail->string
                 :reason (string.format ,...) :msg ,msg :line (get-line 4)}))))

(fn pass [] {:char "." :type :pass})

(fn error-result [msg] {:char "E" :type :err :tostring err->string :msg msg})

(fn skip []
  (error {:char :s :type :skip}))

(fn is [got ?msg]
  (wrap got ?msg "Expected truthy value"))

(fn error* [f ?msg]
  (match (pcall f)
    (true val) (wrap false ?msg "Expected an error, got %s"
                     (fennel.view val))))

(fn extra-fields? [t keys]
  (or (accumulate [extra? false k (pairs t) &until extra?]
        (if (= nil (. keys k))
            true
            (tset keys k nil)))
      (next keys)))

(fn table= [x y equal?]
  (let [keys {}]
    (and (accumulate [same? true k v (pairs x) &until (not same?)]
           (do (tset keys k true)
               (equal? v (. y k))))
         (not (extra-fields? y keys)))))

(fn equal? [x y]
  (or (= x y)
      (and (= (type x) :table (type y)) (table= x y equal?))))

(fn =* [exp got ?msg]
  (wrap (equal? exp got) ?msg "Expected %s, got %s"
        (fennel.view exp) (fennel.view got)))

(fn not=* [exp got ?msg]
  (wrap (not (equal? exp got)) ?msg "Expected something other than %s"
        (fennel.view exp)))

(fn <* [...]
  (let [args [...]
        msg (if (= :string (type (. args (length args)))) (table.remove args))
        correct? (faccumulate [ok? true i 2 (length args) &until (not ok?)]
                   (< (. args (- i 1)) (. args i)))]
    (wrap correct? msg
          "Expected arguments in strictly increasing order, got %s"
          (fennel.view args))))

(fn <=* [...]
  (let [args [...]
        msg (if (= :string (type (. args (length args)))) (table.remove args))
        correct? (faccumulate [ok? true i 2 (length args) &until (not ok?)]
                   (<= (. args (- i 1)) (. args i)))]
    (wrap correct? msg
          "Expected arguments in increasing/equal order, got %s"
          (fennel.view args))))

(fn almost= [exp got tolerance ?msg]
  (wrap (<= (math.abs (- exp got)) tolerance) ?msg
        "Expected %s +/- %s, got %s" exp tolerance got))

(fn identical [exp got ?msg]
  (wrap (= exp got) ?msg
        "Expected %s, got %s" (fennel.view exp) (fennel.view got)))

(fn match* [pat s ?msg]
  (wrap (: (tostring s) :match pat) ?msg
        "Expected string to match pattern %s, was\n%s" pat s))

(fn not-match [pat s ?msg]
  (wrap (or (not= (type s) :string) (not (s:match pat))) ?msg
        "Expected string not to match pattern %s, was\n %s" pat s))

;;; running

(fn dot [c ran]
  (io.write c)
  (when (= 0 (math.fmod ran 76))
    (io.write "\n  "))
  (io.stdout:flush))

(fn print-totals [{: pass : fail : skip : err : started-at : ended-at}]
  (let [elapsed (- ended-at started-at)
        elapsed-string (if (< elapsed 1)
                           (string.format " in %.2f %s" (* elapsed 1000) :ms)
                           (string.format " in %.2f %s" elapsed :s))
        buf ["\n---- Testing finished%s, "
             "with %d assertion(s) ----\n"
             "  %d passed, %d failed, "
             "%d error(s), %d skipped.\n"]]
    (print (: (table.concat buf) :format elapsed-string checked
              (count pass) (count fail) (count err) (count skip)))))

(fn begin-module [s-env tests]
  (io.write (string.format "\n-- Starting module %q, %d test(s)\n  "
                           s-env.name (count tests))))
(fn done [results]
  (print "\n")
  (each [_ ts (ipairs [results.fail results.err results.skip])]
    (each [name result (pairs ts)]
      (when result.tostring (print (result:tostring name)))))
  (print-totals results))

(local default-hooks {:begin false
                      : done
                      : begin-module
                      :end-module false
                      :begin-test false
                      :end-test (fn [_name result ran] (dot result.char ran))})

(fn test-key? [k]
  (and (= (type k) :string) (k:match :^test.*)))

(local ok-types {:fail true :pass true :skip true})

(fn err-handler [name]
  (fn [e]
    (if (and (= (type e) :table) (. ok-types e.type))
        e
        (error-result (-> (string.format "\nERROR in %s():\n  %s\n" name e)
                          (fennel.traceback 4))))))

(fn run-test [name test module-result hooks context]
  (when (fn? hooks.begin-test) (hooks.begin-test name))
  (let [started-at (now)
        result (case (xpcall #(test (unpack context)) (err-handler name))
                 true (pass)
                 (_ err) err)]
    (set result.elapsed (- (now) started-at))
    (tset module-result result.type name result)
    (set module-result.ran (+ module-result.ran 1))
    (when (fn? hooks.end-test) (hooks.end-test name result module-result.ran))))

(fn run-setup [setup results module-name]
  (if (fn? setup)
      (case [(pcall setup)]
        [true & context] context
        [false err] (let [msg (string.format "ERROR in test module %s setup: %s"
                                             module-name err)]
                      (table.insert results.failed-modules module-name)
                      (tset results.err module-name (error-result msg))
                      (values nil err)))
      []))

(fn run-module [hooks results module-name test-module]
  (assert (= :table (type test-module)) (.. "test module must be table: "
                                            module-name))
  (let [result (result-table module-name)]
    (case (run-setup test-module.setup results module-name)
      context (do
                (when hooks.begin-module (hooks.begin-module result test-module))
                (each [name test (pairs test-module)]
                  (when (test-key? name)
                    (table.insert result.tests test)
                    (run-test name test result hooks context)))
                (when test-module.teardown
                  (pcall test-module.teardown (unpack context)))
                (when hooks.end-module (hooks.end-module result))
                (combine-results results result)))))

(fn run [module-names ?hooks]
  (set checked 0)
  (io.stdout:setvbuf :line)
  ;; don't count load time against the test runtime
  (each [_ m (ipairs module-names)] (pcall require m))
  (let [hooks (setmetatable (or ?hooks {}) {:__index default-hooks})
        exit (or hooks.exit os.exit)
        results (result-table :main)]
    (when hooks.begin
      (hooks.begin results module-names))
    (each [_ module-name (ipairs module-names)]
      (match (pcall require module-name)
        (true test-mod) (run-module hooks results module-name test-mod)
        (false err) (tset results.err module-name
                          (error-result (: "ERROR loading test module %q:\n  %s"
                                           :format module-name err)))))
    (set results.ended-at (now))
    (when hooks.done (hooks.done results))
    (when (or (next results.err) (next results.fail))
      (exit 1))))

{: run : skip :version "0.1.1"
 : is :error error* := =* :not= not=* :< <* :<= <=* : almost=
 : identical :match match* : not-match}
