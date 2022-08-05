# Fennel

[Fennel][1] is a lisp that compiles to Lua. It aims to be easy to use,
expressive, and has almost zero overhead compared to writing Lua directly.

* *Full Lua compatibility* - You can use any function or library from Lua.
* *Zero overhead* - Compiled code should be just as efficient as hand-written Lua.
* *Compile-time macros* - Ship compiled code with no runtime dependency on Fennel.
* *Embeddable* - Fennel is a one-file library as well as an executable. Embed it in other programs to support runtime extensibility and interactive development.

At [https://fennel-lang.org][1] there's a live in-browser repl you can
use without installing anything. At [https://fennel-lang.org/see][3]
you can see what Lua output a given piece of Fennel compiles to, or
what the equivalent Fennel for a given piece of Lua would be.

## Documentation

* The [setup](setup.md) guide is a great place to start
* The [tutorial](tutorial.md) teaches the basics of the language
* The [rationale](rationale.md) explains the reasoning of why Fennel was created
* The [reference](reference.md) describes all Fennel special forms
* The [macro guide](macros.md) explains how to write macros
* The [API listing](api.md) shows how to integrate Fennel into your codebase
* The [style guide](style.md) gives tips on how to write clear and concise code
* The [Lua primer](lua-primer.md) gives a very brief intro to Lua with
  pointers to further details

For more examples, see [the cookbook][2] on [the wiki][7].

The [changelog](changelog.md) has a list of user-visible changes for
each release.

## Example

#### Hello World
```Fennel
(print "hello, world!")
```

#### Fibonacci sequence
```Fennel
(fn fib [n]
  (if (< n 2)
      n
      (+ (fib (- n 1)) (fib (- n 2)))))

(print (fib 10))
```

## Building Fennel from source

Building Fennel from source allows you to use versions of Fennel that
haven't been released, and it makes contributing to Fennel easier.

### To build Fennel from source

1. `cd` to a directory in which you want to download Fennel, such as
   `~/src`
2. Run `git clone https://git.sr.ht/~technomancy/fennel`
3. Run `cd fennel`
4. Run `make fennel` to create a standalone script called `fennel`
5. Copy or link the `fennel` script to a directory on your `$PATH`, such as `/usr/local/bin`

**Note**: If you copied the `fennel` script to one of the
directories on your `$PATH`, then you can run `fennel filename.fnl` to
run a Fennel file anywhere on your system.

## Differences from Lua

* Syntax is much more regular and predictable (no statements; no operator precedence)
* It's impossible to set *or read* a global by accident
* Pervasive destructuring anywhere locals are introduced
* Clearer syntactic distinction between sequential tables and key/value tables
* Separate looping constructs for numeric loops vs iterators instead of overloading `for`
* Opt-in mutability for local variables
* Opt-in nil checks for function arguments
* Pattern matching
* Ability to extend the syntax with your own macros

## Differences from other lisp languages

* Its VM can be embedded in other programs with only 180 kB
* Access to [excellent FFI][4]
* LuaJIT consistently ranks at the top of performance shootouts
* Inherits aggressively simple semantics from Lua; easy to learn
* Lua VM is already embedded in databases, window managers, games, etc
* Low memory usage
* Readable compiler output resembles input

## Why not Fennel?

Fennel inherits the limitations of the Lua runtime, which does not offer
pre-emptive multitasking or OS-level threads. Libraries for Lua work
great with Fennel, but the selection of libraries is not as extensive
as it is with more popular languages. While LuaJIT has excellent
overall performance, purely-functional algorithms will not be as
efficient as they would be on a VM with generational garbage collection.

Even for cases where the Lua runtime is a good fit, Fennel might not
be a good fit when end-users are expected to write their own code to
extend the program, because the available documentation for learning
Lua is much more readily-available than it is for Fennel.

## Resources

* Join the `#fennel` chat [thru IRC on Libera.Chat][9] or [on Matrix][10]
* The [mailing list][5] has slower-paced discussion and announcements
* Report issues on the mailing list, [Sourcehut todo][11] or [Github issues][12]
* You can browse and edit [the Wiki][7]
* View builds in Fennel's [continuous integration][8]
* Community interactions are subject to the [code of conduct](CODE-OF-CONDUCT.md).

## License

Copyright © 2016-2022 Calvin Rose and contributors

Released under the [MIT license](LICENSE).

[1]: https://fennel-lang.org
[2]: https://github.com/bakpakin/Fennel/wiki/Cookbook
[3]: https://fennel-lang.org/see
[4]: http://luajit.org/ext_ffi_tutorial.html
[5]: https://lists.sr.ht/%7Etechnomancy/fennel
[7]: https://github.com/bakpakin/Fennel/wiki
[8]: https://builds.sr.ht/~technomancy/fennel
[9]: https://libera.chat
[10]: https://matrix.to/#/!rnpLWzzTijEUDhhtjW:matrix.org?via=matrix.org
[11]: https://todo.sr.ht/~technomancy/fennel
[12]: https://github.com/bakpakin/Fennel/issues
