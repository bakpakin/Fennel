;; relatively require a macro from a module required by a macro
(import-macros {: dec} (do (.. (or (string.match ... "(.+%.)mod%-mid") "") :mac-tail)))

(fn bkwd [seq]
  (var i (+ (length seq) 1))
  (fn iter []
    (let [next-i (dec i)
          val (. seq next-i)]
      (when val
        (set i next-i)
        (values val i)))))

{: bkwd}
