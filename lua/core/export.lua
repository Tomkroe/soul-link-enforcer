-- Textexporte (Todesprotokoll für Stream-Overlays). Rein; Server und Script nutzen dieselbe Funktion.

local M = require("core.model")
local U = require("core.util")

local X = {}

local CAUSES = { eigener = "gefallen", mitgerissen = "mitgerissen", gebiet_verbraucht = "Gebiet verbraucht", gesperrt = "gesperrt" }

-- Kalenderdatum aus Tagen seit 1970 (proleptischer Gregorianischer Kalender, Algorithmus von H. Hinnant).
local function civil(days)
  local z = days + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local d = doy - math.floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  return yoe + era * 400 + (m <= 2 and 1 or 0), m, d
end
X.civil = civil

--- Zeitstempel (ms seit 1970, UTC) als "TT.MM. hh:mm UTC" – ohne Datumsbibliothek, damit Server und Script
-- gleich formatieren.
local function clock(t)
  if not t or t == 0 then return "--.--. --:--" end
  local s = math.floor(t / 1000)
  local _, mo, d = civil(math.floor(s / 86400))
  return string.format("%02d.%02d. %02d:%02d UTC", d, mo, math.floor(s / 3600) % 24, math.floor(s / 60) % 60)
end
X.clock = clock

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

--- Todesprotokoll über alle Versuche (aus der dauerhaften Bilanz, neueste zuerst).
function X.deathlog_all(ledger_view, limit)
  limit = limit or 100
  local lines = { "Soul Link – Todesprotokoll über alle Versuche" }
  local log = (ledger_view and ledger_view.deathlog) or {}
  for i = 1, math.min(limit, #log) do
    local d = log[i]
    local where = (d.area or "") ~= "" and (" in " .. d.area) or ""
    local by = (d.opponent or "") ~= "" and (" gegen " .. d.opponent) or (((d.by or "") ~= "") and (" durch " .. d.by) or "")
    lines[#lines + 1] = string.format("%s  Versuch %s  %s (%s) Lv.%s%s%s – %s", clock(d.t), U.num(d.attempt or 0),
      d.label or "?", d.player_name or d.player or "?", U.num(d.level or 0), where, by, CAUSES[d.cause] or tostring(d.cause))
  end
  if #log == 0 then lines[#lines + 1] = "Noch keine Tode." end
  return table.concat(lines, "\n") .. "\n"
end

return X
