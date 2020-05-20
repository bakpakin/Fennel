local function ast_source(ast)
  local m = getmetatable(ast)
  if (m and m.filename and m.line and m) then
    return m
  else
    return ast
  end
end
local suggestions = {["can't start multisym segment with a digit"] = {"removing the digit", "adding a non-digit before the digit"}, ["cannot call literal value"] = {"checking for typos", "checking for a missing function name"}, ["could not compile value of type "] = {"debugging the macro you're calling not to return a coroutine or userdata"}, ["could not read number (.*)"] = {"removing the non-digit character", "beginning the identifier with a non-digit if it is not meant to be a number"}, ["expected a function.* to call"] = {"removing the empty parentheses", "using square brackets if you want an empty table"}, ["expected binding table"] = {"placing a table here in square brackets containing identifiers to bind"}, ["expected body expression"] = {"putting some code in the body of this form after the bindings"}, ["expected each macro to be function"] = {"ensuring that the value for each key in your macros table contains a function", "avoid defining nested macro tables"}, ["expected even number of name/value bindings"] = {"finding where the identifier or value is missing"}, ["expected even number of values in table literal"] = {"removing a key", "adding a value"}, ["expected local"] = {"looking for a typo", "looking for a local which is used out of its scope"}, ["expected macros to be table"] = {"ensuring your macro definitions return a table"}, ["expected parameters"] = {"adding function parameters as a list of identifiers in brackets"}, ["expected rest argument before last parameter"] = {"moving & to right before the final identifier when destructuring"}, ["expected symbol for function parameter: (.*)"] = {"changing %s to an identifier instead of a literal value"}, ["expected var (.*)"] = {"declaring %s using var instead of let/local", "introducing a new local instead of changing the value of %s"}, ["expected vararg as last parameter"] = {"moving the \"...\" to the end of the parameter list"}, ["expected whitespace before opening delimiter"] = {"adding whitespace"}, ["global (.*) conflicts with local"] = {"renaming local %s"}, ["illegal character: (.)"] = {"deleting or replacing %s", "avoiding reserved characters like \", \\, ', ~, ;, @, `, and comma"}, ["local (.*) was overshadowed by a special form or macro"] = {"renaming local %s"}, ["macro not found in macro module"] = {"checking the keys of the imported macro module's returned table"}, ["macro tried to bind (.*) without gensym"] = {"changing to %s# when introducing identifiers inside macros"}, ["malformed multisym"] = {"ensuring each period or colon is not followed by another period or colon"}, ["may only be used at compile time"] = {"moving this to inside a macro if you need to manipulate symbols/lists", "using square brackets instead of parens to construct a table"}, ["method must be last component"] = {"using a period instead of a colon for field access", "removing segments after the colon", "making the method call, then looking up the field on the result"}, ["mismatched closing delimiter (.), expected (.)"] = {"replacing %s with %s", "deleting %s", "adding matching opening delimiter earlier"}, ["multisym method calls may only be in call position"] = {"using a period instead of a colon to reference a table's fields", "putting parens around this"}, ["unable to bind (.*)"] = {"replacing the %s with an identifier"}, ["unexpected closing delimiter (.)"] = {"deleting %s", "adding matching opening delimiter earlier"}, ["unexpected multi symbol (.*)"] = {"removing periods or colons from %s"}, ["unexpected vararg"] = {"putting \"...\" at the end of the fn parameters if the vararg was intended"}, ["unknown global in strict mode: (.*)"] = {"looking to see if there's a typo", "using the _G table instead, eg. _G.%s if you really want a global", "moving this code to somewhere that %s is in scope", "binding %s as a local in the scope of this code"}, ["unused local (.*)"] = {"fixing a typo so %s is used", "renaming the local to _%s"}, ["use of global (.*) is aliased by a local"] = {"renaming local %s"}}
local unpack = (_G.unpack or table.unpack)
local function suggest(msg)
  local suggestion = nil
  for pat, sug in pairs(suggestions) do
    local matches = {msg:match(pat)}
    if (0 < #matches) then
      if ("table" == type(sug)) then
        local out = {}
        for _, s in ipairs(sug) do
          table.insert(out, s:format(unpack(matches)))
        end
        suggestion = out
      else
        suggestion = sug(matches)
      end
    end
  end
  return suggestion
end
local function read_line_from_file(filename, line)
  local bytes = 0
  local f = assert(io.open(filename))
  local _ = nil
  for _0 = 1, (line - 1) do
    bytes = (bytes + 1 + #f:read())
  end
  _ = nil
  local codeline = f:read()
  f:close()
  return codeline, bytes
end
local function read_line_from_source(source, line)
  local lines, bytes, codeline = 0, 0
  for this_line in string.gmatch((source .. "\n"), "(.-)\13?\n") do
    lines = (lines + 1)
    if (lines == line) then
      codeline = this_line
      break
    end
    bytes = (bytes + 1 + #this_line)
  end
  return codeline, bytes
end
local function read_line(filename, line, source)
  if source then
    return read_line_from_source(source, line)
  else
    return read_line_from_file(filename, line)
  end
end
local function friendly_msg(msg, _0_0, source)
  local _1_ = _0_0
  local byteend = _1_["byteend"]
  local bytestart = _1_["bytestart"]
  local filename = _1_["filename"]
  local line = _1_["line"]
  local ok, codeline, bol, eol = pcall(read_line, filename, line, source)
  local suggestions0 = suggest(msg)
  local out = {msg, ""}
  if (ok and codeline) then
    table.insert(out, codeline)
  end
  if (ok and codeline and bytestart and byteend) then
    table.insert(out, (string.rep(" ", (bytestart - bol - 1)) .. "^" .. string.rep("^", math.min((byteend - bytestart), ((bol + #codeline) - bytestart)))))
  end
  if (ok and codeline and bytestart and not byteend) then
    table.insert(out, (string.rep("-", (bytestart - bol - 1)) .. "^"))
    table.insert(out, "")
  end
  if suggestions0 then
    for _, suggestion in ipairs(suggestions0) do
      table.insert(out, ("* Try %s."):format(suggestion))
    end
  end
  return table.concat(out, "\n")
end
local function assert_compile(condition, msg, ast, source)
  if not condition then
    local _1_ = ast_source(ast)
    local filename = _1_["filename"]
    local line = _1_["line"]
    error(friendly_msg(("Compile error in %s:%s\n  %s"):format((filename or "unknown"), (line or "?"), msg), ast_source(ast), source), 0)
  end
  return condition
end
local function parse_error(msg, filename, line, bytestart, source)
  return error(friendly_msg(("Parse error in %s:%s\n  %s"):format(filename, line, msg), {bytestart = bytestart, filename = filename, line = line}, source), 0)
end
return {["assert-compile"] = assert_compile, ["parse-error"] = parse_error}
