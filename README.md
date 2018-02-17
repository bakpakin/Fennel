# Fnl

Fnl is a lisp that compiles to Lua. It aims to be easy to use, expressive, and has almost
zero overhead compared to handwritten Lua. It's currently a single file Lua library that can
be dragged into any Lua project.

The documentation is currently sparse, but I don't want to commit too many features to documentation
that haven't been fully defined. See `test.lua` for usage examples for most features.

Current features include:

* Full Lua compatibility - You can use any function from Lua
* Zero overhead - Compiled code should be fast, standalone, and just as or more efficient than hand-written Lua.
* Compile time only macros - Macros exist only at compile time and are not output in the final Lua compilation. In fact,
  macros are just a special case of special forms.
* Ability to write custom special forms - Special forms are s-expressions that, when evaulated, directly output Lua code.    This feature may be removed, in preference for macros.

Eventually, I also hope to add optional source maps, either embedded in the comments of the generated code, or in separate files. An optional standard library also needs to be made.

## Lua API

The fnl.lua module exports the following functions:

* `fnl.repl()` - Starts a simple REPL.
* `fnl.eval(str, options)` - Evaluates a string of Fnl.
* `fnl.compile(str, options)` - Compiles a string of Fnl into a string of Lua
* `fnl.parse(str)` - Reads a string and returns an AST.
* `fnl.compileAst(ast)` - Compiles an AST into a Lua string.

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

Clone the repository, and run `lua fnl --repl` to quickly start a repl.

## Install with Luarocks

You can install the dev package from luarocks via
```sh
luarocks install --server=http://luarocks.org/dev fnl
```

## License

Copyright © 2016-2018 Calvin Rose and contributors

Released under the MIT license
