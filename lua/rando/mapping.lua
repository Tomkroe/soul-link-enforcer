-- Zuordnungen des Randomizers (rein, deterministisch). Hängt nur von Seed, Modus, Artenliste und
-- Gebiet ab – alle Spieler mit gleichem Seed, gleichen Einstellungen und gleicher Edition erhalten
-- dieselben Begegnungen.
--
--   Stufe A  wilde Begegnungen: pro Gebiet eine feste Zuordnung Originalart -> neue Art (verschieden
--            innerhalb des Gebiets, damit Seltenheitsstufen erhalten bleiben)
--   Stufe B  Starter, Geschenke, feste Begegnungen: pro Gebiet und Originalart
--   Stufe C  geschenkte Items: pro Gebiet und Original-Item, ohne ausgeschlossene Items

local PRNG = require("rando.prng")
local bits = require("lib.bits")

local Map = {}

Map.MAX_SPECIES = { [4] = 493, [5] = 649 }

local function sorted_unique(list)
  local seen, out = {}, {}
  for _, v in ipairs(list) do
    if not seen[v] and v and v > 0 then
      seen[v] = true
      out[#out + 1] = v
    end
  end
  table.sort(out)
  return out
end

--- Artenliste je Modus. edition_species: alle Arten aus den Begegnungsdaten des Spiels (Modus "edition").
-- Rückgabe: Liste oder nil, Fehlertext.
function Map.pool(mode, gen, edition_species, exclude)
  local ex = {}
  for _, v in ipairs(exclude or {}) do ex[v] = true end
  local base
  if mode == "alle" then
    base = {}
    for i = 1, Map.MAX_SPECIES[gen] do base[#base + 1] = i end
  elseif mode == "edition" then
    if not edition_species or #edition_species == 0 then
      return nil, "Modus 'edition' braucht die Begegnungsdaten des Spiels (rom_path in config.lua)"
    end
    base = edition_species
  else
    return nil, "Randomizer aus"
  end
  local out = {}
  for _, v in ipairs(sorted_unique(base)) do
    if not ex[v] then out[#out + 1] = v end
  end
  return out
end

--- Fingerabdruck von Seed, Modus und Artenliste (zum Abgleich zwischen Spielern).
function Map.fingerprint(seed, mode, pool)
  local parts = { tostring(seed), tostring(mode) }
  for _, v in ipairs(pool or {}) do parts[#parts + 1] = string.format("%.0f", v) end
  local h = PRNG.hash32(table.concat(parts, ","))
  local hex = ""
  for i = 7, 0, -1 do
    local d = bits.extract(h, i * 4, 4)
    hex = hex .. ("0123456789abcdef"):sub(d + 1, d + 1)
  end
  return hex
end

--- Stufe A: Zuordnung für ein Gebiet. originals: Arten der Begegnungstabelle (beliebige Reihenfolge,
-- doppelte erlaubt). Rückgabe: Tabelle [original] = neu.
function Map.area_map(seed, area_key, originals, pool)
  local uniq = sorted_unique(originals)
  local rng = PRNG.new(tostring(seed) .. "|A|" .. tostring(area_key))
  local shuffled = rng:shuffle(pool)
  local out = {}
  for i, sp in ipairs(uniq) do
    -- Mehr Originalarten als Pool-Einträge: wieder von vorn (nur bei sehr kleinem Pool)
    out[sp] = shuffled[((i - 1) % #shuffled) + 1]
  end
  return out
end

--- Stufe B: Ersatz für ein Geschenk/eine feste Begegnung.
function Map.gift_species(seed, area_key, original, pool)
  local rng = PRNG.new(tostring(seed) .. "|B|" .. tostring(area_key) .. "|" .. string.format("%.0f", original))
  return pool[rng:int(#pool)]
end

--- Stufe C: Ersatz für ein geschenktes Item. Ausgeschlossene Items bleiben unverändert.
-- items: Liste erlaubter Item-Nummern (bereits ohne Ausschlüsse); excluded: Menge [item] = true.
function Map.gift_item(seed, area_key, original, items, excluded)
  if excluded[original] or #items == 0 then return original end
  local rng = PRNG.new(tostring(seed) .. "|C|" .. tostring(area_key) .. "|" .. string.format("%.0f", original))
  return items[rng:int(#items)]
end

--- Ausschlussliste für Stufe C aus den Item-Kategorien (Taschen) des Spiels.
-- item_pockets: [item] = Taschenname; ausgeschlossen werden VM/TM-Tasche und Basis-Items (Schlüssel-Items).
Map.EXCLUDED_POCKETS = { tm_vm = true, basis = true }
function Map.item_lists(item_pockets)
  local allowed, excluded = {}, {}
  local ids = {}
  for id in pairs(item_pockets) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    if Map.EXCLUDED_POCKETS[item_pockets[id]] or id == 0 then
      excluded[id] = true
    else
      allowed[#allowed + 1] = id
    end
  end
  return allowed, excluded
end

return Map
