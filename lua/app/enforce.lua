-- Durchsetzungsplan: leitet aus Server-Zustand und aktuellem Spielzustand ab, was das Script tun
-- muss (KP auf 0 halten, Eingaben sperren). Rein und testbar; die Regeln selbst kommen aus core.rules.

local R = require("core.rules")

local Enforce = {}

-- Bei einer Sperre erlaubte Tasten: Menü öffnen und darin bedienen (Box-Verwaltung am PC).
Enforce.MENU_KEYS = { start = true, X = true, B = true, A = true, up = true, down = true, left = true, right = true }

--- state: Server-Zustand (oder nil), pid: eigene Spieler-ID, snap: Schnappschuss (oder nil),
--- opts: { absence_pending = bool, override_until = ms, now = ms }
-- Rückgabe: { hp_zero = { uid, ... }, lock = bool, lock_mode = "menu"|"voll", reasons = { text, ... } }
function Enforce.plan(state, pid, snap, opts)
  opts = opts or {}
  local plan = { hp_zero = {}, lock = false, lock_mode = "menu", reasons = {} }
  if not state or state.phase ~= "running" or not state.players[pid] then return plan end

  local dead = {}
  for _, uid in ipairs(R.dead_uids(state, pid)) do dead[uid] = true end

  -- Regel 4: tote Monster dauerhaft auf 0 KP – egal ob Item, Heilung oder Tausch.
  if snap and snap.party then
    for _, m in ipairs(snap.party) do
      if dead[m.uid] and (m.hp or 0) > 0 then plan.hp_zero[#plan.hp_zero + 1] = m.uid end
    end
  end

  -- Abwesenheitsliste: Sperre, bis der Spieler sie bestätigt hat (vor dem Weiterspielen).
  if opts.absence_pending then
    plan.lock = true
    plan.lock_mode = "voll"
    plan.reasons[#plan.reasons + 1] = "In deiner Abwesenheit sind Monster gestorben – Liste bestätigen (Taste siehe Overlay)."
  end

  -- Regeln 4 und 5: tote Monster im Team, Team-Gleichheit. Erst nach dem laufenden Kampf.
  local in_battle = snap and snap.battle ~= nil
  if snap and snap.party and not in_battle then
    local party = {}
    for _, m in ipairs(snap.party) do party[#party + 1] = m.uid end
    local check = R.team_check(state, pid, party)
    if not check.ok then
      plan.lock = true
      for _, d in ipairs(check.dead) do plan.reasons[#plan.reasons + 1] = "Tot, muss in die Box: " .. d.label end
      for _, m in ipairs(check.missing) do plan.reasons[#plan.reasons + 1] = "Fehlt im Team: " .. m.label end
      for _, x in ipairs(check.extra) do plan.reasons[#plan.reasons + 1] = "Zu viel im Team: " .. x.label .. " (" .. x.reason .. ")" end
    end
  end

  -- Kurzzeitige Freigabe für den Weg zum PC (wird allen angezeigt).
  if plan.lock and plan.lock_mode == "menu" and opts.override_until and opts.now and opts.now < opts.override_until then
    plan.lock = false
    plan.reasons[#plan.reasons + 1] = "Sperre kurz ausgesetzt (Weg zum PC)."
  end
  return plan
end

--- Wendet eine Sperre auf die gedrückten Tasten an. Rückgabe: Tabelle für joypad.set
-- (false = Taste unterdrücken) oder nil, wenn nichts gesperrt ist.
function Enforce.joypad_mask(plan, in_menu)
  if not plan.lock then return nil end
  local mask = {}
  local all = { "A", "B", "X", "Y", "L", "R", "start", "select", "up", "down", "left", "right" }
  for _, k in ipairs(all) do
    local allowed = false
    if plan.lock_mode == "menu" then
      allowed = (k == "start" or k == "X") or (in_menu and Enforce.MENU_KEYS[k])
    end
    if not allowed then mask[k] = false end
  end
  return mask
end

return Enforce
