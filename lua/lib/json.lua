-- Kleiner JSON-Kodierer/-Dekodierer, lauffähig unter Lua 5.1 (DeSmuME) und 5.3 (fengari).
--
-- Besonderheiten:
--  * Objektschlüssel werden sortiert ausgegeben (deterministische Ausgabe, gut für Tests und Diffs).
--  * Leere Tabellen werden als [] kodiert, außer sie wurden mit json.object() angelegt
--    oder stammen aus einem dekodierten {}.
--  * Ganze Zahlen werden ohne ".0" geschrieben (wichtig unter Lua 5.3).

local json = {}

local OBJECT_MT = { __jsontype = "object" }
local ARRAY_MT = { __jsontype = "array" }

--- Legt eine Tabelle an, die auch leer als {} kodiert wird.
function json.object(t)
  return setmetatable(t or {}, OBJECT_MT)
end

--- Legt eine Tabelle an, die auch leer als [] kodiert wird.
function json.array(t)
  return setmetatable(t or {}, ARRAY_MT)
end

json.null = setmetatable({}, { __jsontype = "null", __tostring = function() return "null" end })

local function kind_of(t)
  local mt = getmetatable(t)
  if mt and mt.__jsontype then return mt.__jsontype end
  return nil
end

local escapes = {
  ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local function encode_string(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return escapes[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function encode_number(n)
  if n ~= n or n == math.huge or n == -math.huge then
    error("JSON kann NaN/Unendlich nicht darstellen")
  end
  if math.floor(n) == n and n >= -9007199254740992 and n <= 9007199254740992 then
    return string.format("%.0f", n)
  end
  return string.format("%.17g", n)
end

local function is_array(t)
  local k = kind_of(t)
  if k == "array" then return true end
  if k == "object" then return false end
  local n = 0
  for key in pairs(t) do
    if type(key) ~= "number" or key < 1 or math.floor(key) ~= key then return false end
    n = n + 1
  end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

local encode_value

local function encode_table(t, stack)
  if stack[t] then error("JSON: zyklische Tabelle") end
  stack[t] = true
  local out = {}
  if kind_of(t) == "null" then
    stack[t] = nil
    return "null"
  end
  if is_array(t) then
    for i = 1, #t do out[i] = encode_value(t[i], stack) end
    stack[t] = nil
    return "[" .. table.concat(out, ",") .. "]"
  end
  local keys = {}
  for k, v in pairs(t) do
    if type(k) == "number" then k = encode_number(k) end
    if type(k) ~= "string" then error("JSON: Schlüssel muss Text oder Zahl sein") end
    keys[#keys + 1] = k
  end
  table.sort(keys)
  for i, k in ipairs(keys) do
    local v = t[k]
    if v == nil then v = t[tonumber(k)] end
    out[i] = encode_string(k) .. ":" .. encode_value(v, stack)
  end
  stack[t] = nil
  return "{" .. table.concat(out, ",") .. "}"
end

encode_value = function(v, stack)
  local tv = type(v)
  if tv == "nil" then return "null" end
  if tv == "boolean" then return v and "true" or "false" end
  if tv == "number" then return encode_number(v) end
  if tv == "string" then return encode_string(v) end
  if tv == "table" then return encode_table(v, stack) end
  error("JSON: Typ nicht kodierbar: " .. tv)
end

function json.encode(v)
  return encode_value(v, {})
end

-- Dekodierer ------------------------------------------------------------

local function decode_error(str, pos, msg)
  error(string.format("JSON-Fehler an Position %d: %s", pos, msg), 0)
end

local function skip_ws(str, pos)
  local _, e = str:find("^[ \n\r\t]*", pos)
  return e + 1
end

local function utf8_char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  end
  if cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
    0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local decode_value

local function decode_string(str, pos)
  local out = {}
  local i = pos + 1
  while true do
    local c = str:sub(i, i)
    if c == "" then decode_error(str, i, "Text nicht abgeschlossen") end
    if c == '"' then return table.concat(out), i + 1 end
    if c == "\\" then
      local e = str:sub(i + 1, i + 1)
      local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
      if map[e] then
        out[#out + 1] = map[e]
        i = i + 2
      elseif e == "u" then
        local hex = str:sub(i + 2, i + 5)
        local cp = tonumber(hex, 16)
        if not cp or #hex ~= 4 then decode_error(str, i, "ungültiges \\u") end
        i = i + 6
        if cp >= 0xD800 and cp <= 0xDBFF and str:sub(i, i + 1) == "\\u" then
          local lo = tonumber(str:sub(i + 2, i + 5), 16)
          if lo and lo >= 0xDC00 and lo <= 0xDFFF then
            cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
            i = i + 6
          end
        end
        out[#out + 1] = utf8_char(cp)
      else
        decode_error(str, i, "ungültige Escape-Sequenz")
      end
    else
      local s, e = str:find('^[^"\\]+', i)
      out[#out + 1] = str:sub(s, e)
      i = e + 1
    end
  end
end

local function decode_number(str, pos)
  local s, e = str:find("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
  if not s then decode_error(str, pos, "Zahl erwartet") end
  local n = tonumber(str:sub(s, e))
  if not n then decode_error(str, pos, "ungültige Zahl") end
  return n, e + 1
end

local function decode_array(str, pos)
  local arr = json.array()
  pos = skip_ws(str, pos + 1)
  if str:sub(pos, pos) == "]" then return arr, pos + 1 end
  while true do
    local v
    v, pos = decode_value(str, pos)
    arr[#arr + 1] = v
    pos = skip_ws(str, pos)
    local c = str:sub(pos, pos)
    if c == "]" then return arr, pos + 1 end
    if c ~= "," then decode_error(str, pos, "',' oder ']' erwartet") end
    pos = skip_ws(str, pos + 1)
  end
end

local function decode_object(str, pos)
  local obj = json.object()
  pos = skip_ws(str, pos + 1)
  if str:sub(pos, pos) == "}" then return obj, pos + 1 end
  while true do
    if str:sub(pos, pos) ~= '"' then decode_error(str, pos, "Schlüssel erwartet") end
    local k
    k, pos = decode_string(str, pos)
    pos = skip_ws(str, pos)
    if str:sub(pos, pos) ~= ":" then decode_error(str, pos, "':' erwartet") end
    pos = skip_ws(str, pos + 1)
    local v
    v, pos = decode_value(str, pos)
    obj[k] = v
    pos = skip_ws(str, pos)
    local c = str:sub(pos, pos)
    if c == "}" then return obj, pos + 1 end
    if c ~= "," then decode_error(str, pos, "',' oder '}' erwartet") end
    pos = skip_ws(str, pos + 1)
  end
end

decode_value = function(str, pos)
  pos = skip_ws(str, pos)
  local c = str:sub(pos, pos)
  if c == "{" then return decode_object(str, pos) end
  if c == "[" then return decode_array(str, pos) end
  if c == '"' then return decode_string(str, pos) end
  if c == "-" or c:match("%d") then return decode_number(str, pos) end
  if str:sub(pos, pos + 3) == "true" then return true, pos + 4 end
  if str:sub(pos, pos + 4) == "false" then return false, pos + 5 end
  if str:sub(pos, pos + 3) == "null" then return nil, pos + 4 end
  decode_error(str, pos, "unerwartetes Zeichen '" .. c .. "'")
end

--- Dekodiert JSON. null wird zu nil (in Arrays entstehen dadurch Lücken; der Zustand nutzt kein null).
function json.decode(str)
  if type(str) ~= "string" then error("JSON: Text erwartet") end
  local v, pos = decode_value(str, 1)
  pos = skip_ws(str, pos)
  if pos <= #str then decode_error(str, pos, "Zeichen nach Ende") end
  return v
end

return json
