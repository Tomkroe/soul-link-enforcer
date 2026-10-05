-- Transport über Dateien im Austauschordner der Brücke (bridge/bridge.js).
--
--   <dir>/out/<sitzung>_<nr>.json   Script -> Brücke -> Server (eine Nachricht pro Datei)
--   <dir>/in/<nr>.json              Server/Brücke -> Script (fortlaufend ab 1, Script löscht nach Lesen)
--
-- Beim Start schickt das Script {"op":"bridge_reset","nonce":...}. Die Brücke leert daraufhin in/,
-- beginnt wieder bei 1 und schreibt als in/1.json eine Bestätigung mit derselben nonce.
-- Bis diese Bestätigung da ist, ignoriert das Script alles (alte Dateien vorheriger Sitzungen).

local json = require("lib.json")

local Transport = {}
Transport.__index = Transport

local function pad(n, width)
  local s = string.format("%.0f", n)
  return string.rep("0", width - #s) .. s
end

--- opts: dir, fs, session (Text, eindeutig je Sitzung, aufsteigend), nonce (Text)
function Transport.new(opts)
  local self = setmetatable({}, Transport)
  self.dir = opts.dir
  self.fs = opts.fs
  self.session = opts.session or "0"
  self.nonce = opts.nonce or self.session
  self.out_n = 0
  self.in_n = 1
  self.synced = false
  self:write({ op = "bridge_reset", nonce = self.nonce })
  return self
end

function Transport:write(msg)
  self.out_n = self.out_n + 1
  local path = self.dir .. "/out/" .. self.session .. "_" .. pad(self.out_n, 8) .. ".json"
  return self.fs.write_atomic(path, json.encode(msg))
end

--- Sendet eine Nachricht an den Server (über die Brücke).
function Transport:send(msg)
  if not self.synced then return false end
  return self:write(msg)
end

--- Liest alle neuen Nachrichten. Rückgabe: Liste (kann leer sein).
function Transport:receive(max)
  local out = {}
  max = max or 50
  while #out < max do
    local path = self.dir .. "/in/" .. pad(self.in_n, 8) .. ".json"
    local text = self.fs.read(path)
    if not text or text == "" then break end
    local ok, msg = pcall(json.decode, text)
    if not self.synced then
      if ok and type(msg) == "table" and msg.op == "bridge" and msg.reset == self.nonce then
        self.synced = true
        self.fs.remove(path)
        self.in_n = self.in_n + 1
        out[#out + 1] = msg
      else
        break -- alte Datei; die Brücke räumt beim Reset auf
      end
    else
      self.fs.remove(path)
      self.in_n = self.in_n + 1
      if ok and type(msg) == "table" then out[#out + 1] = msg end
    end
  end
  return out
end

return Transport
