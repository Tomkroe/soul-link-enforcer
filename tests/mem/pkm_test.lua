-- PK4/PK5-Format mit synthetischen Datensätzen.
local T = require("lib.t")
local P = require("mem.pkm")

-- Baut einen entschlüsselten Datensatz mit bekannten Feldern (logische Reihenfolge A,B,C,D).
local function make(opts)
  local size = opts.party and P.PARTY_SIZE[opts.gen or 4] or P.BOX_SIZE
  local b = {}
  for i = 1, size do b[i] = 0 end
  P.set_u32(b, 0x00, opts.pid)
  P.set_u16(b, 0x08, opts.species or 387)
  P.set_u16(b, 0x0C, opts.tid or 12345)
  P.set_u16(b, 0x0E, opts.sid or 54321)
  P.set_u32(b, 0x10, opts.exp or 1000)
  -- Füllmuster in allen Blöcken, damit falsches Umsortieren auffällt
  for off = 0x18, 0x27 do b[off + 1] = (off * 7) % 256 end         -- Block A
  for off = 0x28, 0x37 do b[off + 1] = (off * 11) % 256 end        -- Block B (Attacken)
  for off = 0x60, 0x67 do b[off + 1] = (off * 13) % 256 end        -- Block C
  for off = 0x68, 0x87 do b[off + 1] = (off * 17) % 256 end        -- Block D
  -- Spitzname "Ben" (Gen 5: UTF-16; Gen 4: eigene Tabelle)
  local name = opts.gen == 5 and { 66, 101, 110, 0xFFFF } or { 0x12C, 0x149, 0x152, 0xFFFF }
  for i, c in ipairs(name) do P.set_u16(b, 0x48 + (i - 1) * 2, c) end
  if opts.party then
    P.set_u16(b, 0x8C, opts.level or 17) -- Level (u8) + Kapselindex
    P.set_u16(b, 0x8E, opts.hp or 40)
    P.set_u16(b, 0x90, opts.max_hp or 52)
  end
  P.set_u16(b, 0x06, P.checksum(b))
  return b
end

local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

T.test("Blockreihenfolgen: 24 verschiedene Permutationen", function()
  local seen = {}
  for sv = 0, 23 do
    local pos = P.POSITION[sv]
    local used = {}
    for block = 1, 4 do
      T.ok(pos[block] >= 0 and pos[block] <= 3)
      T.no(used[pos[block]], "Position doppelt bei " .. sv)
      used[pos[block]] = true
    end
    local key = pos[1] .. pos[2] .. pos[3] .. pos[4]
    T.no(seen[key], "Permutation doppelt")
    seen[key] = true
  end
  -- Stichprobe gegen die veröffentlichte Tabelle: sv 3 = ACDB -> B liegt an Position 3
  T.eq(P.POSITION[3][2], 3)
  T.eq(P.POSITION[23][1], 3)
end)

T.test("Verschiebungswert aus der PID", function()
  T.eq(P.shift_value(0), 0)
  T.eq(P.shift_value(8192 * 5), 5)
  T.eq(P.shift_value(8192 * 30), 6)   -- 30 % 24
  T.eq(P.shift_value(8192 * 33), 1)   -- nur 5 Bit: 33 & 31 = 1
end)

T.test("LCRNG: bekannte Folge", function()
  T.eq(P.next_seed(0), 24691)
  T.eq(P.next_seed(1), 1103539936)
end)

T.test("Rundreise verschlüsseln/entschlüsseln für alle 24 Reihenfolgen (Box)", function()
  for sv = 0, 23 do
    local pid = sv * 8192 + 4321
    local plain = make({ pid = pid })
    local raw = P.encrypt(plain)
    T.no(same(raw, plain), "verschlüsselt muss anders aussehen (sv " .. sv .. ")")
    local back = P.decrypt(raw)
    T.ok(same(back, plain), "Rundreise sv " .. sv)
    T.ok(P.valid(back))
  end
end)

T.test("Rundreise Team-Datensatz Gen 4 und Gen 5 inkl. Kampfwerte", function()
  for _, gen in ipairs({ 4, 5 }) do
    local plain = make({ pid = 3735928559, party = true, gen = gen }) -- PID über 2^31
    local raw = P.encrypt(plain)
    T.eq(#raw, P.PARTY_SIZE[gen])
    T.no(raw[0x8E + 1] == plain[0x8E + 1] and raw[0x8F + 1] == plain[0x8F + 1] and raw[0x91 + 1] == plain[0x91 + 1],
      "Kampfwerte verschlüsselt")
    T.ok(same(P.decrypt(raw), plain))
  end
end)

T.test("Felder lesen", function()
  local plain = make({ pid = 2882400001, species = 393, tid = 1000, sid = 2000, exp = 125000, party = true, gen = 5 })
  local m = P.parse(P.decrypt(P.encrypt(plain)), 5)
  T.eq(m.species, 393)
  T.eq(m.tid, 1000)
  T.eq(m.sid, 2000)
  T.eq(m.exp, 125000)
  T.eq(m.level, 17)
  T.eq(m.hp, 40)
  T.eq(m.max_hp, 52)
  T.eq(m.nickname, "Ben")
  T.eq(m.uid, "ABCDEF01-03E807D0")
  T.ok(m.valid)
  T.eq(P.parse(make({ pid = 1, gen = 4 }), 4).nickname, "Ben")
end)

T.test("Schillernd-Formel", function()
  -- tid ^ sid ^ pid_hi ^ pid_lo < 8
  local plain = make({ pid = 0x1234 * 65536 + 0x1234, tid = 7, sid = 0 })
  T.ok(P.parse(plain, 4).shiny)
  plain = make({ pid = 0x1234 * 65536 + 0x1234, tid = 8, sid = 0 })
  T.no(P.parse(plain, 4).shiny)
end)

T.test("Beschädigte Daten werden erkannt", function()
  local raw = P.encrypt(make({ pid = 99 }))
  raw[0x20] = (raw[0x20] + 1) % 256
  T.no(P.decrypt(raw) and P.valid(P.decrypt(raw)))
end)

T.test("KP schreiben: Prüfsumme bleibt gültig, Grenzen eingehalten", function()
  local plain = make({ pid = 77777, party = true })
  local dead = P.set_hp(plain, 0)
  T.eq(P.u16(dead, 0x8E), 0)
  local raw = P.encrypt(dead)
  local back = P.parse(P.decrypt(raw), 4)
  T.eq(back.hp, 0)
  T.ok(back.valid)
  T.eq(P.u16(P.set_hp(plain, 999), 0x8E), 52, "nicht über Max-KP")
  T.raises(function() P.set_hp(make({ pid = 1 }), 0) end, "Team")
end)

T.test("Erfahrung deckeln", function()
  local plain = make({ pid = 5, exp = 50000 })
  T.eq(P.u32(P.cap_exp(plain, 30000), 0x10), 30000)
  T.eq(P.u32(P.cap_exp(plain, 90000), 0x10), 50000)
  T.ok(P.valid(P.decrypt(P.encrypt(P.cap_exp(plain, 30000)))))
end)

T.test("Hex-Ausgabe ohne Überlauf", function()
  T.eq(P.hex(0, 4), "0000")
  T.eq(P.hex(4294967295, 8), "FFFFFFFF")
  T.eq(P.hex(48879), "BEEF")
end)
