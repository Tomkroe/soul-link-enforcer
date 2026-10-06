-- Ereigniserkennung: vergleicht aufeinanderfolgende Schnappschüsse des Spielzustands und erzeugt
-- Ereignisse für die Regel-Engine (status, party, catch, faint, encounter_failed).
-- Rein, ohne Emulator-API: Die Schnappschüsse liefert der Spiel-Leser (mem/reader.lua) aus dem Profil.
--
-- Schnappschuss:
--   { t = ms, area = {key, name}, badges, play_time, has_balls, completed, battle_items (Summe Medizin/Kampf-Items),
--     party = { {uid, species, species_name, nickname, level, hp, max_hp, shiny, family, is_egg}, ... },
--     box = { {uid, ...}, ... }  (optional),
--     battle = nil | { wild = bool, result = nil|"caught"|"won"|"fled"|"lost",
--                      opponent = {species, species_name, level, shiny, family} } }

local Detect = {}
Detect.__index = Detect

Detect.STATUS_INTERVAL_MS = 30000  -- Spielzeit höchstens alle 30 s melden
Detect.CATCH_WINDOW_MS = 20000     -- so lange nach einem wilden Kampf ohne Ergebnis auf den Fang warten

function Detect.new()
  return setmetatable({
    prev = nil, known = {}, battle = nil, pending = nil, last_status = nil, last_status_t = -1e12,
  }, Detect)
end

--- Bereits bekannte Monster (z. B. aus dem Server-Zustand) – werden nicht erneut als Fang gemeldet.
function Detect:seed_known(uids)
  for _, uid in ipairs(uids) do self.known[uid] = true end
end

local function all_mons(snap)
  local out = {}
  for _, m in ipairs(snap.party or {}) do out[#out + 1] = m end
  for _, m in ipairs(snap.box or {}) do out[#out + 1] = m end
  return out
end

local function party_key(snap)
  local ids = {}
  for _, m in ipairs(snap.party or {}) do ids[#ids + 1] = m.uid end
  return table.concat(ids, ",")
end

local function mon_info(m)
  return {
    uid = m.uid, species = m.species, species_name = m.species_name, nickname = m.nickname,
    level = m.level, shiny = m.shiny, family = m.family, types = m.types,
  }
end

function Detect:status_event(snap)
  local s = {
    area = snap.area, badges = snap.badges, has_balls = snap.has_balls,
    in_battle = snap.battle ~= nil, completed = snap.completed,
  }
  local key = table.concat({
    tostring(snap.area and snap.area.key), tostring(snap.badges), tostring(snap.has_balls),
    tostring(s.in_battle), tostring(snap.completed),
  }, "|")
  local due = snap.t - self.last_status_t >= Detect.STATUS_INTERVAL_MS
  if key ~= self.last_status or due then
    self.last_status = key
    self.last_status_t = snap.t
    s.type = "status"
    s.play_time = snap.play_time
    return s
  end
  return nil
end

--- Verarbeitet einen Schnappschuss. dead: Menge toter Kennungen (werden auf 0 KP gehalten, kein neuer Tod).
-- Rückgabe: Liste von Ereignissen.
function Detect:update(snap, dead)
  dead = dead or {}
  local events = {}
  local function emit(ev) events[#events + 1] = ev end
  local area = snap.area

  if not self.prev then
    -- Erster Schnappschuss: Bestand gilt als bekannt, nichts als Fang melden.
    for _, m in ipairs(all_mons(snap)) do self.known[m.uid] = true end
  end

  local st = self:status_event(snap)
  if st then emit(st) end

  -- Kampfbeginn (Item-Bestand merken: Items im Kampf, Phase 6.7)
  if snap.battle and not self.battle then
    local party = {}
    for _, m in ipairs(snap.party or {}) do if (m.hp or 1) > 0 then party[#party + 1] = m.uid end end
    self.battle = { wild = snap.battle.wild, opponent = snap.battle.opponent or {}, caught = false, area = area,
      items_before = self.prev and self.prev.battle_items, party = party, fought = {}, kos = {}, enemy_hp = {} }
  end
  -- Kampfstatistik: wer kämpft, wer besiegt Gegner (KP eines Gegners fallen auf 0, während er aktiv ist)
  if snap.battle and self.battle then
    local b = self.battle
    local active = snap.battle.active_uid
    if active then b.fought[active] = true end
    for _, e in ipairs(snap.battle.enemies or {}) do
      local before = b.enemy_hp[e.pid]
      if before and before > 0 and e.hp == 0 and active then b.kos[active] = (b.kos[active] or 0) + 1 end
      b.enemy_hp[e.pid] = e.hp
    end
  end

  -- Neue Monster: Fang oder Geschenk
  for _, m in ipairs(all_mons(snap)) do
    if not self.known[m.uid] and not m.is_egg then
      self.known[m.uid] = true
      local ev = mon_info(m)
      ev.type = "catch"
      ev.area = area
      local from_battle = (self.battle and self.battle.wild) or self.pending
      ev.gift = not from_battle
      if self.battle then self.battle.caught = true end
      if self.pending then
        ev.area = self.pending.area or area
        self.pending = nil
      end
      emit(ev)
    end
    -- Eier zählen erst beim Schlüpfen: Ein Ei wird nicht als bekannt vermerkt und erscheint nach dem
    -- Schlüpfen (gleiche Kennung, is_egg = false) als neuer Fang im aktuellen Gebiet.
  end

  -- Tod: KP fallen auf 0
  if self.prev then
    local before = {}
    for _, m in ipairs(self.prev.party or {}) do before[m.uid] = m end
    for _, m in ipairs(snap.party or {}) do
      local b = before[m.uid]
      if b and b.hp and b.hp > 0 and m.hp == 0 and not dead[m.uid] then
        local opp = self.battle and self.battle.opponent or {}
        emit({ type = "faint", uid = m.uid, level = m.level, area = area,
          opponent = opp.species_name or "" })
      end
    end
  end

  -- Kampfende
  if self.battle and not snap.battle then
    local b = self.battle
    self.battle = nil
    if b.items_before and snap.battle_items and snap.battle_items < b.items_before then
      emit({ type = "item_used", count = b.items_before - snap.battle_items })
    end
    local fought = {}
    for uid in pairs(b.fought) do fought[#fought + 1] = uid end
    table.sort(fought)
    emit({ type = "battle_stats", wild = b.wild, party = b.party, fought = fought, kos = b.kos,
      opponent = b.opponent and b.opponent.species_name or "" })
    if b.wild and not b.caught then
      local result = self.prev and self.prev.battle and self.prev.battle.result
      if result == "caught" then
        self.pending = { area = b.area, until_t = snap.t + Detect.CATCH_WINDOW_MS, opponent = b.opponent, sure = true }
      elseif result then
        emit({ type = "encounter_failed", area = b.area, species = b.opponent.species,
          species_name = b.opponent.species_name, family = b.opponent.family, shiny = b.opponent.shiny })
      else
        self.pending = { area = b.area, until_t = snap.t + Detect.CATCH_WINDOW_MS, opponent = b.opponent }
      end
    end
  end

  -- Wartezeit auf Fang abgelaufen
  if self.pending and snap.t > self.pending.until_t then
    local p = self.pending
    self.pending = nil
    if not p.sure then
      emit({ type = "encounter_failed", area = p.area, species = p.opponent.species,
        species_name = p.opponent.species_name, family = p.opponent.family, shiny = p.opponent.shiny })
    end
  end

  -- Teamzusammensetzung
  if not self.prev or party_key(snap) ~= party_key(self.prev) then
    local mons = {}
    for _, m in ipairs(snap.party or {}) do mons[#mons + 1] = mon_info(m) end
    emit({ type = "party", mons = mons })
  end

  self.prev = snap
  return events
end

return Detect
