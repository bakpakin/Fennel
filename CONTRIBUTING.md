# Guidelines for contributing to Fennel

> True leaders  
> are hardly known to their followers.  
> Next after them are the leaders  
> the people know and admire;  
> after them, those they fear;  
> after them, those they despise.  
>  
> To give no trust  
> is to get no trust.  
>  
> When the work's done right,  
> with no fuss or boasting,  
> ordinary people say,  
> Oh, we did it.  
>  
> - Tao Te Ching chapter 17, translated by Ursula K. Le Guin

## Reporting bugs

* Check past and current issues to see if your problem has been run into before.
  Take a look at the [issue tracker][3], the [mailing list][2], and
  the [old issue tracker][6].
* If you can't find a past issue for your problem, you should open a new issue.
  If there is a closed issue that is relevant, make sure to reference it.
* As with any project, include a comprehensive description of the problem and
  instructions on how to reproduce it. If it is a compiler or language bug,
  please try to include a minimal example.

## Codebase Organization

The `fennel` module is the fundamental entry point; it provides the entire
public API for Fennel when it's used inside another program. All other modules
except `fennel.view` are considered compiler internals and do not have a
guaranteed stable API.

* `src/fennel.fnl`: returned when Fennel is embedded programmatically
* `src/launcher.fnl`: handles being launched from the command line
* `src/fennel/repl.fnl`: provides interactive development context

The core modules implement the text->AST->Lua pipeline. The AST used
by the compiler is the exact same AST that is exposed to macros.

* `src/fennel/parser.fnl`: turns text of code into an AST
* `src/fennel/compiler.fnl`: turns AST into Lua output
* `src/fennel/specials.fnl`: built-in fundamental language constructs
* `src/fennel/macros.fnl`: built-in language constructs that use fundamentals
* `src/fennel/match.fnl`: pattern matching macro implementations
* `src/fennel/utils.fnl`: definitions of core AST types and helper functions

Finally there are a few miscellaneous modules:

* `src/fennel/friend.fnl`: emits friendly messages from compiler/parser errors
* `src/fennel/binary.fnl`: produces binary standalone executables
* `src/fennel/view.fnl`: turn Fennel data structures into printable strings

### Bootstrapping

Fennel is written in Fennel. In order to get around the chicken-and-egg
problem, we include an older version of the compiler (written in Lua)
that's used to compile the new version (written in Fennel).

* `bootstrap/fennel.lua`: version 0.4.x of the compiler library
* `bootstrap/aot.lua`: short shim which wraps the library to do AOT

Not all changes need to be backported to the bootstrap compiler, but
new macros generally should be.

The file `src/fennel/macros.fnl` where the built-in macros are defined
is evaluated by the compiler in `src/`, not by the bootstrap compiler.
This means that you cannot use any macros here; for instance it's
necessary to use `if` even in cases where `when` would make more sense.

The file `src/fennel/match.fnl` contains the pattern matching macros;
because of their complexity they are broken out so that they can use the rest
of the macros in their implementation.

## Deciding to make a Change

Before considering making a change to Fennel, please familiarize yourself
with [the Values of Fennel](values.md).

Fennel has made incompatible changes in the past, but at this point in its
evolution we are committed to backwards compatibility. A change which breaks
existing programs will only be considered if it fixes a security vulnerability.

Fennel follows Lua's lead in being a language with a very small conceptual
footprint. Being built on Lua, Fennel is necessarily larger than Lua, but not
by a lot. We have a high bar for adding new features to the language. Once you
have identified a problem and have sketched out a potential solution there are
four main questions to consider:

* How common is the problem?
* How bad is the workaround you must employ without the proposed solution?
* How much code does the proposed solution involve?
* How much mental overhead does the proposed solution introduce?

Let's look at some examples.

The `match` macro is quite large, both in terms of its implementation and its
meaning; it is by far the biggest addition to the semantics of Fennel for
which a comparative construct does not exist in Lua. Pattern matching in
general can be thought of as a composition of conditions and destructuring,
so its addition is not as big in Fennel (where conditions and destructuring
both already exist a la carte) as it would be in a language which did not
already have destructuring.  But weighing this cost against the benefits we note
that `match` is applicable to a multitude of situations and that rewriting
the code to avoid it results in ugly code.

Adding `icollect` was thoroughly merited in that it is needed very frequently,
and the alternative is tedious. When considering the conceptual footprint, we
note that `icollect` parallels the existing `each` construct closely; the
only difference being that the body of the macro is used to construct a
sequential table instead of being discarded. So the cost/benefit ratio is
great. The `collect` macro, on the other hand, is used much more
infrequently. But it's also an even smaller change; given that `icollect`
exists, it's fairly obvious how a parallel key/value-based variant would
work.

Note that the above only describes the process for language-level features.
There are other changes which affect (say) the compiler or the repl but do not
affect the language itself; the dynamic for making those changes is different
and the bar (other than that of backwards-compatibility) is not quite so high.
An addition to the language is a cost that everyone reading and writing Fennel
code from here on out will have to pay; an addition to the API is not.

## Contribution Transparency

Please note that it is **ethically unacceptable** to submit patches (to this
project or any other) which you did not author yourself without giving clear
attribution to the original author. Note that this includes submitting changes
generated by most so-called "artificial intelligence" language models as these
systems make it impossible to even identify (much less credit) the original
source of the changes.

Please do not submit patches or issue reports that are generated by a large
language model. Doing this shows a profound disrespect for the maintainers'
time and will result in an immediate ban.

## Making Changes

If you want to contribute code to the project, please [create a ticket][7] for
the change if it doesn't exist yet. It's a good idea to do this before you
start working on the change. A little up-front discussion can help avoid
sinking time into something that may not be able to get merged.

Please include tests if at all possible. Fennel's tests use the [faith][5]
library; see the docs there and follow the conventions in existing tests. For
smaller changes you can just test against a single version of Lua (with `make
test`) and rely on the CI suite to run the rest, but for larger changes please
make sure that your changes will work on Lua versions 5.1, 5.2, 5.3,
5.4, 5.5, and LuaJIT. Making fennel require LuaJIT or 5.2+ specific features
is not going to fly. Running `make testall` will test against all supported
versions, assuming they're installed.

For user-visible changes, add a description of the change in `changelog.md`.
Changes that affect the compiler API should update `api.md` while changes to
the built-in forms will usually need to update `reference.md` to reflect the
new behavior.

Write a detailed description of the changes in the commit message, including
motivation for the change and alternatives which were considered but decided
against. One-line commit messages are only appropriate for trivial changes.

## Submitting Changes

Once you've committed your change in git, you can run `git format-patch HEAD~`
to generate a `.patch` file of your most recent commit. Then attach your patch
to the ticket. Attaching a patch will [trigger a CI run][8] for your changes.

If you prefer to send patches over email, you can send them to the [mailing
list][4] instead, but don't paste the patch directly into your mail client as
it will usually reformat it subtly. Use an attachment or `git send-email`.

For trivial changes you can push your commit to a git remote (on any host)
and drop a link to the branch in chat. But this is not suitable for changes
that may require discussion.

Please be patient if it takes a long time to get feedback on your change;
there are very few people who review patches, and no one works on Fennel for
their day job.

[1]: https://git-send-email.io
[2]: https://lists.sr.ht/%7Etechnomancy/fennel
[3]: https://dev.fennel-lang.org/report/1
[4]: mailto:~technomancy/fennel@lists.sr.ht
[5]: https://git.sr.ht/~technomancy/faith
[6]: https://todo.sr.ht/~technomancy/fennel
[7]: https://dev.fennel-lang.org/newticket
[8]: https://builds.sr.ht/~technomancy/fennel
