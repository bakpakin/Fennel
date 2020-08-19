LUA ?= lua
LUA_VERSION ?= $(shell $(LUA) -e 'v=_VERSION:gsub("^Lua *","");print(v)')
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
LUADIR ?= $(PREFIX)/share/lua/$(LUA_VERSION)

SRC=src/fennel.fnl fennelview.fnl $(wildcard src/fennel/*.fnl)

build: fennel

test: fennel.lua fennel
	$(LUA) test/init.lua

testall: export FNL_TESTALL = 1
testall: export FNL_TEST_OUTPUT ?= text
testall: fennel
	@printf 'Testing lua 5.1:\n'  ; lua5.1 test/init.lua
	@printf "\nTesting lua 5.2:\n"; lua5.2 test/init.lua
	@printf "\nTesting lua 5.3:\n"; lua5.3 test/init.lua
	@printf "\nTesting lua 5.4:\n"; lua5.4 test/init.lua
	@printf "\nTesting luajit:\n" ; luajit test/init.lua

count: ; cloc --force-lang=lisp $(SRC)

# Avoid chicken/egg situation using the old Lua launcher.
LAUNCHER=$(LUA) old/launcher.lua --add-fennel-path src/?.fnl --globals "_G,_ENV"

# Precompile fennel libraries
fennelview.lua: fennelview.fnl fennel.lua ; $(LAUNCHER) --compile $< > $@

# All-in-one pure-lua script:
fennel: src/launcher.fnl $(SRC) fennelview.lua
	echo "#!/usr/bin/env $(LUA)" > $@
	$(LAUNCHER) --no-metadata --require-as-include --compile $< >> $@
	chmod 755 $@

fennel.lua: $(SRC)
	$(LAUNCHER) --no-metadata --require-as-include --compile $< > $@

# Change these up to swap out the version of Lua or for other operating systems.
STATIC_LUA_LIB ?= /usr/lib/x86_64-linux-gnu/liblua5.3.a
LUA_INCLUDE_DIR ?= /usr/include/lua5.3

fennel-bin: src/launcher.fnl fennel
	./fennel --add-fennel-path src/?.fnl --compile-binary $< $@ \
		$(STATIC_LUA_LIB) $(LUA_INCLUDE_DIR)

# Cross-compile to Windows; very experimental:
fennel-bin.exe: src/launcher.fnl fennel lua-5.3.5/src/liblua-mingw.a
	CC=i686-w64-mingw32-gcc fennel --compile-binary $< fennel-bin \
		lua-5.3.5/src/liblua-mingw.a $(LUA_INCLUDE_DIR)

# Sadly git will not work; you have to get the tarball for a working makefile:
lua-5.3.5: ; curl https://www.lua.org/ftp/lua-5.3.5.tar.gz | tar xz

# install gcc-mingw-w64-i686
lua-5.3.5/src/liblua-mingw.a: lua-5.3.5
	make -C lua-5.3.5 mingw CC=i686-w64-mingw32-gcc
	mv lua-5.3.5/src/liblua.a $@

ci: testall count

clean:
	rm -f fennel.lua fennel fennel-bin *_binary.c fennel-bin.exe luacov.*
	make -C lua-5.3.5 clean || true # this dir might not exist

coverage: fennel
	$(LUA) -lluacov test/init.lua
	@echo "generated luacov.report.out"

install: fennel fennel.lua fennelview.lua
	mkdir -p $(BINDIR) && \
		cp fennel $(BINDIR)/
	mkdir -p $(LUADIR) && \
		for f in fennel.lua fennelview.lua; do cp $$f $(LUADIR)/; done

# Release-related tasks:

ARM_HOST=deck3

fennel-arm32:
	ssh $(ARM_HOST) "cd src/fennel && git fetch && git checkout $(VERSION) && \
    STATIC_LUA_LIB=/usr/lib/arm-linux-gnueabihf/liblua5.3.a make fennel-bin"
	scp $(ARM_HOST):src/fennel/fennel-bin $@

fennel.tar.gz: README.md LICENSE fennel.1 fennel fennel.lua fennelview.lua \
		Makefile fennelview.fnl $(SRC)
	mkdir fennel-$(VERSION)
	cp -r $^ fennel-$(VERSION)
	tar czf $@ fennel-$(VERSION)

release: fennel fennel-bin fennel-bin.exe fennel-arm32 fennel.tar.gz
	mkdir -p downloads/
	mv fennel downloads/fennel-$(VERSION)
	mv fennel-bin downloads/fennel-$(VERSION)-x86_64
	mv fennel-bin.exe downloads/fennel-$(VERSION)-windows32.exe
	mv fennel-arm32 downloads/fennel-$(VERSION)-arm32
	mv fennel.tar.gz downloads/fennel-$(VERSION).tar.gz
	gpg -ab downloads/fennel-$(VERSION)
	gpg -ab downloads/fennel-$(VERSION)-x86_64
	gpg -ab downloads/fennel-$(VERSION)-windows32.exe
	gpg -ab downloads/fennel-$(VERSION)-arm32
	gpg -ab downloads/fennel-$(VERSION).tar.gz
	rsync -r downloads/* fennel-lang.org:fennel-lang.org/downloads/

.PHONY: build test testall count ci clean coverage install release
