# Summary of user-visible changes

## 0.9.3 / ???

* Add `fennel.syntax` function describing built-ins.

## 0.9.2 / 2021-05-02

* Add Fennel for Clojure Users guide
* Never treat `_ENV` as an unknown global
* Fix multi-value destructuring in pattern matches that use `where`
* Fix a bug around disambiguating parens in method calls
* Improve behavior of `?.` when used directly on nil
* Fix a bug where line number correlation was thrown off in macros
* Fix a bug where `--use-bit-lib` was not propagating to the REPL
* Fix a launcher bug where `-v` was not implemented as an alias for `--version`

## 0.9.1 / 2021-04-10

* Fix a bug in compiled output for statement separators in LuaJIT

## 0.9.0 / 2021-04-08

* Add `--use-bit-lib` flag to allow bitwise operations to work in LuaJIT
* Add `macro-searchers` table for finding macros similarly to `package.searchers`
* Support `&as` inside pattern matches
* Include stack trace for errors during macroexpansion
* The `sym` function in compile scope now takes a source table second argument
* Support `:until` clauses for early termination in all loops
* Support `:escape-newlines?` and `:prefer-colon?` options in fennel.view
* Add nil-safe table access operator `?.`
* Add support for guards using `where`/`or` clauses in `match`
* Allow symbols to compare as equal in macros based on name
* Fix a bug where newlines were emitted with backslashes in fennel.view
* Fix a bug in the compiler sandbox where requiring had the wrong scope

## 0.8.1 / 2021-02-02

* Improve compiler sandboxing to copy standard tables and protect metatables
* Fix an issue where loading nested copies of Fennel would fail
* Fix a bug where sparse tables were displayed incorrectly in fennel view
* Ensure the compiler runs under strict mode
* Fix a bug where certain numbers would be emitted incorrectly

## 0.8.0 / 2021-01-18

* Allow the parser to optionally include comments in the parsed AST
* The fennelview module is now incorporated into the compiler as `fennel.view`
* Fully rewrite fennelview for better indentation handling; see fennelview
  docstring for detailed description of API changes
* Improve printing of destructured args in function arglist in `doc`
* Allow plugins to provide repl commands
* Fix a bug where decimal numbers would be emitted with commas in some locales
* Label auto-generated locals in Lua output for improved readability
* Fix the behavior of `...` inside `eval-compiler`
* Warn when using the `&` character in identifiers; will be disallowed later
* Add whole-table destructuring with `&as`
* Add list/table "comprehension" macros (`collect`/`icollect`)
* Numbers using underscores for readability **may not** begin with an underscore
* Provide `...` arguments consistently with Lua when requiring modules
* Fix a bug where `import-macros` would not respect certain compiler options
* fennelview: respect presence of `__fennelview` metamethod on userdata metatables
* Fix a bug where shebang caused incorrect sourcemapped row/col in stacktraces

## 0.7.0 / 2020-11-03

* Improve printing of multiple return values in the repl
* Add repl commands including `,reload`; see `,help` for a full list
* Fix several bugs in the linter
* Fix a bug where `--no-compiler-sandbox` did not apply in `import-macros`
* Fix a bug where compiler sandboxing makes `macrodebug` fail to print correctly
* Correct `--no-sandbox-compiler` to `--no-compiler-sandbox` in help/docs
* Fix a bug in `:` when used with methods that are not valid Lua names

## 0.6.0 / 2020-09-03

This release introduces the plugin system as well as starting to
sandbox the compiler environment for safer code loading. Nothing is
blocked yet, but it emits warnings when macros use functionality that
is not considered safe; future versions will prevent this.

* Change table reference notation in fennelview to use `@`
* Fix a bug where long arglists could get jumbled.
* Add plugin system.
* Sandbox compiler environment and emit a warning when it leaks.
* Fix a bug where repls would fail when provided with an overridden env.
* Expose `list?` and `sym?` in compiler API.
* Fix a bug where method calls would early-evaluate their receiver.
* Fix a bug where multi-arity comparisons would early-evaluate their arguments.
* Add `--lua` CLI flag for specifying a custom Lua command/executable. (#324)

## 0.5.0 / 2020-08-08

This release features a version of the Fennel compiler that is
self-hosted and written entirely in Fennel!

* Fix a bug where lambdas with no body would return true instead of nil.
* Fix a bug where global mangling would break when used with an environment.
* Fix a bug where globals tracking would lose track of allowed list.
* Fix a bug where top-level expressions in `include` would get skipped.
* The "fennelfriend" module is now incorporated into the compiler, not separate.

## 0.4.2 / 2020-07-11

This release mostly includes small bug fixes but also adds the
`with-open` macro for automating closing file handles, etc.

* Fix a bug where multiple `include` calls would splice locals incorrectly
* Support varargs in hashfn with `$...` (#298)
* Add `with-open` macro for auto-closing file handles (#295)
* Add `--native-module` and `--native-library` to `--compile-binary` command
* Make autogensym symbols omit "#" when appending unique suffix
* Fix a bug where autogensyms (using `#`) couldn't be used as multisyms (#294)
* Add `fennel.searchModule` function to module API
* Fix a bug causing `include` to ignore compiler options
* Fix a bug causing the repl to fail when `$HOME` env var was not set

## 0.4.1 / 2020-05-25

This release mostly includes small bug fixes, but also introduces a very
experimental command for compiling standalone executables.

* Experimental `--compile-binary` command (#281)
* Support shebang in all contexts, not just dofile
* Pinpoint source in compile errors even when loading from a string
* Fix a bug where included modules could get included twice (#278)
* Fix a 0.4.0 bug where macros can't expand to string/boolean/number primitives (#279)
* Fix a bug in macros returning forms of a different length from their input (#276)

## 0.4.0 / 2020-05-12

This release adds support for Lua 5.3's bitwise operators as well as a
new way of importing macro modules. It also adds `pick-values` and
`pick-args` for a little more flexibility around function args and
return values. The compiler now tries to emit friendlier errors that
suggest fixes for problems.

* Add `import-macros` for more flexible macro module loading (#269)
* Ensure deterministic compiler output (#257)
* Add bit-wise operators `rshift`, `lshift`, `bor`, `band`, `bnot`, and `bxor`
* Friendlier compiler/parse error messages with suggestions
* Omit compiler internal stack traces by default unless `FENNEL_DEBUG=trace`
* Add support for `__fennelview` metamethod for custom serialization
* Fix a bug where `dofile` would report the wrong filename
* Fix bug causing failing `include` of Lua modules that lack a trailing newline (#234)
* Introduce `pick-values` and `pick-args` macros (as `limit-*`: #246, as `pick-*`: #256)
* Add new `macroexpand` helper to expand macro forms during compilation (#258)
* Add `macrodebug` utility macro for printing expanded macro forms in REPL (#258)

## 0.3.2 / 2020-01-14

This release mostly contains small bug fixes.

* Fix a bug where `include` could not be nested without repetition (#214)
* Fix a bug where globals checking would mistakenly flag locals (#213)
* Fix a bug that would cause incorrect filenames in error messages (#208)
* Fix a bug causing `else` to emit twice in some contexts (#212)
* Dissallow naming a local the same as global in some contexts

## 0.3.1 / 2019-12-17

This release mostly contains small bug fixes.

* Look for init file for repl in XDG config dirs as well as ~/.fennelrc (#193)
* Add support for `--load FILE` argument to command-line launcher (#193)
* Fix `each` to work with raw iterator values (#201)
* Optionally check for unused locals with `--check-unused-locals`
* Make repl completion descend into nested table fields (#192)
* Fix repl completer to correctly handle symbol mangling (#195)

## 0.3.0 / 2019-09-22

This release introduces docstrings as well as several new features to
the macro system and some breaking changes; the most significant being
the new unquote syntax and the requirement of auto-gensym for
identifiers in backtick.

* Fix a bug where errors would show incorrect line numbers
* Add support for docstrings and `doc` for displaying them in repl
* Support `:detect-cycles? false` in fennelview to turn off "#<table 1>" output
* **Disallow** non-gensym identifiers in backtick/macros
* Support `x#` syntax for auto-gensym inside backtick
* Fix a bug in `lambda` arity checks when using destructuring
* Support `:one-line` output in fennelview
* Add `include` special form to selectively inline modules in compiled output
* Add `--require-as-include` to inline required modules in compiled output
* Add `--eval` argument to command-line launcher
* Add environment variable `FENNEL_PATH` to `path`
* Fix a few bugs in `match`
* **Remove** undocumented support for single-quoted strings
* Add support for guard clauses with `?` in pattern matching
* Support completion in repl when `readline.lua` is available
* Add `--globals` and `--globals-only` options to launcher script
* **Remove** `luaexpr` and `luastatement` for a single `lua` special
* Improve code generation for `if` expressions in many situations
* Alias `#` special with `length`
* Replace `@` (unquote) with `,`; comma is **no longer** whitespace
* **Disallow** `~` in symbols other than `~=`
* Add `hashfn` and `#` reader macro for shorthand functions like `#(+ $1 $2)`
* Allow hashfn arguments to be used in multisyms
* Add `macro` to make defining a single macro easier
* Add `(comment)` special which emits a Lua comment in the generated source
* Allow lua-style method calls like `(foo:bar baz)`; **disallow** `:` in symbols

## 0.2.1 / 2019-01-22

This release mostly contains small bug fixes.

* Add `not=` as an alias for `~=`
* Fix a bug with `in-scope?` which caused `match` outer unification to fail
* Fix a bug with variadic `~=` comparisons
* Improve error reporting for mismatched delimiters

## 0.2.0 / 2019-01-17

The second minor release introduces backtick, making macro authoring
much more streamlined. Macros may now be defined in the same file, and
pattern matching is added.

* Prevent creation of bindings that collide with special forms and macros
* Make parens around steps optional in arrow macros for single-arg calls
* Allow macros to be defined inline with `macros`
* Add `--add-package-path` and `--add-fennel-path` to launcher script
* Add `-?>` and `-?>>` macros
* Add support for quoting with backtick and unquoting with `@` (later changed to `,`)
* Support key/value tables when destructuring
* Add `match` macro for pattern matching
* Add optional GNU readline support for repl
* Fix a bug where runtime errors were not reported by launcher correctly
* Allow repl to recover gracefully from parse errors

## 0.1.1 / 2018-12-05

This release contains a few small bug fixes.

* Fix luarocks packaging so repl includes fennelview
* Fix bug in the repl where locals-saving would fail for certain input
* Fix launcher to write errors to stderr, not stdout

## 0.1.0 / 2018-11-29

The first real release sees the addition of several "creature comfort"
improvements such as comments, iterator support, line number tracking,
accidental global protection, pretty printing, and repl locals. It
also introduces the name "Fennel".

* Save locals in between chunks in the repl
* Allow destructuring in more places
* **Remove** redundant `defn` macro
* Add `doto` macro
* Support newlines in strings
* Prevent typos from accidentally referring to unknown globals
* Improve readability of compiler output
* Add `->` and `->>` macros
* **Remove** deprecated special forms: `pack`, `$`, `block`, `*break`, `special`
* Support nested lookup in `.` form
* Add `var`; disallow regular locals from being set
* Add `global`; refuse to set globals without it
* Make comparison operators variadic
* Support destructuring "rest" of a table into a local with `&`
* Add fennelview pretty-printer
* Add `require-macros`
* Add `//` for integer division on Lua 5.3+
* Add `fennel.dofile` and `fennel.searcher` for `require` support
* Track line numbers
* Add `partial`
* Add `local`
* Support binding against multiple values
* Add `:` for method calls
* Compile tail-calls properly
* Rename to Fennel
* Add `each`
* Add `lambda`/`λ` for arity-checked functions
* Add `when`
* Add comments

## 0.0.1 / 2016-08-14

The initial version (named "fnl") was created in 8 days and then
set aside for several years.
