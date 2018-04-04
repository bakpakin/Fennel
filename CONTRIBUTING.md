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

If you want to contribute some code to the project, please submit a pull request and
follow the below guidlines. For large changes, please submit an issue first or raise the topic
on the IRC channel first before sinkning timing into something we may not merge.

* Include a description of the changes.
* If there are changes to the compiler or the language, please include tests in test.lua. You can
  run tests with `make test`, or `lua test.lua`.
* Make sure that your changes will work on Lua versions 5.1, 5.2, 5.3, and LuaJIT. Making fennel
  require LuaJIT, 5.2, or 5.3 specific features is a non-goal of the project. In general, this means
  target Lua 5.1, but provide shims for where functionality is different in newer Lua versions.
* Be consistent with the style of the project. If you are making changes to fennel.lua, run `make ci` or
  luacheck on the source code to check for style. Please try to code moderately tersely;
  code is a liability, so the less of it there is, the better.
  
## Suggesting Changes

To suggest changes, open an issue on github. You can also go to the IRC channel and ask questions
there. There is a possibility that there is already a solution for your problems so be sure that there is a good use case
for your changes before opening an issue.

* Include a good description of the problem that is being solved
* Include descriptions of potential solutions if you have some in mind.
* Add the appropriate tags to the issue. For new features, add the `enhancement` tag.
  
If all goes well, we should merge your changes fairly quickly.
