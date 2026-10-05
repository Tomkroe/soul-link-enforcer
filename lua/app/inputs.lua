-- Eingabe-Automatik: spielt Tastenfolgen ab und nimmt die Eingaben des Spielers auf (für Profile).
-- Rein: liefert pro Frame eine Tastentabelle; app/init.lua übergibt sie an joypad.set.
--
-- Schrittformat (Profil, z. B. prologue.inputs):
--   { keys = "A", frames = 2 }          Taste(n) für n Frames drücken ("A+B" für mehrere)
--   { wait = 30 }                        n Frames nichts drücken
--   { repeat_ = 5, keys = "A", frames = 2, gap = 20 }   mehrfach mit Pause
-- Ein Ablauf endet, wenn alle Schritte gespielt sind oder stop() gerufen wird.

local Inputs = {}
Inputs.__index = Inputs

Inputs.KEYS = { "A", "B", "X", "Y", "L", "R", "start", "select", "up", "down", "left", "right" }

local function parse_keys(spec)
  local t = {}
  for k in tostring(spec or ""):gmatch("[^+]+") do t[k] = true end
  return t
end

--- Wandelt Schritte in eine flache Liste von Frames um (Liste von Tastentabellen).
function Inputs.expand(steps)
  local frames = {}
  local function push(keys, n)
    for _ = 1, n do frames[#frames + 1] = keys end
  end
  for _, st in ipairs(steps or {}) do
    if st.wait then
      push({}, st.wait)
    else
      local times = st.repeat_ or 1
      for i = 1, times do
        push(parse_keys(st.keys), st.frames or 2)
        if st.gap and i < times then push({}, st.gap) end
      end
      push({}, st.release or 1) -- loslassen, damit die nächste Taste als neuer Druck zählt
    end
  end
  return frames
end

function Inputs.new()
  return setmetatable({ queue = nil, pos = 0, name = nil }, Inputs)
end

function Inputs:play(name, steps)
  self.queue = Inputs.expand(steps)
  self.pos = 0
  self.name = name
end

function Inputs:busy()
  return self.queue ~= nil
end

function Inputs:stop()
  self.queue, self.pos, self.name = nil, 0, nil
end

--- Nächster Frame: Tastentabelle (true = gedrückt) oder nil, wenn nichts läuft.
function Inputs:next_frame()
  if not self.queue then return nil end
  self.pos = self.pos + 1
  local keys = self.queue[self.pos]
  if not keys then
    self:stop()
    return nil
  end
  local out = {}
  for _, k in ipairs(Inputs.KEYS) do out[k] = keys[k] == true end
  return out
end

-- Aufnahme ----------------------------------------------------------------------

--- Rekorder: pro Frame die gedrückten Tasten übergeben; ergibt Schritte im Profilformat.
function Inputs.recorder()
  local r = { steps = {}, current = nil, count = 0 }
  local function key_of(pad)
    local parts = {}
    for _, k in ipairs(Inputs.KEYS) do if pad[k] then parts[#parts + 1] = k end end
    return table.concat(parts, "+")
  end
  function r:frame(pad)
    local k = key_of(pad or {})
    if k == self.current then
      self.count = self.count + 1
      return
    end
    self:flush()
    self.current, self.count = k, 1
  end
  function r:flush()
    if self.current == nil then return end
    if self.current == "" then
      self.steps[#self.steps + 1] = { wait = self.count }
    else
      self.steps[#self.steps + 1] = { keys = self.current, frames = self.count, release = 0 }
    end
    self.current, self.count = nil, 0
  end
  --- Lua-Quelltext der Schritte (zum Einfügen ins Profil).
  function r:source()
    self:flush()
    local lines = { "{" }
    for _, st in ipairs(self.steps) do
      if st.wait then
        lines[#lines + 1] = string.format("  { wait = %d },", st.wait)
      else
        lines[#lines + 1] = string.format("  { keys = %q, frames = %d, release = 0 },", st.keys, st.frames)
      end
    end
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n")
  end
  return r
end

return Inputs
