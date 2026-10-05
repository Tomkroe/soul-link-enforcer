-- Schreibschutz: Alle Schreibzugriffe auf den Spielspeicher laufen hier durch.
--
-- Geschrieben wird nur, wenn ALLE Bedingungen erfüllt sind:
--   1. Ein Profil für die geladene ROM ist bekannt (unbekannte ROM = reiner Lesemodus).
--   2. Die Adresse steht im Profil und ist als "getestet = true" markiert.
--   3. Schreiben ist global freigegeben (config.lua: write_enabled) und die Selbsttests liefen grün.
--   4. Im Kampf nur, wenn die Adresse im Profil als battle_safe markiert ist.
-- Jede Ablehnung wird mit Grund protokolliert (für Overlay und TESTEN.md).

local Guard = {}
Guard.__index = Guard

--- opts: profile (oder nil), emu (Adapter mit write8/write16/write32), enabled (bool), log (Funktion)
function Guard.new(opts)
  local self = setmetatable({}, Guard)
  self.profile = opts.profile
  self.emu = opts.emu
  self.enabled = opts.enabled and true or false
  self.selftest_ok = false
  self.log = opts.log or function() end
  self.resolve = opts.resolve -- optional: löst Zeiger-Einträge { ptr, offset } zur Adresse auf
  self.refused = {}
  self.writes = 0
  return self
end

function Guard:set_selftest(ok)
  self.selftest_ok = ok and true or false
end

--- Prüft, ob unter dem Namen geschrieben werden darf. Rückgabe: erlaubt, Grund.
function Guard:can_write(name, in_battle)
  if not self.profile then return false, "unbekannte ROM – reiner Lesemodus" end
  if not self.enabled then return false, "Schreiben in config.lua abgeschaltet" end
  if not self.selftest_ok then return false, "Selbsttests nicht bestanden" end
  local entry = self.profile.addresses and self.profile.addresses[name]
  if not entry then return false, "Adresse '" .. name .. "' fehlt im Profil" end
  if entry.tested ~= true then return false, "Adresse '" .. name .. "' ist nicht getestet" end
  if in_battle and entry.battle_safe ~= true then return false, "im Kampf nicht freigegeben" end
  return true, ""
end

function Guard:address(name)
  local entry = self.profile.addresses[name]
  if self.resolve then return self.resolve(entry) end
  return entry.addr
end

--- Schreibt width (8/16/32) Bit an Basisadresse des Profileintrags + offset.
function Guard:write(name, offset, width, value, in_battle)
  local ok, reason = self:can_write(name, in_battle)
  if not ok then
    if not self.refused[name .. reason] then
      self.refused[name .. reason] = true
      self.log("Schreiben abgelehnt (" .. name .. "): " .. reason)
    end
    return false, reason
  end
  local addr = self:address(name) + (offset or 0)
  if width == 8 then self.emu.write8(addr, value)
  elseif width == 16 then self.emu.write16(addr, value)
  elseif width == 32 then self.emu.write32(addr, value)
  else error("Ungültige Breite: " .. tostring(width)) end
  self.writes = self.writes + 1
  return true
end

--- Schreibt eine Byte-Liste ab Profileintrag + offset.
function Guard:write_bytes(name, offset, bytes, in_battle)
  local ok, reason = self:can_write(name, in_battle)
  if not ok then return self:write(name, offset, 8, 0, in_battle) end
  local addr = self:address(name) + (offset or 0)
  for i, v in ipairs(bytes) do self.emu.write8(addr + i - 1, v) end
  self.writes = self.writes + 1
  return true
end

return Guard
