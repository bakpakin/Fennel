LUA ?= lua

test:
	$(LUA) test/init.lua

testall:
	lua5.1 test/init.lua
	lua5.2 test/init.lua
	lua5.3 test/init.lua
	luajit test/init.lua

luacheck:
	luacheck fennel.lua fennel test/*.lua

count:
	cloc fennel.lua

# Precompile fennel libraries
%.fnl.lua: %.fnl fennel fennel.lua
	./fennel --compile $< > $@

pre-compile: fennelview.fnl.lua

ci: luacheck testall count pre-compile

.PHONY: test testall luacheck count pre-compile ci
