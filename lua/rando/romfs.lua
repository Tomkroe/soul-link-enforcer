-- Liest Dateien aus dem NDS-ROM-Abbild des Spielers (eigene Spielkopie, Pfad in config.lua).
-- Unterstützt das NDS-Dateisystem (FNT/FAT) und NARC-Archive. Nur lesen, nichts wird kopiert oder
-- gespeichert. Der Zugriff läuft über eine Funktion read(offset, length) -> Text, damit große ROMs
-- nicht komplett in den Speicher müssen.

local RomFS = {}
RomFS.__index = RomFS

local function u16(s, off) local a, b = s:byte(off + 1, off + 2) return a + b * 256 end
local function u32(s, off)
  local a, b, c, d = s:byte(off + 1, off + 4)
  return a + b * 256 + c * 65536.0 + d * 16777216.0
end
RomFS.u16, RomFS.u32 = u16, u32

--- read: Funktion (offset, length) -> Text (Bytes ab offset, 0-basiert)
function RomFS.new(read)
  local self = setmetatable({ read = read }, RomFS)
  local header = read(0, 0x60)
  if not header or #header < 0x60 then error("ROM-Kopf nicht lesbar") end
  self.game_code = header:sub(0x0C + 1, 0x0C + 4)
  self.fnt_off, self.fnt_size = u32(header, 0x40), u32(header, 0x44)
  self.fat_off, self.fat_size = u32(header, 0x48), u32(header, 0x4C)
  self.fnt = read(self.fnt_off, self.fnt_size)
  self.fat = read(self.fat_off, self.fat_size)
  self.paths = nil
  return self
end

--- Öffnet eine ROM-Datei über io (nur natives Lua / DeSmuME).
function RomFS.open_file(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, "ROM nicht lesbar: " .. tostring(err) end
  local read = function(offset, length)
    f:seek("set", offset)
    return f:read(length)
  end
  return RomFS.new(read)
end

--- Alle Dateipfade -> Datei-Nummer.
function RomFS:list()
  if self.paths then return self.paths end
  local paths = {}
  local fnt = self.fnt
  local function walk(dir_index, prefix, depth)
    if depth > 32 then return end
    local entry = dir_index * 8
    local sub = u32(fnt, entry)
    local file_id = u16(fnt, entry + 4)
    local pos = sub
    while pos < #fnt do
      local t = fnt:byte(pos + 1)
      if t == 0 then break end
      local len = t % 128
      local name = fnt:sub(pos + 2, pos + 1 + len)
      pos = pos + 1 + len
      if t >= 128 then
        local id = u16(fnt, pos) - 0xF000
        pos = pos + 2
        walk(id, prefix .. name .. "/", depth + 1)
      else
        paths[prefix .. name] = file_id
        file_id = file_id + 1
      end
    end
  end
  walk(0, "", 0)
  self.paths = paths
  return paths
end

--- Inhalt einer Datei nach Pfad (z. B. "fielddata/encountdata/pl_enc_data.narc").
function RomFS:file(path)
  local id = self:list()[path]
  if not id then return nil, "Datei nicht im ROM: " .. path end
  local start, stop = u32(self.fat, id * 8), u32(self.fat, id * 8 + 4)
  return self.read(start, stop - start)
end

-- NARC ---------------------------------------------------------------------------

--- Zerlegt ein NARC-Archiv. Rückgabe: Liste von Texten (Unterdateien, 1-basiert).
function RomFS.narc(data)
  if not data or data:sub(1, 4) ~= "NARC" then return nil, "kein NARC-Archiv" end
  local pos = u16(data, 0x0C) -- Kopfgröße (0x10)
  local fat_pos, count, entries
  local gmif_data
  while pos < #data do
    local magic = data:sub(pos + 1, pos + 4)
    local size = u32(data, pos + 4)
    if magic == "BTAF" then
      count = u16(data, pos + 8)
      fat_pos = pos + 12
    elseif magic == "GMIF" then
      gmif_data = pos + 8
    end
    if size < 8 then break end
    pos = pos + size
  end
  if not fat_pos or not gmif_data then return nil, "NARC ohne BTAF/GMIF" end
  entries = {}
  for i = 0, count - 1 do
    local s, e = u32(data, fat_pos + i * 8), u32(data, fat_pos + i * 8 + 4)
    entries[#entries + 1] = data:sub(gmif_data + s + 1, gmif_data + e)
  end
  return entries
end

--- Text in Byte-Liste.
function RomFS.bytes(s)
  local out = {}
  for i = 1, #s do out[i] = s:byte(i) end
  return out
end

return RomFS
