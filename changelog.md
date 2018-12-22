# Summary of user-visible changes

## 0.1.2 / ???

* Add optional GNU readline support for repl
* Fix a bug where runtime errors were not reported by launcher correctly
* Allow repl to recover gracefully from parse errors

## 0.1.1 / 2018-12-05

* Fix luarocks packaging so repl includes fennelview
* Fix bug in the repl where locals-saving would fail for certain input
* Fix launcher to write errors to stderr, not stdout

## 0.1.0 / 2018-11-29

* Save locals in between chunks in the repl
* Allow destructuring in more places
* Remove redundant `defn` macro
* Add `doto` macro
* Support newlines in strings
* Prevent typos from accidentally referring to unknown globals
* Improve readability of compiler output
* Add `->` and `->>` macros
* Remove deprecated special forms: `pack`, `$`, `block`, `*break`, `special`
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

* Initial version (named "fnl") created in 2 weeks
