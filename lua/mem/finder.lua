-- Adress-Suche: findet das Team im Arbeitsspeicher über seine Signatur, unabhängig von Sprachversion
-- und Zeigern. Aufbau im Spiel (Gen 4, laut Decompilation "Party"): u32 Kapazität (= 6), u32 Anzahl (0–6),
-- danach 6 Team-Datensätze. Ein Kandidat gilt als Treffer, wenn der erste Datensatz entschlüsselt eine
-- gültige Prüfsumme, eine plausible Art (1–493) und plausible Kampfwerte hat.
--
-- Rein bis auf die übergebenen Lesefunktionen (emu.read32, emu.read_bytes) – mit dem Speicher-Emulator testbar.

local P = require("mem.pkm")

local Finder = {}

Finder.RAM_START = 0x02000000
Finder.RAM_END = 0x02400000 -- 4 MB Hauptspeicher
Finder.MAX_SPECIES = { [4] = 493, [5] = 649 }

--- Prüft einen entschlüsselten Team-Datensatz auf Plausibilität.
function Finder.plausible_mon(plain, gen)
  if not P.valid(plain) then return false end
  local m = P.parse(plain, gen)
  if m.species < 1 or m.species > Finder.MAX_SPECIES[gen] then return false end
  if m.level == nil or m.level < 1 or m.level > 100 then return false end
  if m.max_hp == 0 or m.hp > m.max_hp then return false end
  return true, m
end

--- Ist addr der Anfang des ersten Team-Datensatzes? Rückgabe: ok, anzahl, erstes Monster
function Finder.party_at(emu, addr, gen)
  if addr < Finder.RAM_START + 8 or addr >= Finder.RAM_END then return false end
  if emu.read32(addr - 8) ~= 6 then return false end
  local count = emu.read32(addr - 4)
  if count < 1 or count > 6 then return false end
  local size = P.PARTY_SIZE[gen]
  local ok, m = Finder.plausible_mon(P.decrypt(emu.read_bytes(addr, size)), gen)
  if not ok then return false end
  return true, count, m
end

--- Löst einen Kandidaten-Eintrag (addr | ptr+offset | chain+offset) mit emu.resolve auf und prüft ihn.
function Finder.try_candidates(emu, candidates, gen)
  for i, c in ipairs(candidates or {}) do
    local ok_resolve, addr = pcall(emu.resolve, c)
    if ok_resolve and addr then
      local ok = Finder.party_at(emu, addr, gen)
      if ok then return addr, i end
    end
  end
  return nil
end

--- Schrittweise Suche über den ganzen Hauptspeicher (für die Frame-Schleife: pro Aufruf ein Stück).
-- Rückgabe eines Suchobjekts mit :step(bytes) -> fertig?, und .found (Liste der Treffer).
function Finder.scanner(emu, gen, opts)
  opts = opts or {}
  local s = {
    pos = opts.from or Finder.RAM_START,
    stop = opts.to or Finder.RAM_END,
    found = {},
    done = false,
  }
  function s:step(bytes)
    local last = math.min(self.stop - 8, self.pos + (bytes or 0x10000))
    local addr = self.pos
    while addr < last do
      -- schnelle Vorprüfung: Kapazität 6, danach Anzahl 1–6
      if emu.read32(addr) == 6 then
        local count = emu.read32(addr + 4)
        if count >= 1 and count <= 6 then
          local ok = Finder.party_at(emu, addr + 8, gen)
          if ok then self.found[#self.found + 1] = addr + 8 end
        end
      end
      addr = addr + 4
    end
    self.pos = last
    if self.pos >= self.stop - 8 then self.done = true end
    return self.done
  end
  return s
end

--- Sucht Zeiger, die auf base - offset zeigen, für bekannte Offsets (um eine Zeigerkette zu bestätigen).
-- Gibt eine Liste { {ptr_addr, offset}, ... } zurück. Durchsucht nur [from, to).
function Finder.find_pointers(emu, target, offsets, from, to)
  local hits = {}
  local wanted = {}
  for _, off in ipairs(offsets) do wanted[target - off] = off end
  local addr = from or Finder.RAM_START
  local stop = to or Finder.RAM_END
  while addr < stop do
    local v = emu.read32(addr)
    if wanted[v] then hits[#hits + 1] = { ptr = addr, offset = wanted[v] } end
    addr = addr + 4
  end
  return hits
end

return Finder
