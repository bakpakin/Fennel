local l = require("luaunit")
local fennel = require("fennel")

local function c(code)
    return fennel.compileString(code, {allowedGlobals=false})
end

local function test_quote()
    l.assertEquals(c('`:abcde'), "return \"abcde\"", "simple string quoting")
    l.assertEquals(c(',a'), "return unquote(a)",
                   "unquote outside quote is simply passed thru")
    l.assertEquals(c('`[1 2 ,(+ 1 2) 4]'), "return {1, 2, (1 + 2), 4}",
                   "unquote inside quote leads to evaluation")
    l.assertEquals(c('(let [a (+ 2 3)] `[:hey ,(+ a a)])'),
                   "local a = (2 + 3)\nreturn {\"hey\", (a + a)}",
                   "unquote inside other forms")
    l.assertEquals(c('`[:a :b :c]'), "return {\"a\", \"b\", \"c\"}",
                   "quoted sequential table")
    local compiled = c('`{:a 5 :b 9}')
    l.assertTrue(compiled == "return {[\"a\"]=5, [\"b\"]=9}" or
                     compiled == "return {[\"b\"]=9, [\"a\"]=5}",
                 "quoted keyed table")

    -- syms have source data
    c("\n\n(eval-compiler (set _G.source-line (. `abc :line)))")
    l.assertEquals(_G["source-line"], 3)
    -- autogensyms have source data
    c("\n(eval-compiler (set _G.source-line (. `abc# :line)))")
    l.assertEquals(_G["source-line"], 2)
    -- lists have source data
    -- tables have source data
end

return {test_quote=test_quote}
