'use strict';
// Ende-zu-Ende: echtes Lua 5.1 (falls installiert) -> Datei-Brücke -> Server.
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { spawn, spawnSync } = require('child_process');
const { startServer, connect, tmpDir } = require('./helpers');
const { Bridge } = require('../../bridge/bridge');

const ROOT = path.resolve(__dirname, '..', '..');
const quiet = { log() {}, warn() {}, error() {} };

function findLua() {
  for (const exe of ['lua5.1', 'lua51', 'luajit', 'lua']) {
    const r = spawnSync(exe, ['-v'], { encoding: 'utf8' });
    if (!r.error && /Lua 5\.1|LuaJIT/.test(`${r.stdout}${r.stderr}`)) return exe;
  }
  return null;
}

const lua = findLua();

test('Brücke allein: Reset, Weiterleitung, Statusmeldungen', async () => {
  const { srv, url } = await startServer();
  const dir = tmpDir();
  const fs = require('fs');
  const bridge = new Bridge({ url, dir, poll: 20, idle: 0, logger: quiet });
  bridge.start();
  try {
    fs.writeFileSync(path.join(dir, 'out', 'old_00000001.json'), JSON.stringify({ op: 'hello', lobby: 'STALE', name: 'x', role: 'player' }));
    fs.writeFileSync(path.join(dir, 'out', 's1_00000001.json'), JSON.stringify({ op: 'bridge_reset', nonce: 'abc' }));
    const read = (n) => {
      const f = path.join(dir, 'in', `${String(n).padStart(8, '0')}.json`);
      return fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : null;
    };
    const until = async (pred) => {
      for (let i = 0; i < 100; i++) {
        const v = pred();
        if (v) return v;
        await new Promise((r) => setTimeout(r, 20));
      }
      throw new Error('Zeitüberschreitung');
    };
    const first = await until(() => read(1));
    assert.equal(first.reset, 'abc');
    fs.writeFileSync(path.join(dir, 'out', 's1_00000002.json'), JSON.stringify({ op: 'hello', role: 'player', lobby: 'BRIDGE', name: 'Bea' }));
    let welcome = null;
    await until(() => {
      for (let n = 2; n < 10; n++) {
        const m = read(n);
        if (m && m.op === 'welcome') welcome = m;
      }
      return welcome;
    });
    assert.equal(welcome.player, 'bea');
    assert.equal(srv.hub.lobbies.has('STALE'), false, 'alte Nachricht vor dem Reset wurde verworfen');
  } finally {
    bridge.stop();
    await srv.stop();
  }
});

test('Ende-zu-Ende mit echtem Lua 5.1', { skip: lua ? false : 'kein natives Lua 5.1 installiert' }, async () => {
  const { srv, url } = await startServer();
  const dir = tmpDir();
  const bridge = new Bridge({ url, dir, poll: 20, idle: 0, logger: quiet });
  bridge.start();
  try {
    const viewer = await connect(url, null);
    const out = await new Promise((resolve, reject) => {
      const p = spawn(lua, ['tests/net/e2e_client.lua', dir, 'E2E', 'Lua-Tester'], { cwd: ROOT });
      let stdout = '';
      let stderr = '';
      p.stdout.on('data', (d) => { stdout += d; });
      p.stderr.on('data', (d) => { stderr += d; });
      p.on('close', (code) => (code === 0 ? resolve(stdout) : reject(new Error(`Lua beendet mit ${code}: ${stderr}`))));
    });
    assert.match(out, /^OK lua-tester lebt Verbunden/);
    viewer.send({ op: 'hello', role: 'viewer', lobby: 'E2E' });
    const st = await viewer.waitFor((m) => m.op === 'state');
    assert.equal(st.state.players['lua-tester'].badges, 1);
    assert.equal(st.state.teams.t1.groups.g1.status, 'komplett');
    viewer.close();
  } finally {
    bridge.stop();
    await srv.stop();
  }
});
