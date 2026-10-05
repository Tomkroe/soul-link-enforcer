-- Textexporte (Todesprotokoll für Stream-Overlays). Rein; Server und Script nutzen dieselbe Funktion.

local M = require("core.model")
local U = require("core.util")
local R = require("core.rules")

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
    local st = d.stats and (d.stats.battles or 0) > 0
      and string.format(" [%s Kämpfe, %s K.O.]", U.num(d.stats.battles), U.num(d.stats.kos or 0)) or ""
    lines[#lines + 1] = string.format("%s  %s (%s) Lv.%s%s%s – %s%s", clock(d.t), d.label, who, U.num(d.level),
      where, by, CAUSES[d.cause] or d.cause, st)
  end
  if #all == 0 then lines[#lines + 1] = "Noch keine Tode." end
  return table.concat(lines, "\n") .. "\n"
end

--- Dauer in Text ("2 h 14 min", "45 min", "30 s").
function X.duration(ms)
  local s = math.max(0, math.floor((ms or 0) / 1000))
  if s < 60 then return U.num(s) .. " s" end
  local m = math.floor(s / 60)
  if m < 60 then return U.num(m) .. " min" end
  if m % 60 == 0 then return U.num(math.floor(m / 60)) .. " h" end
  return U.num(math.floor(m / 60)) .. " h " .. U.num(m % 60) .. " min"
end

--- Run-Statistik (Endbildschirm, Discord, Übersicht). Rückgabe: Liste von Zeilen.
function X.summary(state)
  local lines = {}
  local head = "Versuch " .. U.num(state.attempt)
  if state.phase == "finished" then
    head = head .. " – " .. state.result
  end
  if state.started_at > 0 then
    local stop = state.ended_at > 0 and state.ended_at or state.started_at
    head = head .. " nach " .. X.duration(stop - state.started_at)
  end
  lines[#lines + 1] = head
  if #state.team_order > 1 then
    for _, row in ipairs(R.ranking(state)) do
      lines[#lines + 1] = "Platz " .. U.num(row.rank) .. ": " .. row.name .. " (" .. row.status .. ")"
    end
  end
  local badges, deaths, viol = {}, {}, 0
  for _, pid in ipairs(state.order) do
    local p = state.players[pid]
    badges[#badges + 1] = p.name .. " " .. U.num(p.badges)
    deaths[#deaths + 1] = p.name .. " " .. U.num(p.deaths) .. (p.dragged > 0 and (" (+" .. U.num(p.dragged) .. " mitgerissen)") or "")
    viol = viol + (p.violations or 0)
  end
  lines[#lines + 1] = "Orden: " .. table.concat(badges, ", ")
  lines[#lines + 1] = "Tode: " .. table.concat(deaths, ", ")
  local groups, dead, areas, consumed = 0, 0, 0, 0
  for _, tid in ipairs(state.team_order) do
    local team = state.teams[tid]
    groups = groups + #team.group_order
    for _, gid in ipairs(team.group_order) do
      if team.groups[gid].status == "tot" then dead = dead + 1 end
    end
    areas = areas + #team.area_order
    for _, key in ipairs(team.area_order) do
      if team.areas[key].consumed then consumed = consumed + 1 end
    end
  end
  lines[#lines + 1] = "Gruppen: " .. U.num(groups) .. " (" .. U.num(groups - dead) .. " lebend, " .. U.num(dead) .. " tot)"
  lines[#lines + 1] = "Gebiete: " .. U.num(areas) .. " betreten, " .. U.num(consumed) .. " verbraucht"
  if viol > 0 then lines[#lines + 1] = "Regelverstöße: " .. U.num(viol) end
  return lines
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

-- Zeitleiste als SVG ---------------------------------------------------------------

local function xml(s)
  return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local TL_STYLE = {
  fang = { color = "#2e9d5b", name = "Fang" }, tot = { color = "#d64541", name = "Tod" },
  mitgerissen = { color = "#e67e22", name = "mitgerissen" }, orden = { color = "#d4a017", name = "Orden" },
  verbraucht = { color = "#8a94a6", name = "Gebiet verbraucht" }, verstoss = { color = "#8e44ad", name = "Regelverstoß" },
}
X.TL_STYLE = TL_STYLE

--- Zeitleiste des Versuchs als SVG-Bild. now: Endzeit, falls der Run noch läuft (ms).
function X.timeline_svg(state, now)
  local tl = state.timeline or {}
  local start = state.started_at > 0 and state.started_at or ((tl[1] and tl[1].t) or 0)
  local stop = state.ended_at > 0 and state.ended_at or (now or start)
  for _, e in ipairs(tl) do if e.t > stop then stop = e.t end end
  if stop <= start then stop = start + 60000 end
  local W, left, right, lane, top = 1000, 130, 20, 54, 46
  local players = state.order
  local H = top + #players * lane + 56
  local span = stop - start
  local function x(t) return left + (t - start) / span * (W - left - right) end
  local out = {}
  local function add(s) out[#out + 1] = s end
  add(string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" font-family="sans-serif" font-size="12">', W, H, W, H))
  add('<rect width="100%" height="100%" fill="#ffffff"/>')
  add(string.format('<text x="10" y="22" font-size="16" font-weight="bold">%s</text>',
    xml("Soul Link – Zeitleiste Versuch " .. U.num(state.attempt) .. (state.phase == "finished" and (" (" .. state.result .. ")") or ""))))
  -- Zeitachse: Markierungen in sinnvollen Abständen
  local steps = { 60000, 300000, 600000, 900000, 1800000, 3600000, 7200000 }
  local step = steps[#steps]
  for _, st in ipairs(steps) do if span / st <= 12 then step = st break end end
  local axis_y = top + #players * lane + 8
  local tick = 0
  while tick <= span do
    local tx = x(start + tick)
    add(string.format('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="#e3e6eb"/>', tx, top - 6, tx, axis_y))
    add(string.format('<text x="%.1f" y="%d" text-anchor="middle" fill="#677085">%s</text>', tx, axis_y + 14, X.duration(tick)))
    tick = tick + step
  end
  for i, pid in ipairs(players) do
    local y = top + (i - 1) * lane + lane / 2
    add(string.format('<text x="10" y="%.1f" font-weight="bold">%s</text>', y + 4, xml(M.player_name(state, pid))))
    add(string.format('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="#c9ced8" stroke-width="2"/>', left, y, W - right, y))
    -- Offline-Zeiten als graue Balken
    local off
    for _, e in ipairs(tl) do
      if e.p == pid and e.k == "offline" then off = e.t end
      if e.p == pid and e.k == "online" and off then
        add(string.format('<rect x="%.1f" y="%.1f" width="%.1f" height="14" fill="#c9ced8" opacity="0.6"><title>offline</title></rect>',
          x(off), y - 7, math.max(1, x(e.t) - x(off))))
        off = nil
      end
    end
    if off then
      add(string.format('<rect x="%.1f" y="%.1f" width="%.1f" height="14" fill="#c9ced8" opacity="0.6"><title>offline</title></rect>',
        x(off), y - 7, math.max(1, x(stop) - x(off))))
    end
    for _, e in ipairs(tl) do
      local st = TL_STYLE[e.k]
      if e.p == pid and st then
        local ex = x(e.t)
        local title = "<title>" .. xml(st.name .. ": " .. e.l .. " – " .. X.duration(e.t - start)) .. "</title>"
        if e.k == "fang" then
          add(string.format('<circle cx="%.1f" cy="%.1f" r="5" fill="%s">%s</circle>', ex, y, st.color, title))
        elseif e.k == "tot" or e.k == "mitgerissen" then
          add(string.format('<g stroke="%s" stroke-width="3">%s<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/><line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/></g>',
            st.color, title, ex - 5, y - 5, ex + 5, y + 5, ex - 5, y + 5, ex + 5, y - 5))
        elseif e.k == "orden" then
          add(string.format('<polygon points="%.1f,%.1f %.1f,%.1f %.1f,%.1f %.1f,%.1f" fill="%s">%s</polygon>',
            ex, y - 9, ex + 7, y, ex, y + 9, ex - 7, y, st.color, title))
          add(string.format('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="10" fill="#8a6d00">%s</text>', ex, y - 12, xml(e.l:gsub("Orden ", ""))))
        elseif e.k == "verbraucht" then
          add(string.format('<rect x="%.1f" y="%.1f" width="9" height="9" fill="%s">%s</rect>', ex - 4.5, y - 4.5, st.color, title))
        elseif e.k == "verstoss" then
          add(string.format('<polygon points="%.1f,%.1f %.1f,%.1f %.1f,%.1f" fill="%s">%s</polygon>', ex, y - 7, ex + 7, y + 6, ex - 7, y + 6, st.color, title))
        end
      end
    end
  end
  -- Legende
  local lx, ly = left, H - 14
  for _, k in ipairs({ "fang", "tot", "mitgerissen", "orden", "verbraucht", "verstoss" }) do
    add(string.format('<rect x="%d" y="%d" width="10" height="10" fill="%s"/><text x="%d" y="%d">%s</text>',
      lx, ly - 9, TL_STYLE[k].color, lx + 14, ly, xml(TL_STYLE[k].name)))
    lx = lx + 30 + #TL_STYLE[k].name * 7
  end
  add(string.format('<rect x="%d" y="%d" width="10" height="10" fill="#c9ced8"/><text x="%d" y="%d">offline</text>', lx, ly - 9, lx + 14, ly))
  add("</svg>")
  return table.concat(out, "\n") .. "\n"
end

local VIOLATION_KINDS = {
  orden_aufhol = "Orden im Aufhol-Modus", items_im_kampf = "Items im Kampf", savestate = "alter Spielstand",
  level_cap = "über dem Level-Cap", fang_gesperrt = "gesperrter Fang",
}
X.VIOLATION_KINDS = VIOLATION_KINDS

--- Protokoll der Regelverstöße über alle Versuche (neueste zuerst), mit Summe pro Spieler und Art.
function X.violations(ledger_view, limit)
  limit = limit or 100
  local log = (ledger_view and ledger_view.violations) or {}
  local lines = { "Soul Link – Protokoll der Regelverstöße" }
  local per = {}
  local order = {}
  for _, v in ipairs(log) do
    local key = v.player_name or v.player
    if not per[key] then per[key] = {} order[#order + 1] = key end
    per[key][v.kind] = (per[key][v.kind] or 0) + 1
  end
  for _, name in ipairs(order) do
    local parts = {}
    for _, kind in ipairs(U.sorted_keys(per[name])) do
      parts[#parts + 1] = (VIOLATION_KINDS[kind] or kind) .. " " .. U.num(per[name][kind])
    end
    lines[#lines + 1] = name .. ": " .. table.concat(parts, ", ")
  end
  for i = 1, math.min(limit, #log) do
    local v = log[i]
    lines[#lines + 1] = string.format("%s  Versuch %s  %s", clock(v.t), U.num(v.attempt or 0), v.text)
  end
  if #log == 0 then lines[#lines + 1] = "Keine Regelverstöße." end
  return table.concat(lines, "\n") .. "\n"
end

return X
