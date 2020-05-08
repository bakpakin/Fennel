# Setting up Fennel

This document will guide you through setting up Fennel on your
computer. This document assumes you know how to download a Git
repository and edit configuration files in a UNIX-like environment.

## Requirements

* Access to a UNIX-like environment, such as Ubuntu, Debian, Arch
  Linux, Windows Subsystem for Linux, Homebrew, scoop.sh, etc.
* Lua version 5.1, 5.2, 5.3, or LuaJIT
* LuaRocks or Git

Note that Fennel can be used on non-Unix systems, but that is out of
scope for this document.

# Downloading Fennel

Currently, you can either download Fennel from
[https://github.com/bakpakin/Fennel](https://github.com/bakpakin/Fennel)
or use LuaRocks to download Fennel. On certain operating systems, you
might have Fennel available from your system package manager, but that is
out of scope for this document.

Depending on which method you want to use, choose a subsection below:

* [Using Git to download Fennel](#using-git-to-download-fennel)
* [Using LuaRocks to download Fennel](#using-luarocks-to-download-fennel)

**Tip**: If you are using an application that already has Fennel
built-in (such as [TIC-80](https://tic.computer)) you might not need
to download Fennel at all.

## Using Git to download Fennel

You may want to use Git to install if:

* You want to use a version that hasn't been released yet
* You want to contribute changes to Fennel
* You have Git installed and don't want to bother with another system

To install:

1. Change to the directory where you keep source checkouts (eg `~/src`)
2. Run `git clone https://github.com/bakpakin/Fennel` in a shell
3. Change directories with `cd Fennel`
4. Run `make fennel` to compile Fennel into a standalone script
5. Copy or link `fennel` to a location on your shell's `$PATH` (eg
   `~/bin` or `/usr/local/bin`)

## Using LuaRocks to download Fennel

[LuaRocks](https://luarocks.org/) contains a repository of Lua
packages. It allows you to download and install packages and automates
installation steps.

1. Open up a shell
2. Ensure the `luarocks` package is installed on your system
3. Ensure the `~/.luarocks/bin` directory is added to your shell's `$PATH`
4. Run `luarocks --local install fennel`

You can try running `fennel --help` to confirm the installation succeeded.

# Embedding Fennel

Installing Fennel on your system will allow you to run scripts written
in pure Fennel. However, for more complex situations it's common to
embed Fennel code inside a larger application. You can do this in two
ways: including the Fennel compiler or performing ahead-of-time compilation.

Including the Fennel compiler is a much more flexible way to go, and
it's recommended that you go this route if you can. This allows you to
offer extensibility features that let your users write their own
Fennel scripts to automate your application. However, if you are
working with an application that has more restrictions, it may be
simpler to compile your Fennel code to Lua during the build process
and only include the Lua output in the application.

## Embedding the compiler

Add `fennel.lua` to your repository, then you can load it from Lua like so:

```lua
local fennel = require("fennel")
table.insert(package.loaders or package.searchers, fennel.searcher)
local mylib = require("mylib") -- will compile and load code in mylib.fnl
```

You can call any function defined in Fennel code from Lua with zero
overhead, and vice versa.

In order to get the repl to be able to print tables correctly, you
probably also want to add `fennelview.fnl`. In order to improve the
compiler errors, you can add `fennelfriend.fnl`. However, both these
modules are optional.

## Ahead of time compilation

If you need to ship `.lua` files in your program, you can use `make`
to perform the compilation. Add this to your `Makefile`:

```
%.lua: %.fnl fennel
	./fennel --compile $< > $@
```

It's recommended you include `fennel` itself in your repository so that
you will always get consistent results rather than relying on whatever
version of Fennel is installed on your machine at the time of building.

# Making games in Fennel

The two main platforms for making games with Fennel are
[LOVE](https://love2d.org/) and [TIC-80](https://tic.computer).

LOVE is a game-making framework for the Lua programming language. The
LOVE website contains [a wiki](https://love2d.org/wiki/Main_Page) with
helpful game-making information related to game-programming in LOVE.

Compared to using TIC-80, LOVE is much more flexible. In TIC-80, you
can only use one specific low resolution, and you create all the
graphics and sounds yourself inside TIC, while LOVE lets you import
from external sources and use any resolution. However, the cost of
this flexibility is that it's a lot more complicated. Both tools offer
cross-platform support across Windows, Mac, and Linux systems, but
TIC-80 games can be played in the browser and LOVE games cannot.

## Using Fennel in TIC-80

Support for Fennel is built-in. If you want to use the built-in text
editor, you don't need any other tools, just launch TIC-80 and run
`new fennel` to get started.

But if you want to see an example, this
[Conway's Life](https://tic.computer/play?cart=656) implementation
could be a good starting point. Click start, press ESC, use the arrows
to go down to "close game", and press Z to go to the console. Then
press ESC to see the source.

The [TIC-80 wiki](https://github.com/nesbox/TIC-80/wiki) is an
indispensable documentation resource.

If you would prefer to use an external editor, this
[project skeleton repo](https://github.com/stefandevai/fennel-tic80-game)
provides some helpful support.

## Using Fennel with LOVE

LOVE has no built-in support for Fennel, so you need to bring it yourself.
This [project skeleton repo](https://gitlab.com/alexjgriffith/min-love2d-fennel)
for LOVE shows you how to do that, including a console-based REPL for
debugging and reloading.

# Expanding your Fennel development experience

You can write Fennel code in any editor, but some make it more
convenient than others. Most people find that you want at least some
level of support for syntax highlighting, automatic indentation, and
matching delimiters, as working without these can feel very tedious.

Other editors support advanced features like an integrated REPL,
reloading, documentation lookup, and jumping to source definitions.

If your favorite editor isn't listed here, that's OK; stick with what
you're most comfortable. You can usually get decent results by telling
your editor to treat Fennel files as if they were Clojure or Scheme.

This section consists of the following subections:

* [Adding Fennel support to Emacs](#adding-fennel-support-to-emacs)
* [Adding Fennel support to Vim](#adding-fennel-support-to-vim)
* [Adding Fennel support to Neovim](#adding-fennel-support-to-neovim)
* [Adding readline support to Fennel](#adding-readline-support-to-fennel)

## Adding Fennel support to Emacs

Installing [fennel-mode](https://gitlab.com/technomancy/fennel-mode/)
gives you syntax highlighting, indentation, paren-matching, a repl,
reloading, documentation lookup, and jumping to source definitions.

It's one file, so it is easy to install from source on use your
package manager; see
[the readme](https://gitlab.com/technomancy/fennel-mode/-/blob/master/Readme.md)
for details.

## Adding Fennel support to Vim

TODO: Introduce concept
TODO: Explain one of the following:

* How does this benefit the user?
* What significance does this have to the user?
* What's in it for the user? WIIFM (What's in it for me? (for the user))

### To add Fennel support to Vim

1. TODO
2. TODO
3. TODO

## Adding Fennel support to Neovim

TODO: Introduce concept
TODO: Explain one of the following:

* How does this benefit the user?
* What significance does this have to the user?
* What's in it for the user? WIIFM (What's in it for me? (for the user))

### To add Fennel support to Neovim

1. TODO
2. TODO
3. TODO

## Adding readline support to Fennel

TODO: Introduce concept
TODO: Explain one of the following:

* How does this benefit the user?
* What significance does this have to the user?
* What's in it for the user? WIIFM (What's in it for me? (for the user))

### To add readline support to Fennel

1. TODO
2. TODO
3. TODO
