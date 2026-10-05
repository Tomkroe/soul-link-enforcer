local T = require("lib.t")
local GD = require("mem.gamedata")
local RomFS = require("rando.romfs")
local F = require("rando.romfake")

T.test("Erfahrungskurven: bekannte Werte für Level 100 und kleine Level", function()
  T.eq(GD.exp_for_level(0, 100), 1000000)
  T.eq(GD.exp_for_level(1, 100), 600000)
  T.eq(GD.exp_for_level(2, 100), 1640000)
  T.eq(GD.exp_for_level(3, 100), 1059860)
  T.eq(GD.exp_for_level(4, 100), 800000)
  T.eq(GD.exp_for_level(5, 100), 1250000)
  T.eq(GD.exp_for_level(3, 2), 9)
  T.eq(GD.exp_for_level(0, 5), 125)
  T.eq(GD.exp_for_level(3, 1), 0)
  T.eq(GD.level_for_exp(0, 124), 4)
  T.eq(GD.level_for_exp(0, 125), 5)
  -- streng steigend
  for rate = 0, 5 do
    for lv = 2, 100 do T.ok(GD.exp_for_level(rate, lv) > GD.exp_for_level(rate, lv - 1), rate .. "/" .. lv) end
  end
end)

T.test("Texte: Gen-4-Verschlüsselung und Zeichentabelle (Rundreise)", function()
  local names = { "-----", "Bisasam", "Nidoran♀", "Äpfel Öl Übel ß", "Mr. Mime", "Porygon2" }
  local codes = {}
  for i, n in ipairs(names) do codes[i] = GD.encode_text(n) end
  local bank = GD.encode_bank(codes, 0x5A3C)
  T.eq(GD.decode_bank(bank), names)
  T.eq(GD.encode_text("A")[1], 0x12B)
  T.eq(GD.encode_text("ä")[1], 0x15F + (0xE4 - 0xC0))
end)

local function personal_entry(base, t1, t2, growth)
  local b = {}
  for i = 1, 44 do b[i] = 0 end
  for i, v in ipairs(base) do b[i] = v end
  b[7], b[8], b[0x14] = t1, t2, growth
  local chars = {}
  for i = 1, #b do chars[i] = string.char(b[i]) end
  return table.concat(chars)
end

local function evo_entry(targets)
  local parts = {}
  for k = 1, 7 do
    local t = targets[k]
    parts[#parts + 1] = F.le16(t and 4 or 0) .. F.le16(t and 16 or 0) .. F.le16(t or 0)
  end
  return table.concat(parts) .. F.le16(0)
end

local function fake_rom()
  local personal = { personal_entry({}, 0, 0, 0) }
  personal[2] = personal_entry({ 45, 49, 49, 45, 65, 65 }, 12, 3, 3) -- Art 1: Pflanze/Gift, mittellangsam
  personal[3] = personal_entry({ 60, 62, 63, 60, 80, 80 }, 12, 3, 3)
  personal[4] = personal_entry({ 39, 52, 43, 65, 60, 50 }, 10, 10, 3) -- Art 3: Feuer
  local evo = { evo_entry({}), evo_entry({ 2 }), evo_entry({}), evo_entry({}) }
  local species = { "-----", "Bisasam", "Bisaknosp", "Glumanda" }
  local types = {}
  local type_names = { [0] = "Normal", [3] = "Gift", [10] = "Feuer", [12] = "Pflanze" }
  for i = 0, 17 do types[i + 1] = type_names[i] or ("T" .. i) end
  local function bank(list)
    local codes = {}
    for i, n in ipairs(list) do codes[i] = GD.encode_text(n) end
    return GD.encode_bank(codes)
  end
  local msg = {}
  for i = 1, 6 do msg[i] = bank({ "x" }) end
  msg[5] = bank(species)   -- Bank 4
  msg[6] = bank(types)     -- Bank 5
  local files = {
    ["poketool/personal/pl_personal.narc"] = F.narc(personal),
    ["poketool/personal/evo.narc"] = F.narc(evo),
    ["msgdata/pl_msg.narc"] = F.narc(msg),
  }
  return RomFS.new(F.reader(F.rom_files(files, "CPUD")))
end

local CFG = {
  personal_narc = "poketool/personal/pl_personal.narc", evo_narc = "poketool/personal/evo.narc",
  msg_narc = "msgdata/pl_msg.narc", texts = { species = 4, types = 5 },
}

T.test("Spieldaten aus der ROM: Namen, Typen, Wachstum, Entwicklungsreihen", function()
  local rom = fake_rom()
  T.eq(rom:list()["poketool/personal/evo.narc"] ~= nil, true)
  local gd = assert(GD.load(rom, CFG, 4))
  T.eq(gd:species_name(1), "Bisasam")
  T.eq(gd:species_name(3), "Glumanda")
  T.eq(gd:types(1), { "Pflanze", "Gift" })
  T.eq(gd:types(3), { "Feuer" })
  T.eq(gd:growth(1), 3)
  T.eq(gd:family(2), 1, "Bisaknosp gehört zur Reihe von Bisasam")
  T.eq(gd:family(1), 1)
  T.eq(gd:family(3), 3)
  T.eq(gd:cap_exp(1, 14), GD.exp_for_level(3, 14))
end)

T.test("Spieldaten: fehlende ROM oder Datei -> klare Meldung", function()
  local gd, err = GD.load(nil, CFG)
  T.eq(gd, nil)
  T.ok(err:find("rom_path"))
  local gd2, err2 = GD.load(fake_rom(), { personal_narc = "gibt/es/nicht.narc" })
  T.eq(gd2, nil)
  T.ok(err2:find("Personal"))
end)

return { fake_rom = fake_rom, CFG = CFG }
