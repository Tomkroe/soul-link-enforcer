-- Deterministischer Zufall für den Randomizer. Gleicher Seed => gleiche Folge auf jedem PC und in
-- jeder Lua-Version (5.1 in DeSmuME, 5.3 in fengari): nur 32-Bit-Arithmetik über lib/bits.lua.

local bits = require("lib.bits")

local PRNG = {}
PRNG.__index = PRNG

--- FNV-1a, 32 Bit.
function PRNG.hash32(s)
  local h = 2166136261
  for i = 1, #s do
    h = bits.bxor(h, s:byte(i))
    h = bits.mul32(h, 16777619)
  end
  return h
end

function PRNG.new(seed_text)
  return setmetatable({ state = PRNG.hash32(tostring(seed_text)) }, PRNG)
end

--- Nächste Zahl (16 Bit, obere Hälfte eines 32-Bit-LCG).
function PRNG:next16()
  self.state = bits.norm(bits.mul32(self.state, 1664525) + 1013904223)
  return math.floor(self.state / 65536)
end

--- Gleichverteilt in 1..n (n <= 65536; die geringe Verzerrung durch % ist hier unerheblich).
function PRNG:int(n)
  local v = self:next16() * 65536.0 + self:next16() -- Gleitkomma: fengari-Ganzzahlen laufen bei 2^31 über
  return math.floor(v % n) + 1
end

--- Mischt eine Kopie der Liste (Fisher-Yates).
function PRNG:shuffle(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  for i = #out, 2, -1 do
    local j = self:int(i)
    out[i], out[j] = out[j], out[i]
  end
  return out
end

return PRNG
