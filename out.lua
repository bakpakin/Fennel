local generate = nil
local function _0_()
  if (math[("random")]()) > (0.90000000000000002) then
    return string[("char")]((48 + math[("random")](10)))
  elseif (math[("random")]()) > (0.5) then
    return string[("char")]((97 + math[("random")](26)))
  elseif (math[("random")]()) > (0.5) then
    return string[("char")]((65 + math[("random")](26)))
  elseif (math[("random")]()) > (0.5) then
    return string[("char")]((32 + math[("random")](15)))
  elseif ("else") then
    return string[("char")]((58 + math[("random")](5)))
  end
end
local random_char = _0_
local function _1_()
  return (math[("random")]()) > (0.5)
end
local function _2_()
  if (math[("random")]()) > (0.90000000000000002) then
    do
      local x = math[("random")](2147483647)
      return math[("floor")]((x - (x / 2)))
    end
  elseif (math[("random")]()) > (0.20000000000000001) then
    return math[("floor")](math[("random")](2048))
  elseif ("else") then
    return math[("random")]()
  end
end
local function _3_()
  local s = ("")
  for _ = 1, math[("random")](16) do
    s = (s .. random_char())
  end
  return s
end
local function _4_(table_chance)
  do
    local t = ({})
    local k = nil
    for _ = 1, math[("random")](16) do
      k = generate(0.90000000000000002)
      while (k) ~= (k) do
        k = generate(0.90000000000000002)
      end
      t[k] = generate((table_chance * 1.5))
    end
    return t
  end
end
local generators = ({[("boolean")] = _1_, [("number")] = _2_, [("string")] = _3_, [("table")] = _4_})
local function _5_(table_chance)
  local table_chance = (table_chance or 0.5)
  if (math[("random")]()) > (0.5) then
    return generators[("number")]()
  elseif (math[("random")]()) > (0.5) then
    return generators[("string")]()
  elseif (math[("random")]()) > (table_chance) then
    return generators[("table")](table_chance)
  elseif ("else") then
    return generators[("boolean")]()
  end
end
generate = _5_
return generate
