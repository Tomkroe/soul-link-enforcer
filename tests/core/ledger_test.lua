local T = require("lib.t")
local H = require("core.helpers")
local L = require("core.ledger")

local function feed(ledger, s, effects)
  local names = {}
  for _, pid in ipairs(s.state.order) do names[pid] = s.state.players[pid].name end
  return L.apply(ledger, effects, names)
end

T.test("Bilanz: Todeszähler, Versuche, Zurücksetzen", function()
  local ledger = L.new()
  local s = H.run(2)
  feed(ledger, s, { { type = "stat", player = "anna", key = "attempts", delta = 1 },
    { type = "stat", player = "anna", key = "deaths", delta = 1 }, { type = "stat", player = "ben", key = "dragged", delta = 1 } })
  T.eq(ledger.players.anna.deaths, 1)
  T.eq(ledger.players.anna.name, "Anna")
  T.eq(ledger.players.ben.dragged, 1)
  feed(ledger, s, { { type = "reset_stats", players = { "anna", "ben" } } })
  T.eq(ledger.players.anna.deaths, 0)
  T.eq(ledger.players.anna.attempts, 1, "Versuche bleiben")
end)

T.test("Bilanz: Wettkampf 2v2 über zwei Runs – Siege, Platzierungen, Konstellation", function()
  local ledger = L.new()
  for run = 1, 2 do
    local s = H.run(4, { teams = { { "anna", "ben" }, { "cem", "dana" } }, settings = { goal = { kind = "orden", value = 1 } } })
    local winner = run == 1 and { "anna", "ben" } or { "dana", "cem" }
    local loser = run == 1 and { "cem", "dana" } or { "anna", "ben" }
    H.catch_all(s, H.AREA1, "a")
    for _, pid in ipairs(winner) do s:ok("status", pid, { badges = 1 }) end
    s:ok("faint", loser[1], { uid = loser[1] .. "-a" })
    T.eq(s.state.phase, "finished")
    local all = {}
    for _, e in ipairs(s.effects) do all[#all + 1] = e end
    feed(ledger, s, all)
  end
  T.eq(ledger.players.anna.runs, 2)
  T.eq(ledger.players.anna.wins, 1)
  T.eq(ledger.players.anna.places["1"], 1)
  T.eq(ledger.players.anna.places["2"], 1)
  local c = ledger.constellations["anna+ben|cem+dana"]
  T.ok(c, "Konstellation unabhängig von Reihenfolge")
  T.eq(c.runs, 2)
  T.eq(c.label, "Anna & Ben vs. Cem & Dana")
  T.eq(c.teams["anna+ben"].wins, 1)
  T.eq(c.teams["cem+dana"].wins, 1)
  -- Ansicht für eine Lobby mit anderen Spielern enthält die Konstellation nicht
  local v = L.view(ledger, { "anna", "ben" })
  T.eq(v.constellations["anna+ben|cem+dana"], nil)
  T.ok(L.view(ledger, { "anna", "ben", "cem", "dana" }).constellations["anna+ben|cem+dana"])
end)

T.test("Bilanz: Soul Link verloren zählt als Run ohne Sieg", function()
  local ledger = L.new()
  local s = H.run(2)
  H.catch_all(s, H.AREA1, "a")
  local eff = s:ok("faint", "anna", { uid = "anna-a" })
  feed(ledger, s, eff)
  T.eq(ledger.players.anna.runs, 1)
  T.eq(ledger.players.anna.wins, 0)
  T.eq(ledger.constellations["anna+ben"].runs, 1)
end)
