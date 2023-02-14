# Steps to release a new Fennel version

This document is intended for Fennel maintainers.

## Preparing

1. Make sure tests pass for all versions of Lua using `make ci`.
2. Update and date the changelog.
3. Update version number in `src/fennel/utils.fnl`.
4. Check for changes which need to be mentioned in help text or man page.
5. Update the download links in `setup.md`.
6. Run `make rockspec VERSION=$VERSION`
7. Run `git commit -m "Release $VERSION" && git tag -s $VERSION -m $VERSION`

## Uploading

The `make release` command should be run on a system with the lowest
available glibc for maximum compatibility.

1. Run `make release VERSION=$VERSION`.
2. Run `git push && git push --tags`.
3. Update the submodule in the fennel-lang.org repository.

Announce it on the mailing list. Fennel is now released!

## Post-release

1. Bump the version in `src/fennel/utils.fnl` to the next version with a "-dev" suffix.
2. Add a stub for the next version to `changelog.md`
