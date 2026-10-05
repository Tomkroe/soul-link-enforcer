# Fortschritt

Stand: 05.10.2026, Cloud-Sitzung ohne Emulator. Gebaut wurde alles, was sich ohne DeSmuME bauen und testen
lässt. Phase 0 und alles mit Speicheradressen ist übersprungen, die Schnittstellen dafür stehen.

## Heute Abend am PC zuerst (Platin, CPUD) – in dieser Reihenfolge

1. **Repo holen und testen:** `git pull`, `npm install`, `npm test`. Erwartet: alles grün.
2. **Machbarkeit:** Platin in DeSmuME laden, `lua/check.lua` ausführen, TESTEN.md Abschnitt 0 ausfüllen.
   Erwartet: Game-Code `CPUD`, „Profil geladen: Platin“, Datei-Test OK.
3. **Adress-Suche:** Spielstand mit mindestens einem Monster laden. `check.lua` findet das Team über die
   Kandidaten aus den US-Werkzeugen oder per Signatursuche und zeigt Orden, Karte, Bälle und Kampfstatus live
   an. TESTEN.md Abschnitt 0b abarbeiten und **`local/adressen_CPUD.txt` an mich schicken**. Damit kann ich
   abweichende deutsche Adressen eintragen.
4. **Verbindung im Lesemodus:** `npm start`, dann `lua/main.lua`. Overlay: „Verbunden“ und
   „Profil Platin: 0/… Adressen getestet – nur lesen“. Übersicht unter <http://localhost:8080/>.
5. Stimmen die Werte, in `lua/profiles/CPUD.lua` die Lese-Einträge auf `tested = true` setzen und TESTEN.md
   Abschnitt 1 und 2 durchgehen. Erst danach Abschnitt 3 mit `write_enabled = true`.

## Fertig (automatisch getestet)

| Bereich | Inhalt | Tests |
|---|---|---|
| Projektgerüst | Ordnerstruktur, `package.json`, IntelliJ-Startkonfigurationen (`.run/`), CI (GitHub Actions, Lua 5.1 + fengari), Pages-Workflow, Render-Blueprint, `npm run tunnel` (Server + Tunnel in einem Befehl), `npm run restore`, Windows-Startdateien | `scripts/test` |
| `lua/lib` | JSON (deterministisch), Bit-Operationen ohne native Operatoren | `tests/lib` |
| `lua/core` | Zustandsmodell, Reducer, Abfragen: Lobby (1–4 Spieler, Einstellungen, Vorlagen, Teams), Link-Gruppen, Gebietsverbrauch, gekoppelter Tod, Team-Prüfung (Regeln 4/5), Level-Cap-Abfrage, Run verloren/gewonnen, **Aufhol-Modus** komplett (Orden-Sperre, Fang-Sperre, Abwesenheitsliste), Savestate-Erkennung, Abstimmungen (Einstellungen, Zähler zurücksetzen, aufgeben), Duplikat-/Schillernd-Klausel, Schonfrist, Wettkampf-Teams mit Rangliste | `tests/core`: jede Regel für 1, 2, 3 und 4 Spieler, Aufhol-Modus mit 2/3/4 Spielern, 2v2 und 1v1 |
| `server/` | Lobby per Code, Lua-Engine über fengari, Herzschlag (offline nach 20 s), Wiedereinstieg mit Sequenznummern, Speicherung als JSON (Datei oder Upstash), Statistik dauerhaft und lobbyübergreifend, Discord-Webhook (je Art abschaltbar), Zuschauer schreibgeschützt, eigene Vorlagen speichern, liefert die Run-Übersicht aus | `server/test`: inkl. Neustart-Persistenz, Herzschlag, Abwesenheitsliste |
| `bridge/` + `lua/net` | Brücke Script ↔ Server (Dateiaustausch, startet automatisch, beendet sich ohne Lebenszeichen), Client mit Warteschlange, Bestätigungen, Ping, lokaler Kopie der Todeszähler | `tests/net`, `server/test/e2e.test.js` (**echtes Lua 5.1 → Brücke → Server**) |
| `lua/mem` | PK4/PK5: Entschlüsselung, Blockreihenfolge, Prüfsumme, Felder, KP schreiben, Erfahrung deckeln; Schreibschutz (`guard`); Ereigniserkennung aus Schnappschüssen (Fang, Tod, verpasste Begegnung, Geschenk, Ei); Spiel-Leser aus Profil-Adressen; Emulator-Adapter | `tests/mem` (synthetische Datensätze, alle 24 Blockreihenfolgen) |
| `lua/app` + `main.lua` | Ablauf im Script: Prüfzyklus, Ereignisse senden, tote Monster auf 0 KP (nur über Schreibschutz), Eingabesperre mit Begründung, Overlay (Status, Aufhol-Modus, Partner, Gruppen, Todeszähler, Friedhof, Gebiete), Tasten, Run-Start/Abstimmung per Taste, automatische Sicherungen (vor erstem Schreiben, Orden, 15 min, letzte 20) | `tests/app` inkl. `main.lua`/`check.lua` gegen nachgebaute DeSmuME-API |
| `lua/profiles` | Laden nach Game-Code, Prüfung der `tested`-Markierungen, Vorlage, Liste der deutschen Editionen; **Platin (CPUD)**: Kandidaten aus Ironmon-Tracker und yPokeStats (US/PAL), Werte relativ zum Team, Arena-Level – alles ungetestet | `tests/mem/reader_test.lua` |
| Adress-Suche | Team per Signatur im ganzen Speicher finden (unabhängig von Sprachversion/Zeigern), Zeigerketten, Suche nach Zeigern auf die Team-Basis, Live-Anzeige und Bericht in `check.lua` | `tests/mem/finder_test.lua` |
| `web/` | Run-Übersicht: Spieler, Online-Status, Orden, Gruppen, Gebiete, Friedhof/Todesprotokoll, Regeln, Verlauf, frühere Versuche, Rangliste; live; nur Text; im Browser geprüft (Desktop/Mobil) | Server-Test für Auslieferung |
| Spieldaten | aus der eigenen ROM: NDS-Dateisystem, NARC, Gen-4-Texte (Entschlüsselung, Zeichensatz), Personal-Daten (Typen, Wachstum), Entwicklungsreihen; Erfahrungskurven | `tests/mem/gamedata_test.lua` mit synthetischer ROM |
| Zusatzregeln | Level-Cap durchsetzen, Sonderbonbons, Folgemodus, Items im Kampf, Todesprotokoll-Export, Bilanz | `tests/core`, `tests/mem`, `tests/app`, Server-Test |
| Doku | README (alle geforderten Abschnitte), DECISIONS.md, TESTEN.md | – |

Abnahmekriterien, die schon automatisch belegt sind: Tests für core und mem grün ohne Emulator (1–4 Spieler,
Aufhol-Modus), Server startet mit einem Befehl (`npm start`), Verbindung per Lobby-Code, unbekannte ROM bzw.
ungetestete Adresse führt nie zu Schreibzugriffen (`tests/mem/guard_test.lua`, `tests/app/app_test.lua`),
Todeszähler und Protokoll überstehen einen Server-Neustart (`server/test`).

## Offen (nach Phasen)

Alles Folgende braucht den Emulator, also Adressen bestätigen und Verhalten prüfen. Im Code ist es gebaut, soweit
unten nicht anders genannt.

**Phase 0 – Machbarkeit** (heute Abend, siehe oben): `check.lua` ausführen, Entscheidung E3 bestätigen.

**Phase 1 – Lesen:** Platin-Profil bestätigen (Bericht `local/adressen_CPUD.txt`). Spieldaten aus der ROM sind
gebaut (Namen, Typen, Wachstum, Entwicklungsreihen); Pfade, Textbank-Nummern und Zeichentabelle sind zu prüfen.
Spielzeit-Kandidat liefert `check.lua`. **Noch nicht gebaut:** Gebietsnamen (Zuordnung Karte → Ortsname liegt
nicht in einem einfachen Archiv), Boxen lesen (Box-Suche in `check.lua` ist gebaut; Adresse muss im Emulator ermittelt werden, bis dahin
werden Fänge bei vollem Team nicht erkannt), Kampfergebnis (Entscheidung „verpasst“ läuft über 20 s Wartezeit), „im Menü/PC“ erkennen.

**Phase 2:** fertig, Prüfung im Emulator (TESTEN.md Abschnitt 2).

**Phase 3:** Regeln 3–8 im Code fertig: KP auf 0, Sperren, Team-Gleichheit, Level-Cap (Erfahrung deckeln,
Überschreitung melden), Sonderbonbons nachfüllen. Prüfung: TESTEN.md Abschnitte 3 und 3b. Unklar bis zum
Test: Wie unterdrückt `joypad.set` in DeSmuME Tasten? Steigt ein Monster am Cap im Kampf trotzdem auf?

**Phase 4:** fertig im Code (Sicherungen, Todeszähler, Overlay, Aufhol-Kasten, Gruppen-Ansicht, Prolog
überspringen mit Aufnahme, Spitznamen ablehnen). Für Platin fehlen im Profil: Prolog-Eingabefolge (Aufnahme),
Merkmal „kann frei laufen“, Merkmal „Spitznamen-Abfrage offen“. Den Spielernamen gibt es als Kandidat.

**Solo-Modus:** fertig.

**Phase 5 – Randomizer:** Stufe A fertig. Stufen B und C: Zuordnungen fertig, Schreibzugriffe laut Vorgabe erst
nach stabil getesteter Stufe A bzw. B.

**Phase 6:** fertig im Code. Im Einzelnen:
1. Duplikat-Klausel: mit Entwicklungsreihen aus der ROM.
2. Schillernd-Klausel.
3. Schonfrist.
4. Geschenke und feste Begegnungen zählen als Gebietsfang. Das Randomisieren gehört zu Phase 5, Stufe B, und ist
   laut Vorgabe bis zum Test von Stufe A gesperrt.
5. Folgemodus: Die Optionen-Adresse fehlt noch im Profil.
6. Todesprotokoll: dauerhaft über alle Versuche (in der Bilanz, mit Versuchsnummer), Textexport für den aktuellen
   Versuch und für alle Versuche (Server und lokal), Anzeige in der Run-Übersicht; dazu der Versuchszähler.
7. Items im Kampf: erkennen und protokollieren.

Dazu der Hinweis zu Kampfbeginn, ob eine wilde Begegnung zählt. Die Bewertung steht dafür einmal in
`core.rules.encounter_status` und wird von Engine und Overlay genutzt.

**Phase 7:** fertig im Code. Im Einzelnen:
- **Vorlagen:** vollständig nach Vorgabe; ein Wechsel lässt nichts übrig. Danach einzeln anpassbar, eigene Vorlagen
  speichern und laden (Server und Solo).
- **Discord:** alle Meldungsarten, Run-Ende mit Statistik, Wiederholung bei Drosselung, jede Art abschaltbar.
- **Run-Übersicht:** aktuelle Teams pro Spieler, Orden-Fortschritt, Gruppen, Gebiete, Friedhof, beide
  Todesprotokolle, Regeln, Verlauf, frühere Versuche, Bilanz, Statistik nach Run-Ende; live, nur Text.
- **Endbildschirm im Overlay** (Regel 3.8): Statistik aus `core.export.summary`, dieselbe wie bei Discord und
  in der Übersicht.

**Phase 8:** fertig im Code. Im Einzelnen:
- **Teams:** aus `config.lua`, im Wettkampf 1 oder 2 Spieler je Team; Hinweis bei ungleicher Größe (Lobby,
  Overlay, Discord).
- **Wertung:** Rennen (Reihenfolge des Ziel-Erreichens) und Überleben (Fortschritt, dann weniger Tode); Gewinner je
  Wertung.
- **Spielablauf:** Ausscheiden ohne Run-Ende, Aufhol-Modus nur im Team.
- **Live-Rangliste:** im Overlay und in der Übersicht, mit Orden, lebenden Monstern und Toden.
- **Discord:** Run-Start mit Teams, Wertung und Ziel.
- **Bilanz:** dauerhaft pro Spieler und Konstellation.

Offen: Profil-Merkmal `game_completed` für das Ziel „Spielende“.

**Ideen für später:** auf Wunsch alle gebaut, im Code fertig und getestet:
- **Erfolge:** 17 Stück, in `core/achievements.lua`.
- **Kampfstatistik pro Monster:** braucht die Profil-Adressen für aktives Monster und Gegner-Team.
- **Tipprunde vor Arenen.**
- **Handicap-Ereignisse im Wettkampf:** abschaltbar, Standard aus.
- **Zeitleiste des Runs als SVG.**
- **Protokoll von Regelverstößen:** dauerhaft, mit Export.

Test im Emulator: TESTEN.md Abschnitt „Extras“.

## Verlauf

- 05.10.2026 (11): Ideen für später gebaut: Regelverstöße-Protokoll, Erfolge, Tipprunden, Handicaps,
  Kampfstatistik, Zeitleiste (SVG). Fix im JSON-Modul (Schlüssel in aus [] gelesenen Tabellen gingen verloren).
- 05.10.2026 (10): Boxen mit Zwischenspeicher (Leistung in DeSmuME), `npm run tunnel` (Server + Tunnel in einem
  Befehl, Adresse für config.lua), `npm run restore` (Sicherung zurückspielen), Windows-Startdateien,
  Lua-5.1-Verträglichkeit geprüft.
- 05.10.2026 (9): Phase 8 abgeschlossen: Wertung Überleben, Teamgrößen im Wettkampf, Live-Rangliste im
  Overlay (lebende Monster), Run-Start nennt Teams, Lobby-Hinweis, Spielende-Merkmal im Leser.
- 05.10.2026 (8): Phase 7 abgeschlossen: vollständige Vorlagen, Run-Statistik (Endbildschirm, Discord,
  Übersicht), Discord-Wiederholung bei 429, Übersicht mit aktuellen Teams und Orden-Fortschritt.
- 05.10.2026 (7): Phase 6 abgeschlossen: dauerhaftes Todesprotokoll über alle Versuche (+ Export, Übersicht),
  Datum im Export, Begegnungs-Bewertung als Regel-Abfrage mit Hinweis zu Kampfbeginn.
- 05.10.2026 (6): Box-Suche, tote Monster in der Kampfkopie auf 0 KP (battle_safe), Vorschläge per Taste V,
  native Bit-Bibliothek nutzen, wenn vorhanden.
- 05.10.2026 (5): Todesprotokoll-Export, Bilanz (Siege, Platzierungen, Konstellationen), Vorlagen/Teams aus
  config.lua, Items im Kampf, Spieldaten aus der ROM, Level-Cap durchsetzen, Sonderbonbons, Folgemodus,
  Gen-4-Zeichensatz, Spielername-Kandidat, Spielzeit-Suche.
- 05.10.2026 (4): Phase 5 Randomizer Stufe A, Zuordnungen für B/C, ROM-Leser, Fingerabdruck-Abgleich.
- 05.10.2026 (3): Aufhol-Modus-Overlay (Kasten mit Grenze, Fang hier, freie Gebiete, „offline seit“),
  Phase 4 (Gruppen-Ansicht, Automatiken Prolog/Spitzname, Eingabe-Aufnahme, lokale Todeszähler),
  Solo-Modus ohne Server.
- 05.10.2026 (2): Platin-Profil CPUD (ungetestet, mit Quellen), Adress-Suche per Signatur, Zeigerketten,
  Header-Adresse korrigiert (0x023FFE0C statt Spiegeladresse 0x027FFE0C), `check.lua` mit Live-Anzeige und Bericht.
- 05.10.2026: Gerüst, Lua-Grundlagen, Regel-Engine, Server, Netz und Brücke, Speicherschicht,
  Emulator-Script-Gerüst, Run-Übersicht, Doku. Alles committet und gepusht auf
  `claude/soul-link-enforcer-desmumeee-oa1faz`.
