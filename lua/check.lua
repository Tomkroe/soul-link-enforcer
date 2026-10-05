-- Machbarkeitsprüfung (Phase 0) für heute Abend: in DeSmuME laden und die Ausgabe ansehen.
-- Prüft: Lua-Version, Bibliotheken (io/os/LuaSocket), Dateiaustausch, Game-Code, Speicherlesen.
-- Schreibt NICHTS in den Spielspeicher.

local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then src = src:sub(2) end
  return (src:match("^(.*)[/\\][^/\\]*$") or "."):gsub("\\", "/")
end
local LUA_DIR = script_dir()
local ROOT = LUA_DIR .. "/.."
package.path = LUA_DIR .. "/?.lua;" .. LUA_DIR .. "/?/init.lua;" .. package.path

local results = {}
local function add(name, ok, detail)
  results[#results + 1] = { name = name, ok = ok, detail = detail or "" }
  print((ok and "[OK]   " or "[FEHLT] ") .. name .. (detail and detail ~= "" and (" – " .. detail) or ""))
end

add("Lua-Version", true, _VERSION)
add("io.open", io and io.open ~= nil)
add("os.rename/os.remove", os and os.rename ~= nil and os.remove ~= nil)
add("os.execute", os and os.execute ~= nil)
add("bit-Bibliothek (optional)", bit ~= nil, bit and "vorhanden" or "nicht nötig, rein arithmetisch")
local has_socket, socket = pcall(require, "socket")
add("LuaSocket (optional)", has_socket, has_socket and tostring(socket._VERSION) or "nicht nötig, Datei-Brücke wird genutzt")

-- Dateiaustausch im Projektordner
local FS = require("net.fs")
local test_path = ROOT .. "/bridge/check_test.json"
local ok_w = FS.write_atomic(test_path, "{\"ok\":true}")
local ok_r = FS.read(test_path) == "{\"ok\":true}"
local ok_w2 = FS.write_atomic(test_path, "{\"ok\":2}")
FS.remove(test_path)
add("Datei schreiben/umbenennen", ok_w and ok_r and ok_w2, test_path)

-- Speicher und Game-Code
local Emu = require("mem.emu")
local adapter = Emu.desmume()
local okc, code = pcall(adapter.game_code)
add("Game-Code lesen (0x023FFE0C)", okc and code ~= nil, tostring(code))
local Profiles = require("profiles")
local profile, msg = Profiles.load(okc and code or nil)
add("Profil", profile ~= nil, msg)

-- Selbsttest der Schreibfunktionen (rein rechnerisch, ohne Spielspeicher)
local App = require("app")
add("Selbsttest PK4/PK5", App.selftest())

-- Adress-Suche (nur lesen): Team über Kandidaten oder Signatur finden, Profilwerte live anzeigen.
-- Ergebnis zusätzlich in local/adressen_<CODE>.txt (zum Weitergeben).
local Reader = require("mem.reader")
local Finder = require("mem.finder")
local P = require("mem.pkm")
local reader = profile and Reader.new({ profile = profile, emu = adapter }) or nil
local search = { done = false, pointers = nil, ptr_pos = nil, written = false }

local function hex(n) return n and ("0x" .. P.hex(n, 8)) or "–" end

local function write_report(d)
  local lines = {
    "Soul-Link check.lua – Adress-Suche " .. os.date("%Y-%m-%d %H:%M"),
    "Game-Code: " .. tostring(code),
    "Team-Adresse: " .. hex(d.party_addr) .. " (" .. tostring(d.party_source) .. ")",
    "Anzahl im Team: " .. tostring(d.party_count),
  }
  for i, m in ipairs(d.party or {}) do
    lines[#lines + 1] = string.format("  %d: Art %d, Lv. %d, KP %d/%d, Kennung %s", i, m.species, m.level, m.hp, m.max_hp, m.uid)
  end
  for _, name in ipairs({ "badges", "area_id", "bag_balls", "battle_flag", "battle_type" }) do
    lines[#lines + 1] = name .. ": " .. tostring(d[name])
  end
  lines[#lines + 1] = rando_info
  for _, h in ipairs(search.pointers or {}) do
    lines[#lines + 1] = string.format("Zeiger auf Team-Basis: [%s] + 0x%s", hex(h.ptr), P.hex(h.offset))
  end
  FS.write_atomic(ROOT .. "/local/adressen_" .. tostring(code) .. ".txt", table.concat(lines, "\n") .. "\n")
end

-- Randomizer: geladene Begegnungstabelle über die ROM-Dateien suchen (braucht rom_path in config.lua)
local rando_scan, rando_info = nil, "Randomizer: rom_path in config.lua fehlt – Tabellensuche übersprungen"
do
  local ok_cfg, cfg = pcall(dofile, ROOT .. "/config.lua")
  if ok_cfg and type(cfg) == "table" and cfg.rom_path and cfg.rom_path ~= "" and profile and profile.randomizer then
    local RomFS = require("rando.romfs")
    local rom, err = RomFS.open_file(cfg.rom_path)
    if not rom then
      rando_info = "Randomizer: " .. tostring(err)
    else
      local data, ferr = rom:file(profile.randomizer.encounter_narc)
      local files = data and RomFS.narc(data)
      if not files then
        rando_info = "Randomizer: " .. tostring(ferr or "NARC unlesbar") .. " (" .. tostring(profile.randomizer.encounter_narc) .. ")"
      else
        add("ROM gelesen", rom.game_code == code, "Game-Code im ROM " .. tostring(rom.game_code) .. ", " .. #files .. " Begegnungstabellen")
        rando_scan = Finder.block_scanner(adapter, files)
        rando_info = "Suche Begegnungstabelle ..."
      end
    end
  end
end

local frames = 0
gui.register(function()
  frames = frames + 1
  local y = 2
  for _, r in ipairs(results) do
    gui.text(2, y, (r.ok and "OK  " or "--  ") .. r.name .. " " .. r.detail, r.ok and "green" or "yellow")
    y = y + 9
  end
  gui.text(2, y, "Frames: " .. frames, "white")
  y = y + 9
  if rando_scan then
    rando_scan:step(0x40000)
    if #rando_scan.found > 0 then
      local f = rando_scan.found[1]
      rando_info = "Begegnungstabelle: " .. hex(f.addr) .. " (ROM-Datei " .. (f.index - 1) .. ")"
      rando_scan = nil
    elseif rando_scan.done then
      rando_info = "Begegnungstabelle nicht im Speicher gefunden (andere Karte betreten und neu starten)"
      rando_scan = nil
    end
  end
  gui.text(2, y, rando_info, "gray")
  y = y + 9
  if not reader then return end

  local ok, d = pcall(reader.diagnose, reader)
  if not ok then
    gui.text(2, y, "Lesefehler: " .. tostring(d), "red")
    return
  end
  if not d.party_addr then
    local where = reader.scan and string.format("%.0f%%", (reader.scan.pos - Finder.RAM_START) / (Finder.RAM_END - Finder.RAM_START) * 100) or "–"
    gui.text(2, y, "Suche Team im Speicher ... " .. where .. " (Spielstand laden, mind. 1 Monster im Team)", "yellow")
    return
  end
  -- Zeiger auf die Team-Basis suchen (für bekannte Offsets), stückweise über mehrere Frames
  if not search.pointers then search.pointers, search.ptr_pos = {}, Finder.RAM_START end
  if search.ptr_pos < Finder.RAM_END then
    local to = math.min(Finder.RAM_END, search.ptr_pos + 0x40000)
    for _, h in ipairs(Finder.find_pointers(adapter, d.party_addr, { 0xB4, 0xD094 }, search.ptr_pos, to)) do
      search.pointers[#search.pointers + 1] = h
    end
    search.ptr_pos = to
  elseif not search.written then
    search.written = true
    write_report(d)
  end
  gui.text(2, y, "Team: " .. hex(d.party_addr) .. " (" .. tostring(d.party_source) .. "), Anzahl " .. tostring(d.party_count), "green")
  y = y + 9
  for i, m in ipairs(d.party or {}) do
    gui.text(2, y, string.format("  %d: Art %d Lv.%d KP %d/%d", i, m.species, m.level, m.hp, m.max_hp), "white")
    y = y + 9
  end
  gui.text(2, y, string.format("Orden-Byte %s  Karte %s  Bälle %s  Kampf %s/%s",
    tostring(d.badges), tostring(d.area_id), tostring(d.bag_balls), tostring(d.battle_flag), tostring(d.battle_type)), "white")
  y = y + 9
  gui.text(2, y, search.written and ("Bericht: local/adressen_" .. tostring(code) .. ".txt") or "Suche Zeiger ...", "gray")
end)
