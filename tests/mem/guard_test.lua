-- Schreibschutz: unbekannte ROM oder ungetestete Adresse führt nie zu Schreibzugriffen.
local T = require("lib.t")
local Guard = require("mem.guard")

local function fake_emu()
  local e = { writes = {} }
  e.write8 = function(a, v) e.writes[#e.writes + 1] = { 8, a, v } end
  e.write16 = function(a, v) e.writes[#e.writes + 1] = { 16, a, v } end
  e.write32 = function(a, v) e.writes[#e.writes + 1] = { 32, a, v } end
  return e
end

local profile = {
  addresses = {
    party = { addr = 1000, tested = true, battle_safe = false },
    party_battle = { addr = 2000, tested = true, battle_safe = true },
    bag = { addr = 3000, tested = false },
  },
}

T.test("Unbekannte ROM: kein Schreiben", function()
  local emu = fake_emu()
  local g = Guard.new({ profile = nil, emu = emu, enabled = true })
  g:set_selftest(true)
  T.no(g:write("party", 0, 16, 0))
  T.eq(#emu.writes, 0)
end)

T.test("Ungetestete oder fehlende Adresse: kein Schreiben", function()
  local emu = fake_emu()
  local g = Guard.new({ profile = profile, emu = emu, enabled = true })
  g:set_selftest(true)
  local ok, reason = g:write("bag", 0, 16, 999)
  T.no(ok)
  T.ok(reason:find("nicht getestet"))
  T.no(g:write("gibtsnicht", 0, 8, 1))
  T.no(g:write_bytes("bag", 0, { 1, 2, 3 }))
  T.eq(#emu.writes, 0)
end)

T.test("Ohne Freigabe oder ohne bestandene Selbsttests: kein Schreiben", function()
  local emu = fake_emu()
  local g = Guard.new({ profile = profile, emu = emu, enabled = false })
  g:set_selftest(true)
  T.no(g:write("party", 0, 16, 0))
  local g2 = Guard.new({ profile = profile, emu = emu, enabled = true })
  T.no(g2:write("party", 0, 16, 0))
  T.eq(#emu.writes, 0)
end)

T.test("Im Kampf nur freigegebene Adressen", function()
  local emu = fake_emu()
  local g = Guard.new({ profile = profile, emu = emu, enabled = true })
  g:set_selftest(true)
  T.no(g:write("party", 0, 16, 0, true))
  T.ok(g:write("party_battle", 4, 16, 0, true))
  T.eq(emu.writes, { { 16, 2004, 0 } })
end)

T.test("Erlaubtes Schreiben landet an Basis + Offset", function()
  local emu = fake_emu()
  local g = Guard.new({ profile = profile, emu = emu, enabled = true })
  g:set_selftest(true)
  T.ok(g:write("party", 0x8E, 16, 0))
  T.ok(g:write_bytes("party", 10, { 7, 8 }))
  T.eq(emu.writes, { { 16, 1142, 0 }, { 8, 1010, 7 }, { 8, 1011, 8 } })
end)
