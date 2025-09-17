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

PRECOMPILED=bootstrap/view.lua bootstrap/macros.lua bootstrap/match.lua

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
fennel: src/launcher.fnl $(SRC) bootstrap/aot.lua $(PRECOMPILED)
	@echo "#!/usr/bin/env $(LUA)" > $@
	@echo "-- SPDX-License-Identifier: MIT" >> $@
	@echo "-- SPDX-FileCopyrightText: Calvin Rose and contributors" >> $@
	FENNEL_PATH=src/?.fnl $(LUA) bootstrap/aot.lua $< --require-as-include >> $@
	@chmod 755 $@

# Library file
fennel.lua: $(SRC) bootstrap/aot.lua $(PRECOMPILED)
	@echo "-- SPDX-License-Identifier: MIT" > $@
	@echo "-- SPDX-FileCopyrightText: Calvin Rose and contributors" >> $@
	FENNEL_PATH=src/?.fnl $(LUA) bootstrap/aot.lua $< --require-as-include >> $@

bootstrap/macros.lua: src/fennel/macros.fnl; $(LUA) bootstrap/aot.lua $< --macro > $@
bootstrap/match.lua: src/fennel/match.fnl; $(LUA) bootstrap/aot.lua $< --macro > $@
bootstrap/view.lua: src/fennel/view.fnl
	FENNEL_PATH=src/?.fnl $(LUA) bootstrap/aot.lua $< > $@

test/faith.lua: test/faith.fnl
	$(LUA) bootstrap/aot.lua $< > $@

lint:
	fennel-ls --lint $(SRC)

ci: testall fuzz fennel fennel-bin
	./fennel-bin --eval '(print "binary works!")'

clean:
	rm -f fennel.lua fennel fennel-bin fennel.exe \
		*_binary.c luacov.* $(PRECOMPILED) \
		test/faith.lua build/manfilter.lua fennel-bin-luajit
	$(MAKE) -C $(BIN_LUA_DIR) clean || true # this dir might not exist
	$(MAKE) -C $(BIN_LUAJIT_DIR) clean || true # this dir might not exist
	rm -f $(NATIVE_LUA_LIB) $(NATIVE_LUAJIT_LIB)

coverage: fennel
	$(LUA) -lluacov test/init.lua
	@echo "generated luacov.report.out"

## Binaries

BIN_LUA_DIR ?= lua
BIN_LUAJIT_DIR ?= luajit
NATIVE_LUA_LIB ?= $(BIN_LUA_DIR)/src/liblua.a
NATIVE_LUAJIT_LIB ?= $(BIN_LUAJIT_DIR)/src/libluajit.a
LUA_INCLUDE_DIR ?= $(BIN_LUA_DIR)/src
LUAJIT_INCLUDE_DIR ?= $(BIN_LUAJIT_DIR)/src

COMPILE_ARGS=FENNEL_PATH=src/?.fnl FENNEL_MACRO_PATH=src/?.fnl CC_OPTS=-static
LUAJIT_COMPILE_ARGS=FENNEL_PATH=src/?.fnl FENNEL_MACRO_PATH=src/?.fnl

$(LUA_INCLUDE_DIR): ; git submodule update --init
$(LUAJIT_INCLUDE_DIR): ; git submodule update --init

# Native binary for whatever platform you're currently on
fennel-bin: src/launcher.fnl $(BIN_LUA_DIR)/src/lua $(NATIVE_LUA_LIB) fennel
	$(COMPILE_ARGS) $(BIN_LUA_DIR)/src/lua fennel \
		--no-compiler-sandbox --compile-binary \
		$< $@ $(NATIVE_LUA_LIB) $(LUA_INCLUDE_DIR)

fennel-bin-luajit: src/launcher.fnl $(NATIVE_LUAJIT_LIB) fennel
	$(LUAJIT_COMPILE_ARGS) $(BIN_LUAJIT_DIR)/src/luajit fennel \
		--no-compiler-sandbox --compile-binary \
		$< $@ $(NATIVE_LUAJIT_LIB) $(LUAJIT_INCLUDE_DIR)

$(BIN_LUA_DIR)/src/lua: $(LUA_INCLUDE_DIR) ; make -C $(BIN_LUA_DIR)
$(NATIVE_LUA_LIB): $(LUA_INCLUDE_DIR) ; $(MAKE) -C $(BIN_LUA_DIR)/src liblua.a
$(NATIVE_LUAJIT_LIB): $(LUAJIT_INCLUDE_DIR)
	$(MAKE) -C $(BIN_LUAJIT_DIR) BUILDMODE=static

fennel.exe: src/launcher.fnl fennel $(LUA_INCLUDE_DIR)/liblua-mingw.a
	$(COMPILE_ARGS) ./fennel --no-compiler-sandbox \
		--compile-binary $< fennel-bin \
		$(LUA_INCLUDE_DIR)/liblua-mingw.a $(LUA_INCLUDE_DIR)
	mv fennel-bin.exe $@

$(BIN_LUA_DIR)/src/liblua-mingw.a: $(LUA_INCLUDE_DIR)
	$(MAKE) -C $(BIN_LUA_DIR)/src clean mingw CC=x86_64-w64-mingw32-gcc
	mv $(BIN_LUA_DIR)/src/liblua.a $@
	$(MAKE) -C $(BIN_LUA_DIR)/src clean

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
	rm -f $(DESTDIR)$(BIN_DIR)/fennel
	rm -f $(DESTDIR)$(LUA_LIB_DIR)/fennel.lua
	rm -f $(addprefix $(DESTDIR)$(MAN_DIR)/,$(MAN_DOCS))

build/manfilter.lua: build/manfilter.fnl fennel.lua fennel
	./fennel --correlate --compile $< > $@

man: $(dir $(MAN_DOCS)) $(MAN_DOCS)
man/man%/: ; mkdir -p $@
man/man3/fennel-%.3: %.md build/manfilter.lua
	$(MAN_PANDOC) $< -o $@
	sed -i.tmp 's/\\f\[C\]/\\f[CR]/g' $@ # work around pandoc 2.x bug
man/man5/fennel-%.5: %.md build/manfilter.lua
	$(MAN_PANDOC) $< -o $@
	sed -i.tmp 's/\\f\[C\]/\\f[CR]/g' $@ # work around pandoc 2.x bug
man/man7/fennel-%.7: %.md build/manfilter.lua
	$(MAN_PANDOC) $< -o $@
	sed -i.tmp 's/\\f\[C\]/\\f[CR]/g' $@ # work around pandoc 2.x bug

## Release-related tasks:

SSH_KEY ?= ~/.ssh/id_ed25519.pub

test-builds: fennel test/faith.lua
	./fennel --metadata --eval "(require :test.init)"
	$(MAKE) install PREFIX=/tmp/opt

upload: fennel fennel.lua fennel-bin
	$(MAKE) fennel.exe CC=x86_64-w64-mingw32-gcc
	mkdir -p downloads/
	mv fennel downloads/fennel-$(VERSION)
	mv fennel.lua downloads/fennel-$(VERSION).lua
	mv fennel-bin downloads/fennel-$(VERSION)-x86_64
	mv fennel.exe downloads/fennel-$(VERSION).exe
	gpg -ab downloads/fennel-$(VERSION)
	gpg -ab downloads/fennel-$(VERSION).lua
	gpg -ab downloads/fennel-$(VERSION)-x86_64
	gpg -ab downloads/fennel-$(VERSION).exe
	ssh-keygen -Y sign -f $(SSH_KEY) -n file downloads/fennel-$(VERSION)
	ssh-keygen -Y sign -f $(SSH_KEY) -n file downloads/fennel-$(VERSION).lua
	ssh-keygen -Y sign -f $(SSH_KEY) -n file downloads/fennel-$(VERSION)-x86_64
	ssh-keygen -Y sign -f $(SSH_KEY) -n file downloads/fennel-$(VERSION).exe
	rsync -rtAv downloads/fennel-$(VERSION)* \
		fenneler@fennel-lang.org:fennel-lang.org/downloads/

release: guard-VERSION upload
	git tag -v $(VERSION) # created by prerelease target
	git push
	git push --tags
	@echo "* Update the submodule in the fennel-lang.org repository."
	@echo "* Announce the release on the mailing list."
	@echo "* Bump the version in src/fennel/utils.fnl to the next dev version."
	@echo "* Add a stub for the next version in changelog.md"

prerelease: guard-VERSION ci test-builds
	@echo "Did you look for changes that need to be mentioned in help/man text?"
	sed -i.tmp s/$(VERSION)-dev/$(VERSION)/ src/fennel/utils.fnl
	$(MAKE) man
	grep "$(VERSION)" setup.md > /dev/null
	! grep "???" changelog.md
	git commit -a -m "Release $(VERSION)"
	git tag -s $(VERSION) -m $(VERSION)

guard-%:
	@ if [ "${${*}}" = "" ]; then \
		echo "Environment variable $* not set"; \
		exit 1; \
	fi

.PHONY: build test testall fuzz count format ci clean coverage install \
	man upload prerelease release guard-VERSION test-builds lint

# Steps to release a new Fennel version

# The `make release` command should be run on a system with the lowest
# available glibc for maximum compatibility.

# 1. Check for changes which need to be mentioned in help text or man page
# 2. Date `changelog.md` and update download links in `setup.md`
# 3. Run `make prerelease VERSION=$VERSION`
# 4. Update fennel-lang.org's fennel submodule and `make html` there
# 5. Run `make release VERSION=$VERSION`
# 6. Run `make upload` in fennel-lang.org.
# 7. Announce on the mailing list
