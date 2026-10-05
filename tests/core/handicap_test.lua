-- Handicap-Ereignisse im Wettkampf.
local T = require("lib.t")
local H = require("core.helpers")
local R = require("core.rules")

local function setup(enabled)
  local s = H.run(2, { teams = { { "anna" }, { "ben" } }, settings = { handicaps = { enabled = enabled, gap = 2 } } })
  H.catch_all(s, H.AREA1, "a")
  return s
end

T.test("Handicap: erst ab Vorsprung, nur wenn eingeschaltet, eines pro Team gleichzeitig", function()
  local off = setup(false)
  off:ok("status", "anna", { badges = 3 })
  T.eq(off.state.teams.t1.handicaps, nil)
  local s = setup(true)
  s:ok("status", "anna", { badges = 1 })
  T.eq(s.state.teams.t1.handicaps, nil, "Vorsprung 1 reicht nicht")
  local eff = s:ok("status", "anna", { badges = 2 })
  local hs = s.state.teams.t1.handicaps
  T.eq(#hs, 1)
  T.ok(hs[1].active)
  T.has(eff, { type = "discord", kind = "handicap" })
  -- deterministisch: gleiches Ergebnis bei gleichem Ablauf
  local s2 = setup(true)
  s2:ok("status", "anna", { badges = 1 })
  s2:ok("status", "anna", { badges = 2 })
  T.eq(s2.state.teams.t1.handicaps[1].kind, hs[1].kind)
end)

T.test("Handicap-Wirkungen: Level-Cap −3, Items verboten, Gebietschance verfällt", function()
  local s = setup(true)
  -- Hinweis: die Engine ersetzt den Zustand nach jedem Ereignis -> Team immer frisch holen
  local function team() return s:team("anna") end
  local function give(kind, badges_at)
    team().handicaps = { { kind = kind, text = "x", active = true, badges_at = badges_at or {} } }
  end
  give("cap_minus", { anna = 2 })
  s:p("anna").badges = 2
  T.eq(R.level_cap(s.state, "anna", { 14, 22, 26 }), 23)
  T.eq(R.level_cap(s.state, "ben", { 14, 22, 26 }), 14, "nur das eigene Team")
  give("items_verboten", { anna = 2 })
  T.has(s:ok("item_used", "anna", { count = 1 }), { type = "violation" })
  T.no(T.find(s:ok("item_used", "ben", { count = 1 }), { type = "violation" }))
  s:ok("status", "anna", { badges = 3 })
  T.no(team().handicaps[1].active, "endet mit dem nächsten Orden")
  give("fang_verfaellt")
  s:ok("status", "anna", { area = H.AREA1 })
  T.no(team().areas["201"].consumed, "Gebiet mit Gruppe bleibt unberührt")
  s:ok("status", "anna", { area = H.AREA2 })
  T.ok(team().areas["202"].consumed)
  T.eq(team().areas["202"].consumed_by, "handicap")
  T.no(team().handicaps[1].active)
  local other = s.state.teams.t2.areas["202"]
  T.ok(other == nil or not other.consumed)
end)
