# Fennel

[Fennel][1] is a lisp that compiles to Lua. It aims to be easy to use,
expressive, and has almost zero overhead compared to handwritten Lua.

* *Full Lua compatibility* - You can use any function or library from Lua.
* *Zero overhead* - Compiled code should be just as or more efficient than hand-written Lua.
* *Compile-time macros* - Ship compiled code with no runtime dependency on Fennel.
* *Embeddable* - Fennel is a one-file library as well as an executable. Embed it in other programs to support runtime extensibility and interactive development.

## Documentation

* The [tutorial](tutorial.md) is a great place to start
* The [reference](reference.md) describes all Fennel special forms
* The [API listing](api.md) shows how to integrate Fennel into your codebase
* The [Lua primer](lua-primer.md) gives a very brief intro to Lua with
  pointers to further details
* The [test suite](test.lua) has basic usage examples for most features.

For a small complete example that uses the LÖVE game engine, see
[pong.fnl][2].

The [changelog](changelog.md) has a list of user-visible changes for
each release.

## Example

#### Hello World
```
(print "hello, world!")
```

#### Fibonacci sequence
```
(fn fib [n]
 (if (< n 2)
  n
  (+ (fib (- n 1)) (fib (- n 2)))))

(print (fib 10))
```

## Usage

At [https://fennel-lang.org][1] there's a live in-browser repl you can
use without installing anything.

Check your OS's package manager to see if Fennel is available
there. If you use [LuaRocks][3] you can run `luarocks install fennel`.

Otherwise clone this repository, and run `./fennel` to start a
repl. Use `./fennel my-file.fnl` to run code or `./fennel --compile
my-file.fnl > my-file.lua` to perform ahead-of-time compilation.

See the [API documentation](api.md) for how to embed Fennel in your program.

## Differences from Lua

* Syntax is much more regular and predictable (no statements; no operator precedence)
* It's impossible to set *or read* a global by accident
* Pervasive destructuring anywhere locals are introduced
* Clearer syntactic distinction between sequential tables and key/value tables
* Separate looping constructs for numeric loops vs iterators instead of overloading `for`
* Opt-in mutability for local variables
* Opt-in arity checks for `lambda` functions
* Ability to extend the syntax with your own macros and special forms

## Differences from other lisp languages

* Lua VM can be embedded in other programs with only 180kb
* Access to [excellent FFI][4]
* LuaJIT consistently ranks at the top of performance shootouts
* Inherits aggressively simple semantics from Lua; easy to learn
* Lua VM is already embedded in databases, window managers, games, etc
* Low memory usage
* Readable compiler output resembles input

(Obviously not all these apply to every lisp you could compare Fennel to.)

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

Editor support is currently somewhat limited outside Emacs/Vim, but
unsupported editors can be used with syntax highlighting for Clojure
reasonably well.

## Resources

* [Mailing list][5]
* [Emacs support][6]
* [Vim support][10]
* [Wiki][7]
* Build: [![CircleCI](https://circleci.com/gh/bakpakin/Fennel.svg?style=svg)][8]
* The `#fennel` IRC channel is [on Freenode][9]

## License

Copyright © 2016-2019 Calvin Rose and contributors

Released under the MIT license

[1]: https://fennel-lang.org
[2]: https://p.hagelb.org/pong.fnl.html
[3]: https://luarocks.org/
[4]: http://luajit.org/ext_ffi_tutorial.html
[5]: https://lists.sr.ht/%7Etechnomancy/fennel
[6]: https://gitlab.com/technomancy/fennel-mode
[7]: https://github.com/bakpakin/Fennel/wiki
[8]: https://circleci.com/gh/bakpakin/Fennel
[9]: https://webchat.freenode.net/
[10]: https://github.com/bakpakin/fennel.vim
