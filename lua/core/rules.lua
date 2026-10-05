-- Regel-Abfragen: reine Funktionen über dem Zustand. Das Emulator-Script ruft sie jeden
-- Prüfzyklus mit dem zuletzt vom Server erhaltenen Zustand auf; der Server nutzt dieselben
-- Funktionen im Reducer (engine.lua). Dadurch gibt es jede Regel nur einmal.

local U = require("core.util")
local M = require("core.model")

local R = {}

--- Aufhol-Modus: aktiv, wenn mindestens ein Mitspieler des eigenen Teams offline ist.
function R.catchup_active(state, pid)
  if state.phase ~= "running" then return false, {} end
  local off = M.offline_teammates(state, pid)
  return #off > 0, off
end

--- Darf der Spieler im Gebiet fangen (bzw. zählt eine Begegnung dort)?
-- Rückgabe: erlaubt (bool), Grund (Text), Art ("ok" | "aufhol" | "verbraucht" | "genutzt")
function R.catch_allowed(state, pid, area_key)
  local team = M.team_of(state, pid)
  if not team then return false, "Kein laufender Run", "kein_run" end
  area_key = U.key(area_key)
  local area = team.areas[area_key]
  if area then
    if area.consumed then return false, "Gebiet " .. area.name .. " ist verbraucht", "verbraucht" end
    if area.by[pid] then return false, "Fang in " .. area.name .. " bereits genutzt", "genutzt" end
  end
  local active, off = R.catchup_active(state, pid)
  if active then
    for _, q in ipairs(off) do
      if not area or area.by[q] ~= "gefangen" then
        return false, "Aufhol-Modus: " .. M.player_name(state, q) .. " hat hier noch nicht gefangen", "aufhol"
      end
    end
  end
  return true, "Fang offen", "ok"
end

--- Darf der Spieler den nächsten Orden holen / die nächste Arena betreten?
function R.gym_allowed(state, pid)
  local p = state.players[pid]
  if not p or state.phase ~= "running" then return true, "" end
  local active, off = R.catchup_active(state, pid)
  if not active then return true, "" end
  for _, q in ipairs(off) do
    local partner = state.players[q]
    if p.badges >= partner.badges then
      return false, "Aufhol-Modus: " .. partner.name .. " hat " .. U.num(partner.badges)
        .. " Orden – du bist gleich weit oder weiter. Nächste Arena gesperrt."
    end
  end
  return true, ""
end

--- Alles, was das Overlay im Aufhol-Modus zeigt (Regeln nur hier, Anzeige in app/overlay.lua).
-- area_key: aktuelles Gebiet des Spielers (optional). Rückgabe:
-- { active, offline = { {player, name, badges, area, last_seen}, ... }, badge_limit, gym_ok, gym_reason,
--   catch_here = { ok, reason, kind } | nil, free_areas = { {key, name}, ... } }
function R.catchup_info(state, pid, area_key)
  local active, off = R.catchup_active(state, pid)
  local info = { active = active, offline = {}, free_areas = {} }
  if not active then return info end
  local limit
  for _, q in ipairs(off) do
    local p = state.players[q]
    info.offline[#info.offline + 1] = {
      player = q, name = p.name, badges = p.badges, area = p.area.name or "", last_seen = p.last_seen,
    }
    if not limit or p.badges < limit then limit = p.badges end
  end
  info.badge_limit = limit
  info.gym_ok, info.gym_reason = R.gym_allowed(state, pid)
  if area_key then
    local ok, reason, kind = R.catch_allowed(state, pid, area_key)
    info.catch_here = { ok = ok, reason = reason, kind = kind }
  end
  local team = M.team_of(state, pid)
  for _, key in ipairs(team.area_order) do
    if R.catch_allowed(state, pid, key) then
      info.free_areas[#info.free_areas + 1] = { key = key, name = team.areas[key].name }
    end
  end
  return info
end

--- Kennungen aller toten Monster des Spielers (für das Halten auf 0 KP).
function R.dead_uids(state, pid)
  local p = state.players[pid]
  local out = {}
  if not p then return out end
  for _, uid in ipairs(U.sorted_keys(p.mons)) do
    if p.mons[uid].status == "tot" then out[#out + 1] = uid end
  end
  return out
end

local function party_groups(state, pid, party)
  local p = state.players[pid]
  local groups, info = {}, {}
  for _, uid in ipairs(party or p.party) do
    local mon = p.mons[uid]
    if mon and mon.status == "lebt" and mon.group ~= "" then
      groups[mon.group] = uid
    end
    info[#info + 1] = { uid = uid, mon = mon }
  end
  return groups, info
end

--- Team-Prüfung (Regeln 4 und 5): tote Monster im Team und Team-Gleichheit.
-- party: optionale Liste von Kennungen (Standard: zuletzt gemeldetes Team des Spielers).
-- Rückgabe: { ok, dead = {...}, missing = {...}, extra = {...}, waiting = {...} }
-- Verglichen wird nur mit Mitspielern, die online sind (Aufhol-Modus). Monster offener Gruppen
-- (Partner hat noch nicht gefangen) werden toleriert und unter "waiting" geführt.
function R.team_check(state, pid, party)
  local result = { ok = true, dead = {}, missing = {}, extra = {}, waiting = {} }
  local p = state.players[pid]
  local team = M.team_of(state, pid)
  if not p or not team or state.phase ~= "running" then return result end

  local team_obj = team
  local mine, info = party_groups(state, pid, party)

  for _, entry in ipairs(info) do
    local mon = entry.mon
    if not mon then
      result.extra[#result.extra + 1] = { uid = entry.uid, label = "Unbekanntes Monster", reason = "nicht verknüpft" }
    elseif mon.status == "tot" then
      result.dead[#result.dead + 1] = { uid = entry.uid, label = M.mon_label(mon) }
    elseif mon.status == "lebt" and mon.group ~= "" and team_obj.groups[mon.group].status == "offen" then
      result.waiting[#result.waiting + 1] = { uid = entry.uid, label = M.mon_label(mon), group = mon.group }
    elseif mon.status == "unbekannt" or (mon.status == "lebt" and mon.group == "") then
      result.extra[#result.extra + 1] = { uid = entry.uid, label = M.mon_label(mon), reason = "nicht verknüpft" }
    end
  end

  -- Nur komplette, lebende Gruppen werden verglichen.
  local function complete_set(groups)
    local s = {}
    for gid in pairs(groups) do
      if team_obj.groups[gid] and team_obj.groups[gid].status == "komplett" then s[gid] = true end
    end
    return s
  end
  local my_set = complete_set(mine)

  local others = {}
  for _, q in ipairs(M.teammates(state, pid)) do
    -- Nur Mitspieler, die online sind und schon ein Team gemeldet haben.
    if state.players[q].online and #state.players[q].party > 0 then
      others[#others + 1] = complete_set((party_groups(state, q, nil)))
    end
  end

  if #others > 0 then
    local missing = {}
    for _, s in ipairs(others) do
      for gid in pairs(s) do
        if not my_set[gid] then missing[gid] = true end
      end
    end
    for _, gid in ipairs(U.sorted_keys(missing)) do
      local g = team_obj.groups[gid]
      local own_uid = g.members[pid]
      result.missing[#result.missing + 1] = {
        group = gid, uid = own_uid,
        label = M.mon_label(p.mons[own_uid]) .. " – " .. M.group_label(g),
      }
    end
    for _, gid in ipairs(U.sorted_keys(my_set)) do
      local in_all = true
      for _, s in ipairs(others) do
        if not s[gid] then in_all = false end
      end
      if not in_all then
        local uid = mine[gid]
        result.extra[#result.extra + 1] = {
          uid = uid, group = gid,
          label = M.mon_label(p.mons[uid]) .. " – " .. M.group_label(team_obj.groups[gid]),
          reason = "fehlt bei Mitspieler",
        }
      end
    end
  end

  result.ok = #result.dead == 0 and #result.missing == 0 and #result.extra == 0
  return result
end

--- Level-Cap: höchstes Level des nächsten Arenaleiters. gym_levels kommt aus dem Profil
-- (Index 1 = erster Arenaleiter). Rückgabe: Level oder nil (kein Cap mehr, z. B. nach allen Orden).
function R.level_cap(state, pid, gym_levels)
  if not state.settings.level_cap then return nil end
  local p = state.players[pid]
  if not p or not gym_levels then return nil end
  return gym_levels[p.badges + 1]
end

--- Gebiets-Übersicht für Overlay und Run-Übersicht.
function R.area_overview(state, pid)
  local team = M.team_of(state, pid)
  local out = {}
  if not team then return out end
  local p = state.players[pid]
  for _, key in ipairs(team.area_order) do
    local area = team.areas[key]
    local row = { key = key, name = area.name, current = (p.area.key == key), players = {} }
    for _, q in ipairs(team.members) do
      local status
      if area.by[q] == "gefangen" then
        status = "gefangen"
      elseif area.consumed then
        status = "verbraucht"
      else
        status = "Fang offen"
      end
      row.players[#row.players + 1] = { player = q, status = status }
    end
    row.group = area.group
    out[#out + 1] = row
  end
  return out
end

--- Ist das Team ausgelöscht? (Alle Gruppen tot, mindestens eine Gruppe vorhanden.)
function R.team_wiped(team)
  if #team.group_order == 0 then return false end
  for _, gid in ipairs(team.group_order) do
    if team.groups[gid].status ~= "tot" then return false end
  end
  return true
end

--- Hat das Team sein Ziel erreicht? (Alle Mitglieder haben Ordenzahl bzw. Spielende erreicht.)
function R.goal_reached(state, team)
  local goal = state.settings.goal
  for _, pid in ipairs(team.members) do
    local p = state.players[pid]
    if goal.kind == "orden" then
      if p.badges < goal.value then return false end
    else
      if not p.completed then return false end
    end
  end
  return #team.members > 0
end

local function team_progress(state, team)
  local sum = 0
  for _, pid in ipairs(team.members) do sum = sum + state.players[pid].badges end
  return sum / math.max(1, #team.members)
end

local function team_alive_groups(team)
  local n = 0
  for _, gid in ipairs(team.group_order) do
    if team.groups[gid].status ~= "tot" then n = n + 1 end
  end
  return n
end

--- Live-Rangliste aller Teams (Phase 8). Rennen: Ziel-Reihenfolge zuerst; danach Fortschritt,
-- lebende Gruppen und weniger Tode. Ausgeschiedene Teams stehen hinter aktiven.
function R.ranking(state)
  local rows = {}
  for _, tid in ipairs(state.team_order) do
    local team = state.teams[tid]
    rows[#rows + 1] = {
      team = tid, name = team.name, status = team.status, place = team.place,
      progress = team_progress(state, team), alive = team_alive_groups(team), deaths = team.deaths,
    }
  end
  local function rank_status(r)
    if r.status == "fertig" then return 0 end
    if r.status == "aktiv" then return 1 end
    return 2
  end
  table.sort(rows, function(a, b)
    local sa, sb = rank_status(a), rank_status(b)
    if sa ~= sb then return sa < sb end
    if sa == 0 and a.place ~= b.place then return a.place < b.place end
    if a.progress ~= b.progress then return a.progress > b.progress end
    if a.deaths ~= b.deaths then return a.deaths < b.deaths end
    if a.alive ~= b.alive then return a.alive > b.alive end
    return a.team < b.team
  end)
  for i, r in ipairs(rows) do r.rank = i end
  return rows
end

return R
