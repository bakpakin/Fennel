LUA ?= lua
LUA_VERSION ?= $(shell $(LUA) -e 'v=_VERSION:gsub("^Lua *","");print(v)')
DESTDIR ?=
PREFIX ?= /usr/local
BIN_DIR ?= $(PREFIX)/bin
LUA_LIB_DIR ?= $(PREFIX)/share/lua/$(LUA_VERSION)
MAN_DIR ?= $(PREFIX)/share

MAKEFLAGS += --no-print-directory

MINI_SRC=src/fennel.fnl src/fennel/parser.fnl src/fennel/specials.fnl \
		src/fennel/utils.fnl src/fennel/compiler.fnl  src/fennel/macros.fnl \
		src/fennel/match.fnl

LIB_SRC=$(MINI_SRC) src/fennel/friend.fnl src/fennel/view.fnl src/fennel/repl.fnl

SRC=$(LIB_SRC) src/launcher.fnl src/fennel/binary.fnl

MAN_PANDOC = pandoc -f gfm -t man -s --lua-filter=build/manfilter.lua \
	     --metadata author="Fennel Maintainers" \
	     --variable footer="fennel $(shell ./fennel -e '(. (require :fennel) :version)')"

build: fennel fennel.lua

test: fennel.lua fennel test/faith.lua
	@LUA_PATH=?.lua $(LUA) test/init.lua $(TESTS)
	@echo

testall: export FNL_TEST_OUTPUT=text
testall: export FNL_TESTALL=yes
testall: fennel # recursive make considered not really a big deal; calm down
	$(MAKE) test LUA=lua5.1
	$(MAKE) test LUA=lua5.2
	$(MAKE) test LUA=lua5.3
	$(MAKE) test LUA=lua5.4
	$(MAKE) test LUA=luajit

fuzz: ; $(MAKE) test TESTS=test.fuzz

# older versions of cloc might need --force-lang=lisp
count: ; cloc $(MINI_SRC); cloc $(LIB_SRC) ; cloc $(SRC)

# install https://git.sr.ht/~technomancy/fnlfmt manually for this:
format: ; for f in $(SRC); do fnlfmt --fix $$f ; done

# All-in-one pure-lua script:
fennel: src/launcher.fnl $(SRC) bootstrap/view.lua
	@echo "#!/usr/bin/env $(LUA)" > $@
	@echo "-- SPDX-License-Identifier: MIT" >> $@
	@echo "-- SPDX-FileCopyrightText: Calvin Rose and contributors" >> $@
	FENNEL_PATH=src/?.fnl $(LUA) bootstrap/aot.lua $< --require-as-include >> $@
	@chmod 755 $@

# Library file
fennel.lua: $(SRC) bootstrap/aot.lua bootstrap/view.lua
	@echo "-- SPDX-License-Identifier: MIT" > $@
	@echo "-- SPDX-FileCopyrightText: Calvin Rose and contributors" >> $@
	FENNEL_PATH=src/?.fnl $(LUA) bootstrap/aot.lua $< --require-as-include >> $@

bootstrap/view.lua: src/fennel/view.fnl
	FENNEL_PATH=src/?.fnl $(LUA) bootstrap/aot.lua $< > $@

test/faith.lua: test/faith.fnl
	$(LUA) bootstrap/aot.lua $< > $@

# A lighter version of the compiler that excludes some features; experimental.
minifennel.lua: $(MINI_SRC) fennel
	echo "-- SPDX-License-Identifier: MIT" > $@
	echo "-- SPDX-FileCopyrightText: Calvin Rose and contributors" >> $@
	./fennel --no-metadata --require-as-include --add-fennel-path src/?.fnl \
		--skip-include fennel.repl,fennel.view,fennel.friend --no-compiler-sandbox \
		--compile $< >> $@

lint: fennel
	@FENNEL_LINT_MODULES="^fennel%." ./fennel --no-compiler-sandbox \
		--add-fennel-path src/?.fnl --plugin src/linter.fnl \
		--require-as-include --compile src/fennel.fnl > /dev/null

check:
	find src -name "*fnl" | xargs fennel-ls --check

## Binaries

BIN_LUA_VERSION ?= 5.4.6
BIN_LUAJIT_VERSION ?= 2.0.5
BIN_LUA_DIR ?= $(PWD)/lua-$(BIN_LUA_VERSION)
BIN_LUAJIT_DIR ?= $(PWD)/LuaJIT-$(BIN_LUAJIT_VERSION)
NATIVE_LUA_LIB ?= $(BIN_LUA_DIR)/src/liblua-native.a
NATIVE_LUAJIT_LIB ?= $(BIN_LUAJIT_DIR)/src/libluajit.a
LUA_INCLUDE_DIR ?= $(BIN_LUA_DIR)/src
LUAJIT_INCLUDE_DIR ?= $(BIN_LUAJIT_DIR)/src

COMPILE_ARGS=FENNEL_PATH=src/?.fnl FENNEL_MACRO_PATH=src/?.fnl CC_OPTS=-static
LUAJIT_COMPILE_ARGS=FENNEL_PATH=src/?.fnl FENNEL_MACRO_PATH=src/?.fnl

$(BIN_LUA_DIR): ; curl https://www.lua.org/ftp/lua-$(BIN_LUA_VERSION).tar.gz | tar xz

$(BIN_LUAJIT_DIR): ; curl https://luajit.org/download/LuaJIT-$(BIN_LUAJIT_VERSION).tar.gz | tar xz

# Native binary for whatever platform you're currently on
fennel-bin: src/launcher.fnl fennel $(NATIVE_LUA_LIB)
	$(COMPILE_ARGS) ./fennel --no-compiler-sandbox --compile-binary \
		$< $@ $(NATIVE_LUA_LIB) $(LUA_INCLUDE_DIR)

fennel-bin-luajit: src/launcher.fnl fennel $(NATIVE_LUAJIT_LIB)
	$(LUAJIT_COMPILE_ARGS) ./fennel --no-compiler-sandbox --compile-binary \
		$< $@ $(NATIVE_LUAJIT_LIB) $(LUAJIT_INCLUDE_DIR)

$(NATIVE_LUA_LIB): $(BIN_LUA_DIR)
	$(MAKE) -C $(BIN_LUA_DIR)/src clean liblua.a
	mv $(BIN_LUA_DIR)/src/liblua.a $@

$(NATIVE_LUAJIT_LIB): $(BIN_LUAJIT_DIR)
	$(MAKE) -C $(BIN_LUAJIT_DIR) BUILDMODE=static

## Cross compiling

xc-deps:
	apt install -y gcc-arm-linux-gnueabihf libc6-dev-armhf-cross curl \
		gcc-multilib-x86-64-linux-gnu libc6-dev-amd64-cross gcc-mingw-w64-i686

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

$(BIN_LUA_DIR)/src/liblua-x86_64.a: $(BIN_LUA_DIR)
	$(MAKE) -C $(BIN_LUA_DIR)/src clean posix liblua.a
	mv $(BIN_LUA_DIR)/src/liblua.a $@

# Cross-compilation here doesn't work from arm64; need to do it on x86_64
$(BIN_LUA_DIR)/src/liblua-mingw.a: $(BIN_LUA_DIR)
	$(MAKE) -C $(BIN_LUA_DIR)/src clean mingw CC=i686-w64-mingw32-gcc
	mv $(BIN_LUA_DIR)/src/liblua.a $@

$(BIN_LUA_DIR)/src/liblua-arm32.a: $(BIN_LUA_DIR)
	$(MAKE) -C $(BIN_LUA_DIR)/src clean posix liblua.a CC=arm-linux-gnueabihf-gcc
	mv $(BIN_LUA_DIR)/src/liblua.a $@

ci: testall lint fuzz fennel

clean:
	rm -f fennel.lua fennel fennel-bin fennel-x86_64 fennel.exe fennel-arm32 \
		*_binary.c luacov.* fennel.tar.gz fennel-*.src.rock bootstrap/view.lua \
		test/faith.lua minifennel.lua build/manfilter.lua fennel-bin-luajit
	$(MAKE) -C $(BIN_LUA_DIR) clean || true # this dir might not exist
	$(MAKE) -C $(BIN_LUAJIT_DIR) clean || true # this dir might not exist
	rm -f $(NATIVE_LUA_LIB) $(NATIVE_LUAJIT_LIB)

coverage: fennel
	$(LUA) -lluacov test/init.lua
	@echo "generated luacov.report.out"

MAN_DOCS := man/man1/fennel.1 man/man3/fennel-api.3 man/man5/fennel-reference.5\
	    man/man7/fennel-tutorial.7

define maninst =
mkdir -p $(dir $(2)) && cp $(1) $(2)

endef

install: fennel fennel.lua
	mkdir -p $(DESTDIR)$(BIN_DIR) && cp fennel $(DESTDIR)$(BIN_DIR)/
	mkdir -p $(DESTDIR)$(LUA_LIB_DIR) && cp fennel.lua $(DESTDIR)$(LUA_LIB_DIR)/
	$(foreach doc,$(MAN_DOCS),\
		$(call maninst,$(doc),$(DESTDIR)$(MAN_DIR)/$(doc)))

uninstall:
	rm $(DESTDIR)$(BIN_DIR)/fennel
	rm $(DESTDIR)$(LUA_LIB_DIR)/fennel.lua
	rm $(addprefix $(DESTDIR)$(MAN_DIR)/,$(MAN_DOCS))

build/manfilter.lua: build/manfilter.fnl fennel.lua fennel
	./fennel --correlate --compile $< > $@

man: $(dir $(MAN_DOCS)) $(MAN_DOCS)

man/man%/: ; mkdir -p $@

man/man3/fennel-%.3: %.md build/manfilter.lua ; $(MAN_PANDOC) $< -o $@

man/man5/fennel-%.5: %.md build/manfilter.lua ; $(MAN_PANDOC) $< -o $@

man/man7/fennel-%.7: %.md build/manfilter.lua ; $(MAN_PANDOC) $< -o $@

# Release-related tasks:

fennel.tar.gz: README.md LICENSE $(MAN_DOCS) fennel fennel.lua \
		Makefile $(SRC)
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
	VERSION=$(VERSION) fennel --no-compiler-sandbox -c $< > $@
	git add $@

rockspec: rockspecs/fennel-$(VERSION)-1.rockspec

test-builds: fennel fennel-x86_64 test/faith.lua
	./fennel --metadata --eval "(require :test.init)"
	./fennel-x86_64 --metadata --eval "(require :test.init)"

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
	rsync -rtAv downloads/ fenneler@fennel-lang.org:fennel-lang.org/downloads/

release: test-builds guard-VERSION uploadtar uploadrock

guard-%:
	@ if [ "${${*}}" = "" ]; then \
		echo "Environment variable $* not set"; \
		exit 1; \
	fi

.PHONY: build test testall fuzz lint count format ci clean coverage install man \
	uploadtar uploadrock release rockspec xc-deps guard-VERSION test-builds
