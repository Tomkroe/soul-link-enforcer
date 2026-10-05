-- Overlay-Inhalt als Textzeilen. Rein (keine Emulator-API); app/init.lua zeichnet die Zeilen.
-- Zeile: { text, color, bg } – bg (optional) färbt den Hintergrund der Zeile (z. B. Aufhol-Kasten).

local R = require("core.rules")
local M = require("core.model")
local Export = require("core.export")

local Overlay = {}

Overlay.WIDTH = 42 -- Zeichen pro Zeile (DS-Bildschirm 256 px, Schrift ca. 6 px)

local function num(n) return string.format("%.0f", n or 0) end

--- Bricht Text an Leerzeichen um (UTF-8-sicher genug: zählt Bytes, Umlaute brechen etwas früher um).
function Overlay.wrap(text, width)
  width = width or Overlay.WIDTH
  local out = {}
  local line = ""
  for word in tostring(text):gmatch("%S+") do
    if line == "" then
      line = word
    elseif #line + 1 + #word <= width then
      line = line .. " " .. word
    else
      out[#out + 1] = line
      line = "  " .. word
    end
    while #line > width do
      out[#out + 1] = line:sub(1, width)
      line = "  " .. line:sub(width + 1)
    end
  end
  if line ~= "" then out[#out + 1] = line end
  if #out == 0 then out[1] = "" end
  return out
end

--- Dauer in Minuten/Sekunden ("3 min", "45 s", "2 h 5 min").
function Overlay.duration(ms)
  local s = math.max(0, math.floor((ms or 0) / 1000))
  if s < 60 then return num(s) .. " s" end
  local m = math.floor(s / 60)
  if m < 60 then return num(m) .. " min" end
  return num(math.floor(m / 60)) .. " h " .. num(m % 60) .. " min"
end

--- Aufhol-Modus-Kasten. now_server: aktuelle Serverzeit (ms) für "offline seit".
function Overlay.catchup(state, pid, area_key, now_server)
  local out = {}
  local info = R.catchup_info(state, pid, area_key)
  if not info.active then return out end
  local function add(text, color)
    for _, l in ipairs(Overlay.wrap(text)) do out[#out + 1] = { text = l, color = color or "weiss", bg = "gelb" } end
  end
  add("AUFHOL-MODUS", "schwarz")
  for _, o in ipairs(info.offline) do
    local since = (now_server and o.last_seen and o.last_seen > 0) and (" seit " .. Overlay.duration(now_server - o.last_seen)) or ""
    add(o.name .. " offline" .. since .. " – " .. num(o.badges) .. " Orden" .. (o.area ~= "" and (", zuletzt " .. o.area) or ""), "schwarz")
  end
  if info.gym_ok then
    add("Orden: frei bis " .. num(info.badge_limit) .. " (du: " .. num(state.players[pid].badges) .. ")", "schwarz")
  else
    add("Nächste Arena GESPERRT – Orden-Grenze " .. num(info.badge_limit) .. " erreicht", "rot")
  end
  if info.catch_here then
    if info.catch_here.ok then
      add("Fang hier erlaubt – Gruppe sofort komplett", "gruen")
    elseif info.catch_here.kind == "aufhol" then
      add("Fang hier GESPERRT (Partner hat hier nicht gefangen)", "rot")
    else
      add("Fang hier: " .. info.catch_here.reason, "schwarz")
    end
  end
  if #info.free_areas > 0 then
    local names = {}
    for _, a in ipairs(info.free_areas) do names[#names + 1] = a.name end
    add("Fang möglich in: " .. table.concat(names, ", "), "schwarz")
  else
    add("Kein Gebiet zum Fangen frei – Training ist erlaubt", "schwarz")
  end
  add("Tode werden beim Partner nachgetragen.", "schwarz")
  return out
end

--- Hauptzeilen. ctx: state, pid, net_status, online, read_only, profile_msg, profile_info, warnings,
--- stats, lock_reasons, messages, level_cap, compact, area_key, now_server, extra (Zeilen von Automatiken)
function Overlay.lines(ctx)
  local out = {}
  local function add(text, color)
    for _, l in ipairs(Overlay.wrap(text)) do out[#out + 1] = { text = l, color = color or "weiss" } end
  end
  local state, pid = ctx.state, ctx.pid

  add("Soul Link – " .. (ctx.net_status or "?"), ctx.online and "gruen" or "gelb")
  if ctx.read_only then add("LESEMODUS: " .. (ctx.profile_msg or "kein Profil"), "gelb") end
  if ctx.profile_info then add(ctx.profile_info, "grau") end
  for _, w in ipairs(ctx.warnings or {}) do add("! " .. w, "rot") end
  for _, e in ipairs(ctx.extra or {}) do add(e.text, e.color) end

  if not state then return out end
  if state.phase == "lobby" then
    add("Lobby " .. state.code .. ": " .. num(#state.order) .. " Spieler – warte auf Run-Start", "grau")
    if #state.team_plan > 1 then
      local parts, unequal = {}, false
      for _, members in ipairs(state.team_plan) do
        local names = {}
        for _, q in ipairs(members) do names[#names + 1] = M.player_name(state, q) end
        parts[#parts + 1] = table.concat(names, " & ")
        if #members ~= #state.team_plan[1] then unequal = true end
      end
      add("Teams: " .. table.concat(parts, " vs. "), "weiss")
      if unequal then add("Hinweis: Teams ungleich groß – ungleich belastet.", "gelb") end
    end
    return out
  end
  if state.phase == "finished" then
    -- Endbildschirm mit Statistik
    local color = state.result == "gewonnen" and "gruen" or "rot"
    add("RUN BEENDET: " .. string.upper(state.result), color)
    for i, line in ipairs(Export.summary(state)) do
      if i > 1 then add(line, "weiss") end
    end
  end

  local me = state.players[pid]
  if not me then return out end
  for _, l in ipairs(Overlay.catchup(state, pid, ctx.area_key, ctx.now_server)) do out[#out + 1] = l end
  for _, l in ipairs(Overlay.ranking(state, pid)) do out[#out + 1] = l end
  if ctx.level_cap then add("Level-Cap: " .. (type(ctx.level_cap) == "number" and num(ctx.level_cap) or ctx.level_cap)) end

  for _, r in ipairs(ctx.lock_reasons or {}) do add(r, "rot") end
  for _, m in ipairs(ctx.messages or {}) do
    add(m.text, m.level == "alarm" and "rot" or (m.level == "warn" and "gelb" or "weiss"))
  end
  if ctx.compact then return out end

  -- Mitspieler
  for _, q in ipairs(M.teammates(state, pid)) do
    local p = state.players[q]
    add(string.format("%s: %s, %s Orden%s%s", p.name, p.area.name or "?", num(p.badges),
      p.in_battle and ", im Kampf" or "", p.online and "" or " – OFFLINE"), p.online and "weiss" or "grau")
  end

  local team = M.team_of(state, pid)
  if team then
    local alive, open, dead = 0, 0, 0
    for _, gid in ipairs(team.group_order) do
      local st = team.groups[gid].status
      if st == "tot" then dead = dead + 1 elseif st == "offen" then open = open + 1 else alive = alive + 1 end
    end
    add("Gruppen: " .. num(alive) .. " komplett, " .. num(open) .. " offen, " .. num(dead) .. " tot")
    -- Todeszähler aller Spieler (dauerhaft, vom Server bzw. lokale Kopie)
    local parts = {}
    for _, q in ipairs(state.order) do
      local s = ctx.stats and ctx.stats[q]
      parts[#parts + 1] = M.player_name(state, q) .. " " .. num(s and s.deaths or 0)
        .. (s and s.dragged and s.dragged > 0 and ("+" .. num(s.dragged)) or "")
    end
    add("Tode: " .. table.concat(parts, "  "))
  end
  return out
end

--- Live-Rangliste (nur bei mehreren Teams): Orden, lebende Monster, Tode; eigenes Team hervorgehoben.
function Overlay.ranking(state, pid)
  local out = {}
  if #state.team_order <= 1 then return out end
  local mine = state.players[pid] and state.players[pid].team
  local label = state.settings.scoring == "ueberleben" and "Überleben" or "Rennen"
  out[#out + 1] = { text = "Rangliste (" .. label .. ")", color = "weiss" }
  for _, r in ipairs(R.ranking(state)) do
    local status = r.status == "fertig" and " – Ziel!" or (r.status == "verloren" and " – raus" or "")
    -- Kurzname (nur Spieler), damit die Zeile in die DS-Breite passt
    local names = {}
    for _, q in ipairs(state.teams[r.team].members) do names[#names + 1] = M.player_name(state, q) end
    local text = string.format("%s%d. %s: %s Orden, %s lebend, %s Tode%s", r.team == mine and ">" or " ", r.rank,
      table.concat(names, "&"), num(r.progress), num(r.alive), num(r.deaths), status)
    for _, l in ipairs(Overlay.wrap(text)) do
      out[#out + 1] = { text = l, color = r.team == mine and "gelb" or (r.status == "verloren" and "grau" or "weiss") }
    end
  end
  return out
end

--- Gruppen-Ansicht: jede Gruppe mit Gebiet, Mitgliedern und Status.
function Overlay.groups(state, pid)
  local out = {}
  local team = state and M.team_of(state, pid)
  if not team then return out end
  out[#out + 1] = { text = "Gruppen", color = "weiss" }
  local party = {}
  for _, uid in ipairs(state.players[pid].party) do party[uid] = true end
  for _, gid in ipairs(team.group_order) do
    local g = team.groups[gid]
    local names = {}
    for _, q in ipairs(team.members) do
      local uid = g.members[q]
      local mon = uid and state.players[q].mons[uid]
      names[#names + 1] = mon and M.mon_label(mon) or "–"
    end
    local mine = g.members[pid] and party[g.members[pid]] and "*" or " "
    local color = g.status == "tot" and "grau" or (g.status == "offen" and "gelb" or "weiss")
    for _, l in ipairs(Overlay.wrap(mine .. gid:sub(2) .. " " .. g.area_name .. ": " .. table.concat(names, " / ")
      .. " [" .. g.status .. "]")) do
      out[#out + 1] = { text = l, color = color }
    end
  end
  if #team.group_order == 0 then out[#out + 1] = { text = "  noch keine", color = "grau" } end
  return out
end

--- Friedhof-Ansicht.
function Overlay.graveyard(state, pid)
  local out = {}
  local team = state and M.team_of(state, pid)
  if not team then return out end
  out[#out + 1] = { text = "Friedhof", color = "rot" }
  for i = #team.graveyard, math.max(1, #team.graveyard - 12), -1 do
    local d = team.graveyard[i]
    for _, l in ipairs(Overlay.wrap(string.format("%s (%s) Lv.%s %s", d.label, M.player_name(state, d.player), num(d.level),
      d.area ~= "" and ("– " .. d.area) or ""))) do
      out[#out + 1] = { text = l, color = "grau" }
    end
  end
  return out
end

--- Gebiets-Übersicht.
function Overlay.areas(state, pid)
  local out = { { text = "Gebiete", color = "weiss" } }
  if not state then return out end
  for _, row in ipairs(R.area_overview(state, pid)) do
    local parts = {}
    for _, ps in ipairs(row.players) do parts[#parts + 1] = M.player_name(state, ps.player) .. ": " .. ps.status end
    for _, l in ipairs(Overlay.wrap((row.current and "> " or "  ") .. row.name .. " – " .. table.concat(parts, ", "))) do
      out[#out + 1] = { text = l, color = row.current and "gelb" or "weiss" }
    end
  end
  return out
end

return Overlay
