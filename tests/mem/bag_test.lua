local T = require("lib.t")
local Bag = require("mem.bag")

local function pocket(entries, slots)
  local b = {}
  for i = 1, slots * 4 do b[i] = 0 end
  for i, e in ipairs(entries) do
    local off = (i - 1) * 4
    b[off + 1], b[off + 2] = e[1] % 256, math.floor(e[1] / 256)
    b[off + 3], b[off + 4] = e[2] % 256, math.floor(e[2] / 256)
  end
  return b
end

local function qty(b, slot) return b[slot * 4 + 3] + b[slot * 4 + 4] * 256 end
local function id(b, slot) return b[slot * 4 + 1] + b[slot * 4 + 2] * 256 end

T.test("Sonderbonbons: neu einsortieren, auffüllen, nichts tun wenn voll", function()
  local b = pocket({ { 17, 3 } }, 5)
  local n = Bag.ensure_item(b, 5, 50, 999)
  T.eq(id(n, 1), 50)
  T.eq(qty(n, 1), 999)
  T.eq(id(n, 0), 17, "andere Items bleiben")
  local b2 = pocket({ { 50, 12 } }, 5)
  T.eq(qty(Bag.ensure_item(b2, 5, 50, 999), 0), 999)
  T.eq(Bag.ensure_item(pocket({ { 50, 999 } }, 5), 5, 50, 999), nil)
  local full = pocket({ { 1, 1 }, { 2, 1 } }, 2)
  local none, err = Bag.ensure_item(full, 2, 50, 999)
  T.eq(none, nil)
  T.eq(err, "Tasche voll")
end)

T.test("Optionen: Bit setzen/löschen", function()
  T.eq(Bag.ensure_bit(0, 3, true), 8)
  T.eq(Bag.ensure_bit(8, 3, true), nil)
  T.eq(Bag.ensure_bit(15, 1, false), 13)
end)
