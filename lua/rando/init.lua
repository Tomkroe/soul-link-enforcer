-- Randomizer (Phase 5): Steuerung im Script.
--
-- Stufe A (umgesetzt): Beim Gebietswechsel wird die geladene Begegnungstabelle gemäß Seed überschrieben.
--   Die Zuordnung ist pro Gebiet fest (rando/mapping.lua), alle Spieler mit gleichem Seed, gleichen
--   Einstellungen und gleicher Edition erhalten dieselben Begegnungen (Abgleich über Fingerabdruck).
-- Stufe B und C: Zuordnungen fertig (mapping.lua), Schreibzugriffe erst nach stabil getesteter Stufe A
--   (Profil: randomizer.stage_a_stable = true) – noch nicht umgesetzt.
--
-- Nie aktiv ohne: Modus ≠ aus, Profilangaben (randomizer.encounter_layout), getestete Adresse
-- "encounter_table" + Schreibfreigabe (mem/guard.lua). Geschrieben wird nur außerhalb von Kämpfen.

local json = require("lib.json")
local Map = require("rando.mapping")
local Enc = require("rando.encounters")
local RomFS = require("rando.romfs")
local Finder = require("mem.finder")

local Rando = {}
Rando.__index = Rando

Rando.SCAN_BYTES_PER_TICK = 0x40000

--- opts: profile, emu, guard, reader (für Adressauflösung), fs, local_dir, note, rom (RomFS) | rom_path,
---       backup (Funktion vor erstem Schreiben)
function Rando.new(opts)
  local self = setmetatable({}, Rando)
  self.profile = opts.profile or {}
  self.cfg = self.profile.randomizer or {}
  self.emu, self.guard, self.reader = opts.emu, opts.guard, opts.reader
  self.fs, self.local_dir = opts.fs, opts.local_dir
  self.note = opts.note or function() end
  self.backup = opts.backup or function() end
  self.rom, self.rom_path = opts.rom, opts.rom_path
  self.status = "aus"
  self.reason = ""
  self.key = nil          -- Seed|Modus, für den die Vorbereitung gilt
  self.done_areas = {}    -- [gebiet] = geschriebene Arten (Text), um Doppelanwendung zu vermeiden
  self.table_addr = nil
  self.writes = 0
  return self
end

function Rando:gen()
  return self.profile.gen or 4
end

--- ROM-Dateien (nur bei Bedarf): Begegnungstabellen aus dem NARC.
function Rando:rom_tables()
  if self.tables ~= nil then return self.tables or nil, self.tables_err end
  self.tables = false
  if not self.rom then
    if not self.rom_path or self.rom_path == "" then
      self.tables_err = "rom_path in config.lua fehlt"
      return nil, self.tables_err
    end
    local rom, err = RomFS.open_file(self.rom_path)
    if not rom then self.tables_err = err return nil, err end
    self.rom = rom
  end
  local data, err = self.rom:file(self.cfg.encounter_narc or "")
  if not data then self.tables_err = err return nil, err end
  local files, nerr = RomFS.narc(data)
  if not files then self.tables_err = nerr return nil, nerr end
  self.tables = files
  return files
end

--- Artenliste "edition": alle Arten aus den Begegnungsdaten des Spiels.
function Rando:edition_species()
  local files, err = self:rom_tables()
  if not files then return nil, err end
  local out = {}
  for _, f in ipairs(files) do
    for _, sp in ipairs(Enc.species(RomFS.bytes(f), self.cfg.encounter_layout, Map.MAX_SPECIES[self:gen()])) do
      out[#out + 1] = sp
    end
  end
  return out
end

function Rando:set_inactive(status, reason)
  if self.status ~= status or self.reason ~= reason then
    self.status, self.reason = status, reason
    if status == "inaktiv" then self.note("Randomizer inaktiv: " .. reason, "warn") end
  end
end

--- Vorbereitung für die aktuellen Einstellungen. Rückgabe: aktiv?
function Rando:prepare(settings)
  local rs = settings and settings.randomizer or { mode = "aus" }
  if rs.mode == "aus" then
    self:set_inactive("aus", "")
    self.key = nil
    return false
  end
  local key = tostring(rs.seed) .. "|" .. tostring(rs.mode)
  if self.key == key then return self.prepared end
  self.key = key
  self.prepared = false
  self.done_areas = {}
  if not self.cfg.encounter_layout then
    self:set_inactive("inaktiv", "Profil hat kein Begegnungsformat (randomizer.encounter_layout)")
    return false
  end
  local edition
  if rs.mode == "edition" then
    local err
    edition, err = self:edition_species()
    if not edition then
      self:set_inactive("inaktiv", "Modus 'edition': " .. tostring(err))
      return false
    end
  end
  local pool, perr = Map.pool(rs.mode, self:gen(), edition, self.cfg.exclude)
  if not pool or #pool == 0 then
    self:set_inactive("inaktiv", perr or "leere Artenliste")
    return false
  end
  self.seed, self.mode, self.pool = rs.seed, rs.mode, pool
  self.fingerprint = Map.fingerprint(rs.seed, rs.mode, pool)
  self:load_originals()
  self.status, self.reason = "bereit", ""
  self.prepared = true
  return true
end

-- Originaltabellen pro Gebiet dauerhaft merken (übersteht Script-Neustarts mit bereits geänderter Tabelle).
function Rando:originals_path()
  return self.local_dir .. "/rando_" .. tostring(self.profile.game_code) .. ".json"
end

function Rando:load_originals()
  self.originals = {}
  local ok, data = pcall(json.decode, self.fs.read(self:originals_path()) or "")
  if ok and type(data) == "table" and data.key == self.key then
    self.originals = data.areas or {}
    self.written = data.written or {}
  else
    self.written = {}
  end
end

function Rando:save_originals()
  self.fs.write_atomic(self:originals_path(), json.encode(json.object({
    key = self.key, areas = json.object(self.originals), written = json.object(self.written),
  })))
end

local function species_key(list)
  local parts = {}
  for _, v in ipairs(list) do parts[#parts + 1] = string.format("%.0f", v) end
  return table.concat(parts, ",")
end

--- Adresse der geladenen Begegnungstabelle (Profil oder Suche über die ROM-Tabellen).
function Rando:locate_table(size)
  local entry = self.profile.addresses and self.profile.addresses.encounter_table
  if not entry then return nil, "Adresse encounter_table fehlt im Profil" end
  if entry.addr or entry.ptr or entry.chain then
    return self.reader and self.reader:resolve(entry) or self.emu.resolve(entry)
  end
  if not entry.scan then return nil, "keine Adresse und keine Suche für encounter_table" end
  local files, err = self:rom_tables()
  if not files then return nil, "Suche braucht die ROM-Tabellen: " .. tostring(err) end
  if self.table_addr then
    -- Gültig, solange dort eine plausible Tabelle liegt (Original oder unsere geschriebene)
    local current = self.emu.read_bytes(self.table_addr, size)
    if Enc.plausible(current, self.cfg.encounter_layout, Map.MAX_SPECIES[self:gen()]) then
      return self.table_addr
    end
    self.table_addr = nil
  end
  self.scan = self.scan or Finder.block_scanner(self.emu, files)
  self.scan:step(Rando.SCAN_BYTES_PER_TICK)
  if #self.scan.found > 0 then
    self.table_addr = self.scan.found[1].addr
    self.scan = nil
    return self.table_addr
  end
  if self.scan.done then self.scan = nil end
  return nil, "suche Begegnungstabelle ..."
end

--- Pro Prüfzyklus. settings: Run-Einstellungen; snap: Schnappschuss (area, battle).
function Rando:tick(settings, snap)
  if not self:prepare(settings) then return end
  if not snap or not snap.area then return end
  if snap.battle then return end -- nur außerhalb von Kämpfen schreiben
  local ok, reason = self.guard:can_write("encounter_table")
  if not ok then
    self:set_inactive("inaktiv", reason)
    return
  end
  local layout = self.cfg.encounter_layout
  local size = layout.size
  local addr, err = self:locate_table(size)
  if not addr then
    self.status, self.reason = "bereit", err or ""
    return
  end
  local area = snap.area.key
  local bytes = self.emu.read_bytes(addr, size)
  if not Enc.plausible(bytes, layout, Map.MAX_SPECIES[self:gen()]) then
    self.status, self.reason = "bereit", "Tabelle an " .. string.format("%.0f", addr) .. " unplausibel"
    return
  end
  local current = Enc.species(bytes, layout)
  local cur_key = species_key(current)
  if self.written[area] == cur_key then
    self.status = "aktiv"
    return -- bereits randomisiert
  end
  -- Original merken (erstes Mal in diesem Gebiet) – danach immer dieselbe Zuordnung verwenden
  self.originals[area] = self.originals[area] or current
  local map = Map.area_map(self.seed, area, self.originals[area], self.pool)
  local new_bytes, changed = Enc.apply(bytes, layout, map)
  if changed > 0 then
    self.backup()
    local wok, werr = self.guard:write_bytes_at("encounter_table", addr, new_bytes)
    if not wok then
      self:set_inactive("inaktiv", werr or "Schreiben abgelehnt")
      return
    end
    self.writes = self.writes + 1
  end
  self.written[area] = species_key(Enc.species(new_bytes, layout))
  self:save_originals()
  self.status, self.reason = "aktiv", ""
end

--- Statuszeile für das Overlay.
function Rando:status_line()
  if self.status == "aus" then return nil end
  if self.status == "aktiv" then return "Randomizer aktiv (" .. tostring(self.mode) .. ", " .. tostring(self.fingerprint) .. ")" end
  if self.status == "bereit" then return "Randomizer: " .. (self.reason ~= "" and self.reason or "bereit") end
  return "Randomizer inaktiv: " .. self.reason
end

-- Stufen B und C ----------------------------------------------------------------

--- Freigabe-Reihenfolge: B erst nach stabiler Stufe A, C erst nach stabiler Stufe B.
function Rando:stage_allowed(stage)
  if stage == "A" then return true end
  if stage == "B" then
    if self.cfg.stage_a_stable ~= true then return false, "Stufe B erst, wenn Stufe A stabil getestet ist" end
    return false, "Stufe B ist noch nicht umgesetzt"
  end
  if stage == "C" then
    if self.cfg.stage_b_stable ~= true then return false, "Stufe C erst, wenn Stufe B stabil getestet ist" end
    return false, "Stufe C ist noch nicht umgesetzt"
  end
  return false, "unbekannte Stufe"
end

Rando.Map = Map
return Rando
