-- Spiel-Leser mit dem Platin-Profil und dem Speicher-Emulator.
local T = require("lib.t")
local Emu = require("mem.emu")
local P = require("mem.pkm")
local Reader = require("mem.reader")
local Guard = require("mem.guard")
local Profiles = require("profiles")
local F = require("mem.finder_test")

local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = copy(v) end
  return o
end

-- Spielspeicher wie in der US-Version laut Quellen aufbauen.
local function us_layout(emu, opts)
  opts = opts or {}
  local vbase = 0x0227F000
  emu.write32(0x02000BA8, 0x02200000)
  emu.write32(0x02200020, vbase)
  local party = vbase + 0xB4
  F.put_party(emu, party, opts.mons or { F.party_mon(305419896, 393, 5, 20, 20) })
  emu.write8(vbase + 0x96, opts.badges or 3)          -- 2 Orden
  emu.write16(party + 0xC4C, opts.balls or 4)         -- Ball-Tasche
  emu.write16(vbase + 0x239B0, opts.map or 412)
  return vbase, party
end

T.test("Profil CPUD ist gültig und vollständig ungetestet", function()
  local p, msg = Profiles.load("CPUD")
  T.ok(p, msg)
  T.eq(p.name, "Platin")
  local tested, total = Profiles.coverage(p)
  T.eq(tested, 0)
  T.ok(total >= 8)
  T.eq(p.gym_levels.tested, false)
end)

T.test("Platin-Layout: Team über die Zeigerkette, Werte relativ zum Team", function()
  local emu = Emu.fake()
  local _, party = us_layout(emu)
  local r = Reader.new({ profile = Profiles.load("CPUD"), emu = emu })
  local snap = r:snapshot(0)
  T.eq(r.party_addr, party)
  T.ok(r.party_source:find("Ironmon"))
  T.eq(#snap.party, 1)
  T.eq(snap.party[1].species, 393)
  T.eq(snap.badges, 2)
  T.eq(snap.has_balls, true)
  T.eq(snap.area.key, "412")
  T.eq(snap.battle, nil)
end)

T.test("Andere Zeiger (z. B. deutsche Version): Team wird per Suche gefunden", function()
  local emu = Emu.fake()
  local party = 0x02180100
  F.put_party(emu, party, { F.party_mon(77, 25, 9, 25, 25), F.party_mon(78, 1, 7, 20, 22) })
  emu.write8(party - 0x1E, 1)
  local r = Reader.new({ profile = Profiles.load("CPUD"), emu = emu })
  local snap
  for _ = 1, 40 do
    snap = r:snapshot(0)
    if snap.party then break end
  end
  T.eq(r.party_addr, party)
  T.eq(r.party_source, "Suche")
  T.eq(#snap.party, 2)
  T.eq(snap.badges, 1)
  T.eq(snap.area, nil, "Kartenzeiger fehlt -> kein Gebiet statt falscher Werte")
end)

T.test("Erfolglose Suche pausiert und startet dann erneut", function()
  local emu = Emu.fake()
  local r = Reader.new({ profile = Profiles.load("CPUD"), emu = emu })
  for _ = 1, 16 do r:snapshot(0) end
  T.eq(r.scan, nil)
  T.eq(r.scan_pause, Reader.SCAN_PAUSE_TICKS)
  r:snapshot(0)
  T.eq(r.scan_pause, Reader.SCAN_PAUSE_TICKS - 1)
  T.eq(r.scan, nil)
end)

T.test("Kampf: Kennzeichen, wild/Trainer und Gegner", function()
  local emu = Emu.fake()
  local vbase = us_layout(emu)
  emu.write16(0x0224A55A, 0x2100)
  F.put_party(emu, vbase + 0x4BE5C + 8, {}) -- nur damit der Speicher existiert
  local enemy = F.party_mon(1234, 396, 3, 11, 11)
  for i, v in ipairs(enemy) do emu.write8(vbase + 0x4BE5C + i - 1, v) end
  local r = Reader.new({ profile = Profiles.load("CPUD"), emu = emu })
  local snap = r:snapshot(0)
  T.ok(snap.battle)
  T.eq(snap.battle.wild, true)
  T.eq(snap.battle.opponent.species, 396)
  T.eq(snap.battle.opponent.level, 3)
  emu.write16(vbase + 0x4189E, 17)
  T.eq(r:snapshot(0).battle.wild, false)
  emu.write16(0x0224A55A, 0x2800)
  T.eq(r:snapshot(0).battle, nil)
end)

T.test("Leeres Team bei bekannter Adresse wird nicht verworfen", function()
  local emu = Emu.fake()
  local _, party = us_layout(emu)
  local r = Reader.new({ profile = Profiles.load("CPUD"), emu = emu })
  r:snapshot(0)
  emu.write32(party - 4, 0)
  local snap = r:snapshot(0)
  T.eq(r.party_addr, party)
  T.eq(#snap.party, 0)
end)

T.test("KP schreiben nur mit getesteter Team-Adresse, dann an der gefundenen Stelle", function()
  local emu = Emu.fake()
  local _, party = us_layout(emu)
  local profile = copy(Profiles.load("CPUD"))
  local guard = Guard.new({ profile = profile, emu = emu, enabled = true })
  guard:set_selftest(true)
  local r = Reader.new({ profile = profile, emu = emu, guard = guard })
  local snap = r:snapshot(0)
  local uid = snap.party[1].uid
  local ok, reason = r:set_hp(uid, 0)
  T.no(ok)
  T.ok(reason:find("nicht getestet"))
  T.eq(P.parse(P.decrypt(emu.read_bytes(party, 236)), 4).hp, 20)
  profile.addresses.party.tested = true
  T.ok(r:set_hp(uid, 0))
  local back = P.parse(P.decrypt(emu.read_bytes(party, 236)), 4)
  T.eq(back.hp, 0)
  T.ok(back.valid)
end)

T.test("Beutel: Summe der Medizin- und Kampf-Items", function()
  local emu = Emu.fake()
  local _, party = us_layout(emu)
  emu.write16(party + 0xAAC, 17)      -- Trank
  emu.write16(party + 0xAAC + 2, 5)
  emu.write16(party + 0xAAC + 4, 26)  -- Superschutz o. ä.
  emu.write16(party + 0xAAC + 6, 2)
  emu.write16(party + 0xC88, 55)
  emu.write16(party + 0xC88 + 2, 1)
  local r = Reader.new({ profile = Profiles.load("CPUD"), emu = emu })
  T.eq(r:snapshot(0).battle_items, 8)
end)
