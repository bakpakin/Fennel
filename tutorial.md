# Getting Started with Fennel

A programming language is made up of **syntax** and **semantics**. The
semantics of Fennel vary only in small ways from Lua (all noted
below). The syntax of Fennel comes from the lisp family of
languages. Lisps have syntax which is very uniform and predictable,
which makes it easier to [write code that operates on code][1] as well as
[structured editing][2].

If you know Lua and a lisp already, you'll feel right at home in Fennel. Even
if not, Lua is one of the simplest programming languages in existence, so if
you've programmed before you should be able to pick it up without too much
trouble, especially if you've used another dynamic imperative language with
closures. The [Lua reference manual][3] is a fine place to look for details,
but Fennel's own [Lua Primer][14] is shorter and covers the highlights.

If you've already got some Lua example code and you just want to see how it
would look in Fennel, you can learn a lot from putting it in [antifennel][19].

## OK, so how do you do things?

### Functions and lambdas

Use `fn` to make functions. If you provide an optional name, the
function will be bound to that name in local scope; otherwise it is
simply an anonymous value.

> A brief note on naming: identifiers are typically lowercase
> separated by dashes (aka "kebab-case"). They may contain digits too,
> as long as they're not at the start. You can also use the question mark
> (typically for functions that return a true or false, ex., `at-max-velocity?`).
> Underscores (`_`) are often used to name a variable that we don't plan
> on using.

The argument list is provided in square brackets. The final value in
the body is returned.

(If you've never used a lisp before, the main thing to note is that
the function or macro being called goes *inside* the parens, not
outside.)

```fennel
(fn print-and-add [a b c]
  (print a)
  (+ b c))
```

Functions can take an optional docstring in the form of a string that
immediately follows the argument list. Under normal compilation, this is
removed from the emitted Lua, but during development in the REPL the
docstring and function usage can be viewed with the `,doc` command:

```fennel
(fn print-sep [sep ...]
  "Prints args as a string, delimited by sep"
  (print (table.concat [...] sep)))
,doc print-sep ; -> outputs:
;; (print-sep sep ...)
;;   Prints args as a string, delimited by sep
```

Like other lisps, Fennel uses semicolons for comments.

Functions defined with `fn` are fast; they have no runtime overhead
compared to Lua. However, they also have no arity checking. (That is,
calling a function with the wrong number of arguments does not cause
an error.) For safer code you can use `lambda` which ensures you will
get at least as many arguments as you define, unless you signify that
one may be omitted by beginning its name with a `?`:

```fennel
(lambda print-calculation [x ?y z]
  (print (- x (* (or ?y 1) z))))

(print-calculation 5) ; -> error: Missing argument z
```

Note that the second argument `?y` is allowed to be `nil`, but `z` is not:

```fennel
(print-calculation 5 nil 3) ; -> 2
```

Like `fn`, lambdas accept an optional docstring after the argument list.

### Locals and variables

Locals are introduced using `let` with the names and values wrapped in
a single set of square brackets:

```fennel
(let [x (+ 89 5.2)
      f (fn [abc] (print (* 2 abc)))]
  (f x))
```

Here `x` is bound to the result of adding 89 and 5.2, while `f` is
bound to a function that prints twice its argument. These bindings are
only valid inside the body of the `let` call.

You can also introduce locals with `local`, which is nice when they'll
be used across the whole file, but in general `let` is preferred
inside functions because it's clearer at a glance where the value can 
be used:

```fennel
(local tau-approx 6.28318)
```

Locals set this way cannot be given new values, but you *can*
introduce new locals that shadow the outer names:

```fennel
(let [x 19]
  ;; (set x 88) <- not allowed!
  (let [x 88]
    (print (+ x 2))) ; -> 90
  (print x)) ; -> 19
```

If you need to change the value of a local, you can use `var` which
works like `local` except it allows `set` to work on it. There is no
nested `let`-like equivalent of `var`.

```fennel
(var x 19)
(set x (+ x 8))
(print x) ; -> 27
```

### Numbers and strings

Of course, all our standard arithmetic operators like `+`, `-`, `*`, and `/`
work here in prefix form. Note that numbers are double-precision floats in all
Lua versions prior to 5.3, which introduced integers. On 5.3 and
up, integer division uses `//` and bitwise operations use `lshift`, `rshift`,
`bor`, `band`, `bnot` and `xor`. Bitwise operators and integer division will
not work if the host Lua environment is older than version 5.3.

You may also use underscores to separate sections of long numbers. The
underscores have no effect on the value.

```fennel
(let [x (+ 1 99)
      y (- x 12)
      z 100_000]
  (+ z (/ y 10)))
```

Strings are essentially immutable byte arrays. UTF-8 support is
provided in the `utf8` table in [Lua 5.3+][15] or from a
[3rd-party library][4] in earlier versions. Strings are concatenated with `..`:

```fennel
(.. "hello" " world")
```

### Tables

In Lua (and thus in Fennel), tables are the only data structure. The
main syntax for tables uses curly braces with key/value pairs in them:

```fennel
{"key" value
 "number" 531
 "f" (fn [x] (+ x 2))}
```

You can use `.` to get values out of tables:

```fennel
(let [tbl (function-which-returns-a-table)
      key "a certain key"]
  (. tbl key))
```

And `tset` to put them in:

```fennel
(let [tbl {}
      key1 "a long string"
      key2 12]
  (tset tbl key1 "the first value")
  (tset tbl key2 "the second one")
  tbl) ; -> {"a long string" "the first value" 12 "the second one"}
```

### Sequential Tables

Some tables are used to store data that's used sequentially; the keys
in this case are just numbers starting with 1 and going up. Fennel
provides alternate syntax for these tables with square brackets:

```fennel
["abc" "def" "xyz"] ; equivalent to {1 "abc" 2 "def" 3 "xyz"}
```

Lua's built-in `table.insert` function is meant to be used with sequential
tables; all values after the inserted value are shifted up by one index:
If you don't provide an index to `table.insert` it will append to the end
of the table.

The `table.remove` function works similarly; it takes a table and an index
(which defaults to the end of the table) and removes the value at that
index, returning it.

```fennel
(local ltrs ["a" "b" "c" "d"])

(table.remove ltrs)       ; Removes "d"
(table.remove ltrs 1)     ; Removes "a"
(table.insert ltrs "d")   ; Appends "d"
(table.insert ltrs 1 "a") ; Prepends "a"

(. ltrs 2)                ; -> "b"
;; ltrs is back to its original value ["a" "b" "c" "d"]
```

The `length` form returns the length of sequential tables and strings:

```fennel
(let [tbl ["abc" "def" "xyz"]]
  (+ (length tbl)
     (length (. tbl 1)))) ; -> 6
```

Note that the length of a table with gaps in it is undefined; it can
return a number corresponding to any of the table's "boundary"
positions between nil and non-nil values.

Lua's standard library is very small, and thus several functions you
might expect to be included, such `map`, `reduce`, and `filter` are
absent. In Fennel macros are used for this instead; see `icollect`,
`collect`, and `accumulate`.

### Iteration

Looping over table elements is done with `each` and an iterator like
`pairs` (used for general tables) or `ipairs` (for sequential tables):

```fennel
(each [key value (pairs {"key1" 52 "key2" 99})]
  (print key value))

(each [index value (ipairs ["abc" "def" "xyz"])]
  (print index value))
```

Note that whether a table is sequential or not is not an inherent
property of the table but depends on which iterator is used with it.
You can call `ipairs` on any table, and it will only iterate
over numeric keys starting with 1 until it hits a `nil`.

You can use any [Lua iterator][6] with `each`, but these are the most
common. Here's an example that walks through [matches in a string][7]:

```fennel
(var sum 0)
(each [digits (string.gmatch "244 127 163" "%d+")]
  (set sum (+ sum (tonumber digits))))
```

If you want to get a table back, try `icollect` to get a sequential
table or `collect` to get a key/value one. A body which returns nil
will cause that to be omitted from the resulting table.

```fennel
(icollect [_ s (ipairs [:greetings :my :darling])]
  (if (not= :my s)
      (s:upper)))
;; -> ["GREETINGS" "DARLING"]

(collect [_ s (ipairs [:greetings :my :darling])]
  s (length s))
;; -> {:darling 7 :greetings 9 :my 2}
```

A lower-level iteration construct is `for` which iterates numerically from
the provided start value to the inclusive finish value:

```fennel
(for [i 1 10]
  (print i))
```

You can specify an optional step value; this loop will only print odd
numbers under ten:

```fennel
(for [i 1 10 2]
  (print i))
```

### Looping

If you need to loop but don't know how many times, you can use `while`:

```fennel
(while (keep-looping?)
  (do-something))
```

### Conditionals

Finally we have conditionals. The `if` form in Fennel can be used the
same way as in other lisp languages, but it can also be used as `cond`
for multiple conditions compiling into `elseif` branches:

```fennel
(let [x (math.random 64)]
  (if (= 0 (% x 2))
      "even"
      (= 0 (% x 9))
      "multiple of nine"
      "I dunno, something else"))
```

With an odd number of arguments, the final clause is interpreted as "else".

Being a lisp, Fennel has no statements, so `if` returns a value as an
expression. Lua programmers will be glad to know there is no need to
construct precarious chains of `and`/`or` just to get a value!

The other conditional is `when`, which is used for an arbitrary number
of side-effects and has no else clause:

```fennel
(when (currently-raining?)
  (wear "boots")
  (deploy-umbrella))
```

## Back to tables just for a bit

Strings that don't have spaces or reserved characters in them can use
the `:shorthand` syntax instead, which is often used for table keys:

```fennel
{:key value :number 531}
```

If a table has string keys like this, you can pull values out of it
easily with a dot if the keys are known up front:

```fennel
(let [tbl {:x 52 :y 91}]
  (+ tbl.x tbl.y)) ; -> 143
```

You can also use this syntax with `set`:

```fennel
(let [tbl {}]
  (set tbl.one 1)
  (set tbl.two 2)
  tbl) ; -> {:one 1 :two 2}
```

If a table key has the same name as the variable you're setting it to,
you can omit the key name and use `:` instead:

```fennel
(let [one 1 two 2
      tbl {: one : two}]
  tbl) ; -> {:one 1 :two 2}
```

Finally, `let` can destructure a table into multiple locals.

There is positional destructuring:

```fennel
(let [data [1 2 3]
      [fst snd thrd] data]
  (print fst snd thrd)) ; -> 1       2       3
```

And destructuring of tables via key:

```fennel
(let [pos {:x 23 :y 42}
      {:x x-pos :y y-pos} pos]
  (print x-pos y-pos)) ; -> 23      42
```

As above, if a table key has the same name as the variable you're
destructuring it to, you can omit the key name and use `:` instead:

```fennel
(let [pos {:x 23 :y 42}
      {: x : y} pos]
  (print x y)) ; -> 23      42
```

This can nest and mix and match:

```fennel
(let [f (fn [] ["abc" "def" {:x "xyz" :y "abc"}])
      [a d {:x x : y}] (f)]
  (print a d)
  (print x y))
```

If the size of the table doesn't match the number of binding locals,
missing values are filled with `nil` and extra values are discarded.
Note that unlike many languages, `nil` in Lua actually represents the
absence of a value, and thus tables cannot contain `nil`. It is an
error to try to use `nil` as a key, and using `nil` as a value removes
whatever entry was at that key before.

## Error handling

Errors in Lua have two forms they can take. Functions in Lua can
return any number of values, and most functions which can fail will
indicate failure by using two return values: `nil` followed by a
failure message string. You can interact with this style of function
in Fennel by destructuring with parens instead of square brackets:

```fennel
(case (io.open "file")
  ;; when io.open succeeds, it will return a file, but if it fails
  ;; it will return nil and an err-msg string describing why
  f (do (use-file-contents (f:read :*all))
        (f:close))
  (nil err-msg) (print "Could not open file:" err-msg))
```

You can write your own function which returns multiple values with `values`.

```fennel
(fn use-file [filename]
  (if (valid-file-name? filename)
      (open-file filename)
      (values nil (.. "Invalid filename: " filename))))
```

**Note**: while errors are the most common reason to return multiple values
from a function, it can be used in other cases as well. This is
the most complex thing about Lua, and a full discussion is out of
scope for this tutorial, but it's [covered well elsewhere][18].

The problem with this type of error is that it does not compose well;
the error status must be propagated all the way along the call chain
from inner to outer. To address this, you can use `error`. This will
terminate the whole process unless it's within a protected call,
similar to the way in other languages where throwing an exception will
stop the program unless it is within a try/catch. You can make a
protected call with `pcall`:

```fennel
(let [(ok? val-or-msg) (pcall potentially-disastrous-call filename)]
  (if ok?
      (print "Got value" val-or-msg)
      (print "Could not get value:" val-or-msg)))
```

The `pcall` invocation there means you are running
`(potentially-disastrous-call filename)` in protected mode. `pcall` takes
an arbitrary number of arguments which are passed on to the
function. You can see that `pcall` returns a boolean (`ok?` here) to
let you know if the call succeeded or not, and a second value
(`val-or-msg`) which is the actual value if it succeeded or an error
message if it didn't.

The `assert` function takes a value and an error message; it calls
`error` if the value is `nil` and returns it otherwise. This can be
used to turn multiple-value failures into errors (kind of the inverse
of `pcall` which turns `error`s into multiple-value failures):

```fennel
(let [f (assert (io.open filename))
      contents (f.read f "*all")]
  (f.close f)
  contents)
```

In this example because `io.open` returns `nil` and an error message
upon failure, a failure will trigger an `error` and halt execution.

## Variadic Functions

Fennel supports variadic functions (in other words, functions which
take any number of arguments) like many languages. The syntax for taking
a variable number of arguments to a function is the `...` symbol, which
must be the last parameter to a function. This syntax is inherited from Lua rather
than Lisp.

The `...` form is not a list or first class value, it expands to multiple values
inline.  To access individual elements of the vararg, you can
destructure with parentheses, or first wrap it in a table
literal (`[...]`) and index like a normal table, or use the `select` function
from Lua's core library. Often, the vararg can be passed directly to another
function such as `print` without needing to bind it.

```fennel
(fn print-each [...]
  (each [i v (ipairs [...])]
    (print (.. "Argument " i " is " v))))

(print-each :a :b :c)
```

```fennel
(fn myprint [prefix ...]
  (io.write prefix)
  (io.write (.. (select "#" ...) " arguments given: "))
  (print ...))

(myprint ":D " :d :e :f)
```

Varargs are scoped differently than other variables as well - they are
only accessible to the function in which they are created. Unlike
normal values, functions cannot close over them. This means that the
following code will NOT work, as the varargs in the inner function are
out of scope.

```fennel
(fn badcode [...]
  (fn []
    (print ...)))
```


## Strict global checking

If you get an error that says `unknown global in strict mode` it means that
you're trying compile code that uses a global which the Fennel compiler doesn't
know about. Most of the time, this is due to a coding mistake. However, in some
cases you may get this error with a legitimate global reference. If this
happens, it may be due to an inherent limitation of Fennel's strategy. You can
use `_G.myglobal` to refer to it in a way that works around this check
and calls attention to the fact that this is in fact a global.

Another possible cause for this error is a modified [function environment][16].
The solution depends on how you're using Fennel:

* Embedded Fennel can have its searcher modified to ignore certain (or all)
  globals via the `allowedGlobals` parameter. See the [Lua API][17] page for
  instructions.
* Fennel's CLI has the `--globals` parameter, which accepts a comma-separated
  list of globals to ignore. For example, to disable strict mode for globals
  x, y, and z:
  ```shell
  fennel --globals x,y,z yourfennelscript.fnl
  ```

## Gotchas

There are a few surprises that might bite seasoned lispers. Most of
these result necessarily from Fennel's insistence upon imposing zero
runtime overhead over Lua.

* The arithmetic, comparison, and boolean operators are not
  first-class functions. They can behave in surprising ways with
  multiple-return-valued functions, because the number of arguments to
  them must be known at compile-time.

* There is no `apply` function; instead use `table.unpack` or `unpack`
  depending on your Lua version: `(f 1 3 (table.unpack [4 9]))`.

* Tables are compared for equality by identity, not based on the value of
  their contents, as per [Baker][8].

* Return values in the repl will get pretty-printed, but
  calling `(print tbl)` will emit output like `table: 0x55a3a8749ef0`.
  If you don't already have one, it's recommended for debugging to
  define a printer function which calls `fennel.view` on its argument
  before printing it: `(local fennel (require :fennel))
  (fn _G.pp [x] (print (fennel.view x)))`. If you add this definition
  to your `~/.fennelrc` file it will be available in the standard repl.

* Lua programmers should note Fennel functions cannot do early returns.

## Other stuff just works

Note that built-in functions in [Lua's standard library][10] like `math.random`
above can be called with no fuss and no overhead.

This includes features like coroutines, which are often implemented
using special syntax in other languages. Coroutines
[let you express non-blocking operations without callbacks][11].

Tables in Lua may seem a bit limited, but [metatables][12] allow a great deal
more flexibility. All the features of metatables are accessible from Fennel
code just the same as they would be from Lua.

## Modules and multiple files

You can use the `require` function to load code from other files.

```fennel
(let [lume (require :lume)
      tbl [52 99 412 654]
      plus (fn [x y] (+ x y))]
  (lume.map tbl (partial plus 2))) ; -> [54 101 414 656]
```

Modules in Fennel and Lua are simply tables which contain functions
and other values.  The last value in a Fennel file will be used as the
value of the whole module. Technically this can be any value, not just a
table, but using a table is most common for good reason.

To require a module that's in a subdirectory, take the file name,
replace the slashes with dots, and remove the extension, then pass
that to `require`. For instance, a file called `lib/ui/menu.lua` would
be read when loading the module `lib.ui.menu`.

When you run your program with the `fennel` command, you can call
`require` to load Fennel or Lua modules. But in other contexts (such
as compiling to Lua and then using the `lua` command, or in programs
that embed Lua) it will not know about Fennel modules. You need to
install the searcher that knows how to find `.fnl` files:

```lua
require("fennel").install()
local mylib = require("mylib") -- will compile and load code in mylib.fnl
```

Once you add this, `require` will work on Fennel files just like it
does with Lua; for instance `(require :mylib.parser)` will look in
"mylib/parser.fnl" on Fennel's search path (stored in `fennel.path`
which is distinct from `package.path` used to find Lua modules). The
path usually includes an entry to let you load things relative to the
current directory by default.

## Relative require

There are several ways to write a library which uses modules.  One of
these is to rely on something like LuaRocks, to manage library
installation and availability of it and its modules.  Another way is
to use the relative require style for loading nested modules.  With
relative require, libraries don't depend on the root directory name or
its location when resolving inner module paths.

For example, here's a small `example` library, which contains an
`init.fnl` file, and a module at the root directory:

```fennel
;; file example/init.fnl:
(local a (require :example.module-a))

{:hello-a a.hello}
```

Here, the main module requires additional `example.module-a` module,
which holds the implementation:

```fennel
;; file example/module-a.fnl
(fn hello [] (print "hello from a"))
{:hello hello}
```

The main issue here is that the path to the library must be exactly
`example`, e.g. library must be required as `(require :example)` for
it to work, which can't be enforced on the library user.  For example,
if the library were moved into `libs` directory of the project to
avoid cluttering, and required as `(require :libs.example)`, there
will be a runtime error.  This happens because library itself will try
to require `:example.module-a` and not `:libs.example.module-a`, which
is now the correct module path:

    runtime error: module 'example.module-a' not found:
            no field package.preload['example.module-a']
            ...
            no file './example/module-a.lua'
            ...
    stack traceback:
      [C]: in function 'require'
      ./libs/example/init.fnl:2: in main chunk

LuaRocks addresses this problem by enforcing both the directory name
and installation path, populating the `LUA_PATH` environment variable
to make the library available.  This, of course, can be done manually
by setting `LUA_PATH` per project in the build pipeline, pointing it
to the right directory.  But this is not very transparent, and when
requiring a project local library it's better to see the full path,
that directly maps to the project's file structure, rather than
looking up where the `LUA_PATH` is modified.

In the Fennel ecosystem we encourage a simpler way of managing project
dependencies.  Simply dropping a library into your project's tree or
using git submodule is usually enough, and the require paths should be
handled by the library itself.

Here's how a relative require path can be specified in the
`libs/example/init.fnl` to make it name/path agnostic, assuming that
we've moved our `example` library there:

```fennel
;; file libs/example/init.fnl:
(local a (require (.. ... :.module-a)))

{:hello-a a.hello}
```

Now, it doesn't matter how library is named or where we put it - we
can require it from anywhere.  It works because when requiring the
library with `(require :lib.example)`, the first value in `...` will
hold the `"lib.example"` string.  This string is then concatenated
with the `".module-a"`, and `require` will properly find and load the
nested module at runtime under the `"lib.example.module-a"` path.
It's a Lua feature, and not something Fennel specific, and it will
work the same when the library is AOT compiled to Lua.

### Compile-time relative include

Since Fennel v0.10.0 this also works at compile-time, when using the
`include` special or the `--require-as-include` flag, with the
constraint that the expression can be computed at compile time.  This
means that the expression must be self-contained, i.e. doesn't refer
to locals or globals, but embeds all values directly.  In other words,
the following code will only work at runtime, but not with `include`
or `--require-as-include` because `current-module` is not known at
compile time:

```fennel
(local current-module ...)
(require (.. current-module :.other-module))
```

This, on the other hand, will work both at runtime and at compile
time:

```fennel
(require (.. ... :.other-module))
```

The `...` module args are propagated during compilation, so when the
application which uses this library is compiled, all library code is
correctly included into the self-contained Lua file.

Compiling a project that uses this `example` library with
`--require-as-include` will include the following section in the
resulting Lua code:

```lua
package.preload["libs.example.module-a"] = package.preload["libs.example.module-a"] or function(...)
  local function hello()
    return print("hello from a")
  end
  return {hello = hello}
end
```

Note that the `package.preload` entry contains a fully qualified path
`"libs.example.module-a"`, which was resolved at compile time.

### Requiring modules from modules other than `init.fnl`

To require a module from a module other than `init` module, we must
keep the path up to the current module, but remove the module name.  For
example, let's add a `greet` module in `libs/example/utils/greet.fnl`,
and require it from `libs/example/module-a.fnl`:

```fennel
;; file libs/example/utils/greet.fnl:
(fn greet [who] (print (.. "hello " who)))
```

This module can be required as follows:

```fennel
;; file libs/example/module-a.fnl
(local greet (require (.. (: ... :match "(.+)%.[^.]+") :.utils.greet)))

(fn hello [] (print "hello from a"))

{:hello hello :greet greet}
```

The parent module name is determined via calling the `match` method on the
current module name string (`...`).

[1]: https://stopa.io/post/265
[2]: http://danmidwood.com/content/2014/11/21/animated-paredit.html
[3]: https://www.lua.org/manual/5.4/
[4]: https://github.com/Stepets/utf8.lua
[6]: https://www.lua.org/pil/7.1.html
[7]: https://www.lua.org/manual/5.4/manual.html#pdf-string.gmatch
[8]: https://p.hagelb.org/equal-rights-for-functional-objects.html
[10]: https://www.lua.org/manual/5.4/manual.html#6
[11]: https://leafo.net/posts/itchio-and-coroutines.html
[12]: https://www.lua.org/pil/13.html
[13]: https://love2d.org
[14]: https://fennel-lang.org/lua-primer
[15]: https://www.lua.org/manual/5.3/manual.html#6.5
[16]: https://www.lua.org/pil/14.3.html
[17]: https://fennel-lang.org/api
[18]: https://benaiah.me/posts/everything-you-didnt-want-to-know-about-lua-multivals/
[19]: https://fennel-lang.org/see
