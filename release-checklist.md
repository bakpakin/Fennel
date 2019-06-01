# What to change on versioned releases of Fennel

This document contains a checklist for releasing a Fennel version to luarocks. This document
is intended for Fennel maintainers.

1. Update and date changelog.md, add stub for next release
2. Update version number in fennel.lua to correct version
3. Create rockspec by copying an old rockspec. Make sure luarocks version
   matches the file name exactly. Pick a git tag name.
4. Make sure all tests pass for all versions of Lua (`make testcall`)
5. Check code style with luacheck (`make luacheck`)
6. Ensure fennelview.fnl.lua is generated (`make ci`, also tests everything)
7. Commit above changes.
8. Tag release with chosen git tag, and push to repository.
9. Upload rock with `luarocks upload rockspecs/fennel-(version)-1.rockspec`. Fennel is now released!
10. Update the submodule for fennel-lang.org.
11. Announce it on the mailing list.
