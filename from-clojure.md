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
quite minimal, it's common to pull in 3rd-party things like [Lume][1]
or [LuaFun][2] for things you might expect to be built-in to the
language.

In Clojure it's typical to bring in libraries using a tool like
[Leiningen][3]. In Fennel you can use [LuaRocks][4] for dependencies,
but it's often overkill. Usually it's better to just check your
dependencies into your source repository. Deep dependency trees are
very rare in Fennel and Lua. Deploying Clojure usually means creating
an uberjar that you launch using an existing JVM installation, because
the JVM is a pretty large piece of software. Fennel deployments are
much more varied; you can easily create self-contained standalone
executables that are under a megabyte, or you can create scripts which
rely on an existing Lua install, or code which gets embedded inside a
larger application.

## Functions and locals

Clojure has two types of scoping: lexical (for locals) and dynamic
(for vars). Fennel only has lexical scope. (Globals exist, but they're
mostly used for debugging and repl purposes; you don't use them in
normal code.) This means that the "unit of reloading" is not the
top-level form, but the module. Fennel's repl includes a `,reload
module-name` command for this.

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

Fennel does not have `apply`; instead you unpack arguments. Instead of Clojure's
`(apply plus [1 2 3])` you would do `(plus (table.unpack [1 2
3]))`. (In older versions of Lua it's `unpack` instead of `table.unpack`.)

## Tables

* "keywords" are strings

## Iterators

## Pattern Matching

Tragically Clojure does not have pattern matching as part of the
language. Fennel fixes this problem by implementing pattern matching.

## Modules

## Macros

* compile-scope is very different
* macros in normal modules cannot be exported

## Errors

## Other

* if is cond
* compile-time arity for operators

[1]: https://github.com/rxi/lume
[2]: https://luafun.github.io/
[3]: https://leiningen.org
[4]: https://luarocks.org
