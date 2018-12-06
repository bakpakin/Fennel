local function _0_(str)
  return ("\"" .. str:gsub("\"", "\\\"") .. "\"")
end
local quote = _0_
local short_control_char_escapes = {["\11"] = "\\v", ["\12"] = "\\f", ["\13"] = "\\r", ["\7"] = "\\a", ["\8"] = "\\b", ["\9"] = "\\t", ["\n"] = "\\n"}
local function _1_(...)
  local long = {}
  for i = 0, 31 do
    local ch = string.char(i)
    local function _2_(...)
      if not short_control_char_escapes[ch] then
        short_control_char_escapes[ch] = ("\\" .. i)
        long[ch] = ("\\%03d"):format(i)
        return nil
      end
    end
    _2_(...)
  end
  return long
end
local long_control_char_esapes = _1_(...)
local function escape(str)
  local str = str:gsub("\\", "\\\\")
  local str = str:gsub("(%c)%f[0-9]", long_control_char_esapes)
  return str:gsub("%c", short_control_char_escapes)
end
local function sequence_key_3f(k, len)
  return ((type(k) == "number") and (1 <= k) and (k <= len) and (math.floor(k) == k))
end
local type_order = {["function"] = 5, boolean = 2, number = 1, string = 3, table = 4, thread = 7, userdata = 6}
local function sort_keys(a, b)
  local ta = type(a)
  local tb = type(b)
  if ((ta == tb) and (ta ~= "boolean") and ((ta == "string") or (ta == "number"))) then
    return (a < b)
  else
    local dta = type_order[a]
    local dtb = type_order[b]
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
  local len = 1
  for i in ipairs(t) do
    len = i
  end
  return len
end
local function get_nonsequential_keys(t)
  local keys = {}
  local sequence_length = get_sequence_length(t)
  for k in pairs(t) do
    local function _2_()
      if not sequence_key_3f(k, sequence_length) then
        return table.insert(keys, k)
      end
    end
    _2_()
  end
  table.sort(keys, sort_keys)
  return keys, sequence_length
end
local function count_table_appearances(t, appearances)
  local function _2_()
    if (type(t) == "table") then
      if not appearances[t] then
        appearances[t] = 1
        for k, v in pairs(t) do
          count_table_appearances(k, appearances)
          count_table_appearances(v, appearances)
        end
        return nil
      end
    else
      if (t and (t == t)) then
        appearances[t] = ((appearances[t] or 0) + 1)
        return nil
      end
    end
  end
  _2_()
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
  return puts(self, "\n", self.indent:rep(self.level))
end
local function already_visited_3f(self, v)
  return (self.ids[v] ~= nil)
end
local function get_id(self, v)
  local id = self.ids[v]
  local function _2_()
    if not id then
      local tv = type(v)
      id = ((self["max-ids"][tv] or 0) + 1)
      self["max-ids"][tv] = id
      self.ids[v] = id
      return nil
    end
  end
  _2_()
  return tostring(id)
end
local function put_sequential_table(self, t, length)
  puts(self, "[")
  self.level = (self.level + 1)
  for i = 1, length do
    puts(self, " ")
    put_value(self, t[i])
  end
  self.level = (self.level - 1)
  return puts(self, " ]")
end
local function put_key(self, k)
  if ((type(k) == "string") and k:find("^[-%w?\\^_`!#$%&*+./@~:|<=>]+$")) then
    return puts(self, ":", k)
  else
    return put_value(self, k)
  end
end
local function put_kv_table(self, t)
  puts(self, "{")
  self.level = (self.level + 1)
  for k, v in pairs(t) do
    tabify(self)
    put_key(self, k)
    puts(self, " ")
    put_value(self, v)
  end
  self.level = (self.level - 1)
  tabify(self)
  return puts(self, "}")
end
local function put_table(self, t)
  if already_visited_3f(self, t) then
    return puts(self, "#<table ", get_id(self, t), ">")
  elseif (self.level >= self.depth) then
    return puts(self, "{...}")
  elseif "else" then
    local non_seq_keys, length = get_nonsequential_keys(t)
    local id = get_id(self, t)
    if (self.appearances[t] > 1) then
      return puts(self, "#<", id, ">")
    elseif ((#non_seq_keys == 0) and (#t == 0)) then
      return puts(self, "{}")
    elseif (#non_seq_keys == 0) then
      return put_sequential_table(self, t, length)
    elseif "else" then
      return put_kv_table(self, t)
    end
  end
end
local function _2_(self, v)
  local tv = type(v)
  if (tv == "string") then
    return puts(self, quote(escape(v)))
  elseif ((tv == "number") or (tv == "boolean") or (tv == "nil")) then
    return puts(self, tostring(v))
  elseif (tv == "table") then
    return put_table(self, v)
  elseif "else" then
    return puts(self, "#<", tostring(v), ">")
  end
end
put_value = _2_
local function fennelview(root, options)
  local options = (options or {})
  local inspector = {["max-ids"] = {}, appearances = count_table_appearances(root, {}), buffer = {}, depth = (options.depth or 128), ids = {}, indent = (options.indent or "  "), level = 0}
  put_value(inspector, root)
  return table.concat(inspector.buffer)
end
return fennelview
