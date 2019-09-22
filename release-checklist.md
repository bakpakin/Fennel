# What to change on versioned releases of Fennel

This document contains a checklist for releasing a Fennel version to luarocks. This document
is intended for Fennel maintainers.

1. Update and date changelog.md.
2. Update version number in fennel.lua to correct version.
3. Create rockspec by copying an old rockspec. Make sure luarocks version
   matches the file name exactly. Pick a git tag name.
4. Make sure tests pass for all versions of Lua and the linter is OK (`make ci`)
5. Commit above changes.
6. Tag release with chosen git tag, and push to repository.
7. Upload rock with `luarocks upload rockspecs/fennel-(version)-1.rockspec`. Fennel is now released!
8. Update the submodule in the fennel-lang.org repository.
9. Announce it on the mailing list.
10. Bump the version in fennel.lua to the next version with a "-dev" suffix; add changelog stub.
