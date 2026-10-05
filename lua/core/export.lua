-- Textexporte (Todesprotokoll für Stream-Overlays). Rein; Server und Script nutzen dieselbe Funktion.

local M = require("core.model")
local U = require("core.util")

local X = {}

local CAUSES = { eigener = "gefallen", mitgerissen = "mitgerissen", gebiet_verbraucht = "Gebiet verbraucht", gesperrt = "gesperrt" }

local function clock(t)
  if not t or t == 0 then return "--:--" end
  -- t in ms seit 1970 (UTC). Uhrzeit ohne Datumsbibliothek, damit Server und Script gleich formatieren.
  local s = math.floor(t / 1000)
  local h = math.floor(s / 3600) % 24
  local m = math.floor(s / 60) % 60
  return string.format("%02d:%02d UTC", h, m)
end

--- Todesprotokoll als Text: Kopfzeile mit Versuch und Zählern, dann ein Tod pro Zeile (neueste zuerst).
-- stats: optionale dauerhafte Statistik pro Spieler. limit: maximale Zeilen (Standard 50).
function X.deathlog(state, stats, limit)
  limit = limit or 50
  local lines = {}
  lines[#lines + 1] = "Soul Link – Versuch " .. U.num(state.attempt) .. " – " ..
    ({ lobby = "Lobby", running = "Run läuft", finished = "Run beendet (" .. tostring(state.result) .. ")" })[state.phase]
  local parts = {}
  for _, pid in ipairs(state.order) do
    local p = state.players[pid]
    local s = stats and stats[pid]
    parts[#parts + 1] = p.name .. ": " .. U.num(s and s.deaths or p.deaths) .. " Tode"
      .. (s and s.dragged and s.dragged > 0 and (", " .. U.num(s.dragged) .. " mitgerissen") or "")
      .. (s and s.attempts and (", " .. U.num(s.attempts) .. " Versuche") or "")
  end
  if #parts > 0 then lines[#lines + 1] = table.concat(parts, " | ") end
  if not state.settings.death_log then
    lines[#lines + 1] = "(Todesprotokoll ist in den Einstellungen abgeschaltet)"
    return table.concat(lines, "\n") .. "\n"
  end
  local all = {}
  for _, tid in ipairs(state.team_order) do
    local team = state.teams[tid]
    for _, d in ipairs(team.graveyard) do all[#all + 1] = { d = d, team = team } end
  end
  table.sort(all, function(a, b)
    if a.d.t ~= b.d.t then return a.d.t > b.d.t end
    return a.d.uid > b.d.uid
  end)
  for i = 1, math.min(limit, #all) do
    local d, team = all[i].d, all[i].team
    local who = M.player_name(state, d.player) .. (#state.team_order > 1 and (" [" .. team.name .. "]") or "")
    local where = d.area ~= "" and (" in " .. d.area) or ""
    local by = d.opponent ~= "" and (" gegen " .. d.opponent) or (d.by ~= "" and (" durch " .. d.by) or "")
    lines[#lines + 1] = string.format("%s  %s (%s) Lv.%s%s%s – %s", clock(d.t), d.label, who, U.num(d.level),
      where, by, CAUSES[d.cause] or d.cause)
  end
  if #all == 0 then lines[#lines + 1] = "Noch keine Tode." end
  return table.concat(lines, "\n") .. "\n"
end

return X
