-- Eingabe-Automatik: spielt Tastenfolgen ab und nimmt die Eingaben des Spielers auf (für Profile).
-- Rein: liefert pro Frame eine Tastentabelle; app/init.lua übergibt sie an joypad.set.
--
-- Schrittformat (Profil, z. B. prologue.inputs):
--   { keys = "A", frames = 2 }          Taste(n) für n Frames drücken ("A+B" für mehrere)
--   { touch = { x = 128, y = 96 }, frames = 2 }   Touchscreen an (x,y) antippen (DS unterer Schirm)
--   { keys = "A", touch = { x = 10, y = 20 }, frames = 2 }  beides gleichzeitig
--   { wait = 30 }                        n Frames nichts drücken (auch kein Touch)
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

--- Wandelt Schritte in eine flache Liste von Frames um. Jeder Frame ist eine Tastentabelle
--- (A=true, ...), optional mit Feld touch = { x, y } für den Touchscreen.
function Inputs.expand(steps)
  local frames = {}
  local function push(keys, touch, n)
    for _ = 1, n do
      local f = {}
      for k, v in pairs(keys) do f[k] = v end
      if touch then f.touch = touch end
      frames[#frames + 1] = f
    end
  end
  for _, st in ipairs(steps or {}) do
    if st.wait then
      push({}, nil, st.wait)
    else
      local keys = parse_keys(st.keys)
      local times = st.repeat_ or 1
      for i = 1, times do
        push(keys, st.touch, st.frames or 2)
        if st.gap and i < times then push({}, nil, st.gap) end
      end
      push({}, nil, st.release or 1) -- loslassen, damit die nächste Taste als neuer Druck zählt
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

--- Nächster Frame: Tastentabelle (true = gedrückt), evtl. mit Feld touch = { x, y };
--- nil, wenn nichts läuft.
function Inputs:next_frame()
  if not self.queue then return nil end
  self.pos = self.pos + 1
  local fr = self.queue[self.pos]
  if not fr then
    self:stop()
    return nil
  end
  local out = {}
  for _, k in ipairs(Inputs.KEYS) do out[k] = fr[k] == true end
  if fr.touch then out.touch = fr.touch end
  return out
end

-- Aufnahme ----------------------------------------------------------------------

--- Rekorder: pro Frame die gedrückten Tasten (pad) und optional den Touch ({ x, y, touch })
--- übergeben; ergibt Schritte im Profilformat (inkl. touch).
function Inputs.recorder()
  local r = { steps = {}, sig = nil, keys = nil, touch = nil, count = 0 }
  local function key_of(pad)
    local parts = {}
    for _, k in ipairs(Inputs.KEYS) do if pad[k] then parts[#parts + 1] = k end end
    return table.concat(parts, "+")
  end
  function r:frame(pad, touch)
    local k = key_of(pad or {})
    local t = (touch and touch.touch) and { x = touch.x, y = touch.y } or nil
    local sig = k .. "|" .. (t and (t.x .. "," .. t.y) or "")
    if sig == self.sig then
      self.count = self.count + 1
      return
    end
    self:flush()
    self.sig, self.keys, self.touch, self.count = sig, k, t, 1
  end
  function r:flush()
    if self.sig == nil then return end
    if self.keys == "" and not self.touch then
      self.steps[#self.steps + 1] = { wait = self.count }
    else
      local st = { frames = self.count, release = 0 }
      if self.keys ~= "" then st.keys = self.keys end
      if self.touch then st.touch = self.touch end
      self.steps[#self.steps + 1] = st
    end
    self.sig, self.keys, self.touch, self.count = nil, nil, nil, 0
  end
  --- Lua-Quelltext der Schritte (zum Einfügen ins Profil).
  function r:source()
    self:flush()
    local lines = { "{" }
    for _, st in ipairs(self.steps) do
      if st.wait then
        lines[#lines + 1] = string.format("  { wait = %d },", st.wait)
      else
        local parts = {}
        if st.keys then parts[#parts + 1] = string.format("keys = %q", st.keys) end
        if st.touch then parts[#parts + 1] = string.format("touch = { x = %d, y = %d }", st.touch.x, st.touch.y) end
        parts[#parts + 1] = string.format("frames = %d", st.frames)
        parts[#parts + 1] = "release = 0"
        lines[#lines + 1] = "  { " .. table.concat(parts, ", ") .. " },"
      end
    end
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n")
  end
  return r
end

return Inputs
