-- Testlauf für alle Lua-Tests. Aufruf aus dem Projektordner:
--   lua tests/run.lua            (Lua 5.1, falls installiert)
--   node scripts/run-lua-tests.js (fengari, Lua 5.3, ohne Installation)

package.path = "./lua/?.lua;./lua/?/init.lua;./tests/?.lua;" .. package.path

local T = require("lib.t")

local files = require("all")

print("Lua-Tests unter " .. _VERSION)
for _, name in ipairs(files) do
  print("- " .. name)
  T.current_file = name
  local ok, err = pcall(require, name)
  if not ok then
    T.results.failed = T.results.failed + 1
    table.insert(T.results.failures, name .. " :: Laden fehlgeschlagen\n      " .. tostring(err))
    print("  FEHLER beim Laden: " .. tostring(err))
  end
end

local r = T.results
print(string.format("\n%d bestanden, %d fehlgeschlagen, %d übersprungen", r.passed, r.failed, r.skipped))
if r.failed > 0 then
  print("\nFehlgeschlagen:")
  for _, f in ipairs(r.failures) do print("  " .. f) end
  os.exit(1)
end
