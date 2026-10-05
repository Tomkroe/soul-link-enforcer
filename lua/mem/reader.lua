-- Spiel-Leser: baut aus den Profil-Adressen einen Schnappschuss für mem/detect.lua.
-- Fehlende Profileinträge ergeben nil-Felder (die Erkennung arbeitet dann nur eingeschränkt).
-- Schreibzugriffe (KP auf 0) laufen ausschließlich über den Schreibschutz (mem/guard.lua).
--
-- Profileinträge (siehe lua/profiles/_vorlage.lua):
--   { addr = A } | { ptr = P, offset = O } | { chain = {S, o1, ...}, offset = O }
--   { rel = "party", offset = O }   relativ zur gefundenen Team-Adresse
--   party: zusätzlich { candidates = {...}, scan = true } – Kandidaten werden geprüft (Signatur),
--          sonst wird der Hauptspeicher schrittweise durchsucht (mem/finder.lua).
--   width = 8 | 16 | 32 (Standard je nach Feld), values = { [wert] = true } für Kennzeichen.

local P = require("mem.pkm")
local Finder = require("mem.finder")

local Reader = {}
Reader.__index = Reader

Reader.SCAN_BYTES_PER_TICK = 0x40000
Reader.SCAN_PAUSE_TICKS = 60 -- nach einem erfolglosen Durchgang (z. B. Titelbildschirm) kurz warten

--- opts: profile, emu, guard, names (optional: Funktion species -> Name, aus Spieldaten)
function Reader.new(opts)
  local self = setmetatable({}, Reader)
  self.profile = opts.profile
  self.emu = opts.emu
  self.guard = opts.guard
  self.names = opts.names or function() return nil end
  self.gen = opts.profile.gen
  self.party_size = P.PARTY_SIZE[self.gen]
  self.party_slots = {}   -- uid -> Slot (für Schreibzugriffe)
  self.party_addr = nil   -- gefundene Adresse des ersten Team-Datensatzes
  self.party_source = nil -- "Kandidat <n>" | "Suche"
  self.scan = nil
  if self.guard then
    self.guard.resolve = function(entry) return self:resolve(entry) end
  end
  return self
end

function Reader:entry(name)
  return self.profile.addresses[name]
end

--- Team-Adresse bestimmen: bisherige prüfen, sonst Kandidaten, sonst schrittweise Suche.
function Reader:locate_party()
  local e = self:entry("party")
  if not e then return nil end
  if self.party_addr and Finder.party_at(self.emu, self.party_addr, self.gen) then return self.party_addr end
  -- Leeres Team (Spielbeginn) besteht die Signatur nicht; bekannte Adresse dann behalten, wenn die Kapazität passt.
  if self.party_addr and self.emu.read32(self.party_addr - 8) == 6 and self.emu.read32(self.party_addr - 4) == 0 then
    return self.party_addr
  end
  self.party_addr = nil
  if e.candidates then
    local addr, i = Finder.try_candidates(self.emu, e.candidates, self.gen)
    if addr then
      self.party_addr, self.party_source = addr, "Kandidat " .. i .. (e.candidates[i].quelle and (" (" .. e.candidates[i].quelle .. ")") or "")
      return addr
    end
  elseif e.addr or e.ptr or e.chain then
    local addr = self.emu.resolve(e)
    if addr and Finder.party_at(self.emu, addr, self.gen) then
      self.party_addr, self.party_source = addr, "Profil"
      return addr
    end
  end
  if e.scan then
    if (self.scan_pause or 0) > 0 then
      self.scan_pause = self.scan_pause - 1
      return nil
    end
    self.scan = self.scan or Finder.scanner(self.emu, self.gen)
    self.scan:step(Reader.SCAN_BYTES_PER_TICK)
    if #self.scan.found > 0 then
      self.party_addr, self.party_source = self.scan.found[1], "Suche"
      self.scan = nil
      return self.party_addr
    end
    if self.scan.done then
      self.scan = nil
      self.scan_pause = Reader.SCAN_PAUSE_TICKS
    end
  end
  return nil
end

--- Absolute Adresse eines Profileintrags (oder nil).
function Reader:resolve(entry)
  if not entry then return nil end
  -- Team-Adresse wird einmal pro Schnappschuss bestimmt (locate_party), hier nur verwendet.
  if entry.rel == "party" then
    if not self.party_addr then return nil end
    return self.party_addr + (entry.offset or 0)
  end
  if entry == self:entry("party") then return self.party_addr end
  return self.emu.resolve(entry)
end

function Reader:addr(name)
  return self:resolve(self:entry(name))
end

function Reader:read(name, default_width)
  local e = self:entry(name)
  local a = self:resolve(e)
  if not a then return nil end
  local w = e.width or default_width or 8
  if w == 8 then return self.emu.read8(a) end
  if w == 16 then return self.emu.read16(a) end
  return self.emu.read32(a)
end

local function bitcount(n)
  local c = 0
  while n > 0 do
    c = c + n % 2
    n = math.floor(n / 2)
  end
  return c
end

function Reader:read_party()
  local base = self.party_addr
  if not base then return nil end
  local count = self:read("party_count", 32) or self.emu.read32(base - 4)
  if count > 6 then return nil end -- Unsinn: Adresse falsch
  local party = {}
  self.party_slots = {}
  for i = 0, count - 1 do
    local raw = self.emu.read_bytes(base + i * self.party_size, self.party_size)
    local plain = P.decrypt(raw)
    local m = P.parse(plain, self.gen)
    if m.valid and m.species ~= 0 then
      m.species_name = self.names(m.species)
      party[#party + 1] = m
      self.party_slots[m.uid] = i
    end
  end
  return party
end

function Reader:read_box()
  local e = self:entry("boxes")
  local base = self:resolve(e)
  if not e or not base then return nil end
  local out = {}
  local total = (e.count or 18) * (e.slots or 30)
  for i = 0, total - 1 do
    local raw = self.emu.read_bytes(base + i * P.BOX_SIZE, P.BOX_SIZE)
    if not (raw[1] == 0 and raw[2] == 0 and raw[3] == 0 and raw[4] == 0 and raw[7] == 0 and raw[8] == 0) then
      local m = P.parse(P.decrypt(raw), self.gen)
      if m.valid and m.species ~= 0 then out[#out + 1] = m end
    end
  end
  return out
end

function Reader:read_battle()
  local e = self:entry("battle_flag")
  if not e then return nil end
  local v = self:read("battle_flag", 8)
  if v == nil then return nil end
  local active
  if e.values then active = e.values[v] == true else active = v ~= 0 end
  if not active then return nil end
  local battle = { wild = true, opponent = {} }
  local bt = self:entry("battle_type")
  if bt then
    local t = self:read("battle_type", 16)
    if t ~= nil then
      if bt.wild_if_zero then battle.wild = t == 0 else battle.wild = t ~= 0 end
    end
  end
  local enemy = self:addr("battle_enemy")
  if enemy then
    local plain = P.decrypt(self.emu.read_bytes(enemy, self.party_size))
    local ok, m = Finder.plausible_mon(plain, self.gen)
    if ok then
      battle.opponent = { species = m.species, level = m.level, shiny = m.shiny, species_name = self.names(m.species) }
    end
  end
  return battle
end

--- Schnappschuss. t: Zeit in ms. Boxen werden nur gelesen, wenn read_box gesetzt ist (teuer).
function Reader:snapshot(t, read_box)
  local snap = { t = t }
  self:locate_party()
  snap.party = self:read_party()
  if read_box then snap.box = self:read_box() end
  local area = self:read("area_id", 16)
  if area then
    snap.area = { key = tostring(area), name = self.area_name and self.area_name(area) or ("Gebiet " .. tostring(area)) }
  end
  local badges = self:read("badges", 8)
  if badges then snap.badges = bitcount(badges) end
  local pt = self:addr("play_time")
  if pt then
    snap.play_time = self.emu.read16(pt) * 3600 + self.emu.read8(pt + 2) * 60 + self.emu.read8(pt + 3)
  end
  local balls = self:read("bag_balls", 16)
  if balls then snap.has_balls = balls ~= 0 end
  snap.battle = self:read_battle()
  return snap
end

--- Diagnose für check.lua: was ist gefunden, welche Werte liest das Profil?
function Reader:diagnose()
  local out = {}
  local base = self:locate_party()
  out.party_addr = base
  out.party_source = self.party_source
  if base then
    out.party_count = self.emu.read32(base - 4)
    local party = self:read_party() or {}
    out.party = party
  end
  for _, name in ipairs({ "badges", "area_id", "bag_balls", "battle_flag", "battle_type", "play_time" }) do
    local e = self:entry(name)
    if e then
      local ok, v = pcall(self.read, self, name, name == "badges" and 8 or 16)
      out[name] = ok and v or nil
    end
  end
  return out
end

--- Setzt die KP eines Team-Monsters (über den Schreibschutz). Rückgabe: ok, Grund
function Reader:set_hp(uid, hp, in_battle)
  local slot = self.party_slots[uid]
  if not slot then return false, "nicht im Team" end
  local base_off = slot * self.party_size
  local ok, reason = self.guard:can_write("party", in_battle)
  if not ok then return false, reason end
  local base = self.party_addr
  if not base then return false, "Team-Adresse unbekannt" end
  local plain = P.decrypt(self.emu.read_bytes(base + base_off, self.party_size))
  if P.parse(plain, self.gen).uid ~= uid then return false, "Slot hat sich geändert" end
  local raw = P.encrypt(P.set_hp(plain, hp))
  return self.guard:write_bytes("party", base_off, raw, in_battle)
end

return Reader
