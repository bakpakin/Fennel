# Fennel

[Fennel](https://fennel-lang.org) (formerly fnl) is a lisp that compiles to Lua. It aims to be easy to use, expressive, and has almost
zero overhead compared to handwritten Lua.

* *Full Lua compatibility* - You can use any function or library from Lua.
* *Zero overhead* - Compiled code should be just as or more efficient than hand-written Lua.
* *Compile-time macros* - Ship compiled code with no runtime dependency on Fennel.
* *Embeddable* - Fennel is a one-file library as well as an executable. Embed it in other programs to support runtime extensibility and interactive development.

## Documentation

* The [tutorial](tutorial.md) is a great place to start
* The [reference](reference.md) describes all Fennel special forms
* The [API listing](api.md) shows how to integrate Fennel into your codebaes
* The [Lua primer](lua-primer.md) gives a very brief intro to Lua with
  pointers to further details
* The [test suite](test.lua) has basic usage examples for most features.

For a small complete example that uses the LÖVE game engine, see
[pong.fnl](https://p.hagelb.org/pong.fnl.html).

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

## Try it

At [https://fennel-lang.org](https://fennel-lang.org) there's a live
in-browser repl you can use without installing anything.

Otherwise clone this repository, and run `./fennel --repl` to quickly
start a repl. Use `./fennel my-file.fnl` to run code or `./fennel
--compile my-file.fnl > my-file.lua` to perform ahead-of-time compilation.

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
* Access to [excellent FFI](http://luajit.org/ext_ffi_tutorial.html)
* LuaJIT consistently ranks at the top of performance shootouts
* Inherits aggressively simple semantics from Lua; easy to learn
* Lua VM is already embedded in databases, window managers, games, etc
* Low memory usage
* Readable compiler output resembles input

(Obviously not all these apply to every lisp you could compare Fennel to.)

## Install with Luarocks

You can install the dev package from luarocks via
```sh
luarocks install --server=http://luarocks.org/dev fennel
``` 

This will install both the fennel module, which can be required into via `local fennel = require 'fennel'`,
as well as the `fennel` executable which can be used to run a repl or compile Fennel to Lua.

To start a repl:
```sh
fennel --repl
```

To compile a file:
```sh
fennel --compile myscript.fnl > myscript.lua
```

When given a file without a flag, it will simply load and run the file.

## Resources

* [Emacs support](https://gitlab.com/technomancy/fennel-mode)
* [Wiki](https://github.com/bakpakin/Fennel/wiki)
* Build: [![CircleCI](https://circleci.com/gh/bakpakin/Fennel.svg?style=svg)](https://circleci.com/gh/bakpakin/Fennel)
* The `#fennel` IRC channel is [on Freenode](https://webchat.freenode.net/)

## License

Copyright © 2016-2018 Calvin Rose and contributors

Released under the MIT license
