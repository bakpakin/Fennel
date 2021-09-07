# Macro Guide

Macros are how lisps accomplish metaprogramming. You'll see a lot
of people treat lisp macros with a kind of mystical reverence. "Macros
allow you to do things that aren't possible in other languages" is a
common refrain, but that's nonsense. ([Turing tarpits][1] exist; other
languages have macros.) The difference is that lisps allow you to write
programs using the same notation you use for data structures. It's not
that these things are impossible in other languages; it's just that
the lisp way flows seamlessly instead of feeling arcane.

There are really only three things you need to understand in order to
write effective macros:

* Code is Data
* Manipulating Data
* Details

## Code is data

In some sense "code is data" seems like a tautology. Code lives in
files on disk; files contain data. If you want to use that data, you
load up a parser and you can operate on it like you would any other
file format. Almost every language works this way; that's just the
basics of compilers. In many languages, the compiler feels distant and
hallowed. You submit your code, and you are granted back an executable
etched in a stone tablet (or perhaps the wrath of the compiler if you
made a mistake). The data it used to produce that executable is not
accessible to the lowly program.

But it doesn't have to be this way. Using a compiler can feel more like
having a conversation where you go back and forth, and macros can blur
the line between the compiler and the program. In the case of Fennel,
that means you can get the program's own data as a table.

```fennel
(when message.to
  (deliver message :immediately))
```

According to the compiler, this is a table of three elements: the
symbol `when`, the symbol `message.to`, and the table `(deliver
message :immediately)` which itself consists of two symbols and a
string. A symbol is a bare token which represents an identifier. Let's
look at a more complex example:

```fennel
(let [[a b c & rest] (get-elements)
      {:input input :output output} (pipe-for a 22)]
  (route input b c output (table.unpack rest)))
```

There's a lot more going on here, but it's still just a table of three
elements. Again we start with a symbol (`let`) but in this case the
second argument is a sequential table. Square brackets in Fennel code
tend to indicate that new locals are being introduced, but they are
just normal sequential tables. When destructuring you can see that
both sequential tables and key/value tables can be used, for the
return value of `get-elements` and `pipe-for` respectively.

## Manipulating Data

Manipulating data is just regular programming! If you know Fennel, you
know how to write a function which takes a table and returns a table
that looks a little different. Cool!

Once you understand that code is data and data is (mostly) tables,
that means all the skills you have from writing regular Fennel
programs can apply to macros. You want to use `table.remove` on a list
that represents code? Go for it. You can use `each`/`ipairs` to step
thru the contents of the lists. Destructuring and even pattern
matching work as you'd expect. A list is just a special kind of table
which prints with parens instead of square brackets.

## Details

That's all! Everything else is details.

OK, so ... that's not quite fair. There are a few things you still
need to understand. Let's start with the tiniest of examples just to kick
things off:

```fennel
(macro postfix3 [[x1 x2 x3]]
  (list x3 x2 x1))

(postfix3 ("world" "hello" print)) ; -> becomes (print "hello" "world")
```

This is one of the simplest macros possible. It takes a list of three
elements and returns a list with the elements in the opposite
order. From this example you can see that macros look like functions
which take arguments. But you can't write a function that takes
`("world" "hello" print)` as an argument! What's going on here?

Let's walk thru a bigger example.

The first step when you want to write a macro is to identify the
transformation you want to perform on the code. Let's take a look at what it might
look like to write a `thrice-if` macro which takes a condition and a
form, and runs the form three times, each time first checking that the
condition is still true.

```fennel
(thrice-if (ready-to-go?)
           (make-it-so!))
```

We want this to result in the following code:

```fennel
(if (ready-to-go?)
    (do (make-it-so!)
        (if (ready-to-go?)
            (do (make-it-so!)
                (if (ready-to-go?)
                    (do (make-it-so!)))))))
```

So maybe we don't yet know how to write this macro. But stop for a
minute and imagine if this were not a macro but a
function which takes a normal square-bracket table and uses strings
instead of symbols. It would look like this when run:

```fennel
(thrice-if* [:ready-to-go?]
            [:make-it-so!])

;; [:if [:ready-to-go?]
;;       [:do [:make-it-so!]
;;            [:if [:ready-to-go?]
;;                 [:do [:make-it-so!] 
;;                      [:if [:ready-to-go?]
;;                           [:do [:make-it-so!]]]]]]]
```

When the problem is framed this way, it's easy to imagine how such a
function might work. This one uses recursion, but you could implement it
with a loop if you prefer; that's not important. The important thing
is: tables go in, and a table comes out.

```fennel
(fn thrice-if* [condition body]
  (fn step [i]
    (if (< 0 i)
        [:if condition [:do body (step (- i 1))]]))
  (step 3))
```

Now that we have this function, what does it take to turn it into a macro?

```fennel
(macro thrice-if [condition body]
  (fn step [i]
    (if (< 0 i)
        (list (sym :if) condition (list (sym :do) body (step (- i 1))))))
  (step 3))
```

Instead of using `[]` tables we call the `list` function, and instead
of strings we call the `sym` function. Easy!

Both these functions are only available inside macros because of the
compiler environment. We'll get back to that later.

**Note**: It is very common to get to step one, write out the
expansion you want your macro to return, and then realize you could
probably do it with a function. If you can, then great! You'll save
yourself some headache. Macros can tidy up repetitive code, but they
do introduce conceptual overhead, so be sure to weigh the pros and
cons before diving in. Of course, it takes time and experience to
learn how to judge this.

### Quoting

The notation above is easy to understand, but it's not as concise as
it could be. We have a trick that lets us tidy up those verbose calls
to `list` and `sym`: quoting.

The backtick character can be thought of as creating a template of a
list which you can then selectively interpolate values using a comma
character to unquote. This is similar to how string interpolation
works in languages like Ruby.

```fennel
(macro thrice-if [condition body]
  (fn step [i]
    (if (< 0 i)
        `(if ,condition (do ,body ,(step (- i 1))))))
  (step 3))
```

Symbols inside a quoted form remain as symbols. Symbols in an unquoted
form (like `,condition` and `,body` above) are **evaluated** meaning
they are replaced with whatever value they have in the code at that point.

Unquoting doesn't just apply to symbols; you can unquote lists too:
`,(step (- i 1))` above does that. A quoted list remains a list, but an
unquoted list behaves like it does in normal code: it calls a
function. The return value of the function is placed into the quoted list.

Quote and unquote are merely tools of notation. There is no difference
in the meaning between this version and the first version which calls
`list` and `sym` explicitly.

### macrodebug

Quoting is notoriously subtle and often trips new macro authors up. If
you run into trouble, `macrodebug` can save the day by showing you
precisely what your macro is expanding to. It's a tool you can run in
the repl to inspect the results of the macro expansion:

```fennel
>> (macrodebug (thrice-if (and (transporters-online?) 
                               (< 8 (torpedo-count))) 
                          (make-it-so!)))
(if (and (transporters-online?) (< 8 (torpedo-count))) (do (make-it-so!) (if (and (transporters-online?) (< 8 (torpedo-count))) (do (make-it-so!) (if (and (transporters-online?) (< 8 (torpedo-count))) (do (make-it-so!)))))))
```

Unfortunately as you can see, the downside of `macrodebug` is that
its output is not the most readable. You will want to copy it into your
text editor and add in newlines and indentation before you go any
further, or run it thru [fnlfmt][2].

### Identifiers and Gensym

Macros which introduce identifiers are slightly more complicated. If
you write a macro which accepts code as an argument, you can't make
any assumptions about the code. For example:

```fennel
(local engines (require :engines))

(macro when-weapons-safe [body]
  `(let [phasers (require :phasers)
         overloaded? (phasers.overloaded?)]
     (when (not overloaded?)
       ,body)))

(let [overloaded? (engines.overloaded?)]
  (when-weapons-safe (if overloaded?
                         (print "Engines overloaded")
                         (print "Engines OK."))))
```

This program will not behave as expected, because the outer
`overloaded?` value is shadowed by the one introduced by the
macro. In this case, the bug is very subtle and might not get noticed
until there is a dangerous situation!

But in fact, this program will not even compile. Fennel
will detect that the macro is introducing a new identifier in an
unsafe way:

```
Compile error in enterprise.fnl:4
  macro tried to bind phasers without gensym

  `(let [phasers (require :phasers)
         ^^^^^^^
* Try changing to phasers# when introducing identifiers inside macros.
```

The compiler's helpful hint on the last line there points us to a
solution. Adding `#` to the end of a symbol inside a quoted form
activates "gensym", that is, the symbol will be expanded to a
different symbol which is guaranteed to be unique and can never
conflict with an existing local value.

```fennel
(macro when-weapons-safe [body]
  `(let [phasers# (require :phasers)
         overloaded?# (phasers#.overloaded?)]
     (when (not overloaded?#)
       ,body)))
```

Above we said that there is no difference between using `list`/`sym`
and using backtick to construct lists. While the resulting code is the
same, this safety check will only work when you use backtick, so you should
prefer that style. In very rare cases, you could wish to bypass this
safety check; when you are in a situation like that, you can use `sym`
to create a symbol which the compiler will not flag. But this is
almost always a mistake.

### Macro Modules

In the example above we used `macro` to write an inline macro. This is
great when you only need it used in one file. But the `import-macros`
form lets you write a macro module containing macros which can be
re-used anywhere.

A macro module is just like any other module: it contains function
definitions and ends with a table containing just the functions which
are exported. The only difference is that the entire macro module is
loaded in the **compiler environment**. This is how it has access to
functions like `list`, `sym`, etc. For a full list of functions
available, see the "Compiler Environment" section of [the reference][3].

```fennel
;; thrice.fnl
(fn thrice-if [condition body]
  (fn step [i]
    (if (< 0 i)
        `(if ,condition (do ,body ,(step (- i 1))))))
  (step 3))

{: thrice-if}
```

The `import-macros` form allows you to use macros from a macro
module. The first argument is a destructuring form which lets you pull
individual macros out, but you can bind the entire module to a single
table if you prefer. The second argument is the name of the macro
module. Again, see [the reference][3] for details.

```fennel
(import-macros {: thrice-if} :thrice)

(thrice-if (main-power-online?)
           (enable-replicators))
```

### assert-compile

You can use `assert` in your macros to defensively ensure the inputs
passed in make sense. However, it's preferable to use the
`assert-compile` form instead. It works exactly the same as `assert`
except it takes an optional third argument, which should be
a list or symbol passed in as an argument to the macro. Lists and
symbols have file and line number metadata attached to them, which
means the compiler can pinpoint the source of the problem in the error message.

```fennel
(macro thrice-if [condition body]
  (assert-compile (list? body) "expected list for body" body)
  (fn step [i]
    (if (< 0 i)
        `(if ,condition (do ,body ,(step (- i 1))))))
  (step 3))

(thrice-if true abc)
```

```shell
$ fennel scratch.fnl
Compile error in scratch.fnl:8
  expected list for body

(thrice-if true abc)
                ^^^
stack traceback: ...
```

It's not required, but it's a nice courtesy to your users.

## That's all!

Now you're all set: go write a macro or two. 

But ... don't go overboard.

[1]: https://en.wikipedia.org/wiki/Turing_tarpit
[2]: https://git.sr.ht/~technomancy/fnlfmt
[3]: reference.md
