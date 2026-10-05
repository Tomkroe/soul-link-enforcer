-- Zustandsmodell des Runs: Konstruktoren, Nachschlagen, Beschriftungen.
-- Der gesamte Zustand ist reines JSON (keine Funktionen, keine Metatabellen außer Typmarkern),
-- damit Server und Script ihn identisch speichern und austauschen können.

local U = require("core.util")
local Settings = require("core.settings")

local M = {}

M.SCHEMA = 1
M.LOG_LIMIT = 300

function M.new_state(code)
  return U.map({
    schema = M.SCHEMA,
    code = code or "",
    phase = "lobby",            -- lobby | running | finished
    attempt = 0,
    settings = Settings.defaults(),
    players = U.map(),          -- [spieler_id] = Spieler
    order = U.list(),           -- Beitrittsreihenfolge
    team_plan = U.list(),       -- Lobby: geplante Teams als Liste von Spielerlisten (leer = alle in einem Team)
    teams = U.map(),            -- [team_id] = Team (ab Run-Start)
    team_order = U.list(),
    proposals = U.map(),        -- offene Abstimmungen
    counters = U.map({ group = 0, proposal = 0, finish = 0, tip = 0 }),
    tips = U.map(),             -- Tipprunden vor Arenen [id] = Runde
    log = U.list(),
    history = U.list(),         -- frühere Versuche
    started_at = 0,
    ended_at = 0,
    result = "",                -- "" | verloren | gewonnen | beendet
  })
end

function M.new_player(id, name, t)
  return U.map({
    id = id,
    name = name or id,
    team = "",
    online = false,
    last_seen = t or 0,
    joined_at = t or 0,
    -- Spielstand (pro Versuch zurückgesetzt)
    area = U.map(),             -- { key, name } des aktuellen Gebiets
    badges = 0,                 -- höchster erreichter Ordenstand
    game_badges = 0,            -- zuletzt gemeldeter Ordenstand (für Savestate-Erkennung)
    play_time = 0,              -- zuletzt gemeldete Spielzeit in Sekunden
    in_battle = false,
    has_balls = false,
    completed = false,          -- Spielende erreicht
    party = U.list(),           -- Kennungen der Monster im Team (Reihenfolge wie im Spiel)
    mons = U.map(),             -- [kennung] = Monster
    absence = U.list(),         -- Tode während der Abwesenheit, bis zur Bestätigung
    deaths = 0,                 -- eigene Tode in diesem Versuch
    dragged = 0,                -- mitgerissene Monster in diesem Versuch
    violations = 0,
    rando_fp = "",              -- Fingerabdruck der Randomizer-Zuordnung (Seed, Modus, Artenliste)
  })
end

function M.reset_player_run(p)
  p.area = U.map()
  p.badges = 0
  p.game_badges = 0
  p.play_time = 0
  p.in_battle = false
  p.has_balls = false
  p.completed = false
  p.party = U.list()
  p.mons = U.map()
  p.absence = U.list()
  p.deaths = 0
  p.dragged = 0
  p.violations = 0
  p.rando_fp = ""
  p.team = ""
end

function M.new_team(id, name, members)
  return U.map({
    id = id,
    name = name,
    members = U.list(members),
    groups = U.map(),           -- [gruppen_id] = Gruppe
    group_order = U.list(),
    areas = U.map(),            -- [gebiet] = Gebietsstatus
    area_order = U.list(),
    graveyard = U.list(),       -- Friedhof / Todesprotokoll
    status = "aktiv",           -- aktiv | verloren | fertig
    place = 0,                  -- Platzierung bei Wettkampf (0 = offen)
    finished_at = 0,
    deaths = 0,
  })
end

function M.new_group(id, area_key, area_name, t)
  return U.map({
    id = id,
    area = area_key,
    area_name = area_name or area_key,
    members = U.map(),          -- [spieler_id] = Monster-Kennung
    status = "offen",           -- offen | komplett | tot
    created_at = t or 0,
    died_at = 0,
    cause = "",
  })
end

function M.new_area(key, name, t)
  return U.map({
    key = key,
    name = name or key,
    first_seen = t or 0,
    by = U.map(),               -- [spieler_id] = "gefangen" | "verpasst"
    group = "",
    consumed = false,
    consumed_by = "",
  })
end

function M.new_mon(uid, ev, area_key, t)
  return U.map({
    uid = uid,
    species = ev.species or 0,
    species_name = ev.species_name or "",
    nickname = ev.nickname or "",
    types = U.list(ev.types or {}),
    family = ev.family or 0,
    level = ev.level or 0,
    shiny = ev.shiny and true or false,
    gift = ev.gift and true or false,
    area = area_key or "",
    group = "",
    status = "lebt",            -- lebt | tot | frei | unbekannt
    cause = "",
    caught_at = t or 0,
    caught_level = ev.level or 0,
    died_at = 0,
    stats = U.map({ battles = 0, fought = 0, kos = 0 }), -- Kampfstatistik (Idee für später, umgesetzt)
  })
end

-- Nachschlagen -----------------------------------------------------------

function M.team_of(state, pid)
  local p = state.players[pid]
  if not p or p.team == "" then return nil end
  return state.teams[p.team]
end

function M.teammates(state, pid)
  local team = M.team_of(state, pid)
  local out = {}
  if not team then return out end
  for _, q in ipairs(team.members) do
    if q ~= pid then out[#out + 1] = q end
  end
  return out
end

function M.offline_teammates(state, pid)
  local out = {}
  for _, q in ipairs(M.teammates(state, pid)) do
    if not state.players[q].online then out[#out + 1] = q end
  end
  return out
end

function M.mon_label(mon)
  if not mon then return "?" end
  if mon.nickname ~= "" then
    if mon.species_name ~= "" and mon.species_name ~= mon.nickname then
      return mon.nickname .. " (" .. mon.species_name .. ")"
    end
    return mon.nickname
  end
  if mon.species_name ~= "" then return mon.species_name end
  return "Art #" .. U.num(mon.species)
end

function M.group_label(group)
  return "Gruppe " .. group.id:sub(2) .. " (" .. group.area_name .. ")"
end

function M.player_name(state, pid)
  local p = state.players[pid]
  return p and p.name or pid
end

--- Liefert true, wenn die Gruppe noch mindestens ein lebendes Mitglied hat.
function M.group_alive(group)
  return group.status ~= "tot"
end

--- Entwicklungsreihen aller Gruppenmitglieder eines Teams (für die Duplikat-Klausel).
function M.team_families(state, team)
  local fam = {}
  for _, gid in ipairs(team.group_order) do
    local g = team.groups[gid]
    for pid, uid in pairs(g.members) do
      local mon = state.players[pid].mons[uid]
      if mon and mon.family ~= 0 then fam[mon.family] = true end
    end
  end
  return fam
end

function M.ensure_area(team, area, t)
  local key = U.key(area.key)
  if not team.areas[key] then
    team.areas[key] = M.new_area(key, area.name, t)
    team.area_order[#team.area_order + 1] = key
  elseif area.name and area.name ~= "" and team.areas[key].name == key then
    team.areas[key].name = area.name
  end
  return team.areas[key]
end

return M
