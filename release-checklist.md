# Steps to release a new Fennel version

This document is intended for Fennel maintainers.

## Preparing

1. Check for changes which need to be mentioned in help text or man page
2. Date `changelog.md` and update download links in `setup.md`
3. Run `make prerelease VERSION=$VERSION`

## Uploading

The `make release` command should be run on a system with the lowest
available glibc for maximum compatibility.

1. Run `make release VERSION=$VERSION`
