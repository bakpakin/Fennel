# Why Fennel?

Fennel is a programming language that runs on the Lua runtime.

## Why Lua?

The Lua programming language is an excellent and very underrated tool. Is it
remarkably powerful yet keeps a very small footprint both conceptually as a
language and in terms of the size of its implementation. (The reference
implementation consists of about nineteen thousand lines of C and compiles to
278kb.) Partly because it is so simple, Lua is also extremely fast. But the
most important thing about Lua is that it's specifically designed to be put
in other programs to make them reprogrammable by the end user.

The conceptual simplicity of Lua stands in stark contrast to other "easy to
learn" languages like JavaScript or Python--Lua contains very close to the
minimum number of ideas needed to get the job done; only Forth and Scheme
offer a comparable simplicity. When you combine this meticulous simplicity
with the emphasis on making programs reprogrammable, the result is a powerful
antidote to prevailing trends in technology of treating programs as black
boxes out of the control of the user.

## And yet...

So if Lua is so great, why not just use Lua? In many cases you should!  But
there are a handful of shortcomings in Lua which over time have shown to be
error-prone or unclear. Fennel runs on Lua, and the runtime semantics of
Fennel are a subset of Lua's, but you can think of Fennel as an alternate
notation you can use to write Lua programs which helps you avoid common
pitfalls. This allows Fennel to focus on doing one thing very well and not get
dragged down with things like implementing a virtual machine, a standard
library, or profilers and debuggers. Any library or tool that already works
for Lua will work just as well for Fennel.

The most obvious difference between Lua and Fennel is the parens-first
syntax; Fennel belongs to the Lisp family of programming languages. You could
say that this removes complexity from the grammar; the paren-based syntax is
more regular and has fewer edge cases. Simply by virtue of being a lisp,
Fennel removes from Lua:

* statements (everything is an expression),
* operator precedence (there is no ambiguity about what comes first), and
* early returns (functions always return in tail positions).

## Variables

One of the most common legitimate criticisms leveled at Lua is that it makes
it easy to accidentally use globals, either by forgetting to add a `local`
declaration or by making a typo. Fennel allows you to use globals in the rare
case they are necessary but makes it very difficult to use them by accident.

Fennel also removes the ability to reassign normal locals. If you declare a
variable that will be reassigned, you must introduce it with `var`
instead. This encourages cleaner code and makes it obvious at a glance when
reassignment is going to happen. Note that Lua 5.4 introduced a similar idea
with `<const>` variables, but since Fennel did not have to keep decades of
existing code like Lua it was able to make the cleaner choice be the default
rather than opt-in.

## Tables and Loops

Lua's notation for tables (its data structure) feels somewhat dated. It uses
curly brackets for both sequential (array-like) and key/value
(dictionary-like) tables, while Fennel uses the much more familiar notation
of using square brackets for sequential tables and curly brackets for
key/value tables.

In addition Lua overloads the `for` keyword for both numeric "count from X to
Y" style loops as well as more generic iterator-based loops. Fennel
uses `for` in the first case and introduces the `each` form for the latter.

## Functions

Another common criticism of Lua is that it lacks arity checks; that is, if
you call a function without enough arguments, it will simply proceed instead
of indicating an error. Fennel allows you to write functions that work this
way (`fn`) when it's needed for speed, but it also lets you write functions
which check for the arguments they expect using `lambda`.

## Other

If you've been programming in newer languages, you are likely to be spoiled
by pervasive destructuring of data structures when binding variables, as well
as by pattern matching to write more declarative conditionals. Both these are
absent from Lua and included in Fennel.

Finally Fennel includes a macro system so that you can easily extend the
language to include new syntactic forms. This feature is intentionally listed
last because while lisp programmers have historically made a big deal about
how powerful it is, it is relatively rare to encounter situations where such
a powerful construct is justified.
