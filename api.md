# Fennel's Lua API

The `fennel` module provides the following functions for use when
embedding Fennel in a Lua program. If you're writing a pure Fennel
program or working on a system that already has Fennel support, you
probably don't need this.

Any time a function takes an `options` table argument, that table will
usually accept these fields:

* `allowedGlobals`: a sequential table of strings of the names of globals which
  the compiler will allow references to. Set to false to disable checks.
* `correlate`: when this is truthy, Fennel attempts to emit Lua where the line
  numbers match up with the Fennel input code; useful for situation where code
  that isn't under your control will print the stack traces.
* `useMetadata` *(since 0.3.0)*: enables or disables [metadata](#work-with-docstrings-and-metadata),
  allowing use of the doc macro. Intended for development purposes
  (see [performance note](#metadata-performance-note)); defaults to
  true for REPL only.
* `requireAsInclude` *(since 0.3.0)*: Alias any static `require` calls to the `include` special,
  embedding the module code inline in the compiled output. If the module name isn't a string
  literal or resolvable at compile time, falls back to `require` at runtime. Can be used to
  embed both fennel and Lua modules.
* `env`: an environment table in which to run the code; see the Lua manual.
* `compilerEnv`: an environment table in which to run compiler-scoped code
  for macro definitions and `eval-compiler` calls. Internal Fennel functions
  such as `list`, `sym`, etc. will be exposed in addition to this table.
  Defaults to a table containing limited known-safe globals. Pass `_G` to
  disable sandboxing.
* `unfriendly`: disable friendly compiler/parser error messages.

Note that only the `fennel` module is part of the public API. The
other modules (`fennel.utils`, `fennel.compiler`, etc) should be
considered compiler internals subject to change.

## Start a configurable repl

```lua
fennel.repl([options])
```

Takes these additional options:

* `readChunk()`: a function that when called, returns a string of source code.
  The empty is string is used as the end of source marker.
* `pp`: a pretty-printer function to apply on values.
* `onValues(values)`: a function that will be called on all returned top level values.
* `onError(errType, err, luaSource)`: a function that will be called on each error.
  `errType` is a string with the type of error, can be either, 'parse',
  'compile', 'runtime',  or 'lua'. `err` is the error message, and `luaSource`
  is the source of the generated lua code.

`src/fennel/view.fnl` will produce output that can be fed back into Fennel
(other than functions, coroutines, etc) but you can use a 3rd-party
pretty-printer that produces output in Lua format if you prefer.

If you don't provide `allowedGlobals` then it defaults to being all
the globals in the environment under which the code will run. Passing
in `false` here will disable global checking entirely.

By default, metadata will be enabled and you can view function signatures and
docstrings with the `doc` macro from the REPL.

## Evaulate a string of Fennel

```lua
local result = fennel.eval(str[, options[, ...]])
```

The `options` table may also contain:

* `filename`: override the filename that Lua thinks the code came from.

Additional arguments beyond `options` are passed to the code and
available as `...`.

## Evaluate a file of Fennel

```lua
local result = fennel.dofile(filename[, options[, ...]])
```

## Use Lua's built-in require function

```lua
table.insert(package.loaders or package.searchers, fennel.searcher)
local mylib = require("mylib") -- will compile and load code in mylib.fnl
```

Normally Lua's `require` function only loads modules written in Lua,
but you can install `fennel.searcher` into `package.searchers` (or in
Lua 5.1 `package.loaders`) to teach it how to load Fennel code.

If you would rather change some of the `options` you can use
`fennel.makeSearcher` to override `env`, `correlate`, etc.

The `require` function is different from `fennel.dofile` in that it
searches the directories in `fennel.path` for `.fnl` files matching
the module name, and also in that it caches the loaded value to return
on subsequent calls, while `fennel.dofile` will reload each time. The
behavior of `fennel.path` mirrors that of Lua's `package.path`.

If you install Fennel into `package.searchers` then you can use the
3rd-party [lume.hotswap][1] function to reload modules that have been
loaded with `require`.

## Search the path for a module without loading it

```lua
print(fennel.searchModule("my.mod", package.path))
```

If you just want to find the file path that a module would resolve to
without actually loading it, you can use `fennel.searchModule`. The
first argument is the module name, and the second argument is the path
string to search. If none is provided, it defaults to Fennel's own path.

Returns `nil` if the module is not found on the path.

## Compile a string into Lua (can throw errors)

```lua
local lua = fennel.compileString(str[, options])
```

Accepts `indent` as a string in `options` causing output to be
indented using that string, which should contain only whitespace if
provided. Unlike the other functions, the `compile` functions default
to performing no global checks, though you can pass in an `allowedGlobals`
table in `options` to enable it.

## Compile an iterator of bytes into a string of Lua (can throw errors)

```lua
local lua = fennel.compileStream(strm[, options])
```

Accepts `indent` in `options` as per above.

## Compile a data structure (AST) into Lua source code (can throw errors)

The code can be loaded via dostring or other methods. Will error on bad input.

```lua
local lua = fennel.compile(ast[, options])
```

Accepts `indent` in `options` as per above.

## Get an iterator over the bytes in a string

```lua
local stream = fennel.stringStream(str)
```

## Converts an iterator for strings into an iterator over their bytes

Useful for the REPL or reading files in chunks. This will NOT insert
newlines or other whitespace between chunks, so be careful when using
with io.read().  Returns a second function, clearstream, which will
clear the current buffered chunk when called. Useful for implementing
a repl.

```lua
local bytestream, clearstream = fennel.granulate(chunks)
```

## Converts a stream of bytes to a stream of values

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

The `fennel.parser` function takes two optional arguments; a filename
and a table of options. Supported options are both booleans that
default to false:

* `unfriendly`: disable enhanced parse error reporting
* `comments`: include comment nodes in AST

## Work with docstrings and metadata

*(Since 0.3.0)*

When running a REPL or using compile/eval with metadata enabled, each function
declared with `fn` or `λ/lambda` will use the created function as a key on
`fennel.metadata` to store the function's arglist and (if provided) docstring.
The metadata table is weakly-referenced by key, so each function's metadata will
be garbage collected along with the function itself.

You can work with the API to view or modify this metadata yourself, or use the `doc`
macro from fennel to view function documentation.

In addition to direct access to the metadata tables, you can use the following methods:

* `fennel.metadata:get(func, key)`: get a value from a function's metadata
* `fennel.metadata:set(func, key, val)`:  set a metadata value
* `fennel.metadata:setall(func, key1, val1, key2, val2, ...)`: set pairs
* `fennel.doc(func, fnName)`: print formatted documentation for function using name.
  Utilized by the `doc` macro, name is whatever symbol you operate on that's bound to
  the function.

```lua
greet = fennel.eval([[
(λ greet [name] "Say hello" (print (string.format "Hello, %s!" name)))
]], {useMetadata = true})

-- fennel.metadata[greet]
-- > {"fnl/docstring" = "Say hello", "fnl/arglist" = ["name"]}

-- works because greet was set globally above for example purposes only
fennel.eval("(doc greet)", { useMetadata = true })
-- > (greet name)
-- >   Say hello

fennel.metadata:set(greet, "fnl/docstring", "Say hello!!!")
fennel.doc(greet, "greet!")
--> (greet! name)
-->   Say hello!!!
```

### Metadata performance note

Enabling metadata in the compiler/eval/REPL will cause every function to store a new
table containing the function's arglist and docstring in the metadata table, weakly
referenced by the function itself as a key.

This may have a performance impact in some applications due to the extra
allocations and garbage collection associated with dynamic function creation.
The impact hasn't been benchmarked, and may be minimal particularly in luajit,
but enabling metadata is currently recommended for development purposes only
to minimize overhead.

## Load Lua code in a portable way

This isn't Fennel-specific, but the `loadCode` function takes a string
of Lua code along with an optional environment table and filename
string, and returns a function for the loaded code which will run inside
that environment, in a way that's portable across any Lua 5.1+ version.

```lua
local f = fennel.loadCode(luaCode, { x = y }, "myfile.lua")
```

## Plugins

Fennel's plugin system is extremely experimental and exposes internals of
the compiler in ways that no other part of the compiler does. It should be
considered unstable; changes to the compiler in future versions are likely
to break plugins, and each plugin should only be assumed to work with
specific versions of the compiler that they're tested against. The
backwards-compatibility guarantees of the rest of Fennel **do not apply** to
plugins.

Compiler plugins allow the functionality of the compiler to be extended in
various ways. A plugin is a module containing various functions in fields
named after different compiler extension points. When the compiler hits an
extension point, it will call each plugin's function for that extension
point, if provided, with various arguments; usually the AST in question and
the scope table.

* `symbol-to-expression`
* `call`
* `do`
* `fn`
* `destructure`

The `destructure` extension point is different because instead of just
taking `ast` and `scope` it takes a `from` which is the AST for the value
being destructured and a `to` AST which is the AST for the form being
destructured to. This is most commonly a symbol but can be a list or a table.

The `scope` argument is a table containing all the compiler's information
about the current scope. Most of the tables here look up values in their
parent scopes if they do not contain a key.

Plugins can also contain repl commands. If your plugin module has a
field with a name beginning with "repl-command-" then that function
will be available as a comma command from within a repl session. It
will be called with a table for the repl session's environment, a
function which will read the next form from stdin, a function which is
used to print normal values, and one which is used to print errors.

```fennel
(local fennel (require :fennel)
(fn locals [env _read on-values on-error]
  "Print all locals in repl session scope."
  (on-values [(fennel.view env.___replLocals___)]))

{:repl-command-locals locals}
```

```
$ fennel --plugin locals-plugin.fnl
Welcome to Fennel 0.8.0 on Lua 5.4!
Use ,help to see available commands.
>> (local x 4)
nil
>> (local abc :xyz)
nil
>> ,locals
{
  :abc "xyz"
  :x 4
}
```

The docstring of the function will be used as its summary in the
",help" command listing. Unlike other plugin hook fields, only the
first plugin to provide a repl command will be used.

### Activation

Plugins are activated by passing the `--plugin` argument on the command line,
which should be a path to a Fennel file containing a module that has some of
the functions listed above. If you're using the compiler programmatically,
you can include a `:plugins` table in the `options` table to most compiler
entry point functions.

[1]: https://github.com/rxi/lume#lumehotswapmodname
