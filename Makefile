LUA ?= lua

test:
	$(LUA) test/init.lua

testall:
	lua5.1 test/init.lua
	lua5.2 test/init.lua
	lua5.3 test/init.lua
	luajit test/init.lua

luacheck:
	luacheck fennel.lua test/*.lua

count:
	cloc fennel.lua

# Precompile fennel libraries
%.lua: %.fnl fennel.lua
	./launcher.lua --compile $< > $@

fennel: launcher.fnl fennel.lua fennelview.lua fennelfriend.lua
	echo "#!/usr/bin/env lua" > $@
	chmod 755 $@
	./launcher.lua --require-as-include --no-searcher --compile $< >> $@

pre-compile: fennelview.lua fennelfriend.lua

ci: luacheck testall count pre-compile

.PHONY: test testall luacheck count pre-compile ci
