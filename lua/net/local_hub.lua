-- Solo-Modus ohne Server: ein lokaler Vermittler im Script, der dasselbe Protokoll spricht wie der
-- Server (hello/welcome, event/ack, state, effects) und dieselbe Regel-Engine (lua/core) ausführt.
-- Zustand und Todeszähler liegen als JSON in local/ und überstehen Neustarts.
-- Für den Netz-Client (net/client.lua) sieht er aus wie ein Transport.

local json = require("lib.json")
local E = require("core.engine")

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
  self.stats_path = opts.dir .. "/todeszaehler.json"
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
  local stext = self.fs.read(self.stats_path)
  local sok, stats = pcall(json.decode, stext or "")
  self.stats = (sok and type(stats) == "table") and stats or json.object()
end

function Hub:save()
  self.fs.write_atomic(self.state_path, json.encode(json.object({ state = self.state, acks = self.acks })))
  self.fs.write_atomic(self.stats_path, json.encode(self.stats))
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
  self:push({ op = "state", state = self.state, stats = self:my_stats(), server_time = self.now() })
end

function Hub:handle_effects(effects)
  for _, e in ipairs(effects) do
    if e.type == "stat" then
      local s = self.stats[e.player]
      if not s then
        s = { name = self.name, deaths = 0, dragged = 0, attempts = 0, wins = 0 }
        self.stats[e.player] = s
      end
      s[e.key] = (s[e.key] or 0) + e.delta
    elseif e.type == "reset_stats" then
      for _, pid in ipairs(e.players) do
        if self.stats[pid] then self.stats[pid].deaths, self.stats[pid].dragged = 0, 0 end
      end
    end
  end
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
    if self.settings and self.settings.preset then self:apply({ type = "set_settings", preset = self.settings.preset }) end
    if self.settings and self.settings.changes then self:apply({ type = "set_settings", changes = self.settings.changes }) end
    self:apply({ type = "start_run" })
  end
  self:save()
  self:push({ op = "welcome", role = "player", lobby = self.code, player = self.pid, last_seq = self.acks })
  self:push_state()
end

--- Nachricht vom Client.
function Hub:send(msg)
  if msg.op == "hello" then
    self:hello()
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
