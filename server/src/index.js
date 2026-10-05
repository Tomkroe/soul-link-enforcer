'use strict';
// Vermittlungsserver: HTTP (Run-Übersicht, /health) und WebSocket (/ws) auf einem Port.
// Start: npm start   (Port aus server/config.json oder Umgebungsvariable PORT)
const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');
const { loadConfig } = require('./config');
const { createCore } = require('./core');
const { createStore } = require('./store');
const { Discord } = require('./discord');
const { Hub } = require('./hub');
const { ROOT } = require('./lua-vm');

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
};

function serveStatic(req, res, webDir) {
  const url = new URL(req.url, 'http://x');
  let rel = decodeURIComponent(url.pathname);
  if (rel.endsWith('/')) rel += 'index.html';
  const file = path.normalize(path.join(webDir, rel));
  if (!file.startsWith(webDir)) {
    res.writeHead(403).end();
    return;
  }
  fs.readFile(file, (err, data) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Nicht gefunden');
      return;
    }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' }).end(data);
  });
}

async function createServer({ config = loadConfig(), store, now, logger = console, discordFetch } = {}) {
  const core = createCore();
  const st = store || createStore(config.storage);
  const discord = new Discord(config.discord, discordFetch);
  const hub = new Hub({ core, store: st, config, discord, now, logger });
  await hub.init();

  const webDir = path.join(ROOT, 'web');
  const server = http.createServer((req, res) => {
    if (req.url === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, lobbies: hub.lobbies.size }));
      return;
    }
    // Todesprotokoll als Text für Stream-Overlays: /api/<LOBBY>/todesprotokoll.txt (aktueller Versuch)
    // und /api/<LOBBY>/todesprotokoll_alle.txt (alle Versuche, dauerhaft)
    const v = /^\/api\/([A-Za-z0-9]{3,16})\/verstoesse\.txt$/.exec(req.url.split('?')[0]);
    if (v) {
      const lobby = hub.lobbies.get(v[1].toUpperCase());
      if (!lobby) {
        res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Lobby nicht gefunden\n');
        return;
      }
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*' });
      res.end(core.violations(hub.lobbyLedger(lobby)));
      return;
    }
    const m = /^\/api\/([A-Za-z0-9]{3,16})\/todesprotokoll(_alle)?\.txt$/.exec(req.url.split('?')[0]);
    if (m) {
      const lobby = hub.lobbies.get(m[1].toUpperCase());
      if (!lobby) {
        res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Lobby nicht gefunden\n');
        return;
      }
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*' });
      res.end(m[2] ? core.deathlogAll(hub.lobbyLedger(lobby)) : core.deathlog(lobby.state, hub.lobbyStats(lobby)));
      return;
    }
    if (config.serve_web) return serveStatic(req, res, webDir);
    res.writeHead(404).end();
  });
  const wss = new WebSocketServer({ server, path: '/ws' });
  wss.on('connection', (ws) => hub.attach(ws));

  let timer = null;
  return {
    hub,
    server,
    async start(port = config.port, host = config.host) {
      await new Promise((resolve) => server.listen(port, host, resolve));
      timer = setInterval(() => hub.tick(), 2000);
      return server.address().port;
    },
    async stop() {
      clearInterval(timer);
      for (const c of wss.clients) c.terminate();
      await new Promise((resolve) => wss.close(resolve));
      await new Promise((resolve) => server.close(resolve));
      await hub.flush();
    },
  };
}

if (require.main === module) {
  (async () => {
    const config = loadConfig();
    const srv = await createServer({ config });
    const port = await srv.start();
    const where = config.storage.type === 'file' ? config.storage.dir : 'Upstash Redis';
    console.log(`Soul-Link-Server läuft auf Port ${port} (Speicher: ${where}).`);
    console.log(`Run-Übersicht: http://localhost:${port}/   WebSocket: ws://localhost:${port}/ws`);
    const shutdown = async () => {
      console.log('Beende Server, speichere Zustand ...');
      await srv.stop();
      process.exit(0);
    };
    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);
  })().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = { createServer };
