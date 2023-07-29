;;; faith.fnl --- The Fennel Advanced Interactive Test Helper

;; https://git.sr.ht/~technomancy/faith

;; SPDX-License-Identifier: MIT
;; SPDX-FileCopyrightText: Scott Vokes, Phil Hagelberg, and contributors

;; To use Faith, create a test runner file which calls the `run` function with
;; a list of module names. The modules should export functions whose
;; names start with `test-` and which call the assertion functions in the
;; `faith` module.

;; Copyright © 2009-2013 Scott Vokes and contributors
;; Copyright © 2023 Phil Hagelberg and contributors

;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:

;; The above copyright notice and this permission notice shall be included in
;; all copies or substantial portions of the Software.

;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

(local fennel (require :fennel))

;;; helper functions

(local unpack (or table.unpack _G.unpack))

(fn now []
  {:real (or (and (pcall require :socket)
                  (package.loaded.socket.gettime))
             (and (pcall require :posix)
                  (package.loaded.posix.gettimeofday)
                  (let [t (package.loaded.posix.gettimeofday)]
                    (+ t.sec (/ t.usec 1000000))))
             nil)
   :approx (os.time)
   :cpu (os.clock)})

(fn result-table [name]
  {:started-at (now) :err [] :fail [] : name :pass [] :skip [] :ran 0 :tests []})

(fn combine-results [to from]
  (each [_ s (ipairs [:pass :fail :skip :err])]
    (each [name val (pairs (. from s))]
      (tset (. to s) name val))))

(fn fn? [v] (= (type v) :function))

(fn count [t] (accumulate [c 0 _ (pairs t)] (+ c 1)))

(fn fail->string [{: where : reason : msg} name]
  (string.format "FAIL: %s: %s\n  %s%s\n"
                 where name (or reason "")
                 (or (and msg (.. " - " (tostring msg))) "")))

(fn err->string [{: msg} name]
  (or msg (string.format "ERROR (in %s, couldn't get traceback)"
                         (or name "(unknown)"))))

(fn get-where [start]
  (let [traceback (fennel.traceback nil start)
        (_ _ where) (traceback:find "\n *([^:]+:[0-9]+):")]
    (or where "?")))

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
                 :reason (string.format ,...) :msg ,msg :where (get-where 4)}))))

(fn pass [] {:char "." :type :pass})

(fn error-result [msg] {:char "E" :type :err :tostring err->string :msg msg})

(fn skip []
  (error {:char :s :type :skip}))

(fn is [got ?msg]
  (wrap got ?msg "Expected truthy value"))

(fn error* [f ?msg]
  (case (pcall f)
    (true val) (wrap false ?msg "Expected an error, got %s"
                     (fennel.view val))))

(fn error-match [pat f ?msg]
  (case (pcall f)
    (true val) (wrap false ?msg
                     "Expected an error, got %s" (fennel.view val))
    (_ err) (let [err-string (if (= (type err) :string) err (fennel.view err))]
              (wrap (: err-string :match pat) ?msg
                    "Expected error to match pattern %s, was %s"
                    pat err-string))))

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
    (io.write "\n"))
  (io.stdout:flush))

(fn print-totals [{: pass : fail : skip : err : started-at : ended-at}]
  (let [duration (fn [start end]
                   (let [decimal-places 2]
                     (: (.. "%." (tonumber decimal-places) "f")
                        :format
                        (math.max (- end start)
                                  (math.pow 10 (- decimal-places))))))]
    (print (: (.. "Testing finished %s with %d assertion(s)\n"
                  "%d passed, %d failed, %d error(s), %d skipped\n"
                  "%.2f second(s) of CPU time used")
              :format
              (if started-at.real
                  (: "in %s second(s)" :format
                     (duration started-at.real ended-at.real))
                  (: "in approximately %s second(s)" :format
                     (- ended-at.approx started-at.approx)))
              checked
              (count pass) (count fail) (count err) (count skip)
              (duration started-at.cpu ended-at.cpu)))))

(fn begin-module [s-env tests]
  (print (string.format "\nStarting module %s with %d test(s)"
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
        (error-result (-> (string.format "\nERROR: %s:\n%s\n" name e)
                          (fennel.traceback 4))))))

(fn run-test [name ?setup test ?teardown module-result hooks context]
  (when (fn? hooks.begin-test) (hooks.begin-test name))
  (let [started-at (now)
        result (case-try (if ?setup (xpcall ?setup (err-handler name)) true)
                 true (xpcall #(test (unpack context)) (err-handler name))
                 true (pass)
                 (catch (_ err) err))]
    (when ?teardown (pcall ?teardown (unpack context)))
    (tset module-result result.type name result)
    (set module-result.ran (+ module-result.ran 1))
    (when (fn? hooks.end-test) (hooks.end-test name result module-result.ran))))

(fn run-setup-all [setup-all results module-name]
  (if (fn? setup-all)
      (case [(pcall setup-all)]
        [true & context] context
        [false err] (let [msg (: "ERROR in test module %s setup-all: %s"
                                 :format module-name err)]
                      (tset results.err module-name (error-result msg))
                      (values nil err)))
      []))

(fn run-module [hooks results module-name test-module]
  (assert (= :table (type test-module)) (.. "test module must be table: "
                                            module-name))
  (let [result (result-table module-name)]
    (case (run-setup-all test-module.setup-all results module-name)
      context (do
                (when hooks.begin-module (hooks.begin-module result test-module))
                (each [name test (pairs test-module)]
                  (when (test-key? name)
                    (table.insert result.tests test)
                    (run-test name
                              test-module.setup
                              test
                              test-module.teardown
                              result
                              hooks
                              context)))
                (case test-module.teardown-all
                  teardown (pcall teardown (unpack context)))
                (when hooks.end-module (hooks.end-module result))
                (combine-results results result)))))

(fn exit [hooks]
  (if hooks.exit (hooks.exit 1)
      _G.___replLocals___ :failed
      (and os os.exit) (os.exit 1)))

(fn run [module-names ?hooks]
  (set checked 0)
  (io.stdout:setvbuf :line)
  ;; don't count load time against the test runtime
  (each [_ m (ipairs module-names)]
    (when (not (pcall require m))
      (tset package.loaded m nil)))
  (let [hooks (setmetatable (or ?hooks {}) {:__index default-hooks})
        results (result-table :main)]
    (when hooks.begin
      (hooks.begin results module-names))
    (each [_ module-name (ipairs module-names)]
      (case (pcall require module-name)
        (true test-mod) (run-module hooks results module-name test-mod)
        (false err) (tset results.err module-name
                          (error-result (: "ERROR: Cannot load %q:\n%s"
                                           :format module-name err)))))
    (set results.ended-at (now))
    (when hooks.done (hooks.done results))
    (when (or (next results.err) (next results.fail))
      (exit hooks))))

{: run : skip :version "0.1.2"
 : is :error error* : error-match := =* :not= not=* :< <* :<= <=* : almost=
 : identical :match match* : not-match}
