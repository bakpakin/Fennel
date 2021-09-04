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

This old version (based on 0.4.2) does not have all the newer language features
of Fennel except in cases where we have explicitly backported certain
things, such as `collect` and `icollect`.

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
* Include a description of the changes in the commit message.
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

If all goes well, we should merge your changes fairly quickly.

## Suggesting Changes

Informal discussion of changes is easiest on the IRC/Matrix channel, but the
mailing list can also be good for this. More serious proposals should go on the
mailing list or issue tracker. There is a possibility that there is already a
solution for your problems so be sure that there is a good use case for your
changes before opening an issue.

* Include a good description of the problem that is being solved.
* Include descriptions of potential solutions if you have some in mind.
* Add the appropriate labels to the issue. For new features, add `enhancement`.

[1]: https://man.sr.ht/git.sr.ht/send-email.md
[2]: https://lists.sr.ht/%7Etechnomancy/fennel
[3]: https://todo.sr.ht/~technomancy/fennel
