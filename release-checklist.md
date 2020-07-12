# What to change on versioned releases of Fennel

This document contains a checklist for releasing a Fennel version to luarocks. This document
is intended for Fennel maintainers.

1. Update and date changelog.md; update version number in fennel.lua.
2. Create rockspec by copying an old rockspec. Make sure luarocks version
   matches the file name exactly and the tgz URL is updated.
3. Make sure tests pass for all versions of Lua and the linter is OK (`make ci`)
4. Update the download links in `setup.md`.
5. Commit above changes.
6. Tag release with chosen git tag, and push to repository.
7. Create a release in GitHub; paste the changelog for this version.
8. Copy tarball from GitHub to https://fennel-lang.org/downloads/Fennel-$(VERSION).tgz
9. Upload rock with `luarocks upload rockspecs/fennel-(version)-1.rockspec`.
   Test that the new version can be installed thru LuaRocks.
10. Run `make release VERSION=$VERSION`. Build and upload arm binary separately.
11. Update the submodule in the fennel-lang.org repository.
12. Announce it on the mailing list. Fennel is now released!
13. Bump the version in fennel.lua to the next version with a "-dev" suffix; add changelog stub.

