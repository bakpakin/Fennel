# Steps to release a new Fennel version

This document is intended for Fennel maintainers.

## Preparing the tag

1. Update and date changelog.md; update version number in fennel.lua.
   Check for changes which need to be mentioned in help text or man page.
2. Create rockspec by copying an old rockspec. Make sure luarocks version
   matches the file name exactly and the tgz URL is updated.
   (one time: change the rockspec to look for tar.gz instead of tgz and lowercase)
3. Make sure tests pass for all versions of Lua and the linter is OK (`make ci`)
4. Update the download links in `setup.md`.
5. Commit above changes.
6. Run `git tag -s $VERSION -m $VERSION`.

Once this is done, run `git push && git push --tags`.

## Uploading builds

1. Run `make release VERSION=$VERSION`.
2. Update the submodule in the fennel-lang.org repository.
3. Run `luarocks --local build rockspecs/fennel-$(VERSION)-1.rockspec`
4. Test `~/.luarocks/bin/fennel --version`.
5. Run ` API_KEY=... luarocks upload rockspecs/fennel-$(VERSION)-1.rockspec`

Announce it on the mailing list. Fennel is now released!

## Post-release

1. Bump the version in fennel.lua to the next version with a "-dev" suffix.
2. Add a stub for the next version to `changelog.md`
