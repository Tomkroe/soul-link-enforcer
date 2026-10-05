-- Netz-Client mit Datei-Transport gegen eine simulierte Brücke (Speicher-Dateisystem).
local T = require("lib.t")
local json = require("lib.json")
local FS = require("net.fs")
local Transport = require("net.transport_file")
local Client = require("net.client")

-- Simulierte Brücke: liest out/, schreibt in/ – wie bridge/bridge.js.
local function fake_bridge(mem, dir)
  local b = { in_n = 1, sent = {}, connected = false }
  function b:to_script(msg)
    mem.files[string.format("%s/in/%08d.json", dir, self.in_n)] = json.encode(msg)
    self.in_n = self.in_n + 1
  end
  function b:pump()
    local names = {}
    for path in pairs(mem.files) do
      if path:find(dir .. "/out/", 1, true) == 1 then names[#names + 1] = path end
    end
    table.sort(names)
    for _, path in ipairs(names) do
      local msg = json.decode(mem.files[path])
      mem.files[path] = nil
      if msg.op == "bridge_reset" then
        for p in pairs(mem.files) do
          if p:find(dir .. "/in/", 1, true) == 1 then mem.files[p] = nil end
        end
        self.in_n = 1
        self:to_script({ op = "bridge", reset = msg.nonce, connected = self.connected })
      elseif self.connected then
        self.sent[#self.sent + 1] = msg
      end
    end
  end
  return b
end

local function setup(opts)
  opts = opts or {}
  local mem = opts.mem or FS.memory()
  local clock = { t = 0 }
  local bridge = fake_bridge(mem, "ex")
  local tr = Transport.new({ dir = "ex", fs = mem, session = opts.session or "000000000001", nonce = opts.nonce or "n1" })
  local c = Client.new({ transport = tr, name = "Anna", lobby = "ABC", now = function() return clock.t end,
    fs = mem, queue_path = "local/queue.json", stats_path = "local/stats.json" })
  return { mem = mem, clock = clock, bridge = bridge, tr = tr, c = c }
end

local function find_sent(sent, op)
  for _, m in ipairs(sent) do if m.op == op then return m end end
end

T.test("Brücke: alte Dateien werden bis zur Reset-Bestätigung ignoriert", function()
  local mem = FS.memory()
  mem.files["ex/in/00000001.json"] = json.encode({ op = "state", state = { alt = true } })
  local s = setup({ mem = mem })
  s.c:poll()
  T.eq(s.c.state, nil)
  T.no(s.tr.synced)
  s.bridge:pump()
  s.c:poll()
  T.ok(s.tr.synced)
  T.ok(s.c.bridge_up)
  T.eq(s.c:status_text(), "Keine Verbindung zum Server")
end)

T.test("Anmeldung nach Verbindungsaufbau, Ereignisse mit Bestätigung", function()
  local s = setup()
  s.bridge:pump(); s.c:poll()
  local seq = s.c:send_event({ type = "status", badges = 1 })
  T.eq(seq, 1)
  T.eq(#s.c.queue, 1, "vor der Anmeldung nur in der Warteschlange")
  s.bridge.connected = true
  s.bridge:to_script({ op = "bridge", connected = true })
  s.c:poll()
  s.bridge:pump()
  local hello = find_sent(s.bridge.sent, "hello")
  T.eq(hello.lobby, "ABC")
  T.eq(hello.name, "Anna")
  T.eq(hello.role, "player")
  s.bridge:to_script({ op = "welcome", player = "anna", last_seq = 0 })
  s.c:poll()
  s.bridge:pump()
  local ev = find_sent(s.bridge.sent, "event")
  T.eq(ev.seq, 1)
  T.eq(ev.event.badges, 1)
  T.eq(s.c:status_text(), "Verbunden (1 offen)")
  s.bridge:to_script({ op = "ack", seq = 1 })
  s.c:poll()
  T.eq(#s.c.queue, 0)
  T.eq(s.c:status_text(), "Verbunden")
end)

T.test("Zustand, Effekte und lokale Statistik werden übernommen", function()
  local s = setup()
  s.bridge:pump(); s.c:poll()
  s.bridge:to_script({ op = "state", state = { phase = "running" }, derived = { x = 1 }, stats = { anna = { deaths = 3 } } })
  s.bridge:to_script({ op = "effects", effects = { { type = "kill", player = "anna", uid = "u1" } } })
  s.c:poll()
  T.eq(s.c.state.phase, "running")
  T.eq(s.c.stats.anna.deaths, 3)
  T.eq(json.decode(s.mem.files["local/stats.json"]).anna.deaths, 3)
  local eff = s.c:take_effects()
  T.eq(#eff, 1)
  T.eq(eff[1].uid, "u1")
  T.eq(#s.c:take_effects(), 0)
end)

T.test("Wiedereinstieg: Warteschlange übersteht Script-Neustart, Bestätigtes wird verworfen", function()
  local s = setup()
  s.bridge:pump(); s.c:poll()
  s.c:send_event({ type = "catch", uid = "a" })
  s.c:send_event({ type = "catch", uid = "b" })
  s.c:send_event({ type = "faint", uid = "a" })
  -- Script stürzt ab. Neustart mit demselben Dateisystem und neuer Sitzung.
  local s2 = setup({ mem = s.mem, session = "000000000002", nonce = "n2" })
  T.eq(#s2.c.queue, 3)
  T.eq(s2.c.seq, 3)
  s2.bridge:pump(); s2.c:poll()
  s2.bridge.connected = true
  s2.bridge:to_script({ op = "bridge", connected = true })
  s2.c:poll()
  -- Server hatte 1 und 2 schon bestätigt
  s2.bridge:to_script({ op = "welcome", player = "anna", last_seq = 2 })
  s2.c:poll()
  s2.bridge:pump()
  local events = {}
  for _, m in ipairs(s2.bridge.sent) do if m.op == "event" then events[#events + 1] = m end end
  T.eq(#events, 1)
  T.eq(events[1].seq, 3)
  T.eq(s2.c:send_event({ type = "status" }), 4)
end)

T.test("Sequenznummer folgt dem Server, wenn die lokale Datei fehlt", function()
  local s = setup()
  s.bridge:pump(); s.c:poll()
  s.bridge.connected = true
  s.bridge:to_script({ op = "bridge", connected = true })
  s.bridge:to_script({ op = "welcome", player = "anna", last_seq = 41 })
  s.c:poll()
  T.eq(s.c:send_event({ type = "status" }), 42)
end)

T.test("Herzschlag: Ping alle 5 Sekunden", function()
  local s = setup()
  s.bridge:pump(); s.c:poll()
  s.bridge.connected = true
  s.clock.t = 6000
  s.c:poll()
  s.bridge:pump()
  T.ok(find_sent(s.bridge.sent, "ping"))
end)

T.test("Brücke fehlt: verständliche Meldung", function()
  local s = setup()
  s.c:poll()
  T.eq(s.c:status_text(), "Starte Brücke ...")
  s.clock.t = 9000
  T.ok(s.c:status_text():find("Brücke antwortet nicht"))
end)

T.test("Verbindungsverlust und Fehler werden angezeigt", function()
  local s = setup()
  s.bridge:pump(); s.c:poll()
  s.bridge:to_script({ op = "bridge", connected = true })
  s.bridge:to_script({ op = "welcome", player = "anna", last_seq = 0 })
  s.bridge:to_script({ op = "bridge", connected = false })
  s.c:poll()
  T.eq(s.c:status_text(), "Keine Verbindung zum Server")
  s.bridge:to_script({ op = "error", fatal = true, message = "Lobby voll" })
  s.c:poll()
  T.eq(s.c:status_text(), "Fehler: Lobby voll")
end)

T.test("Echtes Dateisystem (nur natives Lua)", function()
  if not io.open then T.skip("kein io.open (fengari)") end
  local FSr = require("net.fs")
  local base = os.tmpname()
  os.remove(base)
  local path = base .. "_slink.json"
  T.ok(FSr.write_atomic(path, "{\"a\":1}"))
  T.eq(FSr.read(path), "{\"a\":1}")
  T.ok(FSr.write_atomic(path, "{\"a\":2}"), "Überschreiben")
  T.eq(FSr.read(path), "{\"a\":2}")
  FSr.remove(path)
  T.no(FSr.exists(path))
end)
