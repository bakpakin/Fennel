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

# none of these actually work yet
# bugs reported/found:
# * https://github.com/mjanicek/rembulan/issues/17
# * https://github.com/luaj/luaj/issues/6
# * https://github.com/rvirding/luerl/issues/91
# * kahlua doesn't even define require, so ... probably not worth trying
testobscure:
	erl -run luerl dofile test.lua -s init stop -noshell | grep -v terminating
	java -cp luaj-jse-3.0.1.jar lua test.lua
	rembulan/rembulan-standalone/target/rembulan-capsule.x test.lua

obscuredeps:
	apt install erlang-luerl maven ant
	wget https://repo1.maven.org/maven2/org/luaj/luaj-jse/3.0.1/luaj-jse-3.0.1.jar
	git clone https://github.com/mjanicek/rembulan
	cd rembulan && mvn package -DskipTests -Dmaven.javadoc.skip=true -DstandaloneFinalName=rembulan && cd -
