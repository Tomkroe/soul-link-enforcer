-- Automatische Sicherungen der Speicherdatei (Phase 4).
-- Wann: vor dem ersten Schreibzugriff jeder Sitzung, bei jedem neuen Orden und alle 15 Minuten.
-- Behalten: die letzten 20 (Liste in <dir>/index.json, weil Lua keine Ordner auflisten kann).
-- Dateiname: <Zeitstempel>_orden<N>_<Grund>.dsv

local json = require("lib.json")

local Backup = {}
Backup.__index = Backup

--- opts: fs (read/write_atomic/remove), save_path, dir, keep (20), interval_ms (15 min), date (Funktion -> Text)
function Backup.new(opts)
  local self = setmetatable({}, Backup)
  self.fs = opts.fs
  self.save_path = opts.save_path
  self.dir = opts.dir
  self.keep = opts.keep or 20
  self.interval_ms = opts.interval_ms or 15 * 60 * 1000
  self.date = opts.date or function() return os.date("%Y-%m-%d_%H-%M-%S") end
  self.last_t = nil
  self.first_write_done = false
  self.last_badges = nil
  self.index_path = self.dir .. "/index.json"
  local text = self.fs.read(self.index_path)
  local ok, idx = pcall(json.decode, text or "[]")
  self.index = (ok and type(idx) == "table") and idx or {}
  return self
end

function Backup:enabled()
  return self.save_path ~= nil and self.save_path ~= ""
end

--- Legt eine Sicherung an. Rückgabe: Dateiname oder nil, Fehler
function Backup:create(reason, badges)
  if not self:enabled() then return nil, "Kein Pfad zur Speicherdatei in config.lua" end
  local data = self.fs.read(self.save_path)
  if not data then return nil, "Speicherdatei nicht lesbar: " .. self.save_path end
  local name = string.format("%s_orden%.0f_%s.dsv", self.date(), badges or 0, reason)
  local path = self.dir .. "/" .. name
  local ok, err = self.fs.write_atomic(path, data)
  if not ok then return nil, err end
  self.index[#self.index + 1] = name
  while #self.index > self.keep do
    local old = table.remove(self.index, 1)
    self.fs.remove(self.dir .. "/" .. old)
  end
  self.fs.write_atomic(self.index_path, json.encode(json.array(self.index)))
  return name
end

--- Vor dem ersten Schreibzugriff der Sitzung aufrufen.
function Backup:before_first_write(badges)
  if self.first_write_done then return nil end
  self.first_write_done = true
  return self:create("vor-schreiben", badges)
end

--- Regelmäßig aufrufen. Legt bei neuem Orden oder nach Ablauf des Intervalls eine Sicherung an.
function Backup:tick(now, badges)
  if not self:enabled() then return nil end
  if self.last_badges ~= nil and badges and badges > self.last_badges then
    self.last_badges = badges
    self.last_t = now
    return self:create("orden", badges)
  end
  if badges then self.last_badges = badges end
  if self.last_t == nil then
    self.last_t = now
    return nil
  end
  if now - self.last_t >= self.interval_ms then
    self.last_t = now
    return self:create("intervall", badges)
  end
  return nil
end

return Backup
