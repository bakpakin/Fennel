local function view_quote(str)
  return ("\"" .. str:gsub("\"", "\\\"") .. "\"")
end
local short_control_char_escapes = {["\11"] = "\\v", ["\12"] = "\\f", ["\13"] = "\\r", ["\7"] = "\\a", ["\8"] = "\\b", ["\9"] = "\\t", ["\n"] = "\\n"}
local long_control_char_escapes = nil
do
  local long = {}
  for i = 0, 31 do
    local ch = string.char(i)
    if not short_control_char_escapes[ch] then
      short_control_char_escapes[ch] = ("\\" .. i)
      long[ch] = ("\\%03d"):format(i)
    end
  end
  long_control_char_escapes = long
end
local function escape(str)
  return str:gsub("\\", "\\\\"):gsub("(%c)%f[0-9]", long_control_char_escapes):gsub("%c", short_control_char_escapes)
end
local function sequence_key_3f(k, len)
  return ((type(k) == "number") and (1 <= k) and (k <= len) and (math.floor(k) == k))
end
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
    elseif "else" then
      return (ta < tb)
    end
  end
end
local function get_sequence_length(t)
  local len = 0
  for i in ipairs(t) do
    len = i
  end
  return len
end
local function get_nonsequential_keys(t)
  local keys = {}
  local sequence_length = get_sequence_length(t)
  for k, v in pairs(t) do
    if not sequence_key_3f(k, sequence_length) then
      table.insert(keys, {k, v})
    end
  end
  table.sort(keys, sort_keys)
  return keys, sequence_length
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
local put_value = nil
local function puts(self, ...)
  for _, v in ipairs({...}) do
    table.insert(self.buffer, v)
  end
  return nil
end
local function tabify(self)
  return puts(self, "\n", (self.indent):rep(self.level))
end
local function already_visited_3f(self, v)
  return (self.ids[v] ~= nil)
end
local function get_id(self, v)
  local id = self.ids[v]
  if not id then
    local tv = type(v)
    id = ((self["max-ids"][tv] or 0) + 1)
    self["max-ids"][tv] = id
    self.ids[v] = id
  end
  return tostring(id)
end
local function put_sequential_table(self, t, len)
  puts(self, "[")
  self.level = (self.level + 1)
  for k, v in ipairs(t) do
    local _2_ = (1 + len)
    if ((1 < k) and (k < _2_)) then
      puts(self, " ")
    end
    put_value(self, v)
  end
  self.level = (self.level - 1)
  return puts(self, "]")
end
local function put_key(self, k)
  if ((type(k) == "string") and k:find("^[-%w?\\^_!$%&*+./@:|<=>]+$")) then
    return puts(self, ":", k)
  else
    return put_value(self, k)
  end
end
local function put_kv_table(self, t, ordered_keys)
  puts(self, "{")
  self.level = (self.level + 1)
  for i, _2_0 in ipairs(ordered_keys) do
    local _3_ = _2_0
    local k = _3_[1]
    local v = _3_[2]
    if (self["table-edges"] or (i ~= 1)) then
      tabify(self)
    end
    put_key(self, k)
    puts(self, " ")
    put_value(self, v)
  end
  for i, v in ipairs(t) do
    tabify(self)
    put_key(self, i)
    puts(self, " ")
    put_value(self, v)
  end
  self.level = (self.level - 1)
  if self["table-edges"] then
    tabify(self)
  end
  return puts(self, "}")
end
local function put_table(self, t)
  local metamethod = nil
  local function _3_()
    local _2_0 = t
    if _2_0 then
      local _4_0 = getmetatable(_2_0)
      if _4_0 then
        return _4_0.__fennelview
      else
        return _4_0
      end
    else
      return _2_0
    end
  end
  metamethod = (self["metamethod?"] and _3_())
  if (already_visited_3f(self, t) and self["detect-cycles?"]) then
    return puts(self, "#<table @", get_id(self, t), ">")
  elseif (self.level >= self.depth) then
    return puts(self, "{...}")
  elseif metamethod then
    return puts(self, metamethod(t, self.fennelview))
  elseif "else" then
    local non_seq_keys, len = get_nonsequential_keys(t)
    local id = get_id(self, t)
    if ((1 < (self.appearances[t] or 0)) and self["detect-cycles?"]) then
      puts(self, "@", id)
    end
    if ((#non_seq_keys == 0) and (#t == 0)) then
      local function _5_()
        if self["empty-as-square"] then
          return "[]"
        else
          return "{}"
        end
      end
      return puts(self, _5_())
    elseif (#non_seq_keys == 0) then
      return put_sequential_table(self, t, len)
    elseif "else" then
      return put_kv_table(self, t, non_seq_keys)
    end
  end
end
local function _2_(self, v)
  local tv = type(v)
  if (tv == "string") then
    return puts(self, view_quote(escape(v)))
  elseif ((tv == "number") or (tv == "boolean") or (tv == "nil")) then
    return puts(self, tostring(v))
  else
    local _4_
    do
      local _3_0 = getmetatable(v)
      if _3_0 then
        _4_ = _3_0.__fennelview
      else
        _4_ = _3_0
      end
    end
    if ((tv == "table") or ((tv == "userdata") and (nil ~= _4_))) then
      return put_table(self, v)
    elseif "else" then
      return puts(self, "#<", tostring(v), ">")
    end
  end
end
put_value = _2_
local function one_line(str)
  local ret = str:gsub("\n", " "):gsub("%[ ", "["):gsub(" %]", "]"):gsub("%{ ", "{"):gsub(" %}", "}"):gsub("%( ", "("):gsub(" %)", ")")
  return ret
end
local function fennelview(x, options)
  local options0 = (options or {})
  local inspector = nil
  local function _3_(_241)
    return fennelview(_241, options0)
  end
  local function _4_()
    if options0["one-line"] then
      return ""
    else
      return "  "
    end
  end
  inspector = {["detect-cycles?"] = not (false == options0["detect-cycles?"]), ["empty-as-square"] = options0["empty-as-square"], ["max-ids"] = {}, ["metamethod?"] = not (false == options0["metamethod?"]), ["table-edges"] = (options0["table-edges"] ~= false), appearances = count_table_appearances(x, {}), buffer = {}, depth = (options0.depth or 128), fennelview = _3_, ids = {}, indent = (options0.indent or _4_()), level = 0}
  put_value(inspector, x)
  local str = table.concat(inspector.buffer)
  if options0["one-line"] then
    return one_line(str)
  else
    return str
  end
end
return fennelview
