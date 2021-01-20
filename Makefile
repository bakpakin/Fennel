LUA ?= lua
LUA_VERSION ?= $(shell $(LUA) -e 'v=_VERSION:gsub("^Lua *","");print(v)')
PREFIX ?= /usr/local
BIN_DIR ?= $(PREFIX)/bin
LUA_LIB_DIR ?= $(PREFIX)/share/lua/$(LUA_VERSION)

SRC=src/fennel.fnl $(wildcard src/fennel/*.fnl)

build: fennel fennel.lua

test: fennel.lua fennel
	$(LUA) test/init.lua

testall: export FNL_TESTALL = 1
testall: export FNL_TEST_OUTPUT ?= text
testall: fennel fennel.lua
	@printf 'Testing lua 5.1:\n'  ; lua5.1 test/init.lua
	@printf "\nTesting lua 5.2:\n"; lua5.2 test/init.lua
	@printf "\nTesting lua 5.3:\n"; lua5.3 test/init.lua
	@printf "\nTesting lua 5.4:\n"; lua5.4 test/init.lua
	@printf "\nTesting luajit:\n" ; luajit test/init.lua

count: ; cloc --force-lang=lisp $(SRC)

# Avoid chicken/egg situation using the old Lua launcher.
LAUNCHER=$(LUA) old/launcher.lua --add-fennel-path src/?.fnl --globals "_G,_ENV"

# Precompile fennel libraries
fennelview.lua: src/fennel/view.fnl fennel.lua ; $(LAUNCHER) --compile $< > $@

# All-in-one pure-lua script:
fennel: src/launcher.fnl $(SRC)
	echo "#!/usr/bin/env $(LUA)" > $@
	$(LAUNCHER) --no-metadata --require-as-include --compile $< >> $@
	chmod 755 $@

fennel.lua: $(SRC)
	$(LAUNCHER) --no-metadata --require-as-include --compile $< > $@

LUA_DIR=$(PWD)/lua-5.4.2
STATIC_LUA_LIB=$(LUA_DIR)/src/liblua-linux-x86_64.a
LUA_INCLUDE_DIR=$(LUA_DIR)/src

fennel-bin: src/launcher.fnl fennel
	./fennel --add-fennel-path src/?.fnl --no-compiler-sandbox --compile-binary \
		$< $@ $(STATIC_LUA_LIB) $(LUA_INCLUDE_DIR)

fennel-bin.exe: src/launcher.fnl fennel $(LUA_INCLUDE_DIR)/liblua-mingw.a
	CC=i686-w64-mingw32-gcc fennel --compile-binary $< fennel-bin \
		$(LUA_INCLUDE_DIR)/liblua-mingw.a $(LUA_INCLUDE_DIR)

fennel-arm32: src/launcher.fnl fennel $(LUA_INCLUDE_DIR)/liblua-arm32.a
	CC=arm-linux-gnueabihf-gcc fennel --compile-binary $< fennel-arm32 \
		$(LUA_INCLUDE_DIR)/liblua-arm32.a $(LUA_INCLUDE_DIR)

# Sadly git will not work; you have to get the tarball for a working makefile:
$(LUA_DIR): ; curl https://www.lua.org/ftp/lua-5.4.2.tar.gz | tar xz

$(STATIC_LUA_LIB): $(LUA_DIR)
	make -C $(LUA_DIR) clean linux
	mv $(LUA_DIR)/src/liblua.a $@

# install gcc-mingw-w64-i686
$(LUA_DIR)/src/liblua-mingw.a: $(LUA_DIR)
	make -C $(LUA_DIR) clean mingw CC=i686-w64-mingw32-gcc
	mv $(LUA_DIR)/src/liblua.a $@

# install gcc-arm-linux-gnueabihf
$(LUA_DIR)/src/liblua-arm32.a: $(LUA_DIR)
	make -C $(LUA_DIR) clean linux CC=arm-linux-gnueabihf-gcc
	mv $(LUA_DIR)/src/liblua.a $@

ci: testall count

clean:
	rm -f fennel.lua fennel fennel-bin *_binary.c fennel-bin.exe luacov.*
	make -C $(LUA_DIR) clean || true # this dir might not exist

coverage: fennel
	$(LUA) -lluacov test/init.lua
	@echo "generated luacov.report.out"

install: fennel fennel.lua fennelview.lua
	mkdir -p $(BIN_DIR) && \
		cp fennel $(BIN_DIR)/
	mkdir -p $(LUA_LIB_DIR) && \
		for f in fennel.lua fennelview.lua; do cp $$f $(LUA_LIB_DIR)/; done

# Release-related tasks:

fennel.tar.gz: README.md LICENSE fennel.1 fennel fennel.lua fennelview.lua \
		Makefile $(SRC)
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
	rsync -r downloads/* fenneler@fennel-lang.org:fennel-lang.org/downloads/

.PHONY: build test testall count ci clean coverage install release
