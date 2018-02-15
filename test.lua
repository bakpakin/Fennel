#!/usr/bin/env lua
local t = require("lunatest")
local fnl = require("fnl")

t.suite("test_core")

t.run(nil, {"--verbose"})
