-- Hauptlogik mit Speicher-Emulator, Speicher-Dateisystem und simulierter Brücke.
local T = require("lib.t")
local json = require("lib.json")
local FS = require("net.fs")
local Emu = require("mem.emu")
local P = require("mem.pkm")
local App = require("app")
local Launcher = require("net.launcher")

local PROFILE = {
  game_code = "TEST", name = "Testspiel", gen = 4,
  addresses = {
    party = { addr = 0x02002000, tested = true, battle_safe = false },
    party_count = { rel = "party", offset = -4, width = 32, tested = true },
    area_id = { addr = 0x02003000, width = 16, tested = true },
    badges = { addr = 0x02003004, tested = true },
    bag_balls = { addr = 0x02003008, width = 16, tested = true },
  },
  gym_levels = { 14, 22 },
}

local function party_mon(pid, hp)
  local b = {}
  for i = 1, P.PARTY_SIZE[4] do b[i] = 0 end
  P.set_u32(b, 0, pid)
  P.set_u16(b, 0x08, 25)
  P.set_u16(b, 0x0C, 1)
  P.set_u16(b, 0x0E, 2)
  b[0x8C + 1] = 10
  P.set_u16(b, 0x8E, hp)
  P.set_u16(b, 0x90, 30)
  P.set_u16(b, 0x06, P.checksum(b))
  return P.encrypt(b)
end

local function write_bytes(emu, addr, bytes)
  for i, v in ipairs(bytes) do emu.write8(addr + i - 1, v) end
end

local function make_app(opts)
  opts = opts or {}
  package.loaded["profiles.TEST"] = PROFILE
  local emu = Emu.fake({ game_code = opts.game_code or "TEST" })
  local mem = FS.memory()
  local clock = { t = 1000000 }
  local launched = {}
  local cfg = {
    player_name = "Anna", lobby_code = "ABC", server_url = "wss://x/ws", write_enabled = opts.write ~= false,
    bridge = { autostart = true }, hotkeys = { overlay = "O", confirm = "J", graveyard = "F", areas = "G", pc_pass = "P",
      start = "N", vote_yes = "Y", vote_no = "U" },
    lobby_settings = { preset = "hardcore" },
    backups = { save_path = "save.dsv", dir = "bk" },
  }
  mem.files["save.dsv"] = "SAVE"
  local app = App.new({ config = cfg, emu = emu, fs = mem, root = "/proj", now = function() return clock.t end,
    launch = function(o) launched[#launched + 1] = o end, date = function() return "D" end })
  return app, emu, mem, clock, launched
end

-- Simuliert die Brücke: Nachrichten in in/ legen.
local function deliver(app, mem, msgs)
  local tr = app.transport
  if not tr.synced then
    mem.files[string.format("/proj/bridge/exchange/in/%08d.json", 1)] = json.encode({ op = "bridge", reset = tr.nonce, connected = true })
    app.bridge_n = 2
  end
  for _, m in ipairs(msgs) do
    mem.files[string.format("/proj/bridge/exchange/in/%08d.json", app.bridge_n)] = json.encode(m)
    app.bridge_n = app.bridge_n + 1
  end
end

local function outbox(mem)
  local out = {}
  local names = {}
  for path in pairs(mem.files) do if path:find("/out/", 1, true) then names[#names + 1] = path end end
  table.sort(names)
  for _, p in ipairs(names) do out[#out + 1] = json.decode(mem.files[p]) end
  return out
end

-- Baut einen Server-Zustand mit der echten Engine.
local function server_state(dead_uid, mon_uids)
  local H = require("core.helpers")
  local s = H.run(1)
  for i, uid in ipairs(mon_uids) do
    s:ok("catch", "anna", { uid = uid, area = { key = tostring(i), name = "G" .. i } })
  end
  if dead_uid then s:ok("faint", "anna", { uid = dead_uid }) end
  return s.state
end

T.test("Unbekannte ROM: Lesemodus, keine Schreibzugriffe, Meldung im Overlay", function()
  local app, emu = make_app({ game_code = "ZZZZ" })
  T.ok(app.read_only)
  T.eq(app.reader, nil)
  local lines = app:lines()
  T.ok(lines[2].text:find("LESEMODUS"))
  T.ok(lines[2].text:find("Unbekannte ROM"))
  T.no(app.guard:can_write("party"))
end)

T.test("Bekannte Edition ohne Profil: Lesemodus mit Namen", function()
  local app = make_app({ game_code = "APAD" })
  T.ok(app.read_only)
  T.ok(app.profile_msg:find("Perl"))
end)

T.test("Brücke wird automatisch gestartet", function()
  local _, _, _, _, launched = make_app()
  T.eq(#launched, 1)
  T.eq(launched[1].url, "wss://x/ws")
  T.eq(launched[1].dir, "/proj/bridge/exchange")
  local cmd = Launcher.command({ root = "C:/proj", url = "wss://x/ws", dir = "C:/proj/bridge/exchange", windows = true })
  T.ok(cmd:find('start "Soul%-Link%-Brücke" /MIN "node" "C:\\proj\\bridge\\bridge.js" %-%-url "wss://x/ws"'))
end)

T.test("Anmeldung, Spielzustand melden, totes Monster auf 0 KP setzen, Sperre im Overlay", function()
  local app, emu, mem, clock = make_app()
  -- zwei Monster im Team
  emu.write32(0x02002000 - 8, 6)
  emu.write32(0x02002000 - 4, 2)
  write_bytes(emu, 0x02002000, party_mon(305419896, 20))
  write_bytes(emu, 0x02002000 + 236, party_mon(2882400001, 25))
  emu.write16(0x02003000, 412)
  emu.write8(0x02003004, 3) -- zwei Orden (Bits 0 und 1)
  emu.write16(0x02003008, 5)
  local uid_a = P.uid({ pid = 305419896, tid = 1, sid = 2 })
  local uid_b = P.uid({ pid = 2882400001, tid = 1, sid = 2 })

  local state = server_state(uid_a, { uid_a, uid_b })
  deliver(app, mem, {
    { op = "welcome", player = "anna", last_seq = 0 },
    { op = "state", state = state, stats = { anna = { deaths = 1, dragged = 0 } } },
  })
  app:tick()
  T.eq(app.client.player, "anna")
  T.ok(app.client:online())
  -- Ereignisse wurden gemeldet (status mit Gebiet/Orden, Team)
  local sent = outbox(mem)
  local status, party
  for _, m in ipairs(sent) do
    if m.op == "event" and m.event.type == "status" then status = m.event end
    if m.op == "event" and m.event.type == "party" then party = m.event end
  end
  T.eq(status.area.key, "412")
  T.eq(status.badges, 2)
  T.eq(status.has_balls, true)
  T.eq(#party.mons, 2)
  -- totes Monster auf 0 KP gesetzt (verschlüsselt, Prüfsumme gültig)
  local back = P.parse(P.decrypt(emu.read_bytes(0x02002000, 236)), 4)
  T.eq(back.uid, uid_a)
  T.eq(back.hp, 0)
  T.ok(back.valid)
  local other = P.parse(P.decrypt(emu.read_bytes(0x02002000 + 236, 236)), 4)
  T.eq(other.hp, 25)
  -- Sicherung vor dem ersten Schreiben
  T.eq(mem.files["bk/D_orden2_vor-schreiben.dsv"], "SAVE")
  -- Sperre: totes Monster im Team
  T.ok(app.plan.lock)
  local text = {}
  for _, l in ipairs(app:lines()) do text[#text + 1] = l.text end
  local all = table.concat(text, "\n")
  T.ok(all:find("Tot, muss in die Box"), all)
  T.ok(all:find("Tode: Anna 1"), all)
  T.ok(all:find("Level%-Cap: 14"), all) -- Server-Zustand: noch 0 Orden
  -- Frame mit Sperre setzt die Tastenmaske
  emu.frame_no = 1
  app:frame()
  T.eq(emu.joypad.up, false)
end)

T.test("Schreiben abgeschaltet: KP bleiben, obwohl das Monster tot ist", function()
  local app, emu, mem = make_app({ write = false })
  emu.write32(0x02002000 - 8, 6)
    emu.write32(0x02002000 - 4, 1)
  write_bytes(emu, 0x02002000, party_mon(305419896, 20))
  local uid_a = P.uid({ pid = 305419896, tid = 1, sid = 2 })
  deliver(app, mem, {
    { op = "welcome", player = "anna", last_seq = 0 },
    { op = "state", state = server_state(uid_a, { uid_a, "x2" }) },
  })
  app:tick()
  T.eq(P.parse(P.decrypt(emu.read_bytes(0x02002000, 236)), 4).hp, 20)
end)

T.test("Ungetestete Adresse im Profil: kein Schreiben", function()
  local app, emu, mem = make_app()
  PROFILE.addresses.party.tested = false
  local ok = pcall(function()
    emu.write32(0x02002000 - 8, 6)
    emu.write32(0x02002000 - 4, 1)
    write_bytes(emu, 0x02002000, party_mon(305419896, 20))
    local uid_a = P.uid({ pid = 305419896, tid = 1, sid = 2 })
    deliver(app, mem, {
      { op = "welcome", player = "anna", last_seq = 0 },
      { op = "state", state = server_state(uid_a, { uid_a, "x2" }) },
    })
    app:tick()
    T.eq(P.parse(P.decrypt(emu.read_bytes(0x02002000, 236)), 4).hp, 20)
  end)
  PROFILE.addresses.party.tested = true
  T.ok(ok)
end)

T.test("Abwesenheitsliste: Anzeige, Sperre, Bestätigung per Taste", function()
  local app, emu, mem = make_app()
  deliver(app, mem, {
    { op = "welcome", player = "anna", last_seq = 0 },
    { op = "state", state = server_state(nil, { "m1" }) },
    { op = "effects", effects = { { type = "absence_report", player = "anna",
      deaths = { { label = "Bidiza", by = "Staralili (Ben)" } } } } },
  })
  app:tick()
  T.ok(app.absence)
  T.ok(app.plan.lock)
  local found = false
  for _, l in ipairs(app:lines()) do if l.text:find("Bidiza") then found = true end end
  T.ok(found)
  emu.pressed = { J = true }
  app:frame()
  T.eq(app.absence, nil)
  local last = outbox(mem)
  T.eq(last[#last].event.type, "ack_absence")
end)

T.test("Overlay per Taste ein- und ausblenden", function()
  local app, emu = make_app()
  emu.pressed = { O = true }
  app:frame()
  T.no(app.show.overlay)
  app:frame() -- gehalten: keine erneute Umschaltung
  T.no(app.show.overlay)
  emu.pressed = {}
  app:frame()
  emu.pressed = { O = true }
  app:frame()
  T.ok(app.show.overlay)
  app:draw()
  T.ok(#emu.texts > 0)
end)

T.test("Lobby: Run per Taste starten, Einstellungen aus config.lua", function()
  local app, emu, mem = make_app()
  local E = require("core.engine")
  local st = E.new_state("ABC")
  E.apply(st, { type = "join", player = "anna", t = 1 })
  deliver(app, mem, { { op = "welcome", player = "anna", last_seq = 0 }, { op = "state", state = st } })
  app:tick()
  local found = false
  for _, l in ipairs(app:lines()) do if l.text:find("Run starten") then found = true end end
  T.ok(found)
  emu.pressed = { N = true }
  app:frame()
  local sent = outbox(mem)
  T.eq(sent[#sent - 1].event.type, "set_settings")
  T.eq(sent[#sent - 1].event.preset, "hardcore")
  T.eq(sent[#sent].event.type, "start_run")
end)

T.test("Abstimmung per Taste", function()
  local app, emu, mem = make_app()
  local H = require("core.helpers")
  local s = H.run(2)
  s:ok("propose", "ben", { kind = "reset_counters" })
  s.state.players.anna = s.state.players.anna -- anna ist der Script-Spieler
  deliver(app, mem, { { op = "welcome", player = "anna", last_seq = 0 }, { op = "state", state = s.state } })
  app:tick()
  local found = false
  for _, l in ipairs(app:lines()) do if l.text:find("Abstimmung: Todeszähler zurücksetzen") then found = true end end
  T.ok(found)
  emu.pressed = { Y = true }
  app:frame()
  local sent = outbox(mem)
  T.eq(sent[#sent].event.type, "vote")
  T.eq(sent[#sent].event.accept, true)
  T.eq(sent[#sent].event.id, "v1")
end)

T.test("Solo-Modus im Script: ohne Brücke, Run läuft, Ereignisse werden lokal angewendet", function()
  package.loaded["profiles.TEST"] = PROFILE
  local emu = Emu.fake({ game_code = "TEST" })
  local mem = FS.memory()
  local launched = 0
  local cfg = { mode = "solo", player_name = "Tom", lobby_code = "X", write_enabled = false, hotkeys = {},
    lobby_settings = { preset = "locker" } }
  local app = App.new({ config = cfg, emu = emu, fs = mem, root = "/proj", now = function() return 1000 end,
    launch = function() launched = launched + 1 end })
  T.eq(launched, 0)
  emu.write32(0x02002000 - 8, 6)
  emu.write32(0x02002000 - 4, 1)
  write_bytes(emu, 0x02002000, party_mon(305419896, 20))
  emu.write16(0x02003000, 412)
  emu.write16(0x02003008, 5)
  app:tick()
  app:tick()
  local st = app.client.state
  T.eq(st.phase, "running")
  T.eq(st.settings.preset, "locker")
  T.eq(st.players.tom.area.key, "412")
  T.eq(#st.players.tom.party, 1)
  local all = {}
  for _, l in ipairs(app:lines()) do all[#all + 1] = l.text end
  T.ok(table.concat(all, "\n"):find("Solo %(ohne Server%)"))
  T.no(table.concat(all, "\n"):find("AUFHOL"), "Solo hat nie Aufhol-Modus")
end)

T.test("Aufhol-Kasten mit Hintergrund, Gruppen-Ansicht per Taste", function()
  local app, emu, mem = make_app()
  local H = require("core.helpers")
  local s = H.run(2)
  H.catch_all(s, H.AREA1, "a")
  s:ok("status", "ben", { badges = 1, area = H.AREA2 })
  s:ok("offline", "ben")
  s.state.players.anna.area = { key = "201", name = "Route 201" }
  deliver(app, mem, { { op = "welcome", player = "anna", last_seq = 0 },
    { op = "state", state = s.state, server_time = s.t + 125000 } })
  app:tick()
  local lines = app:lines()
  local boxed, texts = 0, {}
  for _, l in ipairs(lines) do
    if l.bg == "gelb" then boxed = boxed + 1 end
    texts[#texts + 1] = l.text
  end
  local all = table.concat(texts, "\n")
  T.ok(boxed >= 5, all)
  T.ok(all:find("AUFHOL%-MODUS"), all)
  T.ok(all:find("Ben offline seit 2 min"), all)
  T.ok(all:find("Orden: frei bis 1"), all)
  T.ok(all:find("Kein Gebiet zum Fangen frei"), all)
  for _, l in ipairs(lines) do T.ok(#l.text <= 42 + 2, "Zeile zu lang: " .. l.text) end
  emu.pressed = { H = true }
  app.cfg.hotkeys.groups = "H"
  app:frame()
  T.ok(app.show.groups)
  local found = false
  for _, l in ipairs(app:lines()) do if l.text:find("Route 201: Arta / Arta %[komplett%]") then found = true end end
  T.ok(found)
  emu.texts = {}
  app:draw()
  T.ok(#emu.texts > 5)
end)

T.test("Eingabe-Aufnahme per Taste speichert eine Datei fürs Profil", function()
  local app, emu, mem = make_app()
  app.cfg.hotkeys.record = "K"
  emu.pressed = { K = true }
  app:frame()
  T.ok(app.recorder)
  emu.pressed = {}
  emu.pad = { A = true }
  app:frame()
  emu.pad = {}
  app:frame()
  emu.pressed = { K = true }
  app:frame()
  T.eq(app.recorder, nil)
  local src = mem.files["/proj/local/prolog_aufnahme_TEST.lua"]
  T.ok(src and src:find('keys = "A", frames = 1'), tostring(src))
end)

T.test("Selbsttest der Schreibfunktionen", function()
  T.ok(App.selftest())
end)

T.test("Lobby: Vorlage vom Server, Änderungen, Teams und Speichern als eigene Vorlage", function()
  local app, emu, mem = make_app()
  app.cfg.lobby_settings = { template = "Meine", changes = { grace = false }, save_as = "Neu",
    teams = { { "Anna", "Ben" }, { "Cem" } } }
  local E = require("core.engine")
  local st = E.new_state("ABC")
  for _, p in ipairs({ "anna", "ben", "cem" }) do E.apply(st, { type = "join", player = p, t = 1 }) end
  deliver(app, mem, { { op = "welcome", player = "anna", last_seq = 0, templates = { Meine = { level_cap = false } } },
    { op = "state", state = st } })
  app:tick()
  emu.pressed = { N = true }
  app:frame()
  local sent = outbox(mem)
  local kinds = {}
  for _, m in ipairs(sent) do
    if m.op == "event" then kinds[#kinds + 1] = m.event.type end
    if m.op == "template_save" then
      kinds[#kinds + 1] = "template_save"
      T.eq(m.name, "Neu")
      T.eq(m.settings.level_cap, false)
      T.eq(m.settings.grace, false)
    end
  end
  local tail = {}
  for i = #kinds - 4, #kinds do tail[#tail + 1] = kinds[i] end
  T.eq(tail, { "set_settings", "set_settings", "template_save", "set_teams", "start_run" })
  for _, m in ipairs(sent) do
    if m.op == "event" and m.event.type == "set_teams" then T.eq(m.event.teams, { { "anna", "ben" }, { "cem" } }) end
  end
end)

T.test("Lobby: unbekannte Vorlage -> Hinweis, kein Start", function()
  local app, emu, mem = make_app()
  app.cfg.lobby_settings = { template = "Gibtsnicht" }
  local E = require("core.engine")
  local st = E.new_state("ABC")
  E.apply(st, { type = "join", player = "anna", t = 1 })
  deliver(app, mem, { { op = "welcome", player = "anna", last_seq = 0 }, { op = "state", state = st } })
  app:tick()
  local before = #outbox(mem)
  emu.pressed = { N = true }
  app:frame()
  T.eq(#outbox(mem), before)
  T.ok(app.messages[#app.messages].text:find("Gibtsnicht"))
end)

T.test("Level-Cap, Sonderbonbons und Namen/Typen aus der ROM im Prüfzyklus", function()
  local GDT = require("mem.gamedata_test")
  local GD = require("mem.gamedata")
  local profile = {
    game_code = "TEST", name = "Testspiel", gen = 4,
    addresses = {
      party = { addr = 0x02002000, tested = true },
      party_count = { rel = "party", offset = -4, width = 32, tested = true },
      bag_items = { addr = 0x02005000, slots = 10, tested = true },
    },
    gym_levels = { 14, 22, tested = true },
    items = { rare_candy = 50 },
    gamedata = GDT.CFG,
  }
  package.loaded["profiles.TEST"] = profile
  local emu = Emu.fake({ game_code = "TEST" })
  local mem = FS.memory()
  local cfg = { mode = "solo", player_name = "Tom", lobby_code = "X", write_enabled = true, hotkeys = {},
    lobby_settings = { preset = "klassisch" } }
  local app = App.new({ config = cfg, emu = emu, fs = mem, root = "/proj", now = function() return 1000 end,
    rom = GDT.fake_rom() })
  T.ok(app.gamedata, "Spieldaten geladen")
  -- Bisasam (Art 1, mittellangsam) Level 14 mit zu viel Erfahrung
  local b = {}
  for i = 1, 236 do b[i] = 0 end
  P.set_u32(b, 0, 99991)
  P.set_u16(b, 0x08, 1)
  P.set_u32(b, 0x10, GD.exp_for_level(3, 15) - 1)
  b[0x8C + 1] = 14
  P.set_u16(b, 0x8E, 30)
  P.set_u16(b, 0x90, 40)
  P.set_u16(b, 0x06, P.checksum(b))
  emu.write32(0x02002000 - 8, 6)
  emu.write32(0x02002000 - 4, 1)
  write_bytes(emu, 0x02002000, P.encrypt(b))
  for _ = 1, 30 do app:tick() end
  local m = P.parse(P.decrypt(emu.read_bytes(0x02002000, 236)), 4)
  T.eq(m.exp, GD.exp_for_level(3, 14), "Erfahrung auf Level 14 gedeckelt")
  T.ok(m.valid)
  -- Sonderbonbons im Beutel
  T.eq(emu.read16(0x02005000), 50)
  T.eq(emu.read16(0x02005002), 999)
  -- Name und Typen aus der ROM in Zustand und Gruppen-Ansicht
  local st = app.client.state
  local mon = st.players.tom.mons[m.uid]
  T.eq(mon.species_name, "Bisasam")
  T.eq(mon.types, { "Pflanze", "Gift" })
  T.eq(mon.family, 1)
end)

T.test("Vorschlag per Taste V aus config.lua", function()
  local app, emu, mem = make_app()
  app.cfg.hotkeys.propose = "V"
  local H = require("core.helpers")
  local s = H.run(2)
  deliver(app, mem, { { op = "welcome", player = "anna", last_seq = 0 }, { op = "state", state = s.state } })
  app:tick()
  emu.pressed = { V = true }
  app:frame()
  T.ok(app.messages[#app.messages].text:find("Kein Vorschlag"))
  emu.pressed = {}
  app:frame()
  app.cfg.proposal = { kind = "settings", changes = { level_cap = false } }
  emu.pressed = { V = true }
  app:frame()
  local sent = outbox(mem)
  local last = sent[#sent].event
  T.eq(last.type, "propose")
  T.eq(last.kind, "settings")
  T.eq(last.payload.changes.level_cap, false)
end)

T.test("Hinweis zu Kampfbeginn: zählt die Begegnung? (einmal pro Kampf)", function()
  local app, emu, mem = make_app()
  local H = require("core.helpers")
  local s = H.run(1)
  deliver(app, mem, { { op = "welcome", player = "anna", last_seq = 0 }, { op = "state", state = s.state } })
  local battle = { wild = true, opponent = { species = 16, shiny = false } }
  app.reader.snapshot = function() return { t = 0, party = {}, area = { key = "201", name = "Route 201" }, battle = battle } end
  app:tick()
  local found = 0
  for _, m in ipairs(app.messages) do if m.text:find("Erste Begegnung in 201") or m.text:find("Erste Begegnung in Route 201") then found = found + 1 end end
  T.eq(found, 1)
  app:tick()
  local again = 0
  for _, m in ipairs(app.messages) do if m.text:find("Erste Begegnung") then again = again + 1 end end
  T.eq(again, 1, "nur einmal pro Kampf")
  battle.opponent.shiny = true
  app.reader.snapshot = function() return { t = 0, party = {}, area = { key = "201", name = "Route 201" } } end
  app:tick()
  app.reader.snapshot = function() return { t = 0, party = {}, area = { key = "201", name = "Route 201" }, battle = battle } end
  app:tick()
  T.ok(app.messages[#app.messages].text:find("Schillernd"))
end)

T.test("Endbildschirm mit Statistik im Overlay", function()
  local app, emu, mem = make_app()
  local H = require("core.helpers")
  local s = H.run(1)
  H.catch_all(s, H.AREA1, "a")
  s:ok("faint", "anna", { uid = "anna-a" })
  deliver(app, mem, { { op = "welcome", player = "anna", last_seq = 0 }, { op = "state", state = s.state } })
  app:tick()
  local all = {}
  for _, l in ipairs(app:lines()) do all[#all + 1] = l.text end
  local text = table.concat(all, "\n")
  T.ok(text:find("RUN BEENDET: VERLOREN"), text)
  T.ok(text:find("Tode: Anna 1"), text)
  T.ok(text:find("neuer Versuch"), text)
end)

T.test("Live-Rangliste im Overlay bei mehreren Teams, eigenes Team markiert", function()
  local app, emu, mem = make_app()
  local H = require("core.helpers")
  local s = H.run(2, { teams = { { "anna" }, { "ben" } } })
  H.catch_all(s, H.AREA1, "a")
  s:ok("status", "ben", { badges = 1 })
  deliver(app, mem, { { op = "welcome", player = "anna", last_seq = 0 }, { op = "state", state = s.state } })
  app:tick()
  local found, mine = false, false
  for _, l in ipairs(app:lines()) do
    if l.text:find("Rangliste %(Rennen%)") then found = true end
    if l.text:find("^>2%. Anna: 0 Orden, 1 lebend, 0 Tode$") then mine = true end
  end
  T.ok(found)
  T.ok(mine)
end)

T.test("Lobby zeigt Teams und Hinweis bei ungleicher Größe", function()
  local app, emu, mem = make_app()
  local H = require("core.helpers")
  local s = H.run(3, { start = false, teams = { { "anna", "ben" }, { "cem" } } })
  deliver(app, mem, { { op = "welcome", player = "anna", last_seq = 0 }, { op = "state", state = s.state } })
  app:tick()
  local text = {}
  for _, l in ipairs(app:lines()) do text[#text + 1] = l.text end
  local all = table.concat(text, "\n")
  T.ok(all:find("Teams: Anna & Ben vs%. Cem"), all)
  T.ok(all:find("ungleich groß"), all)
end)
