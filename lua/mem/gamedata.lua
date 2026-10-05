-- Spieldaten zur Laufzeit aus der ROM des Spielers (nichts davon liegt im Projekt):
-- Basiswerte, Typen und Wachstumskurve (Personal-Daten), Entwicklungsreihen (Entwicklungsdaten),
-- Art- und Typnamen (Textarchive). Dateipfade und Textbank-Nummern stehen im Profil (gamedata = {...}).
--
-- Formate (Gen 4, laut Decompilation pokeplatinum; im Emulator zu prüfen, TESTEN.md):
--   Personal-Eintrag (44 Byte): 0–5 Basiswerte, 6/7 Typ 1/2, 0x13 Wachstumskurve, 0x16/0x17 Fähigkeiten
--   Entwicklungs-Eintrag: 7 × (u16 Methode, u16 Parameter, u16 Ziel-Art)
--   Textbank: u16 Anzahl, u16 Startwert; je Eintrag (u32 Offset, u32 Länge) mit Schlüssel
--             (Startwert * 765 * (i+1)) & 0xFFFF, Zeichen u16 mit Schlüssel 596947 * (i+1), +18749 je Zeichen

local bits = require("lib.bits")
local RomFS = require("rando.romfs")

local GD = {}
GD.__index = GD

-- Erfahrung -------------------------------------------------------------------------

--- Erfahrung für ein Level je Wachstumskurve (Gen 4: 0 mittelschnell, 1 unregelmäßig, 2 schwankend,
-- 3 mittellangsam, 4 schnell, 5 langsam).
function GD.exp_for_level(rate, n)
  if n <= 1 then return 0 end
  local n3 = n * n * n
  local v
  if rate == 0 then
    v = n3
  elseif rate == 1 then
    if n <= 50 then v = n3 * (100 - n) / 50
    elseif n <= 68 then v = n3 * (150 - n) / 100
    elseif n <= 98 then v = n3 * math.floor((1911 - 10 * n) / 3) / 500
    else v = n3 * (160 - n) / 100 end
  elseif rate == 2 then
    if n <= 15 then v = n3 * (math.floor((n + 1) / 3) + 24) / 50
    elseif n <= 36 then v = n3 * (n + 14) / 50
    else v = n3 * (math.floor(n / 2) + 32) / 50 end
  elseif rate == 3 then
    v = 6 * n3 / 5 - 15 * n * n + 100 * n - 140
  elseif rate == 4 then
    v = 4 * n3 / 5
  elseif rate == 5 then
    v = 5 * n3 / 4
  else
    error("Unbekannte Wachstumskurve: " .. tostring(rate))
  end
  return math.floor(v + 1e-9)
end

--- Level zu einer Erfahrung.
function GD.level_for_exp(rate, exp)
  local lv = 1
  while lv < 100 and GD.exp_for_level(rate, lv + 1) <= exp do lv = lv + 1 end
  return lv
end

-- Texte -----------------------------------------------------------------------------

local CHARS = require("mem.charset").GEN4
GD.CHARS = CHARS

local function u16(s, off) local a, b = s:byte(off + 1, off + 2) return a + b * 256 end
local function u32(s, off)
  local a, b, c, d = s:byte(off + 1, off + 4)
  return a + b * 256 + c * 65536.0 + d * 16777216.0
end

--- Entschlüsselt eine Textbank. Rückgabe: Liste von Texten (1-basiert: Eintrag 0 -> [1]).
function GD.decode_bank(data)
  local count, seed = u16(data, 0), u16(data, 2)
  local out = {}
  for i = 0, count - 1 do
    local k = bits.mul32(bits.mul32(seed, 765), i + 1) % 65536
    local key = k * 65537.0 -- k | (k << 16)
    local off = bits.bxor(u32(data, 4 + i * 8), key)
    local len = bits.bxor(u32(data, 8 + i * 8), key)
    local ckey = bits.mul32(596947, i + 1) % 65536
    local chars = {}
    for j = 0, len - 1 do
      local c = bits.bxor(u16(data, off + j * 2), ckey)
      ckey = (ckey + 18749) % 65536
      if c == 0xFFFF then break end
      if c == 0xE000 then chars[#chars + 1] = "\n"
      elseif c < 0xF000 then chars[#chars + 1] = CHARS[c] or "?" end
    end
    out[#out + 1] = table.concat(chars)
  end
  return out
end

--- Gegenstück zum Entschlüsseln (für Tests und eigene Werkzeuge). strings: Liste von Zeichencode-Listen.
function GD.encode_bank(code_lists, seed)
  seed = seed or 0x1234
  local header = { string.char(#code_lists % 256, math.floor(#code_lists / 256), seed % 256, math.floor(seed / 256)) }
  local table_parts, body = {}, {}
  local pos = 4 + 8 * #code_lists
  local function le32(v) return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256) end
  for i, codes in ipairs(code_lists) do
    local idx = i - 1
    local len = #codes + 1
    local k = bits.mul32(bits.mul32(seed, 765), idx + 1) % 65536
    local key = k * 65537.0
    table_parts[#table_parts + 1] = le32(bits.bxor(pos, key)) .. le32(bits.bxor(len, key))
    local ckey = bits.mul32(596947, idx + 1) % 65536
    local chars = {}
    for j = 1, len do
      local c = codes[j] or 0xFFFF
      local e = bits.bxor(c, ckey)
      chars[#chars + 1] = string.char(e % 256, math.floor(e / 256))
      ckey = (ckey + 18749) % 65536
    end
    body[#body + 1] = table.concat(chars)
    pos = pos + len * 2
  end
  return table.concat(header) .. table.concat(table_parts) .. table.concat(body)
end

--- Text in Gen-4-Zeichencodes (Gegenstück zu CHARS; für Tests).
function GD.encode_text(text)
  local rev = {}
  for code, ch in pairs(CHARS) do rev[ch] = code end
  local out = {}
  local i = 1
  while i <= #text do
    local found
    for len = 3, 1, -1 do
      local ch = text:sub(i, i + len - 1)
      if rev[ch] then found = ch break end
    end
    if not found then error("Zeichen nicht in der Tabelle: " .. text:sub(i, i)) end
    out[#out + 1] = rev[found]
    i = i + #found
  end
  return out
end

-- Laden ------------------------------------------------------------------------------

--- Lädt die Spieldaten. cfg: profile.gamedata. Rückgabe: Objekt oder nil, Fehlertext.
function GD.load(rom, cfg, gen)
  if not rom then return nil, "keine ROM (rom_path in config.lua)" end
  if not cfg then return nil, "Profil hat keine gamedata-Angaben" end
  local self = setmetatable({ personal = {}, evo = {}, names = {}, type_names = {}, families = {}, gen = gen or 4 }, GD)
  local function narc(path)
    local data, err = rom:file(path or "")
    if not data then return nil, err end
    return RomFS.narc(data)
  end
  local personal, err = narc(cfg.personal_narc)
  if not personal then return nil, "Personal-Daten: " .. tostring(err) end
  for i, entry in ipairs(personal) do
    if #entry >= 0x18 then
      self.personal[i - 1] = {
        base = { entry:byte(1, 6) }, type1 = entry:byte(7), type2 = entry:byte(8),
        growth = entry:byte(0x14), abilities = { entry:byte(0x17), entry:byte(0x18) },
      }
    end
  end
  local evo = narc(cfg.evo_narc)
  if evo then
    for i, entry in ipairs(evo) do
      local targets = {}
      for k = 0, 6 do
        if #entry >= k * 6 + 6 then
          local method, target = u16(entry, k * 6), u16(entry, k * 6 + 4)
          if method ~= 0 and target ~= 0 then targets[#targets + 1] = target end
        end
      end
      self.evo[i - 1] = targets
    end
    self:build_families()
  end
  if cfg.msg_narc and cfg.texts then
    local banks = narc(cfg.msg_narc)
    if banks then
      local function bank(n) return n and banks[n + 1] and GD.decode_bank(banks[n + 1]) or nil end
      local sp = bank(cfg.texts.species)
      if sp then for i, name in ipairs(sp) do self.names[i - 1] = name end end
      local ty = bank(cfg.texts.types)
      if ty then for i, name in ipairs(ty) do self.type_names[i - 1] = name end end
    end
  end
  return self
end

--- Entwicklungsreihen: alle Arten, die über Entwicklungen verbunden sind, bekommen dieselbe Kennung
-- (die kleinste Art-Nummer der Reihe).
function GD:build_families()
  local parent = {}
  local function find(x)
    while parent[x] and parent[x] ~= x do x = parent[x] end
    return x
  end
  local function union(a, b)
    local ra, rb = find(a), find(b)
    parent[ra] = parent[ra] or ra
    parent[rb] = parent[rb] or rb
    if ra < rb then parent[rb] = ra else parent[ra] = rb end
  end
  for sp, targets in pairs(self.evo) do
    parent[sp] = parent[sp] or sp
    for _, t in ipairs(targets) do union(sp, t) end
  end
  for sp in pairs(parent) do self.families[sp] = find(sp) end
end

function GD:family(species) return self.families[species] or species end
function GD:species_name(species) return self.names[species] end
function GD:growth(species) return self.personal[species] and self.personal[species].growth end

--- Typnamen einer Art (ein oder zwei).
function GD:types(species)
  local p = self.personal[species]
  if not p then return nil end
  local function name(t) return self.type_names[t] or ("Typ " .. tostring(t)) end
  if p.type1 == p.type2 then return { name(p.type1) } end
  return { name(p.type1), name(p.type2) }
end

--- Erfahrungsgrenze für ein Level-Cap (Erfahrung genau am Cap-Level).
function GD:cap_exp(species, cap)
  local rate = self:growth(species)
  if not rate then return nil end
  return GD.exp_for_level(rate, cap)
end

return GD
