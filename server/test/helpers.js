'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const WebSocket = require('ws');
const { createServer } = require('../src/index');
const { DEFAULTS } = require('../src/config');

function tmpDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'slink-'));
}

const quiet = { log() {}, warn() {}, error() {} };

async function startServer({ dir = tmpDir(), clock, discordFetch, discordUrl = '' } = {}) {
  const config = {
    ...DEFAULTS,
    storage: { type: 'file', dir },
    save_delay_ms: 10,
    discord: { webhook_url: discordUrl, events: { death: true, group: true, badge: true, run_start: true, run_end: false } },
  };
  const srv = await createServer({ config, now: clock ? () => clock.t : undefined, logger: quiet, discordFetch });
  const port = await srv.start(0, '127.0.0.1');
  return { srv, port, dir, url: `ws://127.0.0.1:${port}/ws` };
}

/** Testclient: sammelt Nachrichten, wartet gezielt auf bestimmte. */
async function connect(url, hello) {
  const ws = new WebSocket(url);
  const inbox = [];
  const waiters = [];
  ws.on('message', (d) => {
    const msg = JSON.parse(String(d));
    inbox.push(msg);
    for (const w of [...waiters]) {
      if (w.pred(msg)) {
        waiters.splice(waiters.indexOf(w), 1);
        w.resolve(msg);
      }
    }
  });
  await new Promise((res, rej) => { ws.once('open', res); ws.once('error', rej); });
  let seq = 0;
  const client = {
    ws,
    inbox,
    send(msg) { ws.send(JSON.stringify(msg)); },
    waitFor(pred, ms = 3000) {
      const found = inbox.find(pred);
      if (found) {
        inbox.splice(inbox.indexOf(found), 1);
        return Promise.resolve(found);
      }
      return new Promise((resolve, reject) => {
        const w = { pred, resolve: (m) => { clearTimeout(timer); inbox.splice(inbox.indexOf(m), 1); resolve(m); } };
        const timer = setTimeout(() => reject(new Error('Zeitüberschreitung beim Warten')), ms);
        waiters.push(w);
      });
    },
    async event(ev) {
      seq += 1;
      const mySeq = seq;
      client.send({ op: 'event', seq: mySeq, event: ev });
      return client.waitFor((m) => m.op === 'ack' && m.seq === mySeq);
    },
    lastState() {
      for (let i = inbox.length - 1; i >= 0; i--) if (inbox[i].op === 'state') return inbox[i];
      return null;
    },
    async freshState() {
      inbox.length = 0;
      return client.waitFor((m) => m.op === 'state');
    },
    close() { ws.close(); },
  };
  if (hello) {
    client.send({ op: 'hello', ...hello });
    client.welcome = await client.waitFor((m) => m.op === 'welcome' || m.op === 'error');
    // Protokollregel: nach dem Wiederverbinden ab der letzten bestätigten Nummer weiterzählen.
    if (client.welcome.last_seq) seq = client.welcome.last_seq;
  }
  return client;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

module.exports = { startServer, connect, tmpDir, sleep };
