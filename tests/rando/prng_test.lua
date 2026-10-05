local T = require("lib.t")
local PRNG = require("rando.prng")

T.test("FNV-1a 32 Bit: bekannte Referenzwerte", function()
  T.eq(PRNG.hash32("a"), 3826002220)      -- 0xE40C292C
  T.eq(PRNG.hash32("foobar"), 3214735720) -- 0xBF9CF968
end)

T.test("Gleicher Seed = gleiche Folge in jeder Lua-Version (Referenzwerte aus Lua 5.1)", function()
  local r = PRNG.new("Seed")
  local t = {}
  for i = 1, 6 do t[i] = r:int(1000) end
  T.eq(t, { 18, 965, 475, 425, 322, 275 })
end)

T.test("Mischen ergibt eine Permutation und ist deterministisch", function()
  local list = {}
  for i = 1, 50 do list[i] = i end
  local a = PRNG.new("x"):shuffle(list)
  local b = PRNG.new("x"):shuffle(list)
  T.eq(a, b)
  local seen = {}
  for _, v in ipairs(a) do seen[v] = true end
  for i = 1, 50 do T.ok(seen[i]) end
  T.no(T.deep_eq(a, PRNG.new("y"):shuffle(list)), "anderer Seed, andere Reihenfolge")
end)
