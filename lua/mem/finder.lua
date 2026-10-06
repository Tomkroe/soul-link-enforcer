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

--- Schrittweise Suche nach Blöcken, die exakt einem der übergebenen Blöcke entsprechen (z. B. die aktuell
-- geladene Begegnungstabelle = eine Datei aus dem ROM). blocks: Liste von Texten gleicher Länge.
-- Rückgabe wie scanner: Objekt mit :step(bytes), .found = { {addr, index}, ... }.
function Finder.block_scanner(emu, blocks, opts)
  opts = opts or {}
  local index = {}
  local function key(a, b) return string.format("%.0f:%.0f", a, b) end
  local function le32(s, off)
    local x1, x2, x3, x4 = s:byte(off + 1, off + 4)
    return x1 + x2 * 256 + x3 * 65536.0 + x4 * 16777216.0
  end
  for i, blk in ipairs(blocks) do
    if #blk >= 16 then
      local k = key(le32(blk, 0), le32(blk, 4))
      index[k] = index[k] or {}
      table.insert(index[k], i)
    end
  end
  local s = { pos = opts.from or Finder.RAM_START, stop = opts.to or Finder.RAM_END, found = {}, done = false }
  function s:step(bytes)
    local last = math.min(self.stop - 16, self.pos + (bytes or 0x10000))
    local addr = self.pos
    while addr < last do
      local cands = index[key(emu.read32(addr), emu.read32(addr + 4))]
      if cands then
        for _, i in ipairs(cands) do
          if Finder.block_equals(emu, addr, blocks[i]) then
            self.found[#self.found + 1] = { addr = addr, index = i }
            break
          end
        end
      end
      addr = addr + 4
    end
    self.pos = last
    if self.pos >= self.stop - 16 then self.done = true end
    return self.done
  end
  return s
end

--- Vergleicht den Speicher ab addr mit einem Text.
function Finder.block_equals(emu, addr, blk)
  for j = 0, #blk - 1 do
    if emu.read8(addr + j) ~= blk:byte(j + 1) then return false end
  end
  return true
end

--- Schrittweise Suche nach Box-Datensätzen (136 Byte) bekannter Monster, außerhalb des Team-Bereichs.
-- pids: Menge [pid] = uid. Rückgabe wie scanner: .found = { {addr, uid}, ... }.
function Finder.box_scanner(emu, pids, gen, exclude_from, exclude_to, opts)
  opts = opts or {}
  local s = { pos = opts.from or Finder.RAM_START, stop = opts.to or Finder.RAM_END, found = {}, done = false }
  function s:step(bytes)
    local last = math.min(self.stop - P.BOX_SIZE, self.pos + (bytes or 0x10000))
    local addr = self.pos
    while addr < last do
      local uid = pids[emu.read32(addr)]
      if uid and not (exclude_from and addr >= exclude_from and addr < exclude_to) then
        local plain = P.decrypt(emu.read_bytes(addr, P.BOX_SIZE))
        if P.valid(plain) then
          local m = P.parse(plain, gen)
          if m.uid == uid then self.found[#self.found + 1] = { addr = addr, uid = uid } end
        end
      end
      addr = addr + 4
    end
    self.pos = last
    if self.pos >= self.stop - P.BOX_SIZE then self.done = true end
    return self.done
  end
  return s
end

--- Spielzeit-Suche: samples = Liste { bytes = {...}, dt = Sekunden seit der vorigen Probe } eines Speicherfensters.
-- Kandidat ist ein 4-Byte-Wert (u16 Stunden, u8 Minuten, u8 Sekunden), dessen Gesamtsekunden zwischen
-- allen Proben um genau dt (±1) wachsen. Rückgabe: Liste { offset, seconds } (offset im Fenster).
function Finder.playtime_candidates(samples)
  local out = {}
  if #samples < 3 then return out end
  local size = #samples[1].bytes
  local function total(b, o)
    local h = b[o + 1] + b[o + 2] * 256
    local m, sec = b[o + 3], b[o + 4]
    if m > 59 or sec > 59 or h > 9999 then return nil end
    return h * 3600 + m * 60 + sec
  end
  for o = 0, size - 4, 2 do
    local ok = true
    local prev = total(samples[1].bytes, o)
    if not prev then ok = false end
    for i = 2, #samples do
      if not ok then break end
      local cur = total(samples[i].bytes, o)
      local dt = samples[i].dt
      if not cur or math.abs((cur - prev) - dt) > 1 or cur == prev then ok = false end
      prev = cur
    end
    if ok then out[#out + 1] = { offset = o, seconds = prev } end
  end
  return out
end

--- Prüft, ob ein Spielzeit-Kandidat in Wahrheit die Echtzeituhr (RTC) ist: Stunden < 24 und
-- Minuten:Sekunden stimmen (±2 s) mit der PC-Uhr überein. now = { min = .., sec = .. } (os.date("*t")).
-- Nur Minuten/Sekunden werden verglichen, damit eine andere Zeitzone im Emulator nicht stört.
function Finder.is_clock(seconds, now)
  if not now or seconds >= 24 * 3600 then return false end
  local diff = math.abs(seconds % 3600 - (now.min * 60 + now.sec))
  return math.min(diff, 3600 - diff) <= 2
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
