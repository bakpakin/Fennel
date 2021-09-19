# Summary of user-visible changes

Changes are **marked in bold** which could result in backwards-incompatibility.

## 1.0.0 / ???

### New Features
* Support `--rename-native-module` when compiling binaries
* Add `:into` clause to `collect` and `icollect`
* Add Macro guide
* Improve consistency of table key ordering in compiled output
* Apply strict globals checking in the repl by default
* Allow strict globals checking to be disabled with `--globals "*"`
* Emit warning when `--require-as-include` fails to find a module to include

### Bug Fixes
* Fix a bug where macro modules did not get compiler options propagated

### Changes and Removals
* **Enforce compiler sandbox** by default instead of warning
* **Disallow &** in identifiers
* Implicit else branches in `if` are treated as nil, **not zero values**


## 0.10.0 / 2021-08-07

It's Fennel's 5th birthday! We've got the new `accumulate` macro for
reducing over tables, plus a couple new repl commands and more
flexibility when using `include`.

### New Forms
* Add `accumulate` macro for reduce operations

### New Features
* Add `--skip-include` option to prevent modules from being included in output
* Add `,apropos pattern` and `,apropos-doc pattern` repl commands
* Add `,complete foo` repl command
* Add `fennel.syntax` function describing built-ins
* Add `-c` alias for `--compile` in command line arguments
* Allow using expressions in `include` and make `--require-as-include`
  resolve module names dynamically.  See the require section in the reference
* Support repl completion on methods
* Make macro tables shadow runtime tables more consistently
* Keep gaps when printing sparse sequences; see `max-sparse-gap`
  option in `fennel.view`

### Bug Fixes
* Fix a bug with strict global checking in macro modules

### Changes and Removals
* Deprecate `pick-args` macro
* **Add separate `fennel.macro-path` for searching for macro modules
  and `FENNEL_MACRO_PATH` environment variable**


## 0.9.2 / 2021-05-02

This release mostly contains small bug fixes.

### New Features
* Add Fennel for Clojure Users guide
* Never treat `_ENV` as an unknown global
* Improve behavior of `?.` when used directly on nil

### Bug Fixes
* Fix multi-value destructuring in pattern matches that use `where`
* Fix a bug around disambiguating parens in method calls
* Fix a bug where line number correlation was thrown off in macros
* Fix a bug where `--use-bit-lib` was not propagating to the REPL

## 0.9.1 / 2021-04-10

This release contains one small bug fix.

### Bug Fixes
* Fix a bug in compiled output for statement separators in LuaJIT


## 0.9.0 / 2021-04-08

The biggest change in this release is the addition of the `:until`
clause in all iteration forms to end iteration early.

### New Forms
* Add nil-safe table access operator `?.`
* Add support for guards using `where`/`or` clauses in `match`

### New Features
* Add `--use-bit-lib` flag to allow bitwise operations to work in LuaJIT
* Add `macro-searchers` table for finding macros similarly to `package.searchers`
* Support `&as` inside pattern matches
* Include stack trace for errors during macroexpansion
* The `sym` function in compile scope now takes a source table second argument
* Support `:until` clauses for early termination in all loops
* Support `:escape-newlines?` and `:prefer-colon?` options in fennel.view
* Allow symbols to compare as equal in macros based on name

### Bug Fixes
* Fix a bug where newlines were emitted with backslashes in fennel.view
* Fix a bug in the compiler sandbox where requiring had the wrong scope

## 0.8.1 / 2021-02-02

This release mostly contains small bug fixes.

### Bug Fixes
* Fix compiler sandboxing to copy standard tables and protect metatables
* Fix an issue where loading nested copies of Fennel would fail
* Fix a bug where sparse tables were displayed incorrectly in fennel view
* Fix a bug where certain numbers would be emitted incorrectly


## 0.8.0 / 2021-01-18

The highlight of this release is the table comprehension macros which
take the place of `map` in other lisps. The `&as` clause in
destructuring now allows you to access the original table even as you
destructure it into its fields. The `fennel.view` serializer has been
completely rewritten to improve indentation.

### New Forms
* Add table "comprehension" macros (`collect`/`icollect`)

### New Features
* Allow the parser to optionally include comments in the parsed AST
* The fennelview module is now incorporated into the compiler as `fennel.view`
* Fully rewrite `fennel.view` for better indentation handling
* Improve printing of destructured args in function arglist in `doc`
* Allow plugins to provide repl commands
* Label auto-generated locals in Lua output for improved readability
* Add whole-table destructuring with `&as`
* Provide `...` arguments consistently with Lua when requiring modules
* fennelview: respect presence of `__fennelview` metamethod on userdata metatables

### Bug Fixes
* Fix the behavior of `...` inside `eval-compiler`
* Fix a bug where decimal numbers would be emitted with commas in some locales
* Fix a bug where `import-macros` would not respect certain compiler options
* Fix a bug where shebang caused incorrect sourcemapped row/col in stacktraces

### Changes and Removals
* Warn when using the `&` character in identifiers; will be disallowed later
* Numbers using underscores for readability **may not** begin with an underscore


## 0.7.0 / 2020-11-03

This release adds support for reloading modules in the repl, making
interactive development more streamlined.

### New Features
* Improve printing of multiple return values in the repl
* Add repl commands including `,reload`; see `,help` for a full list

### Bug Fixes
* Fix several bugs in the linter
* Fix a bug where `--no-compiler-sandbox` did not apply in `import-macros`
* Fix a bug where compiler sandboxing makes `macrodebug` fail to print correctly
* Fix a bug in `:` when used with methods that are not valid Lua names


## 0.6.0 / 2020-09-03

This release introduces the plugin system as well as starting to
sandbox the compiler environment for safer code loading. Nothing is
blocked yet, but it emits warnings when macros use functionality that
is not considered safe; future versions will prevent this.

### New Features
* Add compiler plugin system
* Add `--lua` CLI flag for specifying a custom Lua command/executable
* Expose `list?` and `sym?` in compiler API
* Sandbox compiler environment and emit a warning when it leaks

### Bug Fixes
* Fix a bug where repls would fail when provided with an overridden env
* Fix a bug where long arglists could get jumbled
* Fix a bug where method calls would early-evaluate their receiver
* Fix a bug where multi-arity comparisons would early-evaluate their arguments

### Changes and Removals
* Change table reference notation in fennelview to use `@`


## 0.5.0 / 2020-08-08

This release features a version of the Fennel compiler that is
self-hosted and written entirely in Fennel!

### New Features
* The `fennel.friend` module is now incorporated into the compiler, not separate

### Bug Fixes
* Fix a bug where lambdas with no body would return true instead of nil
* Fix a bug where global mangling would break when used with an environment
* Fix a bug where globals tracking would lose track of allowed list
* Fix a bug where top-level expressions in `include` would get skipped


## 0.4.2 / 2020-07-11

This release mostly includes small bug fixes but also adds the
`with-open` macro for automating closing file handles, etc.

### New Features
* Support varargs in hashfn with `$...`
* Add `with-open` macro for auto-closing file handles
* Add `--native-module` and `--native-library` to `--compile-binary` command
* Make autogensym symbols omit "#" when appending unique suffix
* Add `fennel.searchModule` function to module API

### Bug Fixes
* Fix a bug where multiple `include` calls would splice locals incorrectly
* Fix a bug where autogensyms (using `#`) couldn't be used as multisyms
* Fix a bug causing `include` to ignore compiler options
* Fix a bug causing the repl to fail when `$HOME` env var was not set


## 0.4.1 / 2020-05-25

This release mostly includes small bug fixes, but also introduces a very
experimental command for compiling standalone executables.

### New Features
* Experimental `--compile-binary` command
* Support shebang in all contexts, not just dofile
* Pinpoint source in compile errors even when loading from a string

### Bug Fixes
* Fix a bug where included modules could get included twice
* Fix a 0.4.0 bug where macros can't expand to string/boolean/number primitives
* Fix a bug in macros returning forms of a different length from their input


## 0.4.0 / 2020-05-12

This release adds support for Lua 5.3's bitwise operators as well as a
new way of importing macro modules. It also adds `pick-values` and
`pick-args` for a little more flexibility around function args and
return values. The compiler now tries to emit friendlier errors that
suggest fixes for problems.

### New Forms
* Add `import-macros` for more flexible macro module loading
* Add bit-wise operators `rshift`, `lshift`, `bor`, `band`, `bnot`, and `bxor`
* Add new `macroexpand` helper to expand macro forms during compilation
* Add `macrodebug` utility macro for printing expanded macro forms in REPL
* Add `pick-values` and `pick-args` macros

### New Features
* Ensure deterministic compiler output
* Friendlier compiler/parse error messages with suggestions
* Omit compiler internal stack traces by default unless `FENNEL_DEBUG=trace`
* Add support for `__fennelview` metamethod for custom serialization

### Bug Fixes
* Fix a bug where `dofile` would report the wrong filename
* Fix bug causing failing `include` of Lua modules that lack a trailing newline


## 0.3.2 / 2020-01-14

This release mostly contains small bug fixes.

### Bug Fixes
* Fix a bug where `include` could not be nested without repetition
* Fix a bug where globals checking would mistakenly flag locals
* Fix a bug that would cause incorrect filenames in error messages
* Fix a bug causing `else` to emit twice in some contexts

### Changes and Removals
* Dissallow naming a local the same as global in some contexts


## 0.3.1 / 2019-12-17

This release mostly contains small bug fixes.

### New Features
* Look for init file for repl in XDG config dirs as well as ~/.fennelrc
* Add support for `--load FILE` argument to command-line launcher
* Make repl completion descend into nested table fields

### Bug Fixes
* Fix `each` to work with raw iterator values
* Fix repl completer to correctly handle symbol mangling


## 0.3.0 / 2019-09-22

This release introduces docstrings as well as several new features to
the macro system and some breaking changes; the most significant being
the new unquote syntax and the requirement of auto-gensym for
identifiers in backtick.

### New Forms
* Add `include` special form to selectively inline modules in compiled output
* Add support for docstrings and `doc` for displaying them in repl
* Alias `#` special with `length`
* Add `hashfn` and `#` reader macro for shorthand functions like `#(+ $1 $2)`
* Add `macro` to make defining a single macro easier
* Add `(comment)` special which emits a Lua comment in the generated source

### New Features
* Support `:detect-cycles? false` in fennelview to turn off "#<table 1>" output
* Support `x#` syntax for auto-gensym inside backtick
* Support `:one-line` output in fennelview
* Add `--require-as-include` to inline required modules in compiled output
* Add `--eval` argument to command-line launcher
* Add environment variable `FENNEL_PATH` to `path`
* Add support for guard clauses with `?` in pattern matching
* Support completion in repl when `readline.lua` is available
* Add `--globals` and `--globals-only` options to launcher script
* Allow lua-style method calls like `(foo:bar baz)`; **disallow** `:` in symbols

### Bug Fixes
* Fix a bug where errors would show incorrect line numbers
* Fix a bug in `lambda` argument checks when using destructuring
* Fix a few bugs in `match`

### Changes and Removals
* **Disallow** non-gensym identifiers in backtick/macros
* **Remove** undocumented support for single-quoted strings
* **Remove** `luaexpr` and `luastatement` for a single `lua` special
* Replace `@` (unquote) with `,`; comma is **no longer** whitespace
* **Disallow** `~` in symbols other than `~=`


## 0.2.1 / 2019-01-22

This release mostly contains small bug fixes.

### New Forms
* Add `not=` as an alias for `~=`

### New Features
* Improve error reporting for mismatched delimiters

### Bug Fixes
* Fix a bug with `in-scope?` which caused `match` outer unification to fail
* Fix a bug with variadic `~=` comparisons


## 0.2.0 / 2019-01-17

The second minor release introduces backtick, making macro authoring
much more streamlined. Macros may now be defined in the same file, and
pattern matching is added.

### New Forms
* Add `-?>` and `-?>>` macros
* Add `match` macro for pattern matching
* Allow macros to be defined inline with `macros`

### New Features
* Add support for quoting with backtick and unquoting with `@` (later changed to `,`)
* Prevent creation of bindings that collide with special forms and macros
* Make parens around steps optional in arrow macros for single-arg calls
* Add `--add-package-path` and `--add-fennel-path` to launcher script
* Support key/value tables when destructuring
* Add optional GNU readline support for repl

### Bug Fixes
* Fix a bug where runtime errors were not reported by launcher correctly
* Allow repl to recover gracefully from parse errors


## 0.1.1 / 2018-12-05

This release contains a few small bug fixes.

### Bug Fixes
* Fix luarocks packaging so repl includes fennelview
* Fix bug in the repl where locals-saving would fail for certain input
* Fix launcher to write errors to stderr, not stdout


## 0.1.0 / 2018-11-29

The first real release sees the addition of several "creature comfort"
improvements such as comments, iterator support, line number tracking,
accidental global protection, pretty printing, and repl locals. It
also introduces the name "Fennel".

### New Forms
* Add `->` and `->>` macros
* Add `var`; disallow regular locals from being set
* Add `global`; refuse to set globals without it
* Add `require-macros`
* Add `//` for integer division on Lua 5.3+
* Add `fennel.dofile` and `fennel.searcher` for `require` support
* Add `partial`
* Add `local`
* Add `doto` macro
* Add `:` for method calls
* Add `each`
* Add `lambda`/`λ` for nil-argument-checked functions
* Add `when`

### New Features
* Add comments
* Add fennelview pretty-printer
* Save locals in between chunks in the repl
* Allow destructuring in more places
* Support newlines in strings
* Prevent typos from accidentally referring to unknown globals
* Improve readability of compiler output
* Make comparison operators variadic
* Support destructuring "rest" of a table into a local with `&`
* Track line numbers
* Support binding against multiple values
* Compile tail-calls properly
* Support nested lookup in `.` form

### Changes and Removals
* Rename to Fennel
* **Remove** deprecated special forms: `pack`, `$`, `block`, `*break`, `special`
* **Remove** redundant `defn` macro


## 0.0.1 / 2016-08-14

The initial version (named "fnl") was created in 8 days and then
set aside for several years.
