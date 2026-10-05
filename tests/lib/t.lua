-- Minimales Test-Framework ohne Abhängigkeiten (Lua 5.1 und 5.3).

local T = { results = { passed = 0, failed = 0, skipped = 0, failures = {} }, current_file = "?" }

local function describe(v, depth)
  depth = depth or 0
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  if depth > 3 then return "{...}" end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = tostring(k) .. "=" .. describe(v[k], depth + 1)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end
T.describe = describe

local function deep_eq(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    if not deep_eq(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end
T.deep_eq = deep_eq

local function fail(msg, level)
  error({ t_failure = true, msg = msg }, (level or 1) + 1)
end

function T.eq(actual, expected, msg)
  if not deep_eq(actual, expected) then
    fail((msg and (msg .. ": ") or "") .. "erwartet " .. describe(expected) .. ", erhalten " .. describe(actual), 2)
  end
end

function T.ok(value, msg)
  if not value then fail(msg or "Bedingung nicht erfüllt", 2) end
end

function T.no(value, msg)
  if value then fail(msg or ("Wert sollte falsch sein: " .. describe(value)), 2) end
end

function T.raises(fn, pattern, msg)
  local ok, err = pcall(fn)
  if ok then fail(msg or "Fehler erwartet, aber keiner aufgetreten", 2) end
  if pattern and not tostring(err):find(pattern) then
    fail("Fehlermeldung passt nicht: " .. tostring(err), 2)
  end
end

--- Sucht in einer Liste ein Element, dessen Felder alle in 'fields' übereinstimmen.
function T.find(list, fields)
  for _, item in ipairs(list or {}) do
    local match = true
    for k, v in pairs(fields) do
      if item[k] ~= v then match = false break end
    end
    if match then return item end
  end
  return nil
end

function T.has(list, fields, msg)
  local found = T.find(list, fields)
  if not found then
    fail((msg and (msg .. ": ") or "") .. "kein Eintrag mit " .. describe(fields) .. " in " .. describe(list), 2)
  end
  return found
end

function T.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    T.results.passed = T.results.passed + 1
  elseif type(err) == "table" and err.t_skip then
    T.results.skipped = T.results.skipped + 1
    print("  übersprungen: " .. name .. " (" .. err.msg .. ")")
  else
    T.results.failed = T.results.failed + 1
    local msg = type(err) == "table" and err.msg or tostring(err)
    table.insert(T.results.failures, T.current_file .. " :: " .. name .. "\n      " .. msg)
    print("  FEHLER: " .. name .. "\n      " .. msg)
  end
end

function T.skip(reason)
  error({ t_skip = true, msg = reason }, 2)
end

return T
