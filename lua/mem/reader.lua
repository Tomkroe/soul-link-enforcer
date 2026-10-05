-- Spiel-Leser: baut aus den Profil-Adressen einen Schnappschuss für mem/detect.lua.
-- Fehlende Profileinträge ergeben nil-Felder (die Erkennung arbeitet dann nur eingeschränkt).
-- Schreibzugriffe (KP auf 0) laufen ausschließlich über den Schreibschutz (mem/guard.lua).

local P = require("mem.pkm")

local Reader = {}
Reader.__index = Reader

--- opts: profile, emu, guard, names (optional: Funktion species -> Name, aus Spieldaten)
function Reader.new(opts)
  local self = setmetatable({}, Reader)
  self.profile = opts.profile
  self.emu = opts.emu
  self.guard = opts.guard
  self.names = opts.names or function() return nil end
  self.gen = opts.profile.gen
  self.party_size = P.PARTY_SIZE[self.gen]
  self.party_slots = {} -- uid -> Slot (für Schreibzugriffe)
  return self
end

function Reader:entry(name)
  return self.profile.addresses[name]
end

function Reader:addr(name)
  local e = self:entry(name)
  if not e then return nil end
  return self.emu.resolve(e)
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
  local count_addr, base = self:addr("party_count"), self:addr("party")
  if not count_addr or not base then return nil end
  local count = self.emu.read8(count_addr)
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
  local base = self:addr("boxes")
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

--- Schnappschuss. t: Zeit in ms. Boxen werden nur gelesen, wenn read_box gesetzt ist (teuer).
function Reader:snapshot(t, read_box)
  local snap = { t = t }
  snap.party = self:read_party()
  if read_box then snap.box = self:read_box() end
  local area = self:addr("area_id")
  if area then
    local id = self.emu.read16(area)
    snap.area = { key = tostring(id), name = self.area_name and self.area_name(id) or ("Gebiet " .. tostring(id)) }
  end
  local badges = self:addr("badges")
  if badges then snap.badges = bitcount(self.emu.read8(badges)) end
  local pt = self:addr("play_time")
  if pt then
    snap.play_time = self.emu.read16(pt) * 3600 + self.emu.read8(pt + 2) * 60 + self.emu.read8(pt + 3)
  end
  local balls = self:addr("bag_balls")
  if balls then snap.has_balls = self.emu.read16(balls) ~= 0 end
  local bf = self:addr("battle_flag")
  if bf and self.emu.read8(bf) ~= 0 then
    snap.battle = { wild = true, opponent = {} }
    local bt = self:addr("battle_type")
    if bt then snap.battle.wild = self.emu.read8(bt) == 0 end
  end
  return snap
end

--- Setzt die KP eines Team-Monsters (über den Schreibschutz). Rückgabe: ok, Grund
function Reader:set_hp(uid, hp, in_battle)
  local slot = self.party_slots[uid]
  if not slot then return false, "nicht im Team" end
  local base_off = slot * self.party_size
  local ok, reason = self.guard:can_write("party", in_battle)
  if not ok then return false, reason end
  local base = self:addr("party") + base_off
  local plain = P.decrypt(self.emu.read_bytes(base, self.party_size))
  if P.parse(plain, self.gen).uid ~= uid then return false, "Slot hat sich geändert" end
  local raw = P.encrypt(P.set_hp(plain, hp))
  return self.guard:write_bytes("party", base_off, raw, in_battle)
end

return Reader
