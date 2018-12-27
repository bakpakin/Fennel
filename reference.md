# Fennel Reference

These are all the special forms recognized by the Fennel compiler. It
does not include built-in Lua functions; see the
[Lua reference manual](https://www.lua.org/manual/5.1/) for that.

## Functions

### `fn` function

Creates a function which binds the arguments given inside the square
brackets. Will accept any number of arguments; ones in excess of the
declared ones are ignored, and if not enough arguments are supplied to
cover the declared ones, the remaining ones are `nil`.

Example: `(fn pxy [x y] (print (+ x y)))`

Giving it a name is optional; if one is provided it will be bound to
it as a local. Even if you don't use it as an anonymous function,
providing a name will cause your stack traces to be more readable, so
it's recommended. Providing a name that's a table field will cause it
to be inserted in a table instead of bound as a local.

### `lambda`/`λ` arity-checked function

Creates a function like `fn` does, but throws an error at runtime if
any of the listed arguments are nil, unless its identifier begins with `?`.

Example: `(lambda [x ?y z] (print (- x (* (or ?y 1) z))))`

The `λ` form is an alias for `lambda` and behaves identically.

### `partial` partial application

Returns a new function which works like its first argument, but fills
the first few arguments in place with the given ones. This is related
to currying but different because calling it will call the underlying
function instead of waiting till it has the "correct" number of args.

Example: `(partial (fn [x y] (print (+ x y))) 2)`

This example returns a function which will print a number that is 2
greater than the argument it is passed.

## Binding

### `let` scoped locals

Introduces a new scope in which a given set of local bindings are used.

Example: `(let [x 89] (print (+ x 12))` -> 101

These locals cannot be changed with `set` but they can be shadowed by
an inner `let` or `local`. Outside the body of the `let`, the bindings
it introduces are no longer visible.

Any time you bind a local, you can destructure it if the value is a
sequential table or a function call which returns multiple values:

Example: `(let [[a b c] [1 2 3]] (+ a b c))` -> `6`

Example: `(let [(x y z) (unpack [10 9 8])] (+ x y z))` -> `27`

### `local` declare local

Introduces a new local inside an existing scope. Similar to `let` but
without a body argument. Recommended for use at the top-level of a
file for locals which will be used throughout the file.

Example: `(local lume (require "lume"))`

Supports destructuring and multiple-value binding.

### `match` pattern matching

Evaluates its first argument, then searches thru the subsequent
pattern/body clauses to find one where the pattern matches the value,
and evaluates the corresponding body. Pattern matching can be thought
of as a combination of destructuring and conditionals.

Example:

```lisp
(match mytable
  59      :will-never-match-hopefully
  [9 q 5] (print :q q)
  [1 a b] (+ a b))
```

In the example above, we have a `mytable` value followed by three
pattern/body clauses. The first clause will only match if `mytable`
is 59. The second clause will match if `mytable` is a table with 9 as
its first element and 5 as its third element; if it matches, then it
evaluates `(print :q q)` with `q` bound to the second element of
`mytable`. The final clause will only match if `mytable` has 1 as its
first element; if so then it will add up the second and third elements.

Patterns can be tables, literal values, or symbols. If a symbol has
already been bound, then the value is checked against the existing
local's value, but if it's a new local then the symbol is bound to the
value. 

Tables can be nested, and they may be either sequential (`[]` style)
or key/value (`{}` style) tables. Sequential tables will match if they
have at least as many elements as the pattern. (To allow an element to
be nil, use a symbol like `?this`.) Tables will never fail to match
due to having too many elements.

```lisp
(match mytable
  {:subtable [a b ?c] :depth depth} (* b depth)
  _ :unknown)
```

You can also match against multiple return values using
parentheses. (These cannot be nested, but they can contain tables.)
This can be useful for error checking.

```lisp
(match (io.open "/some/file")
  (nil msg) (report-error msg)
  f (read-file f))
```

Pattern matching performs unification, meaning that if `x` has an
existing binding, clauses which attempt to bind it to a different
value will not match:

```lisp
(let [x 95]
 (match [52 85 95] 
   [b a a] :no ; because a=85 and a=95
   [x y z] :no ; because x=95 and x=52
   [a b x] :yes)) ; a and b are fresh values while x=95 and x=95
```

There is a special case for `_`; it is never bound and always acts as
a wildcard.

(Note that Lua also has "patterns" which are matched against strings
similar to how regular expressions work in other languages; these are
two distinct concepts with similar names.)

### `global` set global variable

Sets a global variable to a new value. Note that there is no
distinction between introducing a new global and changing the value of
an existing one.

Example: `(global prettyprint (fn [x] (print (view x))))`

Supports destructuring and multiple-value binding.

### `var` declare local variable

Introduces a new local inside an existing scope which may have its
value changed. Identical to `local` apart from allowing `set` to work
on it.

Example: `(var x 83)`

Supports destructuring and multiple-value binding.

### `set` set local variable or table field

Changes the value of a variable introduced with `var`. Will not work
on globals or `let`/`local`-bound locals. Can also be used to change a
field of a table, even if the table is bound with `let` or `local`,
provided the field is given at compile-time.

Example: `(set x (+ x 91))`

Example: `(let [t {:a 4 :b 8}] (set t.a 2) t)` -> `{:a 2 :b 8}`

Supports destructuring and multiple-value binding.

### `tset` set table field

Set the field of a given table to a new value. The field name does not
need to be known at compile-time. Works on any table, even those bound
with `local` and `let`.

Example: `(let [tbl {:d 32} field :d] (tset tbl field 19) tbl)` -> `{:d 19}`

You can provide multiple successive field names to perform nested sets.

### multiple value binding

In any of the above contexts where you can make a new binding, you
can use multiple value binding. Otherwise you will only capture the first
value.

Example: `(let [x (values 1 2 3)] x)` => 1

Example: `(let [(file-handle message code) (io.open "foo.blah")] message)` => "foo.blah: No such file or directory"

Example: `(global (x-m x-e) (math.frexp 21)), {:m x-m :e m-e}` => {:e 5 :m 0.65625}

Example: `(do (local (_ _ z) (unpack [:a :b :c :d :e])), z)` => c

## Flow Control

### `if` conditional

Checks a condition and evaluates a corresponding body. Accepts any
number of condition/body pairs; if an odd number of arguments is
given, the last value is treated as a catch-all "else". Similar to
`cond` in other lisps.

Example:

```
(let [x (math.random 64)]
  (if (= 0 (% x 10))
      "multiple of ten"
      (= 0 (% x 2))
      "even"
      "I dunno, something else"))
```

All values other than nil or false are treated as true.

### `when` single side-effecting conditional

Takes a single condition and evaluates the rest as a body if it's not
nil or false. As it always returns nil; this is intended for side-effects.

Example:

```
(when launch-missiles?
  (power-on)
  (open-doors)
  (fire))
```

### `each` general iteration

Run the body once for each value provided by the iterator. Commonly
used with `ipairs` (for sequential tables) or `pairs` (for any table
in undefined order) but can be used with any iterator.

Example:

```
(each [key value (pairs mytbl)]
  (print key (f value)))
```

Most iterators return two values, but `each` will bind any number.

### `for` numeric loop

Counts a number from a start to stop point (inclusive), evaluating the
body once for each value. Accepts an optional step.

Example:

```
(for [i 1 10 2]
  (print i))
```

This example will print all odd numbers under ten.

### `do` evaluate multiple forms returning last value

Accepts any number of forms and evaluates all of them in order,
returning the last value. This is used for inserting side-effects into
a form which accepts only a single value, such as in a body of an `if`
when multiple clauses make it so you can't use `when`. Some lisps call
this `begin` or `progn`.

```
(if launch-missiles?
    (do
      (power-on)
      (open-doors)
      (fire))
    false-alarm?
    (promote lt-petrov))
```

## Data

### operators

* `and`, `or`, `not` boolean
* `+`, `-`, `*`, `/`, `//`, `%`, `^` arithmetic
* `>`, `<`, `>=`, `<=`, `=`, `~=` comparison

These all work as you would expect, with a few caveats. The `~=`
operator is used for "not equal", and `//` for integer division is
only available in Lua 5.3 and onward.

They all take any number of arguments, as long as that number is fixed
at compile-time. For instance, `(= 2 2 (unpack [2 5]))` will evaluate
to `true` because the compile-time number of values being compared is 3.

Note that these are all special forms which cannot be used as
higher-order functions.

### `..` string concatenation

Concatenates its arguments into one string. Will coerce numbers into
strings, but not other types.

Example: `(.. "Hello" " " "world" 7 "!!!")` -> `"Hello world7!!!"`

### `#` string or table length

Returns the length of a string or table. Note that the length of a
table with gaps in it is undefined; it can return a number
corresponding to any of the table's "boundary" positions between nil
and non-nil values. If a table has nils and you want to know the last
consecutive numeric index starting at 1, you must calculate it
yourself with `ipairs`; if you want to know the maximum numeric key in
a table with nils, you can use `table.maxn`.

Example: `(+ (# [1 2 3 nil 8]) (# "abc"))` -> `6` or `8`

### `.` table lookup

Looks up a given key in a table. Multiple arguments will perform
nested lookup.

Example: `(. mytbl myfield)`

Example: `(let [t {:a [2 3 4]}] (. t :a 2))` -> `3`

Note that if the field name is known at compile time, you don't need
this and can just use `mytbl.field`.

### `:` method call

Looks up a function in a table and calls it with the table as its
first argument. This is a common idiom in many Lua APIs, including
some built-in ones.

Example:

```
(let [f (assert (io.open "hello" "w"))]
  (: f :write "world")
  (: f :close))
```

Equivalent to:

```
(let [f (assert (io.open "hello" "w"))]
  (f.write f "world")
  (f.close f))
```

### `values` multi-valued return

Returns multiple values from a function. Usually used to signal
failure by returning nil followed by a message.

Example:

```
(fn [filename]
  (if (valid-file-name? filename)
      (open-file filename)
      (values nil (.. "Invalid filename: " filename))))
```

### `while` good old while loop

Loops over a body until a condition is met. Uses a native
Lua while loop, so is preferable to a lambda function and tail recursion.

Example:

```
(do
  (var done? false)
  (while (not done?)
    (print :not-done)
    (when (> (math.random) 0.95)
      (set done? true))))
```

## Other

### `->` and `->>` threading macros

The `->` macro takes its first value and splices it into the second
form as the first argument. The result of evaluating the second form
gets spliced into the first argument of the third form, and so on.

Example:

```
(-> 52
    (+ 91 2) ; (+ 52 91 2)
    (- 8)    ; (- (+ 52 91 2) 8)
    (print "is the answer")) ; (print (- (+ 52 91 2) 8) "is the answer")
```

The `->>` macro works the same, except it splices it into the last
position of each form instead of the first.

Note that these have nothing to do with "threads" used for
concurrency; they are named after the thread which is used in
sewing. This is similar to the way that `|>` works in OCaml and Elixir.

### `doto`

Similarly, the `doto` macro splices the first value into subsequent
forms. However, it keeps the same value and continually splices the
same thing in rather than using the value from the previous form for
the next form.

```
(doto (io.open "/tmp/err.log)
  (: :write contents)
  (: :close))

;; equivalent to:
(let [x (io.open "/tmp/err.log")]
  (: x :write contents)
  (: x :close)
  x)
```

The first form becomes the return value for the whole expression, and
subsequent forms are evaluated solely for side-effects.

### `require-macros`

Requires a module and binds its fields locally as macros.

Macros currently must be defined in separate modules. A macro module
exports any number of functions which take forms as arguments at
compile time and emit lists which are fed back into the compiler. For
instance, here is a macro function which implements `when` in terms of
`if` and `do`:

```
(fn [condition body1 ...]
  (assert body1 "expected body")
  (list (sym 'if') condition
        (list (sym 'do') body1 ...)))
```

It constructs a `list` where the first element is the symbol "if", the
second element is the condition passed in, and the third element is a
list with a "do" symbol as its first element and the rest of the body
inside that list. In effect it turns this input:

```
(when (= 3 (+ 2 a)) (print "yes"))
```

into this output:

```
(if (= 3 (+ 2 a)) (do (print "yes")))
```

See "Compiler API" below for details about extra functions and tables
visible inside compiler scope which macros run in. Note that lists are
compile-time concepts that don't typically exist at runtime; they are
implemented as regular tables which have a special metatable to
distinguish them from regular tables defined with square or curly
brackets. Similarly symbols are tables with a string entry for their
name and a metatable that the compiler uses to distinguish them.

Note that the macro interface is still preliminary and is subject to
change over time.

### `eval-compiler`

Evaluate a block of code during compile-time with access to compiler
scope. This gives you a superset of the features you can get with
macros, but you should use macros if you can.

Example:

```
(eval-compiler
  (tset _SPECIALS "local" (. _SPECIALS "global")))
```

### Compiler API

Inside `eval-compiler` blocks or `require-macros` modules, this extra
functionality is visible to your Fennel code:

* `list`
* `sym`
* `list?`
* `sym?`
* `multi-sym?`
* `table?`
* `varg?`

Note that other internals of the compiler exposed in compiler scope are
subject to change.
