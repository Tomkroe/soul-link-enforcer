local T = require("lib.t")
local json = require("lib.json")

T.test("Rundreise einfacher Werte", function()
  local v = { a = 1, b = "x\"y\n", c = { 1, 2, 3 }, d = true, e = false, f = -2.5 }
  T.eq(json.decode(json.encode(v)), v)
end)

T.test("Ganze Zahlen ohne Nachkommastellen", function()
  T.eq(json.encode({ 3, 2 ^ 40, -7 }), "[3,1099511627776,-7]")
  T.eq(json.encode(0.5), "0.5")
end)

T.test("Schlüssel sortiert, deterministisch", function()
  T.eq(json.encode({ b = 1, a = 2, c = { z = 1, y = 2 } }), '{"a":2,"b":1,"c":{"y":2,"z":1}}')
end)

T.test("Leere Tabellen: [] standardmäßig, {} mit json.object", function()
  T.eq(json.encode({}), "[]")
  T.eq(json.encode(json.object()), "{}")
  T.eq(json.encode(json.decode("{}")), "{}")
  T.eq(json.encode(json.decode("[]")), "[]")
end)

T.test("Unicode und Umlaute", function()
  T.eq(json.decode('"\\u00e4\\u00f6\\u00fc \\ud83d\\ude00"'), "äöü 😀")
  T.eq(json.decode(json.encode("Zweiblattdorf – Äpfel")), "Zweiblattdorf – Äpfel")
end)

T.test("Fehlerhaftes JSON wirft Fehler", function()
  T.raises(function() json.decode("{") end, "JSON")
  T.raises(function() json.decode("[1,]") end, "JSON")
  T.raises(function() json.decode("1 2") end, "JSON")
end)

T.test("Zyklus wird erkannt", function()
  local a = {}
  a.self = a
  T.raises(function() json.encode(a) end, "zyklisch")
end)

T.test("Aus [] dekodierte Tabelle mit später ergänzten Schlüsseln wird als Objekt gespeichert", function()
  local t = json.decode('{"a":[]}')
  t.a.erster = 5
  T.eq(json.encode(t), '{"a":{"erster":5}}')
  local l = json.decode("[]")
  l[1] = "x"
  T.eq(json.encode(l), '["x"]')
  T.eq(json.encode(json.decode('{"b":[]}')), '{"b":[]}')
end)
