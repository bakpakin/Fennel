LUA ?= lua
LUA_VERSION ?= $(shell $(LUA) -e 'v=_VERSION:gsub("^Lua *","");print(v)')
DESTDIR ?=
PREFIX ?= /usr/local
BIN_DIR ?= $(PREFIX)/bin
LUA_LIB_DIR ?= $(PREFIX)/share/lua/$(LUA_VERSION)
MAN_DIR ?= $(PREFIX)/man/man1

MINI_SRC=src/fennel.fnl src/fennel/parser.fnl src/fennel/specials.fnl \
		src/fennel/utils.fnl src/fennel/compiler.fnl  src/fennel/macros.fnl

LIB_SRC=$(MINI_SRC) src/fennel/friend.fnl src/fennel/view.fnl src/fennel/repl.fnl

SRC=$(LIB_SRC) src/launcher.fnl src/fennel/binary.fnl

build: fennel fennel.lua

test: fennel.lua ; $(LUA) test/init.lua $(TESTS)

testall: export FNL_TEST_OUTPUT=text
testall: export FNL_TESTALL=yes
testall: fennel # recursive make considered not really a big deal; calm down
	$(MAKE) test LUA=lua5.1
	$(MAKE) test LUA=lua5.2
	$(MAKE) test LUA=lua5.3
	$(MAKE) test LUA=lua5.4
	$(MAKE) test LUA=luajit

fuzz: fennel.lua; $(LUA) test/init.lua fuzz

# older versions of cloc might need --force-lang=lisp
count: ; cloc $(MINI_SRC); cloc $(LIB_SRC) ; cloc $(SRC)

# install https://git.sr.ht/~technomancy/fnlfmt manually for this:
format: ; for f in $(SRC); do fnlfmt --fix $$f ; done

# Avoid chicken/egg situation using the old Lua launcher.
LAUNCHER=$(LUA) bootstrap/launcher.lua --no-compiler-sandbox --add-fennel-path src/?.fnl --globals _G

# All-in-one pure-lua script:
fennel: src/launcher.fnl $(SRC)
	echo "#!/usr/bin/env $(LUA)" > $@
	$(LAUNCHER) --no-metadata --require-as-include --compile $< >> $@
	chmod 755 $@

# Library file
fennel.lua: $(SRC)
	$(LAUNCHER) --no-metadata --require-as-include --compile $< > $@

# A lighter version of the compiler that excludes some features; experimental.
minifennel.lua: $(MINI_SRC) fennel
	./fennel --no-metadata --require-as-include --add-fennel-path src/?.fnl \
		--skip-include fennel.repl,fennel.view,fennel.friend --no-compiler-sandbox \
		--compile $< > $@

lint: fennel
	FENNEL_LINT_MODULES="^fennel%." ./fennel --no-compiler-sandbox \
		--add-fennel-path src/?.fnl --plugin src/linter.fnl \
		--require-as-include --compile src/fennel.fnl > /dev/null

## Binaries

LUA_DIR ?= lua
NATIVE_LUA_LIB ?= $(LUA_DIR)/liblua-native.a
LUA_INCLUDE_DIR ?= $(LUA_DIR)/src

COMPILE_ARGS=FENNEL_PATH=src/?.fnl FENNEL_MACRO_PATH=src/?.fnl CC_OPTS=-static

# Native binary for whatever platform you're currently on
fennel-bin: src/launcher.fnl fennel $(NATIVE_LUA_LIB)
	$(COMPILE_ARGS) ./fennel --no-compiler-sandbox --compile-binary \
		$< $@ $(NATIVE_LUA_LIB) $(LUA_INCLUDE_DIR)

$(LUA_DIR): .gitmodules ; git submodule update

$(NATIVE_LUA_LIB): $(LUA_DIR)
	$(MAKE) -C $(LUA_INCLUDE_DIR) clean liblua.a
	mv $(LUA_INCLUDE_DIR)/liblua.a $@

## Cross compiling

fennel-x86_64: src/launcher.fnl fennel $(LUA_INCLUDE_DIR)/liblua-x86_64.a
	$(COMPILE_ARGS) CC=x86_64-linux-gnu-gcc ./fennel --no-compiler-sandbox \
		--compile-binary $< $@ \
		$(LUA_INCLUDE_DIR)/liblua-x86_64.a $(LUA_INCLUDE_DIR)

fennel.exe: src/launcher.fnl fennel $(LUA_INCLUDE_DIR)/liblua-mingw.a
	$(COMPILE_ARGS) CC=i686-w64-mingw32-gcc ./fennel --no-compiler-sandbox \
		--compile-binary $< fennel-bin \
		$(LUA_INCLUDE_DIR)/liblua-mingw.a $(LUA_INCLUDE_DIR)
	mv fennel-bin.exe $@

fennel-arm32: src/launcher.fnl fennel $(LUA_INCLUDE_DIR)/liblua-arm32.a
	$(COMPILE_ARGS) CC=arm-linux-gnueabihf-gcc ./fennel --no-compiler-sandbox \
		--compile-binary $< $@  $(LUA_INCLUDE_DIR)/liblua-arm32.a $(LUA_INCLUDE_DIR)

$(LUA_INCLUDE_DIR)/liblua-x86_64.a: $(LUA_DIR)
	$(MAKE) -C $(LUA_INCLUDE_DIR) clean liblua.a CC=x86_64-linux-gnu-gcc
	mv $(LUA_INCLUDE_DIR)/liblua.a $@

# Cross-compilation here doesn't work from arm64; need to do it on x86_64
$(LUA_INCLUDE_DIR)/liblua-mingw.a: $(LUA_DIR)
	$(MAKE) -C $(LUA_INCLUDE_DIR) clean mingw CC=i686-w64-mingw32-gcc
	mv $(LUA_INCLUDE_DIR)/liblua.a $@

$(LUA_INCLUDE_DIR)/liblua-arm32.a: $(LUA_DIR)
	$(MAKE) -C $(LUA_INCLUDE_DIR) clean liblua.a CC=arm-linux-gnueabihf-gcc
	mv $(LUA_INCLUDE_DIR)/liblua.a $@

ci: testall lint fuzz fennel

clean:
	rm -f fennel.lua fennel fennel-bin fennel-x86_64 fennel.exe fennel-arm32 \
		*_binary.c luacov.* fennel.tar.gz fennel-*.src.rock
	$(MAKE) -C $(LUA_DIR) clean || true # this dir might not exist

coverage: fennel
	$(LUA) -lluacov test/init.lua
	@echo "generated luacov.report.out"

install: fennel fennel.lua fennel.1
	mkdir -p $(DESTDIR)$(BIN_DIR) && cp fennel $(DESTDIR)$(BIN_DIR)/
	mkdir -p $(DESTDIR)$(LUA_LIB_DIR) && cp fennel.lua $(DESTDIR)$(LUA_LIB_DIR)/
	mkdir -p $(DESTDIR)$(MAN_DIR) && cp fennel.1 $(DESTDIR)$(MAN_DIR)/

### Release

# The release should depend on only a handful of external things:
# * git
# * make
# * gcc (see .build.yml for specific packages needed for cross-compilation)

fennel.tar.gz: README.md LICENSE fennel.1 fennel fennel.lua Makefile $(SRC)
	test -n "$(VERSION)" # Need version
	rm -rf fennel-$(VERSION)
	mkdir fennel-$(VERSION)
	cp -r $^ fennel-$(VERSION)
	tar czf $@ fennel-$(VERSION)

uploadrock: rockspecs/fennel-$(VERSION)-1.rockspec
	luarocks --local build $<
	$(HOME)/.luarocks/bin/fennel --version | grep $(VERSION)
	luarocks --local remove fennel
	luarocks upload --api-key $(shell pass luarocks-api-key) $<
	luarocks --local install fennel
	$(HOME)/.luarocks/bin/fennel --version | grep $(VERSION)
	luarocks --local remove fennel

SSH_KEY ?= ~/.ssh/id_rsa

rockspecs/fennel-$(VERSION)-1.rockspec: rockspecs/template.fnl
	test -n "$(VERSION)" # Need version
	VERSION=$(VERSION) fennel --no-compiler-sandbox -c $< > $@
	git add $@

rockspec: rockspecs/fennel-$(VERSION)-1.rockspec

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
	ssh-keygen -Y sign -f $(SSH_KEY) -n file downloads/fennel-$(VERSION)
	ssh-keygen -Y sign -f $(SSH_KEY) -n file downloads/fennel-$(VERSION)-x86_64
	ssh-keygen -Y sign -f $(SSH_KEY) -n file downloads/fennel-$(VERSION)-windows32.exe
	ssh-keygen -Y sign -f $(SSH_KEY) -n file downloads/fennel-$(VERSION)-arm32
	ssh-keygen -Y sign -f $(SSH_KEY) -n file downloads/fennel-$(VERSION).tar.gz
	rsync -rtAv downloads/ fenneler@fennel-lang.org:fennel-lang.org/test-downloads/

release: uploadtar uploadrock

.PHONY: build test testall fuzz lint count format ci clean coverage install \
	uploadtar uploadrock release rockspec
