'use strict';
// Discord-Meldungen über einen Webhook. Ohne Adresse passiert nichts. Fehler werden nur protokolliert.

class Discord {
  constructor(cfg, fetchImpl = globalThis.fetch) {
    this.url = (cfg && cfg.webhook_url) || '';
    this.events = (cfg && cfg.events) || {};
    this.fetch = fetchImpl;
    this.queue = Promise.resolve();
    this.waitScale = 1; // für Tests verkleinerbar
  }

  enabled(kind) {
    return Boolean(this.url) && this.events[kind] !== false;
  }

  /** Stellt eine Meldung in die Warteschlange (nacheinander, damit Discord nicht drosselt). */
  post(kind, text, lobby) {
    if (!this.enabled(kind)) return this.queue;
    const content = `${lobby ? `[${lobby}] ` : ''}${text}`.slice(0, 1900);
    const body = JSON.stringify({ content, allowed_mentions: { parse: [] } });
    this.queue = this.queue.then(async () => {
      // Bei Drosselung (429) einmal nach der von Discord genannten Wartezeit wiederholen (höchstens 10 s).
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          const res = await this.fetch(this.url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body });
          if (res.status === 429 && attempt === 0) {
            let wait = 1;
            try { wait = Number((await res.json()).retry_after) || 1; } catch { /* Standard 1 s */ }
            await new Promise((r) => setTimeout(r, Math.min(10, wait) * 1000 * this.waitScale));
            continue;
          }
          if (!res.ok) console.warn(`Discord: Antwort ${res.status}`);
        } catch (e) {
          console.warn(`Discord: ${e.message}`);
        }
        break;
      }
    });
    return this.queue;
  }
}

module.exports = { Discord };
