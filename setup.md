# Setting up Fennel

This document will guide you through setting up Fennel on your
computer. This document assumes you know how to run shell commands and
edit configuration files in a UNIX-like environment.

Fennel can be used in non-UNIX environments, but those environments
will not be covered in this document.

# Downloading and installing Fennel

Downloading and installing Fennel on your system allows you to run
Fennel scripts. Currently, you can download and install Fennel using
Git or LuaRocks.

Depending on which method you want to use, choose a subsection below:

* [Installing directly](#installing-directly)
* [Using Git to download Fennel](#using-git-to-download-and-install-fennel)
* [Using LuaRocks to download Fennel](#using-luarocks-to-download-and-install-fennel)

**Tip**: If you are using software that supports Fennel, such as
[TIC-80](https://tic.computer), you do not need to download Fennel,
because you can use it inside of TIC-80.

## Installing directly

If you have Lua (5.1, 5.2, 5.3, or LuaJIT) installed on your system
you can download the Fennel script easily, but updates will have to be
done manually.

### To install directly

1. Download [the fennel script](https://fennel-lang.org/downloads/fennel-0.4.1)
3. Run `chmod +x fennel-0.4.1` to make it executable
4. Download [the signature](https://fennel-lang.org/downloads/fennel-0.4.1.asc)
5. Confirm it using `gpg --verify fennel-0.4.1.asc`
3. Move `fennel-0.4.1` to a directory on your `$PATH`, such as `/usr/local/bin`

You can rename the script to just `fennel` for convenience. If you
don't have Lua installed, you can get one of the standalone binaries
instead if there is one provided for your system:

* [GNU/Linux x86_64](https://fennel-lang.org/downloads/fennel-0.4.1-x86_64) ([signature](https://fennel-lang.org/downloads/fennel-0.4.1-x86_64.asc))
* [GNU/Linux arm32](https://fennel-lang.org/downloads/fennel-0.4.1-arm32) ([signature](https://fennel-lang.org/downloads/fennel-0.4.1-arm32.asc))
* [Windows x86 32-bit](https://fennel-lang.org/downloads/fennel-0.4.1-windows32.exe) ([signature](https://fennel-lang.org/downloads/fennel-0.4.1-windows32.exe.asc))

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

**Note 1**: Step 2 above will compile Fennel into a standalone script
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
3. Run one of
    - `luarocks install fennel` to install globally (requires admin or sudo)
    - `luarocks --local install fennel` to install locally (see the note below about paths)

**Note:** When using luarocks with `--local`, you'll need to ensure you have
the correct lua path values. You can run `eval $(luarocks path --bin)` from
your shell to set this correctly; see [LuaRocks path docs](https://github.com/luarocks/luarocks/wiki/path)
for details.

You can try running `fennel --help` to confirm the
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
Fennel to interact with the application, and you can reload during
development. If the application is more restricted, then compiling
Fennel code to Lua during the build process and including the Lua
output in the application may be easier.

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

**Note**: Optionally, if you want the Fennel REPL to print tables
in a more readable format, you can add `fennelview.fnl` to
your code repository. For more helpful compiler errors, you can add
`fennelfriend.fnl` to your code repository.

## Performing ahead-of-time compilation

If the target system of your application does not make it easy to add
the Fennel compiler but has Lua installed, Fennel offers ahead-of-time
compilation. This allows you to compile `.fnl` files to `.lua` files
before shipping an application.

This section will guide you through updating a `Makefile` to perform
this compilation for you.

### To perform ahead-of-time compilation

1. Add the following lines to your `Makefile`:

```
%.lua: %.fnl fennel
	./fennel --compile $< > $@
```

2. Ensure your build target depends on the `.lua` files you need.

**Note 1**: Ahead-of-time compilation is also useful if what you are
working with requires optimal startup time. "Fennel compiles fast,
but not as fast as not having to compile." -- jaawerth

**Note 2**: It's recommended you include the `fennel` script in your
repository to get consistent results rather than relying on an
arbitrary version of Fennel that is installed on your machine at the
time of building.

# Expanding your Fennel development experience

You can write Fennel code in any editor, but some editors make it more
comfortable than others. Most people find support for syntax
highlighting, automatic indentation, and delimiter matching
convenient, as working without these features can feel tedious.

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
* [Adding Fennel support to Visual Studio Code](#adding-fennel-support-to-visual-studio-code)
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

The [fennel.vim](https://github.com/bakpakin/fennel.vim) plugin offers
syntax highlighting and indentation support.

## Adding Fennel support to Neovim

* For syntax highlighting and indentation, install [fennel.vim](https://github.com/bakpakin/fennel.vim)
* To spin up a REPL in the terminal buffer, you can install a REPL plugin like [iron.nvim](https://github.com/Vigemus/iron.nvim)
and follow the documentation to add fennel as an executable REPL command.

## Adding Fennel support to Visual Studio Code

Search in the built-in extension manager for "Fennel" to install
[the vsc-fennel extension](https://github.com/kongeor/vsc-fennel). At
the time of this writing it only provides syntax support.

## Adding readline support to Fennel

The command-line REPL that comes with the `fennel` works out of the box, but
the built-in line-reader is very limited in user experience. Adding
[GNU Readline](https://tiswww.case.edu/php/chet/readline/rltop.html) support
enables such user-friendly features as

- Tab completion on the REPL that can complete on all locals, macros, and special forms
- A rolling history buffer, which can be navigated, searched (`ctrl+r`), and optionally
persisted to disk so you can search input from previous REPL sessions.
- emacs (default) or vi emulation via readline's custom support for better line
navigation
- Optional use of additional readline features in `~/.inputrc`, such as blinking
on matched parentheses or color color output (described below)

### Requirements for readline support

All you need to enable readline support is:

* GNU Readline installed on your system (installation steps vary for
  different operating systems, but you may already have it!)
* [readline.lua](https://pjb.com.au/comp/lua/readline.html) lua bindings to libreadline

The stock Fennel REPL will automatically load and use the readline bindings when
it can resolve the `readline` module, so that's all you need to get started.

### Installing readline.lua

For the official support on getting readline.lua, see the
[official docs](https://pjb.com.au/comp/lua/readline.html#installation).

The easiest way to get readline.lua is to install it with Luarocks, which
will fetch the package and automatically compile the native bindings for you.
If you don't want to use LuaRocks, you can do a
[manual install](https://pjb.com.au/comp/lua/readline.html#installation).

#### Installing readline with LuaRocks

```bash
# to install globally on the system (requires admin privileges or sudo)
$ luarocks install readline

# to install to the user's local tree
$ luarocks install --local readline

# install for Lua 5.1 (including LuaJIT)
$ luarocks install --lua-version=5.1 readline
```

Because the readline Lua module contains native bindings to libreadline, be sure
it's installed for the Lua version you intend to use.

**Note:** If you've installed with the `--local` flag, you may need to ensure your `package.path`
and `package.cpath` contain its location. See the
[note on LuaRocks installation](#using-luarocks-to-download-and-install-fennel) for details.

### Configuring readline for an enhanced experience

Readline itself has a number of configuration options, which can be set either
via the readline.lua API in `fennelrc`, or in readline's own `~/.inputrc` config file.

#### Enabling persistent history

To configure the REPL to save the rolling history to file at the end of every
session, add the following to your `fennelrc` with your desired filename:

See the readline.lua documentation for information on its API, most notably
other parameters that can be set via
[rl.set_options](https://pjb.com.au/comp/lua/readline.html#set_options).

```fennel
; persist repl history
(match package.loaded.readline
  rl   (rl.set_options {:histfile  "~/.fennel_history" ; default:"" (don't save)
                        :keeplines 1000}))             ; default:1000
```

#### Configuring readline in `~/.inputrc`

See the [documentation on the readline init file](https://www.gnu.org/software/bash/manual/html_node/Readline-Init-File.html)
for the full set of options and a sample inputrc.

As of Fennel 0.4.0 and readline.lua 2.6, you can make use of a [conditional
directive your `inputrc`](https://www.gnu.org/software/bash/manual/html_node/Conditional-Init-Constructs.html#Conditional-Init-Constructs)
for fennel-only configuration options. 

The following example adds these behaviors:
- Blink on a matching parenthesis when entering `)`. Useful in a Lisp REPL, where
the parens are plentiful!
- Enable bracketed paste mode for more reliable pasting from clipboard
- When tab-completing on a term with more than one possible match, display all
candidates immediately instead of ringing the bell + requiring a second `<tab>`

```inputrc
# requires Fennel >= 0.4.0 and readline.lua >= 2.6
$if fennel
  set enable-bracketed-paste on
  set blink-matching-paren on
  set show-all-if-ambiguous on
$endif
```

# Making games in Fennel

The two main platforms for making games with Fennel are
[TIC-80](https://tic.computer) and [LÖVE](https://love2d.org/).

TIC-80 is software that acts as a computer in which you can write
code, design art, compose music, and lay out maps for games. TIC-80
also makes it easy for you to publish and share the games you make
with others. TIC-80 introduces restrictions such as low resolution and
limited memory to emulate retro game styles.

LÖVE is a game-making framework for the Lua programming
language. Because Fennel compiles to Lua, you can reference the [LÖVE
wiki](https://love2d.org/wiki/Main_Page) when making games with Fennel.
LÖVE is more flexible than TIC-80 in that it allows you to import from
external resources and use any resolution or memory you like, but at
a cost in that it is more complicated to make games in.

Both TIC-80 and LÖVE offer cross-platform support across Windows, Mac,
and Linux systems, but TIC-80 games can be played in the browser and
LÖVE games cannot.

This section consists of the following subsections:

* [Using Fennel in TIC-80](#using-fennel-in-tic-80)
* [Using Fennel with LÖVE](#using-fennel-with-love)

The [Fennel wiki](https://github.com/bakpakin/Fennel/wiki#games) links
to many games made in both systems you can study.

## Using Fennel in TIC-80

Support for Fennel is built into TIC-80. If you want to use the
built-in text editor, you don't need any other tools, just launch
TIC-80 and run `new fennel` to get started.

* The [TIC-80 wiki](https://github.com/nesbox/TIC-80/wiki) documents
  the functions to use and important concepts.
* See this [project skeleton repo](https://github.com/stefandevai/fennel-tic80-game)
  for information on using external editors, instead of the built-in
  TIC-80 editor.

All TIC-80 games allow you to view and edit the source and assets. Try
loading this [Conway's Life](https://tic.computer/play?cart=656) game
to see how it's made:

* Click "start" to begin
* Press the Esc key to open a menu
* Use the arrow keys to navigate the menu
* Press the Z key to open the console, followed by Esc to see the
  source code.

## Using Fennel with LÖVE

LÖVE has no built-in support for Fennel, so you will need to setup support yourself.

This [project skeleton for LÖVE](https://gitlab.com/alexjgriffith/min-love2d-fennel)
shows you how to setup support for Fennel and how to setup a
console-based REPL for debugging your game while it runs.
