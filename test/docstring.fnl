(local l (require :test.luaunit))
(local fennel (require :fennel))
(local specials (require :fennel.specials))

(local doc-env (setmetatable {:print #$ :fennel fennel}
                             {:__index _G}))

(local cases
       [["(doc doc)" "(doc x)\n  Print the docstring and arglist for a function, macro, or special form." "docstrings for special forms"]
        ["(doc doto)" "(doto val ...)\n  Evaluates val and splices it into the first argument of subsequent forms." "docstrings for built-in macros" ]
        ["(doc table.concat)"  "(table.concat #<unknown-arguments>)\n  #<undocumented>" "docstrings for built-in Lua functions" ]
        ["(fn ew [] \"so \\\"gross\\\" \\\\\\\"I\\\\\\\" can't even\" 1) (doc ew)"  "(ew)\n  so \"gross\" \\\"I\\\" can't even" "docstrings should be auto-escaped" ]
        ["(fn foo [a] :C 1) (doc foo)"  "(foo a)\n  C" "for named functions, (doc fnname) shows name, args invocation, docstring" ]
        ["(fn foo! [-kebab- {:x x}] 1) (doc foo!)"  "(foo! -kebab- {:x x})\n  #<undocumented>" "fn-name and args pretty-printing" ]
        ["(fn foo! [-kebab- [a b {: x} [x y]]] 1) (doc foo!)"  "(foo! -kebab- [a b {:x x} [x y]])\n  #<undocumented>" "fn-name and args deep pretty-printing" ]
        ["(fn foo! [-kebab- [a b {\"a b c\" a-b-c} [x y]]] 1) (doc foo!)"  "(foo! -kebab- [a b {\"a b c\" a-b-c} [x y]])\n  #<undocumented>" "fn-name and args deep pretty-printing" ]
        ["(fn foo! [-kebab- [a b {\"a \\\"b\\\" c\" a-b-c} [x y]]] 1) (doc foo!)"  "(foo! -kebab- [a b {\"a \\\"b\\\" c\" a-b-c} [x y]])\n  #<undocumented>" "fn-name and args deep pretty-printing" ]
        ["(fn foo! [-kebab- [a b {\"a \\\"b \\\\\\\"c\\\\\\\" d\\\" e\" a-b-c-d-e} [x y]]] 1) (doc foo!)"  "(foo! -kebab- [a b {\"a \\\"b \\\\\"c\\\\\" d\\\" e\" a-b-c-d-e} [x y]])\n  #<undocumented>" "fn-name and args deep pretty-printing" ]
        ["(fn ml [] \"a\nmultiline\ndocstring\" :result) (doc ml)"  "(ml)\n  a\n  multiline\n  docstring" "multiline docstrings work correctly" ]
        ["(let [f (fn [] \"f\" :f) g (fn [] f)] (doc (g)))"  "((g))\n  f" "doc on expression" ]
        ["(let [x-tbl []] (fn x-tbl.y! [d] \"why\" 123) (doc x-tbl.y!))"  "(x-tbl.y! d)\n  why" "docstrings for mangled multisyms" ]
        ["(local {: generate} (fennel.dofile \"test/generate.fnl\" {:useMetadata true})) (doc generate)"  "(generate depth ?choice)\n  Generate a random piece of data." "docstrings from required module." ]
        ["(macro abc [x y z] \"this is a macro.\" :123) (doc abc)"  "(abc x y z)\n  this is a macro." "docstrings for user-defined macros" ]
        ["(macro ten [] \"[ten]\" 10) (doc ten)" "(ten)\n  [ten]" "macro docstrings with brackets"]
        ["(λ foo [] :D 1) (doc foo)"  "(foo)\n  D" "(doc fnname) for named lambdas appear like named functions" ]])

(fn eval [code]
  (fennel.eval code {:useMetadata true :env doc-env}))

(fn test-docstrings []
  (each [_ [code expected msg] (ipairs cases)]
    (l.assertEquals (eval code) expected msg)))

(fn test-no-undocumented []
  (let [undocumented-ok? {:lua true "#" true :set-forcibly! true}
        {: _SPECIALS} (specials.make-compiler-env)]
    (each [name (pairs _SPECIALS)]
      (when (not (. undocumented-ok? name))
        (let [docstring (eval (: "(doc %s)" :format name))]
          (l.assertNil (docstring:find "undocumented")
                       (.. "Missing docstring for " name)))))))

{: test-docstrings
 : test-no-undocumented}
