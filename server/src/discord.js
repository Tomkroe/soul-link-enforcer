'use strict';
// Discord-Meldungen über einen Webhook. Ohne Adresse passiert nichts. Fehler werden nur protokolliert.

class Discord {
  constructor(cfg, fetchImpl = globalThis.fetch) {
    this.url = (cfg && cfg.webhook_url) || '';
    this.events = (cfg && cfg.events) || {};
    this.fetch = fetchImpl;
    this.queue = Promise.resolve();
  }

  enabled(kind) {
    return Boolean(this.url) && this.events[kind] !== false;
  }

  /** Stellt eine Meldung in die Warteschlange (nacheinander, damit Discord nicht drosselt). */
  post(kind, text, lobby) {
    if (!this.enabled(kind)) return this.queue;
    const content = `${lobby ? `[${lobby}] ` : ''}${text}`.slice(0, 1900);
    this.queue = this.queue.then(async () => {
      try {
        const res = await this.fetch(this.url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ content, allowed_mentions: { parse: [] } }),
        });
        if (!res.ok) console.warn(`Discord: Antwort ${res.status}`);
      } catch (e) {
        console.warn(`Discord: ${e.message}`);
      }
    });
    return this.queue;
  }
}

module.exports = { Discord };
