#!/usr/bin/env node
// Führt tests/run.lua aus: immer unter fengari (Lua 5.3 in Node, keine Installation nötig)
// und zusätzlich unter einem nativen Lua 5.1, falls eines im PATH liegt (wie in DeSmuME).
'use strict';
const path = require('path');
const { spawnSync } = require('child_process');
const { runLuaFile } = require('../server/src/lua-vm');

const root = path.resolve(__dirname, '..');
process.chdir(root);

let failed = false;

console.log('=== fengari (Lua 5.3) ===');
const code = runLuaFile(path.join(root, 'tests', 'run.lua'));
if (code !== 0) failed = true;

const candidates = ['lua5.1', 'lua51', 'luajit', 'lua'];
let native = null;
for (const exe of candidates) {
  const probe = spawnSync(exe, ['-v'], { encoding: 'utf8' });
  if (!probe.error && /Lua 5\.1|LuaJIT/.test((probe.stdout || '') + (probe.stderr || ''))) {
    native = exe;
    break;
  }
}
if (native) {
  console.log(`\n=== natives ${native} (Lua 5.1, wie DeSmuME) ===`);
  const r = spawnSync(native, ['tests/run.lua'], { stdio: 'inherit' });
  if (r.status !== 0) failed = true;
} else {
  console.log('\n(Kein natives Lua 5.1 gefunden – nur fengari-Lauf. Das reicht für die Abnahme.)');
}

process.exit(failed ? 1 : 0);
