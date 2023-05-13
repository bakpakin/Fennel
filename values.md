# Values of Fennel

This document is an outline of the guiding design principles of Fennel.
Fennel's community values are covered in the [code of conduct](https://fennel-lang.org/coc).

## Compile-time

First and foremost is the notion that Fennel is a compiler with no
runtime. This places somewhat severe limits on what we can accomplish,
but it also creates a valuable sense of focus. We are of course very
fortunate to be building on a language like Lua where the runtime
semantics are for the most part excellent, and the areas upon which we
improve can be identified at compile time.

This means Fennel (the language) consists entirely of macros and
special forms, and no functions. Fennel (the compiler) of course has
plenty of functions in it, but they are for the most part not intended
for use outside the context of embedding the compiler in another Lua
program.

The exception to this rule is `fennel.view` which can be used
independently; it addresses a severe problem in Lua's runtime
semantics where `tostring` on a table produces nearly-useless
results. But this can be thought of as simply another library which
happens to be included in the compiler. The `fennel.view` function is
a prerequisite to having a useful repl.

The repl of course is also a function you can call at runtime if you
embed the compiler, but this is a special case that blurs the lines
between runtime and compile time.  After all, what is compile time
except that subset of runtime during which the function being run
happens to be a compiler?

## Transparency

Well-written Lua programs exhibit an excellent sense of transparency
largely due to how Lua leans on lexical scoping so predominantly.
When you look at a good Lua program, you can tell exactly where any
given identifier comes from just by following the basic rules of
lexical scope. Badly-written Lua programs often use globals and do not
have this property.

With Fennel we try to take this even further by making globals an
error by default. It's still possible to write programs that use
globals using `_G` (indeed for Lua interop this sometimes cannot be
avoided) but it should be very clear when this happens; it's not
something that you would do by accident or due to laziness.

One counter-example here is the deprecated `require-macros` form; it
introduced new identifiers into the scope without making it clear what
the names were. That is why it was replaced by the much clearer
`import-macros`.  The two below are equivalent, but one has hidden
implicit scope changes and the other exhibits transparency:

```fennel
(require-macros :my.macros) ; what did we introduce here? who knows!

(import-macros {: transform-bar : skip-element} :my-macros)
```

Of course this comes at the cost of a little extra verbosity, but it
is well worth it. In Fennel programs, you should never have a hard
time answering the question "where did this come from?"

## Making mistakes obvious

The most obvious legitimate criticism of Lua is that it makes it easy
to set or read globals by accident simply by making a typo in the name
of an identifier. This is easily fixed by requiring global access to
be explicit; it's perhaps the most obvious way that Fennel tries to
catch common mistakes. But there are others; for instance Fennel does
not allow you to shadow the name of a special form with a local. It
also doesn't allow you to omit the body from a `let` form like many
other lisps do:

```fennel
(fn abc []
  (let [a 1
        b 2
        c (calculate-c)]) ; <- missing body!
    (+ a b c))
```

This will be flagged as an error because the entire `let` form is
closed after the call to `calculate-c` when the intent was clearly
only to close the binding form.

Another example would be that you can't call `set` on a local unless
it is introduced using `var`. This means that if you have code which
assumes the locals will remain the same and then go and mess with that
assumption it is an error; you have to explicitly declare that
assumption void first before you are permitted to violate it.

This touches on a broader theme: it's easier to understand code when
you can look at it and immediately know certain things will never
happen. By excluding certain capabilities from the language, certain
mistakes become impossible.

For example, Fennel code will never use a block of memory after it has
been freed, because `malloc` and `free` are not even part of its
vocabulary. In languages with immutable data structures, it's
impossible to have bugs which come from one piece of code making a
change to data in a way that another function did not expect. Fennel
does not have immutable data structures, but still we recognize that
removing the ability to do things (or making them opt-in instead of
opt-out) can significantly improve the resulting code.

Other examples include the lack of `goto` and the lack of early
returns. Or how if a loop terminates early, it will make this obvious by
using an `&until` clause at the top of the loop; you don't have to
read the entire loop body to search for a `break` as you would in Lua.

## Consistency and Distinction

Older lisps overload parentheses to mean lots of different things;
they are used for data lists, but they are also used to signify
function and macro calls or to group key/value pairs together and
around an entire group of key/value pairs in `let`. There are many
other uses.

Fennel overloads delimiters in a few ways, but the distinction should
be visually clearer and much more limited by context. Parentheses
almost always mean a function or macro call; the main exception is
inside a binding form where it can be used to bind multiple
values. The other exception is the now-deprecated `?` notation for
pattern matching guards; it has been replaced by calling
`where`. Square brackets usually indicate a sequential table, but in a
macro they can indicate a binding form. Perhaps were Fennel rooted in
a language richer in typographical delimiters than English, this
overloading would not be necessary and every delimiter pair could have
exactly one meaning.

This is something Lua drops the ball on in a few places; it overloads
one notation to mean different things. For instance, `for` in Lua can
be used to numerically step from one number to another in a loop, or
it can be used to step thru an iterator. Fennel separates this out
into `for` to be used with numeric stepping and `each` which uses
iterators. Another example is the table literal notation: Lua uses
`{}` for sequential tables as well as key/value tables, while Fennel
uses `[]` for sequential tables following more recent programming
convention.

Fennel uses notation in other ways to avoid ambiguity; for instance
when `&as` was introduced in destructuring forms for giving access to
the entire table, the `&` character was reserved so that it could not
be used in identifiers. This also makes it easier to write macros
which do similar things; now we have a way to indicate that a given
symbol must have some meaning assigned to it other than being an
identifier.

