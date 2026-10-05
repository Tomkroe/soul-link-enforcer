-- Ende-zu-Ende-Lauf: echtes Lua 5.1 -> Datei-Brücke -> Server. Wird von server/test/e2e.test.js gestartet.
-- Aufruf: lua tests/net/e2e_client.lua <austauschordner> <lobby> <name>
package.path = "./lua/?.lua;" .. package.path
local FS = require("net.fs")
local Transport = require("net.transport_file")
local Client = require("net.client")

local dir, lobby, name = arg[1], arg[2], arg[3]
local start = os.time()
local function now() return (os.time() - start) * 1000 + math.floor(os.clock() * 1000) end
local tr = Transport.new({ dir = dir, fs = FS, session = string.format("%012d", os.time()), nonce = tostring(os.time()) .. name })
local c = Client.new({ transport = tr, name = name, lobby = lobby, now = now, fs = FS, queue_path = dir .. "/queue.json" })

local function wait(pred, label)
  for _ = 1, 200 do
    c:poll()
    if pred() then return end
    os.execute("sleep 0.05")
  end
  io.stderr:write("Zeitüberschreitung: " .. label .. " (" .. c:status_text() .. ")\n")
  os.exit(1)
end

wait(function() return c:online() end, "Anmeldung")
c:send_event({ type = "start_run" })
wait(function() return c.state and c.state.phase == "running" end, "Run-Start")
c:send_event({ type = "status", has_balls = true, badges = 1, area = { key = "201", name = "Route 201" } })
c:send_event({ type = "catch", uid = "e2e-1", species_name = "Testmon", area = { key = "201", name = "Route 201" } })
wait(function() return #c.queue == 0 and c.state.players[c.player].mons["e2e-1"] ~= nil end, "Fang bestätigt")
print("OK " .. c.player .. " " .. c.state.players[c.player].mons["e2e-1"].status .. " " .. c:status_text())
os.exit(0)
