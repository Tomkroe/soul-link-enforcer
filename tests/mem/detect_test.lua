-- Ereigniserkennung aus Schnappschüssen.
local T = require("lib.t")
local Detect = require("mem.detect")

local R201 = { key = "201", name = "Route 201" }
local R202 = { key = "202", name = "Route 202" }

local function mon(uid, hp, extra)
  local m = { uid = uid, species = 1, species_name = "Art-" .. uid, level = 5, hp = hp or 20, max_hp = 20 }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

local function snap(t, fields)
  local s = { t = t, area = R201, badges = 0, play_time = math.floor(t / 1000), has_balls = true, party = {} }
  for k, v in pairs(fields or {}) do s[k] = v end
  return s
end

local function types(events)
  local out = {}
  for _, e in ipairs(events) do out[#out + 1] = e.type end
  return out
end

T.test("Erster Schnappschuss: Status und Team, Bestand ist kein Fang", function()
  local d = Detect.new()
  local ev = d:update(snap(0, { party = { mon("a") } }))
  T.eq(types(ev), { "status", "party" })
  T.eq(ev[1].area.key, "201")
  T.eq(ev[2].mons[1].uid, "a")
end)

T.test("Status nur bei Änderung oder alle 30 Sekunden", function()
  local d = Detect.new()
  d:update(snap(0))
  T.eq(#d:update(snap(1000)), 0)
  T.eq(types(d:update(snap(2000, { area = R202 }))), { "status" })
  T.eq(#d:update(snap(10000, { area = R202 })), 0)
  T.eq(types(d:update(snap(40000, { area = R202 }))), { "status" })
  T.eq(types(d:update(snap(41000, { area = R202, badges = 1 }))), { "status" })
end)

T.test("Fang im wilden Kampf", function()
  local d = Detect.new()
  d:update(snap(0, { party = { mon("a") } }))
  local battle = { wild = true, opponent = { species = 16, species_name = "Staralili", family = 396 } }
  T.eq(types(d:update(snap(1000, { party = { mon("a") }, battle = battle }))), { "status" })
  local ev = d:update(snap(2000, { party = { mon("a"), mon("b", 20, { species = 16 }) }, battle = battle }))
  local c = T.has(ev, { type = "catch", uid = "b" })
  T.eq(c.gift, false)
  T.eq(c.area.key, "201")
  ev = d:update(snap(3000, { party = { mon("a"), mon("b") } }))
  T.no(T.find(ev, { type = "encounter_failed" }))
  ev = d:update(snap(30000, { party = { mon("a"), mon("b") } }))
  T.no(T.find(ev, { type = "encounter_failed" }))
end)

T.test("Fang erscheint erst nach Kampfende (Spitznamen-Abfrage)", function()
  local d = Detect.new()
  d:update(snap(0, { party = { mon("a") } }))
  d:update(snap(1000, { party = { mon("a") }, battle = { wild = true, opponent = { species = 16 } } }))
  d:update(snap(2000, { party = { mon("a") } }))
  local ev = d:update(snap(9000, { area = R202, party = { mon("a") }, box = { mon("b") } }))
  local c = T.has(ev, { type = "catch", uid = "b" })
  T.eq(c.gift, false)
  T.eq(c.area.key, "201", "Fang zählt im Gebiet des Kampfes")
end)

T.test("Wilder Kampf ohne Fang: Gebiet verpasst (mit Ergebnis sofort, sonst nach Wartezeit)", function()
  local d = Detect.new()
  d:update(snap(0, { party = { mon("a") } }))
  d:update(snap(1000, { party = { mon("a") }, battle = { wild = true, result = "won", opponent = { species = 16, family = 396, shiny = false } } }))
  local ev = d:update(snap(2000, { party = { mon("a") } }))
  local f = T.has(ev, { type = "encounter_failed" })
  T.eq(f.family, 396)

  local d2 = Detect.new()
  d2:update(snap(0, { party = { mon("a") } }))
  d2:update(snap(1000, { party = { mon("a") }, battle = { wild = true, opponent = { species = 16 } } }))
  T.no(T.find(d2:update(snap(2000, { party = { mon("a") } })), { type = "encounter_failed" }))
  T.no(T.find(d2:update(snap(15000, { party = { mon("a") } })), { type = "encounter_failed" }))
  T.has(d2:update(snap(23000, { party = { mon("a") } })), { type = "encounter_failed" })
end)

T.test("Trainerkämpfe verbrauchen kein Gebiet", function()
  local d = Detect.new()
  d:update(snap(0, { party = { mon("a") } }))
  d:update(snap(1000, { party = { mon("a") }, battle = { wild = false, result = "won", opponent = {} } }))
  d:update(snap(2000, { party = { mon("a") } }))
  T.no(T.find(d:update(snap(30000, { party = { mon("a") } })), { type = "encounter_failed" }))
end)

T.test("Geschenk außerhalb von Kämpfen", function()
  local d = Detect.new()
  d:update(snap(0))
  local ev = d:update(snap(1000, { party = { mon("starter") } }))
  T.eq(T.has(ev, { type = "catch" }).gift, true)
  T.has(ev, { type = "party" })
end)

T.test("Tod: KP fallen auf 0, mit Gegner; tote Monster lösen keinen neuen Tod aus", function()
  local d = Detect.new()
  local opp = { species = 66, species_name = "Machollo" }
  d:update(snap(0, { party = { mon("a"), mon("b") } }))
  d:update(snap(1000, { party = { mon("a"), mon("b") }, battle = { wild = false, opponent = opp } }))
  local ev = d:update(snap(2000, { party = { mon("a", 0), mon("b") }, battle = { wild = false, opponent = opp } }))
  local f = T.has(ev, { type = "faint", uid = "a" })
  T.eq(f.opponent, "Machollo")
  -- geheilt und vom Script wieder auf 0 gesetzt: kein neues Ereignis
  d:update(snap(3000, { party = { mon("a", 15), mon("b") } }), { a = true })
  ev = d:update(snap(4000, { party = { mon("a", 0), mon("b") } }), { a = true })
  T.no(T.find(ev, { type = "faint" }))
end)

T.test("Eier zählen erst nach dem Schlüpfen", function()
  local d = Detect.new()
  d:update(snap(0, { party = { mon("a") } }))
  local ev = d:update(snap(1000, { party = { mon("a"), mon("egg", 0, { is_egg = true }) } }))
  T.no(T.find(ev, { type = "catch" }))
  ev = d:update(snap(2000, { area = R202, party = { mon("a"), mon("egg", 10) } }))
  local c = T.has(ev, { type = "catch", uid = "egg" })
  T.eq(c.area.key, "202")
end)

T.test("Vorbekannte Monster aus dem Server-Zustand", function()
  local d = Detect.new()
  d:seed_known({ "x" })
  d:update(snap(0))
  T.no(T.find(d:update(snap(1000, { party = { mon("x") } })), { type = "catch" }))
end)
