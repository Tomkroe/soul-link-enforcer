-- Baut synthetische NDS-ROM-Abbilder und NARC-Archive für Tests (keine echten Spieldaten).
local F = {}

function F.le16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
function F.le32(v)
  return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end

--- NARC aus einer Liste von Texten.
function F.narc(files)
  local fat, data = {}, {}
  local pos = 0
  for _, f in ipairs(files) do
    fat[#fat + 1] = F.le32(pos) .. F.le32(pos + #f)
    data[#data + 1] = f
    pos = pos + #f
  end
  local btaf = "BTAF" .. F.le32(12 + 8 * #files) .. F.le16(#files) .. F.le16(0) .. table.concat(fat)
  local btnf = "BTNF" .. F.le32(16) .. F.le32(4) .. F.le16(0) .. F.le16(1)
  local gmif = "GMIF" .. F.le32(8 + pos) .. table.concat(data)
  local body = btaf .. btnf .. gmif
  return "NARC" .. F.le16(0xFFFE) .. F.le16(0x0100) .. F.le32(16 + #body) .. F.le16(16) .. F.le16(3) .. body
end

--- NDS-Abbild mit: a.bin (Datei 0), fielddata/encountdata/<narc_name> (Datei 1).
function F.rom(narc_name, narc_data, game_code)
  -- FNT: Haupttabelle (3 Ordner à 8 Byte), dann Untertabellen
  local root_sub = string.char(5) .. "a.bin" .. string.char(0x80 + 9) .. "fielddata" .. F.le16(0xF001) .. string.char(0)
  local dir1_sub = string.char(0x80 + 11) .. "encountdata" .. F.le16(0xF002) .. string.char(0)
  local dir2_sub = string.char(#narc_name) .. narc_name .. string.char(0)
  local main_size = 3 * 8
  local o0 = main_size
  local o1 = o0 + #root_sub
  local o2 = o1 + #dir1_sub
  local fnt = F.le32(o0) .. F.le16(0) .. F.le16(3)
    .. F.le32(o1) .. F.le16(1) .. F.le16(0xF000)
    .. F.le32(o2) .. F.le16(1) .. F.le16(0xF001)
    .. root_sub .. dir1_sub .. dir2_sub
  local header_size = 0x200
  local fnt_off = header_size
  local fat_off = fnt_off + #fnt
  local fat_size = 16
  local data_off = fat_off + fat_size
  local file0 = "HALLO"
  local f0s, f0e = data_off, data_off + #file0
  local f1s, f1e = f0e, f0e + #narc_data
  local fat = F.le32(f0s) .. F.le32(f0e) .. F.le32(f1s) .. F.le32(f1e)
  local header = string.rep("\0", 0x0C) .. (game_code or "TEST") .. string.rep("\0", 0x40 - 0x10)
    .. F.le32(fnt_off) .. F.le32(#fnt) .. F.le32(fat_off) .. F.le32(fat_size)
  header = header .. string.rep("\0", header_size - #header)
  return header .. fnt .. fat .. file0 .. narc_data
end

--- Lesefunktion über einen Text (wie RomFS erwartet).
function F.reader(s)
  return function(offset, length) return s:sub(offset + 1, offset + length) end
end

--- Begegnungstabelle im Platin-Layout (0x1A8 Byte) mit Grasarten und Surfarten.
function F.enc_table(grass, surf)
  local b = {}
  for i = 1, 0x1A8 do b[i] = 0 end
  local function put32(off, v)
    b[off + 1] = v % 256
    b[off + 2] = math.floor(v / 256) % 256
  end
  put32(0, 20) -- Rate
  for i, sp in ipairs(grass or {}) do
    put32(0x04 + (i - 1) * 8, 3)       -- Level
    put32(0x08 + (i - 1) * 8, sp)      -- Art
  end
  put32(0xCC, 10)
  for i, sp in ipairs(surf or {}) do put32(0xD4 + (i - 1) * 8, sp) end
  local chars = {}
  for i = 1, #b do chars[i] = string.char(b[i]) end
  return table.concat(chars)
end


--- NDS-Abbild mit beliebigen Dateien: files = { ["pfad/zur/datei"] = inhalt, ... }
function F.rom_files(files, game_code)
  -- Ordnerbaum aufbauen
  local root = { dirs = {}, files = {}, order = {} }
  local paths = {}
  for p in pairs(files) do paths[#paths + 1] = p end
  table.sort(paths)
  for _, p in ipairs(paths) do
    local node = root
    local parts = {}
    for part in p:gmatch("[^/]+") do parts[#parts + 1] = part end
    for i = 1, #parts - 1 do
      if not node.dirs[parts[i]] then
        node.dirs[parts[i]] = { dirs = {}, files = {}, order = {} }
        node.order[#node.order + 1] = { dir = parts[i] }
      end
      node = node.dirs[parts[i]]
    end
    node.files[#node.files + 1] = { name = parts[#parts], data = files[p] }
  end
  -- Ordner nummerieren (Breitensuche), Dateien in Ordnerreihenfolge nummerieren
  local dirs, queue = {}, { root }
  while #queue > 0 do
    local d = table.remove(queue, 1)
    dirs[#dirs + 1] = d
    d.id = #dirs - 1
    for _, o in ipairs(d.order) do queue[#queue + 1] = d.dirs[o.dir] end
  end
  local file_list = {}
  for _, d in ipairs(dirs) do
    d.first_file = #file_list
    for _, f in ipairs(d.files) do file_list[#file_list + 1] = f end
  end
  local subs = {}
  for _, d in ipairs(dirs) do
    local parts = {}
    for _, f in ipairs(d.files) do parts[#parts + 1] = string.char(#f.name) .. f.name end
    for _, o in ipairs(d.order) do
      parts[#parts + 1] = string.char(0x80 + #o.dir) .. o.dir .. F.le16(0xF000 + d.dirs[o.dir].id)
    end
    parts[#parts + 1] = string.char(0)
    subs[#subs + 1] = table.concat(parts)
  end
  local main, pos = {}, #dirs * 8
  for i, d in ipairs(dirs) do
    main[#main + 1] = F.le32(pos) .. F.le16(d.first_file) .. F.le16(i == 1 and #dirs or 0xF000)
    pos = pos + #subs[i]
  end
  local fnt = table.concat(main) .. table.concat(subs)
  local header_size = 0x200
  local fnt_off = header_size
  local fat_off = fnt_off + #fnt
  local data_off = fat_off + 8 * #file_list
  local fat, data = {}, {}
  local p = data_off
  for _, f in ipairs(file_list) do
    fat[#fat + 1] = F.le32(p) .. F.le32(p + #f.data)
    data[#data + 1] = f.data
    p = p + #f.data
  end
  local header = string.rep("\0", 0x0C) .. (game_code or "TEST") .. string.rep("\0", 0x40 - 0x10)
    .. F.le32(fnt_off) .. F.le32(#fnt) .. F.le32(fat_off) .. F.le32(8 * #file_list)
  header = header .. string.rep("\0", header_size - #header)
  return header .. fnt .. table.concat(fat) .. table.concat(data)
end

return F
