#!/usr/bin/env node
'use strict';
// Startet den Vermittlungsserver und einen kostenlosen Cloudflare-Tunnel mit einem Befehl:
//   npm run tunnel
// Gibt die Adresse für config.lua (wss://…/ws) und die Run-Übersicht aus. Braucht "cloudflared" im PATH
// (Windows: winget install --id Cloudflare.cloudflared) oder den Pfad in der Umgebungsvariable CLOUDFLARED.
const { spawn } = require('child_process');
const { createServer } = require('../server/src/index');
const { loadConfig } = require('../server/src/config');

/** Sucht die öffentliche Tunnel-Adresse in der Ausgabe von cloudflared. */
function extractUrl(text) {
  const m = /https:\/\/[a-z0-9-]+\.trycloudflare\.com/i.exec(String(text));
  return m ? m[0] : null;
}

function instructions(url, lobby = 'SOUL01') {
  const host = url.replace(/^https:\/\//, '');
  return [
    '',
    '================ Tunnel bereit ================',
    `In config.lua aller Spieler:   server_url = "wss://${host}/ws"`,
    `Run-Übersicht:                 ${url}/  (Lobby-Code eingeben)`,
    `Todesprotokoll (Stream):       ${url}/api/${lobby}/todesprotokoll.txt`,
    'Die Adresse ändert sich bei jedem Start des Tunnels.',
    'Beenden mit Strg+C.',
    '===============================================',
    '',
  ].join('\n');
}

async function main() {
  const config = loadConfig();
  const srv = await createServer({ config });
  const port = await srv.start();
  console.log(`Server läuft lokal auf Port ${port}.`);
  const exe = process.env.CLOUDFLARED || 'cloudflared';
  const child = spawn(exe, ['tunnel', '--no-autoupdate', '--url', `http://localhost:${port}`], { stdio: ['ignore', 'pipe', 'pipe'] });
  let shown = false;
  const onData = (d) => {
    const url = !shown && extractUrl(d);
    if (url) {
      shown = true;
      console.log(instructions(url));
    }
  };
  child.stdout.on('data', onData);
  child.stderr.on('data', onData);
  child.on('error', () => {
    console.log([
      '',
      'cloudflared wurde nicht gefunden. Der Server läuft trotzdem lokal (nur in deinem Netz erreichbar).',
      'Installation (Windows):  winget install --id Cloudflare.cloudflared',
      'Danach "npm run tunnel" erneut starten. Anleitung: README, Abschnitt "Server erreichbar machen".',
      '',
    ].join('\n'));
  });
  child.on('exit', (code) => {
    if (shown) console.log(`Tunnel beendet (Code ${code}).`);
  });
  const stop = async () => {
    child.kill();
    await srv.stop();
    process.exit(0);
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = { extractUrl, instructions };
