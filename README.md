# Fennel

Fennel (formerly fnl) is a lisp that compiles to Lua. It aims to be easy to use, expressive, and has almost
zero overhead compared to handwritten Lua. It's currently a single file Lua library that can
be dragged into any Lua project.

See [the tutorial](https://github.com/bakpakin/Fennel/tree/master/tutorial.md)
for an overview of the language features. The `test.lua` suite has usage
examples for most features. For a small complete example that uses the LÖVE
game engine, see [pong.fnl](https://p.hagelb.org/pong.fnl.html).

Current features include:

* Full Lua compatibility - You can use any function from Lua
* Zero overhead - Compiled code should be fast, standalone, and just as or more efficient than hand-written Lua.
* Compile time only macros - Macros exist only at compile time and are not output in the final Lua compilation. In fact,
  macros are just a special case of special forms.
* Ability to write custom special forms - Special forms are s-expressions that, when evaulated, directly output Lua code.
* Fennel is a library as well as a compiler. Embed it in other projects.

Eventually, I also hope to add optional source maps, either embedded in the comments of the generated code, or in separate files. An optional standard library also needs to be made.

## Lua API

The fennel module exports the following functions:

Start a configurable repl.
```lua
fennel.repl([options])
```

Evaulate a string of Fennel.
```lua
local result = fennel.eval(str[, options])
```

Compile a string into Lua. Can throw errors.
```lua
local lua = fennel.compileString(str[, options])
```

Compile an iterator of bytes into a string of Lua. Can throw errors.
```lua
local lua = fennel.compileStream(strm, options)
```

Get an iterator over the bytes in a string.
```lua
local stream = fennel.stringStream(str)
```
    
Converts an iterator for strings into an iterator over their bytes. Useful
for the REPL or reading files in chunks. This will NOT insert newlines or
other whitespace between chunks, so be careful when using with io.read().
Returns a second function, clearstream, which will clear the current buffered
chunk when called. Useful for implementing a repl.
```lua
local bytestream, clearstream = fennel.granulate(chunks)
```
    
Get the next top level value parsed from a stream of
bytes. Returns true in the first return value if a value was read, and
returns nil if and end of file was reached without error. Will error
on bad input or unexpected end of source.
```lua
local ok, value = fennel.parse(strm)
```

Compile a data structure (AST) into Lua source code. The code can be loaded
via dostring or other methods. Will error on bad input.
```lua
local lua = fennel.compile(ast)
```

## Example

#### Hello World
```
(print "hello, world!")
```

#### Fibonacci sequence
```
(set fib (fn [n] (or (and (> n 1)
                          (+ (fib (- n 1))
                             (fib (- n 2))))
                     1)))

(print (fib 10))
```

## Try it

Clone the repository, and run `lua fennel --repl` to quickly start a repl.

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

## Resources

* [Emacs support](https://gitlab.com/technomancy/fennel-mode)

## License

Copyright © 2016-2018 Calvin Rose and contributors

Released under the MIT license
