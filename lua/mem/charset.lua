-- Gen-4-Zeichentabelle (Ausschnitt, getestet: nein): Ziffern, Buchstaben, Latin-1-Akzente, Satzzeichen.
-- Quelle: Zeichensatz der Decompilation (pokeplatinum, charmap); im Emulator an Namen prüfen (TESTEN.md).

local C = {}
local CHARS = {}
for i = 0, 9 do CHARS[0x121 + i] = string.char(48 + i) end
for i = 0, 25 do
  CHARS[0x12B + i] = string.char(65 + i)
  CHARS[0x145 + i] = string.char(97 + i)
end
local function utf8(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
  return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end
for i = 0, 63 do CHARS[0x15F + i] = utf8(0xC0 + i) end -- À (0x15F) … ÿ (0x19E)
local PUNCT = {
  [0x19F] = 0x152, [0x1A0] = 0x153, [0x1A9] = 0xA1, [0x1AA] = 0xBF, [0x1AB] = 33, [0x1AC] = 63, [0x1AD] = 44,
  [0x1AE] = 46, [0x1AF] = 0x2026, [0x1B0] = 0xB7, [0x1B1] = 47, [0x1B2] = 0x2018, [0x1B3] = 0x2019,
  [0x1B4] = 0x201C, [0x1B5] = 0x201D, [0x1B6] = 0x201E, [0x1B7] = 0xAB, [0x1B8] = 0xBB, [0x1B9] = 40,
  [0x1BA] = 41, [0x1BB] = 0x2642, [0x1BC] = 0x2640, [0x1BD] = 43, [0x1BE] = 45, [0x1BF] = 42, [0x1C0] = 35,
  [0x1C1] = 61, [0x1C2] = 38, [0x1C3] = 126, [0x1C4] = 58, [0x1C5] = 59, [0x1DE] = 32,
}
for code, cp in pairs(PUNCT) do CHARS[code] = utf8(cp) end
C.GEN4 = CHARS

--- Dekodiert u16-Zeichencodes (Gen 4) bis 0xFFFF.
function C.decode_gen4(codes)
  local out = {}
  for _, c in ipairs(codes) do
    if c == 0xFFFF then break end
    out[#out + 1] = CHARS[c] or "?"
  end
  return table.concat(out)
end

return C
