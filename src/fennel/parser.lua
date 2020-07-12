local utils = require("fennel.utils")
local unpack = _G.unpack or table.unpack

-- Convert a stream of chunks to a stream of bytes.
-- Also returns a second function to clear the buffer in the byte stream
local function granulate(getchunk)
    local c = ''
    local index = 1
    local done = false
    return function (parserState)
        if done then return nil end
        if index <= #c then
            local b = c:byte(index)
            index = index + 1
            return b
        else
            c = getchunk(parserState)
            if not c or c == '' then
                done = true
                return nil
            end
            index = 2
            return c:byte(1)
        end
    end, function ()
        c = ''
    end
end

-- Convert a string into a stream of bytes
local function stringStream(str)
    str=str:gsub("^#![^\n]*\n", "") -- remove shebang
    local index = 1
    return function()
        local r = str:byte(index)
        index = index + 1
        return r
    end
end

-- Table of delimiter bytes - (, ), [, ], {, }
-- Opener keys have closer as the value, and closers keys
-- have true as their value.
local delims = {
    [40] = 41,        -- (
    [41] = true,      -- )
    [91] = 93,        -- [
    [93] = true,      -- ]
    [123] = 125,      -- {
    [125] = true      -- }
}

local function iswhitespace(b)
    return b == 32 or (b >= 9 and b <= 13)
end

local function issymbolchar(b)
    return b > 32 and
        not delims[b] and
        b ~= 127 and -- "<BS>"
        b ~= 34 and -- "\""
        b ~= 39 and -- "'"
        b ~= 126 and -- "~"
        b ~= 59 and -- ";"
        b ~= 44 and -- ","
        b ~= 64 and -- "@"
        b ~= 96 -- "`"
end

local prefixes = { -- prefix chars substituted while reading
    [96] = 'quote', -- `
    [44] = 'unquote', -- ,
    [39] = 'quote', -- '
    [35] = 'hashfn' -- #
}

-- Parse one value given a function that
-- returns sequential bytes. Will throw an error as soon
-- as possible without getting more bytes on bad input. Returns
-- if a value was read, and then the value read. Will return nil
-- when input stream is finished.
local function parser(getbyte, filename, options)

    -- Stack of unfinished values
    local stack = {}

    -- Provide one character buffer and keep
    -- track of current line and byte index
    local line = 1
    local byteindex = 0
    local lastb
    local function ungetb(ub)
        if ub == 10 then line = line - 1 end
        byteindex = byteindex - 1
        lastb = ub
    end
    local function getb()
        local r
        if lastb then
            r, lastb = lastb, nil
        else
            r = getbyte({ stackSize = #stack })
        end
        byteindex = byteindex + 1
        if r == 10 then line = line + 1 end
        return r
    end

    -- If you add new calls to this function, please update fenneldfriend.fnl
    -- as well to add suggestions for how to fix the new error.
    local function parseError(msg)
        local source = utils.root.options and utils.root.options.source
        utils.root.reset()
        local override = options and options["parse-error"]
        if override then override(msg, filename or "unknown", line or "?",
                                  byteindex, source) end
        return error(("Parse error in %s:%s: %s"):
                format(filename or "unknown", line or "?", msg), 0)
    end

    -- Parse stream
    return function()

        -- Dispatch when we complete a value
        local done, retval
        local whitespaceSinceDispatch = true
        local function dispatch(v)
            if #stack == 0 then
                retval = v
                done = true
            elseif stack[#stack].prefix then
                local stacktop = stack[#stack]
                stack[#stack] = nil
                return dispatch(utils.list(utils.sym(stacktop.prefix), v))
            else
                table.insert(stack[#stack], v)
            end
            whitespaceSinceDispatch = false
        end

        -- Throw nice error when we expect more characters
        -- but reach end of stream.
        local function badend()
            local accum = utils.map(stack, "closer")
            parseError(('expected closing delimiter%s %s'):format(
                #stack == 1 and "" or "s",
                string.char(unpack(accum))))
        end

        -- The main parse loop
        repeat
            local b

            -- Skip whitespace
            repeat
                b = getb()
                if b and iswhitespace(b) then
                    whitespaceSinceDispatch = true
                end
            until not b or not iswhitespace(b)
            if not b then
                if #stack > 0 then badend() end
                return nil
            end

            if b == 59 then -- ; Comment
                repeat
                    b = getb()
                until not b or b == 10 -- newline
            elseif type(delims[b]) == 'number' then -- Opening delimiter
                if not whitespaceSinceDispatch then
                    parseError('expected whitespace before opening delimiter '
                                   .. string.char(b))
                end
                table.insert(stack, setmetatable({
                    closer = delims[b],
                    line = line,
                    filename = filename,
                    bytestart = byteindex
                }, getmetatable(utils.list())))
            elseif delims[b] then -- Closing delimiter
                if #stack == 0 then parseError('unexpected closing delimiter '
                                                   .. string.char(b)) end
                local last = stack[#stack]
                local val
                if last.closer ~= b then
                    parseError('mismatched closing delimiter ' .. string.char(b) ..
                               ', expected ' .. string.char(last.closer))
                end
                last.byteend = byteindex -- Set closing byte index
                if b == 41 then -- ; )
                    val = last
                elseif b == 93 then -- ; ]
                    val = utils.sequence(unpack(last))
                    -- for table literals we can store file/line/offset source
                    -- data in fields on the table itself, because the AST node
                    -- *is* the table, and the fields would show up in the
                    -- compiled output. keep them on the metatable instead.
                    for k,v in pairs(last) do getmetatable(val)[k]=v end
                else -- ; }
                    if #last % 2 ~= 0 then
                        byteindex = byteindex - 1
                        parseError('expected even number of values in table literal')
                    end
                    val = {}
                    setmetatable(val, last) -- see note above about source data
                    for i = 1, #last, 2 do
                        if(tostring(last[i]) == ":" and utils.isSym(last[i + 1])
                           and utils.isSym(last[i])) then
                            last[i] = tostring(last[i + 1])
                        end
                        val[last[i]] = last[i + 1]
                    end
                end
                stack[#stack] = nil
                dispatch(val)
            elseif b == 34 then -- Quoted string
                local state = "base"
                local chars = {34}
                stack[#stack + 1] = {closer = 34}
                repeat
                    b = getb()
                    chars[#chars + 1] = b
                    if state == "base" then
                        if b == 92 then
                            state = "backslash"
                        elseif b == 34 then
                            state = "done"
                        end
                    else
                        -- state == "backslash"
                        state = "base"
                    end
                until not b or (state == "done")
                if not b then badend() end
                stack[#stack] = nil
                local raw = string.char(unpack(chars))
                local formatted = raw:gsub("[\1-\31]", function (c)
                                               return '\\' .. c:byte() end)
                local loadFn = (loadstring or load)(('return %s'):format(formatted))
                dispatch(loadFn())
            elseif prefixes[b] then
                -- expand prefix byte into wrapping form eg. '`a' into '(quote a)'
                table.insert(stack, {
                    prefix = prefixes[b]
                })
                local nextb = getb()
                if iswhitespace(nextb) then
                    if b == 35 then
                        stack[#stack] = nil
                        dispatch(utils.sym('#'))
                    else
                        parseError('invalid whitespace after quoting prefix')
                    end
                end
                ungetb(nextb)
            elseif issymbolchar(b) or b == string.byte("~") then -- Try sym
                local chars = {}
                local bytestart = byteindex
                repeat
                    chars[#chars + 1] = b
                    b = getb()
                until not b or not issymbolchar(b)
                if b then ungetb(b) end
                local rawstr = string.char(unpack(chars))
                if rawstr == 'true' then dispatch(true)
                elseif rawstr == 'false' then dispatch(false)
                elseif rawstr == '...' then dispatch(utils.varg())
                elseif rawstr:match('^:.+$') then -- colon style strings
                    dispatch(rawstr:sub(2))
                elseif rawstr:match("^~") and rawstr ~= "~=" then
                    -- for backwards-compatibility, special-case allowance
                    -- of ~= but all other uses of ~ are disallowed
                    parseError("illegal character: ~")
                else
                    local forceNumber = rawstr:match('^%d')
                    local numberWithStrippedUnderscores = rawstr:gsub("_", "")
                    local x
                    if forceNumber then
                        x = tonumber(numberWithStrippedUnderscores) or
                            parseError('could not read number "' .. rawstr .. '"')
                    else
                        x = tonumber(numberWithStrippedUnderscores)
                        if not x then
                            if(rawstr:match("%.[0-9]")) then
                                byteindex = (byteindex - #rawstr +
                                                 rawstr:find("%.[0-9]") + 1)
                                parseError("can't start multisym segment " ..
                                               "with a digit: ".. rawstr)
                            elseif(rawstr:match("[%.:][%.:]") and
                                   rawstr ~= ".." and rawstr ~= '$...') then
                                byteindex = (byteindex - #rawstr +
                                                 rawstr:find("[%.:][%.:]") + 1)
                                parseError("malformed multisym: " .. rawstr)
                            elseif(rawstr:match(":.+[%.:]")) then
                                byteindex = (byteindex - #rawstr +
                                                 rawstr:find(":.+[%.:]"))
                                parseError("method must be last component "
                                               .. "of multisym: " .. rawstr)
                            else
                                x = utils.sym(rawstr, nil, {line = line,
                                                      filename = filename,
                                                      bytestart = bytestart,
                                                      byteend = byteindex,})
                            end
                        end
                    end
                    dispatch(x)
                end
            else
                parseError("illegal character: " .. string.char(b))
            end
        until done
        return true, retval
    end, function ()
        stack = {}
    end
end
return { granulate=granulate, stringStream=stringStream, parser=parser }

