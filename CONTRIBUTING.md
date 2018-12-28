# Guidelines for contributing to Fennel

Thanks for taking time to contribute to Fennel!

Please read this document before making contributions.

## Reporting bugs

* Check past and current issues to see if your problem has been run into before.
* If you can't find a past issue for your problem, or if the issues has been closed
  you should open a new issue. If there is a closed issue that is relevant, make
  sure to reference it.
* As with any project, include a comprehensive description of the problem and instructions
  on how to reproduce it. If it is a compiler or language bug, please try to include a minimal
  example. This means don't post all 200 lines of code from your project, but spend some time
  distilling the problem to just the relevant code.
* Add the `bug` tag to the issue.

## Contributing Changes

If you want to contribute code to the project, please
[send patches][1] to the [mailing list][2]. Note that
you do not need to subscribe to the mailing list in order to post to it!

Alternately you may open a pull request on GitHub.

For large changes, please discuss it first either on the mailing list, IRC channel, or in a GitHub
issue before sinking time and effort into something we may not merge.

* Include a description of the changes.
* If there are changes to the compiler or the language, please include tests in test.lua. You can
  run tests with `make test`, or `lua test.lua`.
* Make sure that your changes will work on Lua versions 5.1, 5.2, 5.3, and LuaJIT. Making fennel
  require LuaJIT, 5.2, or 5.3 specific features is a non-goal of the project. In general, this means
  target Lua 5.1, but provide shims for where functionality is different in newer Lua versions. Running
  `make testall` will test against all supported versions, assuming they're installed.
* Be consistent with the style of the project. If you are making changes to fennel.lua, run `make ci` or
  luacheck on the source code to check for style. Please try to code moderately tersely;
  code is a liability, so the less of it there is, the better.
* For user-visible changes, include a description of the change in `changelog.md`. Changes that affect
  the compiler API should update `api.md` while changes to the built-in forms will usually need to
  update `reference.md` to reflect the new behavior.

If all goes well, we should merge your changes fairly quickly.

## Suggesting Changes

Informal discussion of changes is easiest on the IRC channel, but the mailing list can also be good
for this. More serious proposals should go on the mailing list or a GitHub issue. There is a
possibility that there is already a solution for your problems so be sure that there is a good use
case for your changes before opening an issue.

* Include a good description of the problem that is being solved
* Include descriptions of potential solutions if you have some in mind.
* Add the appropriate tags to the issue. For new features, add the `enhancement` tag.

[1]: https://man.sr.ht/git.sr.ht/send-email.md
[2]: https://lists.sr.ht/%7Etechnomancy/fennel
