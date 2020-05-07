# Setting up Fennel

This document will guide you through setting up Fennel on your
computer. This document assumes you know how to download a Git
repository, and edit configuration files in a UNIX-like environment.

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

* You want to use a version that hasn't been released yet.
* You want to contribute changes to Fennel.
* You have Git installed and don't want to bother with another system.

Run `git clone https://github.com/bakpakin/Fennel` in a shell. This
will create a directory called "Fennel" in your current directory.

At this time it's recommended to add the "Fennel" directory to your
shell's `$PATH` in order to be able to run the `fennel` command from
anywhere.

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

## Embedding the compiler (TODO)

## Ahead of time compilation (TODO)

# Making games in Fennel with LOVE

[LOVE](https://love2d.org/) is a beginner-friendly, game-making
library for the Lua programming language. The LOVE website contains [a
wiki](https://love2d.org/wiki/Main_Page) with helpful game-making
information related to game-programming in LOVE. Because Fennel
compiles to Lua, this can be used with Fennel.

Compared to using TIC-80, LOVE is much more flexible. However, the
cost of this flexibility is that it's a lot more complicated. LOVE
allows you to use a lot more 3rd-party libraries and tools, whereas
TIC-80 includes built-in tools for graphics and music. Both tools
offer cross-platform support across Windows, Mac, and Linux systems,
but TIC-80 games can be played in the browser and LOVE games cannot.

## Using Fennel in TIC-80

TODO

### To use Fennel in TIC-80

TODO: Maybe a link to the TIC-80 wiki?

# Expanding your Fennel development experience

TODO: Introduce concept
TODO: Explain one of the following:

* How does this benefit the user?
* What significance does this have to the user?
* What's in it for the user? WIIFM (What's in it for me? (for the user))

Provide a section outline with the names of all the subsections using the following phrase:

This section consists of the following subections:

* [Adding Fennel support to Emacs](#adding-fennel-support-to-emacs)
* [Adding Fennel support to Vim](#adding-fennel-support-to-vim)
* [Adding Fennel support to Neovim](#adding-fennel-support-to-neovim)
* [Adding readline support to Fennel](#adding-readline-support-to-fennel)

## Adding Fennel support to Emacs

This section will guide you through adding syntax highlighting,
indentation support, and REPL integration into Emacs. These features
will make Fennel code easier to read, save you time on indenting, and
create an interactive experience when writing Fennel code.

### To add Fennel support to Emacs

1. TODO
2. TODO
3. TODO

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
