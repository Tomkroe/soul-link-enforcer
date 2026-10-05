'use strict';
// Lädt server/config.json und überschreibt Werte aus Umgebungsvariablen (für Cloud-Dienste).
const fs = require('fs');
const path = require('path');
const { ROOT } = require('./lua-vm');

const DEFAULTS = {
  port: 8080,
  host: '0.0.0.0',
  storage: { type: 'file', dir: './server/data' },
  heartbeat_timeout_s: 20,
  save_delay_ms: 1000,
  serve_web: true,
  discord: { webhook_url: '', events: { death: true, group: true, badge: true, run_start: true, run_end: true } },
};

function merge(a, b) {
  const out = { ...a };
  for (const [k, v] of Object.entries(b || {})) {
    out[k] = v && typeof v === 'object' && !Array.isArray(v) ? merge(a[k] || {}, v) : v;
  }
  return out;
}

function loadConfig(file = path.join(ROOT, 'server', 'config.json'), env = process.env) {
  let cfg = DEFAULTS;
  if (fs.existsSync(file)) cfg = merge(cfg, JSON.parse(fs.readFileSync(file, 'utf8')));
  if (env.PORT) cfg.port = Number(env.PORT);
  if (env.DATA_DIR) cfg.storage = { ...cfg.storage, type: 'file', dir: env.DATA_DIR };
  if (env.UPSTASH_REDIS_REST_URL && env.UPSTASH_REDIS_REST_TOKEN) {
    cfg.storage = { type: 'upstash', url: env.UPSTASH_REDIS_REST_URL, token: env.UPSTASH_REDIS_REST_TOKEN, prefix: env.STORAGE_PREFIX || 'slink:' };
  }
  if (env.DISCORD_WEBHOOK_URL) cfg.discord = { ...cfg.discord, webhook_url: env.DISCORD_WEBHOOK_URL };
  if (cfg.storage.type === 'file' && !path.isAbsolute(cfg.storage.dir)) {
    cfg.storage = { ...cfg.storage, dir: path.join(ROOT, cfg.storage.dir) };
  }
  return cfg;
}

module.exports = { loadConfig, DEFAULTS };
