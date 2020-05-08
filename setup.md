# Setting up Fennel

This document will guide you through setting up Fennel on your
computer. This document assumes you know how to download a Git
repository and edit configuration files in a UNIX-like environment.

Fennel can be used in non-UNIX environments, but those environments
will not be covered in this document.

# Requirements

* Access to a UNIX-like environment, such as Ubuntu, Debian, Arch
  Linux, Windows Subsystem for Linux, Homebrew, scoop.sh, etc.
* Lua version 5.1, 5.2, 5.3, or LuaJIT
* LuaRocks or Git

# Downloading and installing Fennel

Downloading and installing Fennel on your system allows you to run
Fennel scripts. Currently, you can download and install Fennel using
Git or LuaRocks.

Depending on which method you want to use, choose a subsection below:

* [Using Git to download Fennel](#using-git-to-download-fennel)
* [Using LuaRocks to download Fennel](#using-luarocks-to-download-fennel)

**Tip**: If you are using software that supports Fennel, such as
[TIC-80](https://tic.computer), you do not need to download Fennel,
because you can use it inside of TIC-80.

## Using Git to download and install Fennel

Downloading and installing Fennel using Git allows you to use versions
of Fennel that haven't been released yet and makes contributions to
Fennel easier.

### To download Fennel

1. `cd` to a directory in which you want to download Fennel, such as
   `~/src`
2. Run `git clone https://github.com/bakpakin/Fennel`

### To install Fennel

1. Run `cd Fennel`
2. Run `make fennel`
3. Copy or link the `fennel` script to a directory on your `$PATH`,
   such as `/usr/local/bin`

**Note 1**: `Step 2.` above will compile Fennel into a standalone script
called `fennel`.

**Note 2**: If the `fennel` script exists in one of the directories on
your `$PATH` , you can run `fennel filename.fnl` to run a Fennel file.

## Using LuaRocks to download and install Fennel

[LuaRocks](https://luarocks.org/) contains a repository of Lua
software packages. LuaRocks is convenient because it automates the
downloading, installation, and uninstallation of Lua software packages.

### To download and install Fennel

1. Ensure the `luarocks` package is installed on your system
2. Ensure the `~/.luarocks/bin` directory is added to your shell's `$PATH`
3. Run `luarocks --local install fennel`

**Note**: You can try running `fennel --help` to confirm the
installation succeeded.

# Embedding Fennel

Fennel code can be embedded inside of Lua applications by including the
Fennel compiler inside of a Lua application, or by performing
ahead-of-time compilation.

This section consists of the following subsections:

* [Embedding the Fennel compiler in a Lua application](#embedding-the-fennel-compiler-in-a-lua-application)
* [Performing ahead-of-time compilation](#performing-ahead-of-time-compilation)

**Note**: Embedding the Fennel compiler in an application is the more
flexible option, and is recommended. By embedding the Fennel compiler
in an application, users can write their own extension scripts in
Fennel to interact with the application. If the application is more
restricted, then compiling Fennel code to Lua during the build
process, and including the Lua output in the application may be
easier.

## Embedding the Fennel compiler in a Lua application

The Fennel compiler can be added to your code repository, and then
loaded from Lua. 

### To embed the Fennel compiler in a Lua application

1. Add `fennel.lua` to your code repository
2. Add the following lines to your Lua code:

```lua
local fennel = require("fennel")
table.insert(package.loaders or package.searchers, fennel.searcher)
local mylib = require("mylib") -- will compile and load code in mylib.fnl
```

**Note**: Optionally, if you want the Fennel REPL to print tables and
other data in a more readable format, you can add `fennelview.fnl` to
your code repository. For more helpful compiler errors, you can add
`fennelfriend.fnl` to your code repository.

## Performing ahead-of-time compilation

If the target system of your application does not have Fennel
installed, but has Lua installed, Fennel offers ahead-of-time
compilation. This allows you to compile `.fnl` files to `.lua` files
before shipping an application.

This section will guide you through creating a `Makefile` to perform
this compilation for you.

### To perform ahead-of-time compilation

1. Run `touch Makefile`
2. Add the following lines to the `Makefile`:

```
%.lua: %.fnl fennel
	./fennel --compile $< > $@
```

3. Run `make` to perform the compilation

**Note 1**: Ahead-of-time compilation is also useful if what you are
working with requires optimal startup time. "Fennel compiles fast,
but not as fast as not having to compile" -- jaawerth

**Note 2**: It's recommended you include the `fennel` script in your
repository to get consistent results rather than relying on an
arbitrary version of Fennel that is installed on your machine at the
time of building.

# Making games in Fennel

The two main platforms for making games with Fennel are
[TIC-80](https://tic.computer) and [LOVE](https://love2d.org/).

TIC-80 is software that acts as a computer in which you can write
code, design art, compose music, and lay out maps for games. TIC-80
also makes it easy for you to publish and share the games you make
with others. TIC-80 creates restrictions, such as low resolution and
memory to emulate old games.

LOVE is a game-making framework for the Lua programming
language. Because Fennel compiles to Lua, you can reference the [LOVE
wiki](https://love2d.org/wiki/Main_Page) when making games with Fennel.
LOVE is more flexible than TIC-80 in that it allows you to import from
external resources and use any resolution or memory you like, but at
a cost in that it is more complicated to make games in.

Both TIC-80 and LOVE offer cross-platform support across Windows, Mac,
and Linux systems, but TIC-80 games can be played in the browser and
LOVE games cannot.

This section consists of the following subsections:

* [Using Fennel in TIC-80](#using-fennel-in-tic-80)
* [Using Fennel with LOVE](#using-fennel-with-love)

## Using Fennel in TIC-80

Support for Fennel is built into TIC-80. If you want to use the
built-in text editor, you don't need any other tools, just launch
TIC-80 and run `new fennel` to get started.

For references , see the Links below:

* [Conway's Life](https://tic.computer/play?cart=656): Implementing
  this would be a good learning exercise.
    * Click "start" to begin
    * Press the Esc key to open a menu
    * Use the arrow keys to navigate the menu
    * Press the Z key to open the console, followed by Esc to see the
      source code.
* [The TIC-80 wiki](https://github.com/nesbox/TIC-80/wiki)
* [project skeleton repo](https://github.com/stefandevai/fennel-tic80-game) for
  information on using external editors, instead of the built-in
  TIC-80 editor.

## Using Fennel with LOVE

LOVE has no built-in support for Fennel, so you will need to setup support yourself.

This [project skeleton for LOVE](https://gitlab.com/alexjgriffith/min-love2d-fennel)
shows you how to setup support for Fennel and how to setup a
console-based REPL for debugging your game while it runs.

# Expanding your Fennel development experience

You can write Fennel code in any editor, but some editors make it more
convenient than others. Most people find support for syntax
highlighting, automatic indentation, and delimiter matching
convenient, as working without these features can feel very tedious.

Other editors support advanced features like an integrated REPL, live
reloading while you edit the program, documentation lookups, and
jumping to source definitions.

If your favorite editor isn't listed here, that's OK; stick with what
you're most comfortable. You can usually get decent results by telling
your editor to treat Fennel files as if they were Clojure or Scheme
files.

This section consists of the following subections:

* [Adding Fennel support to Emacs](#adding-fennel-support-to-emacs)
* [Adding Fennel support to Vim](#adding-fennel-support-to-vim)
* [Adding Fennel support to Neovim](#adding-fennel-support-to-neovim)
* [Adding readline support to Fennel](#adding-readline-support-to-fennel)

## Adding Fennel support to Emacs

Installing [fennel-mode](https://gitlab.com/technomancy/fennel-mode/)
gives you syntax highlighting, indentation, paren-matching, a repl,
reloading, documentation lookup, and jumping to source definitions.

### To add Fennel support to Emacs

See the `Readme.md`
[here](https://gitlab.com/technomancy/fennel-mode/-/blob/master/Readme.md)
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
