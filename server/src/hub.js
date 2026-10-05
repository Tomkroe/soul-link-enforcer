'use strict';
// Vermittlung: Lobbys, Verbindungen, Herzschlag, Speicherung, Statistik, Discord.
// Die Spielregeln selbst stecken ausschließlich in der Lua-Engine (core.js -> lua/core).

const CLIENT_EVENTS = new Set([
  'leave', 'set_settings', 'set_teams', 'start_run', 'new_attempt',
  'status', 'catch', 'encounter_failed', 'faint', 'party', 'ack_absence', 'propose', 'vote', 'item_used',
]);

const CODE_RE = /^[A-Z0-9]{3,16}$/;

function normCode(code) {
  return String(code || '').trim().toUpperCase();
}

function playerId(name) {
  return String(name || '').trim().toLowerCase().replace(/\s+/g, '_');
}

class Hub {
  constructor({ core, store, config, discord, now = Date.now, logger = console }) {
    this.core = core;
    this.store = store;
    this.config = config;
    this.discord = discord;
    this.now = now;
    this.logger = logger;
    this.lobbies = new Map(); // code -> { state, meta, conns:Set, dirty }
    this.ledger = { players: {}, constellations: {} }; // Bilanz, fortgeschrieben von core/ledger.lua
    this.templates = {};      // name -> Einstellungen
    this.saveTimer = null;
    this.dirtyStats = false;
  }

  async init() {
    // Bilanz (Spieler + Team-Konstellationen). Ältere Speicherstände hatten nur "stats" (Spieler).
    this.ledger = (await this.store.get('ledger')) || { players: (await this.store.get('stats')) || {}, constellations: {} };
    this.templates = (await this.store.get('templates')) || {};
    for (const key of await this.store.list('lobby:')) {
      const saved = await this.store.get(key);
      if (!saved || !saved.state) continue;
      const check = this.core.check(saved.state);
      if (!check.ok) {
        this.logger.warn(`Lobby ${key} übersprungen: ${check.error}`);
        continue;
      }
      const lobby = { state: saved.state, meta: saved.meta || { acks: {} }, conns: new Set(), dirty: false };
      this.lobbies.set(saved.state.code, lobby);
      // Nach einem Neustart ist niemand verbunden: über die Engine offline setzen.
      for (const pid of lobby.state.order) {
        if (lobby.state.players[pid].online) this.apply(lobby, { type: 'offline', player: pid });
      }
    }
    await this.flush();
  }

  // Verbindungen ------------------------------------------------------------

  attach(ws) {
    const conn = { ws, role: null, lobby: null, player: null, lastSeen: this.now() };
    ws.on('message', (data) => {
      conn.lastSeen = this.now();
      let msg;
      try {
        msg = JSON.parse(String(data));
      } catch {
        return this.send(conn, { op: 'error', message: 'Ungültige Nachricht (kein JSON)' });
      }
      try {
        this.onMessage(conn, msg);
      } catch (e) {
        this.logger.error(e);
        this.send(conn, { op: 'error', message: `Serverfehler: ${e.message}` });
      }
    });
    ws.on('close', () => this.detach(conn));
    ws.on('error', () => {});
    return conn;
  }

  detach(conn) {
    const lobby = conn.lobby && this.lobbies.get(conn.lobby);
    if (!lobby) return;
    lobby.conns.delete(conn);
    if (conn.role === 'player' && !this.playerConn(lobby, conn.player)) {
      this.apply(lobby, { type: 'offline', player: conn.player });
    }
  }

  playerConn(lobby, pid) {
    for (const c of lobby.conns) if (c.role === 'player' && c.player === pid) return c;
    return null;
  }

  send(conn, msg) {
    if (conn.ws.readyState === 1) conn.ws.send(JSON.stringify(msg));
  }

  onMessage(conn, msg) {
    switch (msg.op) {
      case 'hello': return this.hello(conn, msg);
      case 'ping': return this.send(conn, { op: 'pong', t: this.now() });
      case 'event': return this.clientEvent(conn, msg);
      case 'template_save': return this.saveTemplate(conn, msg);
      default: return this.send(conn, { op: 'error', message: `Unbekannte Operation: ${msg.op}` });
    }
  }

  hello(conn, msg) {
    const code = normCode(msg.lobby);
    if (!CODE_RE.test(code)) {
      return this.send(conn, { op: 'error', fatal: true, message: 'Lobby-Code: 3 bis 16 Buchstaben oder Ziffern.' });
    }
    let lobby = this.lobbies.get(code);
    if (msg.role === 'viewer') {
      if (!lobby) return this.send(conn, { op: 'error', fatal: true, message: `Lobby ${code} gibt es nicht.` });
      conn.role = 'viewer';
      conn.lobby = code;
      lobby.conns.add(conn);
      this.send(conn, { op: 'welcome', role: 'viewer', lobby: code, templates: this.templates });
      return this.send(conn, this.stateMessage(lobby));
    }

    const name = String(msg.name || '').trim().slice(0, 20);
    const pid = playerId(name);
    if (!pid) return this.send(conn, { op: 'error', fatal: true, message: 'Spielername fehlt (config.lua).' });
    if (!lobby) {
      lobby = { state: this.core.newState(code), meta: { acks: {} }, conns: new Set(), dirty: true };
      this.lobbies.set(code, lobby);
      this.logger.log(`Lobby ${code} angelegt von ${name}`);
    }
    const joined = this.apply(lobby, { type: 'join', player: pid, name });
    if (joined.error) {
      return this.send(conn, { op: 'error', fatal: true, message: joined.error });
    }
    // Ältere Verbindung desselben Spielers ersetzen (z. B. nach Script-Neustart).
    const old = this.playerConn(lobby, pid);
    if (old) {
      lobby.conns.delete(old);
      try { old.ws.close(4000, 'Ersetzt durch neue Verbindung'); } catch { /* egal */ }
    }
    conn.role = 'player';
    conn.lobby = code;
    conn.player = pid;
    lobby.conns.add(conn);
    this.send(conn, {
      op: 'welcome', role: 'player', lobby: code, player: pid,
      last_seq: lobby.meta.acks[pid] || 0, templates: this.templates,
    });
    this.apply(lobby, { type: 'online', player: pid });
    this.send(conn, this.stateMessage(lobby));
  }

  clientEvent(conn, msg) {
    if (conn.role !== 'player') {
      return this.send(conn, { op: 'error', message: 'Nur Spieler können Ereignisse senden (Ansicht ist schreibgeschützt).' });
    }
    const lobby = this.lobbies.get(conn.lobby);
    const ev = msg.event || {};
    const seq = Number(msg.seq) || 0;
    const last = lobby.meta.acks[conn.player] || 0;
    if (seq > 0 && seq <= last) {
      return this.send(conn, { op: 'ack', seq, duplicate: true });
    }
    if (!CLIENT_EVENTS.has(ev.type)) {
      if (seq > 0) lobby.meta.acks[conn.player] = seq;
      return this.send(conn, { op: 'ack', seq, error: `Ereignis nicht erlaubt: ${ev.type}` });
    }
    const result = this.apply(lobby, { ...ev, player: conn.player }, seq);
    this.send(conn, { op: 'ack', seq, error: result.error || undefined });
  }

  async saveTemplate(conn, msg) {
    if (conn.role !== 'player') return;
    const name = String(msg.name || '').trim().slice(0, 30);
    if (!name || typeof msg.settings !== 'object') {
      return this.send(conn, { op: 'error', message: 'Vorlage braucht Namen und Einstellungen.' });
    }
    this.templates[name] = msg.settings;
    await this.store.set('templates', this.templates);
    this.send(conn, { op: 'templates', templates: this.templates });
  }

  // Ereignisse anwenden -------------------------------------------------------

  /** Wendet ein Ereignis über die Lua-Engine an und verteilt die Effekte. */
  apply(lobby, event, seq = 0) {
    const ev = { ...event, t: this.now() };
    const { state, effects } = this.core.apply(lobby.state, ev);
    const err = effects.find((e) => e.type === 'error');
    if (seq > 0) {
      lobby.meta.acks[ev.player] = seq;
      lobby.dirty = true;
    }
    if (err) {
      this.scheduleSave();
      return { error: err.text };
    }
    lobby.state = state;
    lobby.dirty = true;
    if (effects.some((e) => e.type === 'stat' || e.type === 'reset_stats' || e.type === 'result')) {
      const names = {};
      for (const pid of lobby.state.order) names[pid] = lobby.state.players[pid].name;
      this.ledger = this.core.ledgerApply(this.ledger, effects, names);
      this.dirtyStats = true;
    }
    for (const eff of effects) this.handleEffect(lobby, eff);
    this.broadcast(lobby, effects);
    this.scheduleSave();
    return { effects };
  }

  handleEffect(lobby, eff) {
    if (eff.type === 'discord' && this.discord) {
      this.discord.post(eff.kind, eff.text, lobby.state.code);
    }
  }

  lobbyStats(lobby) {
    const out = {};
    for (const pid of lobby.state.order) {
      out[pid] = this.ledger.players[pid] || { name: lobby.state.players[pid].name, deaths: 0, dragged: 0, attempts: 0, wins: 0 };
    }
    return out;
  }

  lobbyLedger(lobby) {
    return this.core.ledgerView(this.ledger, lobby.state.order);
  }

  stateMessage(lobby) {
    return {
      op: 'state',
      state: lobby.state,
      derived: this.core.derive(lobby.state),
      stats: this.lobbyStats(lobby),
      ledger: this.lobbyLedger(lobby),
      server_time: this.now(),
    };
  }

  broadcast(lobby, effects) {
    if (lobby.conns.size === 0) return;
    const stateMsg = JSON.stringify(this.stateMessage(lobby));
    const effMsg = effects.length ? JSON.stringify({ op: 'effects', effects }) : null;
    for (const c of lobby.conns) {
      if (c.ws.readyState !== 1) continue;
      if (effMsg) c.ws.send(effMsg);
      c.ws.send(stateMsg);
    }
  }

  // Herzschlag ----------------------------------------------------------------

  /** Prüft regelmäßig, ob Spieler noch Lebenszeichen senden. */
  tick() {
    const limit = this.config.heartbeat_timeout_s * 1000;
    const now = this.now();
    for (const lobby of this.lobbies.values()) {
      for (const pid of lobby.state.order) {
        const p = lobby.state.players[pid];
        if (!p || !p.online) continue;
        const c = this.playerConn(lobby, pid);
        if (!c || now - c.lastSeen > limit) {
          this.logger.log(`Lobby ${lobby.state.code}: kein Herzschlag von ${p.name}`);
          if (c) {
            lobby.conns.delete(c);
            try { c.ws.terminate(); } catch { /* egal */ }
          }
          this.apply(lobby, { type: 'offline', player: pid });
        }
      }
    }
  }

  // Speichern -----------------------------------------------------------------

  scheduleSave() {
    if (this.saveTimer) return;
    this.saveTimer = setTimeout(() => {
      this.saveTimer = null;
      this.flush().catch((e) => this.logger.error(`Speichern fehlgeschlagen: ${e.message}`));
    }, this.config.save_delay_ms);
  }

  async flush() {
    if (this.saveTimer) {
      clearTimeout(this.saveTimer);
      this.saveTimer = null;
    }
    for (const lobby of this.lobbies.values()) {
      if (!lobby.dirty) continue;
      lobby.dirty = false;
      await this.store.set(`lobby:${lobby.state.code}`, { state: lobby.state, meta: lobby.meta });
    }
    if (this.dirtyStats) {
      this.dirtyStats = false;
      await this.store.set('ledger', this.ledger);
    }
  }
}

module.exports = { Hub, playerId, normCode, CLIENT_EVENTS };
