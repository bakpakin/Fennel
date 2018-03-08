LUA ?= lua

test:
	$(LUA) test.lua

testall:
	lua5.1 test.lua
	lua5.2 test.lua
	lua5.3 test.lua
	luajit test.lua

luacheck:
	luacheck fennel.lua fennel

count:
	cloc fennel.lua

ci: luacheck testall count
