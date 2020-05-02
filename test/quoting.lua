local l = require("luaunit")
local fennel = require("fennel")
local fennelview = require("fennelview")

local function c(code)
    return fennel.compileString(code, {allowedGlobals=false})
end

local function v(code)
    return fennelview(fennel.loadCode(c(code), _G)(), {["one-line"]=true})
end

local function test_quote()
    l.assertEquals(c('`:abcde'), "return \"abcde\"", "simple string quoting")
    l.assertEquals(c(',a'), "return unquote(a)",
                   "unquote outside quote is simply passed thru")
    l.assertEquals(v('`[1 2 ,(+ 1 2) 4]'), "[1 2 3 4]",
                   "unquote inside quote leads to evaluation")
    l.assertEquals(v('(let [a (+ 2 3)] `[:hey ,(+ a a)])'), '["hey" 10]',
                   "unquote inside other forms")
    l.assertEquals(v('`[:a :b :c]'), '[\"a\" \"b\" \"c\"]',
                   "quoted sequential table")
    local viewed = v('`{:a 5 :b 9}')
    l.assertTrue(viewed == "{:a 5 :b 9}" or viewed == "{:b 9 :a 5}",
                 "quoted keyed table: " .. viewed)
end

local function test_quoted_source()
    c("\n\n(eval-compiler (set _G.source-line (. `abc :line)))")
    l.assertEquals(_G["source-line"], 3, "syms have source data")

    c("\n(eval-compiler (set _G.source-line (. `abc# :line)))")
    l.assertEquals(_G["source-line"], 2, "autogensyms have source data")

    c("\n\n\n(eval-compiler (set _G.source-line (. `(abc) :line)))")
    -- TODO: this one's hard!
    -- l.assertEquals(_G["source-line"], 4, "lists have source data")

    local _, msg = pcall(c, "\n\n\n\n(macro abc [] `(fn [... a#] 1)) (abc)")
    l.assertStrContains(msg, "unknown:5", "quoted tables have source data")
end

return {test_quote=test_quote, test_quoted_source=test_quoted_source}
