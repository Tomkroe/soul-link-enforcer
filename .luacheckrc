-- Statische Prüfung des Lua-Codes (luacheck). Aufruf: npm run lint
-- Findet versehentliche globale Variablen, Tippfehler in Namen und toten Code.
std = "lua51"                          -- DeSmuME nutzt Lua 5.1
globals = { "memory", "emu", "gui", "input", "joypad", "bit" } -- DeSmuME-API
max_line_length = false
unused_args = false
