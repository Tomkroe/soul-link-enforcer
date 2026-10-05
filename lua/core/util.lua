-- Hilfsfunktionen für die Regel-Engine. Rein, ohne Emulator-API.
-- Hinweis: unter fengari sind Ganzzahlen 32 Bit breit und tostring(3.0) ergibt "3.0".
-- Zahlen deshalb immer über U.num() in Text wandeln.

local json = require("lib.json")

local U = {}

--- Tabelle, die auch leer als JSON-Objekt {} gespeichert wird (für Zuordnungen nach Schlüssel).
U.map = json.object

--- Tabelle, die auch leer als JSON-Array [] gespeichert wird.
U.list = json.array

function U.num(n)
  if type(n) ~= "number" then return tostring(n) end
  if math.floor(n) == n then return string.format("%.0f", n) end
  return string.format("%.14g", n)
end

--- Schlüssel für Gebiete, Monster usw. immer als Text.
function U.key(v)
  if v == nil then return nil end
  if type(v) == "number" then return U.num(v) end
  return tostring(v)
end

function U.contains(list, value)
  for _, v in ipairs(list or {}) do
    if v == value then return true end
  end
  return false
end

function U.remove_value(list, value)
  for i = #list, 1, -1 do
    if list[i] == value then table.remove(list, i) end
  end
end

function U.copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = U.copy(x) end
  return setmetatable(out, getmetatable(v))
end

--- Überträgt Felder aus src rekursiv nach dst (nur bekannte Schlüssel, wenn known gesetzt ist).
function U.merge(dst, src)
  for k, v in pairs(src or {}) do
    if type(v) == "table" and type(dst[k]) == "table" and not v[1] then
      U.merge(dst[k], v)
    else
      dst[k] = U.copy(v)
    end
  end
  return dst
end

function U.count(map)
  local n = 0
  for _ in pairs(map or {}) do n = n + 1 end
  return n
end

function U.set(list)
  local s = {}
  for _, v in ipairs(list or {}) do s[v] = true end
  return s
end

--- Schlüssel einer Menge in fester Reihenfolge (sortiert), für deterministische Ausgaben.
function U.sorted_keys(map)
  local keys = {}
  for k in pairs(map or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

function U.join(list, sep)
  local parts = {}
  for i, v in ipairs(list or {}) do parts[i] = tostring(v) end
  return table.concat(parts, sep or ", ")
end

return U
