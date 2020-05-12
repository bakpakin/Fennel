LUA ?= lua

test: fennel
	$(LUA) test/init.lua

testall: export FNL_TEST_OUTPUT ?= text
testall: fennel
	@echo -e 'Testing lua 5.1:'  ; lua5.1 test/init.lua
	@echo -e "\nTesting lua 5.2:"; lua5.2 test/init.lua
	@echo -e "\nTesting lua 5.3:"; lua5.3 test/init.lua
	@echo -e "\nTesting luajit:" ; luajit test/init.lua

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
		--compile $< >> $@

pre-compile: fennelview.lua fennelfriend.lua

ci: luacheck testall count pre-compile

.PHONY: test testall luacheck count pre-compile ci
