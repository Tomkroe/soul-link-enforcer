-- JSON-Schnittstelle, wie sie der Server über fengari nutzt.
local T = require("lib.t")
local json = require("lib.json")
local api = require("core.api")

local function apply(state_json, ev)
  local out = json.decode(api.apply(state_json, json.encode(ev)))
  return json.encode(out.state), out.effects
end

T.test("API: neuer Zustand, Ereignisse, abgeleitete Ansicht", function()
  local st = api.new_state("ABCD")
  local eff
  st = apply(st, { type = "join", player = "anna", t = 1 })
  st = apply(st, { type = "join", player = "ben", t = 2 })
  st = apply(st, { type = "start_run", player = "anna", t = 3 })
  st = apply(st, { type = "online", player = "anna", t = 4 })
  st, eff = apply(st, { type = "status", player = "anna", t = 5, area = { key = 201, name = "Route 201" } })
  T.has(eff, { type = "notify" })
  local derived = json.decode(api.derive(st))
  T.eq(derived.players.anna.catchup, true, "ben ist nie online gewesen")
  T.eq(derived.players.anna.areas[1].key, "201", "Gebietsschlüssel als Text")
  T.eq(derived.ranking[1].team, "t1")
  T.eq(json.decode(api.check(st)).ok, true)
end)

T.test("API: Fehler werden als Effekt geliefert", function()
  local st = api.new_state("X")
  local st2, eff = apply(st, { type = "catch", player = "nobody", t = 1 })
  T.has(eff, { type = "error" })
  T.eq(st2, st)
end)
