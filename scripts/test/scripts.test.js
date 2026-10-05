'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { extractUrl, instructions } = require('../tunnel');
const { readConfig, listBackups, restore } = require('../restore-backup');

test('Tunnel: Adresse aus der cloudflared-Ausgabe lesen', () => {
  const out = '2026-10-05T18:00:00Z INF |  https://blue-river-test-42.trycloudflare.com                    |';
  assert.equal(extractUrl(out), 'https://blue-river-test-42.trycloudflare.com');
  assert.equal(extractUrl('INF Starting tunnel'), null);
  const text = instructions('https://blue-river-test-42.trycloudflare.com', 'ABC');
  assert.match(text, /server_url = "wss:\/\/blue-river-test-42\.trycloudflare\.com\/ws"/);
  assert.match(text, /api\/ABC\/todesprotokoll\.txt/);
});

test('Sicherung: Pfade aus config.lua lesen', () => {
  const cfg = fs.readFileSync(path.join(__dirname, '..', '..', 'config.lua'), 'utf8');
  assert.deepEqual(readConfig(cfg), { savePath: '', dir: null });
  const own = 'backups = {\n  save_path = "C:/DeSmuME/Battery/Platin.dsv",\n  dir = "D:/sicher",\n  keep = 20,\n}';
  assert.deepEqual(readConfig(own), { savePath: 'C:/DeSmuME/Battery/Platin.dsv', dir: 'D:/sicher' });
});

test('Sicherung zurückspielen: neueste zuerst, aktuelle Datei vorher gesichert', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'slink-bk-'));
  const save = path.join(dir, 'spiel.dsv');
  fs.writeFileSync(save, 'AKTUELL');
  fs.writeFileSync(path.join(dir, 'a_orden1_intervall.dsv'), 'ALT');
  fs.writeFileSync(path.join(dir, 'b_orden2_orden.dsv'), 'NEUER');
  fs.writeFileSync(path.join(dir, 'index.json'), JSON.stringify(['a_orden1_intervall.dsv', 'b_orden2_orden.dsv', 'fehlt.dsv']));
  assert.deepEqual(listBackups(dir), ['b_orden2_orden.dsv', 'a_orden1_intervall.dsv']);
  const r = restore({ savePath: save, dir, nr: 2, now: new Date('2026-10-05T20:00:00Z') });
  assert.equal(r.restored, 'a_orden1_intervall.dsv');
  assert.equal(fs.readFileSync(save, 'utf8'), 'ALT');
  assert.equal(fs.readFileSync(r.kept, 'utf8'), 'AKTUELL');
  assert.throws(() => restore({ savePath: save, dir, nr: 9 }), /gibt es nicht/);
});
