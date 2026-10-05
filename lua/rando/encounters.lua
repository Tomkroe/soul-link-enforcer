-- Begegnungstabellen lesen und überschreiben (rein, auf Byte-Listen).
-- Das Format kommt aus dem Profil (randomizer.encounter_layout), z. B. für Gen 4:
--   { size = 0x1A4, slots = { { offset = 0x08, count = 12, stride = 8, width = 32 }, ... } }
-- Jeder Slot ist die Position einer Art-Nummer. Level und Raten bleiben unverändert.

local Enc = {}

local function get(b, off, width)
  local v = b[off + 1] + b[off + 2] * 256
  if width == 32 then v = v + b[off + 3] * 65536 + b[off + 4] * 16777216.0 end
  return v
end

local function set(b, off, width, v)
  b[off + 1] = v % 256
  b[off + 2] = math.floor(v / 256) % 256
  if width == 32 then
    b[off + 3] = 0
    b[off + 4] = 0
  end
end

--- Alle Art-Positionen einer Tabelle: Liste { offset, width, species }.
function Enc.slots(bytes, layout)
  local out = {}
  for _, s in ipairs(layout.slots) do
    for i = 0, (s.count or 1) - 1 do
      local off = s.offset + i * (s.stride or 4)
      if off + (s.width == 32 and 4 or 2) <= #bytes then
        local width = s.width or 16
        out[#out + 1] = { offset = off, width = width, species = get(bytes, off, width) }
      end
    end
  end
  return out
end

--- Arten einer Tabelle (ohne 0).
function Enc.species(bytes, layout, max_species)
  local out = {}
  for _, slot in ipairs(Enc.slots(bytes, layout)) do
    local sp = slot.species
    if sp > 0 and (not max_species or sp <= max_species) then out[#out + 1] = sp end
  end
  return out
end

--- Wendet eine Zuordnung [alt] = neu an. Rückgabe: neue Byte-Liste, Anzahl geänderter Slots.
function Enc.apply(bytes, layout, map)
  local out = {}
  for i = 1, #bytes do out[i] = bytes[i] end
  local changed = 0
  for _, slot in ipairs(Enc.slots(bytes, layout)) do
    local new = map[slot.species]
    if new and new ~= slot.species then
      set(out, slot.offset, slot.width, new)
      changed = changed + 1
    end
  end
  return out, changed
end

--- Prüft, ob eine Tabelle plausibel ist (alle Arten 0 oder 1..max_species). Schutz vor falscher Adresse.
function Enc.plausible(bytes, layout, max_species)
  local any = false
  for _, slot in ipairs(Enc.slots(bytes, layout)) do
    if slot.species ~= 0 then
      if slot.species > max_species then return false end
      any = true
    end
  end
  return any
end

return Enc
