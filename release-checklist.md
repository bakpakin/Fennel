# Steps to release a new Fennel version

This document is intended for Fennel maintainers.

## Preparing

1. Update and date the changelog.
2. Update version number in `src/fennel.fnl`.
3. Check for changes which need to be mentioned in help text or man page.
4. Create rockspec by copying an old rockspec. Make sure luarocks version
   matches the file name exactly and the tarball URL is updated.
5. Make sure tests pass for all versions of Lua using `make ci`.
6. Update the download links in `setup.md`.
7. Commit above changes.
8. Run `git tag -s $VERSION -m $VERSION`.
9. Run `git push && git push --tags`.

## Uploading builds

1. Run `make release VERSION=$VERSION`.
2. Update the submodule in the fennel-lang.org repository.
3. Run `luarocks --local build rockspecs/fennel-$(VERSION)-1.rockspec`
4. Test `~/.luarocks/bin/fennel --version`.
5. Run ` API_KEY=... luarocks upload rockspecs/fennel-$(VERSION)-1.rockspec`

Announce it on the mailing list. Fennel is now released!

## Post-release

1. Bump the version in `src/fennel.fnl` to the next version with a "-dev" suffix.
2. Add a stub for the next version to `changelog.md`
