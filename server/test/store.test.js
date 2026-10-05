'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { FileStore, UpstashStore } = require('../src/store');
const { tmpDir } = require('./helpers');

test('FileStore: speichern, laden, auflisten', async () => {
  const dir = tmpDir();
  const s = new FileStore(dir);
  assert.equal(await s.get('lobby:ABC'), null);
  await s.set('lobby:ABC', { a: 1 });
  await s.set('lobby:XYZ', { a: 2 });
  await s.set('stats', { x: 1 });
  assert.deepEqual(await s.get('lobby:ABC'), { a: 1 });
  assert.deepEqual((await s.list('lobby:')).sort(), ['lobby:ABC', 'lobby:XYZ']);
  assert.throws(() => s.file('../böse'), /Ungültiger/);
});

test('FileStore: beschädigte Datei -> Rückfall auf Sicherung', async () => {
  const dir = tmpDir();
  const s = new FileStore(dir);
  await s.set('lobby:A', { v: 1 });
  await s.set('lobby:A', { v: 2 });
  fs.writeFileSync(path.join(dir, 'lobby__A.json'), '{kaputt');
  const quietWarn = console.warn;
  console.warn = () => {};
  try {
    assert.deepEqual(await s.get('lobby:A'), { v: 1 });
  } finally {
    console.warn = quietWarn;
  }
});

test('UpstashStore: REST-Befehle', async () => {
  const db = new Map();
  const sets = new Map();
  const calls = [];
  const fakeFetch = async (url, opts) => {
    assert.equal(opts.headers.Authorization, 'Bearer geheim');
    const [cmd, ...args] = JSON.parse(opts.body);
    calls.push(cmd);
    let result = null;
    if (cmd === 'GET') result = db.has(args[0]) ? db.get(args[0]) : null;
    if (cmd === 'SET') { db.set(args[0], args[1]); result = 'OK'; }
    if (cmd === 'SADD') { if (!sets.has(args[0])) sets.set(args[0], new Set()); sets.get(args[0]).add(args[1]); result = 1; }
    if (cmd === 'SMEMBERS') result = [...(sets.get(args[0]) || [])];
    return { ok: true, json: async () => ({ result }) };
  };
  const s = new UpstashStore({ url: 'https://x.upstash.io/', token: 'geheim', fetchImpl: fakeFetch });
  await s.set('lobby:A', { v: 1 });
  await s.set('stats', { d: 3 });
  assert.deepEqual(await s.get('lobby:A'), { v: 1 });
  assert.equal(await s.get('lobby:B'), null);
  assert.deepEqual(await s.list('lobby:'), ['lobby:A']);
  assert.ok(db.has('slink:lobby:A'));
  assert.ok(calls.includes('SADD'));
});
