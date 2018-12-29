LUA ?= lua

test:
	$(LUA) test.lua

testall:
	lua5.1 test.lua
	lua5.2 test.lua
	lua5.3 test.lua
	luajit test.lua

luacheck:
	luacheck fennel.lua fennel test.lua

count:
	cloc fennel.lua

# Precompile fennel libraries
%.fnl.lua: %.fnl fennel fennel.lua
	./fennel --compile $< > $@

pre-compile: fennelview.fnl.lua

ci: luacheck testall count pre-compile
