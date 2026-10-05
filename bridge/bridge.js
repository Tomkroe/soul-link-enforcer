#!/usr/bin/env node
'use strict';
// Lokale Brücke zwischen dem Emulator-Script und dem Vermittlungsserver.
//
// Warum: Lua in DeSmuME kann kein TLS (wss://) und LuaSocket ist dort nicht immer verfügbar.
// Die Brücke spricht WebSocket mit dem Server und tauscht Nachrichten über Dateien mit dem Script.
//
//   node bridge/bridge.js --url wss://mein-server.example/ws --dir bridge/exchange
//
// Austauschformat siehe lua/net/transport_file.lua. Ohne Lebenszeichen des Scripts
// (--idle Sekunden, Standard 90) beendet sich die Brücke selbst.
const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');

function parseArgs(argv) {
  const args = { url: 'ws://localhost:8080/ws', dir: path.join(__dirname, 'exchange'), idle: 90, poll: 50 };
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    const v = argv[i + 1];
    if (k === '--url') { args.url = v; i++; }
    else if (k === '--dir') { args.dir = path.resolve(v); i++; }
    else if (k === '--idle') { args.idle = Number(v); i++; }
    else if (k === '--poll') { args.poll = Number(v); i++; }
  }
  return args;
}

function pad(n) {
  return String(n).padStart(8, '0');
}

class Bridge {
  constructor({ url, dir, idle = 90, poll = 50, logger = console, now = Date.now }) {
    this.url = url;
    this.dir = dir;
    this.inDir = path.join(dir, 'in');
    this.outDir = path.join(dir, 'out');
    this.idleMs = idle * 1000;
    this.pollMs = poll;
    this.logger = logger;
    this.now = now;
    this.inN = 1;
    this.ws = null;
    this.connected = false;
    this.backoff = 1000;
    this.lastActivity = now();
    this.stopped = false;
    fs.mkdirSync(this.inDir, { recursive: true });
    fs.mkdirSync(this.outDir, { recursive: true });
  }

  start() {
    this.connect();
    this.timer = setInterval(() => this.pump(), this.pollMs);
    this.logger.log(`Brücke: ${this.url} <-> ${this.dir}`);
  }

  stop() {
    this.stopped = true;
    clearInterval(this.timer);
    clearTimeout(this.reconnectTimer);
    if (this.ws) this.ws.terminate();
  }

  connect() {
    if (this.stopped) return;
    const ws = new WebSocket(this.url);
    this.ws = ws;
    ws.on('open', () => {
      this.connected = true;
      this.backoff = 1000;
      this.logger.log('Brücke: mit Server verbunden');
      this.toScript({ op: 'bridge', connected: true });
    });
    ws.on('message', (data) => {
      try {
        this.toScript(JSON.parse(String(data)));
      } catch (e) {
        this.logger.warn(`Brücke: ungültige Servernachricht (${e.message})`);
      }
    });
    ws.on('close', () => {
      const was = this.connected;
      this.connected = false;
      if (was) {
        this.logger.log('Brücke: Verbindung getrennt');
        this.toScript({ op: 'bridge', connected: false });
      }
      if (!this.stopped) {
        this.reconnectTimer = setTimeout(() => this.connect(), this.backoff);
        this.backoff = Math.min(this.backoff * 2, 10000);
      }
    });
    ws.on('error', (e) => {
      if (!this.connected) this.logger.warn(`Brücke: Server nicht erreichbar (${e.message})`);
    });
  }

  /** Schreibt eine Nachricht als nächste Datei in in/ (atomar über Umbenennen). */
  toScript(msg) {
    const file = path.join(this.inDir, `${pad(this.inN)}.json`);
    this.inN += 1;
    const tmp = `${file}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(msg));
    fs.renameSync(tmp, file);
  }

  reset(nonce) {
    for (const f of fs.readdirSync(this.inDir)) fs.rmSync(path.join(this.inDir, f), { force: true });
    this.inN = 1;
    this.toScript({ op: 'bridge', reset: nonce, connected: this.connected });
  }

  /** Liest neue Dateien des Scripts und leitet sie weiter. */
  pump() {
    let files;
    try {
      files = fs.readdirSync(this.outDir).filter((f) => f.endsWith('.json')).sort();
    } catch {
      return;
    }
    // Ein Reset verwirft alles, was davor lag (alte Sitzungen).
    let start = 0;
    for (let i = files.length - 1; i >= 0; i--) {
      const msg = this.readOut(files[i], false);
      if (msg && msg.op === 'bridge_reset') { start = i; break; }
    }
    for (let i = 0; i < files.length; i++) {
      const msg = this.readOut(files[i], true);
      if (i < start || !msg) continue;
      this.lastActivity = this.now();
      if (msg.op === 'bridge_reset') {
        this.reset(msg.nonce);
      } else if (this.connected && this.ws.readyState === WebSocket.OPEN) {
        this.ws.send(JSON.stringify(msg));
      }
    }
    if (this.idleMs > 0 && this.now() - this.lastActivity > this.idleMs) {
      this.logger.log('Brücke: kein Lebenszeichen vom Script – beende mich.');
      this.stop();
      if (this.onIdleExit) this.onIdleExit();
    }
  }

  readOut(name, remove) {
    const file = path.join(this.outDir, name);
    try {
      const text = fs.readFileSync(file, 'utf8');
      if (remove) fs.rmSync(file, { force: true });
      return JSON.parse(text);
    } catch {
      if (remove) fs.rmSync(file, { force: true });
      return null;
    }
  }
}

if (require.main === module) {
  const args = parseArgs(process.argv.slice(2));
  const bridge = new Bridge(args);
  bridge.onIdleExit = () => process.exit(0);
  bridge.start();
  process.on('SIGINT', () => { bridge.stop(); process.exit(0); });
}

module.exports = { Bridge, parseArgs };
