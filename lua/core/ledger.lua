-- Dauerhafte Bilanz über alle Runs hinweg (Phase 4/6/8): Todeszähler, Versuche, Siege, Platzierungen pro
-- Spieler und Ergebnisse pro Team-Konstellation. Wird aus den Effekten der Engine fortgeschrieben – vom
-- Server und im Solo-Modus mit derselben Funktion.
--
-- Aufbau:
--   { players = { [id] = { name, deaths, dragged, attempts, wins, runs, places = { ["1"] = n, ... } } },
--     constellations = { [schluessel] = { label, runs, teams = { [teamschluessel] = { label, wins, places } } } },
--     deathlog = { { t, player, player_name, label, level, area, opponent, by, cause, attempt, lobby }, ... } }

local U = require("core.util")

local L = {}

L.DEATHLOG_LIMIT = 2000 -- älteste Einträge fallen danach heraus

function L.new()
  return U.map({ players = U.map(), constellations = U.map(), deathlog = U.list() })
end

local function player(ledger, pid, name)
  local p = ledger.players[pid]
  if not p then
    p = U.map({ name = name or pid, deaths = 0, dragged = 0, attempts = 0, wins = 0, runs = 0, places = U.map() })
    ledger.players[pid] = p
  end
  if name and name ~= "" then p.name = name end
  p.places = p.places or U.map()
  p.runs = p.runs or 0
  return p
end
L.player = player

local function sorted_copy(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  table.sort(out)
  return out
end

--- Schlüssel einer Team-Konstellation, unabhängig von der Reihenfolge: "anna+ben|cem".
function L.constellation_key(teams)
  local keys = {}
  for _, t in ipairs(teams) do keys[#keys + 1] = table.concat(sorted_copy(t.members), "+") end
  table.sort(keys)
  return table.concat(keys, "|")
end

--- Schreibt Effekte fort. names: [id] = Anzeigename (optional).
function L.apply(ledger, effects, names)
  names = names or {}
  ledger.players = ledger.players or U.map()
  ledger.constellations = ledger.constellations or U.map()
  ledger.deathlog = ledger.deathlog or U.list()
  for _, e in ipairs(effects) do
    if e.type == "death" then
      local log = ledger.deathlog
      log[#log + 1] = e.entry
      while #log > L.DEATHLOG_LIMIT do table.remove(log, 1) end
    elseif e.type == "stat" then
      local p = player(ledger, e.player, names[e.player])
      p[e.key] = (p[e.key] or 0) + e.delta
    elseif e.type == "reset_stats" then
      for _, pid in ipairs(e.players) do
        local p = player(ledger, pid, names[pid])
        p.deaths, p.dragged = 0, 0
      end
    elseif e.type == "result" then
      local key = L.constellation_key(e.teams)
      local labels = {}
      for _, t in ipairs(e.teams) do
        local ms = {}
        for _, pid in ipairs(sorted_copy(t.members)) do ms[#ms + 1] = names[pid] or pid end
        labels[#labels + 1] = table.concat(ms, " & ")
      end
      local c = ledger.constellations[key]
      if not c then
        c = U.map({ label = table.concat(labels, " vs. "), runs = 0, teams = U.map() })
        ledger.constellations[key] = c
      end
      c.runs = c.runs + 1
      for i, t in ipairs(e.teams) do
        local tkey = table.concat(sorted_copy(t.members), "+")
        local tr = c.teams[tkey]
        if not tr then
          tr = U.map({ label = labels[i], wins = 0, places = U.map() })
          c.teams[tkey] = tr
        end
        local place = U.num(t.place)
        tr.places[place] = (tr.places[place] or 0) + 1
        if t.won then tr.wins = tr.wins + 1 end
        for _, pid in ipairs(t.members) do
          local p = player(ledger, pid, names[pid])
          p.runs = p.runs + 1
          p.places[place] = (p.places[place] or 0) + 1
          if t.won then p.wins = p.wins + 1 end
        end
      end
    end
  end
  return ledger
end

--- Bilanz für die Spieler einer Lobby (für Anzeige): Spieler-Einträge und passende Konstellationen.
function L.view(ledger, pids)
  local players = U.map()
  local set = {}
  for _, pid in ipairs(pids) do
    set[pid] = true
    players[pid] = (ledger.players or {})[pid] or U.map({ name = pid, deaths = 0, dragged = 0, attempts = 0, wins = 0, runs = 0, places = U.map() })
  end
  local cons = U.map()
  for key, c in pairs(ledger.constellations or {}) do
    local all_in = true
    for pid in key:gmatch("[^+|]+") do
      if not set[pid] then all_in = false end
    end
    if all_in then cons[key] = c end
  end
  -- Todesprotokoll der Spieler dieser Lobby (neueste 300)
  local deaths = U.list()
  local log = ledger.deathlog or {}
  for i = #log, 1, -1 do
    if set[log[i].player] then deaths[#deaths + 1] = log[i] end
    if #deaths >= 300 then break end
  end
  return U.map({ players = players, constellations = cons, deathlog = deaths })
end

return L
