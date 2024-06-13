;;; faith.fnl --- The Fennel Advanced Interactive Test Helper

;; https://git.sr.ht/~technomancy/faith

;; SPDX-License-Identifier: MIT
;; SPDX-FileCopyrightText: Scott Vokes, Phil Hagelberg, and contributors

;; To use Faith, create a test runner file which calls the `run` function with
;; a list of module names. The modules should export functions whose
;; names start with `test-` and which call the assertion functions in the
;; `faith` module.

;; Copyright © 2009-2013 Scott Vokes and contributors
;; Copyright © 2023-2024 Phil Hagelberg and contributors

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

(fn fn? [v] (= (type v) :function))

(fn fail->string [{: where : reason : msg} name]
  (string.format "FAIL: %s:\n%s: %s%s\n"
                 name where (or reason "")
                 (or (and msg (.. " - " (tostring msg))) "")))

(fn err->string [{: msg} name]
  (or msg (string.format "ERROR (in %s, couldn't get traceback)"
                         (or name "(unknown)"))))

(fn get-where [start]
  (let [traceback (fennel.traceback nil start)
        (_ _ where) (traceback:find "\n\t*([^:]+:[0-9]+):")]
    (or where "?")))

;;; assertions

;; while I'd prefer to remove all top-level state, this one is difficult
;; because it has to be set by every assertion, and the assertion functions
;; themselves do not have access to any stateful arguments given that they
;; are called directly from user code.
(var checked 0)
(var diff-cmd (or (os.getenv "FAITH_DIFF")
                  (if (os.getenv "NO_COLOR")
                      "diff -u %s %s"
                      "diff -u --color=always %s %s")))

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

(fn error* [pat f ?msg]
  (case (pcall f)
    (true ?val) (wrap false ?msg "Expected an error, got %s" (fennel.view ?val))
    (_ err) (let [err-string (if (= (type err) :string) err (fennel.view err))]
              (wrap (err-string:match pat) ?msg
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

(fn diff-report [expv gotv]
  (let [exp-file (os.tmpname "faithdiff1")
        got-file (os.tmpname "faithdiff2")]
    (with-open [f (io.open exp-file :w)]
      (f:write expv))
    (with-open [f (io.open got-file :w)]
      (f:write gotv))
    (let [diff (doto (io.popen (diff-cmd:format exp-file got-file))
                 (: :read) (: :read) (: :read)) ; omit header lines
          out (diff:read :*all)]
      (os.remove exp-file)
      (os.remove got-file)
      (let [(closed _ code) (diff:close)]
        (if (or closed (= 1 code))
            (.. "\n" out)
            (string.format "Expected:\n%s\nGot:\n%s" expv gotv))))))

(fn =* [exp got ?msg]
  (let [expv (fennel.view exp)
        gotv (fennel.view got)
        report (if (and (not= expv gotv) (or (expv:find "\n") (gotv:find "\n")))
                   (diff-report expv gotv)
                   (string.format "Expected %s, got %s" expv gotv))]
    (wrap (equal? exp got) ?msg report)))

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
  (wrap (rawequal exp got) ?msg
        "Expected %s, got %s" (fennel.view exp) (fennel.view got)))

(fn match* [pat s ?msg]
  (wrap (: (tostring s) :match pat) ?msg
        "Expected string to match pattern %s, was\n%s" pat s))

(fn not-match [pat s ?msg]
  (wrap (or (not= (type s) :string) (not (s:match pat))) ?msg
        "Expected string not to match pattern %s, was\n %s" pat s))

;;; running

(fn dot [char total-count]
  (io.write char)
  (when (= 0 (math.fmod total-count 76))
    (io.write "\n"))
  (io.stdout:flush))

(fn print-totals [report]
  (let [{: started-at : ended-at : results} report
        duration (fn [start end]
                   (let [decimal-places 2]
                     (: (.. "%." (tonumber decimal-places) "f")
                        :format
                        (math.max (- end start)
                                  (^ 10 (- decimal-places))))))
        counts (accumulate [counts {:pass 0 :fail 0 :err 0 :skip 0}
                            _ {:type type*} (ipairs results)]
                 (doto counts (tset type* (+ (. counts type*) 1))))]
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
              counts.pass
              counts.fail
              counts.err
              counts.skip
              (duration started-at.cpu ended-at.cpu)))))

(fn begin-module [report tests]
  (print (string.format "\nStarting module %s with %d test(s)"
                        report.module-name
                        (accumulate [count 0 _ (pairs tests)] (+ count 1)))))

(fn done [report]
  (print "\n")
  (each [_ result (ipairs report.results)]
    (when result.tostring (print (result:tostring result.name))))
  (print-totals report))

(local default-hooks {:begin false
                      : done
                      : begin-module
                      :end-module false
                      :begin-test false
                      :end-test (fn [_name result total-count]
                                  (dot result.char total-count))})

(fn test-key? [k]
  (and (= (type k) :string) (k:match :^test.*)))

(local ok-types {:fail true :pass true :skip true})

(fn err-handler [name]
  (fn [e]
    (if (and (= (type e) :table) (. ok-types e.type))
        e
        (error-result (-> (string.format "\nERROR: %s:\n%s\n" name e)
                          (fennel.traceback 4))))))

(fn run-test [name ?setup test ?teardown report hooks context]
  (when (fn? hooks.begin-test) (hooks.begin-test name))
  (let [result (case-try (if ?setup (xpcall ?setup (err-handler name)) true)
                 true (xpcall #(test (unpack context)) (err-handler name))
                 true (pass)
                 (catch (_ err) err))]
    (when ?teardown (pcall ?teardown (unpack context)))
    (table.insert report.results (doto result (tset :name name)))
    (when (fn? hooks.end-test)
      (hooks.end-test name result (length report.results)))))

(fn run-setup-all [setup-all report module-name]
  (if (fn? setup-all)
      (case [(pcall setup-all)]
        [true & context] context
        [false err] (let [msg (: "ERROR in test module %s setup-all: %s"
                                 :format module-name err)]
                      (table.insert report.results
                                    (doto (error-result msg)
                                      (tset :name module-name)))
                      (values nil err)))
      []))

(fn run-module [hooks report module-name test-module]
  (assert (= :table (type test-module))
          (.. "test module must be table: " module-name))
  (let [module-report {: module-name :started-at (now) :results []}]
    (case (run-setup-all test-module.setup-all report module-name)
      context (do
                (when hooks.begin-module
                  (hooks.begin-module module-report test-module))
                (each [_ {: name : test}
                       (ipairs (doto (icollect [name test (pairs test-module)]
                                       (if (test-key? name)
                                           {:line (. (debug.getinfo test :S)
                                                     :linedefined)
                                            : name : test}))
                                 (table.sort #(< $1.line $2.line))))]
                  (run-test name
                            test-module.setup
                            test
                            test-module.teardown
                            module-report
                            hooks
                            context))
                (case test-module.teardown-all
                  teardown (pcall teardown (unpack context)))
                (when hooks.end-module (hooks.end-module module-report))
                (icollect [_ value
                           (ipairs module-report.results)
                           &into report.results]
                  value)))))

(fn exit [hooks]
  (if hooks.exit (hooks.exit 1)
      _G.___replLocals___ :failed
      (and os os.exit) (os.exit 1)))

(fn run [module-names ?opts]
  (set (checked diff-cmd) (values 0 (or (and ?opts ?opts.diff-cmd) diff-cmd)))
  (io.stdout:setvbuf :line)
  ;; don't count load time against the test runtime
  (each [_ m (ipairs module-names)] (require m))
  (let [hooks (setmetatable (or (?. ?opts :hooks) {}) {:__index default-hooks})
        report {:module-name :main :started-at (now) :results []}]
    (when hooks.begin
      (hooks.begin report module-names))
    (each [_ module-name (ipairs module-names)]
      (case (pcall require module-name)
        (true test-module) (run-module hooks report module-name test-module)
        (false err) (let [error (: "ERROR: Cannot load %q:\n%s"
                                   :format module-name err)]
                      (table.insert report.results
                                    (doto (error-result error)
                                      (tset :name module-name))))))
    (set report.ended-at (now))
    (when hooks.done (hooks.done report))
    (when (accumulate [red false
                       _ {:type type*} (ipairs report.results)
                       &until red]
            (or (= type* :fail)
                (= type* :err)))
      (exit hooks))))

(when (= ... "--tests")
  (run (doto [...] (table.remove 1)))
  (os.exit 0))

{: run : skip :version "0.2.0"
 : is :error error* := =* :not= not=* :< <* :<= <=* : almost=
 : identical :match match* : not-match}
