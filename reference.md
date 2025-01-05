# Fennel Reference

This document covers the syntax, built-in macros, and special forms
recognized by the Fennel compiler. It does not include built-in Lua
functions; see the [Lua reference manual][1] or the [Lua primer][3]
for that. This is not an introductory text; see the [tutorial][7] for
that. If you already have a piece of Lua code you just want
to see translated to Fennel, use [antifennel][8].

A macro is a function which runs at compile time and transforms some
Fennel code into different Fennel. A special form (or special) is a
primitive construct which emits Lua code directly. When you are
coding, you don't need to care about the difference between built-in
macros and special forms; it is an implementation detail.

Remember that Fennel relies completely on Lua for its runtime.
Everything Fennel does happens at compile-time, so you will need to
familiarize yourself with Lua's standard library functions. Thankfully
it's much smaller than almost any other language.

The one exception to this compile-time rule is the `fennel.view`
function which returns a string representation of any Fennel data
suitable for printing. But this is not part of the language itself; it
is a library function which can be used from Lua just as easily.

Fennel source code should be UTF-8-encoded text.

## Syntax

`(parentheses)`: used to delimit lists, which are primarily used to
denote calls to functions, macros, and specials, but also can be used
in binding contexts to bind to multiple values. Lists are a
compile-time construct; they are not used at runtime. For example:
`(print "hello world")`

`{curly brackets}`: used to denote key/value table literals, also
known as dictionaries. For example: `{:a 1 :b 2}` In a table if you
have a string key followed by a symbol of the same name as the string,
you can use `:` as the key and it will be expanded to a string
containing the name of the following symbol.

```fennel
{: this} ; is shorthand for {:this this}
```

`[square brackets]`: used to denote sequential
tables, which can be used for literal data structures and also in
specials and macros to delimit where new identifiers are introduced,
such as argument lists or let bindings. For example: `[1 2 3]`

The syntax for numbers is the [same as Lua's][6], except that underscores
may be used to separate digits for readability. Non-ASCII digits are
not yet supported. Infinity and negative infinity are represented as
`.inf` and `-.inf`. NaN and negative Nan are `.nan` and `-.nan`.

The syntax for strings uses double-quotes `"` around the
string's contents. Double quotes inside a string must be escaped with
backslashes. The syntax for these is [the same as Lua's][6], except
that strings may contain newline characters. Single-quoted or long
bracket strings are not supported.

Fennel has a lot fewer restrictions on identifiers than Lua.
Identifiers are represented by symbols, but identifiers are not
exactly the same as symbols; some symbols are used by macros for
things other than identifiers. Symbols may not begin with digits or a
colon, but may have digits anywhere else. Beyond that, any unicode characters are
accepted as long as they are not unprintable or whitespace, one of the
delimiter characters mentioned above, one of the a prefix characters
listed below, or one of these reserved characters:

* single quote: `'`
* tilde: `~`
* semicolon: `;`
* at: `@`

Underscores are allowed in identifier names, but dashes are preferred
as word separators. By convention, identifiers starting with
underscores are used to indicate that a local is bound but not meant
to be used.

The ampersand character `&` is allowed in symbols but not in
identifiers. This allows it to be reserved for macros, like the
behavior of `&as` in destructuring.

Symbols that contain a dot `.` or colon `:` are considered
"multi symbols". The part of the symbol before the first dot or colon is
used as an identifier, and the part after the dot or colon is a field
looked up on the local identified. A colon is only allowed before the
final segment of a multi symbol, so `x.y:z` is valid but `a:b.c` is
not. Colon multi symbols can only be used for method calls.

Fennel also supports certain kinds of strings that begin with a colon
as long as they don't contain any characters which wouldn't be allowed
in a symbol, for example `:fennel-lang.org` is another way of writing
the string "fennel-lang.org".

Spaces, tabs, newlines, vertical tabs, form feeds, and carriage
returns are counted as whitespace. Non-ASCII whitespace characters are
not yet supported.

Certain prefixes are expanded by the parser into longhand equivalents:

* `#foo` expands to `(hashfn foo)`
* `` `foo ``   expands to `(quote foo)`
* `,foo` expands to `(unquote foo)`

A semicolon and everything following it up to the end of the line is a
comment.

Expressions (literals and tables) can be ignored by the parser if preceded by `#_` (like in Clojure):

* `[1 #_ {:a :b} 3 #_ #_ (+ 4 5) 6 7 #_]` expands to `[1 3 7]`

`#_`s stack and also don't leak out after the end of the containing table

## Functions

### `fn` function

Creates a function which binds the arguments given inside the square
brackets. Will accept any number of arguments; ones in excess of the
declared ones are ignored, and if not enough arguments are supplied to
cover the declared ones, the remaining ones are given values of `nil`.

Example:

```fennel
(fn pxy [x y]
  (print (+ x y)))
```

Giving it a name is optional; if one is provided it will be bound to
it as a local. The following mean exactly the same thing; the first is
preferred mostly for indentation reasons, but also because it allows
recursion:

```fennel
(fn pxy [x y]
  (print (+ x y)))

(local pxy (fn [x y]
             (print (+ x y))))
```


Providing a name that's a table field will cause it to be inserted in
a table instead of bound as a local:

```fennel
(local functions {})

(fn functions.p [x y z]
  (print (* x (+ y z))))

;; equivalent to:
(set functions.p (fn [x y z]
                   (print (* x (+ y z)))))
```

Like Lua, functions in Fennel support tail-call optimization, allowing
(among other things) functions to recurse indefinitely without overflowing
the stack, provided the call is in a tail position.

The final form in this and all other function forms is used as the
return value.

### `lambda`/`λ` nil-checked function

Creates a function like `fn` does, but throws an error at runtime if
any of the listed arguments are nil, unless its identifier begins with `?`.

Example:

```fennel
(lambda [x ?y z]
  (print (- x (* (or ?y 1) z))))
```

Note that the Lua runtime will fill in missing arguments with nil when
they are not provided by the caller, so an explicit nil argument is no
different than omitting an argument.

Programmers coming from other languages in which it is an error to
call a function with a different number of arguments than it is
defined with often get tripped up by the behavior of `fn`. This is
where `lambda` is most useful.

The `lambda`, `case`, `case-try`, `match` and `match-try` forms are the only
place where the `?foo` notation is used by the compiler to indicate that a nil
value is allowed, but it is a useful notation to communicate intent anywhere a
new local is introduced.

The `λ` form is an alias for `lambda` and behaves identically.

### Docstrings and metadata

The `fn`, `lambda`, `λ` and `macro` forms accept an optional docstring.

```fennel
(fn pxy [x y]
  "Print the sum of x and y"
  (print (+ x y)))

(λ pxyz [x ?y z]
  "Print the sum of x, y, and z. If y is not provided, defaults to 0."
  (print (+ x (or ?y 0) z)))
```

These are ignored by default outside of the REPL, unless metadata
is enabled from the CLI (`---metadata`) or compiler options `{useMetadata=true}`,
in which case they are stored in a metadata table along with the arglist,
enabling viewing function docs via the `doc` macro.

```
;; this only works in the repl
>> ,doc pxy
(pxy x y)
  Print the sum of x and y
```

All function metadata will be garbage collected along with the function itself.
Docstrings and other metadata can also be accessed via functions on the fennel
API with `fennel.doc` and `fennel.metadata`.

*(Since 1.1.0)*

All forms that accept a docstring will also accept a metadata table in
the same place:

```fennel
(fn add [...]
  {:fnl/docstring "Add arbitrary amount of numbers."
   :fnl/arglist [a b & more]}
  (match (values (select :# ...) ...)
    (0) 0
    (1 a) a
    (2 a b) (+ a b)
    (_ a b) (add (+ a b) (select 3 ...))))
```

Here the arglist is overridden by that in the metadata table (note
that the contents of the table are implicitly quoted). Calling `,doc`
command in the REPL prints specified argument list of the next form:

```
>> ,doc add
(add a b & more)
  Add arbitrary amount of numbers.
```

*(Since 1.3.0)*

Arbitrary metadata keys are allowed in the metadata table syntax:

```fennel
(fn foo []
  {:deprecated "v1.9.0"
   :fnl/docstring "*DEPRECATED* use foo2"}
  ;; old way to do stuff
  )

(fn foo2 [x]
  {:added "v2.0.0"
   :fnl/docstring "Incompatible but better version of foo!"}
  ;; do stuff better, now with x!
  x)
```

In this example, the `deprecated` and `added` keys are used to store a
version of a hypothetical library on which the functions were
deprecated or added.  External tooling then can leverage this
information by using Fennel's metadata API:

```
>> (local {: metadata} (require :fennel))
>> (metadata:get foo :deprecated)
"v1.9.0"
>> (metadata:get foo2 :added)
"v2.0.0"
```

Such metadata can be any data literal, including tables, with the only
restriction that there are no side effects. Fennel's lists are
disallowed as metadata values.

*(Since 1.3.1)*

For editing convenience, the metadata table literals are allowed after docstrings:

``` fennel
(fn some-function [x ...]
  "Docstring for some-function."
  {:fnl/arglist [x & xs]
   :other :metadata}
  (let [xs [...]]
    ;; ...
    ))
```

In this case, the documentation string is automatically inserted to
the metadata table by the compiler.

The whole metadata table can be obtained by calling `metadata:get`
without the `key` argument:

```
>> (local {: metadata} (require :fennel))
>> (metadata:get some-function)
{:fnl/arglist ["x" "&" "xs"]
 :fnl/docstring "Docstring for some-function."
 :other "metadata"}
```

Fennel itself only uses the `fnl/docstring` and `fnl/arglist` metadata
keys but third-party code can make use of arbitrary keys.

### Hash function literal shorthand

It's pretty easy to create function literals, but Fennel provides
an even shorter form of functions. Hash functions are anonymous
functions of one form, with implicitly named arguments. All
of the below functions are functionally equivalent:

```fennel
(fn [a b] (+ a b))
```

```fennel
(hashfn (+ $1 $2)) ; implementation detail; don't use directly
```

```fennel
#(+ $1 $2)
```

This style of anonymous function is useful as a parameter to higher
order functions. It's recommended only for simple one-line functions
that get passed as arguments to other functions.

The current implementation only allows for hash functions to use up to
9 arguments, each named `$1` through `$9`, or those with varargs,
delineated by `$...` instead of the usual `...`. A lone `$` in a hash
function is treated as an alias for `$1`.

Hash functions are defined with the `hashfn` macro or special character `#`,
which wraps its single argument in a function literal. For example,

```fennel
#$3               ; same as (fn [x y z] z)
#[$1 $2 $3]       ; same as (fn [a b c] [a b c])
#{:a $1 :b $2}    ; same as (fn [a b] {:a a :b b})
#$                ; same as (fn [x] x) (aka the identity function)
#val              ; same as (fn [] val)
#[:one :two $...] ; same as (fn [...] ["one" "two" ...])
```

Hash arguments can also be used as parts of multisyms. For instance,
`#$.foo` is a function which will return the value of the "foo" key in
its first argument.

Unlike regular functions, there is no implicit `do` in a hash
function, and thus it cannot contain multiple forms without an
explicit `do`. The body itself is directly used as the return value
rather than the last element in the body.

### `partial` partial application

Returns a new function which works like its first argument, but fills
the first few arguments in place with the given ones. This is related
to currying but different because calling it will call the underlying
function instead of waiting till it has the "correct" number of args.

Example:

```fennel
(fn add-print [x y] (print (+ x y)))
(partial add-print 2)
```

This example returns a function which will print a number that is 2
greater than the argument it is passed.


## Binding

### `let` scoped locals

Introduces a new scope in which a given set of local bindings are used.

Example:

```fennel
(let [x 89
      y 198]
  (print (+ x y 12))) ; => 299
```

These locals cannot be changed with `set` but they can be shadowed by
an inner `let` or `local`. Outside the body of the `let`, the bindings
it introduces are no longer visible. The last form in the body is used
as the return value.

Any time you bind a local, you can destructure it if the value is a
table or a function call which returns multiple values:

Example:

```fennel
(let [(x y z) (unpack [10 9 8])]
  (+ x y z)) ; => 27
```

Example:

```fennel
(let [[a b c] [1 2 3]]
  (+ a b c)) ; => 6
```

If a table key is a string with the same name as the local you want to
bind to, you can use shorthand of just `:` for the key name followed
by the local name. This works for both creating tables and destructuring them.

Example:

```fennel
(let [{:msg message : val} {:msg "hello there" :val 19}]
  (print message)
  val) ; prints "hello there" and returns 19
```

When destructuring a sequential table, you can capture all the remainder
of the table in a local by using `&`:

Example:

```fennel
(let [[a b & c] [1 2 3 4 5 6]]
  (table.concat c ",")) ; => "3,4,5,6"
```
*(Since 1.3.0)*: This also works with function argument lists, but it
has a small performance cost, so it's recommended to use `...` instead
in cases that are sensitive to overhead.

When destructuring a non-sequential table, you can capture the
original table along with the destructuring by using `&as`:

Example:

```fennel
(let [{:a a :b b &as all} {:a 1 :b 2 :c 3 :d 4}]
  (+ a b all.c all.d)) ; => 10
```

### `local` declare local

Introduces a new local inside an existing scope. Similar to `let` but
without a body argument. Recommended for use at the top-level of a
file for locals which will be used throughout the file.

Example:

```fennel
(local tau-approx 6.28318)
```

Supports destructuring and multiple-value binding.

### `case` pattern matching

*(Since 1.3.0)*

Evaluates its first argument, then searches thru the subsequent
pattern/body clauses to find one where the pattern matches the value,
and evaluates the corresponding body. Pattern matching can be thought
of as a combination of destructuring and conditionals.

**Note**: Lua also has "patterns" which are matched against strings
similar to how regular expressions work in other languages; these are
two distinct concepts with similar names.

Example:

```fennel
(case mytable
  59      :will-never-match-hopefully
  [9 q 5] (print :q q)
  [1 a b] (+ a b))
```

In the example above, we have a `mytable` value followed by three
pattern/body clauses.

The first clause will only match if `mytable` is 59.

The second clause will match if `mytable` is a table with 9 as its first
element, any non-nil value as its second value and 5 as its third element; if
it matches, then it evaluates `(print :q q)` with `q` bound to the second
element of `mytable`.

The final clause will only match if `mytable` has 1 as its first element and
two non-nil values after it; if so then it will add up the second and third
elements.

If no clause matches, the form evaluates to nil.

Patterns can be tables, literal values, or symbols. Any symbol is implicitly
checked to be not `nil`. Symbols can be repeated in an expression to check for
the same value.

Example:

```fennel
(case mytable
  ;; the first and second values of mytable are not nil and are the same value
  [a a] (* a 2)
  ;; the first and second values are not nil and are not the same value
  [a b] (+ a b))
```

It's important to note that expressions are checked *in order!* In the above
example, since `[a a]` is checked first, we can be confident that when `[a b]`
is checked, the two values must be different. Had the order been reversed,
`[a b]` would always match as long as they're not `nil` - even if they have the
same value!

You may allow a symbol to optionally be `nil` by prefixing it with `?`.

Example:

```fennel
(case mytable
  ;; not-nil, maybe-nil
  [a ?b] :maybe-one-maybe-two-values
  ;; maybe-nil == maybe-nil, both are nil or both are the same value
  [?a ?a] :maybe-none-maybe-two-same-values
  ;; maybe-nil, maybe-nil
  [?a ?b] :maybe-none-maybe-one-maybe-two-values)
```

Symbols prefixed by an `_` are ignored and may stand in as positional
placeholders or markers for "any" value - including a `nil` value. A single `_`
is also often used at the end of a `case` expression to define an "else" style
fall-through value.

Example:

```fennel
(case mytable
  ;; not-nil, anything
  [a _b] :maybe-one-maybe-two-values
  ;; anything, anything (different to the previous ?a example!)
  ;; note this is effectively the same as []
  [_a _a] :maybe-none-maybe-one-maybe-two-values
  ;; anything, anything
  ;; this is identical to [_a _a] and in this example would never actually match.
  [_a _b] :maybe-none-maybe-one-maybe-two-values
  ;; when no other clause matched, in this case any non-table value
  _ :no-match)
```

Tables can be nested, and they may be either sequential (`[]` style) or
key/value (`{}` style) tables. Sequential tables will match if they have at
least as many elements as the pattern. (To allow an element to be nil, see `?`
and `_` as above.) Tables will *never* fail to match due to having too many
elements - this means `[]` matches *any* table, not an *empty* table. You can
use `&` to  capture all the remaining elements of a sequential table, just like
`let`.

```fennel
(case mytable
  {:subtable [a b ?c] :depth depth} (* b depth)
  _ :unknown)
```

You can also match against multiple return values using
parentheses. (These cannot be nested, but they can contain tables.)
This can be useful for error checking.

```fennel
(case (io.open "/some/file")
  (nil msg) (report-error msg)
  f (read-file f))
```

#### Guard Clauses

Sometimes you need to match on something more general than a structure
or specific value. In these cases you can use guard clauses:

```fennel
(case [91 12 53]
  (where [a b c] (= 5 a)) :will-not-match
  (where [a b c] (= 0 (math.fmod (+ a b c) 2)) (= 91 a)) c) ; -> 53
```

In this case the pattern should be wrapped in parentheses (like when
matching against multiple values) but the first thing in the
parentheses is the `where` symbol. Each form after the pattern is a
condition; all the conditions must evaluate to true for that pattern
to match.

If several patterns share the same body and guards, such patterns can
be combined with `or` special in the `where` clause:

```fennel
(case [5 1 2]
  (where (or [a 3 9] [a 1 2]) (= 5 a)) "Either [5 3 9] or [5 1 2]"
  _ "anything else")
```

This is essentially equivalent to:

```fennel
(case [5 1 2]
  (where [a 3 9] (= 5 a)) "Either [5 3 9] or [5 1 2]"
  (where [a 1 2] (= 5 a)) "Either [5 3 9] or [5 1 2]"
  _ "anything else")
```

However, patterns which bind variables should not be combined with
`or` if different variables are bound in different patterns or some
variables are missing:

``` fennel
;; bad
(case [1 2 3]
  ;; Will throw an error because `b' is nil for the first
  ;; pattern but the guard still uses it.
  (where (or [a 1 2] [a b 3]) (< a 0) (< b 1))
  :body)

;; ok
(case [1 2 3]
  (where (or [a b 2] [a b 3]) (< a 0) (<= b 1))
  :body)
```

#### Binding Pinning

Symbols bound inside a `case` pattern are independent from any existing
symbols in the current scope, that is - names may be re-used without
consequence.

Example:

```fennel
(let [x 1]
  (case [:hello]
    ;; `x` is simply bound to the first value of [:hello]
    [x] x)) ; -> :hello
```

Sometimes it may be desirable to match against an existing value in the outer
scope. To do this we can "pin" a binding inside the pattern with an existing
outer binding with the unary `(= binding-name)` form. The unary `(= binding-name)`
form is *only* valid in a `case` pattern and *must* be inside a `(where)`
guard.

Example:

```fennel
(let [x 1]
  (case [:hello]
    ;; 1 != :hello
    (where [(= x)]) x
    _ :no-match)) ; -> no-match

(let [x 1]
  (case [1]
    ;; 1 == 1
    (where [(= x)]) x
    _ :no-match)) ; -> 1

(let [pass :hunter2]
  (case (user-input)
    (where (= pass)) :login
    _ :try-again!))
```

Pinning is only required inside the pattern. Outer bindings are automatically
available inside guards and bodies as long as the name has not been rebound in
the pattern.

**Note:** The `case` macro can be used in place of the `if-let` macro
from Clojure. The reason Fennel doesn't have `if-let` is that `case`
makes it redundant.

### `match` pattern matching

`match` is conceptually equivalent to `case`, except symbols in the patterns are
always pinned with outer-scope symbols if they exist.

It supports all the same syntax as described in `case` except the pin
(`(= binding-name)`) expression, as it is always performed.

> Be careful when using `match` that your symbols are not accidentally the same
> as any existing symbols! If you know you don't intend to pin any existing
> symbols you should use the `case` expression.

```fennel
(let [x 95]
 (match [52 85 95]
   [b a a] :no ; because a=85 and a=95
   [x y z] :no ; because x=95 and x=52
   [a b x] :yes)) ; a and b are fresh values while x=95 and x=95
```

Unlike in `case`, if an existing binding has the value `nil`, the `?` prefix is
not necessary - it would instead create a new un-pinned binding!

Example:

```fennel
(let [name nil
      get-input (fn [] "Dave")]
  (match (get-input)
    ;; name already exists as nil, "Dave" != nil so this *wont* match
    name (.. "Hello " name)
    ?no-input (.. "Hello anonymous"))) ; -> "Hello anonymous"
```

**Note:** Prior to Fennel 0.9.0 the `match` macro used infix `?`
operator to test patterns against the guards. While this syntax is
still supported, `where` should be preferred instead:

``` fennel
(match [1 2 3]
  (where [a 2 3] (< 0 a)) "new guard syntax"
  ([a 2 3] ? (< 0 a)) "obsolete guard syntax")
```

### `case-try` for matching multiple steps

Evaluates a series of pattern matching steps. The value from the first
expression is matched against the first pattern. If it matches, the first
body is evaluated and its value is matched against the second pattern, etc.

If there is a `(catch pat1 body1 pat2 body2 ...)` form at the end, any mismatch
from the steps will be tried against these patterns in sequence as a fallback
just like a normal `case`. If no `catch` pattern matches, nil is returned.

If there is no catch, the mismatched value will be returned as the value of the
entire expression.

```fennel
(fn handle [conn token]
  (case-try (conn:receive :*l)
    input (parse input)
    (command-name params (= token)) (commands.get command-name)
    command (pcall command (table.unpack params))
    (catch
     (_ :timeout) nil
     (_ :closed) (pcall disconnect conn "connection closed")
     (_ msg) (print "Error handling input" msg))))
```

This is useful when you want to perform a series of steps, any of which could
fail. The `catch` clause lets you keep all your error handling in one
place. Note that there are two ways to indicate failure in Fennel and Lua:
using the `assert`/`error` functions or returning nil followed by some data
representing the failure. This form only works on the latter, but you can use
`pcall` to transform `error` calls into values.

### `match-try` for matching multiple steps

Equivalent to `case-try` but uses `match` internally. See `case` and `match`
for details on the differences between these two forms.

Unlike `case-try`, `match-try` will pin values in a given `catch` block with
those in the original steps.

```fennel
(fn handle [conn token]
  (match-try (conn:receive :*l)
    input (parse input)
    (command-name params token) (commands.get command-name)
    command (pcall command (table.unpack params))
    (catch
      (_ :timeout) nil
      (_ :closed) (pcall disconnect conn "connection closed")
      (_ msg) (print "Error handling input" msg))))
```

### `var` declare local variable

Introduces a new local inside an existing scope which may have its
value changed. Identical to `local` apart from allowing `set` to work
on it.

Example:

```fennel
(var x 83)
```


Supports destructuring and multiple-value binding.

### `set` set local variable or table field

Changes the value of a variable introduced with `var`. Will not work
on globals or `let`/`local`-bound locals. Can also be used to change a
field of a table, even if the table is bound with `let` or `local`. If
the table field name is static, use `tbl.field`; if the field name is
dynamic, use `(. tbl field)`.

Examples:

```fennel
(set x (+ x 91)) ; var

(let [t {:a 4 :b 8}] ; static table field
  (set t.a 2) t) ; => {:a 2 :b 8}

(let [t {:supported-chars {:x true}}
      field1 :supported-chars
      field2 :y] ; dynamic table field
  (set (. t field1 field2) true) t) ; => {:supported-chars {:x true :y true}}
```

Supports destructuring and multiple-value binding.


### multiple value binding

In any of the above contexts where you can make a new binding, you
can use multiple value binding. Otherwise you will only capture the first
value.

Example:

```fennel
(let [x (values 1 2 3)]
  x) ; => 1
```

Example:

```fennel
(let [(file-handle message code) (io.open "foo.blah")]
  message) ; => "foo.blah: No such file or directory"
```

Example:

```fennel
(do (local (_ _ z) (unpack [:a :b :c :d :e])) z)  => c
```

### `tset` set table field

Sets the field of a given table to a new value.

Example:

```fennel
(let [tbl {:d 32} field :d]
  (tset tbl field 19) tbl) ; => {:d 19}
```

You can provide multiple successive field names to perform nested
sets. For example:

```fennel
(let [tbl {:a {:b {}}} field :c]
  (tset tbl :a :b field "d") tbl) ; => {:a {:b {:c "d"}}}
```

Since 1.5.0, `tset` is mostly redundant because `set` can be used for
table fields. The main exception is that `tset` works with `doto` and
`set` does not.

### `with-open` bind and auto-close file handles

While Lua will automatically close an open file handle when it's garbage collected,
GC may not run right away; `with-open` ensures handles are closed immediately, error
or no, without boilerplate.

The usage is similar to `let`, except:
- destructuring is disallowed (symbols only on the left-hand side)
- every binding should be a file handle or other value with a `:close` method.

After executing the body, or upon encountering an error, `with-open`
will invoke `(value:close)` on every bound variable before returning the results.

The body is implicitly wrapped in a function and run with `xpcall` so that all bound
handles are closed before it re-raises the error.

Example:

```fennel
;; Basic usage
(with-open [fout (io.open :output.txt :w) fin (io.open :input.txt)]
  (fout:write "Here is some text!\n")
  ((fin:lines))) ; => first line of input.txt

;; This demonstrates that the file will also be closed upon error.
(var fh nil)
(local (ok err)
  (pcall #(with-open [file (io.open :test.txt :w)]
            (set fh file) ; you would normally never do this
            (error :whoops!))))
(io.type fh) ; => "closed file"
[ok err]     ; => [false "<error message and stacktrace>"]
```


### `pick-values` emit exactly n values

Discards all values after the first n when dealing with multi-values (`...`)
and multiple returns. Useful for composing functions that return multiple values
with variadic functions. Expands to a `let` expression that binds and re-emits
exactly n values, e.g.

```fennel
(pick-values 2 (func))
```
expands to
```fennel
(let [(_0_ _1_) (func)] (values _0_ _1_))
```

Example:

```fennel
(pick-values 0 :a :b :c :d :e) ; => nil
[(pick-values 2 (table.unpack [:a :b :c]))] ;-> ["a" "b"]

(fn add [x y ...] (let [sum (+ (or x 0) (or y 0))]
                        (if (= (select :# ...) 0) sum (add sum ...))))

(add (pick-values 2 10 10 10 10)) ; => 20
(->> [1 2 3 4 5] (table.unpack) (pick-values 3) (add)) ; => 6
```

**Note:** If n is greater than the number of values supplied, n values will still be emitted.
This is reflected when using `(select "#" ...)` to count varargs, but tables `[...]`
ignore trailing nils:

```fennel
(select :# (pick-values 5 "one" "two")) ; => 5
[(pick-values 5 "one" "two")]           ; => ["one" "two"]
```
## Flow Control

### `if` conditional

Checks a condition and evaluates a corresponding body. Accepts any
number of condition/body pairs; if an odd number of arguments is
given, the last value is treated as a catch-all "else". Similar to
`cond` in other lisps.

Example:

```fennel
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
nil or false. This is intended for side-effects. The last form in the
body is used as the return value.

Example:

```fennel
(when launch-missiles?
  (power-on)
  (open-doors)
  (fire))
```

### `each` general iteration

Runs the body once for each value provided by the iterator. Commonly
used with `ipairs` (for sequential tables) or `pairs` (for any table
in undefined order) but can be used with any iterator. Returns nil.

Example:

```fennel
(each [key value (pairs mytbl)]
  (print "executing key")
  (print (f value)))
```

Any loop can be terminated early by placing an `&until` clause at the
end of the bindings:

```fennel
(local out [])
(each [_ value (pairs tbl) &until (< max-len (length out))]
  (table.insert out value))
```

**Note:** prior to fennel version 1.2.0, `:until` was used instead of `&until`;
the old syntax is still supported for backwards compatibility.

Most iterators return two values, but `each` will bind any number. See
[Programming in Lua][4] for details about how iterators work.

### `for` numeric loop

Counts a number from a start to stop point (inclusive), evaluating the
body once for each value. Accepts an optional step. Returns nil.

Example:

```fennel
(for [i 1 10 2]
  (log-number i)
  (print i))
```

This example will print all odd numbers under ten.

Like `each`, loops using `for` can also be terminated early with an
`&until` clause. The clause is checked before each iteration of the
body; if it is true at the beginning then the body will not run at all.

```fennel
(var x 0)
(for [i 1 128 &until (maxed-out? x)]
  (set x (+ x i)))
```

### `while` good old while loop

Loops over a body until a condition is met. Uses a native Lua `while`
loop. Returns nil.

Example:

```fennel
(var done? false)
(while (not done?)
  (print :not-done)
  (when (< 0.95 (math.random))
    (set done? true)))
```

### `do` evaluate multiple forms returning last value

Accepts any number of forms and evaluates all of them in order,
returning the last value. This is used for inserting side-effects into
a form which accepts only a single value, such as in a body of an `if`
when multiple clauses make it so you can't use `when`. Some lisps call
this `begin` or `progn`.

```fennel
(if launch-missiles?
    (do
      (power-on)
      (open-doors)
      (fire))
    false-alarm?
    (promote lt-petrov))
```

Some other forms like `fn` and `let` have an implicit `do`.

## Data

### operators

* `and`, `or`, `not`: boolean
* `+`, `-`, `*`, `/`, `//`, `%`, `^`: arithmetic
* `>`, `<`, `>=`, `<=`, `=`, `not=`: comparison
* `lshift`, `rshift`, `band`, `bor`, `bxor`, `bnot`: bitwise operations

These all work as you would expect, with a few caveats. The bitwise operators
are only available in Lua 5.3+, unless you use the `--use-bit-lib` flag or
the `useBitLib` flag in the options table, which lets them be used in
LuaJIT. The integer division operator (`//`) is only available in Lua 5.3+.

They all take any number of arguments, as long as that number is fixed
at compile-time. For instance, `(= 2 2 (unpack [2 5]))` will evaluate
to `true` because the compile-time number of values being compared is 3.
Multiple values at runtime will not be taken into account.

Note that these are all special forms which cannot be used as
higher-order functions.

### `..` string concatenation

Concatenates its arguments into one string. Will coerce numbers into
strings, but not other types.

Example:

```fennel
(.. "Hello" " " "world" 7 "!!!") ; => "Hello world7!!!"
```

String concatenation is subject to the same compile-time limit as the
operators above; it is not aware of multiple values at runtime.

### `length` string or table length

*(Changed in 0.3.0: it was called `#` before.)*

Returns the length of a string or table. Note that the length of a
table with gaps (nils) in it is undefined; it can return a number
corresponding to any of the table's "boundary" positions between nil
and non-nil values. If a table has nils and you want to know the last
consecutive numeric index starting at 1, you must calculate it
yourself with `ipairs`; if you want to know the maximum numeric key in
a table with nils, you can use `table.maxn` on some versions of Lua.

Example:

```fennel
(+ (length [1 2 3 nil 8]) (length "abc")) ; => 6 or 8
```


### `.` table lookup

Looks up a given key in a table. Multiple arguments will perform
nested lookup.

Example:

```fennel
(. mytbl myfield)
```


Example:

```fennel
(let [t {:a [2 3 4]}] (. t :a 2)) ; => 3
```


Note that if the field name is a string known at compile time, you
don't need this and can just use `mytbl.field`.

### Nil-safe `?.` table lookup

Looks up a given key in a table. Multiple arguments will perform
nested lookup. If any of subsequent keys is not present, will
short-circuit to `nil`.

Example:

```fennel
(?. mytbl myfield)
```


Example:

```fennel
(let [t {:a [2 3 4]}] (?. t :a 4 :b)) ; => nil
(let [t {:a [2 3 4 {:b 42}]}] (?. t :a 4 :b)) ; => 42
```

### `icollect`, `collect` table comprehension macros

*(Since 0.8.0)*

The `icollect` macro takes a "iterator binding table" in the format that `each`
takes, and returns a sequential table containing all the values produced by
each iteration of the macro's body. This is similar to how `map` works in
several other languages, but it is a macro, not a function.

If the value is nil, it is omitted from the return table. This is analogous to
`filter` in other languages.

```fennel
(icollect [_ v (ipairs [1 2 3 4 5 6])]
  (if (< 2 v) (* v v)))
;; -> [9 16 25 36]

;; equivalent to:
(let [tbl []]
  (each [_ v (ipairs [1 2 3 4 5 6])]
    (tset tbl (+ (length tbl) 1) (if (< 2 v) (* v v))))
  tbl)
```

The `collect` macro is almost identical, except that the
body should return two things: a key and a value.

```fennel
(collect [k v (pairs {:apple "red" :orange "orange" :lemon "yellow"})]
  (if (not= v "yellow")
      (values (.. "color-" v) k)))
;; -> {:color-orange "orange" :color-red "apple"}

;; equivalent to:
(let [tbl {}]
  (each [k v (pairs {:apple "red" :orange "orange"})]
    (if (not= v "yellow")
      (match (values (.. "color-" v) k)
        (key value) (tset tbl key value))))
  tbl)
```

If the key and value are given directly in the body of `collect` and
not nested in an outer form, then the `values` can be omitted for brevity:

```fennel
(collect [k v (pairs {:a 85 :b 52 :c 621 :d 44})]
  k (* v 5))
```

Like `each` and `for`, the table comprehensions support an `&until`
clause for early termination.

Both `icollect` and `collect` take an `&into` clause which allows you
put your results into an existing table instead of starting with an
empty one:

```fennel
(icollect [_ x (ipairs [2 3]) &into [9]]
  (* x 11))
;; -> [9 22 33]
```

**Note:** Prior to fennel version 1.2.0, `:into` was used instead of `&into`;
the old syntax is still supported for backwards compatibility.


### `accumulate` iterator accumulation

*(Since 0.10.0)*

Runs through an iterator and performs accumulation, similar to `fold`
and `reduce` commonly used in functional programming languages.
Like `collect` and `icollect`, it takes an iterator binding table
and an expression as its arguments. The difference is that in
`accumulate`, the first two items in the binding table are used as
an "accumulator" variable and its initial value.
For each iteration step, it evaluates the given expression and
its value becomes the next accumulator variable.
`accumulate` returns the final value of the accumulator variable.

Example:

```fennel
(accumulate [sum 0
             i n (ipairs [10 20 30 40])]
    (+ sum n)) ; -> 100
```

The `&until` clause is also supported here for early termination.

### `faccumulate` range accumulation
*(Since 1.3.0)*

Identical to accumulate, but instead of taking an iterator and the same bindings
as `each`, it accepts the same bindings as `for` and will iterate the numerical range.
Accepts `&until` just like `for` and `accumulate`.

Example:

```fennel
(faccumulate [n 0 i 1 5] (+ n i)) ; => 15
```

### `fcollect` range comprehension macro

*(Since 1.1.1)*

Similarly to `icollect`, `fcollect` provides a way of building a
sequential table. Unlike `icollect`, instead of an iterator it
traverses a range, as accepted by the `for` special.  The `&into` and
`&until` clauses work the same as in `icollect`.

Example:

```fennel
(fcollect [i 0 10 2]
  (if (> i 2) (* i i)))
;; -> [16 36 64 100]

;; equivalent to:
(let [tbl {}]
  (for [i 0 10 2]
    (if (> i 2)
        (table.insert tbl (* i i))))
  tbl)
```

### `values` multi-valued return

Returns multiple values from a function. Usually used to signal
failure by returning nil followed by a message.

Example:

```fennel
(fn [filename]
  (if (valid-file-name? filename)
      (open-file filename)
      (values nil (.. "Invalid filename: " filename))))
```

## Other

### `:` method call

Looks up a function in a table and calls it with the table as its
first argument. This is a common idiom in many Lua APIs, including
some built-in ones.

Just like Lua, you can perform a method call by calling a function
name where `:` separates the table variable and method name.

Example:

```fennel
(let [f (assert (io.open "hello" "w"))]
  (f:write "world")
  (f:close))
```

In the example above, `f:write` is a single multisym. If the name of
the method or the table containing it isn't fixed, you can use `:`
followed by the table and then the method's name to allow it to be a
dynamic string instead:

Example:

```fennel
(let [f (assert (io.open "hello" "w"))
      method1 :write
      method2 :close]
  (: f method1 "world")
  (: f method2))
```

Both of these examples are equivalent to the following:

```fennel
(let [f (assert (io.open "hello" "w"))]
  (f.write f "world")
  (f.close f))
```

Unlike Lua, there's nothing special about defining functions that get
called this way; typically it is given an extra argument called `self`
but this is just a convention; you can name it anything.

```fennel
(local t {})

(fn t.enable [self]
  (set self.enabled? true))

(t:enable)
```

### `->`, `->>`, `-?>` and `-?>>` threading macros

The `->` macro takes its first value and splices it into the second
form as the first argument. The result of evaluating the second form
gets spliced into the first argument of the third form, and so on.

Example:

```fennel
(-> 52
    (+ 91 2) ; (+ 52 91 2)
    (- 8)    ; (- (+ 52 91 2) 8)
    (print "is the answer")) ; (print (- (+ 52 91 2) 8) "is the answer")
```

The `->>` macro works the same, except it splices it into the last
position of each form instead of the first.

`-?>` and `-?>>`, the thread maybe macros, are similar to `->` & `->>`
but they also do checking after the evaluation of each threaded
form. If the result is false or nil then the threading stops and the result
is returned. `-?>` splices the threaded value as the first argument,
like `->`, and `-?>>` splices it into the last position, like `->>`.

This example shows how to use them to avoid accidentally indexing a
nil value:

```fennel
(-?> {:a {:b {:c 42}}}
     (. :a)
     (. :missing)
     (. :c)) ; -> nil
(-?>> :a
      (. {:a :b})
      (. {:b :missing})
      (. {:c 42})) ; -> nil
```

While `->` and `->>` pass multiple values thru without any trouble,
the checks in `-?>` and `-?>>` prevent the same from happening there
without performance overhead, so these pipelines are limited to a
single value.

> Note that these have nothing to do with "threads" used for
> concurrency; they are named after the thread which is used in
> sewing. This is similar to the way that `|>` works in OCaml and Elixir.

### `doto`

Similarly, the `doto` macro splices the first value into subsequent
forms. However, it keeps the same value and continually splices the
same thing in rather than using the value from the previous form for
the next form.

```fennel
(doto (io.open "/tmp/err.log")
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

### `tail!`

Tail calls will be optimized automatically. However, the `tail!` form
asserts that its argument is called in a tail position. You can use
this when the code depends on tail call optimization; that way if the
code is changed so that the recursive call is no longer in the tail position,
it will cause a compile error instead of overflowing the stack later on
large data sets.

```fennel
(fn process-all [data i]
  (case (process (. data i))
    :done (print "Process completed.")
    :next (process-all data (+ i 1))
    :skip (do (tail! (process-all data (+ i 2)))
;;             ^^^^^ Compile error: Must be in tail position
              (print "Skipped" (+ i 1)))))
```

### `include`

```fennel
(include :my.embedded.module)
```

Loads Fennel/Lua module code at compile time and embeds it in the
compiled output. The module name must resolve to a string literal
during compilation.  The bundled code will be wrapped in a function
invocation in the emitted Lua and set on
`package.preload[modulename]`; a normal `require` is then emitted
where `include` was used to load it on demand as a normal module.

In most cases it's better to use `require` in your code and use the
`requireAsInclude` option in the API documentation and the
`--require-as-include` CLI flag (`fennel --help`) to accomplish this.

The `require` function is not part of Fennel; it comes from
Lua. However, it works to load Fennel code. See the [Modules and
multiple files](tutorial#modules-and-multiple-files) section in the
tutorial and [Programming in Lua][5] for details about `require`.

Starting from version 0.10.0 `include` and hence
`--require-as-include` support semi-dynamic compile-time resolution of
module paths similarly to `import-macros`.  See the [relative
require](tutorial#relative-require) section in the tutorial for more
information.

### `assert-repl`

*(Since 1.4.0)*

Sometimes it's helpful for debugging purposes to drop a repl right
into the middle of your code to see what's really going on. You can
use the `assert-repl` macro to do this:

```fnl
(let [input (get-input)
      value []]
  (fn helper [x]
    (table.insert value (calculate x)))
  (assert-repl (transform helper value) "could not transform"))
```

This works as a drop-in replacement for the built-in `assert` function, but
when the condition is false or nil, instead of an error, it drops into a repl
which has access to all the locals that are in scope (`input`, `value`, and
`helper` in the example above).

Note that this is meant for use in development and will not work with
ahead-of-time compilation unless your build also includes Fennel as a
library.

If you use the `--assert-as-repl` flag when running Fennel, calls to
`assert` will be replaced with `assert-repl` automatically.

**Note:** In Fennel 1.4.0, `assert-repl` accepted an options table for
`fennel.repl` as an optional third argument. This was removed as a bug in
1.4.1, as it broke compatibility with `assert`.

The REPL spawned by `assert-repl` applies the same default options as
`fennel.repl`, which as of Fennel 1.4.1 can be configured from the API. See the
[Fennel API reference](api.md#customize-repl-default-options) for details.

#### Recovering from failed assertions

You can `,return EXPRESSION` from the repl to replace the original
failing condition with a different arbitrary value. Returning false or
nil will trigger a regular `assert` failure.

**Note:** Currently, only a single value can be returned from the REPL this
way. While `,return` can be used to make a failed assertion recover, if the
calling code expects multiple return values, it may cause unspecified
behavior.

## Macros

All forms which introduce macros do so inside the current scope. This
is usually the top level for a given file, but you can introduce
macros into nested scopes as well. Note that macros are a
compile-time construct; they do not exist at runtime. As such macros
cannot be exported at the bottom of a module like functions and other values.

### `import-macros` load macros from a separate module

Loads a module at compile-time and binds its functions as local macros.

A macro module exports any number of functions which take code forms
as arguments at compile time and emit lists which are fed back into
the compiler as code. The module calling `import-macros` gets whatever
functions have been exported to use as macros. For instance, here is a
macro module which implements `when2` in terms of `if` and `do`:

```fennel
(fn when2 [condition body1 & rest-body]
  (assert body1 "expected body")
  `(if ,condition
     (do ,body1 ,(unpack rest-body))))

{:when2 when2}
```

For a full explanation of how this works see [the macro guide](/macros.md).
All forms in Fennel are normal tables you can use `table.insert`,
`ipairs`, destructuring, etc on. The backtick on the third line
creates a template list for the code emitted by the macro, and the
comma serves as "unquote" which splices values into the
template.

Assuming the code above is in the file "my-macros.fnl" then it turns this input:

```fennel
(import-macros {: when2} :my-macros)

(when2 (= 3 (+ 2 a))
  (print "yes")
  (finish-calculation))
```

and transforms it into this code at compile time by splicing the arguments
into the backtick template:

```fennel
(if (= 3 (+ 2 a))
  (do
    (print "yes")
    (finish-calculation)))
```

The `import-macros` macro can take any number of binding/module-name
pairs. It can also bind the entire macro module to a single name
rather than destructuring it. In this case you can use a dot to call
the individual macros inside the module:

```fennel
(import-macros mine :my-macros)

(mine.when2 (= 3 (+ 2 a))
  (print "yes")
  (finish-calculation))
```

Note that all macro code runs at compile time, which happens before
runtime. Locals which are in scope at runtime are not visible during
compile-time. So this code will not work:

```fennel
(local (module-name file-name) ...)
(import-macros mymacros (.. module-name ".macros"))
```

However, this code will work, provided the module in question exists:

```fennel
(import-macros mymacros (.. ... ".macros"))
```

See "Compiler API" below for details about additional functions visible
inside compiler scope which macros run in.

### Macro module searching

By default, Fennel will search for macro modules similarly to how it
searches for normal runtime modules: by walking thru entries on
`fennel.macro-path` and checking the filesystem for matches. However,
in some cases this might not be suitable, for instance if your Fennel
program is packaged in some kind of archive file and the modules do
not exist as distinct files on disk.

To support this case you can add your own searcher function to the
`fennel.macro-searchers` table. For example, assuming `find-in-archive`
is a function which can look up strings from the archive given a path:

```fennel
(local fennel (require :fennel))

(fn my-searcher [module-name]
  (let [filename (.. "src/" module-name ".fnl")]
    (match (find-in-archive filename)
      code (values (partial fennel.eval code {:env :_COMPILER})
                   filename))))

(table.insert fennel.macro-searchers my-searcher)
```

The searcher function should take a module name as a string and return
two values if it can find the macro module: a loader function which will
return the macro table when called, and an optional filename. The
loader function will receive the module name and the filename as arguments.

### `macros` define several macros

Defines a table of macros. Note that inside the macro definitions, you
cannot access variables and bindings from the surrounding code. The
macros are essentially compiled in their own compiler
environment. Again, see the "Compiler API" section for more details
about the functions available here.

```fennel
(macros {:my-max (fn [x y]
                   `(let [x# ,x y# ,y]
                      (if (< x# y#) y# x#)))})

(print (my-max 10 20))
(print (my-max 20 10))
(print (my-max 20 20))
```

### `macro` define a single macro

```fennel
(macro my-max [x y]
  `(let [x# ,x y# ,y]
     (if (< x# y#) y# x#)))
```

If you are only defining a single macro, this is equivalent to the
previous example. The syntax mimics `fn`.

### `macrodebug` print the expansion of a macro

```fennel
(macrodebug (-> abc
                (+ 99)
                (< 0)
                (when (os.exit))))
; -> (if (< (+ abc 99) 0) (do (os.exit)))
```

Call the `macrodebug` macro with a form and it will repeatedly expand
top-level macros in that form and print out the resulting form. Note
that the resulting form will usually not be sensibly indented, so you
might need to copy it and reformat it into something more readable.

Note that this prints at compile-time since `macrodebug` is a macro.

### Macro gotchas

It's easy to make macros which accidentally evaluate their arguments
more than once. This is fine if they are passed literal values, but if
they are passed a form which has side-effects, the result will be unexpected:

```fennel
(var v 1)
(macros {:my-max (fn [x y]
                   `(if (< ,x ,y) ,y ,x))})

(fn f [] (set v (+ v 1)) v)

(print (my-max (f) 2)) ; -> 3 since (f) is called twice in the macro body above
```

In order to prevent [accidental symbol capture][2], you may not bind a
bare symbol inside a backtick as an identifier. Appending a `#` on
the end of the identifier name as above invokes "auto gensym" which
guarantees the local name is unique.

```fennel
(macros {:my-max (fn [x y]
                   `(let [x2 ,x y2 ,y]
                      (if (< x2 y2) y2 x2)))})

(print (my-max 10 20))
; Compile error in 'x2' unknown:?: macro tried to bind x2 without gensym; try x2# instead
```

`macros` is useful for one-off, quick macros, or even some more complicated
macros, but be careful. It may be tempting to try and use some function
you have previously defined,  but if you need such functionality, you
should probably use `import-macros`.

For example, this will not compile in strict mode! Even when it does
allow the macro to be called, it will fail trying to call a global
`my-fn` when the code is run:

```fennel
(fn my-fn [] (print "hi!"))

(macros {:my-max (fn [x y]
                   (my-fn)
                   `(let [x# ,x y# ,y]
                      (if (< x# y#) y# x#)))})
; Compile error in 'my-max': attempt to call global '__fnl_global__my_2dfn' (a nil value)
```

### `eval-compiler`

Evaluate a block of code during compile-time with access to compiler
scope. This gives you a superset of the features you can get with
macros, but you should use macros if you can.

Example:

```fennel
(eval-compiler
  (each [name (pairs _G)]
    (print name)))
```

This prints all the functions available in compiler scope.

### Compiler Environment

Inside `eval-compiler`, `macros`, or `macro` blocks, as well as
`import-macros` modules, the functions listed below are visible to
your code.

* `list` - return a list, which is a special kind of table used for code.
* `sym` - turn a string into a symbol.
* `gensym` - generates a unique symbol for use in macros, accepts an optional prefix string.
* `list?` - is the argument a list? Returns the argument or `false`.
* `sym?` - is the argument a symbol? Returns the argument or `false`.
* `table?` - is the argument a non-list table? Returns the argument or `false`.
* `sequence?` - is the argument a non-list _sequential_ table (created
                  with `[]`, as opposed to `{}`)? Returns the argument or `false`.
* `varg?` - is this a `...` symbol which indicates var args? Returns a special
             table describing the type or `false`.
* `multi-sym?` - a multi-sym is a dotted symbol which refers to a table's
                   field. Returns a table containing each separate symbol, or
                   `false`.
* `comment?` - is the argument a comment? Comments are only included
                 when `opts.comments` is truthy.
* `view` - `fennel.view` table serializer.
* `get-scope` - return the scope table for the current macro call site.

* `assert-compile` - works like `assert` but takes a list/symbol as its third
  argument in order to provide pinpointed error messages.

These functions can be used from within macros only, not from any
`eval-compiler` call:

* `in-scope?` - does the symbol refer to an in-scope local? Returns the symbol or `nil`.
* `macroexpand` - performs macroexpansion on its argument form; returns an AST.

Note that lists are compile-time concepts that don't exist at runtime; they
are implemented as tables which have a special metatable to distinguish them
from regular tables defined with square or curly brackets. Similarly symbols
are tables with a string entry for their name and a marker metatable. You
can use `tostring` to get the name of a symbol.

As of 1.0.0 the compiler will not allow access to the outside world
(`os`, `io`, etc) from macros. The one exception is `print` which is
included for debugging purposes. You can disable this by providing the
command-line argument `--no-compiler-sandbox` or by passing
`{:compiler-env _G}` in the options table when using the compiler
API to get full access.

Please note that the sandbox is not suitable to be used as a robust
security mechanism.  It has not been audited and should not be relied
upon to protect you from running untrusted code.

Note that other internals of the compiler exposed in compiler scope
but not listed above are subject to change.

## `lua` Escape Hatch

There are some cases when you need to emit Lua output from Fennel in
ways that don't match Fennel's semantics. For instance, if you are
porting an algorithm from Lua that uses early returns, you may want
to do the port as literally as possible first, and then come back to
it later to make it idiomatic. You can use the `lua` special form to
accomplish this:

```fennel
(fn find [tbl pred]
  (each [key val (pairs tbl)]
    (when (pred val)
      (lua "return key"))))
```

Lua code inside the string can refer to locals which are in scope;
however note that it must refer to the names after mangling has been
done, because the identifiers must be valid Lua. The Fennel compiler
will change `foo-bar` to `foo_bar` in the Lua output in order for it
to be valid, as well as other transformations. When in doubt, inspect
the compiler output to see what it looks like. For example the
following Fennel code:

```fennel
(local foo-bar 3)
(let [foo-bar :hello]
  (lua "print(foo_bar0 .. \" world\")"))
```

will produce this Lua code:

```lua
local foo_bar = 3
local foo_bar0 = "hello"
print(foo_bar0 .. " world")
return nil
```

Normally in these cases you would want to emit a statement, in which
case you would pass a string of Lua code as the first argument. But
you can also use it to emit an expression if you pass in a string as
the second argument.

Note that this should only be used in exceptional circumstances, and
if you are able to avoid it, you should.

## Deprecated Forms

The `#` form is a deprecated alias for `length`, and `~=` is a
deprecated alias for `not=`, kept for backwards compatibility.

### `require-macros` load macros with less flexibility

*(Deprecated in 0.4.0)*

The `require-macros` form is like `import-macros`, except it imports
all macros without making it clear what new identifiers are brought
into scope. It is strongly recommended to use `import-macros` instead.

### `pick-args` create a function of fixed arity

*(Deprecated 0.10.0)*

Like `pick-values`, but takes an integer `n` and a function/operator
`f`, and creates a new function that applies exactly `n` arguments to `f`.

### `global` set global variable

*(Deprecated in 1.1.0)*

Sets a global variable to a new value. Note that there is no
distinction between introducing a new global and changing the value of
an existing one. This supports destructuring and multiple-value binding.

Example:

```fennel
(global prettyprint (fn [x] (print (fennel.view x))))
```

Using `global` adds the identifier in question to the list of allowed
globals so that referring to it later on will not cause a compiler error.
However, globals are also available in the `_G` table, and accessing
them that way instead is recommended for clarity.

### Rest destructuring metamethod

*(Deprecated in 1.4.1, will be removed in future versions)*

If a table implements `__fennelrest` metamethod it is used to capture the
remainder of the table. It can be used with custom data structures
implemented in terms of tables, which wish to provide custom rest
destructuring. The metamethod receives the table as the first
argument, and the amount of values it needs to drop from the beginning
of the table, much like table.unpack

Example:

```fennel
(local t [1 2 3 4 5 6])
(setmetatable
 t
 {:__fennelrest (fn [t k]
                  (let [res {}]
                    (for [i k (length t)]
                      (tset res (tostring (. t i)) (. t i)))
                  res))})
(let [[a b & c] t]
  c) ;; => {:3 3 :4 4 :5 5 :6 6}
```

[1]: https://www.lua.org/manual/5.1/
[2]: https://gist.github.com/nimaai/2f98cc421c9a51930e16#variable-capture
[3]: https://fennel-lang.org/lua-primer
[4]: https://www.lua.org/pil/7.1.html
[5]: https://www.lua.org/pil/8.1.html
[6]: https://www.lua.org/manual/5.4/manual.html#3.1
[7]: https://fennel-lang.org/tutorial
[8]: https://fennel-lang.org/see
