LUA ?= lua
LUA_VERSION ?= $(shell $(LUA) -e 'v=_VERSION:gsub("^Lua *","");print(v)')
DESTDIR ?=
PREFIX ?= /usr/local
BIN_DIR ?= $(PREFIX)/bin
LUA_LIB_DIR ?= $(PREFIX)/share/lua/$(LUA_VERSION)

LIB_SRC=src/fennel.fnl src/fennel/friend.fnl src/fennel/parser.fnl \
		src/fennel/specials.fnl src/fennel/utils.fnl src/fennel/view.fnl \
		src/fennel/compiler.fnl  src/fennel/macros.fnl  src/fennel/repl.fnl

SRC=$(LIB_SRC) src/launcher.fnl src/fennel/binary.fnl

build: fennel fennel.lua

test: fennel.lua fennel
	$(LUA) test/init.lua $(TESTS)

testall: export FNL_TESTALL = 1
testall: export FNL_TEST_OUTPUT ?= text
testall: fennel fennel.lua
	@printf 'Testing lua 5.1:\n'  ; lua5.1 test/init.lua
	@printf "\nTesting lua 5.2:\n"; lua5.2 test/init.lua
	@printf "\nTesting lua 5.3:\n"; lua5.3 test/init.lua
	@printf "\nTesting lua 5.4:\n"; lua5.4 test/init.lua
	@printf "\nTesting luajit:\n" ; luajit test/init.lua

fuzz: fennel fennel.lua
	$(LUA) test/init.lua fuzz

# older versions of cloc might need --force-lang=lisp
count: ; cloc $(LIB_SRC) ; cloc $(SRC)

# install https://git.sr.ht/~technomancy/fnlfmt manually for this:
format: ; for f in $(SRC); do fnlfmt --fix $$f ; done

# Avoid chicken/egg situation using the old Lua launcher.
LAUNCHER=$(LUA) old/launcher.lua --no-compiler-sandbox --add-fennel-path src/?.fnl > /dev/null

lint: ; $(LAUNCHER) --plugin src/linter.fnl --require-as-include \
		--compile src/fennel.fnl

# All-in-one pure-lua script:
fennel: src/launcher.fnl $(SRC)
	echo "#!/usr/bin/env $(LUA)" > $@
	$(LAUNCHER) --no-metadata --require-as-include --compile $< >> $@
	chmod 755 $@

# Library file
fennel.lua: $(SRC)
	$(LAUNCHER) --no-metadata --require-as-include --compile $< > $@

# A lighter version of the compiler that excludes some features; experimental.
minifennel.lua: $(SRC) fennel
	./fennel --no-metadata --require-as-include --add-fennel-path src/?.fnl \
		--skip-include fennel.repl,fennel.view,fennel.friend \
		--compile $< > $@

## Binaries

LUA_VERSION=5.4.3
LUA_DIR ?= $(PWD)/lua-$(LUA_VERSION)
NATIVE_LUA_LIB ?= $(LUA_DIR)/src/liblua-native.a
LUA_INCLUDE_DIR ?= $(LUA_DIR)/src

PATH_ARGS=FENNEL_PATH=src/?.fnl FENNEL_MACRO_PATH=src/?.fnl

$(LUA_DIR): ; curl https://www.lua.org/ftp/lua-$(LUA_VERSION).tar.gz | tar xz

# Native binary for whatever platform you're currently on
fennel-bin: src/launcher.fnl fennel $(NATIVE_LUA_LIB)
	$(PATH_ARGS) ./fennel --no-compiler-sandbox --compile-binary \
		$< $@ $(NATIVE_LUA_LIB) $(LUA_INCLUDE_DIR)

$(NATIVE_LUA_LIB): $(LUA_DIR)
	$(MAKE) -C $(LUA_DIR)/src clean liblua.a
	mv $(LUA_DIR)/src/liblua.a $@

## Cross compiling

xc-deps:
	apt install -y gcc-arm-linux-gnueabihf libc6-dev-armhf-cross \
		gcc-multilib-x86-64-linux-gnu libc6-dev-amd64-cross \
		gcc-mingw-w64-i686 curl lua5.3

fennel-x86_64: src/launcher.fnl fennel $(LUA_INCLUDE_DIR)/liblua-x86_64.a
	$(PATH_ARGS) CC=x86_64-linux-gnu-gcc ./fennel --no-compiler-sandbox \
		--compile-binary $< $@ \
		$(LUA_INCLUDE_DIR)/liblua-x86_64.a $(LUA_INCLUDE_DIR)

fennel.exe: src/launcher.fnl fennel $(LUA_INCLUDE_DIR)/liblua-mingw.a
	$(PATH_ARGS) CC=i686-w64-mingw32-gcc ./fennel --no-compiler-sandbox \
		--compile-binary $< fennel-bin \
		$(LUA_INCLUDE_DIR)/liblua-mingw.a $(LUA_INCLUDE_DIR)
	mv fennel-bin.exe $@

fennel-arm32: src/launcher.fnl fennel $(LUA_INCLUDE_DIR)/liblua-arm32.a
	$(PATH_ARGS) CC=arm-linux-gnueabihf-gcc ./fennel --no-compiler-sandbox \
		--compile-binary $< $@  $(LUA_INCLUDE_DIR)/liblua-arm32.a $(LUA_INCLUDE_DIR)

$(LUA_DIR)/src/liblua-x86_64.a: $(LUA_DIR)
	$(MAKE) -C $(LUA_DIR)/src clean liblua.a CC=x86_64-linux-gnu-gcc
	mv $(LUA_DIR)/src/liblua.a $@

# There's a bug in the Lua makefile that doesn't let you override RANLIB so it
# tries to call system strip(1) which only knows how to strip arm64 binaries.
# To work around it, rather than call `make mingw' we expand the call.
$(LUA_DIR)/src/liblua-mingw.a: $(LUA_DIR)
	$(MAKE) -C $(LUA_DIR)/src CC=i686-w64-mingw32-gcc \
		"AR=i686-w64-mingw32-gcc -shared -o" \
		"RANLIB=i686-w64-mingw32-strip --strip-unneeded" clean liblua.a
	mv $(LUA_DIR)/src/liblua.a $@

$(LUA_DIR)/src/liblua-arm32.a: $(LUA_DIR)
	$(MAKE) -C $(LUA_DIR) clean liblua.a CC=arm-linux-gnueabihf-gcc
	mv $(LUA_DIR)/src/liblua.a $@

ci: testall fuzz

clean:
	rm -f fennel.lua fennel fennel-bin fennel-x86_64 fennel.exe fennel-arm32 \
		*_binary.c luacov.*
	$(MAKE) -C $(LUA_DIR) clean || true # this dir might not exist

coverage: fennel
	$(LUA) -lluacov test/init.lua
	@echo "generated luacov.report.out"

install: fennel fennel.lua
	mkdir -p $(DESTDIR)$(BIN_DIR) && cp fennel $(DESTDIR)$(BIN_DIR)/
	mkdir -p $(DESTDIR)$(LUA_LIB_DIR) && cp fennel.lua $(DESTDIR)$(LUA_LIB_DIR)/

# Release-related tasks:

fennel.tar.gz: README.md LICENSE fennel.1 fennel fennel.lua \
		Makefile $(SRC)
	rm -rf fennel-$(VERSION)
	mkdir fennel-$(VERSION)
	cp -r $^ fennel-$(VERSION)
	tar czf $@ fennel-$(VERSION)

uploadrock: rockspecs/fennel-$(VERSION)-1.rockspec uploadtar
	luarocks --local build $<
	$(HOME)/.luarocks/bin/fennel --version | grep $(VERSION)
	luarocks --local remove fennel
	luarocks upload --api-key $(shell pass luarocks-api-key) $<
	luarocks --local install fennel
	$(HOME)/.luarocks/bin/fennel --version | grep $(VERSION)
	luarocks --local remove fennel

uploadtar: fennel fennel-x86_64 fennel.exe fennel-arm32 fennel.tar.gz
	mkdir -p downloads/
	mv fennel downloads/fennel-$(VERSION)
	mv fennel-x86_64 downloads/fennel-$(VERSION)-x86_64
	mv fennel.exe downloads/fennel-$(VERSION)-windows32.exe
	mv fennel-arm32 downloads/fennel-$(VERSION)-arm32
	mv fennel.tar.gz downloads/fennel-$(VERSION).tar.gz
	gpg -ab downloads/fennel-$(VERSION)
	gpg -ab downloads/fennel-$(VERSION)-x86_64
	gpg -ab downloads/fennel-$(VERSION)-windows32.exe
	gpg -ab downloads/fennel-$(VERSION)-arm32
	gpg -ab downloads/fennel-$(VERSION).tar.gz
	rsync -rtAv downloads/ fenneler@fennel-lang.org:fennel-lang.org/downloads/

release: uploadtar uploadrock

.PHONY: build test testall count format ci clean coverage install \
	uploadtar uploadrock release lint

# TODO for 1.0.0 release

# * fix cross-compiling on arm64

