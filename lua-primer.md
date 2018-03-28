# Lua Primer

While the [Lua reference manual](https://www.lua.org/manual/5.1/) is
indispensable, here are the most important parts of Lua you'll need to
get started. This is meant to give a very brief overview and let you
know where in the manual to look for further details, not to teach Lua.

## Important functions

* `tonumber`: converts its string argument to a number; takes optional base
* `tostring`: converts its argument to a string
* `print`: prints `tostring` of all its arguments separated by tab characters
* `type`: returns a string describing the type of its argument
* `pcall`: calls a function in protected mode so errors are not fatal
* `error`: halts execution and break to the nearest `pcall`
* `assert`: raises an error if a condition is nil or false
* `ipairs`: iterates over sequential tables
* `pairs`: iterates over any table, sequential or not, in undefined order
* `unpack`: turns a sequential table into multiple values
* `require`: loads and returns a given module

Note that `tostring` on tables will give unsatisfactory results; you
will want to use `fennelview` or another pretty-printer for debugging
and development.

## Important modules

You can explore a module with `(each [k v (pairs math)] (print k v))`
in the repl to see all the functions and values it contains.

* `math`: all your standard math things including trig and `random`
* `table`: `concat`, `insert`, `remove`, and `sort` are the main things
* `string`: all common string operations (except `split` which is absent)
* `io`: mostly filesystem functions (directory listing is notably absent)
* `os`: operating system functions like `exit`, `time`, `getenv`, etc

In particular `table.insert` and `table.remove` are intended for
sequential tables; they will shift over the indices of every element
after the specified index. To remove something from a non-sequential
table simply set the field to `nil`.

Note that Lua does not implement regular expressions but its own more
limited [pattern](https://www.lua.org/pil/20.2.html) language for
`string.find`, `string.match`, etc.

## Advanced

* `getfenv`/`setfenv`: access to first-class function environments in
  Lua 5.1; in 5.2 onward use
  [the _ENV table](http://leafo.net/guides/setfenv-in-lua52-and-above.html)
  instead
* `getmetatable`/`setmetatable`: metatables allow you to
  [override the behavior of tables](https://www.lua.org/pil/13.html)
  in flexible ways with functions of your choice
* `coroutine`: the coroutine module allows you to do
  [flexible control transfer](http://leafo.net/posts/itchio-and-coroutines.html)
  in a first-class way
* `package`: this module tracks and controls the loading of modules
* `arg`: table of command-line arguments passed to the process
* `...`: arguments passed to the current function; acts as multiple values
* `select`: most commonly used with `...` to find the number of arguments
* `xpcall`: acts like `pcall` but accepts a handler; used to get a
  full stack trace rather than a single line number for errors

## Lua loading

These are used for loading Lua code. The `load*` functions return a
"chunk" function which must be called before the code gets run, but
`dofile` executes immediately.


* `dofile`
* `load`
* `loadfile`
* `loadstring`

## Obscure

* `_G`: a table of all globals
* `_VERSION`: the current version of Lua being used as a string
* `collectgarbage`: you hopefully will never need this
* `debug`: see the Lua manual for this module
* `next`: needed for implementing your own iterators
* `rawequal`/`rawget`/`rawlen`/`rawset`: operations which bypass metatables
