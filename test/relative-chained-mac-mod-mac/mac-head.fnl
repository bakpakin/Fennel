;; relatively require a *module* for functionality in processing macro args
(local relrequire ((fn [ddd]
                     (fn [modname]
                       (let [prefix (or (string.match ddd "(.+%.)mac%-head") "")]
                         (require (.. prefix modname))))) ...))

(local {: bkwd} (relrequire :mod-mid))

(fn rsym [...]
  "generates a list of strings from a given list of symbols, in reverse"
  (let [syms [...]
        rsyms (icollect [v (bkwd syms)] (tostring v))]
    rsyms))

{: rsym}

