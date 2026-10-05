-- Dateizugriff für den Austausch mit der Brücke. Austauschbar (Tests nutzen ein Speicher-Dateisystem).
-- Schnittstelle: read(path) -> text|nil, write_atomic(path, text) -> ok, remove(path), exists(path)

local fs = {}

function fs.read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

function fs.exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

--- Schreibt erst in eine temporäre Datei und benennt dann um, damit die Brücke nie halbe Dateien liest.
function fs.write_atomic(path, text)
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "wb")
  if not f then return false, err end
  f:write(text)
  f:close()
  os.remove(path) -- Windows: rename überschreibt nicht
  local ok, rerr = os.rename(tmp, path)
  if not ok then return false, rerr end
  return true
end

function fs.remove(path)
  os.remove(path)
end

--- Speicher-Dateisystem für Tests.
function fs.memory()
  local files = {}
  return {
    files = files,
    read = function(path) return files[path] end,
    exists = function(path) return files[path] ~= nil end,
    write_atomic = function(path, text) files[path] = text return true end,
    remove = function(path) files[path] = nil end,
  }
end

return fs
