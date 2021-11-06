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
  Take a look at the [issue tracker][3] and the [mailing list][2].
* If you can't find a past issue for your problem, or if the issues has been
  closed you should open a new issue. If there is a closed issue that is
  relevant, make sure to reference it.
* As with any project, include a comprehensive description of the problem and
  instructions on how to reproduce it. If it is a compiler or language bug,
  please try to include a minimal example. This means don't post all 200 lines
  of code from your project, but spend some time distilling the problem to just
  the relevant code.
* Add the `bug` label to the issue.

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
* `src/fennel/specials.fnl`: built-in language constructs written in Lua
* `src/fennel/macros.fnl`: built-in language constructs written in Fennel
* `src/fennel/utils.fnl`: definitions of core AST types and helper functions

Finally there are a few miscellaneous modules:

* `src/fennel/friend.fnl`: emits friendly messages from compiler/parser errors
* `src/fennel/binary.fnl`: produces binary standalone executables
* `src/fennel/view.fnl`: turn Fennel data structures into printable strings

### Bootstrapping

Fennel is written in Fennel. In order to get around the chicken-and-egg
problem, we include an old version of the compiler that's used to
compile the new version.

* `old/fennel.lua`: older version of Fennel compiler from before self-hosting
* `old/launcher.lua`: older version of the command line launcher

The file `src/fennel/macros.fnl` where the built-in macros are defined
is evaluated by the compiler in `src/`, not by the bootstrap compiler.
This means that you cannot use any macros here; for instance it's
necessary to use `if` even in cases where `when` would make more sense.

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

## Contributing Changes

If you want to contribute code to the project, please [send patches][1] to the
[mailing list][2]. (Note that you do not need to subscribe to the mailing list
in order to post to it.) We also accept code contributions on the [GitHub
mirror](https://github.com/bakpakin/Fennel) if you prefer not to use email. For
smaller changes, you can also push your changes to a branch on a public git
remote hosted anywhere you like and ask someone on IRC or the mailing list to
take a look.

In order to get CI to automatically run your patches, they will need to have
`[PATCH fennel]` in the subject. You can configure git to do this automatically:

    git config format.subjectPrefix 'PATCH fennel'

For large changes, please discuss it first either on the mailing list,
IRC/Matrix channel, or in the issue tracker before sinking time and effort into
something that may not be able to get merged.

* Branch off the `main` branch. The contents of this branch should be
  the same on Sourcehut as they are on the Github mirror. But make
  sure that `main` on your copy of the repo matches upstream.
* Write a detailed description of the changes in the commit message, including
  motivation for the change and alternatives which were considered but decided
  against. One-line commit messages are only appropriate for trivial changes.
* Please include tests if at all possible. You can run tests with `make test`.
* Make sure that your changes will work on Lua versions 5.1, 5.2, 5.3, 5.4, and
  LuaJIT. Making fennel require LuaJIT or 5.2+ specific features is a
  non-goal of the project. In general, this means target Lua 5.1, but provide
  shims for where functionality is different in newer Lua versions. Running
  `make testall` will test against all supported versions, assuming they're
  installed. If you don't want to install every supported version of
  Lua, you can rely on the CI suite to test your patches.
* Be consistent with the style of the project. Please try to code moderately
  tersely; code is a liability, so the less of it there is, the better.
* For user-visible changes, include a description of the change in
  `changelog.md`. Changes that affect the compiler API should update `api.md`
  while changes to the built-in forms will usually need to update
  `reference.md` to reflect the new behavior.

[1]: https://man.sr.ht/git.sr.ht/send-email.md
[2]: https://lists.sr.ht/%7Etechnomancy/fennel
[3]: https://todo.sr.ht/~technomancy/fennel
