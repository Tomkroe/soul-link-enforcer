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
add("Game-Code lesen (0x027FFE0C)", okc and code ~= nil, tostring(code))
local Profiles = require("profiles")
local profile, msg = Profiles.load(okc and code or nil)
add("Profil", profile ~= nil, msg)

-- Selbsttest der Schreibfunktionen (rein rechnerisch, ohne Spielspeicher)
local App = require("app")
add("Selbsttest PK4/PK5", App.selftest())

local frames = 0
gui.register(function()
  frames = frames + 1
  for i, r in ipairs(results) do
    gui.text(2, 2 + (i - 1) * 9, (r.ok and "OK  " or "--  ") .. r.name .. " " .. r.detail, r.ok and "green" or "yellow")
  end
  gui.text(2, 2 + #results * 9, "Frames: " .. frames, "white")
end)
