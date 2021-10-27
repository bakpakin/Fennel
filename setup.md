# Setting up Fennel

This document will guide you through setting up Fennel on your
computer. This document assumes you know how to run shell commands and
edit configuration files in a UNIX-like environment.

**Note**: Fennel can be used in non-UNIX environments, but those environments
will not be covered in this document.


## Downloading Fennel

Downloading Fennel on your computer allows you to run Fennel code and
compile to Lua. You have a few options for how to install Fennel.


### Downloading the fennel script

Downloading the `fennel` script allows you to place the script in
convenient locations for running Fennel code.

This method assumes you have Lua 5.1, 5.2, 5.3, 5.4, or LuaJIT
installed on your system.

This method requires you to manually update the `fennel` script when
you want to use a newer version that has come out.

 1. Download [the fennel script](https://fennel-lang.org/downloads/fennel-0.10.0)
 2. Run `chmod +x fennel-0.10.0` to make it executable
 3. Download [the signature](https://fennel-lang.org/downloads/fennel-0.10.0.asc)
 4. Run `gpg --verify fennel-0.10.0.asc` to verify that the fennel
    script is from the Fennel creators (optional but recommended)
 5. Move `fennel-0.10.0` to a directory on your `$PATH`, such as `/usr/local/bin`

**Note**: You can rename the script to `fennel` for convenience. Or
you can leave the version in the name, which makes it easy to keep
many versions of Fennel installed at once.


### Downloading a Fennel binary

Downloading a Fennel binary allows you to run Fennel on your computer without
having to download Lua, if you are on a supported platform.

This method requires you to manually update the `fennel` binary when
you want to use a newer version that has come out.

 1. Choose one the options below, depending on your system:
      - [GNU/Linux x86_64](https://fennel-lang.org/downloads/fennel-0.10.0-x86_64)
        ([signature](https://fennel-lang.org/downloads/fennel-0.10.0-x86_64.asc))
      - [GNU/Linux arm32](https://fennel-lang.org/downloads/fennel-0.10.0-arm32)
        ([signature](https://fennel-lang.org/downloads/fennel-0.10.0-arm32.asc))
      - [Windows x86 32-bit](https://fennel-lang.org/downloads/fennel-0.10.0-windows32.exe)
        ([signature](https://fennel-lang.org/downloads/fennel-0.10.0-windows32.exe.asc))
 2. Run `chmod +x fennel-0.10.0*` to make it executable (not needed on Windows).
 3. Download the signature and confirm it matches using `gpg --verify fennel-0.10.0*.asc`
    (optional but recommended).
 4. Move the downloaded binary to a directory on your `$PATH`, such as `/usr/local/bin`


### Downloading Fennel a package manager

If you already use a package manager on your system, you may be
able to use it to install Fennel. See [the
wiki](https://github.com/bakpakin/Fennel/wiki/Packaging) for a list of
packaging systems which offer Fennel.

## Embedding Fennel

Fennel code can be embedded inside of applications that support Lua
either by including the Fennel compiler inside of the application,
or by performing ahead-of-time compilation. Embedding Fennel in a
program that doesn't already support Lua is possible but outside the
scope of this document.

**Note**: Embedding the Fennel compiler in an application is the more
flexible option, and is recommended. By embedding the Fennel compiler
in an application, users can write their own extension scripts in
Fennel to interact with the application, and you can reload during
development. If the application is more restricted, (for instance, if
you can only embed one Lua file into the application and it cannot
load further files) then compiling Fennel code to Lua during the build
process and including the Lua output in the application may be easier.


### Embedding the Fennel compiler in a Lua application

The Fennel compiler can be added to your code repository, and then
loaded from Lua.

 1. Get the `fennel.lua` library. You can get this from a
    [release tarball](https://fennel-lang.org/downloads/fennel-0.10.0.tar.gz)
    or by running `make` in a source checkout.
 2. Add `fennel.lua` to your code repository.
 3. Add the following lines to your Lua code:

```lua
local fennel = require("fennel")
table.insert(package.loaders or package.searchers, fennel.searcher)
local mylib = require("mylib") -- will compile and load code in mylib.fnl
```

Be sure to use the `fennel.lua` library and not the file for the
entire `fennel` executable.

### Performing ahead-of-time compilation

If the target system of your application does not make it easy to add
the Fennel compiler but has Lua installed, Fennel offers ahead-of-time
compilation. This allows you to compile `.fnl` files to `.lua` files
before shipping an application.

This section will guide you through updating a `Makefile` to perform
this compilation for you.

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


## Adding Fennel support to your text editor

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


### Adding Fennel support to Emacs

Installing [fennel-mode](https://gitlab.com/technomancy/fennel-mode/)
gives you syntax highlighting, indentation, paren-matching, a repl,
reloading, documentation lookup, and jumping to source definitions.

For more information, see [the fennel-mode
readme](https://gitlab.com/technomancy/fennel-mode/-/blob/master/Readme.md).


### Adding Fennel support to Vim

The [fennel.vim](https://github.com/bakpakin/fennel.vim) plugin offers
syntax highlighting and indentation support.


### Adding Fennel support to Neovim

  * For syntax highlighting and indentation, install
    [fennel.vim](https://github.com/bakpakin/fennel.vim)
  * To spin up a REPL in the terminal buffer, you can install a REPL plugin
    like [conjure](https://conjure.fun/).


### Adding Fennel support to Visual Studio Code

Search in the built-in extension manager for "Fennel" to install
[the vsc-fennel extension](https://github.com/kongeor/vsc-fennel). At
the time of this writing it only provides syntax highlighting.


### Adding Fennel support to [Vis](https://github.com/martanne/vis), [Textadept](https://github.com/orbitalquark/textadept), and [Howl](https://github.com/howl-editor/howl)

  * The plugins based on [lisp-parkour](https://repo.or.cz/lisp-parkour) offer
    structured editing/navigation, automatic indentation, and (very) basic REPL integration.
  * Vis and Textadept come with syntax highlighting for Fennel built in.


## Adding readline support to Fennel

The command-line REPL that comes with the `fennel` script works out of the box, but
the built-in line-reader is very limited in user experience. Adding
[GNU Readline](https://tiswww.case.edu/php/chet/readline/rltop.html)
support enables user-friendly features, such as:

  - tab-completion on the REPL that can complete on all locals, macros, and special forms
  - a rolling history buffer, which can be navigated, searched (`ctrl+r`), and optionally
    persisted to disk so you can search input from previous REPL sessions
  - Emacs (default) or vi key binding emulation via readline's custom support for better line
    navigation
  - optional use of additional readline features in `~/.inputrc`, such as blinking
    on matched parentheses or color output (described below)


### Requirements for readline support

  * GNU Readline (installation steps vary for different operating systems, but you may already have it!)
  * [readline.lua](https://pjb.com.au/comp/lua/readline.html) Lua bindings to libreadline

**Note**: The Fennel REPL will automatically load and use the
readline bindings when it can resolve the `readline` module, so that's
all you need to get started.


### Installing readline.lua with LuaRocks

The easiest way to get readline.lua is to install it with LuaRocks, which
will fetch the package and automatically compile the native bindings for you.

To install readline.lua with LuaRocks:

 1. Ensure libreadline is installed for the Lua version you intend to use.
 2. Run one of the following commands:
      - `luarocks install --local readline` (recommended)
      - `luarocks install --lua-version=5.1 readline` (for a non-default Lua version)
      - `luarocks install readline` (requires root or admin)

**Note:** If you've installed with the `--local` flag, you may need to
ensure your `package.path` and `package.cpath` contain its location.


### Configuring readline.lua

You can configure readline.lua using one of the following options:

  * the readline.lua API in `fennelrc`
  * the readline.lua `~/.inputrc` file

If you have readline installed but do not wish to use it (for example,
running Fennel inside an Emacs shell or recording a session to a file)
you can export `TERM=dumb` as an environment variable.


#### Enabling persistent history using `fennelrc`

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

The following example adds these behaviors:

  * Blink on a matching parenthesis when entering `)`. Useful in a Lisp REPL, where
    the parens are plentiful!
  * Enable bracketed paste mode for more reliable pasting from clipboard
  * When tab-completing on a term with more than one possible match, display all
    candidates immediately instead of ringing the bell + requiring a second `<tab>`

Create a `~/.inputrc` file with the following contents:

```inputrc
set enable-bracketed-paste on
set blink-matching-paren on
set show-all-if-ambiguous on
```

As of Fennel 0.4.0 and readline.lua 2.6, you can make use of a [conditional
directive your `inputrc`](https://www.gnu.org/software/bash/manual/html_node/Conditional-Init-Constructs.html#Conditional-Init-Constructs)
if you would like certain settings to only apply to Fennel.

## Making games with Fennel

The two main platforms for making games with Fennel are
[TIC-80](https://tic.computer) and [LÖVE](https://love2d.org/).

TIC-80 is software that acts as a simulated computer in which you can write
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

The [Fennel wiki](https://github.com/bakpakin/Fennel/wiki#games) links
to many games made in both systems you can study.


### Using Fennel in TIC-80

Support for Fennel is built into TIC-80. If you want to use the
built-in text editor, you don't need any other tools, just launch
TIC-80 and run `new fennel` to get started.

The [TIC-80 wiki](https://github.com/nesbox/TIC-80/wiki) documents
the functions to use and important concepts.

All TIC-80 games allow you to view and edit the source and assets. Try
loading this [Conway's Life](https://tic.computer/play?cart=656) game
to see how it's made:

  * Click "start" to begin
  * Press the Esc key and click "Close game"
  * Press Esc again to see the code


### Using Fennel with LÖVE

LÖVE has no built-in support for Fennel, so you will need to setup
support yourself, similar to [Embedding Fennel](#embedding-fennel) above.

This [project skeleton for LÖVE](https://gitlab.com/alexjgriffith/min-love2d-fennel)
shows you how to setup support for Fennel and how to setup a
console-based REPL for debugging your game while it runs.
