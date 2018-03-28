# Fennel

Fennel (formerly fnl) is a lisp that compiles to Lua. It aims to be easy to use, expressive, and has almost
zero overhead compared to handwritten Lua. It's currently a single file Lua library that can
be dragged into any Lua project.

Current features include:

* Full Lua compatibility - You can use any function from Lua.
* Zero overhead - Compiled code should be fast, standalone, and just as or more efficient than hand-written Lua.
* Compile time only macros - Macros exist only at compile time and are not output in the final Lua compilation. In fact,
  macros are just a special case of special forms.
* Ability to write custom special forms - Special forms are s-expressions that, when evaulated, directly output Lua code.
* Fennel is a library as well as a compiler. Embed it in other projects.

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
(local fib (fn [n] (or (and (> n 1)
                            (+ (fib (- n 1))
                               (fib (- n 2))))
                       1)))

(print (fib 10))
```

## Try it

Clone the repository, and run `./fennel --repl` to quickly start a repl.

The repl will load the file `~/.fennelrc` on startup if it exists.

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
