LUA ?= lua
LUA_VERSION ?= $(shell $(LUA) -e 'v=_VERSION:gsub("^Lua *","");print(v)')
DESTDIR ?=
PREFIX ?= /usr/local
BIN_DIR ?= $(PREFIX)/bin
LUA_LIB_DIR ?= $(PREFIX)/share/lua/$(LUA_VERSION)
MAN_DIR ?= $(PREFIX)/share

MAKEFLAGS += --no-print-directory

CORE_SRC=src/fennel.fnl src/fennel/parser.fnl src/fennel/specials.fnl \
		src/fennel/utils.fnl src/fennel/compiler.fnl  src/fennel/macros.fnl \
		src/fennel/match.fnl

LIB_SRC=$(CORE_SRC) src/fennel/friend.fnl src/fennel/view.fnl src/fennel/repl.fnl

SRC=$(LIB_SRC) src/launcher.fnl src/fennel/binary.fnl

MAN_PANDOC = pandoc -f gfm -t man -s --lua-filter=build/manfilter.lua \
	     --metadata author="Fennel Maintainers" \
	     --variable footer="fennel $(shell ./fennel -e '(. (require :fennel) :version)')"

unexport NO_COLOR # this causes test failures
unexport FENNEL_PATH FENNEL_MACRO_PATH # ensure isolation

build: fennel fennel.lua

test: fennel.lua fennel test/faith.lua
	@LUA_PATH=?.lua $(LUA) test/init.lua $(TESTS)
	@echo

testall: export FNL_TESTALL=yes
testall: fennel test/faith.lua # recursive make considered not really a big deal
	$(MAKE) test LUA=lua5.1
	$(MAKE) test LUA=lua5.2
	$(MAKE) test LUA=lua5.3
	$(MAKE) test LUA=lua5.4
	$(MAKE) test LUA=luajit

fuzz: fennel ; $(MAKE) test TESTS=test.fuzz

count: ; cloc $(CORE_SRC); cloc $(LIB_SRC) ; cloc $(SRC)

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

lint: fennel
	@FENNEL_LINT_MODULES="^fennel%." ./fennel --no-compiler-sandbox \
		--add-fennel-path src/?.fnl --plugin src/linter.fnl \
		--require-as-include --compile src/fennel.fnl > /dev/null

check:
	fennel-ls --check $(SRC)

ci: testall lint fuzz fennel

clean:
	rm -f fennel.lua fennel fennel-bin fennel.exe \
		*_binary.c luacov.* fennel-*.src.rock bootstrap/view.lua \
		test/faith.lua build/manfilter.lua fennel-bin-luajit
	$(MAKE) -C $(BIN_LUA_DIR) clean || true # this dir might not exist
	$(MAKE) -C $(BIN_LUAJIT_DIR) clean || true # this dir might not exist
	rm -f $(NATIVE_LUA_LIB) $(NATIVE_LUAJIT_LIB)

coverage: fennel
	$(LUA) -lluacov test/init.lua
	@echo "generated luacov.report.out"

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

$(BIN_LUA_DIR):
	curl https://www.lua.org/ftp/lua-$(BIN_LUA_VERSION).tar.gz | tar xz

$(BIN_LUAJIT_DIR):
	curl https://luajit.org/download/LuaJIT-$(BIN_LUAJIT_VERSION).tar.gz | tar xz

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

fennel.exe: src/launcher.fnl fennel $(LUA_INCLUDE_DIR)/liblua-mingw.a
	$(COMPILE_ARGS) CC=i686-w64-mingw32-gcc ./fennel --no-compiler-sandbox \
		--compile-binary $< fennel-bin \
		$(LUA_INCLUDE_DIR)/liblua-mingw.a $(LUA_INCLUDE_DIR)
	mv fennel-bin.exe $@

$(BIN_LUA_DIR)/src/liblua-mingw.a: $(BIN_LUA_DIR)
	$(MAKE) -C $(BIN_LUA_DIR)/src clean mingw CC=i686-w64-mingw32-gcc
	mv $(BIN_LUA_DIR)/src/liblua.a $@

## Install-related tasks:

MAN_DOCS := man/man1/fennel.1 man/man3/fennel-api.3 man/man5/fennel-reference.5\
	    man/man7/fennel-tutorial.7

# The empty line in maninst is necessary for it to emit distinct commands
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

## Release-related tasks:

SSH_KEY ?= ~/.ssh/id_ed25519.pub

uploadrock: rockspecs/fennel-$(VERSION)-1.rockspec
	luarocks upload --api-key $(shell pass luarocks-api-key) $<

rockspecs/fennel-$(VERSION)-1.rockspec: rockspecs/template.fnl
	@echo TODO: this depends on the broken tarball
	exit 1
	VERSION=$(VERSION) fennel --no-compiler-sandbox -c $< > $@
	git add $@

rockspec: rockspecs/fennel-$(VERSION)-1.rockspec

test-builds: fennel test/faith.lua
	./fennel --metadata --eval "(require :test.init)"
	$(MAKE) install PREFIX=/tmp/opt

upload: fennel fennel.lua fennel-bin fennel.exe
	mkdir -p downloads/
	mv fennel downloads/fennel-$(VERSION)
	mv fennel.lua downloads/fennel-$(VERSION).lua
	mv fennel-bin downloads/fennel-$(VERSION)-x86_64
	mv fennel.exe downloads/fennel-$(VERSION)-windows32.exe
	gpg -ab downloads/fennel-$(VERSION)
	gpg -ab downloads/fennel-$(VERSION).lua
	gpg -ab downloads/fennel-$(VERSION)-x86_64
	gpg -ab downloads/fennel-$(VERSION)-windows32.exe
	ssh-keygen -Y sign -f $(SSH_KEY) -n file downloads/fennel-$(VERSION)
	ssh-keygen -Y sign -f $(SSH_KEY) -n file downloads/fennel-$(VERSION).lua
	ssh-keygen -Y sign -f $(SSH_KEY) -n file downloads/fennel-$(VERSION)-x86_64
	ssh-keygen -Y sign -f $(SSH_KEY) -n file downloads/fennel-$(VERSION)-windows32.exe
	rsync -rtAv downloads/fennel-$(VERSION)* \
		fenneler@fennel-lang.org:fennel-lang.org/downloads/

release: guard-VERSION upload uploadrock
	git push
	git push --tags
	@echo "* Update the submodule in the fennel-lang.org repository."
	@echo "* Announce the release on the mailing list."
	@echo "* Bump the version in src/fennel/utils.fnl to the next dev version."
	@echo "* Add a stub for the next version in changelog.md"

prerelease: guard-VERSION ci test-builds
	@echo "Did you look for changes that need to be mentioned in help/man text?"
	exit 1 # TODO: update setup.md to stop linking to tarball
	sed -i s/$(VERSION)-dev/$(VERSION)/ src/fennel/utils.fnl
	$(MAKE) man rockspec
	grep "$(VERSION)" setup.md > /dev/null
	! grep "???" changelog.md
	git commit -a -m "Release $(VERSION)"
	git tag -s $(VERSION) -m $(VERSION)

guard-%:
	@ if [ "${${*}}" = "" ]; then \
		echo "Environment variable $* not set"; \
		exit 1; \
	fi

.PHONY: build test testall fuzz lint count format ci clean coverage install \
	man upload uploadrock prerelease release rockspec guard-VERSION test-builds
