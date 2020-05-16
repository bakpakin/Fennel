LUA ?= lua

test: fennel
	$(LUA) test/init.lua

testall: export FNL_TEST_OUTPUT ?= text
testall: fennel
	@printf 'Testing lua 5.1:\n'  ; lua5.1 test/init.lua
	@printf "\nTesting lua 5.2:\n"; lua5.2 test/init.lua
	@printf "\nTesting lua 5.3:\n"; lua5.3 test/init.lua
	@printf "\nTesting luajit:\n" ; luajit test/init.lua

luacheck:
	luacheck fennel.lua test/init.lua test/mangling.lua \
		test/misc.lua test/quoting.lua

count:
	cloc fennel.lua
	cloc --force-lang=lisp fennelview.fnl fennelfriend.fnl fennelbinary.fnl \
		launcher.fnl

# For the time being, avoid chicken/egg situation thru the old Lua launcher.
LAUNCHER=./old_launcher.lua

# Precompile fennel libraries
%.lua: %.fnl fennel.lua
	 $(LAUNCHER) --globals "" --compile $< > $@

fennel: launcher.fnl fennel.lua fennelview.lua fennelfriend.lua fennelbinary.fnl
	echo "#!/usr/bin/env lua" > $@
	$(LAUNCHER) --globals "" --require-as-include --metadata --compile $< >> $@
	chmod 755 $@

# Change these up to swap out the version of Lua or for other operating systems.
STATIC_LUA_LIB ?= /usr/lib/x86_64-linux-gnu/liblua5.3.a
LUA_INCLUDE_DIR ?= /usr/include/lua5.3

fennel-bin: launcher.fnl fennel
	fennel --compile-binary $< $@ $(STATIC_LUA_LIB) $(LUA_INCLUDE_DIR)

ci: luacheck testall count

.PHONY: test testall luacheck count ci
