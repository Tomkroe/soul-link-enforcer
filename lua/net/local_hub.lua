-- Solo-Modus ohne Server: ein lokaler Vermittler im Script, der dasselbe Protokoll spricht wie der
-- Server (hello/welcome, event/ack, state, effects) und dieselbe Regel-Engine (lua/core) ausführt.
-- Zustand und Todeszähler liegen als JSON in local/ und überstehen Neustarts.
-- Für den Netz-Client (net/client.lua) sieht er aus wie ein Transport.

local json = require("lib.json")
local E = require("core.engine")
local L = require("core.ledger")

local Hub = {}
Hub.__index = Hub

--- opts: fs, dir (local/), name (Spielername), now (ms), lobby (Code, nur zur Anzeige),
---       settings ({ preset, changes } für den Run-Start), auto_start (Standard: true)
function Hub.new(opts)
  local self = setmetatable({}, Hub)
  self.fs = opts.fs
  self.now = opts.now
  self.name = opts.name
  self.pid = tostring(opts.name):lower():gsub("%s+", "_")
  self.code = "SOLO"
  self.state_path = opts.dir .. "/solo_" .. self.pid .. ".json"
  self.ledger_path = opts.dir .. "/bilanz_solo.json"
  self.dir = opts.dir
  self.settings = opts.settings
  self.auto_start = opts.auto_start ~= false
  self.synced = true
  self.label = "Solo (ohne Server)"
  self.outbox = { { op = "bridge", connected = true } }
  self:load()
  return self
end

function Hub:load()
  local text = self.fs.read(self.state_path)
  local ok, data = pcall(json.decode, text or "")
  if ok and type(data) == "table" and data.state then
    self.state = data.state
    self.acks = data.acks or 0
  else
    self.state = E.new_state(self.code)
    self.acks = 0
  end
  local ltext = self.fs.read(self.ledger_path)
  local lok, ledger = pcall(json.decode, ltext or "")
  self.ledger = (lok and type(ledger) == "table" and ledger.players) and ledger or L.new()
  self.stats = self.ledger.players
end

function Hub:save()
  self.fs.write_atomic(self.state_path, json.encode(json.object({ state = self.state, acks = self.acks })))
  self.fs.write_atomic(self.ledger_path, json.encode(self.ledger))
end

function Hub:push(msg)
  self.outbox[#self.outbox + 1] = msg
end

function Hub:my_stats()
  local out = json.object()
  local s = self.stats[self.pid]
  out[self.pid] = s or { name = self.name, deaths = 0, dragged = 0, attempts = 0, wins = 0 }
  return out
end

function Hub:push_state()
  self:push({ op = "state", state = self.state, stats = self:my_stats(), ledger = L.view(self.ledger, { self.pid }),
    server_time = self.now() })
end

function Hub:handle_effects(effects)
  L.apply(self.ledger, effects, { [self.pid] = self.name })
  self.stats = self.ledger.players
end

--- Wendet ein Ereignis an. Rückgabe: Fehlertext oder nil.
function Hub:apply(ev)
  ev.player = self.pid
  ev.t = self.now()
  local effects = E.apply(self.state, ev)
  for _, e in ipairs(effects) do
    if e.type == "error" then return e.text end
  end
  self:handle_effects(effects)
  if #effects > 0 then self:push({ op = "effects", effects = effects }) end
  return nil
end

function Hub:hello()
  self:apply({ type = "join", name = self.name })
  self:apply({ type = "online" })
  if self.state.phase == "lobby" and self.auto_start then
    local tpl = self.settings and self.settings.template and self:templates()[self.settings.template]
    if tpl then self:apply({ type = "set_settings", preset = tpl }) end
    if self.settings and self.settings.preset and not tpl then self:apply({ type = "set_settings", preset = self.settings.preset }) end
    if self.settings and self.settings.changes then self:apply({ type = "set_settings", changes = self.settings.changes }) end
    self:apply({ type = "start_run" })
  end
  self:save()
  self:push({ op = "welcome", role = "player", lobby = self.code, player = self.pid, last_seq = self.acks,
    templates = self:templates() })
  self:push_state()
end

function Hub:templates()
  local ok, t = pcall(json.decode, self.fs.read(self.dir .. "/vorlagen.json") or "")
  return (ok and type(t) == "table") and t or json.object()
end

--- Nachricht vom Client.
function Hub:send(msg)
  if msg.op == "hello" then
    self:hello()
  elseif msg.op == "template_save" then
    local t = self:templates()
    if type(msg.name) == "string" and msg.name ~= "" and type(msg.settings) == "table" then
      t[msg.name] = msg.settings
      self.fs.write_atomic(self.dir .. "/vorlagen.json", json.encode(t))
    end
    self:push({ op = "templates", templates = t })
  elseif msg.op == "ping" then
    self:push({ op = "pong", t = self.now() })
  elseif msg.op == "event" then
    local seq = msg.seq or 0
    if seq > 0 and seq <= self.acks then
      self:push({ op = "ack", seq = seq, duplicate = true })
      return true
    end
    local ev = {}
    for k, v in pairs(msg.event or {}) do ev[k] = v end
    local err = self:apply(ev)
    if seq > 0 then self.acks = seq end
    self:save()
    self:push({ op = "ack", seq = seq, error = err })
    if not err then self:push_state() end
  end
  return true
end

--- Nachrichten an den Client abholen.
function Hub:receive()
  local out = self.outbox
  self.outbox = {}
  return out
end

return Hub
