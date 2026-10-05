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

function badgeBar(n, max) {
  const total = Math.max(8, max || 8);
  let out = '';
  for (let i = 0; i < total; i++) out += i < n ? '●' : '○';
  return `<span title="${n} Orden" aria-label="${n} von ${total} Orden">${out}</span>`;
}

function renderParties(state) {
  // Aktuelles Team jedes Spielers (wie im Spiel gemeldet), mit Gruppe und Status
  const rows = state.order.map((pid) => {
    const p = state.players[pid];
    const team = state.teams[p.team];
    const mons = (p.party || []).map((uid) => {
      const m = p.mons[uid];
      if (!m) return '<li class="muted">unbekannt</li>';
      const g = m.group && team ? team.groups[m.group] : null;
      const tag = g ? ` <span class="muted">(Gr. ${esc(m.group.slice(1))})</span>` : (m.status === 'frei' ? ' <span class="muted">(frei)</span>' : '');
      const st = m.stats || {};
      const gained = m.caught_level && m.level > m.caught_level ? `, +${m.level - m.caught_level} Lv.` : '';
      const fights = st.battles ? ` <span class="muted">· ${st.battles} Kämpfe, ${st.kos || 0} K.O.${gained}</span>` : '';
      return `<li class="${m.status === 'tot' ? 'dead' : ''}">${esc(monLabel(m))}${tag}${fights}</li>`;
    }).join('');
    return `<div class="stat"><b>${esc(p.name)}</b>${badgeBar(p.badges)}<ul class="feed">${mons || '<li class="muted">noch kein Team gemeldet</li>'}</ul></div>`;
  }).join('');
  return `<div class="stats">${rows}</div>`;
}

function renderPlayers(state, stats) {
  const rows = state.order.map((pid) => {
    const p = state.players[pid];
    const s = stats?.[pid] || {};
    return `<tr><td>${esc(p.name)}</td><td><span class="pill ${p.online ? 'pill-on' : 'pill-off'}">${p.online ? 'online' : 'offline'}</span></td>
      <td>${esc(p.area?.name || '–')}</td><td>${badgeBar(p.badges)}</td><td>${p.in_battle ? 'ja' : 'nein'}</td>
      <td>${s.deaths ?? 0}</td><td>${s.dragged ?? 0}</td><td>${s.attempts ?? 0}</td></tr>`;
  }).join('');
  return `<div class="scroll"><table><thead><tr><th>Spieler</th><th>Status</th><th>Gebiet</th><th>Orden</th><th>Kampf</th>
    <th>Tode</th><th>mitgerissen</th><th>Versuche</th></tr></thead><tbody>${rows}</tbody></table></div>`;
}

function renderRanking(state, derived) {
  const rows = derived.ranking.map((r) => {
    const hs = (state.teams[r.team].handicaps || []).filter((h) => h.active).map((h) => esc(h.text)).join('; ');
    return `<tr><td>${r.rank}.</td><td>${esc(r.name)}</td><td class="st-${r.status}">${r.status}</td>
    <td>${r.progress.toFixed(1)}</td><td>${r.alive}</td><td>${r.deaths}</td><td>${hs || '–'}</td></tr>`;
  }).join('');
  const mode = state.settings.scoring === 'ueberleben' ? 'Überleben' : 'Rennen';
  const goal = state.settings.goal.kind === 'orden' ? `${state.settings.goal.value} Orden` : 'Spielende';
  return `<p class="muted">Wertung: ${mode} · Ziel: ${goal}</p><div class="scroll"><table><thead><tr><th>#</th><th>Team</th><th>Status</th>
    <th>Orden Ø</th><th>lebende Monster</th><th>Tode</th><th>Handicap</th></tr></thead><tbody>${rows}</tbody></table></div>`;
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

function renderLedger(state, ledger) {
  if (!ledger) return '<p class="muted">Noch keine Bilanz.</p>';
  const places = (p) => Object.keys(p || {}).sort((a, b) => a - b).map((k) => `${k}.: ${p[k]}×`).join(', ') || '–';
  const prow = state.order.map((pid) => {
    const p = ledger.players[pid] || {};
    return `<tr><td>${esc(p.name || pid)}</td><td>${p.runs ?? 0}</td><td>${p.wins ?? 0}</td><td>${esc(places(p.places))}</td>
      <td>${p.deaths ?? 0}</td><td>${p.dragged ?? 0}</td><td>${p.attempts ?? 0}</td></tr>`;
  }).join('');
  let html = `<div class="scroll"><table><thead><tr><th>Spieler</th><th>Runs</th><th>Siege</th><th>Platzierungen</th>
    <th>Tode</th><th>mitgerissen</th><th>Versuche</th></tr></thead><tbody>${prow}</tbody></table></div>`;
  const cons = Object.values(ledger.constellations || {});
  if (cons.length) {
    const rows = cons.map((c) => {
      const teams = Object.values(c.teams).map((t) => `${esc(t.label)}: ${t.wins} Siege (${esc(places(t.places))})`).join('<br>');
      return `<tr><td>${esc(c.label)}</td><td>${c.runs}</td><td>${teams}</td></tr>`;
    }).join('');
    html += `<h2 style="margin-top:14px">Team-Konstellationen</h2><div class="scroll"><table><thead><tr><th>Konstellation</th>
      <th>Runs</th><th>Ergebnisse</th></tr></thead><tbody>${rows}</tbody></table></div>`;
  }
  return html;
}

function renderDeathlogAll(state, ledger) {
  const log = (ledger && ledger.deathlog) || [];
  if (!log.length) return '<p class="muted">Noch keine Tode.</p>';
  const rows = log.slice(0, 100).map((d) => `<tr><td>${time(d.t)}</td><td>${d.attempt ?? ''}</td><td>${esc(d.label)}</td>
    <td>${esc(d.player_name || pname(state, d.player))}</td><td>${d.level || ''}</td><td>${esc(d.area)}</td>
    <td>${esc(d.opponent || d.by)}</td><td>${CAUSES[d.cause] || esc(d.cause)}</td></tr>`).join('');
  return `<div class="scroll"><table><thead><tr><th>Zeit</th><th>Versuch</th><th>Monster</th><th>Spieler</th><th>Lv.</th>
    <th>Gebiet</th><th>Gegner / Auslöser</th><th>Art</th></tr></thead><tbody>${rows}</tbody></table></div>`;
}

const VIOLATIONS = { orden_aufhol: 'Orden im Aufhol-Modus', items_im_kampf: 'Items im Kampf', savestate: 'alter Spielstand',
  level_cap: 'über dem Level-Cap', fang_gesperrt: 'gesperrter Fang' };

const ACHIEVEMENTS = [
  ['erster_fang', 'Erster Fang'], ['sammler', 'Sammler'], ['glitzer', 'Glitzer'], ['erster_orden', 'Erster Orden'],
  ['ordensjaeger', 'Ordensjäger'], ['achtfach', 'Achtfach'], ['makellos', 'Makellos'], ['aufholjagd', 'Aufholjagd'],
  ['volles_haus', 'Volles Haus'], ['sieger', 'Sieger'], ['hattrick', 'Hattrick'], ['durchhalter', 'Durchhalter'],
  ['pechvogel', 'Pechvogel'], ['friedhofsgaertner', 'Friedhofsgärtner'], ['seelenverwandt', 'Seelenverwandt'],
  ['tippkoenig', 'Tippkönig'], ['kaempfer', 'Kämpfer'],
];

const TIP_LABELS = { ohne_tod: 'ohne Tod', ein_tod: '1 Tod', mehr: '2+ Tode oder ausgeschieden' };

function renderBattleStats(state) {
  const all = [];
  for (const pid of state.order) {
    const p = state.players[pid];
    for (const m of Object.values(p.mons || {})) {
      if (m.stats && (m.stats.battles || m.stats.kos)) all.push({ m, p });
    }
  }
  if (!all.length) return '<p class="muted">Noch keine Kämpfe erfasst.</p>';
  all.sort((a, b) => (b.m.stats.kos || 0) - (a.m.stats.kos || 0) || (b.m.stats.battles || 0) - (a.m.stats.battles || 0));
  const rows = all.slice(0, 20).map(({ m, p }) => `<tr class="${m.status === 'tot' ? 'dead' : ''}"><td>${esc(monLabel(m))}</td>
    <td>${esc(p.name)}</td><td>${m.stats.battles || 0}</td><td>${m.stats.fought || 0}</td><td>${m.stats.kos || 0}</td>
    <td>${m.caught_level && m.level > m.caught_level ? `+${m.level - m.caught_level}` : '–'}</td></tr>`).join('');
  return `<div class="scroll"><table><thead><tr><th>Monster</th><th>Spieler</th><th>Kämpfe</th><th>eingesetzt</th>
    <th>K.O.</th><th>Level gewonnen</th></tr></thead><tbody>${rows}</tbody></table></div>`;
}

function renderTips(state) {
  const rounds = Object.values(state.tips || {}).sort((a, b) => b.opened_at - a.opened_at);
  if (!rounds.length) return '<p class="muted">Noch keine Tipprunde (im Script Taste T vor dem Arenakampf).</p>';
  return `<ul class="feed">${rounds.map((r) => {
    const tips = Object.entries(r.tips || {}).map(([pid, opt]) => `${esc(pname(state, pid))}: ${esc(TIP_LABELS[opt] || opt)}`).join(', ') || 'noch keine Tipps';
    const res = r.status === 'offen' ? '<b>offen</b>' : `Ergebnis: <b>${esc(TIP_LABELS[r.result] || r.result)}</b>`;
    return `<li>${esc(pname(state, r.target))} – ${res} · ${tips}</li>`;
  }).join('')}</ul>`;
}

function renderAchievements(state, ledger) {
  if (!ledger) return '<p class="muted">Noch keine Bilanz.</p>';
  return `<div class="stats">${state.order.map((pid) => {
    const p = ledger.players[pid] || {};
    const got = p.achievements || {};
    const items = ACHIEVEMENTS.map(([id, name]) => `<li class="${got[id] ? '' : 'muted'}">${got[id] ? '★' : '☆'} ${esc(name)}</li>`).join('');
    const n = ACHIEVEMENTS.filter(([id]) => got[id]).length;
    return `<div class="stat"><b>${esc(p.name || pid)}</b>${n}/${ACHIEVEMENTS.length}<ul class="feed">${items}</ul></div>`;
  }).join('')}</div>`;
}

function renderViolations(state, ledger) {
  const log = (ledger && ledger.violations) || [];
  if (!log.length) return '<p class="muted">Keine Regelverstöße.</p>';
  const rows = log.slice(0, 100).map((v) => `<tr><td>${time(v.t)}</td><td>${v.attempt ?? ''}</td>
    <td>${esc(v.player_name || pname(state, v.player))}</td><td>${esc(VIOLATIONS[v.kind] || v.kind)}</td><td>${esc(v.text)}</td></tr>`).join('');
  return `<div class="scroll"><table><thead><tr><th>Zeit</th><th>Versuch</th><th>Spieler</th><th>Art</th><th>Meldung</th></tr></thead>
    <tbody>${rows}</tbody></table></div>`;
}

function render() {
  if (!last) return;
  const { state, derived, stats } = last;
  let html = card('Überblick', renderHeader(state, derived) + renderPlayers(state, stats), true);
  const summary = derived.summary || [];
  if (state.phase === 'finished' && summary.length) {
    html += card(`Statistik – Run ${esc(state.result)}`, `<ul>${summary.map((l) => `<li>${esc(l)}</li>`).join('')}</ul>`, true);
  }
  if (state.phase !== 'lobby') html += card('Aktuelle Teams', renderParties(state), true);
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
  html += card('Bilanz (alle Runs)', renderLedger(state, last.ledger), true);
  html += card('Todesprotokoll (alle Versuche)', renderDeathlogAll(state, last.ledger), true);
  html += card('Regelverstöße', renderViolations(state, last.ledger), true);
  html += card('Erfolge', renderAchievements(state, last.ledger), true);
  if (state.phase !== 'lobby') html += card('Tipprunden', renderTips(state));
  if (state.phase !== 'lobby') html += card('Kampfstatistik', renderBattleStats(state));
  app.innerHTML = html;
}
