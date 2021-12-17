# Style Guide

Style is a tricky thing to define. The purpose of this style guide is to
provide advice for how to write code that is clear and concise. Its advice is
a starting point rather than a set of universal rules. Broad strokes don't
apply to every situation, so use your judgement and be aware of context.

Fennel is a language in the long tradition of lisp languages going back to
the 1950s. While it breaks from tradition in many key ways, much of the
formatting rules and naming conventions for code follow the same precedent
used by Common Lispers, Schemers, and Clojure programmers for decades.

Fennel is also a language whose semantics follow Lua, which means closures
and tables are *everything*. Understanding how to do a lot with very simple
semantics is key to writing effective Fennel.

TODO: more examples throughout the guide.

## Parentheses

The actual delimiter characters are simply lexical tokens to which little
significance should be assigned.  Lisp programmers do not examine the
delimiters individually, or, Azathoth forbid, count delimiters; instead they
view the higher-level structures expressed in the program, especially as
presented by the indentation.

Lisp is not about writing a sequence of serial instructions; it is about
building complex tree structures by summing parts.  The composition of
complex structures from parts is the focus of Lisp programs, and it should be
readily apparent from the Lisp code.  Placing delimiters haphazardly about
the presentation is jarring to a Lisp programmer, who otherwise would not
even have seen them for the most part.

### Spacing

Use spaces to indent rather than tabs. Do not leave trailing whitespace at
the end of a line. Use unix line endings and avoid carriage return
characters.

If any text precedes an opening delimiter or follows a closing delimiter,
separate that text from that delimiter with a space.  Conversely, leave no
space after an opening delimiter and before following text, or after
preceding text and before a closing delimiter.

```fennel
;; Don't:
(foo(bar baz)quux)
(foo ( bar baz ) quux)

;; Do:
(foo (bar baz) quux)
```

### Line Separation

Absolutely do not place closing delimiters on their own lines.

```fennel
;; Don't:
(fn factorial [x]
  (if (< x 2)
      1
      (* x (factorial (- x 1
                      )
           )
      )
  )
)

;; Do:
(fn factorial [x]
  (if (< x 2)
      1
      (* x (factorial (- x 1)))))
```

The parentheses grow lonely if their closing delimiters are all kept
separated and segregated.

#### Exceptions to the Above Rule Concerning Line Separation

Do not heed this section unless you know what you are doing.  Its title does
*not* make the unacceptable example above acceptable.

When commenting out fragments of expressions with line comments, it may be
necessary to break a line before a sequence of closing delimiters:

```fennel
(fn foo [bar]
  (munge [(frob bar)
          (zork bar)
          ;; (zap bar)
          ]))
```

It is acceptable to break a line immediately after an opening delimiter and
immediately before a closing delimiter for very long tables. This eases the
maintenance of the data and clarifies version diffs. For example:

```fennel
(local color-names ; Add more color names to this list!
       [
        :blue
        :cerulean
        :green
        :magenta
        :purple
        :red
        :scarlet
        :turquoise
        ])
```

## Indentation and Alignment

For any call to a function, macro, or special form, the callee following the
opening paren determines the rules for indenting or aligning the remaining
forms.  Certain names in this position indicate special alignment or
indentation rules; these are special forms and macros that accept a "body"
argument or arguments.

```fennel
;; Don't:
(when condition
      (print "Running the thing!")
      (run :the-thing))

;; Do:
(when condition
  (print "Running the thing!")
  (run :the-thing))
```

If the callee is not a special name, however, then if the first argument is
on the same line, align the starting column of all following arguments with
that of the first argument.  If the first argument is on the following line,
align its starting column with that of the callee, and do the same for
all remaining arguments.

```fennel
;; Don't:
(+ (sqrt -1)
  (* x y)
  (+ p q))

(+
   (sqrt -1)
   (* x y)
   (+ p q))

;; Do:
(+ (sqrt -1)
   (* x y)
   (+ p q))

(+
 (sqrt -1)
 (* x y)
 (+ p q))
```

Indentation should dictate structure; confusing indentation is a burden on the
reader who wishes to derive structure without matching parentheses manually.

In general if you are unsure of how something should be indented you can
defer to [fnlfmt][1]. The exception is
that fnlfmt cannot know when you are writing your own macros which take a
body; it only knows about the ones built-in to Fennel.

TODO: come up with a convention for naming body-having macros.

## Line Length

Try to avoid writing lines that exceed eighty columns. Multiple studies have
shown that long lines have a negative impact on how quickly people can read a
text. It is true that we have very wide screens these days, and we are no
longer limited to eighty-column terminals; however, we ought to exploit our
wide screens not by writing long lines, but by viewing multiple fragments of
code in parallel. We should also be considerate of readers with poor eyesight
for whom smaller font sizes cause eye strain.

## Blank Lines

Separate each adjacent top-level form with a single blank line (i.e.  two
line breaks). Avoid blank lines in the middle of a function except for cases
where a function contains another function definition or for cases where an
`if` or `match` has several test/body pairs that would otherwise be difficult
to distinguish from each other.

## Names

[Naming][2] is subtle and elusive.
Bizarrely, it is simultaneously insignificant, because an object is
independent of and unaffected by the many names by which we refer to it, and
also of supreme importance, because it is what programming -- and, indeed,
almost everything that we humans deal with -- is all about.  A full
discussion of the concept of name lies far outside the scope of this
document, and could surely fill not even a book but a library.

Don't use short names for things unless they are only in scope briefly. The
greater the distance between the introduction of an identifier and its use,
the more descriptive the name should be.

Identifiers are written with lower-case words separated by hyphens. CamelCase
is frowned upon. In cases where the resulting code is intended to be consumed
from Lua programs, a module's fields can use underscores instead of hyphens
because Lua's identifier rules make it tedious to access fields which have
hyphens in them. But the underscores should only be used in the name exported
in the module, not the name used inside the module.

```fennel
;; Don't:

(local XMLHttpRequest (make-request))
(macro foreach [t ...] ...)
(fn append_map [t f] ...)

;; Do:
(local xml-http-request (make-request))
(macro for-each [t ...] ...)
{:append_map append-map} ; when exporting a module for Lua code
```

Do not mark constants specially; every local is a constant unless it is
declared with `var`.

If a function is intended to be placed in a table and take that table as its
first argument, name the first argument `self`, like Lua's `function tbl:f()`
notation does implicitly.

If a parameter is ignored, name it either `_` or (usually better) a
descriptive name starting with an underscore. If a parameter or local may be
nil, begin its name with a question mark. Even though `lambda` and `match`
are the only contexts in which the compiler cares about this convention, it
is still useful to convey to a human reader in other contexts.

### Funny Characters

There are several different conventions for the use of punctuation characters
in names.

#### Question Marks: Predicates

Affix a question mark to the end of a name for a function whose purpose is to
ask a question of an object and to yield a boolean answer.  Such functions
are called "predicates".

Pronounce the question mark as "huh".  For example, to read the fragment
`(pair? object)` aloud, say: "pair-huh object."

Do not name functions `is-foo`; the use of the `is` prefix comes from
languages which are not allowed to use question marks in identifier names and
has no place in Fennel.

#### Exclamation Marks: Destructive Operations

Affix an exclamation mark to the end of a name for a function whose primary
purpose is to modify a table or perform I/O.

Avoid using the exclamation mark willy nilly for just *any* function whose
operation involves any kind of side effect; instead, use the exclamation mark
to identify functions that exist solely for the purpose of destructive
update, or to distinguish a destructive variant of a function of which there
also exists a purely functional variant.

Pronounce the exclamation mark as "bang".  For example, to read the fragment
`(append! contents new-contents)` aloud, say: "append-bang contents
new-contents."

#### Asterisks: Variants

Affix an asterisk to the end of a name to make a variation on a theme of the
original name. Prefer a meaningful name over an asterisk; the asterisk does
not explain what variation on the theme the name means and should generally
be interpreted as "I couldn't come up with a descriptive name here, sorry."

#### Arrows: Conversion functions

Functions which convert one thing to another should be named with a `->` in
the middle, such as `bytes->table`. Don't put `->` at the end of an
identifier unless it's a macro that works like `->`.

Pronounce the arrow as "to". For example, `bytes->table` would be read
as "bytes to table".

## Comments

Write heading comments with at least four semicolons; write top-level
comments with three semicolons. Write comments on a particular fragment of
code before that fragment and aligned with it, using two semicolons. Write
margin comments with one semicolon.

Examples:

```fennel
;;;; Frob Grobl

;;; This section of code has some important implications:
;;;   1. Foo.
;;;   2. Bar.
;;;   3. Baz.

(fn fnord [zarquon]
  ;; If zob, then veeblefitz.
  (quux zot
        mumble             ; Zibblefrotz.
        frotz))
```

Write comments only where the code is incapable of explaining itself.  Prefer
self-explanatory code over explanatory comments. Most comments should answer
questions the reader might have about **why** the code is written that way,
not about how it works. Comments are an opportunity to provide context, not
for description.

## Docstrings

Any function that is part of a library's public API should have a docstring.

The first line of the docstring should be a concise summary of the function's
purpose; successive lines can go into greater detail. Do not indent the prose
contents of the docstring. Code examples in docstrings should be
indented. It's a good idea to mention the types of any arguments you accept
as well as the type of the return value.

Do not extract docstrings from your library and publish them as "The
Documentation". If docstring exports are published, they should be clearly
labeled as supplemental to the actual documentation, which should be
[hand-written by a human][3] and not an automated tool.

Docstrings should be written with the assumption that they are primarily for
consumption within the repl or editor, and not for export to a browser.

## Fennel-specific

The above sections consist mostly of rules which apply to lisps in general,
but the sections below apply to Fennel-specific features.

You can write object-oriented code with Fennel, but avoid carrying over
habits from object-oriented languages.  Consider the different aspects of
"OOP" independently and use only the ones that make sense for the
context. For instance, encapsulation is great and should be used everywhere,
while inheritance is usually a mistake--at the very least inheritance should
not be inseparably linked to classes. Polymorphism can be useful at times but
is not a good default to use everywhere.

When writing a multi-file library where one module relies on another, use
relative requires so that the code can be relocated inside the directory
structure of an application which uses your library.

Avoid sequential tables which have gaps in them; these frequently cause bugs.

If you can separate out side-effecting functions from value-returning
functions, do so. Counter-example: the `setmetatable` function in Lua
performs a side-effect on the table, but also returns it. This is good style
for Lua because there is no `doto` in Lua; it is not good style in Fennel.

When designing APIs, remember that it's always easier to loosen restrictions
without breaking backwards-compatibility than it is to add restrictions to
existing code already in use.

Any strings which have spaces in them must use `"this style"` notation. The
`:shorthand` notation can be more convenient if not, especially for things
like table fields. Most of the time if you should use the shorthand if you
can, but for strings that are used for a kind of data which *could* include
spaces but just happen not to, the longer style is better.

### Specific Forms

Do not use `when` unless the body specifically has side-effects; prefer `if`
for value-returning conditions. In general `do` (which is implied in `when`)
should be read as an indicator of side-effecting code.

Do not overuse the arrow forms like `->`. They are best used when
constructing a pipeline of operations on a consistent piece of data. If the
"subject" of the pipeline changes mid-pipeline, it's a good sign that you
should switch to using `let`. If rewriting the code to use `let` results in
clearer code due to the intermediate steps being named, do not use an arrow.

Try to keep uses of `var` scoped as tightly as possible. If you're using a
`var` more than a page away from where it's defined, consider restructuring
your code.

Only use the `(. foo :bar)` special form when the shorter `foo.bar` syntax
cannot be used due to the field name not being known at compile-time or the
table not being a symbol. Similarly do not call `:` when `(foo:bar)` would
work.

Remember that returning multiple values can make your functions less reusable
in certain contexts:

```fennel
(fn get-box []
  (let [next-box (table.remove box-queue)
        remaining? (< 0 (length box-queue))]
    (values {} remaining?)))

(table.insert boxes (get-box))
runtime error: bad argument #2 to 'insert' (number expected, got table)
```

Prefer destructuring to `.` for field access.

```fennel
;; Don't:

(let [box (. (get-boxes) 1)
      address (. (get-label) :address)]
  ...)

;; Do:
(let [[box] (get-boxes)
      {: address} (get-label)]
  ...)
```

Use `<` and `<=` but avoid `>` and `>=`. Interpret `<` as "are the numbers
in increasing order?" not "is the second number greater than the first number?"
Rationale: it's easy to get mixed up between `<` and `>` if you think of them
as "greater than" and "less than", especially since in infix languages people
are used to making the big end point to the larger value, which doesn't work
in prefix notation. But in Fennel, the `<` operator can take any number of
arguments, so it's really asking whether the arguments are in increasing
order. The `>` operator asks whether the numbers are in decreasing order,
which is less intuitive.

Do not use `#(this-style)` syntax for functions longer than a single
line. Never use long-form `(hashfn)` directly; only use the shorthand. Prefer
`partial` to hashfn shorthand where possible.

Do not use `require-macros` or `eval-compiler`.

The `lua` special form is intended to make it easier to port imperative
code to Fennel and get it working quickly before iterating on improving the
style; it should never be used except as a temporary hack.

### Modules

Avoid plurals in module names.

Gather all your top-level `require` calls to the top of your file so
dependencies can be seen at a glance.

Use `local` only at the top level of a module. Use `let` instead inside
functions. In some cases it can be better to even use `let` at the top level
to make it clearer that a given local is only used in a very limited scope
rather than available for the whole file.

Prefer constructing the module table at the bottom of the file rather than
defining it at the top and adding to it as you go. Being able to look at one
place and see everything that a module exports is great for readability.

If you export the bare minimum possible from your module, it will be easier
to change implementation details in the future without breaking consumers of
your module. Every module in your library should be assumed to be part of its
public API unless the module name contains "internal" or "private". This is
one case where Fennel's own codebase breaks the rules; sorry!

When naming fields of your module, assume that the module will be bound as a
local which matches the last segment of the module name. For instance, if
your module is named `"blaster.input"` then you can expect that users of your
code will bring it in with `(local input (require :blaster.input))` and thus
you can avoid repeating the word "input" in the fields you expose on your
module; rather than `get-input` you can name the function `get` so when it's
called, it will be as `(input.get)` rather than the redundant
`(input.get-input)`.

Always return a table from a module. Even if you think today that returning a
bare function is fine, you will regret it later.

Loading a module should have no side effects.

When requiring modules, note that destructuring fields at the top level will
interfere with reloading.

Example:

```fennel
(local {: view} (require :fennel))
```

Often this is fine; in the example above it's unlikely that the `:fennel`
module will be reloaded, but in other cases it can cause problems.

It is often a good idea to set a global in order to expose some data to the
repl for interactive development, but your program should never use that
global except in order to preserve state during reloads. Avoid the `global`
special form, preferring table access on `_G` instead.

Since modules are tables, their contents can be changed. Avoid this
temptation, except in the case of reloading the entire module.

If you have more than a few files of code, place your module files in a
`src/` directory. If you have scripts meant to be launched from a shell,
place them in a `bin/` directory. Tests should go in a `test/` directory.

### Error handling

Lua and thus Fennel have two ways of indicating errors. The first is the
convention of returning multiple values, nil followed by a message describing
the error. This should be preferred in cases where a failure is to be
expected, such as a file not being found, or a socket closing
unexpectedly. Functions which use this style should usually be called inside
a `match` form so the success and failure cases can be side by side.

Errors raised using the `error` or `assert` functions should be preferred
when fundamental assumptions are found to be violated in a way which
indicates a bug in the program.

However, in some cases when an expected failure cannot be recovered from,
using `error` lets you abort quickly without propagating the error as return
values up a long call stack; this is acceptable, but it's better if your I/O
happens at the edges of your program rather than deep inside.

### Macros

Familiarize yourself with the [values of Fennel][4] before you begin
designing any macros. The rules of lexical scoping are absolutely
foundational to Fennel, and if your macro obscures them, it probably needs to
be reworked. The biggest problem with macros is that it's possible to break
the rules of syntax since they can do basically anything. Try to design your
macros so that they hold as few surprises as possible, and that anyone can
make a reasonable guess as to what they mean.

Fennel is very carefully designed such that parentheses are only ever used
for two things: calling functions/macros, and binding multiple values. If you
want your macro to feel "natural" you should preserve this property as much
as possible.

Before writing a macro you should spell out in detail what you want your
macroexpansion to look like. Then write what you want the macro call to look
like. Often you will find that writing the macroexpansion directly is not
bad, and that the macro is not needed. Never provide functionality which can
*only* be used from a macro. The macro should provide a more convenient
notation for things you can already accomplish with functions.

When writing a macro which depends on functionality that comes from a
separate module, the macroexpansion should include a call to `require` so
that the macro can be used in a module where there's not already a top-level
`require` for said functionality.

Do not write macros which introduce identifiers "out of thin air". If a macro
needs to bind a new local, accept the name of the local as an argument.
Ideally new locals should be accepted in a binding table similar to
`let` or `with-open`. Use quoting to build lists instead of calling `list`.

# Attribution

   Copyright © 2007-2011 Taylor R. Campbell
   Copyright © 2021 Phil Hagelberg and contributors

   CC BY-NC-SA 3.0

   This work is licensed under a Creative Commons
   Attribution-NonCommercial-ShareAlike 3.0 Unported License:
   <http://creativecommons.org/licenses/by-nc-sa/3.0/>.

Based on the [Lisp Style Guide](http://mumble.net/~campbell/scheme/style.txt)
by Taylor R. Campbell

[1]: https://git.sr.ht/~technomancy/fnlfmt
[2]: https://blog.janestreet.com/whats-in-a-name/
[3]: https://jacobian.org/2009/nov/10/what-to-write/
[4]: https://fennel-lang.org/values
