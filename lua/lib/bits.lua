-- Bit-Operationen für 32-Bit-Werte, rein arithmetisch.
-- Lauffähig unter Lua 5.1 (DeSmuME, ohne native Bit-Operatoren) und 5.3 (fengari).
-- Alle Ergebnisse liegen im Bereich 0 .. 2^32-1.
--
-- Achtung fengari: Ganzzahlen sind dort 32 Bit breit und laufen über. Deshalb rechnet dieses
-- Modul durchgehend mit Gleitkommazahlen (exakt bis 2^53) und vermeidet Hex-Literale >= 2^31.

local bits = {}

local TWO32 = 4294967296

local function norm(a)
  a = a % TWO32
  if a < 0 then a = a + TWO32 end
  return math.floor(a) + 0.0
end
bits.norm = norm

local function bitop(a, b, fn)
  a, b = norm(a), norm(b)
  local result, place = 0.0, 1.0
  for _ = 1, 32 do
    local ra, rb = a % 2, b % 2
    if fn(ra, rb) then result = result + place end
    a = (a - ra) / 2
    b = (b - rb) / 2
    place = place * 2
  end
  return result
end

function bits.band(a, b) return bitop(a, b, function(x, y) return x == 1 and y == 1 end) end
function bits.bor(a, b) return bitop(a, b, function(x, y) return x == 1 or y == 1 end) end
function bits.bxor(a, b) return bitop(a, b, function(x, y) return x ~= y end) end

function bits.lshift(a, n) return norm(norm(a) * 2 ^ n) end
function bits.rshift(a, n) return math.floor(norm(a) / 2 ^ n) end

--- Liest die Bits [from, from+count) aus a.
function bits.extract(a, from, count)
  return math.floor(norm(a) / 2 ^ from) % 2 ^ count
end

--- Schreibt value in die Bits [from, from+count) von a.
function bits.replace(a, value, from, count)
  a = norm(a)
  local old = bits.extract(a, from, count)
  return norm(a + (value % 2 ^ count - old) * 2 ^ from)
end

--- 32-Bit-Multiplikation modulo 2^32, ohne Genauigkeitsverlust bei doppelter Genauigkeit.
function bits.mul32(a, b)
  a, b = norm(a), norm(b)
  local b_lo = b % 65536
  local b_hi = (b - b_lo) / 65536
  local lo = a * b_lo                    -- < 2^48, exakt
  local hi = (a * b_hi) % 65536          -- < 2^48, exakt; nur die unteren 16 Bit zählen
  return norm(lo + hi * 65536)
end

return bits
