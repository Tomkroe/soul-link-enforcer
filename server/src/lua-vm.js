'use strict';
// Lua-VM (fengari, Lua 5.3) im Node-Prozess. Damit führt der Server exakt dieselbe
// Regel-Engine aus /lua/core aus wie das Emulator-Script – Regel-Logik existiert nur einmal.
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const ROOT = path.resolve(__dirname, '..', '..');

function newState() {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const luaDir = path.join(ROOT, 'lua').replace(/\\/g, '/');
  const testDir = path.join(ROOT, 'tests').replace(/\\/g, '/');
  const pp = `${luaDir}/?.lua;${luaDir}/?/init.lua;${testDir}/?.lua`;
  lua.lua_getglobal(L, to_luastring('package'));
  lua.lua_pushstring(L, to_luastring(pp));
  lua.lua_setfield(L, -2, to_luastring('path'));
  lua.lua_pop(L, 1);
  return L;
}

function errorText(L) {
  const msg = lua.lua_tojsstring(L, -1);
  lua.lua_pop(L, 1);
  return msg;
}

/** Führt eine Lua-Datei aus (für den Testlauf). Liefert 0 bei Erfolg. */
function runLuaFile(file) {
  const L = newState();
  // os.exit soll den Prozess nicht sofort beenden, sondern den Status zurückgeben.
  let exitCode = 0;
  const origExit = process.exit;
  process.exit = (c) => { exitCode = c === undefined || c === true ? 0 : (c === false ? 1 : c); throw new Error('__lua_exit__'); };
  try {
    const status = lauxlib.luaL_dofile(L, to_luastring(file));
    if (status !== 0) {
      const msg = errorText(L);
      if (!/__lua_exit__/.test(msg)) {
        console.error(msg);
        return 1;
      }
    }
  } catch (e) {
    if (e.message !== '__lua_exit__') throw e;
  } finally {
    process.exit = origExit;
  }
  return exitCode;
}

/**
 * Lädt ein Lua-Modul, das Funktionen der Form f(json_text, ...) -> json_text anbietet.
 * Rückgabe: { call(name, ...strings) -> string }
 */
function loadModule(moduleName) {
  const L = newState();
  const code = `__mod = require(${JSON.stringify(moduleName)})`;
  if (lauxlib.luaL_dostring(L, to_luastring(code)) !== 0) {
    throw new Error(`Lua-Modul ${moduleName} konnte nicht geladen werden: ${errorText(L)}`);
  }
  return {
    call(name, ...args) {
      const top = lua.lua_gettop(L);
      lua.lua_getglobal(L, to_luastring('__mod'));
      lua.lua_getfield(L, -1, to_luastring(name));
      if (lua.lua_type(L, -1) !== lua.LUA_TFUNCTION) {
        lua.lua_settop(L, top);
        throw new Error(`Lua-Funktion ${moduleName}.${name} fehlt`);
      }
      for (const a of args) lua.lua_pushstring(L, to_luastring(String(a)));
      const status = lua.lua_pcall(L, args.length, 1, 0);
      if (status !== 0) {
        const msg = errorText(L);
        lua.lua_settop(L, top);
        throw new Error(`Lua-Fehler in ${moduleName}.${name}: ${msg}`);
      }
      const out = lua.lua_tojsstring(L, -1);
      lua.lua_settop(L, top);
      return out;
    },
  };
}

module.exports = { runLuaFile, loadModule, ROOT };
