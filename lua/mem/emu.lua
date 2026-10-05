-- Adapter für den Emulator. Nur dieses Modul (und main.lua/check.lua) kennt die DeSmuME-API.
-- Für Tests gibt es einen Speicher-Emulator (fake) mit derselben Schnittstelle.

local Emu = {}

-- Game-Code: Kopie des ROM-Headers im Arbeitsspeicher (0x023FFE00 + 0x0C), so auch in yPokeStats und im
-- NDS-Ironmon-Tracker (Main RAM 0x3FFE00). getestet: nein
Emu.GAME_CODE_ADDR = 0x023FFE0C

local TWO32 = 4294967296

--- Löst einen Profileintrag zur absoluten Adresse auf:
---   { addr = A }                         -> A
---   { ptr = P, offset = O }              -> read32(P) + O
---   { chain = { S, o1, o2, ... }, offset = O } -> a = read32(S); a = read32(a + o1); ...; a + O
-- Ergebnis nil, wenn ein Zeiger außerhalb des Hauptspeichers liegt.
function Emu.resolve_with(read32, entry)
  local function deref(addr)
    local v = read32(addr)
    if v < 0 then v = v + TWO32 end
    if v < 0x02000000 or v >= 0x02400000 then return nil end
    return v
  end
  if entry.chain then
    local a = deref(entry.chain[1])
    for i = 2, #entry.chain do
      if not a then return nil end
      a = deref(a + entry.chain[i])
    end
    if not a then return nil end
    return a + (entry.offset or 0)
  end
  if entry.ptr then
    local a = deref(entry.ptr)
    if not a then return nil end
    return a + (entry.offset or 0)
  end
  return entry.addr
end

local function game_code_from(read8)
  local chars = {}
  for i = 0, 3 do
    local c = read8(Emu.GAME_CODE_ADDR + i)
    if not c or c < 32 or c > 126 then return nil end
    chars[#chars + 1] = string.char(c)
  end
  return table.concat(chars)
end

--- Adapter auf die echte DeSmuME-API (globale Tabellen memory, emu, gui, input, joypad).
function Emu.desmume()
  local a = {}
  a.read8 = function(addr) return memory.readbyte(addr) end
  a.read16 = function(addr) return memory.readword(addr) end
  a.read32 = function(addr) return memory.readdword(addr) end
  a.write8 = function(addr, v) memory.writebyte(addr, v) end
  a.write16 = function(addr, v) memory.writeword(addr, v) end
  a.write32 = function(addr, v) memory.writedword(addr, v) end
  a.read_bytes = function(addr, len)
    local out = {}
    for i = 0, len - 1 do out[i + 1] = memory.readbyte(addr + i) end
    return out
  end
  a.game_code = function() return game_code_from(a.read8) end
  a.frame = function() return emu.framecount() end
  a.text = function(x, y, s, color) gui.text(x, y, s, color) end
  a.box = function(x1, y1, x2, y2, fill, line) gui.box(x1, y1, x2, y2, fill, line) end
  a.keys = function() return input.get() end
  a.set_joypad = function(t) joypad.set(t) end -- getestet: nein (Tastennamen und false-Wirkung prüfen)
  a.get_joypad = function() return joypad.get() end
  -- Touchscreen (unterer DS-Schirm). stylus.get/set – getestet: nein.
  a.touch_get = function()
    if stylus and stylus.get then
      local ok, s = pcall(stylus.get)
      if ok and s then return { x = s.x, y = s.y, touch = s.touch == true or s.touch == 1 } end
    end
    return nil
  end
  a.touch_set = function(t)
    if not (stylus and stylus.set) then return end
    if t then pcall(stylus.set, { x = t.x, y = t.y, touch = true })
    else pcall(stylus.set, { touch = false }) end
  end
  -- Schnellvorlauf: emu.speedmode gibt es nicht in jeder DeSmuME-Version (getestet: nein)
  a.set_speed = function(mode)
    local want = mode == "turbo"
    if emu.speedmode then
      -- "maximum" läuft ungebremst (schneller als "turbo"); Fallback auf "turbo", falls der Modus fehlt.
      if not pcall(emu.speedmode, want and "maximum" or "normal") then
        pcall(emu.speedmode, want and "turbo" or "normal")
      end
      return true
    end
    -- Manche DeSmuME-Builds haben stattdessen emu.setspeedmode / einen Framelimit-Schalter.
    if emu.setspeedmode then pcall(emu.setspeedmode, want and "maximum" or "normal"); return true end
    return false
  end
  a.resolve = function(entry) return Emu.resolve_with(a.read32, entry) end
  return a
end

--- Speicher-Emulator für Tests: Bytes in einer Tabelle, Bildschirmtexte werden gesammelt.
function Emu.fake(opts)
  opts = opts or {}
  local mem = {}
  local a = { mem = mem, texts = {}, joypad = nil, frame_no = 0, pressed = {} }
  a.read8 = function(addr) return mem[addr] or 0 end
  a.read16 = function(addr) return a.read8(addr) + a.read8(addr + 1) * 256 end
  a.read32 = function(addr) return a.read16(addr) + a.read16(addr + 2) * 65536.0 end
  a.write8 = function(addr, v) mem[addr] = v % 256 end
  a.write16 = function(addr, v) a.write8(addr, v) a.write8(addr + 1, math.floor(v / 256)) end
  a.write32 = function(addr, v) a.write16(addr, v % 65536) a.write16(addr + 2, math.floor(v / 65536)) end
  a.read_bytes = function(addr, len)
    local out = {}
    for i = 0, len - 1 do out[i + 1] = a.read8(addr + i) end
    return out
  end
  a.game_code = function() return game_code_from(a.read8) end
  a.frame = function() return a.frame_no end
  a.text = function(x, y, s) a.texts[#a.texts + 1] = s end
  a.box = function() end
  a.keys = function() return a.pressed end
  a.set_joypad = function(t) a.joypad = t end
  a.pad = {}
  a.get_joypad = function() return a.pad end
  a.touch = nil                       -- aktueller Touch { x, y, touch } oder nil (wird gelesen)
  a.touch_log = {}                    -- gesetzte Touch-Werte (zum Prüfen)
  a.touch_get = function() return a.touch end
  a.touch_set = function(t) a.touch_log[#a.touch_log + 1] = t end
  a.speed = "normal"
  a.set_speed = function(mode) a.speed = mode return true end
  a.resolve = function(entry) return Emu.resolve_with(a.read32, entry) end
  if opts.game_code then
    for i = 1, 4 do mem[Emu.GAME_CODE_ADDR + i - 1] = opts.game_code:byte(i) end
  end
  return a
end

return Emu
