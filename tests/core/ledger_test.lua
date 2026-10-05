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

T.test("Regelverstöße: alle Arten, dauerhaft im Protokoll, Zähler und Export", function()
  local X = require("core.export")
  local ledger = L.new()
  local s = H.run(2, { settings = { battle_items = { mode = "verboten", max = 0 } } })
  local function f(e) feed(ledger, s, e) end
  f(s:ok("item_used", "anna", { count = 1 }))
  s:ok("status", "ben", { badges = 1 })
  s:ok("status", "anna", { badges = 1 })
  s:ok("offline", "ben")
  f(s:ok("status", "anna", { badges = 2 }))                       -- Orden im Aufhol-Modus (gleich weit)
  f(s:ok("catch", "anna", { uid = "x", area = H.AREA3 }))         -- gesperrter Fang
  s:ok("online", "ben")
  f(s:ok("status", "anna", { play_time = 100 }))
  f(s:ok("status", "anna", { play_time = 10 }))                   -- alter Spielstand
  f(s:ok("over_cap", "anna", { uid = "x", level = 20, cap = 14 }))
  local again = s:ok("over_cap", "anna", { uid = "x", level = 21, cap = 14 })
  T.no(T.find(again, { type = "violation" }), "einmal pro Monster und Cap")
  T.eq(#ledger.violations, 5)
  T.eq(ledger.players.anna.violations, 5)
  local kinds = {}
  for _, v in ipairs(ledger.violations) do kinds[#kinds + 1] = v.kind end
  T.eq(kinds, { "items_im_kampf", "orden_aufhol", "fang_gesperrt", "savestate", "level_cap" })
  local text = X.violations(L.view(ledger, { "anna", "ben" }))
  T.ok(text:find("Anna: Items im Kampf 1, über dem Level%-Cap 1, Orden im Aufhol%-Modus 1, alter Spielstand 1, gesperrter Fang 1")
    or text:find("Anna: [^\n]*gesperrter Fang 1"), text)
  T.ok(text:find("Versuch 1  Regelverstoß"), text)
end)

T.test("Erfolge: Zähler aus der Engine, Freischalten einmalig, Meldungen", function()
  local ledger = L.new()
  local s = H.run(2)
  local unlocked_all = {}
  local function f(e)
    local _, u = L.apply(ledger, e, { anna = "Anna", ben = "Ben" }, 1234)
    for _, x in ipairs(u) do unlocked_all[#unlocked_all + 1] = x.player .. ":" .. x.id end
  end
  f(s:ok("catch", "anna", { uid = "a1", area = H.AREA1 }))
  f(s:ok("catch", "ben", { uid = "b1", area = H.AREA1 }))
  f(s:ok("catch", "anna", { uid = "s1", area = H.AREA2, shiny = true }))
  f(s:ok("status", "anna", { badges = 1 }))
  T.eq(ledger.players.anna.catches, 1)
  T.eq(ledger.players.anna.shinies, 1)
  T.eq(ledger.players.anna.flawless_badge, 1)
  T.eq(ledger.players.anna.achievements.erster_fang, 1234)
  T.eq(unlocked_all, { "anna:erster_fang", "ben:erster_fang", "anna:glitzer", "anna:erster_orden", "anna:makellos" })
  f(s:ok("catch", "anna", { uid = "a2", area = H.AREA3 }))
  T.eq(#unlocked_all, 5, "nichts doppelt")
  local eff = L.unlock_effects({ { player = "anna", name_player = "Anna", id = "sieger", name = "Sieger", text = "x" } })
  T.has(eff, { type = "discord", kind = "achievement" })
  T.has(eff, { type = "notify" })
end)

T.test("Erfolge: Volles Haus, Achtfach, Aufholjagd", function()
  local ledger = L.new()
  local s = H.run(1)
  local function f(e) L.apply(ledger, e, {}, 1) end
  for i = 1, 6 do f(s:ok("catch", "anna", { uid = "m" .. i, area = { key = tostring(i), name = "G" .. i } })) end
  T.eq(ledger.players.anna.full_team, 1)
  T.ok(ledger.players.anna.achievements.volles_haus)
  f(s:ok("status", "anna", { badges = 8 }))
  T.ok(ledger.players.anna.achievements.achtfach)
  local s2 = H.run(2)
  local l2 = L.new()
  s2:ok("status", "ben", { badges = 3 })
  s2:ok("offline", "ben")
  L.apply(l2, s2:ok("status", "anna", { badges = 1 }), {}, 1)
  T.ok(l2.players.anna.achievements.aufholjagd)
end)
