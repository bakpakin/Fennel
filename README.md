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

There is a `#fennel` IRC channel on Freenode where some Fennel users
and contributors discuss.

## Lua API

The fennel module exports the following functions. Most functions take
an `indent` function to override how to indent the compiled Lua output
or an `accurate` function to ignore indentation and attempt to make
the lines in the output code match up with the lines in the input code.

### Start a configurable repl

```lua
fennel.repl([options])
```
Takes these additional options:

* `read`, `write`, and `flush`: replacements for equivalents from `io` table.
* `pp`: a pretty-printer function to apply on values; defaults to `tostring`.
* `env`: an environment table in which to run the code; see the Lua manual.

### Evaulate a string of Fennel

```lua
local result = fennel.eval(str[, options])
```

Takes these additional options:

* `env`: same as above.
* `filename`: override the filename that Lua thinks the code came from.

### Evaluate a file of Fennel

```lua
local result = fennel.dofile(filename[, options])
```

* `env`: same as above.

### Use Lua's built-in require function

```lua
table.insert(package.loaders, fennel.searcher)
local mylib = require("mylib") -- will compile and load code in mylib.fnl
```

Normally Lua's `require` function only loads modules written in Lua,
but you can install `fennel.searcher` into `package.loaders` to teach
it how to load Fennel code.

The `require` function is different from `fennel.dofile` in that it
searches the directories in `fennel.path` for `.fnl` files matching
the module name, and also in that it caches the loaded value to return
on subsequent calls, while `fennel.dofile` will reload each time. The
behavior of `fennel.path` mirrors that of Lua's `package.path`.

If you install Fennel into `package.loaders` then you can use the
3rd-party [lume.hotswap](https://github.com/rxi/lume#lumehotswapmodname) 
function to reload modules that have been loaded with `require`.

### Compile a string into Lua (can throw errors)

```lua
local lua = fennel.compileString(str[, options])
```

### Compile an iterator of bytes into a string of Lua (can throw errors)

```lua
local lua = fennel.compileStream(strm, options)
```

### Get an iterator over the bytes in a string

```lua
local stream = fennel.stringStream(str)
```
    
### Converts an iterator for strings into an iterator over their bytes

Useful for the REPL or reading files in chunks. This will NOT insert
newlines or other whitespace between chunks, so be careful when using
with io.read().  Returns a second function, clearstream, which will
clear the current buffered chunk when called. Useful for implementing
a repl.

```lua
local bytestream, clearstream = fennel.granulate(chunks)
```
    
### Converts a stream of bytes to a stream of values

Valuestream gets the next top level value parsed.
Returns true in the first return value if a value was read, and
returns nil if and end of file was reached without error. Will error
on bad input or unexpected end of source.

```lua
local valuestream = fennel.parser(strm)
local ok, value = valuestream()

-- Or use in a for loop
for ok, value in valuestream do
    print(ok, value)
end
```

### Compile a data structure (AST) into Lua source code

The code can be loaded via dostring or other methods. Will error on bad input.

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

Clone the repository, and run `./fennel --repl` to quickly start a repl.

The repl will load the file `~/.fennelrc` on startup if it exists. If
you'd like to install a pretty-printer for the repl (recommended), put
this in that file:

```lisp
(set options.pp (dofile "/path/to/inspect.lua"))
```

You can point it at a pretty-printing function of your choice; here we
use [inspect.lua](https://github.com/kikito/inspect.lua).

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
* [Wiki](https://github.com/bakpakin/Fennel/wiki)
* Build: [![CircleCI](https://circleci.com/gh/bakpakin/Fennel.svg?style=svg)](https://circleci.com/gh/bakpakin/Fennel)

## License

Copyright © 2016-2018 Calvin Rose and contributors

Released under the MIT license
