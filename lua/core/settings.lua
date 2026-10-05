-- Einstellungen und Regel-Vorlagen. Gelten für alle Spieler eines Runs.

local U = require("core.util")

local S = {}

--- Vollständige Standardeinstellungen ("Klassisch").
function S.defaults()
  return U.map({
    preset = "klassisch",
    level_cap = true,          -- Phase 3.6
    rare_candies = true,       -- Phase 3.7
    grace = true,              -- Schonfrist bis zu den ersten Bällen (Phase 6.3)
    dupes_clause = true,       -- Duplikat-Klausel (Phase 6.1)
    shiny_clause = true,       -- Schillernd-Klausel (Phase 6.2)
    gifts_count = true,        -- Geschenke zählen als Gebietsfang (Phase 6.4)
    follow_mode = true,        -- Kampfoption "Folgen" (Phase 6.5)
    death_log = true,          -- Todesprotokoll (Phase 6.6)
    battle_items = U.map({ mode = "erlaubt", max = 1 }), -- erlaubt | max | verboten (Phase 6.7)
    skip_prologue = false,     -- Phase 4
    skip_nickname = false,     -- Phase 4
    randomizer = U.map({ mode = "aus", seed = "" }),     -- aus | alle | edition (Phase 5)
    goal = U.map({ kind = "spielende", value = 0 }),    -- spielende | orden (Phase 8)
    scoring = "rennen",        -- rennen | ueberleben (Phase 8)
    discord = U.map({ death = true, group = true, badge = true, run_start = true, run_end = true }),
  })
end

S.presets = {
  locker = {
    level_cap = false, rare_candies = true, grace = true, dupes_clause = true,
    shiny_clause = true, follow_mode = false,
  },
  klassisch = {
    level_cap = true, rare_candies = true, grace = true, dupes_clause = true,
    shiny_clause = true, follow_mode = true,
  },
  hardcore = {
    level_cap = true, rare_candies = false, grace = false, dupes_clause = false,
    shiny_clause = true, follow_mode = true, battle_items = { mode = "verboten", max = 0 },
  },
}

S.preset_names = { locker = "Locker", klassisch = "Klassisch", hardcore = "Hardcore" }

local enums = {
  ["battle_items.mode"] = { erlaubt = true, max = true, verboten = true },
  ["randomizer.mode"] = { aus = true, alle = true, edition = true },
  ["goal.kind"] = { spielende = true, orden = true },
  scoring = { rennen = true, ueberleben = true },
}

local function validate_into(target, changes, prefix)
  for k, v in pairs(changes) do
    local path = prefix and (prefix .. "." .. k) or k
    local current = target[k]
    if current == nil then
      return false, "Unbekannte Einstellung: " .. path
    end
    if type(current) == "table" then
      if type(v) ~= "table" then return false, "Einstellung " .. path .. " erwartet eine Gruppe" end
      local ok, err = validate_into(current, v, path)
      if not ok then return false, err end
    else
      if type(v) ~= type(current) then
        return false, "Einstellung " .. path .. " hat den falschen Typ"
      end
      if enums[path] and not enums[path][v] then
        return false, "Ungültiger Wert für " .. path .. ": " .. tostring(v)
      end
      target[k] = v
    end
  end
  return true
end

--- Wendet Änderungen auf eine Kopie an. Rückgabe: neue Einstellungen oder nil, Fehlertext.
function S.apply_changes(settings, changes)
  local copy = U.copy(settings)
  local ok, err = validate_into(copy, changes or {}, nil)
  if not ok then return nil, err end
  return copy
end

--- Wendet eine Vorlage an (eingebaut oder als Tabelle übergeben).
function S.apply_preset(settings, preset)
  local values = type(preset) == "table" and preset or S.presets[preset]
  if not values then return nil, "Unbekannte Vorlage: " .. tostring(preset) end
  local result, err = S.apply_changes(settings, values)
  if not result then return nil, err end
  result.preset = type(preset) == "string" and preset or "eigene"
  return result
end

return S
