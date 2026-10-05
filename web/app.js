// Run-Übersicht: verbindet sich als Zuschauer mit dem Vermittlungsserver und zeigt den Zustand an.
// Keine Regel-Logik hier: abgeleitete Werte (Rangliste, Gebiets-Übersicht, Aufhol-Modus) liefert der Server
// aus der Lua-Regel-Engine im Feld "derived".
'use strict';

const $ = (sel) => document.querySelector(sel);
const app = $('#app');
let ws = null;
let retry = null;
let last = null;
const feed = [];

function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function time(t) {
  return t ? new Date(t).toLocaleString('de-DE', { dateStyle: 'short', timeStyle: 'short' }) : '–';
}
function pname(state, pid) {
  return state.players[pid]?.name ?? pid;
}
function monLabel(m) {
  if (!m) return '?';
  const base = m.nickname && m.species_name && m.nickname !== m.species_name ? `${m.nickname} (${m.species_name})` : (m.nickname || m.species_name || `Art #${m.species}`);
  const types = Array.isArray(m.types) && m.types.length ? ` · ${m.types.join('/')}` : '';
  return `${base}${m.level ? ` Lv.${m.level}` : ''}${types}`;
}
function setConn(text, cls) {
  const el = $('#conn');
  el.textContent = text;
  el.className = `pill ${cls}`;
}

// Verbindung -------------------------------------------------------------------

function defaultServer() {
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  return location.protocol.startsWith('http') && !location.hostname.endsWith('github.io') ? `${proto}//${location.host}/ws` : '';
}

function connect(server, lobby) {
  clearTimeout(retry);
  if (ws) { ws.onclose = null; ws.close(); }
  setConn('verbinde …', 'pill-warn');
  try {
    ws = new WebSocket(server);
  } catch (e) {
    setConn('ungültige Adresse', 'pill-off');
    return;
  }
  ws.onopen = () => {
    ws.send(JSON.stringify({ op: 'hello', role: 'viewer', lobby }));
    setConn('verbunden', 'pill-on');
  };
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.op === 'state') { last = msg; render(); }
    else if (msg.op === 'effects') {
      for (const e of msg.effects) {
        if (e.type === 'notify') feed.unshift({ t: Date.now(), text: e.text, level: e.level });
      }
      feed.splice(60);
    } else if (msg.op === 'error') {
      setConn(msg.message, 'pill-off');
      if (msg.fatal) { ws.onclose = null; ws.close(); }
    }
  };
  ws.onclose = () => {
    setConn('getrennt – neuer Versuch …', 'pill-off');
    retry = setTimeout(() => connect(server, lobby), 3000);
  };
}

$('#connect').addEventListener('submit', (e) => {
  e.preventDefault();
  const server = $('#server').value.trim();
  const lobby = $('#lobby').value.trim().toUpperCase();
  try { localStorage.setItem('slink', JSON.stringify({ server, lobby })); } catch { /* egal */ }
  const url = new URL(location.href);
  url.searchParams.set('lobby', lobby);
  url.searchParams.set('server', server);
  history.replaceState(null, '', url);
  connect(server, lobby);
});

(function init() {
  const params = new URLSearchParams(location.search);
  let saved = {};
  try { saved = JSON.parse(localStorage.getItem('slink') || '{}'); } catch { /* egal */ }
  $('#server').value = params.get('server') || saved.server || defaultServer();
  $('#lobby').value = params.get('lobby') || saved.lobby || '';
  if ($('#server').value && $('#lobby').value) connect($('#server').value, $('#lobby').value.toUpperCase());
})();

// Darstellung -----------------------------------------------------------------

const SETTING_LABELS = {
  level_cap: 'Level-Cap', rare_candies: 'Sonderbonbons', grace: 'Schonfrist', dupes_clause: 'Duplikat-Klausel',
  shiny_clause: 'Schillernd-Klausel', gifts_count: 'Geschenke zählen', follow_mode: 'Folgemodus',
  death_log: 'Todesprotokoll', skip_prologue: 'Prolog überspringen', skip_nickname: 'Spitznamen überspringen',
};
const CAUSES = { eigener: 'gefallen', mitgerissen: 'mitgerissen', gebiet_verbraucht: 'Gebiet verbraucht', gesperrt: 'gesperrt' };

function card(title, body, wide) {
  return `<section class="card${wide ? ' wide' : ''}"><h2>${title}</h2>${body}</section>`;
}

function renderHeader(state, derived) {
  const phase = { lobby: 'Lobby', running: 'Run läuft', finished: `Run beendet (${state.result})` }[state.phase];
  let html = `<p><b>Lobby ${esc(state.code)}</b> · ${phase} · Versuch ${state.attempt} · Vorlage ${esc(state.settings.preset)}</p>`;
  for (const pid of state.order) {
    const d = derived.players[pid];
    if (d && d.catchup && state.players[pid].online) {
      const gym = d.gym_allowed ? '' : ` ${esc(d.gym_reason.replace(/^Aufhol-Modus: /, ''))}`;
      html += `<div class="banner">Aufhol-Modus für ${esc(pname(state, pid))} (offline: ${d.offline_partners.map((q) => esc(pname(state, q))).join(', ')}).${gym}</div>`;
    }
  }
  return html;
}

function renderPlayers(state, stats) {
  const rows = state.order.map((pid) => {
    const p = state.players[pid];
    const s = stats?.[pid] || {};
    return `<tr><td>${esc(p.name)}</td><td><span class="pill ${p.online ? 'pill-on' : 'pill-off'}">${p.online ? 'online' : 'offline'}</span></td>
      <td>${esc(p.area?.name || '–')}</td><td>${p.badges}</td><td>${p.in_battle ? 'ja' : 'nein'}</td>
      <td>${s.deaths ?? 0}</td><td>${s.dragged ?? 0}</td><td>${s.attempts ?? 0}</td></tr>`;
  }).join('');
  return `<div class="scroll"><table><thead><tr><th>Spieler</th><th>Status</th><th>Gebiet</th><th>Orden</th><th>Kampf</th>
    <th>Tode</th><th>mitgerissen</th><th>Versuche</th></tr></thead><tbody>${rows}</tbody></table></div>`;
}

function renderRanking(state, derived) {
  const rows = derived.ranking.map((r) => `<tr><td>${r.rank}.</td><td>${esc(r.name)}</td><td class="st-${r.status}">${r.status}</td>
    <td>${r.progress.toFixed(1)}</td><td>${r.alive}</td><td>${r.deaths}</td></tr>`).join('');
  return `<table><thead><tr><th>#</th><th>Team</th><th>Status</th><th>Orden Ø</th><th>lebende Gruppen</th><th>Tode</th></tr></thead><tbody>${rows}</tbody></table>`;
}

function renderGroups(state, team) {
  if (!team.group_order.length) return '<p class="muted">Noch keine Gruppen.</p>';
  const head = team.members.map((pid) => `<th>${esc(pname(state, pid))}</th>`).join('');
  const rows = team.group_order.map((gid) => {
    const g = team.groups[gid];
    const cells = team.members.map((pid) => {
      const uid = g.members[pid];
      const m = uid ? state.players[pid].mons[uid] : null;
      const inParty = uid && state.players[pid].party.includes(uid);
      return `<td class="${m && m.status === 'tot' ? 'dead' : ''}">${m ? esc(monLabel(m)) + (inParty ? ' ★' : '') : '<span class="muted">–</span>'}</td>`;
    }).join('');
    return `<tr><td>${esc(gid.slice(1))}</td><td>${esc(g.area_name)}</td>${cells}<td class="st-${g.status}">${g.status}</td></tr>`;
  }).join('');
  return `<div class="scroll"><table><thead><tr><th>Nr.</th><th>Gebiet</th>${head}<th>Status</th></tr></thead><tbody>${rows}</tbody></table></div>
    <p class="muted">★ = im Team</p>`;
}

function renderAreas(state, team, derived) {
  const pid = team.members[0];
  const areas = derived.players[pid]?.areas || [];
  if (!areas.length) return '<p class="muted">Noch keine Gebiete betreten.</p>';
  const head = team.members.map((q) => `<th>${esc(pname(state, q))}</th>`).join('');
  const rows = areas.map((a) => {
    const cells = a.players.map((ps) => {
      const cur = state.players[ps.player].area?.key === a.key;
      return `<td class="st-${ps.status.split(' ')[0]}${cur ? ' cur' : ''}">${esc(ps.status)}${cur ? ' ◀' : ''}</td>`;
    }).join('');
    return `<tr><td>${esc(a.name)}</td>${cells}<td>${a.group ? esc(a.group.slice(1)) : ''}</td></tr>`;
  }).join('');
  return `<div class="scroll"><table><thead><tr><th>Gebiet</th>${head}<th>Gruppe</th></tr></thead><tbody>${rows}</tbody></table></div>`;
}

function renderGraveyard(state, team) {
  if (!team.graveyard.length) return '<p class="muted">Noch niemand gestorben.</p>';
  const rows = [...team.graveyard].reverse().map((d) => `<tr><td>${time(d.t)}</td><td>${esc(d.label)}</td><td>${esc(pname(state, d.player))}</td>
    <td>${d.level || ''}</td><td>${esc(d.area)}</td><td>${esc(d.opponent || d.by)}</td><td>${CAUSES[d.cause] || esc(d.cause)}</td></tr>`).join('');
  return `<div class="scroll"><table><thead><tr><th>Zeit</th><th>Monster</th><th>Spieler</th><th>Lv.</th><th>Gebiet</th><th>Gegner / Auslöser</th><th>Art</th></tr></thead>
    <tbody>${rows}</tbody></table></div>`;
}

function renderSettings(s) {
  const flags = Object.entries(SETTING_LABELS).map(([k, label]) => `<li>${label}: <b>${s[k] ? 'an' : 'aus'}</b></li>`).join('');
  return `<ul>${flags}<li>Items im Kampf: <b>${esc(s.battle_items.mode)}</b></li><li>Randomizer: <b>${esc(s.randomizer.mode)}</b></li>
    <li>Ziel: <b>${s.goal.kind === 'orden' ? `${s.goal.value} Orden` : 'Spielende'}</b></li></ul>`;
}

function renderHistory(state) {
  if (!state.history.length) return '<p class="muted">Noch keine abgeschlossenen Versuche.</p>';
  const rows = [...state.history].reverse().map((h) => {
    const players = Object.values(h.players).map((p) => `${esc(p.name)}: ${p.badges} Orden, ${p.deaths} Tode`).join(' · ');
    return `<tr><td>${h.attempt}</td><td>${esc(h.result)}</td><td>${time(h.started_at)}</td><td>${time(h.ended_at)}</td><td>${players}</td></tr>`;
  }).join('');
  return `<div class="scroll"><table><thead><tr><th>Versuch</th><th>Ergebnis</th><th>Start</th><th>Ende</th><th>Spieler</th></tr></thead><tbody>${rows}</tbody></table></div>`;
}

function renderLog(state) {
  const items = feed.map((f) => `<li>${new Date(f.t).toLocaleTimeString('de-DE')} – ${esc(f.text)}</li>`);
  const log = [...state.log].reverse().slice(0, 50).map((l) => `<li>${time(l.t)} – ${esc(l.text)}</li>`);
  return `<ul class="feed">${(items.length ? items : log).join('') || '<li class="muted">Noch keine Einträge.</li>'}</ul>`;
}

function render() {
  if (!last) return;
  const { state, derived, stats } = last;
  let html = card('Überblick', renderHeader(state, derived) + renderPlayers(state, stats), true);
  if (state.team_order.length > 1) html += card('Rangliste', renderRanking(state, derived), true);
  for (const tid of state.team_order) {
    const team = state.teams[tid];
    const suffix = state.team_order.length > 1 ? ` – ${esc(team.name)}` : '';
    html += card(`Gruppen${suffix}`, renderGroups(state, team), true);
    html += card(`Gebiete${suffix}`, renderAreas(state, team, derived));
    html += card(`Friedhof &amp; Todesprotokoll${suffix}`, renderGraveyard(state, team), true);
  }
  html += card('Aktive Regeln', renderSettings(state.settings));
  html += card('Verlauf', renderLog(state));
  html += card('Frühere Versuche', renderHistory(state), true);
  app.innerHTML = html;
}
