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

## Differences from Lua

* Syntax is much more regular and predictable (no statements; no operator precedence)
* It's impossible to set *or read* a global by accident
* Pervasive destructuring anywhere locals are introduced
* Clearer syntactic distinction between sequential tables and key/value tables
* Separate looping constructs for numeric loops vs iterators instead of overloading `for`
* Comprehensions result in much more succinct table transformations
* Opt-in mutability for local variables
* Opt-in nil checks for function arguments
* Pattern matching
* Ability to extend the syntax with your own macros

## Differences from other lisp languages

* Its VM can be embedded in other programs with only ~200kb
* Access to [excellent FFI][4]
* LuaJIT consistently ranks at the top of performance shootouts
* Inherits aggressively simple semantics from Lua; easy to learn
* Lua VM is already embedded in databases, window managers, games, etc
* Low memory usage
* Readable compiler output resembles input
* Easy to build small (~250kb) standalone binaries
* Compilation output has no runtime dependency on Fennel

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

* Join the `#fennel` IRC chat [Libera.Chat][9] 
* The chat is also bridged [on Matrix][10] if you prefer
* The [mailing list][5] has slower-paced discussion and announcements
* Report issues on the mailing list or [issue tracker][11]
* You can browse and edit [the Wiki][7]
* View builds in Fennel's [continuous integration][8]
* Community interactions are subject to the [code of conduct](CODE-OF-CONDUCT.md).

## Building Fennel from source

This requires GNU Make and Lua (5.1-5.4 or LuaJIT).

1. `cd` to a directory in which you want to download Fennel, such as `~/src`
2. Run `git clone https://git.sr.ht/~technomancy/fennel`
3. Run `cd fennel`
4. Run `make fennel` to create a standalone script called `fennel`
5. Run `sudo make install` to install system-wide (or `make install
   PREFIX=$HOME` if `~/bin` is on your `$PATH`)

If you don't have Lua already installed on your system, you can run
`make fennel-bin LUA=lua/src/lua` instead to build a standalone binary
that has its own internal version of Lua. This requires having a C
compiler installed; normally `gcc`.

See the [contributing guide](CONTRIBUTING.md) for details about how to
work on the source.

## License

Unless otherwise listed, all files are copyright © 2016-2025 Calvin
Rose and contributors, released under the [MIT license](LICENSE).

The file `test/faith.fnl` is copyright © 2009-2025 Scott Vokes, Phil
Hagelberg, and contributors, released under the [MIT license](LICENSE).

The file `style.txt` is copyright © 2007-2011 Taylor R. Campbell,
2021-2025 Phil Hagelberg and contributors, released under the
Creative Commons Attribution-NonCommercial-ShareAlike 3.0
Unported License: https://creativecommons.org/licenses/by-nc-sa/3.0/

[1]: https://fennel-lang.org
[2]: https://dev.fennel-lang.org/wiki/Cookbook
[3]: https://fennel-lang.org/see
[4]: http://luajit.org/ext_ffi_tutorial.html
[5]: https://lists.sr.ht/%7Etechnomancy/fennel
[7]: https://dev.fennel-lang.org/
[8]: https://builds.sr.ht/~technomancy/fennel
[9]: https://libera.chat
[10]: https://matrix.to/#/!rnpLWzzTijEUDhhtjW:matrix.org?via=matrix.org
[11]: https://dev.fennel-lang.org/report/1
