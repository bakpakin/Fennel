# Learning Fennel from Clojure

Fennel takes a lot of inspiration from Clojure. If you already know
Clojure, then you'll have a good head start on Fennel. However, there
are still a lot of differences! This document will guide you thru
those differences and get you up to speed from the perspective of
someone who already knows Clojure.

Fennel and Lua are minimalist languages, and Clojure is not. So it may
take some getting used to when you make assumptions about what should
be included in a language and find that it's not. There's almost
always still a good way to do what you want; you just need to get used
to looking somewhere different. With that said, Fennel is easier to
learn since the conceptual surface area is much smaller.

## Runtime

Clojure and Fennel are both languages which have very close
integration with their host runtime. In the case of Clojure it's Java,
and in the case of Fennel it's Lua. However, Fennel's integration goes
beyond that of Clojure. In Clojure, every function implements the
interfaces needed to be callable from Java, but Clojure functions are
distinct from Java methods. Clojure namespaces are related to Java
packages, but namespaces still exist as a distinct concept from
packages. In Fennel you don't have such distinctions. Every Fennel
function is indistinguishable from a Lua function, and every Fennel
module is indistinguishable from a Lua module.

Clojure runs on the JVM, but it also has its own standard library: the
`clojure.core` namespace as well as supplemental ones like
`clojure.set` or `clojure.java.io` provide more functions. In Fennel,
there are no functions whatsoever provided by the language; it only
provides macros and special forms. Since the Lua standard library is
quite minimal, it's common to pull in 3rd-party things like [Lume][1],
[LuaFun][2], or [Penlight][8] for things you might expect to be
built-in to the language, like `reduce` or `keys`.

In Clojure it's typical to bring in libraries using a tool like
[Leiningen][3]. In Fennel you can use [LuaRocks][4] for dependencies,
but it's often overkill. Usually it's better to just check your
dependencies into your source repository. Deep dependency trees are
very rare in Fennel and Lua. Even tho Lua's standard library is very
small, adding a single file for a 3rd-party library into your repo
is very cheap.

Deploying Clojure usually means creating an uberjar that you launch
using an existing JVM installation, because the JVM is a pretty large
piece of software. Fennel deployments are much more varied; you can
easily create self-contained standalone executables that are under a
megabyte, or you can create scripts which rely on an existing Lua
install, or code which gets embedded inside a larger application.

## Functions and locals

Clojure has two types of scoping: lexical (for locals) and dynamic
(for vars). Fennel only has lexical scope. (Globals exist, but they're
mostly used for debugging and repl purposes; you don't use them in
normal code.) This means that the "unit of reloading" is not the
`clojure.lang.Var`, but the module. Fennel's repl includes a `,reload
module-name` command for this. Inside functions, `let` is used to
introduce new locals just like in Clojure. But at the top-level,
`local` is used, which declares a local which is valid for the entire
remaining chunk instead of just for the body of the `let`.

Like Clojure, Fennel uses the `fn` form to create functions. However,
giving it a name will also declare it as a local rather than having
the name be purely internal. Functions declared with `fn` have no
arity checking; you can call them with any number of arguments. To
have arity checking, declare with `lambda` instead, and it will throw
an exception if you provide too few arguments.

Fennel supports destructuring similarly to Clojure. The main
difference is that rather than using `:keys` Fennel has a notation
where a bare `:` is followed by a symbol naming the key.

```clj
;; clojure
(defn my-function [{:keys [msg abc def]}]
  (println msg)
  (+ abc def))

(my-function {:msg "have a cola and smile" :abc 99 :def 523})
```

```fennel
;; fennel
(fn my-function [{: msg : abc : def}]
  (print msg)
  (+ abc def))

(my-function {:msg "have a cola and smile" :abc 99 :def 523})
```


Like Clojure, normal locals cannot be given new values. However,
Fennel has a special `var` form that will allow you to declare a
special kind of local which can be given a new value with `set`.

Fennel also uses `#(foo)` notation as shorthand for anonymous
functions. There are two main differences; the first is that it uses `$1`,
`$2`, etc instead of `%1`, `%2` for arguments. Secondly while Clojure
requires parens in this shorthand, Fennel does not. `#5` in Fennel
is the equivalent of Clojure's `(constantly 5)`.

```clj
;; clojure
(def handler #(my-other-function %1 %3))
(def handler2 (constantly "abc"))
```

```fennel
;; fennel
(local handler #(my-other-function $1 $3))
(local handler2 #"abc")
```

Fennel does not have `apply`; instead you unpack arguments into
function call forms:

```clj
;; clojure
(apply add [1 2 3])
```

```fennel
;; fennel
(add (table.unpack [1 2 3])) ; unpack instead of table.unpack in older Lua
```

In Clojure, you have access to scoping information at compile
time using the undocumented `&env` map. In Fennel and Lua,
[environments are first-class at runtime][10].

## Tables

Clojure ships with a rich selection of data structures for all kinds
of situations. Lua (and thus Fennel) has exactly one data structure:
the table. Under the hood, tables with sequential integer keys are of
course implemented using arrays for performance reasons, but the
table itself does not "know" whether it's a sequence table or a
map-like table. It's up to you when you iterate thru the table to
decide; you iterate on sequence tables using `ipairs` and map-like
tables using `pairs`. Note that you can use `pairs` on sequences just
fine; you just won't get the results in order.

The other big difference is that tables are mutable. It's possible to
use metatables to implement immutable data structures on the Lua
runtime, but there's a significant performance overhead beyond just
the normal immutability penalty. Using the [LuaFun][2] library can get
you immutable operations on mutable tables without as much overhead.
However, note that generational garbage collection is still a very
recent development on the Lua runtime, so purely-functional approaches
that generate a lot of garbage may not be a good choice for libraries
which need to run on a wide range of versions.

Like Clojure, any value can serve as a key. However, since tables are
mutable data, two tables with identical values will not be `=` to each
other as [per Baker][5] and thus will act as distinct keys. Clojure's
`:keyword` notation is used in Fennel as a syntax for certain kinds of
strings; there is no distinct type for keywords.

Note that `nil` in Fennel is rather different from Clojure; in Clojure
it has many different meanings, ("nil punning") but in Fennel it
always represents the absence of a value. As such, tables **cannot**
contain `nil`. Attempting to put `nil` in a table is equivalent to
removing the value from the table, and you never have to worry about
the difference between "the table does not contain this key" vs "the
table contains a nil value at this key".

Tables cannot be called like functions, (unless you set up a special
metatable) nor can `:keyword` style strings. If a string key is
statically known, you can use `tbl.key` notation; if it's not, you use
the `.` form in cases where you can't destructure: `(. tbl key)`.

```clj
;; clojure
(dissoc my-map :abc)
(when-not (contains? my-other-map some-key)
  (println "no abc"))
```

```fennel
;; fennel
(set my-map.abc nil)
(when (= nil (. my-other-map some-key))
  (print "no abc"))
```

## Iterators

In Clojure, we have this idea that "everything is a seq". Lua and
Fennel, not being explicitly functional, have instead "everything is
an iterator". The book [Programming in Lua][7] has a detailed
explanation of iterators. The `each` special form consumes iterators
and steps thru them similarly to how `doseq` does.

```clj
;; clojure
(doseq [[k v] {:key "value" :other-key "SHINY"}]
  (println k "is" v))
```

```fennel
;; fennel
(each [k v (pairs {:key "value" :other-key "SHINY"})]
  (print k "is" v))
```

When iterating thru maps, Clojure has you pull apart the key/value
pair thru destructuring, but in Fennel the iterators provide you with
them as separate values.

Since Fennel has no functions, it relies on macros to do things like
`map` and `filter`. Similarly to Clojure's `for`, Fennel has a pair of
macros that operate on iterators and produce tables. `icollect` walks
thru an iterator and allows the body to return a value that's put in a
sequential table to return. The `collect` macro is similar in that it
returns a table, except the body should return two values, and the
returned table is key/value rather than sequential. The body of either
macro allows you to return `nil` to filter out that entry from the
result table.

```clj
;; clojure
(for [x [1 2 3 4 5 6]
      :when (= 0 (% x 2))]
  x) ; => (2 4 6)

(into {} (for [[k v] {:key "value" :other-key "SHINY"}]
           [k (str "prefix:" v)]))
; => {:key "prefix:value" :other-key "prefix:SHINY"}
```

```fennel
;; fennel
(icollect [i x (ipairs [1 2 3 4 5 6])]
  (if (= 0 (% x 2)) x)) ; => [2 4 6]

(collect [k v (pairs {:key "value" :other-key "SHINY"})]
  (values k (.. "prefix:" v)))
; => {:key "prefix:value" :other-key "prefix:SHINY"}
```

Note that filtering values out using `icollect` does not result in a
table with gaps in it; each value gets added to the end of the table.

All these forms accept iterators. Though the table-based `pairs` and
`ipairs` are the most common iterators, other iterators like
`string.gmatch` or `io.lines` or even custom ones work just as well.

Tables cannot be lazy (again other than thru metatable cleverness) so
to some degree iterators take on the role of laziness.

## Pattern Matching

Tragically Clojure does not have pattern matching as part of the
language. Fennel fixes this problem by implementing the `match` macro.
Refer to [the reference][6] for details. Since `if-let` just an anemic
form of pattern matching, Fennel omits it in favor of `match`.

```clj
;; clojure
(if-let [result (calculate-thingy)]
  (println "Got" result)
  (println "Couldn't get any results"))
```

```fennel
;; fennel
(match (calculate-thingy)
  result (print "Got" result)
  _ (println "Couldn't get any results"))
```

## Modules

Modules in Fennel are first-class; that is, they are nothing more than
tables with a specific mechanism for loading them. This is different
from namespaces in Clojure which have some map-like properties but are
not really data structures in the same way.

In Clojure, vars are public by default. In Fennel, all definitions are
local to the file, but including a local in a table that is placed at
the end of the file will cause it to be exported so other code can use
it. This makes it easy to look in one place to see a list of
everything that a module exports.

```clj
;; clojure
(ns my.namespace)

(def ^:private x 13)
(defn add-x [y] (+ x y))
```

```fennel
;; fennel
(local x 13)
(fn add-x [y] (+ x y))

{: add-x}
```

Modules are loaded by `require` and are typically bound using `local`,
but they are also frequently destructured at the point of binding.

```clojure
;; clojure
(require '[clojure.pprint :as pp])
(require '[my.namespace :refer [add-x]])

(defn show-something []
  (pp/pprint {:a 1 :b (add-x 13)}))
```

```fennel
;; fennel
(local fennel (require :fennel))
(local {: add-x} (require :my.module))

(fn show-something []
  (print (fennel.view {:a 1 :b (add-x 13)})))
```

## Macros

In any lisp, a macro is a function which takes an input form and
returns another form to be compiled in its place. Fennel makes this
even more explicit; macros are loaded as functions from special macro
modules which are loaded in compile scope. They are brought in using
`import-macros`:

```fennel
;; macros.fnl

{:flip (fn [arg1 arg2] `(values ,arg2 ,arg1))}
```

```fennel
;; otherfile.fnl
(import-macros {: flip} :macros)

(print (flip :abc :def))
```

Instead of using `~` for unquote, Fennel uses the more traditional `,`.
At the end of a quoted form you can use `table.unpack` or `unpack` in place
of `~@`.

You can also define macros inline without creating a separate macro
module using `macro`, but these macros cannot be exported from the
module as they do not exist at runtime; also they cannot interact with
other macros.

Lists and symbols are strictly compile-time concepts in Fennel.

## Errors

There are two kinds of ways to represent failure in Lua and
Fennel. The `error` function works a bit like throwing an `ex-info`
in Clojure, except instead of `try` and `catch` we have `pcall` and
`xpcall` to call a function in "protected" state which will prevent
errors from bringing down the process. These can't be chained in the
same way as Exceptions on the JVM are.

See [the tutorial][11] for details.

## Other

There is no `cond` in Fennel because `if` behaves exactly the same as
`cond` if given more than three arguments.

Functions can return [multiple values][9]. This can result in
surprising behavior, but it's outside the scope of this document to
describe. You can use the `values` form in a tail position to return
multiple values.

Operators like `+` and `or`, etc are special forms which must have the
number of arguments fixed at compile time. This means you cannot do
things like `(apply + [1 2 3])` or call `(* ((fn [] (values 4 5 6))))`,
though the latter would work for functions rather than special forms.

[1]: https://github.com/rxi/lume
[2]: https://luafun.github.io/
[3]: https://leiningen.org
[4]: https://luarocks.org
[5]: https://p.hagelb.org/equal-rights-for-functional-objects.html
[6]: https://fennel-lang.org/reference#match-pattern-matching
[7]: https://www.lua.org/pil/7.1.html
[8]: https://github.com/lunarmodules/Penlight
[9]: https://benaiah.me/posts/everything-you-didnt-want-to-know-about-lua-multivals/
[10]: https://www.lua.org/manual/5.4/manual.html#2.2
[11]: https://fennel-lang.org/tutorial#error-handling
