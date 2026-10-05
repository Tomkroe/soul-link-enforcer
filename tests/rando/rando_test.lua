-- Randomizer Stufe A im Zusammenspiel: Speicher-Emulator, synthetische ROM, Schreibschutz.
local T = require("lib.t")
local Emu = require("mem.emu")
local FS = require("net.fs")
local Guard = require("mem.guard")
local RomFS = require("rando.romfs")
local Rando = require("rando")
local Enc = require("rando.encounters")
local F = require("rando.romfake")

local TABLES = {
  F.enc_table({ 396, 399, 396, 403 }, { 54 }),       -- Gebiet 201
  F.enc_table({ 41, 74, 41 }, { 129, 72 }),          -- Gebiet 202
}
local ADDR = 0x02000400 -- früh im Speicher: die Suche findet sie im ersten Schritt (schnelle Tests)

local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = copy(v) end
  return o
end

local function setup(opts)
  opts = opts or {}
  local profile = copy(require("profiles.CPUD"))
  profile.addresses.encounter_table.tested = opts.tested ~= false
  local emu = Emu.fake()
  local function load_table(i)
    for j = 1, #TABLES[i] do emu.write8(ADDR + j - 1, TABLES[i]:byte(j)) end
  end
  load_table(opts.table or 1)
  local guard = Guard.new({ profile = profile, emu = emu, enabled = opts.write ~= false })
  guard:set_selftest(true)
  local mem = opts.mem or FS.memory()
  local rom = RomFS.new(F.reader(F.rom("pl_enc_data.narc", F.narc(TABLES), "CPUD")))
  local r = Rando.new({ profile = profile, emu = emu, guard = guard, fs = mem, local_dir = "local", rom = rom })
  return r, emu, load_table, mem
end

local function table_species(emu)
  local layout = require("profiles.CPUD").randomizer.encounter_layout
  return Enc.species(emu.read_bytes(ADDR, layout.size), layout)
end

local SETTINGS = { randomizer = { mode = "alle", seed = "abc" } }
local function snap(area, battle) return { area = { key = area, name = "G" .. area }, battle = battle } end

local function run_until_active(r, settings, s)
  for _ = 1, 20 do
    r:tick(settings, s)
    if r.status == "aktiv" then return true end
  end
  return false
end

T.test("Stufe A: Tabelle wird gefunden und gemäß Seed überschrieben, nur einmal", function()
  local r, emu = setup()
  T.ok(run_until_active(r, SETTINGS, snap("201")))
  T.eq(r.table_addr, ADDR)
  local after = table_species(emu)
  T.no(T.deep_eq(after, { 396, 399, 396, 403, 54 }))
  T.eq(after[1], after[3], "gleiche Originalart -> gleiche neue Art")
  T.eq(r.writes, 1)
  r:tick(SETTINGS, snap("201"))
  T.eq(r.writes, 1, "keine Doppelanwendung")
  T.eq(table_species(emu), after)
  T.ok(r:status_line():find("Randomizer aktiv"))
end)

T.test("Gleicher Seed + gleiche Einstellungen = identische Begegnungen bei allen Spielern", function()
  local a, emu_a = setup()
  local b, emu_b = setup()
  run_until_active(a, SETTINGS, snap("201"))
  run_until_active(b, SETTINGS, snap("201"))
  T.eq(table_species(emu_a), table_species(emu_b))
  T.eq(a.fingerprint, b.fingerprint)
  local c, emu_c = setup()
  run_until_active(c, { randomizer = { mode = "alle", seed = "anders" } }, snap("201"))
  T.no(T.deep_eq(table_species(emu_c), table_species(emu_a)))
  T.no(c.fingerprint == a.fingerprint)
end)

T.test("Gebiet neu geladen (Original wieder im Speicher): dieselbe Zuordnung erneut", function()
  local r, emu, load_table = setup()
  run_until_active(r, SETTINGS, snap("201"))
  local first = table_species(emu)
  load_table(2)
  r:tick(SETTINGS, snap("202"))
  local second = table_species(emu)
  T.no(T.deep_eq(second, { 41, 74, 41, 129, 72 }))
  load_table(1)
  r:tick(SETTINGS, snap("201"))
  T.eq(table_species(emu), first)
end)

T.test("Script-Neustart mit bereits geänderter Tabelle: keine Doppelanwendung", function()
  local r, emu, _, mem = setup()
  run_until_active(r, SETTINGS, snap("201"))
  local done = table_species(emu)
  -- neues Script, gleicher Speicher und gleiche Dateien
  local r2 = setup({ mem = mem })
  r2.emu = emu
  r2.guard.emu = emu
  for _ = 1, 3 do r2:tick(SETTINGS, snap("201")) end
  T.eq(table_species(emu), done, "geänderte Tabelle ist kein ROM-Original -> bleibt unangetastet")
end)

T.test("Modus edition: Artenliste aus den Begegnungsdaten der ROM", function()
  local r, emu = setup()
  run_until_active(r, { randomizer = { mode = "edition", seed = "abc" } }, snap("201"))
  local allowed = { [396] = true, [399] = true, [403] = true, [54] = true, [41] = true, [74] = true, [129] = true, [72] = true }
  for _, sp in ipairs(table_species(emu)) do T.ok(allowed[sp], "Art " .. sp .. " kommt in der Edition vor") end
  T.eq(#r.pool, 8)
end)

T.test("Nie aktiv ohne getestete Adresse, ohne Schreibfreigabe, im Kampf oder im Modus aus", function()
  local r, emu = setup({ tested = false })
  for _ = 1, 5 do r:tick(SETTINGS, snap("201")) end
  T.eq(table_species(emu), { 396, 399, 396, 403, 54 })
  T.eq(r.status, "inaktiv")
  T.ok(r.reason:find("nicht getestet"))
  local r2, emu2 = setup({ write = false })
  for _ = 1, 5 do r2:tick(SETTINGS, snap("201")) end
  T.eq(table_species(emu2), { 396, 399, 396, 403, 54 })
  local r3, emu3 = setup()
  for _ = 1, 5 do r3:tick(SETTINGS, snap("201", { wild = true })) end
  T.eq(table_species(emu3), { 396, 399, 396, 403, 54 })
  local r4, emu4 = setup()
  for _ = 1, 5 do r4:tick({ randomizer = { mode = "aus", seed = "" } }, snap("201")) end
  T.eq(table_species(emu4), { 396, 399, 396, 403, 54 })
  T.eq(r4:status_line(), nil)
end)

T.test("Modus edition ohne ROM: inaktiv mit klarer Meldung", function()
  local r = setup()
  r.rom = nil
  r.rom_path = ""
  r:tick({ randomizer = { mode = "edition", seed = "x" } }, snap("201"))
  T.eq(r.status, "inaktiv")
  T.ok(r.reason:find("rom_path"))
end)

T.test("Stufen B und C bleiben gesperrt, bis die vorige Stufe stabil getestet ist", function()
  local r = setup()
  local ok, why = r:stage_allowed("B")
  T.no(ok)
  T.ok(why:find("Stufe A stabil"))
  ok, why = r:stage_allowed("C")
  T.no(ok)
  T.ok(why:find("Stufe B stabil"))
  T.ok(r:stage_allowed("A"))
end)
