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
    party_count = { addr = 0x1000, tested = true },
    party = { addr = 0x2000, tested = true, battle_safe = false },
    area_id = { addr = 0x3000, tested = true },
    badges = { addr = 0x3004, tested = true },
    bag_balls = { addr = 0x3008, tested = true },
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
  P.set_u16(b, 0x8C, 10)
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
    bridge = { autostart = true }, hotkeys = { overlay = "O", confirm = "J", graveyard = "F", areas = "G", pc_pass = "P" },
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
  local app = make_app({ game_code = "CPUD" })
  T.ok(app.read_only)
  T.ok(app.profile_msg:find("Platin"))
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
  emu.write8(0x1000, 2)
  write_bytes(emu, 0x2000, party_mon(305419896, 20))
  write_bytes(emu, 0x2000 + 236, party_mon(2882400001, 25))
  emu.write16(0x3000, 412)
  emu.write8(0x3004, 3) -- zwei Orden (Bits 0 und 1)
  emu.write16(0x3008, 5)
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
  local back = P.parse(P.decrypt(emu.read_bytes(0x2000, 236)), 4)
  T.eq(back.uid, uid_a)
  T.eq(back.hp, 0)
  T.ok(back.valid)
  local other = P.parse(P.decrypt(emu.read_bytes(0x2000 + 236, 236)), 4)
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
  emu.write8(0x1000, 1)
  write_bytes(emu, 0x2000, party_mon(305419896, 20))
  local uid_a = P.uid({ pid = 305419896, tid = 1, sid = 2 })
  deliver(app, mem, {
    { op = "welcome", player = "anna", last_seq = 0 },
    { op = "state", state = server_state(uid_a, { uid_a, "x2" }) },
  })
  app:tick()
  T.eq(P.parse(P.decrypt(emu.read_bytes(0x2000, 236)), 4).hp, 20)
end)

T.test("Ungetestete Adresse im Profil: kein Schreiben", function()
  local app, emu, mem = make_app()
  PROFILE.addresses.party.tested = false
  local ok = pcall(function()
    emu.write8(0x1000, 1)
    write_bytes(emu, 0x2000, party_mon(305419896, 20))
    local uid_a = P.uid({ pid = 305419896, tid = 1, sid = 2 })
    deliver(app, mem, {
      { op = "welcome", player = "anna", last_seq = 0 },
      { op = "state", state = server_state(uid_a, { uid_a, "x2" }) },
    })
    app:tick()
    T.eq(P.parse(P.decrypt(emu.read_bytes(0x2000, 236)), 4).hp, 20)
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

T.test("Selbsttest der Schreibfunktionen", function()
  T.ok(App.selftest())
end)
