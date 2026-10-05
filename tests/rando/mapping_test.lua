local T = require("lib.t")
local Map = require("rando.mapping")

T.test("Artenliste je Modus", function()
  T.eq(#Map.pool("alle", 4), 493)
  T.eq(#Map.pool("alle", 5), 649)
  T.eq(Map.pool("edition", 4, { 5, 3, 3, 0, 9 }), { 3, 5, 9 })
  T.eq(#Map.pool("alle", 4, nil, { 150, 151 }), 491)
  local p, err = Map.pool("edition", 4, nil)
  T.eq(p, nil)
  T.ok(err:find("rom_path"))
  T.eq(Map.pool("aus", 4), nil)
end)

T.test("Stufe A: Zuordnung pro Gebiet fest, verschieden innerhalb des Gebiets (Referenzwerte)", function()
  local pool = Map.pool("alle", 4)
  local m = Map.area_map("Seed", "201", { 396, 399, 403 }, pool)
  T.eq({ m[396], m[399], m[403] }, { 457, 296, 439 })
  local m2 = Map.area_map("Seed", "201", { 403, 396, 399, 396 }, pool)
  T.eq(m2, m, "Reihenfolge und Doppelte egal")
  local m3 = Map.area_map("Seed", "202", { 396, 399, 403 }, pool)
  T.no(T.deep_eq(m3, m), "anderes Gebiet")
  local big = {}
  for i = 1, 30 do big[i] = i end
  local seen = {}
  for _, v in pairs(Map.area_map("S", "x", big, pool)) do
    T.no(seen[v], "doppelt")
    seen[v] = true
  end
end)

T.test("Fingerabdruck hängt von Seed, Modus und Artenliste ab", function()
  local pool = Map.pool("alle", 4)
  T.eq(Map.fingerprint("Seed", "alle", pool), "d10527cb")
  T.no(Map.fingerprint("Seed", "edition", pool) == "d10527cb")
  T.no(Map.fingerprint("Seed", "alle", Map.pool("edition", 4, { 1, 2 })) == "d10527cb")
end)

T.test("Stufe B und C: deterministische Ersatzwerte, Ausschlüsse bleiben", function()
  local pool = Map.pool("alle", 4)
  T.eq(Map.gift_species("s", "1", 387, pool), Map.gift_species("s", "1", 387, pool))
  local allowed, excluded = Map.item_lists({ [1] = "baelle", [17] = "medizin", [328] = "tm_vm", [420] = "tm_vm", [450] = "basis" })
  T.eq(allowed, { 1, 17 })
  T.ok(excluded[420])
  T.eq(Map.gift_item("s", "1", 420, allowed, excluded), 420, "VM bleibt")
  T.eq(Map.gift_item("s", "1", 450, allowed, excluded), 450, "Basis-Item bleibt")
  local r = Map.gift_item("s", "1", 17, allowed, excluded)
  T.ok(r == 1 or r == 17)
end)
