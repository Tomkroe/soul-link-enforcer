local T = require("lib.t")
local Inputs = require("app.inputs")
local Auto = require("app.automation")
local P = require("mem.pkm")

T.test("Eingabefolge abspielen: Tasten, Halten, Loslassen, Warten", function()
  local i = Inputs.new()
  i:play("test", { { keys = "A", frames = 2 }, { wait = 1 }, { keys = "B+up", frames = 1, release = 0 } })
  local seq = {}
  while true do
    local f = i:next_frame()
    if not f then break end
    local pressed = {}
    for _, k in ipairs(Inputs.KEYS) do if f[k] then pressed[#pressed + 1] = k end end
    seq[#seq + 1] = table.concat(pressed, "+")
  end
  T.eq(seq, { "A", "A", "", "", "B+up" })
  T.no(i:busy())
end)

T.test("Wiederholung mit Pause", function()
  T.eq(#Inputs.expand({ { repeat_ = 3, keys = "A", frames = 2, gap = 5 } }), 3 * 2 + 2 * 5 + 1)
end)

T.test("Aufnahme ergibt abspielbare Schritte (Rundreise)", function()
  local r = Inputs.recorder()
  local pads = { {}, {}, { A = true }, { A = true }, {}, { B = true, up = true }, {} }
  for _, p in ipairs(pads) do r:frame(p) end
  local src = r:source()
  T.ok(src:find('keys = "A", frames = 2'))
  local steps = (loadstring or load)("return " .. src)()
  local frames = Inputs.expand(steps)
  T.eq(#frames, #pads)
  T.eq(frames[3].A, true)
  T.eq(frames[6].up, true)
end)

-- Automatik mit simuliertem Spielzustand
local function setup(profile)
  local vals = {}
  local notes, speeds, names = {}, {}, {}
  local inputs = Inputs.new()
  local a = Auto.new({
    profile = profile, inputs = inputs,
    read = function(name) return vals[name] end,
    note = function(t, l) notes[#notes + 1] = { text = t, level = l } end,
    set_speed = function(m) speeds[#speeds + 1] = m end,
    write_name = function(n) names[#names + 1] = n return true end,
  })
  return a, vals, notes, speeds, names, inputs
end

local PROFILE = {
  prologue = { inputs = { { keys = "A", frames = 2, release = 0 }, { wait = 100 } }, done = { entry = "can_walk", equals = 1 } },
  nickname = { prompt = { entry = "nick", equals = 1 } },
}

T.test("Prolog: nur bei neuem Spielstand, Schnellvorlauf, Ende am Spielzustand, Name gesetzt", function()
  local a, vals, notes, speeds, names, inputs = setup(PROFILE)
  a:prologue_tick(true, { party = {}, play_time = 3 }, "Tom")
  T.eq(a.prologue_state, "läuft")
  T.ok(inputs:busy())
  T.eq(speeds, { "turbo" })
  a:prologue_tick(true, { party = {}, play_time = 4 }, "Tom")
  T.eq(a.prologue_state, "läuft")
  vals.can_walk = 1
  a:prologue_tick(true, { party = {}, play_time = 60 }, "Tom")
  T.eq(a.prologue_state, "fertig")
  T.eq(speeds, { "turbo", "normal" })
  T.eq(names, { "Tom" })
  T.no(inputs:busy(), "Restliche Eingaben werden abgebrochen")
  T.ok(notes[#notes].text:find("frei laufen"))
end)

T.test("Prolog: kein neuer Spielstand -> nichts tun; Schalter aus -> nichts tun", function()
  local a, _, _, speeds = setup(PROFILE)
  a:prologue_tick(true, { party = { {} }, play_time = 9999 }, "Tom")
  T.eq(a.prologue_state, "aus")
  local b, _, _, speeds2 = setup(PROFILE)
  b:prologue_tick(false, { party = {}, play_time = 1 }, "Tom")
  T.eq(b.prologue_state, "bereit")
  T.eq(#speeds + #speeds2, 0)
end)

T.test("Prolog: Eingabefolge zu Ende ohne Ende-Bedingung -> Hinweis, normale Geschwindigkeit", function()
  local a, _, notes, speeds, _, inputs = setup(PROFILE)
  a:prologue_tick(true, { party = {}, play_time = 1 }, "Tom")
  while inputs:next_frame() do end
  a:prologue_tick(true, { party = {}, play_time = 30 }, "Tom")
  T.eq(a.prologue_state, "fertig")
  T.eq(speeds[#speeds], "normal")
  T.eq(notes[#notes].level, "warn")
end)

T.test("Prolog ohne Eingabefolge im Profil: klare Meldung", function()
  local a, _, notes = setup({ prologue = { inputs = {} } })
  a:prologue_tick(true, { party = {}, play_time = 1 }, "Tom")
  T.eq(a.prologue_state, "nicht_verfügbar")
  T.ok(notes[1].text:find("Aufnahme"))
end)

T.test("Prolog ohne Ende-Bedingung (nur Aufnahme): spielt ab und endet normal", function()
  local a, _, notes, speeds, names, inputs = setup({ prologue = { inputs = { { keys = "A", frames = 2 }, { wait = 3 } } } })
  a:prologue_tick(true, { party = {}, play_time = 1 }, "Tom")
  T.eq(a.prologue_state, "läuft")
  T.eq(speeds, { "turbo" })
  while inputs:next_frame() do end
  a:prologue_tick(true, { party = {}, play_time = 5 }, "Tom")
  T.eq(a.prologue_state, "fertig")
  T.eq(speeds[#speeds], "normal")
  T.eq(names, { "Tom" })
  T.no(notes[#notes].level == "warn", "kein Warn-Hinweis ohne done")
  T.ok(notes[#notes].text:find("frei laufen"))
end)

T.test("Spitznamen-Abfrage: ablehnen, solange sie offen ist (begrenzt)", function()
  local a, vals, _, _, _, inputs = setup(PROFILE)
  a:nickname_tick(true)
  T.no(inputs:busy())
  vals.nick = 1
  a:nickname_tick(true)
  T.ok(inputs:busy())
  T.eq(inputs:next_frame().B, true)
  while inputs:next_frame() do end
  for _ = 1, 10 do
    a:nickname_tick(true)
    while inputs:next_frame() do end
  end
  T.eq(a.nickname_tries, Auto.NICKNAME_MAX_TRIES)
  vals.nick = 0
  a:nickname_tick(true)
  T.eq(a.nickname_tries, 0)
  a:nickname_tick(false)
end)

T.test("Name in Gen-4-Zeichen kodieren", function()
  local b = P.encode_gen4_name("Tom7")
  T.eq(#b, 16)
  T.eq(P.u16(b, 0), 0x12B + 19) -- T
  T.eq(P.u16(b, 6), 0x121 + 7)  -- 7
  T.eq(P.u16(b, 8), 0xFFFF)
  T.ok(P.encode_gen4_name("Jürgen"), "Umlaute erlaubt")
  T.eq(P.u16(P.encode_gen4_name("Jürgen"), 2), 0x15F + (0xFC - 0xC0))
  T.eq(select(2, P.encode_gen4_name("Tom€")):find("nicht unterstützt") ~= nil, true)
  T.eq(select(2, P.encode_gen4_name("Achtzehn")):find("länger") ~= nil, true)
end)
