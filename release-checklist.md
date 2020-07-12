# What to change on versioned releases of Fennel

This document contains a checklist for releasing a Fennel version to luarocks. This document
is intended for Fennel maintainers.

1. Update and date changelog.md.
2. Update version number in fennel.lua to correct version.
3. Create rockspec by copying an old rockspec. Make sure luarocks version
   matches the file name exactly and the tgz URL is updated.
4. Make sure tests pass for all versions of Lua and the linter is OK (`make ci`)
5. Update the download links in `setup.md`.
6. Commit above changes.
7. Tag release with chosen git tag, and push to repository.
8. Create a release in GitHub; paste the changelog for this version.
9. Upload rock with `luarocks upload rockspecs/fennel-(version)-1.rockspec`.
   Test that the new version can be installed thru LuaRocks.
10. Upload builds to https://fennel-lang.org/downloads and .asc files (TODO: automate)
    * fennel-$(VERSION) (`make fennel`)
    * fennel-$(VERSION)-x86_64 (`make fennel-bin`)
    * fennel-$(VERSION)-arm32 (`make fennel-bin` on an ARM box)
    * fennel-$(VERSION)-windows32.exe (`make fennel-bin.exe`)
    * Fennel-$(VERSION).tgz (get this from github)
11. Update the submodule in the fennel-lang.org repository.
12. Announce it on the mailing list. Fennel is now released!
13. Bump the version in fennel.lua to the next version with a "-dev" suffix; add changelog stub.

