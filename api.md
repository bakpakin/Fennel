# Fennel's Lua API

The `fennel` module provides the following functions for use when
embedding Fennel in a Lua program. If you're writing a pure Fennel
program or working on a system that already has Fennel support, you
probably don't need this.

Only the `fennel` module is part of the public API. The other modules are
implementation details subject to change. Most functions will `error` upon
failure.

Any time a function takes an `options` table argument, that table will
usually accept these fields:

* `allowedGlobals`: a sequential table of strings of the names of globals which
  the compiler will allow references to. Set to false to disable checks.
  Defaults to the contents of the `env` table, if provided, or the
  current environment.
* `correlate`: when this is set, Fennel attempts to emit Lua where the line
  numbers match up with the Fennel input code; useful for situation where code
  that isn't under your control will print the stack traces. This is meant
  as a debugging aid and cannot give exact numbers in all cases.
* `useMetadata`: enables or disables [metadata](#work-with-docstrings-and-metadata),
  allowing use of the `,doc` repl command. Intended for development purposes
  (see [performance note](#metadata-performance-note)); defaults to
  true for REPL only.
* `requireAsInclude`: Alias any static `require` calls to the
  `include` special, embedding the module code inline in the compiled
  output. If the module name isn't a string literal that is resolvable at
  compile time it falls back to `require` at runtime. Can be used to embed both
  Fennel and Lua modules.
* `toBeClosed`: Use Lua 5.4+ to-be-closed variables when compiling
  `with-open` in order to avoid interfering with traces.
* `assertAsRepl`: Replace calls to `assert` with `assert-repl` to
  allow for interactive debugging.
* `lambdaAsFn`: Replace `lambda` function definitions with `fn`.
* `env`: an environment table in which to run the code; see the Lua manual.
* `compilerEnv`: an environment table in which to run compiler-scoped code
  for macro definitions and `eval-compiler` calls. Internal Fennel functions
  such as `list`, `sym`, etc. will be exposed in addition to this table.
  Defaults to a table containing limited known-safe globals. Pass `_G` to
  disable sandboxing.
* `unfriendly`: disable friendly compiler/parser error messages.
* `plugins`: list of compiler [plugins](#plugins).
* `error-pinpoint`: a list of two strings indicating what to wrap compile errors in
* `keywords`: a table of the form `{:keyword1 true :keyword2 true}` containing
  symbols that should be treated as reserved Lua keywords.
* `global-mangle`: whether to mangle globals in compiler output; set to `false`
  to turn global references that aren't valid Lua into `_G['hello-world']`.

You can pass the string `"_COMPILER"` as the value for `env`; it will
cause the code to be run/compiled in a context which has all
compiler-scoped values available. This can be useful for macro modules
or compiler plugins. If you want to add additional values to the
environment in this case, you can use the `extra-env` key. You can also
use `extra-compiler-env` to add fields to the compiler environment used
for macros.

Note that only the `fennel` module is part of the public API. The
other modules (`fennel.utils`, `fennel.compiler`, etc) should be
considered compiler internals subject to change.

If you are embedding Fennel in a context where ANSI escape codes are
not interpreted, you can set `error-pinpoint` to `false` to disable
the highlighting of compiler and parse errors.

## Start a configurable repl

```lua
fennel.repl([options])
```

Takes these additional options:

* `readChunk(state)`: a function that when called, returns a line of code to
  run. This can be an incomplete expression, in which case it will be called
  again until a complete expression can be constructed. The state argument is
  a table with a `stack-size` field which will be zero unless it's reading a
  continuation of previous input. Strings returned should end in newlines. It
  should return nil when there is no more source, which will exit the repl.
* `onValues(values)`: a function which is called for every evaluation with a
  sequence table containing string representations of each of the values
  resulting from the input.
* `onError(errType, err, luaSource)`: a function that will be called on each
  error. `errType` is a string with the type of error: 'parse', 'compile',
  'runtime', or 'lua'. `err` is the error message, and `luaSource` is the
  source of the generated lua code.
* `pp(x)`: a pretty-printer function to apply on values (default: `fennel.view`).
* `view-opts`: an options table passed to `pp` (default: `{:depth 4}`).
* `rawValues(...)`: a function which is passed the raw values from
  evaluation; like `onValues` but receives the underlying data rather than
  the string representation.

Note that overriding `readChunk`/`onValues` will only affect input and output
initiated by the repl directly. If the repl runs code that calls `print`,
`io.write`, `io.read`, etc, those will still use stdio unless overridden in
`env`.

By default, metadata will be enabled and you can view function signatures and
docstrings with the `,doc` command in the REPL.

In Fennel 1.4.1 `fennel.repl` was changed from a normal function to a
callable table. This mostly behaves the same, but it can cause problems with
certain functions that are very picky about functions. Unfortunately this
includes `coroutine.create`. You can pass `fennel.repl.repl` instead.

### Customize REPL default options

Any fields set on `fennel.repl`, which is actually a table with a `__call`
metamethod rather than a function, will used as a fallback for any options
passed to `fennel.repl` or `assert-repl` before defaults are applied,
allowing one to customize the default behavior of `(fennel.repl)`:

```lua
fennel.repl.onError = custom_error_handler

function_that_calls_assert_repl_somewhere()

-- In rare cases this needs to be temporary, overrides
-- can be cleared by simply clearing the entire table
for k in pairs(fennel.repl) do
  fennel.repl[k] = nil
end
```

## Evaluate a string of Fennel

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

Additional arguments beyond `options` are passed to the code and
available as `...`.

## Use Lua's built-in require function

```lua
require("fennel").install().dofile("main.fnl")
```

This is the equivalent of this code:

```lua
local fennel = require("fennel")
table.insert(package.loaders or package.searchers, fennel.searcher)
fennel.dofile("main.fnl") -- require calls in main.fnl can load fennel modules
```

Normally Lua's `require` function only loads modules written in Lua,
but you can install `fennel.searcher` into `package.searchers` (or in
Lua 5.1 `package.loaders`) to teach it how to load Fennel code.

If you would rather change some of the options you can use
`fennel.makeSearcher(options)` to get a searcher function that's
equivalent to `fennel.searcher` but overrides the default `options`
table. You can provide a `path` field to set `fennel.path`.

The `require` function is different from `fennel.dofile` in that it
searches the directories in `fennel.path` for `.fnl` files matching
the module name, and also in that it caches the loaded value to return
on subsequent calls, while `fennel.dofile` will reload each time. The
behavior of `fennel.path` mirrors that of Lua's `package.path`. There is
also a `fennel.macro-path` which is used to look up macro modules.

If you install Fennel into `package.searchers` then you can use the repl's
`,reload mod` command to reload modules that have been loaded with `require`.

## Macro Searchers

The compiler sandbox makes it so that the module system is also
isolated from the rest of the system, so the above `require` calls
will not work from inside macros. However, there is a separate
`fennel.macro-searchers` table which can be used to allow different
modules to be loaded inside macros. By default it includes a searcher
to load sandboxed Fennel modules and a searcher to load sandboxed Lua
modules, but if you disable the compiler sandbox you may want to
replace these with searchers which can load arbitrary modules.

The default `fennel.macro-searchers` functions also cannot load C modules.
Here's an example of some code which would allow that to work:

```lua
table.insert(fennel["macro-searchers"], function(module_name)
  local filename = fennel["search-module"](module_name, package.cpath)
  if filename then
    local func = "luaopen_" .. module_name
    return function() return package.loadlib(filename, func) end, filename
  end
end)
```

Macro searchers store loaded macro modules in the `fennel.macro-loaded`
table which works the same as `package.loaded` but for macro modules.

## Get Fennel-aware stack information

The `fennel.traceback` function works like Lua's `debug.traceback`
function, except it tracks line numbers from Fennel code correctly.

If you are working on an application written in Fennel, you can
override the default traceback function to replace it with Fennel's:

```lua
debug.traceback = fennel.traceback
```

Note that some systems print stack traces from C, which will not be affected.

The `fennel.getinfo` function works like Lua's `debug.getinfo`
function, except it tracks line numbers from Fennel code correctly.
Functions defined from Fennel will have the `what` field set to
`"Fennel"` instead of `"Lua"`.

```lua
local mymodule = require("module")
print(fennel.getinfo(mymodule.func1).linedefined)
```

## Compile Fennel code to Lua

### Compile a file, AST, or byte iterator

```lua
local lua = fennel.compile(fennelSource[, options])
```

The first argument here can be a file, an AST (usually produced by
`fennel.parser`), or a stateful iterator function of bytes.

Unlike the other functions, the `compile` functions default to
performing no global checks, though you can pass in an
`allowedGlobals` table in `options` to enable it. Accepts `filename`
in `options` like `fennel.eval` for error reporting purposes.

### Compile a string of Fennel code

```lua
local lua = fennel.compileString(fennelcode[, options])
```

Also aliased to `fennel.compile-string` for convenience calling from Fennel.

## Parse text into AST nodes

The `fennel.parser` function returns a function which you can call
repeatedly to get successive AST nodes from a string. This happens to
be an iterator function, so you can use it with Lua's `for` or
Fennel's `each`. If a form was successfully read, it returns true
followed by the AST node.  Returns nil when it reaches the end. Raises
an error if it can't parse the input.

```lua
local parse = fennel.parser(text)
local ok, ast = assert(parse()) -- just get the first form

-- Or use in a for loop
for ok, ast in parse do
  if ok then
    print(fennel.view(ast))
  end
end
```

The first argument can either be a string or a function that returns
one byte at a time. It takes two optional arguments; a filename
and a table of options. Supported options are both booleans that
default to false:

* `unfriendly`: disable enhanced parse error reporting
* `comments`: include comment nodes in AST
* `plugins`: *(since 1.2.0)* An optional list of compiler [plugins](#plugins).

The list of common options at the top of this document do not apply here.

## AST node definition

The AST returned by the parser consists of data structures
representing the code. Passing AST nodes to the `fennel.view` function
will give you a string which should round-trip thru the parser to give
you the same data back. The same is true with `tostring`, except it
does not work with non-sequence tables.

The `fennel.ast-source` function takes an AST node and returns a table
with source data around filename, line number, et in it, if
possible. Some AST nodes cannot provide this data, for instance
numbers, strings, and booleans, or symbols constructed within macros
using the `sym` function instead of backtick.

AST nodes can be any of these types:

### list

A list represents a call to function/macro, or destructuring multiple
return values in a binding context. It's represented as a table which
can be identified using the `fennel.list?` predicate function or
constructed using `fennel.list` which takes any number of arguments
for the contents of the list.

Note that lists are compile-time constructs in Fennel. They do not exist at
runtime, except in such cases as the compiler is in use at runtime.

The list also contains these keys indicating where it was defined: `filename`,
`line`, `col`, `endcol`, `bytestart`, and `byteend`. This data is used for
stack traces and for pinpointing compiler error messages. Note that column
numbers are based on character count, which does not always correspond to
visual columns; for instance "วัด" is three characters but only two visual
columns.

### sequence/key-value table

These are table literals in Fennel code produced by square brackets
(sequences) or curly brackets (k/v tables). Sequences can be identified
using the `fennel.sequence?` function and constructed using
`fennel.sequence`. There is no predicate or constructor for k/v tables;
any table which is not one of the other types is assumed to be one of
these.

At runtime there is no difference between sequences and k/v tables
which use monotonically increasing integer keys, but the parser is
able to distinguish between them to improve error reporting.

Sequences and k/v tables have their source data in `filename`, `line`,
etc keys of their metatable. The metatable for k/v tables also includes
a `keys` sequence which tells you which order the keys appeared
originally, since k/v tables are unordered and there would otherwise be
no way to reconstruct this information.

### symbol

Symbols typically represent identifiers in Fennel code. Symbols can be
identified with `fennel.sym?` and constructed with `fennel.sym` which
takes a string name as its first argument and a source data table as
the second. Symbols are represented as tables which store their source
data (`filename`, `line`, `col`, etc) in fields on themselves. Unlike
the other tables in the AST, they do not represent collections; they
are used as scalar types.

Symbols can refer not just directly to locals, but also to table
references like `tbl.x` for field lookup or `access.channel:deny` for
method invocation. The `fennel.multi-sym?` function will return a
table containing the segments if the symbol if it is one of these, or
nil otherwise.

**Note:** `nil` is not a valid AST; code that references nil will have
the symbol named `"nil"` which unfortunately prints in a way that is
visually indistinguishable from actual `nil`.

The `fennel.sym-char?` function will tell you if a given character is
allowed to be used in the name of a symbol.

### vararg

This is a special type of symbol-like construct (`...`) indicating
functions using a variable number of arguments. Its meaning is the
same as in Lua. It's identified with `fennel.varg?` and constructed
with `fennel.varg`.

### number/string/boolean

These are literal types defined by Lua. They cannot carry source data.

### comment

By default, ASTs will omit comments. However, when the `:comment`
field is set in the parser options, comments will be included in the
parsed values. They are identified using `fennel.comment?` and
constructed using the `fennel.comment` function. They are represented
as tables that have source data as fields inside them.

In most data contexts, comments just get included inline in a list or
sequence. However, in a k/v table, this cannot be done, because k/v
tables must have balanced key/value pairs, and including comments
inline would imbalance these or cause keys to be considered as values
and vice versa. So the comments are stored on the `comments` field of
metatable instead, keyed by the key or value they were attached to.

## Search the path for a module without loading it

```lua
print(fennel.searchModule("my.mod", package.path))
```

If you just want to find the file path that a module would resolve to
without actually loading it, you can use `fennel.searchModule`. The
first argument is the module name, and the second argument is the path
string to search. If none is provided, it defaults to Fennel's own path.

Returns `nil` if the module is not found on the path.

## Serialization (view)

The `fennel.view` function takes any Fennel data and turns it into a
representation suitable for feeding back to Fennel's parser. In addition to
tables, strings, numbers, and booleans, it can produce reasonable output from
ASTs that come from the parser. It will emit an unreadable placeholder for
coroutines, compiled functions, and userdata, which cannot be understood by the
parser.

```lua
print(fennel.view({abc=123}[, options])
{:abc 123}
```

The list of common options at the top of this document do not apply here;
instead these options are accepted:

* `one-line?` (default: false) keep the output string as a one-liner
* `depth` (number, default: 128) limit how many levels to go
* `detect-cycles?` (default: true) don't try to traverse a looping table
* `metamethod?` (default: true) use the __fennelview metamethod if found
* `empty-as-sequence?` (default: false) render empty tables as []
* `line-length` (number, default: 80) length of the line at which
  multi-line output for tables is forced
* `byte-escape` (function) If present, overrides default behavior of escaping special
characters in decimal format (e.g. `<ESC>` -> `\027`). Called with the signature
`(byte-escape byte view-opts)`, where byte is the char code for a special character
* `escape-newlines?` (default: false) emit strings with \\n instead of newline
* `prefer-colon?` (default: false) emit strings in colon notation when possible
* `utf8?` (default: true) whether to use utf8 module to compute string lengths
* `max-sparse-gap` (number, default: 1) maximum gap to fill in with nils in
  sparse sequential tables before switching to curly brackets.
* `preprocess` (function) if present, called on x (and recursively on each value
  in x), and the result is used for pretty printing; takes the same arguments as
  `fennel.view`

All options can be set to `{:once some-value}` to force their value to be
`some-value` but only for the current level. After that, such option is reset
to its default value.  Alternatively, `{:once value :after other-value}` can
be used, with the difference that after first use, the options will be set to
`other-value` instead of the default value.

You can set a `__fennelview` metamethod on a table to override its
serialization behavior. It should take the table being serialized as its first
argument, a function as its second argument, options table as third argument,
and current amount of indentation as its last argument:

    (fn [t view options indent] ...)

`view` function contains a pretty printer that can be used to serialize
elements stored within the table being serialized. If your metamethod produces
indented representation, you should pass `indent` parameter to `view` increased
by the amount of additional indentation you've introduced. This function has
the same interface as `__fennelview` metamethod, but in addition accepts
`colon-string?` as last argument. If `colon?` is `true`, strings will be printed
as colon-strings when possible, and if its value is `false`, strings will be
always printed in double quotes. If omitted or `nil` will default to value of
`:prefer-colon?` option.

`options` table contains options described above, and also `visible-cycle?`
function, that takes a table being serialized, detects and saves information
about possible reachable cycle.  Should be used in `__fennelview` to implement
cycle detection.

`__fennelview` metamethod should always return a table of correctly indented
lines when producing multi-line output, or a string when always returning
single-line item.  `fennel.view` will transform your data structure to correct
multi-line representation when needed.  There's no need to concatenate table
manually ever - `fennel.view` will apply general rules for your data structure,
depending on current options.  By default multiline output is produced only when
inner data structures contains newlines, or when returning table of lines as
single line results in width greater than `line-size` option.

Multi-line representation can be forced by returning two values from
`__fennelview` - a table of indented lines as first value, and `true` as second
value, indicating that multi-line representation should be forced.

There's no need to incorporate indentation beyond needed to correctly align
elements within the printed representation of your data structure.  For example,
if you want to print a multi-line table, like this:

```
@my-table[1
          2
          3]
```

`__fennelview` should return a sequence of lines:

```
["@my-table[1"
 "          2"
 "          3]"]
```

Note, since we've introduced inner indent string of length 10, when calling
`view` function from within `__fennelview` metamethod, in order to keep inner
tables indented correctly, `indent` must be increased by this amount of extra
indentation.

Here's an implementation of such pretty-printer for an arbitrary sequential
table:

```fennel
(fn pp-doc-example [t view options indent]
  (let [lines (icollect [i v (ipairs t)]
                (let [v (view v options (+ 10 indent))]
                  (if (= i 1) v
                      (.. "          " v))))]
    (doto lines
      (tset 1 (.. "@my-table[" (or (. lines 1) "")))
      (tset (length lines) (.. (. lines (length lines)) "]")))))
```

Setting table's `__fennelview` metamethod to this function will provide correct
results regardless of nesting:

```
>> {:my-table (setmetatable [[1 2 3 4 5]
                             {:smalls [6 7 8 9 10 11 12]
                              :bigs [500 1000 2000 3000 4000]}]
                            {:__fennelview pp-doc-example})
    :normal-table [{:c [1 2 3] :d :some-data} 4]}
{:my-table @my-table[[1 2 3 4 5]
                     {:bigs [500 1000 2000 3000 4000]
                      :smalls [6 7 8 9 10 11 12]}]
 :normal-table [{:c [1 2 3] :d "some-data"} 4]}
```

Note that even though we've only indented inner elements of our table with 10
spaces, the result is correctly indented in terms of outer table, and inner
tables also remain indented correctly.

When using the `:preprocess` option or `__fennelview` method, avoid modifying
any tables in-place in the passed function. Since Lua tables are mutable and
passed in without copying, any modification done in these functions will be
visible outside of `fennel.view`.

Using `:byte-escape` to override the special character escape format is
intended for use-cases where it's known that the output will be consumed by
something other than Lua/Fennel, and may result in output that Fennel can no
longer parse. For example, to force the use of hex escapes:

```fennel
(print (fennel.view {:clear-screen "\027[H\027[2J"}
                    {:byte-escape #(: "\\x%2x" :format $)}))
;; > {:clear-screen "\x1b[H\x1b[2J"}
```

While Lua 5.2+ supports hex escapes, PUC Lua 5.1 does not, so compiling this
with Fennel later would result in an incorrect escape code in Lua 5.1.


## Work with docstrings and metadata

When running a REPL or using compile/eval with metadata enabled, each function
declared with `fn` or `λ/lambda` will use the created function as a key on
`fennel.metadata` to store the function's arglist and (if provided) docstring.
The metadata table is weakly-referenced by key, so each function's metadata will
be garbage collected along with the function itself.

You can work with the API to view or modify this metadata yourself, or use the
`,doc` repl command to view function documentation.

In addition to direct access to the metadata tables, you can use the following methods:

* `fennel.metadata:get(func, key)`: get a value from a function's metadata
* `fennel.metadata:set(func, key, val)`:  set a metadata value
* `fennel.metadata:setall(func, key1, val1, key2, val2, ...)`: set pairs
* `fennel.doc(func, fnName)`: print formatted documentation for function using
  name.  Utilized by the `,doc` command, name is whatever symbol you operate
  on that's bound to the function.

```lua
local greet = fennel.eval('(λ greet [name] "Say hello" (print "Hello," name))',
                          {useMetadata = true})

fennel.metadata[greet]
-- > {"fnl/docstring" = "Say hello", "fnl/arglist" = ["name"]}

fennel.doc(greet, "greet")
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
The impact hasn't been benchmarked, but enabling metadata is currently
recommended for development purposes only.

## Describe Fennel syntax

If you're writing a tool which performs syntax highlighting or some other
operations on Fennel code, the `fennel.syntax` function can provide you with
data about what forms and keywords to treat specially.

```lua
local syntax = fennel.syntax()
print(fennel.view(syntax["icollect"]))
--> {:binding-form? true :body-form? true :macro? true}
```

The table has string keys and table values. Each entry will have one of
`"macro?"`, `"global?"`, or `"special?"` set to `true` indicating what type
it is. Globals can also have `"function?"` set to true. Macros and specials
can have `"binding-form?"` set to true indicating it accepts a `[]` argument
which introduces new locals, and/or a `"body-form?"` indicating whether it
should be indented with two spaces instead of being indented like a function
call. They can also have a `"define?"` key indicating whether it introduces a
new top-level identifier like `local` or `fn`.

## Load Lua code in a portable way

This isn't Fennel-specific, but the `loadCode` function takes a string
of Lua code along with an optional environment table and filename
string, and returns a function for the loaded code which will run inside
that environment, in a way that's portable across any Lua 5.1+ version.

```lua
local f = fennel.loadCode(luaCode, { x = y }, "myfile.lua")
```

## Detect Lua VM runtime version

This function does a best effort detection of the Lua VM environment
hosting Fennel. Useful for displaying an "About" dialog in your
Fennel app that matches the REPL and `--version` CLI flag.

```fennel
(fennel.runtime-version)
```

```lua
print(fennel.runtimeVersion())
-- > Fennel 1.0.0 on PUC Lua 5.4
```

The `fennel.version` field will give you the version of just Fennel itself.

*(since 1.3.1)*

If an optional argument is given, returns version information as a
table:

```fennel
(fennel.runtime-version :as-table)
;; > {:fennel "1.3.1" :lua "PUC Lua 5.4"}
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
the scope table. Each plugin function should normally do side effects and
return nil or error out. If a function returns non-nil, it will cause
the rest of the plugins for a given event to be skipped.

* `symbol-to-expression`
* `call`
* `do`
* `fn`
* `destructure`
* `parse-error`
* `assert-compile`

The `destructure` extension point is different because instead of just
taking `ast` and `scope` it takes a `from` which is the AST for the value
being destructured and a `to` AST which is the AST for the form being
destructured to. This is most commonly a symbol but can be a list or a table.

The `parse-error` and `assert-compile` hooks can be used to override how fennel
behaves down to the parser and compiler levels. Possible use-cases
include building atop `fennel.view` to serialize data with
[EDN](https://clojure.github.io/clojure/clojure.edn-api.html)-style tagging,
or manipulating external s-expression-based syntax, such as
[tree-sitter queries](https://tree-sitter.github.io/tree-sitter/using-parsers#query-syntax).

The `scope` argument is a table containing all the compiler's information
about the current scope. Most of the tables here look up values in their
parent scopes if they do not contain a key.

Plugins can also contain repl commands. If your plugin module has a
field with a name beginning with "repl-command-" then that function
will be available as a comma command from within a repl session. It
will be called with a table for the repl session's environment, a
function which will read the next form from stdin (ignoring newlines
and other whitespace), a function which is used to print normal
values, and one which is used to print errors.

```fennel
(local fennel (require :fennel)
(fn locals [env read on-values on-error scope chars opts]
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

Your plugin should contain a `:versions` field which either contains a
list of strings indicating every version of Fennel which you have
tested it with, or a string containing a pattern which is checked
against Fennel's version with `string.find`.  If your plugin is used
with a version of Fennel that doesn't match `:versions` it will emit a
warning. You should also have a `:name` field with the plugin's name.
