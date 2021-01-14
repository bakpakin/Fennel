local type_order = {["function"] = 5, boolean = 2, number = 1, string = 3, table = 4, thread = 7, userdata = 6}
local function sort_keys(_0_0, _1_0)
  local _1_ = _0_0
  local a = _1_[1]
  local _2_ = _1_0
  local b = _2_[1]
  local ta = type(a)
  local tb = type(b)
  if ((ta == tb) and ((ta == "string") or (ta == "number"))) then
    return (a < b)
  else
    local dta = type_order[ta]
    local dtb = type_order[tb]
    if (dta and dtb) then
      return (dta < dtb)
    elseif dta then
      return true
    elseif dtb then
      return false
    else
      return (ta < tb)
    end
  end
end
local function table_kv_pairs(t)
  local assoc_3f = false
  local kv = {}
  local insert = table.insert
  for k, v in pairs(t) do
    if (type(k) ~= "number") then
      assoc_3f = true
    end
    insert(kv, {k, v})
  end
  table.sort(kv, sort_keys)
  if (#kv == 0) then
    return kv, "empty"
  else
    local function _2_()
      if assoc_3f then
        return "table"
      else
        return "seq"
      end
    end
    return kv, _2_()
  end
end
local function count_table_appearances(t, appearances)
  if (type(t) == "table") then
    if not appearances[t] then
      appearances[t] = 1
      for k, v in pairs(t) do
        count_table_appearances(k, appearances)
        count_table_appearances(v, appearances)
      end
    else
      appearances[t] = ((appearances[t] or 0) + 1)
    end
  end
  return appearances
end
local function save_table(t, seen)
  local seen0 = (seen or {len = 0})
  local id = (seen0.len + 1)
  if not seen0[t] then
    seen0[t] = id
    seen0.len = id
  end
  return seen0
end
local function detect_cycle(t, seen)
  local seen0 = (seen or {})
  seen0[t] = true
  for k, v in pairs(t) do
    if ((type(k) == "table") and (seen0[k] or detect_cycle(k, seen0))) then
      return true
    end
    if ((type(v) == "table") and (seen0[v] or detect_cycle(v, seen0))) then
      return true
    end
  end
  return nil
end
local function visible_cycle_3f(t, options)
  return (options["detect-cycles?"] and detect_cycle(t) and save_table(t, options.seen) and (1 < (options.appearances[t] or 0)))
end
local function table_indent(t, indent, id)
  local opener_length = nil
  if id then
    opener_length = (#tostring(id) + 2)
  else
    opener_length = 1
  end
  return (indent + opener_length)
end
local pp = {}
local function concat_table_lines(elements, options, multiline_3f, indent, table_type, prefix)
  local indent_str = ("\n" .. string.rep(" ", indent))
  local open = nil
  local function _2_()
    if ("seq" == table_type) then
      return "["
    else
      return "{"
    end
  end
  open = ((prefix or "") .. _2_())
  local close = nil
  if ("seq" == table_type) then
    close = "]"
  else
    close = "}"
  end
  local oneline = (open .. table.concat(elements, " ") .. close)
  local _4_
  if (table_type == "seq") then
    _4_ = options["sequential-length"]
  else
    _4_ = options["associative-length"]
  end
  if (not options["one-line?"] and (multiline_3f or (#elements > _4_) or ((indent + #oneline) > options["line-length"]))) then
    return (open .. table.concat(elements, indent_str) .. close)
  else
    return oneline
  end
end
local function pp_associative(t, kv, options, indent, key_3f)
  local multiline_3f = false
  local id = options.seen[t]
  if (options.level >= options.depth) then
    return "{...}"
  elseif (id and options["detect-cycles?"]) then
    return ("@" .. id .. "{...}")
  else
    local visible_cycle_3f0 = visible_cycle_3f(t, options)
    local id0 = (visible_cycle_3f0 and options.seen[t])
    local indent0 = table_indent(t, indent, id0)
    local slength = nil
    local function _3_()
      local _2_0 = rawget(_G, "utf8")
      if _2_0 then
        return _2_0.len
      else
        return _2_0
      end
    end
    local function _4_(_241)
      return #_241
    end
    slength = ((options["utf8?"] and _3_()) or _4_)
    local prefix = nil
    if visible_cycle_3f0 then
      prefix = ("@" .. id0)
    else
      prefix = ""
    end
    local elements = nil
    do
      local tbl_0_ = {}
      for _, _6_0 in pairs(kv) do
        local _7_ = _6_0
        local k = _7_[1]
        local v = _7_[2]
        local _8_
        do
          local k0 = pp.pp(k, options, (indent0 + 1), true)
          local v0 = pp.pp(v, options, (indent0 + slength(k0) + 1))
          multiline_3f = (multiline_3f or k0:find("\n") or v0:find("\n"))
          _8_ = (k0 .. " " .. v0)
        end
        tbl_0_[(#tbl_0_ + 1)] = _8_
      end
      elements = tbl_0_
    end
    return concat_table_lines(elements, options, multiline_3f, indent0, "table", prefix)
  end
end
local function pp_sequence(t, kv, options, indent)
  local multiline_3f = false
  local id = options.seen[t]
  if (options.level >= options.depth) then
    return "[...]"
  elseif (id and options["detect-cycles?"]) then
    return ("@" .. id .. "[...]")
  else
    local visible_cycle_3f0 = visible_cycle_3f(t, options)
    local id0 = (visible_cycle_3f0 and options.seen[t])
    local indent0 = table_indent(t, indent, id0)
    local prefix = nil
    if visible_cycle_3f0 then
      prefix = ("@" .. id0)
    else
      prefix = ""
    end
    local elements = nil
    do
      local tbl_0_ = {}
      for _, _3_0 in pairs(kv) do
        local _4_ = _3_0
        local _0 = _4_[1]
        local v = _4_[2]
        local _5_
        do
          local v0 = pp.pp(v, options, indent0)
          multiline_3f = (multiline_3f or v0:find("\n"))
          _5_ = v0
        end
        tbl_0_[(#tbl_0_ + 1)] = _5_
      end
      elements = tbl_0_
    end
    return concat_table_lines(elements, options, multiline_3f, indent0, "seq", prefix)
  end
end
local function concat_lines(lines, options, indent, force_multi_line_3f)
  if (#lines == 0) then
    if options["empty-as-sequence?"] then
      return "[]"
    else
      return "{}"
    end
  else
    local oneline = nil
    local _2_
    do
      local tbl_0_ = {}
      for _, line in ipairs(lines) do
        tbl_0_[(#tbl_0_ + 1)] = line:gsub("^%s+", "")
      end
      _2_ = tbl_0_
    end
    oneline = table.concat(_2_, " ")
    if (not options["one-line?"] and (force_multi_line_3f or oneline:find("\n") or ((indent + #oneline) > options["line-length"]))) then
      return table.concat(lines, ("\n" .. string.rep(" ", indent)))
    else
      return oneline
    end
  end
end
local function pp_metamethod(t, metamethod, options, indent)
  if (options.level >= options.depth) then
    if options["empty-as-sequence?"] then
      return "[...]"
    else
      return "{...}"
    end
  else
    local _ = nil
    local function _2_(_241)
      return visible_cycle_3f(_241, options)
    end
    options["visible-cycle?"] = _2_
    _ = nil
    local lines, force_multi_line_3f = metamethod(t, pp.pp, options, indent)
    options["visible-cycle?"] = nil
    local _3_0 = type(lines)
    if (_3_0 == "string") then
      return lines
    elseif (_3_0 == "table") then
      return concat_lines(lines, options, indent, force_multi_line_3f)
    else
      local _0 = _3_0
      return error("Error: __fennelview metamethod must return a table of lines")
    end
  end
end
local function pp_table(x, options, indent)
  options.level = (options.level + 1)
  local x0 = nil
  do
    local _2_0 = nil
    if options["metamethod?"] then
      local _3_0 = x
      if _3_0 then
        local _4_0 = getmetatable(_3_0)
        if _4_0 then
          _2_0 = _4_0.__fennelview
        else
          _2_0 = _4_0
        end
      else
        _2_0 = _3_0
      end
    else
    _2_0 = nil
    end
    if (nil ~= _2_0) then
      local metamethod = _2_0
      x0 = pp_metamethod(x, metamethod, options, indent)
    else
      local _ = _2_0
      local _4_0, _5_0 = table_kv_pairs(x)
      if (true and (_5_0 == "empty")) then
        local _0 = _4_0
        if options["empty-as-sequence?"] then
          x0 = "[]"
        else
          x0 = "{}"
        end
      elseif ((nil ~= _4_0) and (_5_0 == "table")) then
        local kv = _4_0
        x0 = pp_associative(x, kv, options, indent)
      elseif ((nil ~= _4_0) and (_5_0 == "seq")) then
        local kv = _4_0
        x0 = pp_sequence(x, kv, options, indent)
      else
      x0 = nil
      end
    end
  end
  options.level = (options.level - 1)
  return x0
end
local function number__3estring(n)
  local _2_0, _3_0, _4_0 = math.modf(n)
  if ((nil ~= _2_0) and (_3_0 == 0)) then
    local int = _2_0
    return tostring(int)
  else
    local _5_
    do
      local frac = _3_0
      _5_ = (((_2_0 == 0) and (nil ~= _3_0)) and (frac < 0))
    end
    if _5_ then
      local frac = _3_0
      return ("-0." .. tostring(frac):gsub("^-?0.", ""))
    elseif ((nil ~= _2_0) and (nil ~= _3_0)) then
      local int = _2_0
      local frac = _3_0
      return (int .. "." .. tostring(frac):gsub("^-?0.", ""))
    end
  end
end
local function colon_string_3f(s)
  return s:find("^[-%w?\\^_!$%&*+./@:|<=>]+$")
end
local function make_options(t, options)
  local defaults = {["associative-length"] = 4, ["detect-cycles?"] = true, ["empty-as-sequence?"] = false, ["line-length"] = 80, ["metamethod?"] = true, ["one-line?"] = false, ["sequential-length"] = 10, ["utf8?"] = true, depth = 128}
  local overrides = {appearances = count_table_appearances(t, {}), level = 0, seen = {len = 0}}
  for k, v in pairs((options or {})) do
    defaults[k] = v
  end
  for k, v in pairs(overrides) do
    defaults[k] = v
  end
  return defaults
end
pp.pp = function(x, options, indent, key_3f)
  local indent0 = (indent or 0)
  local options0 = (options or make_options(x))
  local tv = type(x)
  local function _3_()
    local _2_0 = getmetatable(x)
    if _2_0 then
      return _2_0.__fennelview
    else
      return _2_0
    end
  end
  if ((tv == "table") or ((tv == "userdata") and _3_())) then
    return pp_table(x, options0, indent0)
  elseif (tv == "number") then
    return number__3estring(x)
  elseif ((tv == "string") and key_3f and colon_string_3f(x)) then
    return (":" .. x)
  elseif (tv == "string") then
    return string.format("%q", x)
  elseif ((tv == "boolean") or (tv == "nil")) then
    return tostring(x)
  else
    return ("#<" .. tostring(x) .. ">")
  end
end
local function view(x, options)
  return pp.pp(x, make_options(x, options), 0)
end
return view
