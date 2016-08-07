# Fnl

Fnl is a lisp that compiles to Lua. It aims to be easy to use, expressive, and have almost
zero overhead compared to handwritten Lua. It's currently a single file Lua library that can
be dragged into any Lua project.

## Lua API

The fnl.lua module exports the following functions:

* fnl.repl() - Starts a simple REPL.
* fnl.eval(str, options) - Evaluates a string of Fnl.
* fnl.compile(str, options) - Compiles a string of Fnl into a string of Lua
* fnl.parse(str) - Reads a string and returns an AST.
* fnl.compileAst - Compiles an AST into a Lua string.

## Try it

Clone the repository, and run 'lua repl.lua' to quickly start a repl.
