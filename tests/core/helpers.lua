-- Hilfen für Regel-Tests: Run aufbauen, Ereignisse mit fortlaufender Zeit anwenden.
local E = require("core.engine")
local T = require("lib.t")

local H = {}

H.NAMES = { "anna", "ben", "cem", "dana" }

--- Erstellt einen Run mit n Spielern (alle online, alle mit Bällen, in einem Team).
function H.run(n, opts)
  opts = opts or {}
  local s = { state = E.new_state("TEST"), t = 1000, effects = {} }
  function s:ev(type_, player, fields)
    local ev = {}
    for k, v in pairs(fields or {}) do ev[k] = v end
    ev.type = type_
    ev.player = player
    self.t = self.t + 1000
    ev.t = self.t
    self.effects = E.apply(self.state, ev)
    return self.effects
  end
  function s:ok(type_, player, fields)
    local effects = self:ev(type_, player, fields)
    local err = T.find(effects, { type = "error" })
    if err then error("Ereignis " .. type_ .. " abgelehnt: " .. err.text, 2) end
    return effects
  end
  function s:p(pid) return self.state.players[pid] end
  function s:mon(pid, uid) return self.state.players[pid].mons[uid] end
  function s:team(pid) return self.state.teams[self.state.players[pid].team] end
  local players = {}
  for i = 1, n do players[i] = H.NAMES[i] end
  s.players = players
  for _, pid in ipairs(players) do s:ok("join", pid, { name = pid:sub(1, 1):upper() .. pid:sub(2) }) end
  if opts.settings then s:ok("set_settings", players[1], { changes = opts.settings }) end
  if opts.preset then s:ok("set_settings", players[1], { preset = opts.preset }) end
  if opts.teams then s:ok("set_teams", players[1], { teams = opts.teams }) end
  if opts.start ~= false then
    s:ok("start_run", players[1])
    for _, pid in ipairs(players) do
      s:ok("online", pid)
      if opts.balls ~= false then s:ok("status", pid, { has_balls = true }) end
    end
  end
  return s
end

H.AREA1 = { key = "201", name = "Route 201" }
H.AREA2 = { key = "202", name = "Route 202" }
H.AREA3 = { key = "203", name = "Route 203" }

--- Jeder Spieler fängt in area ein Monster mit Kennung <spieler>-<suffix>.
function H.catch_all(s, area, suffix, players)
  for _, pid in ipairs(players or s.players) do
    s:ok("catch", pid, { uid = pid .. "-" .. suffix, species = 10, species_name = "Art" .. suffix,
      area = area, level = 5, family = 0 })
  end
end

--- Zählt Effekte eines Typs (optional gefiltert).
function H.count(effects, fields)
  local n = 0
  for _, e in ipairs(effects) do
    local match = true
    for k, v in pairs(fields) do
      if e[k] ~= v then match = false end
    end
    if match then n = n + 1 end
  end
  return n
end

return H
