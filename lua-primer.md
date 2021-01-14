# Lua Primer

Once you've finished reading the tutorial, you may be wondering about
the relationship between Fennel and Lua. If you have never programmed
in Lua before, don't fear! It is one of the simplest programming
languages ever. It's possible to learn Fennel without writing any Lua
code, but for certain concepts there's no substitute for the Lua
documentation.

The book Programming in Lua is a great introduction.
[The first edition][6] is available for free online and is still
relevant. However, if you have programmed before in other languages,
you might benefit by focusing on specific areas where Lua is
substantially different.

Lua's types include:

* [nil][7]: represents nothing, treated like false in conditionals
* [booleans][8]: true and false
* [numbers][9]: double-precision floating point only until integers added in 5.3
* [strings][10]: immutable, may contain arbitrary binary data
* [tables][11]: the only data structure
* [coroutines][12]: a mechanism for pre-emptive multitasking
* [userdata][13]: representing types that come from C code

Of these, tables are by far the most complex as well as being the most
different from what you may be used to in other languages. The most
important consideration is that tables are used for both sequential
data (aka lists, vectors, or arrays) as well as associative data (aka
maps, dictionaries, or hashes). The same table can be used in both
roles; whether a table is sequential or associative is not an inherent
property of the table itself but determined by a given piece of code
interacts with the table. Iterating over a table with `ipairs` will
treat it as an array, while `pairs` will treat it as an unordered
key/value map.

The [Lua reference manual][1] covers the entire language (including
details of newer versions) in a more terse form which you may find
more convenient when looking for specific things. The rest of this
document provides a very brief overview of the standard library.

Other Lua runtimes or embedded contexts usually introduce things that
aren't covered here.

## Important top-level functions

* `tonumber`: converts its string argument to a number; takes optional base
* `tostring`: converts its argument to a string
* `print`: prints `tostring` of all its arguments separated by tab characters
* `type`: returns a string describing the type of its argument
* `pcall`: calls a function in protected mode so errors are not fatal
* `error`: halts execution and break to the nearest `pcall`
* `assert`: raises an error if a condition is nil/false, otherwise returns it
* `ipairs`: iterates over sequential tables
* `pairs`: iterates over any table, sequential or not, in undefined order
* `unpack`: turns a sequential table into multiple values (table.unpack in 5.2+)
* `require`: loads and returns a given module

Note that `tostring` on tables will give unsatisfactory results; simply
evaluating the table in the REPL will invoke `fennel.view` for you, and
show a human-readable view of the table (or you can invoke `fennel.view`
explicitly in your code).

## The io module

This module contains functions for operating on the filesystem. Note
that directory listing is absent; you need the luafilesystem library
for that.

To open a file you use `io.open`, which returns a file descriptor upon
success, or nil and a message upon failure. This failure behavior
makes it well-suited for wrapping with `assert` to turn failure into
an error. You can call methods on the file descriptor, concluding with
`f:close`.

```fennel
(let [f (assert (io.open "path/to/file"))]
  (print (f:read)) ; reads a single line by default
  (print (f:read "*a")) ; you can read the whole file
  (f:close))
```

You can also call `io.open` with `:w` as its second argument to open
the file in write mode and then call `f:write` and `f:flush` on the
file descriptor.

The other important function in this module is the `io.lines`
function, which returns an iterator over all the file's lines.

```fennel
(each [line (io.lines "path/to/file")]
  (process-line line))
```

It will automatically close the file once it detects the end of the
file. You can also call `f:lines` on a file descriptor that you got
using `io.open`.

## The table module

This contains some basic table manipulation functions. All these
functions operate on sequential tables, not general key/value tables.
The most important ones are described below:

The `table.insert` function takes a table, an optional position, and
an element, and it will insert the element into the table at that
position. The position defaults to being the end of the
table. Similarly `table.remove` takes a table and an optional
position, removes the element at that position, and returns it. The
position defaults to the last element in the table. To remove
something from a non-sequential table, simply set its key to nil.

The `table.concat` function returns a string that has all the elements
concatenated together with an optional separator.

```fennel
(let [t [1 2 3]]
  (table.insert t 2 "a") ; t is now [1 "a" 2 3]
  (table.insert t "last") ; now [1 "a" 2 3 "last"]
  (print (table.remove t)) ; prints "last"
  (table.remove t 1) ; t is now ["a" 2 3]
  (print (table.concat t ", "))) prints "a, 2, 3"
```

The `table.sort` function a table in-place, as a side-effect. It
takes an optional comparator function which should return true when
its first argument is less than the second.

The `table.unpack` function returns all the elements in the table as
multiple values. Note that `table.unpack` is just `unpack` in Lua 5.1.

## Other important modules

You can explore a module by evaluating it in the REPL to display all
the functions and values it contains.

* `math`: all your standard math functions including trig and `random`
* `string`: all common string operations (except `split` which is absent)
* `os`: operating system functions like `exit`, `time`, `getenv`, etc

Note that Lua does not implement regular expressions but its own more
limited [pattern][2] language for `string.find`, `string.match`, etc.

## Advanced

* `_G`: a table of all globals
* `getfenv`/`setfenv`: access to first-class function environments in
  Lua 5.1; in 5.2 onward use [the _ENV table][3] instead
* `getmetatable`/`setmetatable`: metatables allow you to
  [override the behavior of tables][4]
  in flexible ways with functions of your choice
* `coroutine`: the coroutine module allows you to do
  [flexible control transfer][5] in a first-class way
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

* `_VERSION`: the current version of Lua being used as a string
* `collectgarbage`: you hopefully will never need this
* `debug`: see the Lua manual for this module
* `next`: needed for implementing your own iterators
* `rawequal`/`rawget`/`rawlen`/`rawset`: operations which bypass metatables

[1]: https://www.lua.org/manual/5.1/
[2]: https://www.lua.org/pil/20.2.html
[3]: http://leafo.net/guides/setfenv-in-lua52-and-above.html
[4]: https://www.lua.org/pil/13.html
[5]: http://leafo.net/posts/itchio-and-coroutines.html
[6]: https://www.lua.org/pil/contents.html
[7]: https://www.lua.org/pil/2.1.html
[8]: https://www.lua.org/pil/2.2.html
[9]: https://www.lua.org/pil/2.3.html
[10]: https://www.lua.org/pil/2.4.html
[11]: https://www.lua.org/pil/11.html
[12]: https://www.lua.org/pil/9.1.html
[13]: https://www.lua.org/pil/28.html
