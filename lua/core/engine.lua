-- Regel-Engine als Reducer: apply(state, event) verändert den Zustand und liefert Effekte.
--
-- Ereignisse sind Tabellen { type = "...", player = "<id>", t = <ms>, ... }. Die Zeit t setzt der
-- Server; die Engine liest keine Uhr und nutzt keinen Zufall (deterministisch, testbar).
--
-- Effekte (Rückgabe, Liste):
--   { type = "kill", player, uid, label, cause }        Monster im Spiel auf 0 KP setzen
--   { type = "notify", to = {ids} | nil(alle), level = "info"|"warn"|"alarm", text }
--   { type = "discord", kind = "death"|"group"|"badge"|"run_start"|"run_end", text }
--   { type = "stat", player, key, delta }                dauerhafte Spielerstatistik
--   { type = "reset_stats", players = {ids} }
--   { type = "absence_report", player, deaths = {...} }   Tode während der Abwesenheit
--   { type = "rollback", player, text }                  alter Spielstand erkannt
--   { type = "error", player, text }                     Ereignis abgelehnt, Zustand unverändert

local U = require("core.util")
local M = require("core.model")
local R = require("core.rules")
local Settings = require("core.settings")

local E = {}

E.new_state = M.new_state
E.rules = R
E.model = M

local MAX_PLAYERS = 4
local PLAYTIME_TOLERANCE = 5 -- Sekunden

-- Hilfen ------------------------------------------------------------------

local Ctx = {}
Ctx.__index = Ctx

local function new_ctx(state, ev)
  return setmetatable({ state = state, ev = ev, t = ev.t or 0, effects = {} }, Ctx)
end

function Ctx:emit(effect)
  self.effects[#self.effects + 1] = effect
end

function Ctx:notify(text, level, to)
  self:emit({ type = "notify", text = text, level = level or "info", to = to })
end

function Ctx:log(kind, text, extra)
  local entry = U.map({ t = self.t, kind = kind, text = text })
  for k, v in pairs(extra or {}) do entry[k] = v end
  local log = self.state.log
  log[#log + 1] = entry
  while #log > M.LOG_LIMIT do table.remove(log, 1) end
end

function Ctx:discord(kind, text)
  if self.state.settings.discord[kind] then
    self:emit({ type = "discord", kind = kind, text = text })
  end
end

function Ctx:fail(text)
  self.effects = { { type = "error", player = self.ev.player, text = text } }
  self.failed = true
end

local function team_tag(state, team)
  if #state.team_order > 1 then return " [" .. team.name .. "]" end
  return ""
end

-- Tod eines Monsters ------------------------------------------------------

-- Markiert ein Monster als tot und schreibt den Friedhof-Eintrag.
-- cause: "eigener" (zählt als Tod), "mitgerissen" (zählt separat), "gebiet_verbraucht", "gesperrt"
function Ctx:kill_mon(pid, uid, cause, info)
  local state = self.state
  local p = state.players[pid]
  local mon = p.mons[uid]
  if not mon or mon.status == "tot" then return false end
  mon.status = "tot"
  mon.cause = cause
  mon.died_at = self.t
  if info and info.level and info.level > 0 then mon.level = info.level end

  local team = M.team_of(state, pid)
  local entry = U.map({
    t = self.t, player = pid, uid = uid, label = M.mon_label(mon), species_name = mon.species_name,
    level = mon.level, group = mon.group, cause = cause,
    area = info and info.area_name or "", opponent = info and info.opponent or "",
    by = info and info.by or "",
  })
  team.graveyard[#team.graveyard + 1] = entry

  if cause == "eigener" then
    p.deaths = p.deaths + 1
    team.deaths = team.deaths + 1
    self:emit({ type = "stat", player = pid, key = "deaths", delta = 1 })
  elseif cause == "mitgerissen" then
    p.dragged = p.dragged + 1
    self:emit({ type = "stat", player = pid, key = "dragged", delta = 1 })
  end

  self:emit({ type = "kill", player = pid, uid = uid, label = M.mon_label(mon), cause = cause })
  if not p.online then
    p.absence[#p.absence + 1] = entry
  end
  return true
end

-- Tötet alle noch lebenden Mitglieder einer Gruppe (außer except_pid).
-- Liefert die Liste der betroffenen Einträge { player, uid, label }.
function Ctx:kill_group(team, gid, cause, except_pid, info)
  local g = team.groups[gid]
  local victims = {}
  for _, q in ipairs(team.members) do
    local uid = g.members[q]
    if q ~= except_pid and uid then
      local mon = self.state.players[q].mons[uid]
      if mon and mon.status == "lebt" then
        self:kill_mon(q, uid, cause, info)
        victims[#victims + 1] = { player = q, uid = uid, label = M.mon_label(mon) }
      end
    end
  end
  g.status = "tot"
  g.died_at = self.t
  g.cause = cause
  return victims
end

function Ctx:check_team_end(team)
  local state = self.state
  if team.status ~= "aktiv" then return end
  if R.team_wiped(team) then
    team.status = "verloren"
    team.finished_at = self.t
    local text = "Alle Gruppen tot – " .. (#state.team_order > 1 and (team.name .. " scheidet aus.") or "der Run ist verloren.")
    self:notify(text, "alarm")
    self:log("team_lost", text, { team = team.id })
    self:discord("run_end", text)
  elseif R.goal_reached(state, team) then
    state.counters.finish = state.counters.finish + 1
    team.status = "fertig"
    team.place = state.counters.finish
    team.finished_at = self.t
    local text = team.name .. " hat das Ziel erreicht (Platz " .. U.num(team.place) .. ")."
    self:notify(text, "info")
    self:log("team_goal", text, { team = team.id })
    self:discord("run_end", text)
  end
  self:check_run_end()
end

function Ctx:check_run_end()
  local state = self.state
  if state.phase ~= "running" then return end
  local any_active, any_won = false, false
  for _, tid in ipairs(state.team_order) do
    local team = state.teams[tid]
    if team.status == "aktiv" then any_active = true end
    if team.status == "fertig" then any_won = true end
  end
  -- Rennen: Sobald ein Team fertig ist, steht der Sieger fest; die übrigen spielen trotzdem weiter
  -- (Platzierungen). Der Run endet, wenn kein Team mehr aktiv ist.
  if any_active then return end
  state.phase = "finished"
  state.ended_at = self.t
  state.result = any_won and "gewonnen" or "verloren"
  local text = "Run beendet: " .. state.result .. "."
  self:log("run_end", text)
  self:notify(text, any_won and "info" or "alarm")
  self:archive_attempt()
end

function Ctx:archive_attempt()
  local state = self.state
  local entry = U.map({
    attempt = state.attempt, started_at = state.started_at, ended_at = state.ended_at,
    result = state.result, players = U.map(), teams = U.list(),
  })
  for _, pid in ipairs(state.order) do
    local p = state.players[pid]
    entry.players[pid] = U.map({ name = p.name, badges = p.badges, deaths = p.deaths, dragged = p.dragged, team = p.team })
  end
  for _, tid in ipairs(state.team_order) do
    local team = state.teams[tid]
    entry.teams[#entry.teams + 1] = U.map({
      id = tid, name = team.name, members = U.list(U.copy(team.members)), status = team.status,
      place = team.place, groups = #team.group_order, deaths = team.deaths,
    })
  end
  state.history[#state.history + 1] = entry
  for _, tid in ipairs(state.team_order) do
    for _, pid in ipairs(state.teams[tid].members) do
      if state.teams[tid].status == "fertig" and state.teams[tid].place == 1 then
        self:emit({ type = "stat", player = pid, key = "wins", delta = 1 })
      end
    end
  end
end

-- Lobby -------------------------------------------------------------------

local handlers = {}

function handlers.join(ctx, ev)
  local state = ctx.state
  local pid = ev.player
  if type(pid) ~= "string" or pid == "" then return ctx:fail("Spielername fehlt") end
  local p = state.players[pid]
  if p then
    if ev.name and ev.name ~= "" then p.name = ev.name end
    return
  end
  if state.phase ~= "lobby" then
    return ctx:fail("Der Run läuft bereits – neue Spieler können erst beim nächsten Versuch beitreten.")
  end
  if #state.order >= MAX_PLAYERS then return ctx:fail("Die Lobby ist voll (höchstens 4 Spieler).") end
  state.players[pid] = M.new_player(pid, ev.name, ctx.t)
  state.order[#state.order + 1] = pid
  state.team_plan = U.list()
  ctx:log("join", M.player_name(state, pid) .. " ist der Lobby beigetreten.", { player = pid })
  ctx:notify(M.player_name(state, pid) .. " ist der Lobby beigetreten.")
end

function handlers.leave(ctx, ev)
  local state = ctx.state
  if state.phase == "running" then return ctx:fail("Während des Runs kann niemand die Lobby verlassen.") end
  state.players[ev.player] = nil
  U.remove_value(state.order, ev.player)
  state.team_plan = U.list()
  ctx:log("leave", tostring(ev.player) .. " hat die Lobby verlassen.")
end

function handlers.set_settings(ctx, ev)
  local state = ctx.state
  if state.phase == "running" then
    return ctx:fail("Während des Runs nur per Abstimmung (Vorschlag an alle Spieler).")
  end
  local s = state.settings
  local err
  if ev.preset then
    s, err = Settings.apply_preset(s, ev.preset)
    if not s then return ctx:fail(err) end
  end
  if ev.changes then
    s, err = Settings.apply_changes(s, ev.changes)
    if not s then return ctx:fail(err) end
  end
  state.settings = s
  ctx:log("settings", M.player_name(state, ev.player) .. " hat die Einstellungen geändert.", { player = ev.player })
end

local function validate_team_plan(state, plan)
  local seen = {}
  for _, members in ipairs(plan) do
    if #members < 1 or #members > MAX_PLAYERS then return false, "Teams müssen 1 bis 4 Spieler haben." end
    for _, pid in ipairs(members) do
      if not state.players[pid] then return false, "Unbekannter Spieler im Team: " .. tostring(pid) end
      if seen[pid] then return false, "Spieler doppelt eingeteilt: " .. tostring(pid) end
      seen[pid] = true
    end
  end
  for _, pid in ipairs(state.order) do
    if not seen[pid] then return false, "Spieler nicht eingeteilt: " .. M.player_name(state, pid) end
  end
  return true
end

function handlers.set_teams(ctx, ev)
  local state = ctx.state
  if state.phase ~= "lobby" then return ctx:fail("Teams werden nur in der Lobby eingeteilt.") end
  local plan = U.list()
  for _, members in ipairs(ev.teams or {}) do
    local copy = U.list()
    for _, pid in ipairs(members) do copy[#copy + 1] = pid end
    plan[#plan + 1] = copy
  end
  local ok, err = validate_team_plan(state, plan)
  if not ok then return ctx:fail(err) end
  state.team_plan = plan
  local sizes, unequal = {}, false
  for i, members in ipairs(plan) do
    sizes[i] = U.num(#members)
    if #members ~= #plan[1] then unequal = true end
  end
  if unequal then
    ctx:notify("Hinweis: Die Teams sind ungleich groß (" .. table.concat(sizes, "v")
      .. ") und dadurch ungleich belastet.", "warn")
  end
end

function handlers.start_run(ctx, ev)
  local state = ctx.state
  if state.phase ~= "lobby" then return ctx:fail("Der Run läuft bereits oder ist beendet.") end
  if #state.order < 1 then return ctx:fail("Mindestens ein Spieler wird benötigt.") end
  local plan = state.team_plan
  if #plan == 0 then
    plan = U.list({ U.list(U.copy(state.order)) })
  end
  local ok, err = validate_team_plan(state, plan)
  if not ok then return ctx:fail(err) end

  state.attempt = state.attempt + 1
  state.phase = "running"
  state.started_at = ctx.t
  state.ended_at = 0
  state.result = ""
  state.teams = U.map()
  state.team_order = U.list()
  state.proposals = U.map()
  state.counters.group = 0
  state.counters.finish = 0
  for i, members in ipairs(plan) do
    local tid = "t" .. U.num(i)
    local names = {}
    for _, pid in ipairs(members) do names[#names + 1] = M.player_name(state, pid) end
    local name = #plan > 1 and ("Team " .. U.num(i) .. " (" .. table.concat(names, " & ") .. ")")
      or table.concat(names, " & ")
    state.teams[tid] = M.new_team(tid, name, members)
    state.team_order[#state.team_order + 1] = tid
    for _, pid in ipairs(members) do
      M.reset_player_run(state.players[pid])
      state.players[pid].team = tid
    end
  end
  for _, pid in ipairs(state.order) do
    ctx:emit({ type = "stat", player = pid, key = "attempts", delta = 1 })
  end
  local text = "Run gestartet: Versuch " .. U.num(state.attempt) .. " mit " .. U.num(#state.order)
    .. " Spieler(n), Vorlage " .. (Settings.preset_names[state.settings.preset] or state.settings.preset) .. "."
  ctx:log("run_start", text)
  ctx:notify(text)
  ctx:discord("run_start", text)
end

--- Neuer Versuch nach Run-Ende: zurück in die Lobby, Spieler und Einstellungen bleiben.
function handlers.new_attempt(ctx, ev)
  local state = ctx.state
  if state.phase ~= "finished" then
    return ctx:fail("Ein neuer Versuch ist erst nach Run-Ende möglich (oder per Abstimmung 'aufgeben').")
  end
  state.phase = "lobby"
  state.teams = U.map()
  state.team_order = U.list()
  for _, pid in ipairs(state.order) do M.reset_player_run(state.players[pid]) end
  ctx:log("lobby", "Zurück in der Lobby für Versuch " .. U.num(state.attempt + 1) .. ".")
end

-- Verbindung --------------------------------------------------------------

function handlers.online(ctx, ev)
  local state = ctx.state
  local p = state.players[ev.player]
  if not p then return ctx:fail("Unbekannter Spieler") end
  local was = p.online
  p.online = true
  p.last_seen = ctx.t
  if was then return end
  if state.phase == "running" and p.team ~= "" then
    local others = M.teammates(state, ev.player)
    if #others > 0 then ctx:notify(p.name .. " ist wieder verbunden.", "info", others) end
  end
  -- Auch nach Run-Ende: Der Spieler soll sehen, was in seiner Abwesenheit passiert ist.
  if #p.absence > 0 then
    ctx:emit({ type = "absence_report", player = ev.player, deaths = U.copy(p.absence) })
    ctx:notify(U.num(#p.absence) .. " Monster sind in deiner Abwesenheit gestorben. Bitte bestätigen.",
      "alarm", { ev.player })
  end
end

function handlers.offline(ctx, ev)
  local state = ctx.state
  local p = state.players[ev.player]
  if not p then return end
  if not p.online then return end
  p.online = false
  p.last_seen = ctx.t
  if state.phase == "running" and p.team ~= "" then
    local others = M.teammates(state, ev.player)
    if #others > 0 then
      ctx:notify(p.name .. " ist offline (kein Herzschlag). Aufhol-Modus aktiv.", "warn", others)
      ctx:log("offline", p.name .. " ist offline – Aufhol-Modus für " .. U.join(others) .. ".", { player = ev.player })
    end
  end
end

function handlers.ack_absence(ctx, ev)
  local p = ctx.state.players[ev.player]
  if p then p.absence = U.list() end
end

-- Spielereignisse ---------------------------------------------------------

local function require_running(ctx, ev)
  local state = ctx.state
  if state.phase ~= "running" then ctx:fail("Kein laufender Run.") return nil end
  local p = state.players[ev.player]
  if not p or p.team == "" then ctx:fail("Spieler gehört nicht zum Run.") return nil end
  return p, state.teams[p.team]
end

local function area_of(ev, p)
  if type(ev.area) == "table" and ev.area.key ~= nil then
    return { key = U.key(ev.area.key), name = ev.area.name or U.key(ev.area.key) }
  end
  if p.area.key then return { key = p.area.key, name = p.area.name } end
  return nil
end

function handlers.status(ctx, ev)
  local p, team = require_running(ctx, ev)
  if not p then return end
  local state = ctx.state

  -- Savestate-Erkennung: Spielzeit oder Ordenstand im Spiel gehen zurück.
  local rolled = false
  if type(ev.play_time) == "number" then
    if ev.play_time + PLAYTIME_TOLERANCE < p.play_time then rolled = true end
    p.play_time = ev.play_time
  end
  if type(ev.badges) == "number" then
    if ev.badges < p.game_badges then rolled = true end
  end
  if rolled then
    local text = "Alter Spielstand bei " .. p.name .. " erkannt! Der Server-Zustand gilt weiter, "
      .. "alle Regeln greifen sofort wieder."
    ctx:emit({ type = "rollback", player = ev.player, text = text })
    ctx:notify(text, "alarm")
    ctx:log("rollback", text, { player = ev.player })
  end

  if type(ev.area) == "table" and ev.area.key ~= nil then
    local area = area_of(ev, p)
    if p.area.key ~= area.key then
      p.area = U.map({ key = area.key, name = area.name })
      M.ensure_area(team, area, ctx.t)
      local allowed, reason, kind = R.catch_allowed(state, ev.player, area.key)
      if allowed then
        ctx:notify("Fang offen in " .. area.name .. ".", "info", { ev.player })
      elseif kind == "aufhol" then
        ctx:notify(reason, "warn", { ev.player })
      end
    end
  end

  if type(ev.badges) == "number" then
    if ev.badges > p.badges then
      local allowed, reason = R.gym_allowed(state, ev.player)
      local before = p.badges
      p.badges = ev.badges
      if not allowed then
        p.violations = p.violations + 1
        local text = "Regelverstoß: " .. p.name .. " hat im Aufhol-Modus einen Orden geholt. " .. reason
        ctx:notify(text, "alarm")
        ctx:log("violation", text, { player = ev.player })
      end
      local text = p.name .. team_tag(state, team) .. " hat Orden " .. U.num(ev.badges) .. " erhalten."
      if ev.badges - before > 1 then text = p.name .. " hat jetzt " .. U.num(ev.badges) .. " Orden." end
      ctx:log("badge", text, { player = ev.player })
      ctx:notify(text)
      ctx:discord("badge", text)
    end
    p.game_badges = ev.badges
  end

  if type(ev.in_battle) == "boolean" then p.in_battle = ev.in_battle end
  if type(ev.has_balls) == "boolean" then
    if ev.has_balls and not p.has_balls and state.settings.grace then
      ctx:notify("Erste Bälle im Beutel – die Schonfrist ist vorbei, Tode zählen ab jetzt.", "info", { ev.player })
    end
    if ev.has_balls then p.has_balls = true end
  end
  if ev.completed == true and not p.completed then
    p.completed = true
    ctx:log("complete", p.name .. " hat das Spielende erreicht.", { player = ev.player })
  end
  ctx:check_team_end(team)
end

function handlers.catch(ctx, ev)
  local p, team = require_running(ctx, ev)
  if not p then return end
  local state = ctx.state
  local uid = U.key(ev.uid)
  if not uid then return ctx:fail("Fang ohne Kennung") end
  if p.mons[uid] and p.mons[uid].status ~= "unbekannt" then return end -- bereits bekannt (Wiederholung)

  local area = area_of(ev, p)
  if not area then return ctx:fail("Fang ohne Gebiet") end
  local ar = M.ensure_area(team, area, ctx.t)
  local mon = M.new_mon(uid, ev, ar.key, ctx.t)
  p.mons[uid] = mon
  local label = M.mon_label(mon)

  -- Schillernd-Klausel: immer erlaubt, zählt nicht als Gebietsfang.
  if mon.shiny and state.settings.shiny_clause then
    mon.status = "frei"
    ctx:log("catch_free", p.name .. " hat ein schillerndes " .. label .. " gefangen (zählt nicht als Gebietsfang).",
      { player = ev.player })
    ctx:notify("Schillernd! " .. label .. " zählt nicht als Gebietsfang.", "info", { ev.player })
    return
  end

  -- Geschenke ohne Gebietszählung (Schalter aus): frei, ohne Gruppe.
  if mon.gift and not state.settings.gifts_count then
    mon.status = "frei"
    return
  end

  local allowed, reason, kind = R.catch_allowed(state, ev.player, ar.key)
  if not allowed then
    local cause = (kind == "verbraucht") and "gebiet_verbraucht" or "gesperrt"
    ctx:kill_mon(ev.player, uid, cause, { area_name = ar.name })
    local text = label .. " von " .. p.name .. " ist sofort tot: " .. reason .. "."
    ctx:notify(text, "warn", { ev.player })
    ctx:log("catch_dead", text, { player = ev.player })
    return
  end

  ar.by[ev.player] = "gefangen"
  local g
  if ar.group == "" then
    state.counters.group = state.counters.group + 1
    local gid = "g" .. U.num(state.counters.group)
    g = M.new_group(gid, ar.key, ar.name, ctx.t)
    team.groups[gid] = g
    team.group_order[#team.group_order + 1] = gid
    ar.group = gid
  else
    g = team.groups[ar.group]
  end
  g.members[ev.player] = uid
  mon.group = g.id

  if g.status == "tot" then
    -- Ein Partner-Monster dieser Gruppe ist schon gestorben.
    ctx:kill_mon(ev.player, uid, "gesperrt", { area_name = ar.name, by = "Gruppe bereits tot" })
    ctx:notify(label .. " gehört zu " .. M.group_label(g) .. ", die bereits tot ist.", "warn", { ev.player })
    return
  end

  local complete = true
  for _, q in ipairs(team.members) do
    if not g.members[q] then complete = false end
  end
  ctx:log("catch", p.name .. " hat " .. label .. " in " .. ar.name .. " gefangen.", { player = ev.player })
  if complete then
    g.status = "komplett"
    local parts = {}
    for _, q in ipairs(team.members) do
      parts[#parts + 1] = M.player_name(state, q) .. ": " .. M.mon_label(state.players[q].mons[g.members[q]])
    end
    local text = "Neue " .. M.group_label(g) .. team_tag(state, team) .. " – " .. table.concat(parts, ", ")
    ctx:notify(text)
    ctx:log("group", text, { team = team.id })
    ctx:discord("group", text)
  else
    ctx:notify(p.name .. " hat " .. label .. " in " .. ar.name .. " gefangen. Gruppe wartet auf Partner.",
      "info", team.members)
  end
end

--- Erste Begegnung im Gebiet ohne Fang (besiegt, geflohen): Gebiet verbraucht.
function handlers.encounter_failed(ctx, ev)
  local p, team = require_running(ctx, ev)
  if not p then return end
  local state = ctx.state
  local area = area_of(ev, p)
  if not area then return ctx:fail("Begegnung ohne Gebiet") end
  local ar = M.ensure_area(team, area, ctx.t)

  if ev.shiny and state.settings.shiny_clause then return end
  if not p.has_balls then
    ctx:notify("Noch keine Bälle – Begegnung in " .. ar.name .. " zählt nicht.", "info", { ev.player })
    return
  end
  if state.settings.dupes_clause and ev.family and ev.family ~= 0 and M.team_families(state, team)[ev.family] then
    ctx:notify("Duplikat-Klausel: Die Begegnung verbraucht " .. ar.name .. " nicht.", "info", { ev.player })
    return
  end
  local allowed, reason, kind = R.catch_allowed(state, ev.player, ar.key)
  if not allowed then
    if kind == "aufhol" then
      ctx:notify(reason .. " – die Begegnung verbraucht das Gebiet nicht.", "info", { ev.player })
    end
    return
  end

  ar.by[ev.player] = "verpasst"
  ar.consumed = true
  ar.consumed_by = ev.player
  local text = ar.name .. " ist verbraucht: " .. p.name .. " hat dort nichts gefangen."
  local victims = {}
  if ar.group ~= "" then
    victims = ctx:kill_group(team, ar.group, "gebiet_verbraucht", nil, { area_name = ar.name })
    if #victims > 0 then
      local names = {}
      for _, v in ipairs(victims) do names[#names + 1] = v.label .. " (" .. M.player_name(state, v.player) .. ")" end
      text = text .. " Tot: " .. table.concat(names, ", ") .. "."
    end
  end
  ctx:notify(text, #victims > 0 and "alarm" or "warn", team.members)
  ctx:log("area_consumed", text, { player = ev.player, team = team.id })
  ctx:check_team_end(team)
end

--- Ein Monster ist auf 0 KP gefallen.
function handlers.faint(ctx, ev)
  local p, team = require_running(ctx, ev)
  if not p then return end
  local state = ctx.state
  local uid = U.key(ev.uid)
  if not uid then return ctx:fail("Tod ohne Kennung") end
  local mon = p.mons[uid]
  if mon and (mon.status == "tot") then return end -- bereits tot (Wiederholung oder Halten auf 0 KP)

  if state.settings.grace and not p.has_balls then
    ctx:notify("Schonfrist: Der Tod zählt noch nicht (noch keine Bälle).", "info", { ev.player })
    return
  end

  if not mon then
    -- Monster ohne Fang-Ereignis (z. B. vor Script-Start erhalten): als unbekannt anlegen.
    mon = M.new_mon(uid, ev, p.area.key or "", ctx.t)
    mon.status = "unbekannt"
    p.mons[uid] = mon
  end
  local area = area_of(ev, p)
  local area_name = area and area.name or ""
  if area_name == "" and mon.area ~= "" and team.areas[mon.area] then area_name = team.areas[mon.area].name end
  local info = { area_name = area_name, opponent = ev.opponent or "", level = ev.level }
  ctx:kill_mon(ev.player, uid, "eigener", info)

  local victims = {}
  if mon.group ~= "" then
    info.by = M.mon_label(mon) .. " (" .. p.name .. ")"
    info.level = nil
    victims = ctx:kill_group(team, mon.group, "mitgerissen", ev.player, info)
  end

  local text = M.mon_label(mon) .. " von " .. p.name .. team_tag(state, team) .. " ist gefallen"
  if mon.level > 0 then text = text .. " (Lv. " .. U.num(mon.level) .. ")" end
  if info.area_name ~= "" then text = text .. " in " .. info.area_name end
  if info.opponent ~= "" then text = text .. " gegen " .. info.opponent end
  text = text .. "."
  if #victims > 0 then
    local names = {}
    for _, v in ipairs(victims) do names[#names + 1] = v.label .. " (" .. M.player_name(state, v.player) .. ")" end
    text = text .. " Mitgerissen: " .. table.concat(names, ", ") .. "."
  end
  ctx:notify(text, "alarm")
  ctx:log("death", text, { player = ev.player, team = team.id })
  ctx:discord("death", text)
  ctx:check_team_end(team)
end

--- Aktuelles Team des Spielers (Kennungen, optional mit Level).
function handlers.party(ctx, ev)
  local p = require_running(ctx, ev)
  if not p then return end
  local party = U.list()
  for _, entry in ipairs(ev.mons or {}) do
    local uid = U.key(type(entry) == "table" and entry.uid or entry)
    if uid then
      party[#party + 1] = uid
      local mon = p.mons[uid]
      if type(entry) == "table" then
        if not mon then
          mon = M.new_mon(uid, entry, "", ctx.t)
          mon.status = "unbekannt"
          p.mons[uid] = mon
        end
        if type(entry.level) == "number" and entry.level > 0 then mon.level = entry.level end
        if entry.nickname and entry.nickname ~= "" then mon.nickname = entry.nickname end
        if entry.species_name and entry.species_name ~= "" then mon.species_name = entry.species_name end
      end
    end
  end
  p.party = party
end

-- Abstimmungen ------------------------------------------------------------

local proposal_kinds = { settings = true, reset_counters = true, abandon = true }

local function apply_proposal(ctx, prop)
  local state = ctx.state
  if prop.kind == "settings" then
    local s, err = Settings.apply_changes(state.settings, prop.payload.changes or {})
    if prop.payload.preset then s, err = Settings.apply_preset(s or state.settings, prop.payload.preset) end
    if not s then
      ctx:notify("Einstellungsänderung konnte nicht angewendet werden: " .. tostring(err), "warn")
      return
    end
    state.settings = s
    ctx:notify("Alle haben zugestimmt – die Einstellungen wurden geändert.")
    ctx:log("settings", "Einstellungen per Abstimmung geändert.")
  elseif prop.kind == "reset_counters" then
    local players = U.list(U.copy(state.order))
    for _, pid in ipairs(state.order) do
      state.players[pid].deaths = 0
      state.players[pid].dragged = 0
    end
    ctx:emit({ type = "reset_stats", players = players })
    ctx:notify("Alle haben zugestimmt – die Todeszähler wurden zurückgesetzt.")
    ctx:log("reset", "Todeszähler per Abstimmung zurückgesetzt.")
  elseif prop.kind == "abandon" then
    if state.phase == "running" then
      for _, tid in ipairs(state.team_order) do
        local team = state.teams[tid]
        if team.status == "aktiv" then team.status = "verloren" team.finished_at = ctx.t end
      end
      ctx:log("abandon", "Der Run wurde per Abstimmung aufgegeben.")
      ctx:discord("run_end", "Der Run wurde aufgegeben.")
      ctx:check_run_end()
    end
  end
end

local function voters(state)
  return state.order
end

local function check_proposal(ctx, prop)
  local state = ctx.state
  for _, pid in ipairs(voters(state)) do
    if not prop.votes[pid] then return end
  end
  state.proposals[prop.id] = nil
  apply_proposal(ctx, prop)
end

function handlers.propose(ctx, ev)
  local state = ctx.state
  if not state.players[ev.player] then return ctx:fail("Unbekannter Spieler") end
  if not proposal_kinds[ev.kind] then return ctx:fail("Unbekannte Abstimmung: " .. tostring(ev.kind)) end
  local payload = U.map(U.copy(ev.payload or {}))
  if ev.kind == "settings" then
    local s, err = Settings.apply_changes(state.settings, payload.changes or {})
    if s and payload.preset then s, err = Settings.apply_preset(s, payload.preset) end
    if not s then return ctx:fail(err) end
  end
  state.counters.proposal = state.counters.proposal + 1
  local id = "v" .. U.num(state.counters.proposal)
  local prop = U.map({
    id = id, kind = ev.kind, payload = payload, by = ev.player, created_at = ctx.t,
    votes = U.map({ [ev.player] = true }),
  })
  state.proposals[id] = prop
  local names = { settings = "Einstellungen ändern", reset_counters = "Todeszähler zurücksetzen", abandon = "Run aufgeben" }
  ctx:notify(M.player_name(state, ev.player) .. " schlägt vor: " .. names[ev.kind] .. ". Alle müssen zustimmen.", "warn")
  check_proposal(ctx, prop)
end

function handlers.vote(ctx, ev)
  local state = ctx.state
  local prop = state.proposals[ev.id or ""]
  if not prop then return ctx:fail("Abstimmung nicht gefunden") end
  if not U.contains(voters(state), ev.player) then return ctx:fail("Nicht stimmberechtigt") end
  if ev.accept == false then
    state.proposals[prop.id] = nil
    ctx:notify(M.player_name(state, ev.player) .. " hat abgelehnt – der Vorschlag ist verworfen.", "warn")
    return
  end
  prop.votes[ev.player] = true
  check_proposal(ctx, prop)
end

-- Einstieg ----------------------------------------------------------------

--- Wendet ein Ereignis an. Rückgabe: Liste der Effekte. Bei Fehlern bleibt der Zustand unverändert
--  (die Änderung erfolgt auf einer Kopie, die nur bei Erfolg übernommen wird).
function E.apply(state, ev)
  local handler = handlers[ev.type or ""]
  if not handler then
    return { { type = "error", player = ev.player, text = "Unbekanntes Ereignis: " .. tostring(ev.type) } }
  end
  local work = U.copy(state)
  local ctx = new_ctx(work, ev)
  handler(ctx, ev)
  if ctx.failed then return ctx.effects end
  for k in pairs(state) do state[k] = nil end
  for k, v in pairs(work) do state[k] = v end
  return ctx.effects
end

E.handlers = handlers

return E
