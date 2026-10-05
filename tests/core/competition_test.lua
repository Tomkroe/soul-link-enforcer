-- Wettkampf-Modus (Phase 8): Teams, Wertung Rennen/Überleben, Rangliste, Bilanz.
local T = require("lib.t")
local H = require("core.helpers")
local R = require("core.rules")
local L = require("core.ledger")

T.test("Teams: 1v1, 1v1v1, 1v1v1v1, 2v2 und gemischt erlaubt; 3er-Team im Wettkampf nicht", function()
  for _, plan in ipairs({
    { { "anna" }, { "ben" } }, { { "anna" }, { "ben" }, { "cem" } },
    { { "anna" }, { "ben" }, { "cem" }, { "dana" } }, { { "anna", "ben" }, { "cem", "dana" } },
    { { "anna", "ben" }, { "cem" }, { "dana" } },
  }) do
    local n = 0
    for _, m in ipairs(plan) do n = n + #m end
    local s = H.run(n, { start = false })
    s:ok("set_teams", "anna", { teams = plan })
  end
  local s = H.run(4, { start = false })
  local e = s:ev("set_teams", "anna", { teams = { { "anna", "ben", "cem" }, { "dana" } } })
  T.ok(T.has(e, { type = "error" }).text:find("1 Spieler %(Solo%) oder 2 Spieler"))
  -- ohne Teameinteilung: ein gemeinsamer Soul Link mit 4 Spielern
  s:ok("start_run", "anna")
  T.eq(#s.state.teams.t1.members, 4)
end)

T.test("Run-Start nennt Teams, Wertung und Ziel", function()
  local s = H.run(4, { start = false, teams = { { "anna", "ben" }, { "cem", "dana" } },
    settings = { scoring = "ueberleben", goal = { kind = "orden", value = 8 } } })
  local eff = s:ok("start_run", "anna")
  local d = T.has(eff, { type = "discord", kind = "run_start" })
  T.ok(d.text:find("Wettkampf %(Überleben, Ziel: 8 Orden%): Team 1 %(Anna & Ben%) vs%. Team 2 %(Cem & Dana%)"), d.text)
end)

-- Zwei Solo-Teams; A erreicht das Ziel zuerst, hat aber mehr Tode als B.
local function race(scoring)
  local s = H.run(2, { teams = { { "anna" }, { "ben" } },
    settings = { scoring = scoring, goal = { kind = "orden", value = 1 } } })
  H.catch_all(s, H.AREA1, "a")
  H.catch_all(s, H.AREA2, "b")
  H.catch_all(s, H.AREA3, "c")
  s:ok("faint", "anna", { uid = "anna-a" })
  s:ok("status", "anna", { badges = 1 })
  local eff = s:ok("status", "ben", { badges = 1 })
  return s, eff
end

T.test("Wertung Rennen: wer zuerst das Ziel erreicht, gewinnt", function()
  local s, eff = race("rennen")
  T.eq(s.state.phase, "finished")
  local rank = R.ranking(s.state)
  T.eq(rank[1].team, "t1")
  T.eq(rank[2].team, "t2")
  local res = T.has(eff, { type = "result" })
  T.eq(res.teams[1].team, "t1")
  T.eq(res.teams[1].won, true)
  T.eq(res.teams[2].won, false)
end)

T.test("Wertung Überleben: Fortschritt, bei Gleichstand weniger Tode – Reihenfolge zählt nicht", function()
  local s, eff = race("ueberleben")
  local rank = R.ranking(s.state)
  T.eq(rank[1].team, "t2", "gleicher Fortschritt, Ben hat weniger Tode")
  local res = T.has(eff, { type = "result" })
  T.eq(res.teams[1].team, "t2")
  T.eq(res.teams[1].won, true)
end)

T.test("Überleben: alle ausgeschieden – Platz 1 nach Fortschritt gewinnt", function()
  local s = H.run(2, { teams = { { "anna" }, { "ben" } }, settings = { scoring = "ueberleben" } })
  H.catch_all(s, H.AREA1, "a")
  s:ok("status", "ben", { badges = 2 })
  s:ok("faint", "anna", { uid = "anna-a" })
  local eff = s:ok("faint", "ben", { uid = "ben-a" })
  local res = T.has(eff, { type = "result" })
  T.eq(res.teams[1].team, "t2")
  T.eq(res.teams[1].won, true)
  local ledger = L.apply(L.new(), eff, {})
  T.eq(ledger.players.ben.wins, 1)
  T.eq(ledger.players.anna.places["2"], 1)
end)

T.test("Rangliste zählt lebende Monster, Tode und Fortschritt je Team", function()
  local s = H.run(4, { teams = { { "anna", "ben" }, { "cem", "dana" } } })
  H.catch_all(s, H.AREA1, "a")
  H.catch_all(s, H.AREA2, "b")
  s:ok("faint", "cem", { uid = "cem-a" })
  s:ok("status", "anna", { badges = 2 })
  local rank = R.ranking(s.state)
  T.eq(rank[1].team, "t1")
  T.eq(rank[1].alive, 4)
  T.eq(rank[1].progress, 1)
  T.eq(rank[2].alive, 2)
  T.eq(rank[2].deaths, 1)
end)
