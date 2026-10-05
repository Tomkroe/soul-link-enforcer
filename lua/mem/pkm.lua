-- Monster-Datensätze der 4. und 5. Generation (PK4/PK5): Entschlüsselung, Prüfsumme,
-- Blockreihenfolge, Felder lesen, KP schreiben. Arbeitet auf Byte-Listen (1-basiert), ohne Emulator.
--
-- Aufbau (Offsets 0-basiert):
--   0x00 PID (u32)   0x06 Prüfsumme (u16)   0x08–0x87 vier Blöcke A–D à 32 Byte (verschlüsselt,
--   Reihenfolge abhängig von der PID)   ab 0x88 Kampfwerte (nur im Team; Gen 4: 100 Byte, Gen 5: 84 Byte,
--   verschlüsselt mit der PID als Startwert).
-- Quelle des Formats: öffentliche Dokumentation (Bulbapedia, Project Pokémon). getestet: nein
-- (im Emulator mit echten Daten prüfen, siehe TESTEN.md).

local bits = require("lib.bits")

local P = {}

P.BOX_SIZE = 136
P.PARTY_SIZE = { [4] = 236, [5] = 220 }

-- Reihenfolge der Blöcke im Speicher für jeden Verschiebungswert 0..23.
local ORDERS = {
  "ABCD", "ABDC", "ACBD", "ACDB", "ADBC", "ADCB",
  "BACD", "BADC", "BCAD", "BCDA", "BDAC", "BDCA",
  "CABD", "CADB", "CBAD", "CBDA", "CDAB", "CDBA",
  "DABC", "DACB", "DBAC", "DBCA", "DCAB", "DCBA",
}

-- position[sv][block] = Position (0..3), an der der logische Block (1=A..4=D) gespeichert ist.
local POSITION = {}
for sv, order in ipairs(ORDERS) do
  local pos = {}
  for i = 1, 4 do
    local block = order:byte(i) - 64 -- A=1 .. D=4
    pos[block] = i - 1
  end
  POSITION[sv - 1] = pos
end

-- Bytes ----------------------------------------------------------------------

function P.u8(b, off) return b[off + 1] end
function P.u16(b, off) return b[off + 1] + b[off + 2] * 256 end
-- Gleitkomma-Faktoren: fengari rechnet Ganzzahlen mit 32 Bit und liefe sonst über.
function P.u32(b, off) return b[off + 1] + b[off + 2] * 256.0 + b[off + 3] * 65536.0 + b[off + 4] * 16777216.0 end

function P.set_u16(b, off, v)
  b[off + 1] = v % 256
  b[off + 2] = math.floor(v / 256) % 256
end

function P.set_u32(b, off, v)
  v = bits.norm(v)
  for i = 0, 3 do
    b[off + 1 + i] = math.floor(v / 256 ^ i) % 256
  end
end

local function copy(b)
  local out = {}
  for i = 1, #b do out[i] = b[i] end
  return out
end

-- 16-Bit-XOR ohne Bit-Bibliothek (schneller als die 32-Bit-Variante).
local function bxor16(a, b)
  local r, place = 0, 1
  for _ = 1, 16 do
    local ra, rb = a % 2, b % 2
    if ra ~= rb then r = r + place end
    a = (a - ra) / 2
    b = (b - rb) / 2
    place = place * 2
  end
  return r
end
P.bxor16 = bxor16

local MULT = 1103515245 -- 0x41C64E6D
local INC = 24691        -- 0x6073

--- LCRNG der 4./5. Generation: liefert den nächsten Zustand.
function P.next_seed(seed)
  return bits.norm(bits.mul32(seed, MULT) + INC)
end

--- XOR-Verschlüsselung (symmetrisch) der Wörter in [from, to) mit Startwert seed.
local function crypt(b, from, to, seed)
  for off = from, to - 1, 2 do
    seed = P.next_seed(seed)
    local key = math.floor(seed / 65536)
    P.set_u16(b, off, bxor16(P.u16(b, off), key))
  end
end

function P.shift_value(pid)
  return math.floor(bits.norm(pid) / 8192) % 32 % 24 -- ((pid & 0x3E000) >> 13) % 24
end

function P.checksum(b)
  local sum = 0
  for off = 0x08, 0x86, 2 do sum = sum + P.u16(b, off) end
  return sum % 65536
end

-- Blöcke umsortieren. to_logical = true: gespeichert -> A,B,C,D; sonst umgekehrt.
local function shuffle(b, pid, to_logical)
  local pos = POSITION[P.shift_value(pid)]
  local out = copy(b)
  for block = 1, 4 do
    local logical = 0x08 + (block - 1) * 32
    local stored = 0x08 + pos[block] * 32
    local src, dst = stored, logical
    if not to_logical then src, dst = logical, stored end
    for i = 0, 31 do out[dst + i + 1] = b[src + i + 1] end
  end
  return out
end

--- Entschlüsselt einen Datensatz aus dem Speicher. Rückgabe: neue Byte-Liste in Reihenfolge A,B,C,D.
function P.decrypt(raw)
  local b = copy(raw)
  local pid = P.u32(b, 0)
  crypt(b, 0x08, 0x88, P.u16(b, 0x06))
  if #b > P.BOX_SIZE then crypt(b, 0x88, #b, pid) end
  return shuffle(b, pid, true)
end

--- Verschlüsselt einen entschlüsselten Datensatz (berechnet die Prüfsumme neu).
function P.encrypt(plain)
  local b = copy(plain)
  local pid = P.u32(b, 0)
  P.set_u16(b, 0x06, P.checksum(b))
  b = shuffle(b, pid, false)
  crypt(b, 0x08, 0x88, P.u16(b, 0x06))
  if #b > P.BOX_SIZE then crypt(b, 0x88, #b, pid) end
  return b
end

--- Prüft, ob die gespeicherte Prüfsumme zum entschlüsselten Inhalt passt.
function P.valid(plain)
  return P.checksum(plain) == P.u16(plain, 0x06)
end

-- Felder -----------------------------------------------------------------------

local function decode_gen5_name(b, off, len)
  local chars = {}
  for i = 0, len - 1 do
    local c = P.u16(b, off + i * 2)
    if c == 0xFFFF or c == 0 then break end
    if c < 0x80 then
      chars[#chars + 1] = string.char(c)
    elseif c < 0x800 then
      chars[#chars + 1] = string.char(0xC0 + math.floor(c / 64), 0x80 + c % 64)
    else
      chars[#chars + 1] = string.char(0xE0 + math.floor(c / 4096), 0x80 + math.floor(c / 64) % 64, 0x80 + c % 64)
    end
  end
  return table.concat(chars)
end

-- Gen 4 nutzt eine eigene Zeichentabelle (mem/charset.lua, getestet: nein).
local function decode_gen4_name(b, off, len)
  local codes = {}
  for i = 0, len - 1 do codes[#codes + 1] = P.u16(b, off + i * 2) end
  return require("mem.charset").decode_gen4(codes)
end

--- Kodiert einen Namen in die Gen-4-Zeichentabelle (mem/charset.lua, auch Umlaute; getestet: nein).
-- Rückgabe: Byte-Liste (u16 je Zeichen, 0xFFFF als Ende, auf slots Zeichen aufgefüllt) oder nil, Fehler.
function P.encode_gen4_name(name, max_len, slots)
  max_len = max_len or 7
  slots = slots or (max_len + 1)
  local rev = {}
  for code, ch in pairs(require("mem.charset").GEN4) do rev[ch] = code end
  local codes = {}
  local i = 1
  while i <= #name do
    local found
    for len = 3, 1, -1 do
      local ch = name:sub(i, i + len - 1)
      if #ch == len and rev[ch] then found = ch break end
    end
    if not found then
      return nil, "Zeichen '" .. name:sub(i, i) .. "' wird nicht unterstützt"
    end
    codes[#codes + 1] = rev[found]
    i = i + #found
  end
  if #codes == 0 then return nil, "leerer Name" end
  if #codes > max_len then return nil, "Name länger als " .. max_len .. " Zeichen" end
  local bytes = {}
  for k = 1, slots do
    local v = codes[k] or 0xFFFF
    bytes[#bytes + 1] = v % 256
    bytes[#bytes + 1] = math.floor(v / 256)
  end
  return bytes
end

--- Liest die wichtigen Felder eines entschlüsselten Datensatzes.
function P.parse(plain, gen)
  local pid = P.u32(plain, 0x00)
  local tid, sid = P.u16(plain, 0x0C), P.u16(plain, 0x0E)
  local iv = P.u32(plain, 0x38)
  local shiny_value = bxor16(bxor16(tid, sid), bxor16(math.floor(pid / 65536), pid % 65536))
  local mon = {
    pid = pid,
    tid = tid,
    sid = sid,
    species = P.u16(plain, 0x08),
    item = P.u16(plain, 0x0A),
    exp = P.u32(plain, 0x10),
    is_egg = bits.extract(iv, 30, 1) == 1,
    nicknamed = bits.extract(iv, 31, 1) == 1,
    shiny = shiny_value < 8,
    ball = P.u8(plain, 0x83),
    nickname = (gen == 5 and decode_gen5_name or decode_gen4_name)(plain, 0x48, 11),
    valid = P.valid(plain),
  }
  mon.uid = P.uid(mon)
  if #plain > P.BOX_SIZE then
    mon.status = P.u8(plain, 0x88)
    mon.level = P.u8(plain, 0x8C)
    mon.hp = P.u16(plain, 0x8E)
    mon.max_hp = P.u16(plain, 0x90)
  end
  return mon
end

--- Hexadezimal ohne string.format("%X") (das scheitert unter fengari und 32-Bit-Windows ab 2^31).
function P.hex(n, width)
  local digits = "0123456789ABCDEF"
  local out = {}
  n = bits.norm(n)
  repeat
    local d = n % 16
    table.insert(out, 1, digits:sub(d + 1, d + 1))
    n = (n - d) / 16
  until n == 0
  local s = table.concat(out)
  return string.rep("0", (width or 0) - #s) .. s
end

--- Eindeutige Kennung über Sitzungen hinweg: PID + Trainer-ID + geheime ID.
function P.uid(mon)
  return P.hex(mon.pid, 8) .. "-" .. P.hex(mon.tid, 4) .. P.hex(mon.sid, 4)
end

--- Setzt die aktuellen KP in einem entschlüsselten Team-Datensatz (nur Kampfwerte, Prüfsumme bleibt).
function P.set_hp(plain, hp)
  if #plain <= P.BOX_SIZE then error("KP gibt es nur in Team-Datensätzen") end
  local max = P.u16(plain, 0x90)
  if hp > max then hp = max end
  if hp < 0 then hp = 0 end
  local out = copy(plain)
  P.set_u16(out, 0x8E, hp)
  return out
end

--- Begrenzt die Erfahrung (Level-Cap). Die Erfahrungsgrenze kommt aus den Spieldaten (Wachstumskurve).
function P.cap_exp(plain, max_exp)
  local out = copy(plain)
  if P.u32(out, 0x10) > max_exp then P.set_u32(out, 0x10, max_exp) end
  return out
end

P.ORDERS = ORDERS
P.POSITION = POSITION

return P
