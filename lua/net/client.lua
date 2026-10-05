-- Verbindung zum Vermittlungsserver: Anmeldung, Ereignis-Warteschlange mit Bestätigung,
-- Herzschlag, Empfang von Zustand und Effekten. Unabhängig vom Transport (Datei-Brücke oder Socket).
--
-- Wiedereinstieg ohne Datenverlust: Unbestätigte Ereignisse liegen in einer lokalen Datei und
-- werden nach jedem (Wieder-)Verbinden erneut gesendet. Der Server erkennt Doppelte an der
-- Sequenznummer und meldet in "welcome" die letzte bestätigte Nummer.

local json = require("lib.json")

local Client = {}
Client.__index = Client

Client.PING_MS = 5000
Client.BRIDGE_TIMEOUT_MS = 8000

--- opts: transport, name, lobby, now (ms), fs (für Warteschlange), queue_path (optional)
function Client.new(opts)
  local self = setmetatable({}, Client)
  self.transport = opts.transport
  self.name = opts.name
  self.lobby = opts.lobby
  self.now = opts.now
  self.fs = opts.fs
  self.queue_path = opts.queue_path
  self.stats_path = opts.stats_path
  self.queue = {}          -- { {seq, event}, ... } unbestätigt
  self.seq = 0
  self.bridge_up = false   -- Brücke hat sich gemeldet
  self.connected = false   -- Brücke ist mit dem Server verbunden
  self.welcomed = false    -- Server hat die Anmeldung bestätigt
  self.player = nil
  self.state = nil
  self.derived = nil
  self.stats = nil
  self.effects = {}        -- empfangene Effekte, vom Hauptscript abzuholen
  self.errors = {}         -- Fehlermeldungen (für das Overlay)
  self.fatal = nil
  self.started = self.now()
  self.last_ping = 0
  self.last_rx = 0
  self:load_queue()
  return self
end

function Client:load_queue()
  if not (self.fs and self.queue_path) then return end
  local text = self.fs.read(self.queue_path)
  if not text then return end
  local ok, data = pcall(json.decode, text)
  if ok and type(data) == "table" and data.lobby == self.lobby and data.name == self.name then
    self.queue = data.queue or {}
    self.seq = data.seq or 0
  end
end

function Client:save_queue()
  if not (self.fs and self.queue_path) then return end
  self.fs.write_atomic(self.queue_path, json.encode(json.object({
    lobby = self.lobby, name = self.name, seq = self.seq, queue = json.array(self.queue),
  })))
end

--- Reiht ein Spielereignis ein (wird gesendet, sobald verbunden; bleibt bis zur Bestätigung).
function Client:send_event(ev)
  self.seq = self.seq + 1
  local item = { seq = self.seq, event = ev }
  self.queue[#self.queue + 1] = item
  self:save_queue()
  if self.welcomed then
    self.transport:send({ op = "event", seq = item.seq, event = ev })
  end
  return item.seq
end

function Client:resend_all()
  for _, item in ipairs(self.queue) do
    self.transport:send({ op = "event", seq = item.seq, event = item.event })
  end
end

function Client:handle(msg)
  local op = msg.op
  if op == "bridge" then
    self.bridge_up = true
    if msg.connected ~= nil then
      local was = self.connected
      self.connected = msg.connected and true or false
      if self.connected and not was then
        self.welcomed = false
        self.transport:send({ op = "hello", role = "player", lobby = self.lobby, name = self.name })
      elseif not self.connected then
        self.welcomed = false
      end
    end
  elseif op == "welcome" then
    self.welcomed = true
    self.player = msg.player
    local last = msg.last_seq or 0
    -- Bereits bestätigte Ereignisse verwerfen, Rest erneut senden.
    local rest = {}
    for _, item in ipairs(self.queue) do
      if item.seq > last then rest[#rest + 1] = item end
    end
    self.queue = rest
    if self.seq < last then self.seq = last end
    self:save_queue()
    self:resend_all()
  elseif op == "ack" then
    local rest = {}
    for _, item in ipairs(self.queue) do
      if item.seq ~= msg.seq then rest[#rest + 1] = item end
    end
    self.queue = rest
    self:save_queue()
    if msg.error then self.errors[#self.errors + 1] = msg.error end
  elseif op == "state" then
    self.state = msg.state
    self.derived = msg.derived
    self.stats = msg.stats
    if self.fs and self.stats_path and msg.stats then
      self.fs.write_atomic(self.stats_path, json.encode(msg.stats))
    end
  elseif op == "effects" then
    for _, e in ipairs(msg.effects or {}) do self.effects[#self.effects + 1] = e end
  elseif op == "error" then
    self.errors[#self.errors + 1] = msg.message
    if msg.fatal then self.fatal = msg.message end
  end
end

--- Einmal pro Prüfzyklus aufrufen (z. B. alle 10 Frames).
function Client:poll()
  local now = self.now()
  for _, msg in ipairs(self.transport:receive()) do
    self.last_rx = now
    self:handle(msg)
  end
  if self.transport.synced and now - self.last_ping >= Client.PING_MS then
    self.last_ping = now
    -- Ping hält Server-Herzschlag und Brücke am Leben (die Brücke beendet sich ohne Pings).
    self.transport:send({ op = "ping" })
  end
end

--- Holt empfangene Effekte ab (und leert die Liste).
function Client:take_effects()
  local e = self.effects
  self.effects = {}
  return e
end

--- Verbindungsstatus als Text für das Overlay.
function Client:status_text()
  if self.fatal then return "Fehler: " .. self.fatal end
  if not self.bridge_up then
    if self.now() - self.started > Client.BRIDGE_TIMEOUT_MS then
      return "Brücke antwortet nicht (läuft bridge.js?)"
    end
    return "Starte Brücke ..."
  end
  if not self.connected then return "Keine Verbindung zum Server" end
  if not self.welcomed then return "Anmeldung ..." end
  if #self.queue > 0 then return "Verbunden (" .. #self.queue .. " offen)" end
  return "Verbunden"
end

function Client:online()
  return self.welcomed
end

return Client
