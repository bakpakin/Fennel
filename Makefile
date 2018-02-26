LUA ?= lua

test:
	$(LUA) test.lua

luacheck:
	luacheck fennel.lua fennel

count:
	cloc fennel.lua

ci: luacheck test count
