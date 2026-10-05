-- JSON-Schnittstelle der Regel-Engine. Wird vom Server (über fengari) aufgerufen.
-- Alle Funktionen nehmen und liefern JSON-Text, damit die Grenze Lua <-> JavaScript schmal bleibt.

local json = require("lib.json")
local E = require("core.engine")
local R = require("core.rules")
local M = require("core.model")
local X = require("core.export")
local L = require("core.ledger")

local api = {}

function api.new_state(code)
  return json.encode(E.new_state(code))
end

--- Wendet ein Ereignis an. Rückgabe: {"state": ..., "effects": [...]}.
function api.apply(state_json, event_json)
  local state = json.decode(state_json)
  local ev = json.decode(event_json)
  local effects = E.apply(state, ev)
  return json.encode(json.object({ state = state, effects = json.array(effects) }))
end

--- Abgeleitete Ansichten für Run-Übersicht und Overlay (keine Regel-Logik im Browser).
function api.derive(state_json)
  local state = json.decode(state_json)
  local out = json.object({ ranking = json.array(R.ranking(state)), players = json.object() })
  for _, pid in ipairs(state.order) do
    local catchup, offline = R.catchup_active(state, pid)
    local gym_ok, gym_reason = R.gym_allowed(state, pid)
    out.players[pid] = json.object({
      catchup = catchup,
      offline_partners = json.array(offline),
      gym_allowed = gym_ok,
      gym_reason = gym_reason,
      areas = json.array(R.area_overview(state, pid)),
      team_check = R.team_check(state, pid),
      dead = json.array(R.dead_uids(state, pid)),
    })
  end
  return json.encode(out)
end

--- Bilanz fortschreiben: Rückgabe neue Bilanz.
function api.ledger_apply(ledger_json, effects_json, names_json)
  local ledger = json.decode(ledger_json)
  if type(ledger) ~= "table" or not ledger.players then ledger = L.new() end
  return json.encode(L.apply(ledger, json.decode(effects_json), json.decode(names_json or "{}")))
end

--- Bilanz für eine Lobby.
function api.ledger_view(ledger_json, pids_json)
  return json.encode(L.view(json.decode(ledger_json), json.decode(pids_json)))
end

--- Todesprotokoll als Text (für Stream-Overlays).
function api.deathlog(state_json, stats_json)
  return X.deathlog(json.decode(state_json), json.decode(stats_json or "{}"))
end

--- Todesprotokoll aller Versuche (aus der Bilanz-Ansicht).
function api.deathlog_all(view_json)
  return X.deathlog_all(json.decode(view_json))
end

--- Prüft die Gültigkeit eines Zustands (z. B. nach dem Laden). Rückgabe: {"ok":true} oder Fehler.
function api.check(state_json)
  local state = json.decode(state_json)
  if state.schema ~= M.SCHEMA then
    return json.encode({ ok = false, error = "Unbekannte Schema-Version" })
  end
  return json.encode({ ok = true })
end

return api
