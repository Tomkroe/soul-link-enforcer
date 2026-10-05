'use strict';
// Dauerhafte Speicherung als JSON. Zwei austauschbare Varianten mit gleicher Schnittstelle:
//   FileStore    – Dateien auf der Festplatte (eigener PC, VPS, Dienst mit Volume)
//   UpstashStore – Upstash Redis über REST (kostenlose Cloud-Variante ohne eigenes Dateisystem)
// Schnittstelle: async get(key) -> Objekt|null, async set(key, obj), async list(prefix) -> [key]
const fs = require('fs');
const path = require('path');

function safeName(key) {
  if (!/^[A-Za-z0-9_.:-]+$/.test(key)) throw new Error(`Ungültiger Speicherschlüssel: ${key}`);
  return key.replace(/:/g, '__');
}

class FileStore {
  constructor(dir) {
    this.dir = dir;
    fs.mkdirSync(dir, { recursive: true });
  }

  file(key) {
    return path.join(this.dir, `${safeName(key)}.json`);
  }

  async get(key) {
    const f = this.file(key);
    for (const candidate of [f, `${f}.bak`]) {
      try {
        return JSON.parse(fs.readFileSync(candidate, 'utf8'));
      } catch (e) {
        if (e.code !== 'ENOENT') console.warn(`Speicher: ${candidate} unlesbar (${e.message}), versuche Sicherung`);
      }
    }
    return null;
  }

  async set(key, value) {
    const f = this.file(key);
    const tmp = `${f}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(value, null, 1));
    if (fs.existsSync(f)) fs.copyFileSync(f, `${f}.bak`);
    fs.renameSync(tmp, f);
  }

  async list(prefix) {
    const p = safeName(prefix);
    return fs.readdirSync(this.dir)
      .filter((n) => n.endsWith('.json') && n.startsWith(p))
      .map((n) => n.slice(0, -5).replace(/__/g, ':'));
  }
}

class UpstashStore {
  constructor({ url, token, prefix = 'slink:', fetchImpl = globalThis.fetch }) {
    this.url = url.replace(/\/$/, '');
    this.token = token;
    this.prefix = prefix;
    this.fetch = fetchImpl;
  }

  async cmd(args) {
    const res = await this.fetch(this.url, {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(args),
    });
    const body = await res.json();
    if (!res.ok || body.error) throw new Error(`Upstash: ${body.error || res.status}`);
    return body.result;
  }

  async get(key) {
    const v = await this.cmd(['GET', this.prefix + key]);
    return v == null ? null : JSON.parse(v);
  }

  async set(key, value) {
    await this.cmd(['SET', this.prefix + key, JSON.stringify(value)]);
    await this.cmd(['SADD', `${this.prefix}__keys`, key]);
  }

  async list(prefix) {
    const keys = (await this.cmd(['SMEMBERS', `${this.prefix}__keys`])) || [];
    return keys.filter((k) => k.startsWith(prefix)).sort();
  }
}

function createStore(cfg) {
  if (cfg.type === 'upstash') return new UpstashStore(cfg);
  return new FileStore(cfg.dir);
}

module.exports = { FileStore, UpstashStore, createStore };
