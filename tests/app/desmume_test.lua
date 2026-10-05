-- main.lua und check.lua gegen eine nachgebaute DeSmuME-API (nur natives Lua, braucht io).
local T = require("lib.t")

local function with_stub(fn)
  local saved = { memory = memory, emu = emu, gui = gui, input = input, joypad = joypad, exec = os.execute, print = print }
  local mem = {}
  local code = "CPUD"
  for i = 1, 4 do mem[0x023FFE0C + i - 1] = code:byte(i) end
  local cb = { after = {}, gui = {} }
  local shown = {}
  memory = {
    readbyte = function(a) return mem[a] or 0 end,
    readword = function(a) return (mem[a] or 0) + (mem[a + 1] or 0) * 256 end,
    readdword = function(a) return 0 end,
    writebyte = function(a, v) error("Schreibzugriff in der Prüfung: " .. a) end,
    writeword = function(a, v) error("Schreibzugriff in der Prüfung: " .. a) end,
    writedword = function(a, v) error("Schreibzugriff in der Prüfung: " .. a) end,
  }
  local frame = 0
  emu = { registerafter = function(f) cb.after[#cb.after + 1] = f end, framecount = function() return frame end }
  gui = { register = function(f) cb.gui[#cb.gui + 1] = f end, text = function(x, y, s) shown[#shown + 1] = s end, box = function() end }
  input = { get = function() return {} end }
  joypad = { set = function() end }
  local commands = {}
  os.execute = function(c) commands[#commands + 1] = c return 0 end
  print = function() end
  local ok, err = pcall(function()
    fn(cb, shown, commands, function() frame = frame + 1 end)
  end)
  memory, emu, gui, input, joypad, os.execute, print = saved.memory, saved.emu, saved.gui, saved.input, saved.joypad, saved.exec, saved.print
  if not ok then error(err, 0) end
end

T.test("main.lua läuft mit DeSmuME-API (Lesemodus, keine Schreibzugriffe)", function()
  if not io.open then T.skip("kein io.open (fengari)") end
  with_stub(function(cb, shown, commands, step)
    dofile("lua/main.lua")
    T.eq(#cb.after, 1)
    T.eq(#cb.gui, 1)
    for _ = 1, 25 do
      step()
      cb.after[1]()
      cb.gui[1]()
    end
    local all = table.concat(shown, "\n")
    T.ok(all:find("Profil Platin: 0/"), all)
    T.ok(all:find("nur lesen"), all)
    T.ok(commands[1] and commands[1]:find("bridge.js"), "Brücke gestartet")
  end)
end)

T.test("check.lua läuft und zeigt Ergebnisse", function()
  if not io.open then T.skip("kein io.open (fengari)") end
  with_stub(function(cb, shown)
    dofile("lua/check.lua")
    cb.gui[1]()
    local all = table.concat(shown, "\n")
    T.ok(all:find("CPUD"), all)
    T.ok(all:find("OK  Datei schreiben"), all)
    T.ok(all:find("OK  Selbsttest"), all)
    T.ok(all:find("Suche Team im Speicher"), all)
  end)
end)
