LUA ?= lua

test:
	$(LUA) test.lua

luacheck:
	luacheck fnl.lua

count:
	cloc fnl.lua

ci: luacheck test count
