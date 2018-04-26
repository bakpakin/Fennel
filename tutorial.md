# Getting Started with Fennel

If you know Lua and a lisp already, you'll feel right at home in
Fennel. Even if not, Lua is one of the simplest programming languages
in existence, so if you've programmed before you should be able to
pick it up without too much trouble, especially if you've used another
dynamic imperative language with closures. The
[Lua reference manual](https://www.lua.org/manual/5.1/) is a fine place to
look for details.

A programming language is made up of **syntax** and **semantics**. The
semantics of Fennel vary only in small ways from Lua (all noted
below). The syntax of Fennel comes from the lisp family of
languages. Lisps have syntax which is very uniform and predictable,
which makes it easier to
[write code that operates on code](http://www.defmacro.org/ramblings/lisp.html)
as well as
[structured editing](http://danmidwood.com/content/2014/11/21/animated-paredit.html).

## OK, so how do you do things?

Globals are set with `global`. Good code doesn't use too many of
these, but they can be nice for debugging and experimentation, so
we'll start there. Note that with `global` there is no distinction
between creating a new global and giving an existing global a new
value. Functions are created with `fn`, using square brackets for
arguments.

```lisp
(global add (fn [x y] (+ x y)))
(add 32 12) ; -> 44
```

Functions defined with `fn` are fast; they have no runtime overhead
compared to Lua. However, they also have no arity checking. (That is,
calling a function with the wrong number of arguments does not cause
an error.) For safer code you can use `lambda`:

```lisp
(global print-calculation
        (lambda [x ?y z] (print (- x (* (or ?y 1) z)))))
(print-calculation 5) ; -> error: Missing argument z
```

Note that the second argument `?y` is allowed to be omitted, but `z` is not.

Locals are introduced using `let` with the names and values wrapped in
a single set of square brackets:

```lisp
(let [x (+ 89 5.2)
      f (fn [abc] (print (* 2 abc)))]
  (f x))
```

Here `x` is bound to the result of adding 89 and 5.2, while `f` is
bound to a function that prints twice its argument. These bindings are
only valid for the body of the `let` call.

You can also introduce locals with `local`, which is nice when they'll
be used across the whole file, but in general `let` is preferred:

```lisp
(local lume (require "lume"))
```

Locals set this way cannot be given new values, but you *can*
introduce new locals that shadow the outer names:

```lisp
(let [x 19]
  ;; (set x 88) <- not allowed!
  (let [x 88]
    (print (+ x 2))) ; -> 90
  (print x)) ; -> 19
```

If you need to change the value of a local, you can use `var` which
works like `local` except it allows `set` to work on it. There is no
nested equivalent of `var`.

```lisp
(var x 19)
(set x (+ x 8))
(print x) ; -> 27
```

### Numbers and strings

Of course, all our standard arithmetic operators like `+`, `-`, `*`,
and `/` work here in prefix form. Note that numbers are
double-precision floats in all versions prior to 5.3, which optionally
introduced integers. On 5.3 and up, integer division uses `//`.

```lisp
(let [x (+ 1 99)
      y (- x 12)]
  (/ y 10))
```

Strings are essentially immutable byte arrays. UTF-8 support is
provided from a
[3rd-party library](https://github.com/Stepets/utf8.lua). Strings are
concatenated with `..`:

```lisp
(.. "hello" " world")
```

### Tables

In Lua (and thus in Fennel), tables are the only data structure. The
main syntax for tables uses curly braces with key/value pairs in them:

```lisp
{"key" value
 "number" 531
 "f" (fn [x] (+ x 2))}
```

Some tables are used to store data that's used sequentially; the keys
in this case are just numbers starting with 1 and going up. Fennel
provides alternate syntax for these tables with square brackets:

```lisp
["abc" "def" "xyz"] ; equivalent to {1 "abc" 2 "def" 3 "xyz"}
```

You can use `.` to get values out of tables:

```lisp
(let [tbl (function-which-returns-a-table)
      key "a certain key"]
  (. tbl key))
```

And `tset` to put them in:

```lisp
(let [tbl {}
      key1 "a long string"
      key2 12]
  (tset tbl key1 "the first value")
  (tset tbl key2 "the second one")
  tbl) ; -> {"a long string" "the first value" 12 "the second one"}
```

The `#` function returns the length of sequential tables and strings:

```lisp
(let [tbl ["abc" "def" "xyz"]]
  (+ (# tbl)
     (# (. tbl 1)))) ; -> 6
```

Note that the length of a table with gaps in it is undefined; it can
return a number corresponding to any of the table's "boundary"
positions between nil and non-nil values.

### Iteration

Looping over table elements is done with `each` and an iterator like
`pairs` (used for general tables) or `ipairs` (for sequential tables):

```lisp
(each [key value (pairs {:key1 52 :key2 99})]
  (print key value))

(each [index value (ipairs ["abc" "def" "xyz"])]
  (print index value))
```

Note that whether a table is sequential or not is not an inherent
property of the table but depends on which iterator is used with it.
You can call `ipairs` on any table, and it will only iterate
over numeric keys starting with 1 until it hits a `nil`.

You can use any Lua iterator with `each`, but these are by far the most common.

The other iteration construct is `for` which iterates numerically from
the provided start value to the inclusive finish value:

```lisp
(for [i 1 10]
  (print i))
```

You can specify an optional step value; this loop will only print odd
numbers under ten:

```lisp
(for [i 1 10 2]
  (print i))
```

### Conditionals

Finally we have conditionals. The `if` form in Fennel can be used the
same way as in other lisp languages, but it can also be used as `cond`
for multiple conditions compiling into `elseif` branches:

```lisp
(let [x (math.random 64)]
  (if (= 0 (% x 2))
      "even"
      (= 0 (% x 10))
      "multiple of ten"
      "I dunno, something else"))
```

Being a lisp, Fennel has no statements, so `if` returns a value as an
expression. Lua programmers will be glad to know there is no need to
construct precarious chains of `and`/`or` just to get a value!

The other conditional is `when`, which is used for an arbitrary number
of side-effects, has no else clause, and always returns `nil`:

```lisp
(when (currently-raining?)
  (wear "boots")
  (deploy-umbrella))
```

## Back to tables just for a bit

Strings that don't have spaces in them can use the `:keyword` syntax
instead, which is often used for table keys:

```lisp
{:key value :number 531}
```

If a table has string keys like this, you can pull values out of it easily:

```lisp
(let [tbl {:x 52 :y 91}]
  (+ tbl.x tbl.y)) ; -> 143
```

You can also use this syntax with `set`:

```lisp
(let [tbl {}]
  (set tbl.one 1)
  (set tbl.two 2)
  tbl) ; -> {:one 1 :two 2}
```

Finally, `let` can destructure a sequential table into multiple locals:

```lisp
(let [f (fn [] ["abc" "def" "xyz"])
      [a d x] (f)]
  (print a)
  (print d)
  (print x))
```

Note that unlike many languages, `nil` in Lua actually represents the
absence of a value, and thus tables cannot contain `nil`. It is an
error to try to use `nil` as a key, and using `nil` as a value removes
whatever entry was at that key before.

## Error handling

Error handling in Lua has two forms. Functions in Lua can return any
number of values, and most functions which can fail will indicate
failure by using multiple return values: `nil` followed by a failure
message string. You can interact with this style of function in Fennel
by destructuring with parens instead of square brackets:

```lisp
(let [(f msg) (io.open "file" "rb")]
  ;; when io.open succeeds, f will be a file, but if it fails f will be
  ;; nil and msg will be the failure string
  (if f
      (do (use-file-contents (f.read f "*all"))
          (f.close f))
      (print "Could not open file: " .. msg)))
```

You can write your own function which returns multiple values with `values`:

```lisp
(global use-file
        (fn [filename]
          (if (valid-file-name? filename)
              (open-file filename)
              (values nil (.. "Invalid filename: " filename)))))
```

If you detect a serious error that needs to be signaled beyond just
the calling function, you can use `error` for that. This will
terminate the whole process unless it's within a protected call,
similar to the way throwing an exception works in many languages. You
can make a protected call with `pcall`:

```lisp
(let [(ok val-or-msg) (pcall potentially-disastrous-call filename)]
  (if ok
      (print "Got value" val-or-msg)
      (print "Could not get value:" val-or-msg)))
```

The `pcall` invocation there is equivalent to running
`(potentially-disastrous-call filename)` in protected mode. It takes
an arbitrary number of arguments which are passed on to the
function. You can see that `pcall` returns a boolean (`ok` here) to
let you know if the call succeeded or not, and a second value
(`val-or-msg`) which is the actual value if it succeeded or an error
message if it didn't.

The `assert` function takes a value and an error message; it calls
`error` if the value is `nil` and returns it otherwise. This can be
used to turn multiple-value failures into errors (kind of the inverse
of `pcall` which turns `error`s into multiple-value failures):

```lisp
(let [f (assert (io.open filename))
      contents (f.read f "*all")]
  (f.close f)
  contents)
```

In this example because `io.open` returns `nil` and an error message
upon failure, a failure will trigger an `error` and halt execution.

## Variadic Functions

Fennel supports variadic functions like most modern languages. The syntax for
taking a variable number of arguments to a function is the `...` symbol, which
must be the last parameter to a function. This syntax is inherited from Lua rather
than Lisp.

The `...` form is not a list or first class value, it expands to multiple values inline.
To access individual elements of the vararg, first wrap it in a table literal (`{...}`)
and index like a normal table, or use the `select` function from Lua's core library. Often,
the vararg can be passed directly to another function such as print without needing to
look at individual elements in the vararg structure.

```lisp
(fn print-each [...]
 (each [i v (ipairs [...])]
  (print (.. "Argument " i " is " v))))

(print-each :a :b :c)
```

```lisp
(fn myprint [prefix ...]
 (io.write prefix)
 (io.write (.. (select "#" ...) " arguments given: "))
 (print ...))

(myprint ":D " :d :e :f)
```

Varargs are scoped differently than other variables as well - they are only accessible to
the function in which they are created. This means that the following code wil NOT work,
as the varargs in the inner function are out of scope.

```lisp
(fn badcode [...]
 (fn []
  (print ...)))
```

## Gotchas

There are a few surprises that might bite seasoned lispers. Most of
these result necessarily from Fennel's insistence upon imposing zero
runtime overhead over Lua.

* The arithmetic and comparison operators are not first-class functions.

* There is no `apply` function; use `unpack` (or `table.unpack`
  depending on your Lua version) instead: `(f 1 3 (unpack [4 9])`.

* Tables are compared for identity, not based on the value of their
  contents, as per [Baker](http://home.pipeline.com/%7Ehbaker1/ObjectIdentity.html).

* Return values in the default repl will get pretty-printed, but
  calling `(print tbl)` will emit output like `table: 0x55a3a8749ef0`.
  If you don't already have one, it's recommended for debugging to
  define a printer function which calls `fennelview` on its argument
  before printing it: `(local view (fennel.dofile "fennelview.fnl"))
  (global pp (fn [x] (print (view x))))`

* Lua's standard library is quite small, and so common functions like
  `map`, `reduce`, and `filter` are absent. It's recommended to pull
  in something like [Lume](https://github.com/rxi/lume) or
  [luafun](https://luafun.github.io/) for those.

* Locals are per-chunk. Normally this means per-file, but you can also
  create chunks with `fennel.eval` or Lua's `loadstring`, etc. One
  common source of confusion is that in repl sessions, each input is
  its own chunk, which makes `local` basically useless. For values to
  persist in a repl session beyond one entry they need to be global.

* Lua programmers should note Fennel functions cannot do early returns.

## Other stuff just works

Note that built-in functions in
[Lua's standard library](https://www.lua.org/manual/5.1/manual.html#5)
like `math.random` above can be called with no fuss and no overhead.

This includes features like coroutines, which are usually implemented
using special syntax in other languages. Coroutines
[let you express non-blocking operations without callbacks](http://leafo.net/posts/itchio-and-coroutines.html).

Tables in Lua may seem a bit limited, but
[metatables](http://nova-fusion.com/2011/06/30/lua-metatables-tutorial/)
allow a great deal more flexibility. All the features of metatables
are accessible from Fennel code just the same as they would be from Lua.

## Modules and multiple files

You can use the `require` function to load code from Lua files.

```lisp
(let [lume (require "lume")
      tbl [52 99 412 654]
      plus (fn [x y] (+ x y))]
  (lume.map tbl (partial plus 2))) ; -> [54 101 414 656]
```

Modules in Lua are simply tables which contain functions and other values.
The last value in a Fennel file will be used as the value of the
module. This is typically a table containing functions, though it
can be any value, like a function.

Out of the box `require` doesn't work with Fennel files, but you can
add an entry to Lua's package searchers to support it:

```lua
table.insert(package.loaders or package.searchers, fennel.searcher)
local mylib = require("mylib") -- will compile and load code in mylib.fnl
```

Fennel has its own search path; `fennel.path` acts the same as
`package.path` but only for requiring Fennel modules.

## Embedding

Lua is most commonly used to embed inside other applications, and
Fennel is no different. The simplest thing to do is include Fennel the
output from `fennel --compile` as part of your overall application's
build process. However, the Fennel compiler is very small, and
including it into your codebase means that you can embed a Fennel repl
inside your application or support reloading from disk, allowing a
much more pleasant interactive development cycle.

Here is an example of embedding the Fennel compiler inside a
[LÖVE](https://love2d.org) game written in Lua to allow live reloads:

```lua
local fennel = require("fennel")
local f = io.open("mycode.fnl", "rb")
;; mycode.fnl ends in a line like this:
;; {:draw (fn [] ...) :update (fn [dt] ...)}
local mycode = fennel.dofile("mycode.fnl")
f:close()

love.update = function(dt)
  mycode.update(dt)
  -- other updates
end

love.draw = function()
  mycode.draw()
  -- other drawing
end

love.keypressed = function(key)
  if(key == "f5") then -- support reloading
    for k,v in pairs(fennel.dofile("mycode.fnl")) do
      mycode[k] = v
    end
  else
    -- other key handling
  end
end

```

You can add `fennel.lua` as a single file to your project, but if you
also add `fennelview.fnl` then when you use a Fennel repl you'll get
results rendered much more nicely. You can use the function returned
by `fennel.dofile("fennelview.fnl")` directly to turn any table into a
fennel-syntax string rendering of that table for debugging.
