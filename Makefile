LUA ?= lua

test:
	$(LUA) test.lua

luacheck:
	luacheck fennel.lua

count:
	cloc fennel.lua

ci: luacheck test count
