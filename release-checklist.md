# Steps to release a new Fennel version

This document is intended for Fennel maintainers.

## Preparing

1. Make sure tests pass for all versions of Lua using `make ci`.
2. Update and date the changelog.
3. Update version number in `src/fennel.fnl`.
4. Check for changes which need to be mentioned in help text or man page.
5. Create rockspec by copying an old rockspec. Make sure luarocks version
   matches the file name exactly and the tarball URL is updated.
6. Update the download links in `setup.md`.
7. Commit above changes.
8. Run `git tag -s $VERSION -m $VERSION`.

## Uploading

1. Run `git push && git push --tags`.
2. Run `make release VERSION=$VERSION`.
3. Update the submodule in the fennel-lang.org repository.

Announce it on the mailing list. Fennel is now released!

## Post-release

1. Bump the version in `src/fennel.fnl` to the next version with a "-dev" suffix.
2. Add a stub for the next version to `changelog.md`
