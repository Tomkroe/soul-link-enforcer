local T = require("lib.t")
local bits = require("lib.bits")

-- Hex-Text -> Zahl ohne Überlauf (fengari hat 32-Bit-Ganzzahlen).
local function H(hex)
  local n = 0.0
  for i = 1, #hex do n = n * 16 + tonumber(hex:sub(i, i), 16) end
  return n
end

T.test("and/or/xor", function()
  T.eq(bits.band(0xF0F0, 0xFF00), 0xF000)
  T.eq(bits.bor(0xF0F0, 0x0F00), 0xFFF0)
  T.eq(bits.bxor(H("FFFFFFFF"), 0x0000FFFF), H("FFFF0000"))
  T.eq(bits.bxor(-1, 0), H("FFFFFFFF"))
end)

T.test("Schieben", function()
  T.eq(bits.lshift(1, 31), H("80000000"))
  T.eq(bits.lshift(H("80000000"), 1), 0)
  T.eq(bits.rshift(H("FFFF0000"), 16), 0xFFFF)
end)

T.test("extract/replace", function()
  T.eq(bits.extract(0x3E000, 13, 5), 31)
  T.eq(bits.replace(0, 5, 4, 3), 0x50)
  T.eq(bits.replace(H("FFFFFFFF"), 0, 30, 1), H("BFFFFFFF"))
end)

T.test("mul32 exakt modulo 2^32", function()
  -- Bekannte LCRNG-Werte der 4./5. Generation: seed' = seed * 0x41C64E6D + 0x6073
  T.eq(bits.norm(bits.mul32(0, 0x41C64E6D) + 0x6073), 0x6073)
  T.eq(bits.norm(bits.mul32(1, 0x41C64E6D) + 0x6073), 0x41C6AEE0)
  T.eq(bits.mul32(H("FFFFFFFF"), H("FFFFFFFF")), 1)
  T.eq(bits.mul32(0x12345678, H("9ABCDEF0")), 0x242D2080)
end)
