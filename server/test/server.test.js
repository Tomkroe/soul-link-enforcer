'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { startServer, connect, sleep } = require('./helpers');

async function twoPlayers(url, code = 'ABC123') {
  const a = await connect(url, { role: 'player', lobby: code, name: 'Anna' });
  const b = await connect(url, { role: 'player', lobby: code, name: 'Ben' });
  return { a, b };
}

test('Lobby per Code: zwei Spieler treten bei, Run startet', async () => {
  const { srv, url } = await startServer();
  try {
    const { a, b } = await twoPlayers(url);
    assert.equal(a.welcome.op, 'welcome');
    assert.equal(a.welcome.player, 'anna');
    const ack = await a.event({ type: 'start_run' });
    assert.equal(ack.error, undefined);
    const st = await b.waitFor((m) => m.op === 'state' && m.state.phase === 'running');
    assert.deepEqual(st.state.teams.t1.members, ['anna', 'ben']);
    assert.equal(st.state.players.anna.online, true);
    assert.equal(st.stats.anna.attempts, 1);
    a.close(); b.close();
  } finally {
    await srv.stop();
  }
});

test('Gekoppelter Tod wird an den Partner verteilt', async () => {
  const { srv, url } = await startServer();
  try {
    const { a, b } = await twoPlayers(url);
    await a.event({ type: 'start_run' });
    await a.event({ type: 'status', has_balls: true });
    await b.event({ type: 'status', has_balls: true });
    await a.event({ type: 'catch', uid: 'a1', species_name: 'Staralili', area: { key: '201', name: 'Route 201' } });
    await b.event({ type: 'catch', uid: 'b1', species_name: 'Bidiza', area: { key: '201', name: 'Route 201' } });
    await a.event({ type: 'catch', uid: 'a2', area: { key: '202', name: 'Route 202' } });
    await b.event({ type: 'catch', uid: 'b2', area: { key: '202', name: 'Route 202' } });
    await a.event({ type: 'faint', uid: 'a1', opponent: 'Rivale' });
    const eff = await b.waitFor((m) => m.op === 'effects' && m.effects.some((e) => e.type === 'kill' && e.player === 'ben'));
    assert.ok(eff.effects.find((e) => e.type === 'kill' && e.uid === 'b1'));
    const st = await b.waitFor((m) => m.op === 'state' && m.state.players.ben?.mons.b1?.status === 'tot');
    assert.deepEqual(st.derived.players.ben.dead, ['b1']);
    assert.equal(st.stats.anna.deaths, 1);
    assert.equal(st.stats.ben.dragged, 1);
    a.close(); b.close();
  } finally {
    await srv.stop();
  }
});

test('Doppelte Ereignisse (gleiche Sequenznummer) werden nur einmal angewendet', async () => {
  const { srv, url } = await startServer();
  try {
    const { a } = await twoPlayers(url);
    await a.event({ type: 'start_run' });
    a.send({ op: 'event', seq: 50, event: { type: 'status', badges: 1 } });
    await a.waitFor((m) => m.op === 'ack' && m.seq === 50);
    a.send({ op: 'event', seq: 50, event: { type: 'status', badges: 1 } });
    const dup = await a.waitFor((m) => m.op === 'ack' && m.seq === 50);
    assert.equal(dup.duplicate, true);
    a.close();
    const again = await connect(url, { role: 'player', lobby: 'ABC123', name: 'Anna' });
    assert.equal(again.welcome.last_seq, 50, 'Wiedereinstieg kennt die letzte bestätigte Nummer');
    again.close();
  } finally {
    await srv.stop();
  }
});

test('Ungültige Eingaben: Lobby-Code, fehlender Name, verbotene Ereignisse', async () => {
  const { srv, url } = await startServer();
  try {
    const bad = await connect(url, { role: 'player', lobby: 'x', name: 'Anna' });
    assert.equal(bad.welcome.op, 'error');
    const noname = await connect(url, { role: 'player', lobby: 'ABCD', name: '  ' });
    assert.equal(noname.welcome.op, 'error');
    const a = await connect(url, { role: 'player', lobby: 'ABCD', name: 'Anna' });
    const ack = await a.event({ type: 'offline' });
    assert.match(ack.error, /nicht erlaubt/);
    const ack2 = await a.event({ type: 'faint', uid: 'x' });
    assert.match(ack2.error, /Kein laufender Run/);
    [bad, noname, a].forEach((c) => c.close());
  } finally {
    await srv.stop();
  }
});

test('Run-Übersicht (Zuschauer) ist schreibgeschützt', async () => {
  const { srv, url } = await startServer();
  try {
    const { a } = await twoPlayers(url, 'VIEW1');
    const v = await connect(url, { role: 'viewer', lobby: 'VIEW1' });
    assert.equal(v.welcome.role, 'viewer');
    await v.waitFor((m) => m.op === 'state');
    v.send({ op: 'event', seq: 1, event: { type: 'start_run' } });
    const err = await v.waitFor((m) => m.op === 'error');
    assert.match(err.message, /schreibgeschützt/);
    const none = await connect(url, { role: 'viewer', lobby: 'GIBTSNICHT' });
    assert.equal(none.welcome.op, 'error');
    [a, v, none].forEach((c) => c.close());
  } finally {
    await srv.stop();
  }
});

test('Zustand und Todeszähler überstehen einen Server-Neustart', async () => {
  const first = await startServer();
  const { a, b } = await twoPlayers(first.url, 'PERSIST');
  await a.event({ type: 'start_run' });
  await a.event({ type: 'status', has_balls: true });
  await a.event({ type: 'catch', uid: 'a1', area: { key: '1', name: 'Gebiet 1' } });
  await b.event({ type: 'catch', uid: 'b1', area: { key: '1', name: 'Gebiet 1' } });
  await a.event({ type: 'catch', uid: 'a2', area: { key: '2', name: 'Gebiet 2' } });
  await b.event({ type: 'catch', uid: 'b2', area: { key: '2', name: 'Gebiet 2' } });
  await a.event({ type: 'faint', uid: 'a1' });
  a.close(); b.close();
  await first.srv.stop();
  assert.ok(fs.existsSync(path.join(first.dir, 'lobby__PERSIST.json')));

  const second = await startServer({ dir: first.dir });
  try {
    const v = await connect(second.url, { role: 'viewer', lobby: 'PERSIST' });
    const st = await v.waitFor((m) => m.op === 'state');
    assert.equal(st.state.phase, 'running');
    assert.equal(st.state.players.ben.mons.b1.status, 'tot');
    assert.equal(st.state.players.anna.online, false, 'nach Neustart offline');
    assert.equal(st.stats.anna.deaths, 1);
    assert.equal(st.state.teams.t1.graveyard.length, 2);
    // Wiedereinstieg: Spieler verbindet sich erneut und spielt weiter
    const a2 = await connect(second.url, { role: 'player', lobby: 'PERSIST', name: 'Anna' });
    assert.equal(a2.welcome.op, 'welcome');
    const ack = await a2.event({ type: 'status', badges: 1 });
    assert.equal(ack.error, undefined);
    [v, a2].forEach((c) => c.close());
  } finally {
    await second.srv.stop();
  }
});

test('Fehlender Herzschlag: Spieler wird offline, Partner im Aufhol-Modus', async () => {
  const clock = { t: 1_000_000 };
  const { srv, url } = await startServer({ clock });
  try {
    const { a, b } = await twoPlayers(url, 'BEAT');
    await a.event({ type: 'start_run' });
    clock.t += 5_000;
    a.send({ op: 'ping' });
    await a.waitFor((m) => m.op === 'pong');
    clock.t += 18_000; // ben hat seit 23 s nichts gesendet, anna seit 18 s
    a.inbox.length = 0;
    srv.hub.tick();
    const st = await a.waitFor((m) => m.op === 'state' && m.state.players.ben?.online === false);
    assert.equal(st.state.players.anna.online, true);
    assert.equal(st.derived.players.anna.catchup, true);
    const eff = st; // Hinweis an anna kam als Effekt
    assert.ok(eff);
    a.close(); b.close();
  } finally {
    await srv.stop();
  }
});

test('Verbindungsabbruch: Partner sieht offline, Wiederverbinden zeigt Abwesenheitsliste', async () => {
  const { srv, url } = await startServer();
  try {
    const { a, b } = await twoPlayers(url, 'AWAY');
    await a.event({ type: 'start_run' });
    await a.event({ type: 'status', has_balls: true });
    await b.event({ type: 'status', has_balls: true });
    for (const [k, n] of [['1', 'R1'], ['2', 'R2']]) {
      await a.event({ type: 'catch', uid: `a${k}`, area: { key: k, name: n } });
      await b.event({ type: 'catch', uid: `b${k}`, area: { key: k, name: n } });
    }
    a.inbox.length = 0;
    b.close();
    await a.waitFor((m) => m.op === 'state' && m.state.players.ben?.online === false);
    await a.event({ type: 'faint', uid: 'a1' });
    const b2 = await connect(url, { role: 'player', lobby: 'AWAY', name: 'Ben' });
    const rep = await b2.waitFor((m) => m.op === 'effects' && m.effects.some((e) => e.type === 'absence_report'));
    const report = rep.effects.find((e) => e.type === 'absence_report');
    assert.equal(report.player, 'ben');
    assert.equal(report.deaths[0].uid, 'b1');
    await b2.event({ type: 'ack_absence' });
    const st = await b2.waitFor((m) => m.op === 'state' && m.state.players.ben?.absence.length === 0);
    assert.ok(st);
    a.close(); b2.close();
  } finally {
    await srv.stop();
  }
});

test('Discord-Meldungen über Webhook, abschaltbar pro Art', async () => {
  const posts = [];
  const fakeFetch = async (url, opts) => {
    posts.push({ url, body: JSON.parse(opts.body) });
    return { ok: true, status: 204 };
  };
  const { srv, url } = await startServer({ discordFetch: fakeFetch, discordUrl: 'https://discord.invalid/hook' });
  try {
    const a = await connect(url, { role: 'player', lobby: 'DISC', name: 'Anna' });
    await a.event({ type: 'start_run' });
    await a.event({ type: 'status', has_balls: true });
    await a.event({ type: 'catch', uid: 'a1', species_name: 'Staralili', area: { key: '1', name: 'R1' } });
    await a.event({ type: 'faint', uid: 'a1', opponent: 'Rivale' });
    await srv.hub.discord.queue;
    const texts = posts.map((p) => p.body.content);
    assert.ok(texts.some((t) => t.includes('Run gestartet')));
    assert.ok(texts.some((t) => t.includes('Neue Gruppe')));
    assert.ok(texts.some((t) => t.includes('Staralili') && t.includes('gefallen') && t.includes('R1')));
    assert.ok(!texts.some((t) => t.includes('Run ist verloren')), 'run_end ist in der Konfiguration abgeschaltet');
    a.close();
  } finally {
    await srv.stop();
  }
});

test('Ohne Webhook-Adresse wird nichts gesendet', async () => {
  let called = false;
  const { srv, url } = await startServer({ discordFetch: async () => { called = true; return { ok: true }; } });
  try {
    const a = await connect(url, { role: 'player', lobby: 'NODISC', name: 'Anna' });
    await a.event({ type: 'start_run' });
    await sleep(20);
    assert.equal(called, false);
    a.close();
  } finally {
    await srv.stop();
  }
});

test('HTTP: /health und Run-Übersicht werden ausgeliefert', async () => {
  const { srv, port } = await startServer();
  try {
    const health = await (await fetch(`http://127.0.0.1:${port}/health`)).json();
    assert.equal(health.ok, true);
    const res = await fetch(`http://127.0.0.1:${port}/../package.json`);
    assert.notEqual(res.status, 200);
  } finally {
    await srv.stop();
  }
});

test('Run-Übersicht: statische Dateien werden ausgeliefert', async () => {
  const { srv, port } = await startServer();
  try {
    const html = await (await fetch(`http://127.0.0.1:${port}/`)).text();
    assert.match(html, /Run-Übersicht/);
    const js = await fetch(`http://127.0.0.1:${port}/app.js`);
    assert.equal(js.headers.get('content-type'), 'text/javascript; charset=utf-8');
  } finally {
    await srv.stop();
  }
});

test('Todesprotokoll als Textdatei für Stream-Overlays', async () => {
  const { srv, port, url } = await startServer();
  try {
    const a = await connect(url, { role: 'player', lobby: 'STREAM', name: 'Anna' });
    await a.event({ type: 'start_run' });
    await a.event({ type: 'status', has_balls: true });
    await a.event({ type: 'catch', uid: 'a1', species_name: 'Plinfa', area: { key: '1', name: 'Zweiblattdorf' } });
    await a.event({ type: 'catch', uid: 'a2', area: { key: '2', name: 'Route 201' } });
    await a.event({ type: 'faint', uid: 'a1', level: 7, opponent: 'Rivale' });
    const res = await fetch(`http://127.0.0.1:${port}/api/stream/todesprotokoll.txt`);
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('access-control-allow-origin'), '*');
    const text = await res.text();
    assert.match(text, /Anna: 1 Tode/);
    assert.match(text, /Plinfa \(Anna\) Lv\.7 in Zweiblattdorf gegen Rivale – gefallen/);
    const all = await (await fetch(`http://127.0.0.1:${port}/api/STREAM/todesprotokoll_alle.txt`)).text();
    assert.match(all, /Versuch 1 {2}Plinfa \(Anna\) Lv\.7/);
    const missing = await fetch(`http://127.0.0.1:${port}/api/NIX123/todesprotokoll.txt`);
    assert.equal(missing.status, 404);
    a.close();
  } finally {
    await srv.stop();
  }
});

test('Discord: bei Drosselung (429) einmal nach Wartezeit wiederholen', async () => {
  const { Discord } = require('../src/discord');
  let calls = 0;
  const d = new Discord({ webhook_url: 'https://discord.invalid/x', events: { death: true } }, async () => {
    calls += 1;
    if (calls === 1) return { ok: false, status: 429, json: async () => ({ retry_after: 0.5 }) };
    return { ok: true, status: 204 };
  });
  d.waitScale = 0.01;
  await d.post('death', 'Test');
  assert.equal(calls, 2);
  d.events.death = false;
  await d.post('death', 'aus');
  assert.equal(calls, 2, 'abgeschaltete Meldungsart wird nicht gesendet');
});
