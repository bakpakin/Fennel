# Learning Fennel from Clojure

Fennel takes a lot of inspiration from Clojure. If you already know
Clojure, then you'll have a good head start on Fennel. However, there
are still a lot of differences! This document will guide you thru
those differences and get you up to speed from the perspective of
someone who already knows Clojure.

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
built-in to the language.

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
top-level form, but the module. Fennel's repl includes a `,reload
module-name` command for this.

Fennel supports destructuring similarly to Clojure. The main
difference is that rather than using `{:keys [abc def xyz]}` Fennel
has a notation where a bare `:` can be used `{: abc : def : xyz}` is
the equivalent of the `:keys` notation above.

Like Clojure, Fennel uses the `fn` form to create functions. However,
giving it a name will also declare it as a local rather than having
the name be purely internal. Functions declared with `fn` have no
arity checking; you can call them with any number of arguments. To
have arity checking, declare with `lambda` instead, and it will throw
an exception if you provide too few arguments.

Like Clojure, normal locals cannot be given new values. However,
Fennel has a special `var` form that will allow you to declare a
special kind of local which can be given a new value with `set`.

Fennel also uses `#(foo)` notation as shorthand for anonymous
functions. There are two main differences; the first is that it uses `$1`,
`$2`, etc instead of `%1`, `%2` for arguments. Secondly while Clojure
requires parens in this shorthand, Fennel does not. `#5` in Fennel
is the equivalent of Clojure's `(constantly 5)`.

Fennel does not have `apply`; instead you unpack arguments. Rather
than Clojure's `(apply plus [1 2 3])` you would do `(plus
(table.unpack [1 2 3]))`. (In older versions of Lua it's `unpack`
instead of `table.unpack`.)

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
you immutable operations on mutable tables without a lot of overhead.

Like Clojure, any value can serve as a key. However, since tables are
mutable data, two tables with identical values will not be `=` to each
other as [per Baker][5] and thus will act as distinct keys. Clojure`s
`:keyword` notation is used in Fennel as a syntax for certain kinds of
strings; there is no distinct type for keywords.

Note that `nil` in Fennel is very different from Clojure; in Clojure
it has many different meanings, but in Fennel it always represents the
absence of a value. As such, tables **cannot** contain
`nil`. Attempting to put `nil` in a table is equivalent to removing
the value from the table, and you never have to worry about the
difference between "the table does not contain this key" vs "the table
contains a nil value at this key".

Tables cannot be called like functions, nor can `:keyword` style
strings. If a string key is statically known, you can use `tbl.key`
notation; if it's not, you use the `.` form in cases where you can't
destructure: `(. tbl key)`.

## Iterators

In Clojure, we have this idea that "everything is a seq". Lua and
Fennel, not being explicitly functional, have instead "everything is
an iterator". [Programming in Lua][7] has a detailed explanation of
iterators. The `each` special form consumes iterators and steps
thru them similarly to how `doseq` does.

Since Fennel has no functions, it relies on macros to do things like
`map` and `filter`. Similarly to Clojure's `for`, Fennel has a pair of
macros that operate on iterators and produce tables. `collect` walks
thru an iterator and allows the body to return a key and value using
`values` to return a key/value table. The `icollect` macro is similar
in that it returns a table, except the body should only return one
value, and the returned table is sequential rather than key/value. The
body of either macro allows you to return `nil` to filter out that
entry from the result table.

```fennel
(icollect [i x (ipairs [1 2 3 4 5 6])]
  (if (= 0 (% i 2)) i)) ; => [2 4 6]
```

Note that filtering values out using `icollect` does not result in a
table with gaps in it; each value gets added to the end of the table.

All these forms accept iterators. Though the table-based `pairs` and
`ipairs` are the most common iterators, other iterators like
`string.gmatch` or `io.lines` or even custom ones work just as well.

## Pattern Matching

Tragically Clojure does not have pattern matching as part of the
language. Fennel fixes this problem by implementing the `match` macro.
Refer to [the reference][6] for details.

Since `if-let` just an extremely limited form of pattern matching,
Fennel omits it. Use `match` where you would use `if-let` in Clojure.

## Modules

Modules in Fennel are first-class; that is, they are nothing more than
tables with a specific mechanism for loading them. This is different
from namespaces in Clojure which have some map-like properties but are
not really data structures in the same way.

Modules are loaded by `require` and are typically bound using `local`,
but they are also frequently destructured at the point of binding.

```fennel
(local {: view} (require :fennel))

(print (view {:a 1 :b 2}))
```

## Macros

In any lisp, a macro is a function which takes an AST and returns
another AST. Fennel makes this even more explicit; macros are loaded
as functions from special macro modules which are loaded in compile
scope. They are brought in using `import-macros`:

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
At the end of a table you can use `table.unpack` or `unpack` in place
of `~@`.

You can also define macros inline without creating a separate macro
module using `macro`, but these macros cannot be exported from the
module as they do not exist at runtime; also they cannot interact with
other macros.

## Errors

There are two kinds of ways to represent failure in Lua and
Fennel. The `error` function works a bit like throwing an `ex-info`
in Clojure, except instead of `try` and `catch` we have `pcall` and
`xpcall` to call a function in "protected" state which will prevent
errors from bringing down the process.

```fennel
(match (pcall dangerous-function arg1 arg2)
  (true val) (print "Success; got:" val)
  (false msg) (print "Failure: " msg))
```

The second style of representing failures eschews `pcall` and `error`
altogether and simply returns two values from the function, a boolean
indicating success or failure, and either a value or a message
describing the problem. Using `match` helps clean up code that works
with these kinds of functions.

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
[5]: http://home.pipeline.com/%7Ehbaker1/ObjectIdentity.html
[6]: https://fennel-lang.org/reference#match-pattern-matching
[7]: https://www.lua.org/pil/7.1.html
[8]: https://github.com/lunarmodules/Penlight
[9]: https://benaiah.me/posts/everything-you-didnt-want-to-know-about-lua-multivals/
