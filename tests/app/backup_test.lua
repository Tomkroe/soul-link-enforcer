local T = require("lib.t")
local json = require("lib.json")
local FS = require("net.fs")
local Backup = require("app.backup")

local function setup(opts)
  local mem = FS.memory()
  mem.files["save.dsv"] = "SPIELSTAND"
  local n = 0
  local b = Backup.new({ fs = mem, save_path = opts and opts.no_save and "" or "save.dsv", dir = "bk", keep = 3,
    interval_ms = 1000, date = function() n = n + 1 return string.format("2026-10-05_20-00-%02d", n) end })
  return b, mem
end

T.test("Sicherung vor dem ersten Schreiben, nur einmal pro Sitzung", function()
  local b, mem = setup()
  local name = b:before_first_write(2)
  T.eq(name, "2026-10-05_20-00-01_orden2_vor-schreiben.dsv")
  T.eq(mem.files["bk/" .. name], "SPIELSTAND")
  T.eq(b:before_first_write(2), nil)
end)

T.test("Neuer Orden und Intervall", function()
  local b = setup()
  T.eq(b:tick(0, 1), nil)
  T.eq(b:tick(500, 1), nil)
  T.ok(b:tick(600, 2):find("orden2_orden"))
  T.eq(b:tick(1000, 2), nil)
  T.ok(b:tick(1700, 2):find("intervall"))
end)

T.test("Nur die letzten N bleiben, Liste in index.json", function()
  local b, mem = setup()
  for i = 1, 5 do b:create("test", i) end
  local idx = json.decode(mem.files["bk/index.json"])
  T.eq(#idx, 3)
  T.eq(idx[1], "2026-10-05_20-00-03_orden3_test.dsv")
  T.eq(mem.files["bk/2026-10-05_20-00-01_orden1_test.dsv"], nil)
  T.ok(mem.files["bk/2026-10-05_20-00-05_orden5_test.dsv"])
  -- Neustart liest den Index
  local b2 = Backup.new({ fs = mem, save_path = "save.dsv", dir = "bk", keep = 3, date = function() return "X" end })
  T.eq(#b2.index, 3)
end)

T.test("Ohne Pfad: abgeschaltet mit Meldung", function()
  local b = setup({ no_save = true })
  T.no(b:enabled())
  local name, err = b:create("x", 0)
  T.eq(name, nil)
  T.ok(err:find("config.lua"))
  T.eq(b:tick(99999, 1), nil)
end)
