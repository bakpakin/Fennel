## Fennel's Lua API

The `fennel` module provides the following functions.

### Start a configurable repl

```lua
fennel.repl([options])
```

Takes these additional options:

* `readChunk()`: a function that when called, returns a string of source code.
  The empty is string is used as the end of source marker.
* `pp`: a pretty-printer function to apply on values.
* `env`: an environment table in which to run the code; see the Lua manual.
* `onValues(values)`: a function that will be called on all returned top level values.
* `onError(errType, err, luaSource)`: a function that will be called on each error.
  `errType` is a string with the type of error, can be either, 'parse',
  'compile', 'runtime',  or 'lua'. `err` is the error message, and `luaSource`
  is the source of the generated lua code.
* `allowedGlobals`: a sequential table of strings of the names of globals which
  the compiler will allow references to.

The pretty-printer defaults to loading `fennelview.fnl` if present and
falls back to `tostring` otherwise. `fennelview.fnl` will produce
output that can be fed back into Fennel (other than functions,
coroutines, etc) but you can use a 3rd-party pretty-printer that
produces output in Lua format if you prefer.

If you don't provide `allowedGlobals` then it defaults to being all
the globals in the environment under which the code will run. Passing
in `false` here will disable global checking entirely.

### Evaulate a string of Fennel

```lua
local result = fennel.eval(str[, options[, ...]])
```

The `options` table may contain:

* `env`: same as above.
* `allowedGlobals`: same as above.
* `filename`: override the filename that Lua thinks the code came from.

Additional arguments beyond `options` are passed to the code and
available as `...`.

### Evaluate a file of Fennel

```lua
local result = fennel.dofile(filename[, options[, ...]])
```

The `env` key in `options` and the additional arguments after it work
the same as with `eval` above.

### Use Lua's built-in require function

```lua
table.insert(package.loaders or package.searchers, fennel.searcher)
local mylib = require("mylib") -- will compile and load code in mylib.fnl
```

Normally Lua's `require` function only loads modules written in Lua,
but you can install `fennel.searcher` into `package.loaders` (or in
Lua 5.3+ `package.searchers`) to teach it how to load Fennel code.

The `require` function is different from `fennel.dofile` in that it
searches the directories in `fennel.path` for `.fnl` files matching
the module name, and also in that it caches the loaded value to return
on subsequent calls, while `fennel.dofile` will reload each time. The
behavior of `fennel.path` mirrors that of Lua's `package.path`.

If you install Fennel into `package.loaders` then you can use the
3rd-party [lume.hotswap][1] function to reload modules that have been
loaded with `require`.

### Compile a string into Lua (can throw errors)

```lua
local lua = fennel.compileString(str[, options])
```

Accepts `indent` as a string in `options` causing output to be
indented using that string, which should contain only whitespace if
provided. Unlike the other functions, the `compile` functions default
to performing no global checks, though you can pass in an `allowedGlobals`
table in `options` to enable it.

### Compile an iterator of bytes into a string of Lua (can throw errors)

```lua
local lua = fennel.compileStream(strm[, options])
```

Accepts `indent` in `options` as per above.

### Compile a data structure (AST) into Lua source code (can throw errors)

The code can be loaded via dostring or other methods. Will error on bad input.

```lua
local lua = fennel.compile(ast[, options])
```

Accepts `indent` in `options` as per above.

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

[1]: https://github.com/rxi/lume#lumehotswapmodname
