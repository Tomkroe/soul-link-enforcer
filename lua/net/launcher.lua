-- Startet die Brücke (bridge/bridge.js) automatisch mit, wenn das Script startet.

local Launcher = {}

local function quote(s) return '"' .. s .. '"' end

--- Baut den Startbefehl. windows: true für "start /B" (läuft im Hintergrund weiter).
function Launcher.command(opts)
  local node = opts.node or "node"
  local script = opts.root .. "/bridge/bridge.js"
  local args = " --url " .. quote(opts.url) .. " --dir " .. quote(opts.dir)
  if opts.windows then
    script = script:gsub("/", "\\")
    return 'start "Soul-Link-Brücke" /MIN ' .. quote(node) .. " " .. quote(script) .. args
  end
  return quote(node) .. " " .. quote(script) .. args .. " > /dev/null 2>&1 &"
end

function Launcher.is_windows()
  return package.config:sub(1, 1) == "\\"
end

--- Startet die Brücke. exec: os.execute (austauschbar für Tests).
function Launcher.start(opts, exec)
  local cmd = Launcher.command({
    node = opts.node, root = opts.root, url = opts.url, dir = opts.dir, windows = Launcher.is_windows(),
  })
  return (exec or os.execute)(cmd), cmd
end

return Launcher
