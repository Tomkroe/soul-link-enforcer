-- Beutel und Optionen (rein, auf Byte-Listen): Sonderbonbons nachfüllen (Phase 3.7), Kampfstil "Folgen" (6.5).

local Bag = {}

local function u16(b, off) return b[off + 1] + b[off + 2] * 256 end
local function set16(b, off, v) b[off + 1] = v % 256 b[off + 2] = math.floor(v / 256) % 256 end

--- Stellt sicher, dass item mit Menge qty in der Tasche liegt (Einträge: u16 Item, u16 Menge).
-- Rückgabe: neue Byte-Liste oder nil (keine Änderung nötig), Fehlertext bei voller Tasche.
function Bag.ensure_item(pocket, slots, item, qty)
  local empty
  for i = 0, slots - 1 do
    local id = u16(pocket, i * 4)
    if id == item then
      if u16(pocket, i * 4 + 2) >= qty then return nil end
      local out = {}
      for k = 1, #pocket do out[k] = pocket[k] end
      set16(out, i * 4 + 2, qty)
      return out
    end
    if id == 0 and not empty then empty = i end
  end
  if not empty then return nil, "Tasche voll" end
  local out = {}
  for i = 1, #pocket do out[i] = pocket[i] end
  set16(out, empty * 4, item)
  set16(out, empty * 4 + 2, qty)
  return out
end

--- Setzt ein Bit (bit 0 = niedrigstes) auf den gewünschten Wert. Rückgabe: neuer Wert oder nil (unverändert).
function Bag.ensure_bit(value, bit, desired)
  local cur = math.floor(value / 2 ^ bit) % 2
  local want = desired and 1 or 0
  if cur == want then return nil end
  return value + (want - cur) * 2 ^ bit
end

return Bag
