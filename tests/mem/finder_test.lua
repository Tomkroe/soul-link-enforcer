-- Adress-Suche und Zeigerketten mit dem Speicher-Emulator.
local T = require("lib.t")
local Emu = require("mem.emu")
local P = require("mem.pkm")
local Finder = require("mem.finder")

local function party_mon(pid, species, level, hp, max_hp)
  local b = {}
  for i = 1, P.PARTY_SIZE[4] do b[i] = 0 end
  P.set_u32(b, 0, pid)
  P.set_u16(b, 0x08, species)
  P.set_u16(b, 0x0C, 1)
  P.set_u16(b, 0x0E, 2)
  b[0x8C + 1] = level
  P.set_u16(b, 0x8E, hp)
  P.set_u16(b, 0x90, max_hp)
  P.set_u16(b, 0x06, P.checksum(b))
  return P.encrypt(b)
end

local function put(emu, addr, bytes)
  for i, v in ipairs(bytes) do emu.write8(addr + i - 1, v) end
end

-- Legt ein Team (Kapazität 6, Anzahl n) ab addr - 8 an.
local function put_party(emu, addr, mons)
  emu.write32(addr - 8, 6)
  emu.write32(addr - 4, #mons)
  for i, m in ipairs(mons) do put(emu, addr + (i - 1) * 236, m) end
end

T.test("Team-Signatur erkennen", function()
  local emu = Emu.fake()
  local addr = 0x0227F0B4
  put_party(emu, addr, { party_mon(305419896, 393, 5, 20, 20), party_mon(99, 396, 3, 12, 14) })
  local ok, count, m = Finder.party_at(emu, addr, 4)
  T.ok(ok)
  T.eq(count, 2)
  T.eq(m.species, 393)
  T.no(Finder.party_at(emu, addr + 4, 4))
  -- unplausible Werte
  local bad = 0x02100000
  put_party(emu, bad, { party_mon(7, 600, 5, 20, 20) })
  T.no(Finder.party_at(emu, bad, 4), "Art > 493")
  put_party(emu, bad, { party_mon(7, 25, 5, 30, 20) })
  T.no(Finder.party_at(emu, bad, 4), "KP > Max-KP")
end)

T.test("Suche über den Speicher findet das Team, Köder mit falscher Prüfsumme nicht", function()
  local emu = Emu.fake()
  -- Köder: Kopf passt, Daten nicht
  emu.write32(0x02010000, 6)
  emu.write32(0x02010004, 2)
  for i = 0, 235 do emu.write8(0x02010008 + i, (i * 31) % 256) end
  local addr = 0x02123458 -- 4-Byte-ausgerichtet
  put_party(emu, addr, { party_mon(4242, 25, 12, 30, 33) })
  local s = Finder.scanner(emu, 4, { from = 0x02000000, to = 0x02200000 })
  local steps = 0
  while not s:step(0x40000) do steps = steps + 1 end
  T.eq(s.found, { addr })
  T.ok(steps > 3, "schrittweise")
end)

T.test("Zeigerketten auflösen, ungültige Zeiger ergeben nil", function()
  local emu = Emu.fake()
  emu.write32(0x02000BA8, 0x02200000)
  emu.write32(0x02200020, 0x0227F000)
  T.eq(emu.resolve({ chain = { 0x02000BA8, 0x20 }, offset = 0xB4 }), 0x0227F0B4)
  emu.write32(0x02101D2C, 0x02272020)
  T.eq(emu.resolve({ ptr = 0x02101D2C, offset = 0xD094 }), 0x0227F0B4)
  T.eq(emu.resolve({ addr = 0x0224A55A }), 0x0224A55A)
  emu.write32(0x02000BA8, 0)
  T.eq(emu.resolve({ chain = { 0x02000BA8, 0x20 }, offset = 0xB4 }), nil)
end)

T.test("Kandidaten prüfen: erster gültiger gewinnt", function()
  local emu = Emu.fake()
  local addr = 0x0227F0B4
  put_party(emu, addr, { party_mon(1, 1, 5, 10, 10) })
  emu.write32(0x02101D2C, 0x02272020)
  local found, i = Finder.try_candidates(emu, {
    { chain = { 0x02000BA8, 0x20 }, offset = 0xB4 }, -- Zeiger fehlt
    { ptr = 0x02101D2C, offset = 0xD094 },
  }, 4)
  T.eq(found, addr)
  T.eq(i, 2)
end)

T.test("Zeiger auf die Team-Basis finden", function()
  local emu = Emu.fake()
  emu.write32(0x02000400, 0x0227F000)  -- zeigt auf Team - 0xB4
  emu.write32(0x02000800, 0x02272020)  -- zeigt auf Team - 0xD094
  emu.write32(0x02000900, 0x02270000)  -- irrelevant
  local hits = Finder.find_pointers(emu, 0x0227F0B4, { 0xB4, 0xD094 }, 0x02000000, 0x02001000)
  T.eq(#hits, 2)
  T.eq(hits[1].ptr, 0x02000400)
  T.eq(hits[1].offset, 0xB4)
  T.eq(hits[2].offset, 0xD094)
end)

T.test("Game-Code an der Header-Adresse", function()
  T.eq(Emu.GAME_CODE_ADDR, 0x023FFE0C)
  T.eq(Emu.fake({ game_code = "CPUD" }).game_code(), "CPUD")
  T.eq(Emu.fake().game_code(), nil)
end)

return { party_mon = party_mon, put_party = put_party }
