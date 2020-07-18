LUA ?= lua
LUA_VERSION ?= $(shell $(LUA) -e 'v=_VERSION:gsub("^Lua *","");print(v)')
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
LUADIR ?= $(PREFIX)/share/lua/$(LUA_VERSION)

SRC=src/fennel.fnl $(wildcard src/fennel/*.fnl)
EXTRA_SRC=fennelview.fnl fennelfriend.fnl fennelbinary.fnl launcher.fnl

build: fennel

test: fennel.lua fennel
	$(LUA) test/init.lua

testall: export FNL_TEST_OUTPUT ?= text
testall: fennel
	@printf 'Testing lua 5.1:\n'  ; lua5.1 test/init.lua
	@printf "\nTesting lua 5.2:\n"; lua5.2 test/init.lua
	@printf "\nTesting lua 5.3:\n"; lua5.3 test/init.lua
	@printf "\nTesting lua 5.4:\n"; lua5.4 test/init.lua
	@printf "\nTesting luajit:\n" ; luajit test/init.lua

count:
	cloc --force-lang=lisp $(SRC) # core compiler
	cloc --force-lang=lisp $(EXTRA_SRC) # libraries and launcher

# Avoid chicken/egg situation using the old Lua launcher.
LAUNCHER=$(LUA) old/launcher.lua --add-fennel-path src/?.fnl --globals "_G,_ENV"

# Precompile fennel libraries
fennelview.lua: fennelview.fnl fennel.lua ; $(LAUNCHER) --compile $< > $@
fennelfriend.lua: fennelfriend.fnl fennel.lua ; $(LAUNCHER) --compile $< > $@

# All-in-one pure-lua script:
fennel: launcher.fnl $(SRC) fennelview.lua fennelfriend.lua fennelbinary.fnl
	echo "#!/usr/bin/env $(LUA)" > $@
	$(LAUNCHER) --no-metadata --require-as-include --compile $< >> $@
	chmod 755 $@

fennel.lua: $(SRC)
	$(LAUNCHER) --no-metadata --require-as-include --compile $< > $@

# Change these up to swap out the version of Lua or for other operating systems.
STATIC_LUA_LIB ?= /usr/lib/x86_64-linux-gnu/liblua5.3.a
LUA_INCLUDE_DIR ?= /usr/include/lua5.3

fennel-bin: launcher.fnl fennel
	./fennel --compile-binary $< $@ $(STATIC_LUA_LIB) $(LUA_INCLUDE_DIR)

# Cross-compile to Windows; very experimental:
fennel-bin.exe: launcher.fnl fennel lua-5.3.5/src/liblua-mingw.a
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

release: fennel fennel-bin fennel-bin.exe
	grep $(VERSION) fennel.lua
	grep $(VERSION) changelog.md
	echo Good to release version $(VERSION)?
	shell $(read)
	mkdir -p downloads/
	mv fennel downloads/fennel-$(VERSION)
	mv fennel-bin downloads/fennel-$(VERSION)-x86_64
	mv fennel-bin.exe downloads/fennel-$(VERSION)-windows32.exe
	gpg -ab downloads/fennel-$(VERSION)
	gpg -ab downloads/fennel-$(VERSION)-x86_64
	gpg -ab downloads/fennel-$(VERSION)-windows32.exe
	echo TODO: compile and upload fennel-$(VERSION)-arm32
	echo make fennel-bin STATIC_LUA_LIB=/usr/lib/arm-linux-gnueabihf/liblua5.3.a
	rsync -r downloads/* fennel-lang.org:fennel-lang.org/downloads/

.PHONY: build test testall count ci clean coverage install release
