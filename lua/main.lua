-- Soul-Link-Enforcer – Einstieg für DeSmuME (Lua 5.1).
-- In DeSmuME: Tools > Lua Scripting > New Lua Script Window > Browse > lua/main.lua > Run.
--
-- Diese Datei ist bewusst dünn: Sie verbindet die DeSmuME-API mit der testbaren Logik in lua/app.

local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then src = src:sub(2) end
  return (src:match("^(.*)[/\\][^/\\]*$") or "."):gsub("\\", "/")
end

local LUA_DIR = script_dir()
local ROOT = LUA_DIR .. "/.."
package.path = LUA_DIR .. "/?.lua;" .. LUA_DIR .. "/?/init.lua;" .. package.path

local ok_cfg, config = pcall(dofile, ROOT .. "/config.lua")
if not ok_cfg then
  print("config.lua fehlt oder ist fehlerhaft: " .. tostring(config))
  config = { player_name = "Spieler", lobby_code = "SOUL01", server_url = "ws://localhost:8080/ws", hotkeys = {} }
end

local Emu = require("mem.emu")
local FS = require("net.fs")
local Launcher = require("net.launcher")
local App = require("app")

-- Millisekunden, monoton: Startzeit + vergangene Zeit aus os.clock() (unter Windows Wanduhr seit Start).
local t0_time, t0_clock = os.time(), os.clock()
local function now()
  return t0_time * 1000 + math.floor((os.clock() - t0_clock) * 1000)
end

local app = App.new({
  config = config, emu = Emu.desmume(), fs = FS, root = ROOT, now = now,
  launch = function(opts) return Launcher.start(opts) end,
})

print("Soul-Link-Enforcer gestartet. Game-Code: " .. tostring(app.game_code) .. " – " .. tostring(app.profile_msg))

emu.registerafter(function()
  local ok, err = pcall(app.frame, app)
  if not ok then print("Fehler im Frame: " .. tostring(err)) end
end)

gui.register(function()
  local ok, err = pcall(app.draw, app)
  if not ok then print("Fehler im Overlay: " .. tostring(err)) end
end)
