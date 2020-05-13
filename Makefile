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
	luacheck fennel.lua test/*.lua

count:
	cloc fennel.lua
	cloc --force-lang=lisp fennelview.fnl fennelfriend.fnl launcher.fnl

# For the time being, avoid chicken/egg situation thru the old Lua launcher.
LAUNCHER=./old_launcher.lua

# Precompile fennel libraries
%.lua: %.fnl fennel.lua
	 $(LAUNCHER) --globals "" --compile $< > $@

fennel: launcher.fnl fennel.lua fennelview.lua fennelfriend.lua
	echo "#!/usr/bin/env lua" > $@
	$(LAUNCHER) --globals "" --require-as-include --metadata --compile $< >> $@
	chmod 755 $@

ci: luacheck testall count

.PHONY: test testall luacheck count ci
