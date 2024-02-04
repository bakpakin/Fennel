# Setting up Fennel

This document will guide you through setting up Fennel on your
computer. This document assumes you know how to run shell commands and
edit configuration files in a UNIX-like environment.

**Note**: Fennel can be used in non-UNIX environments, but those environments
will mostly not be covered in this document.

Fennel does not contain any telemetry/spyware and never will.


## Downloading Fennel

Downloading Fennel on your computer allows you to run Fennel code and
compile to Lua. You have a few options for how to install Fennel.


### Downloading Fennel with a package manager

Depending on what package manager you use on your system, you may be
able to use it to install Fennel. See [the
wiki](https://wiki.fennel-lang.org/Packaging) for a list of packaging
systems which offer Fennel. Packaged versions of Fennel may lag behind
the official releases and often only support one version at a time,
but they tend to be the most convenient. For instance, if you use
Fedora, it should be as easy as running `sudo dnf install fennel`.


### Downloading the fennel script

This method assumes you have Lua 5.1, 5.2, 5.3, 5.4, or LuaJIT
installed on your system.

This method requires you to manually update the `fennel` script when
you want to use a newer version that has come out.

 1. Download [the fennel script](https://fennel-lang.org/downloads/fennel-1.4.0)
 2. Run `chmod +x fennel-1.4.0` to make it executable
 3. Download the [signature](https://fennel-lang.org/downloads/fennel-1.4.0.asc)
    and confirm it matches using `gpg --verify fennel-1.4.0*.asc`
    (optional but recommended).
 4. Move `fennel-1.4.0` to a directory on your `$PATH`, such as `/usr/local/bin`

**Note**: You can rename the script to `fennel` for convenience. Or
you can leave the version in the name, which makes it easy to keep
many versions of Fennel installed at once.


### Downloading a Fennel binary

Downloading a Fennel binary allows you to run Fennel on your computer without
having to download Lua, if you are on a supported platform. If you
already have Lua installed, it's better to use the script above.

This method requires you to manually update the `fennel` binary when
you want to use a newer version that has come out.

 1. Choose one the options below, depending on your system:
      - [GNU/Linux x86_64](https://fennel-lang.org/downloads/fennel-1.4.0-x86_64)
        ([signature](https://fennel-lang.org/downloads/fennel-1.4.0-x86_64.asc))
      - [GNU/Linux arm32](https://fennel-lang.org/downloads/fennel-1.4.0-arm32)
        ([signature](https://fennel-lang.org/downloads/fennel-1.4.0-arm32.asc))
      - [Windows x86 32-bit](https://fennel-lang.org/downloads/fennel-1.4.0-windows32.exe)
        ([signature](https://fennel-lang.org/downloads/fennel-1.4.0-windows32.exe.asc))
 2. Run `chmod +x fennel-1.4.0*` to make it executable
 3. Download the signature and confirm it matches using `gpg --verify fennel-1.4.0*.asc`
    (optional but recommended).
 4. Move the downloaded binary to a directory on your `$PATH`, such as `/usr/local/bin`


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
access the disk to load further files) then compiling Fennel code to
Lua during the build process and including the Lua output in the
application may be easier.

There are so many ways to distribute your code that we can't cover
them all here; please [see the wiki page on distribution for details](https://wiki.fennel-lang.org/Distribution).


### Embedding the Fennel compiler in a Lua application

The Fennel compiler can be added to your code repository, and then
loaded from Lua.

 1. Get the `fennel.lua` library. You can get this from a
    [release tarball](https://fennel-lang.org/downloads/fennel-1.4.0.tar.gz)
    or by running `make` in a source checkout.
 2. Add `fennel.lua` to your code repository.
 3. Add the following lines to your Lua code:

```lua
require("fennel").install().dofile("main.fnl")
```

You can pass [options](api.md) to the fennel compiler by passing a
table to the `install` function.

Be sure to use the `fennel.lua` library and not the file for the
entire `fennel` executable.

### Performing ahead-of-time compilation

If the target system of your application does not make it easy to add
the Fennel compiler but has Lua installed, Fennel offers ahead-of-time
(AOT) compilation. This allows you to compile `.fnl` files to `.lua`
files before shipping an application.

This section will guide you through updating a `Makefile` to perform
this compilation for you; if you use a different build system you can
adapt it.

 1. Add the following lines to your `Makefile`:

    ```
    %.lua: %.fnl fennel
    	./fennel --compile $< > $@
    ```

 2. Ensure your build target depends on the `.lua` files you need, for
    example, if every `.fnl` file has a corresponding `.lua` file:

    ```
    SRC := $(wildcard *.fnl)
    OUT := $(patsubst %.fnl,%.lua,$(SRC))
    myprogram: $(OUT)
        [...]
    ```


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

See [the wiki](https://wiki.fennel-lang.org/Editors)
for a list of editors that have Fennel support.

If your editor supports the Language Server Protocol (LSP) then you
can install [fennel-ls](https://git.sr.ht/~xerool/fennel-ls) to get
highlighting of errors and improved navigation.


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

See [the wiki page on readline](https://wiki.fennel-lang.org/Readline)
for details of how to install and configure it on your system.

## Making games with Fennel

The two main platforms for making games with Fennel are
[TIC-80](https://tic80.com) and [LÖVE](https://love2d.org/).

TIC-80 is software that acts as a simulated computer in which you can write
code, design art, compose music, and lay out maps for games. TIC-80
also makes it easy for you to publish and share the games you make
with others. TIC-80 introduces restrictions such as low resolution and
limited memory to emulate retro game styles.

LÖVE is a game-making framework for the Lua programming language. LÖVE
is more flexible than TIC-80 in that it allows you to import from
external resources and use any resolution or memory you like, but at a
cost in that it is more complicated to make games in and more
difficult to run in the browser.

Both TIC-80 and LÖVE offer cross-platform support across Windows, Mac,
and Linux systems, but TIC-80 games can be played in the browser and
LÖVE games cannot without more complex 3rd-party tools.

The [Fennel wiki](https://wiki.fennel-lang.org/Codebases) links
to many games made in both systems you can study.


### Using Fennel in TIC-80

Support for Fennel is built into TIC-80. If you want to use the
built-in text editor, you don't need any other tools, just launch
TIC-80 and run `new fennel` in its console to get started.

The [TIC-80 wiki](https://github.com/nesbox/TIC-80/wiki) documents
the functions to use and important concepts.

All TIC-80 games allow you to view and edit the source and assets. Try
loading this [Conway's Life](https://tic80.com/play?cart=656) game
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

You can reference the [LÖVE wiki](https://love2d.org/wiki/Main_Page)
for Lua-specific documentation. Use [See Fennel](/see) to see how any
given Lua snippet would look translated to Fennel.
