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

# Precompile fennel libraries
%.lua: %.fnl fennel.lua
	./old_launcher.lua --globals "" --compile $< > $@

fennel: launcher.fnl fennel.lua fennelview.lua fennelfriend.lua
	echo "#!/usr/bin/env lua" > $@
	chmod 755 $@
	./old_launcher.lua --globals "" --require-as-include --no-searcher \
	  --metadata --compile $< >> $@

pre-compile: fennelview.lua fennelfriend.lua

ci: luacheck testall count pre-compile

.PHONY: test testall luacheck count pre-compile ci
