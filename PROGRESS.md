# Fortschritt

Stand: 05.10.2026, Cloud-Sitzung ohne Emulator. Gebaut wurde alles, was sich ohne DeSmuME bauen und testen
lässt. Phase 0 und alles mit Speicheradressen ist übersprungen, die Schnittstellen dafür stehen.

## Heute Abend am PC zuerst (in dieser Reihenfolge)

1. **Repo holen und testen:** `git pull`, `npm install`, `npm test`. Erwartet: alles grün
   (148 Lua-Tests unter Lua 5.1 bzw. 145 + 3 übersprungene unter fengari, 17 Server-Tests).
2. **Machbarkeit (Phase 0):** In DeSmuME das Spiel laden, `lua/check.lua` ausführen und die Ergebnisse in
   TESTEN.md Abschnitt 0 eintragen. Wichtig: **Game-Code** (welche ROM?) und ob „Datei schreiben/umbenennen“ OK ist.
   Ist der Game-Code leer, stimmt die Header-Adresse `0x027FFE0C` nicht. Dann im Memory Viewer suchen.
3. **Verbindung im Lesemodus:** `npm start`, dann `lua/main.lua`. Das Overlay sollte „Verbunden“ und
   „LESEMODUS: Für <Spiel> gibt es noch kein Profil“ zeigen, die Übersicht unter <http://localhost:8080/> den Spieler.
4. **Profil für die heutige ROM anlegen** (`lua/profiles/_vorlage.lua` → `lua/profiles/<CODE>.lua`), erst die
   Lese-Adressen: `party_count`, `party`, `area_id`, `badges`, `play_time`, `bag_balls`, `battle_flag`.
   Jede bleibt `tested = false`, bis ihr Schritt in TESTEN.md Abschnitt 1 bestanden ist.
5. Danach Abschnitt 2 (zweite Instanz/zweiter PC) und erst dann Abschnitt 3 mit `write_enabled = true`.

## Fertig (automatisch getestet)

| Bereich | Inhalt | Tests |
|---|---|---|
| Projektgerüst | Ordnerstruktur, `package.json`, IntelliJ-Startkonfigurationen (`.run/`), CI (GitHub Actions, Lua 5.1 + fengari), Pages-Workflow, Render-Blueprint | – |
| `lua/lib` | JSON (deterministisch), Bit-Operationen ohne native Operatoren | `tests/lib` |
| `lua/core` | Zustandsmodell, Reducer, Abfragen: Lobby (1–4 Spieler, Einstellungen, Vorlagen, Teams), Link-Gruppen, Gebietsverbrauch, gekoppelter Tod, Team-Prüfung (Regeln 4/5), Level-Cap-Abfrage, Run verloren/gewonnen, **Aufhol-Modus** komplett (Orden-Sperre, Fang-Sperre, Abwesenheitsliste), Savestate-Erkennung, Abstimmungen (Einstellungen, Zähler zurücksetzen, aufgeben), Duplikat-/Schillernd-Klausel, Schonfrist, Wettkampf-Teams mit Rangliste | `tests/core`: jede Regel für 1, 2, 3 und 4 Spieler, Aufhol-Modus mit 2/3/4 Spielern, 2v2 und 1v1 |
| `server/` | Lobby per Code, Lua-Engine über fengari, Herzschlag (offline nach 20 s), Wiedereinstieg mit Sequenznummern, Speicherung als JSON (Datei oder Upstash), Statistik dauerhaft und lobbyübergreifend, Discord-Webhook (je Art abschaltbar), Zuschauer schreibgeschützt, eigene Vorlagen speichern, liefert die Run-Übersicht aus | `server/test`: inkl. Neustart-Persistenz, Herzschlag, Abwesenheitsliste |
| `bridge/` + `lua/net` | Brücke Script ↔ Server (Dateiaustausch, startet automatisch, beendet sich ohne Lebenszeichen), Client mit Warteschlange, Bestätigungen, Ping, lokaler Kopie der Todeszähler | `tests/net`, `server/test/e2e.test.js` (**echtes Lua 5.1 → Brücke → Server**) |
| `lua/mem` | PK4/PK5: Entschlüsselung, Blockreihenfolge, Prüfsumme, Felder, KP schreiben, Erfahrung deckeln; Schreibschutz (`guard`); Ereigniserkennung aus Schnappschüssen (Fang, Tod, verpasste Begegnung, Geschenk, Ei); Spiel-Leser aus Profil-Adressen; Emulator-Adapter | `tests/mem` (synthetische Datensätze, alle 24 Blockreihenfolgen) |
| `lua/app` + `main.lua` | Ablauf im Script: Prüfzyklus, Ereignisse senden, tote Monster auf 0 KP (nur über Schreibschutz), Eingabesperre mit Begründung, Overlay (Status, Aufhol-Modus, Partner, Gruppen, Todeszähler, Friedhof, Gebiete), Tasten, Run-Start/Abstimmung per Taste, automatische Sicherungen (vor erstem Schreiben, Orden, 15 min, letzte 20) | `tests/app` inkl. `main.lua`/`check.lua` gegen nachgebaute DeSmuME-API |
| `lua/profiles` | Laden nach Game-Code, Prüfung der `tested`-Markierungen, Vorlage, Liste der deutschen Editionen | über `tests/app` |
| `web/` | Run-Übersicht: Spieler, Online-Status, Orden, Gruppen, Gebiete, Friedhof/Todesprotokoll, Regeln, Verlauf, frühere Versuche, Rangliste; live; nur Text; im Browser geprüft (Desktop/Mobil) | Server-Test für Auslieferung |
| Doku | README (alle geforderten Abschnitte), DECISIONS.md, TESTEN.md | – |

Abnahmekriterien, die schon automatisch belegt sind: Tests für core und mem grün ohne Emulator (1–4 Spieler,
Aufhol-Modus), Server startet mit einem Befehl (`npm start`), Verbindung per Lobby-Code, unbekannte ROM bzw.
ungetestete Adresse führt nie zu Schreibzugriffen (`tests/mem/guard_test.lua`, `tests/app/app_test.lua`),
Todeszähler und Protokoll überstehen einen Server-Neustart (`server/test`).

## Offen (nach Phasen)

**Phase 0 – Machbarkeit** (heute Abend, siehe oben): `check.lua` ausführen, Entscheidung E3 bestätigen.

**Phase 1 – Lesen:**
- Profil für die heutige ROM (alle Adressen, `tested`-Markierungen).
- Spieldaten zur Laufzeit lesen: Artnamen, Typen, Entwicklungsreihen (für Duplikat-Klausel), Gebietsnamen,
  Item-Kategorien. Dafür fehlt noch ein Leser für die Datenarchive (NARC) im ROM-Abbild bzw. die
  Tabellen im Arbeitsspeicher. Bis dahin: Art als Nummer, Gebiet als „Gebiet <Nr>“.
- Gen-4-Zeichentabelle für Spitznamen (bisher nur Buchstaben/Ziffern).
- Kampfergebnis und Gegnerdaten aus dem Kampfspeicher (für sofortige Entscheidung „verpasst“).
- „Im Menü/PC“ erkennen (für die Menü-Sperre).

**Phase 2 – Verbindung und Zustand:** fertig bis auf die Prüfung im Emulator (TESTEN.md Abschnitt 2).
Bedienoberfläche für Teams (Wettkampf) und für Vorschläge während des Runs fehlt noch. Die Engine kann es,
im Script gibt es bisher nur Run-Start (N) und Abstimmen (Y/U).

**Phase 3 – Regeln erzwingen:** Regeln 3, 4, 5 sind in Engine und Script umgesetzt (KP auf 0, Sperren) und
warten auf Profil-Adressen und die Prüfung in TESTEN.md Abschnitt 3. Regel 6 (Level-Cap): Abfrage fertig, das
Deckeln der Erfahrung braucht die Wachstumskurven aus den Spieldaten. Regel 7 (Sonderbonbons) offen.
Unklar bis zum Test: Wie unterdrückt `joypad.set` in DeSmuME Tasten?

**Phase 4:** Sicherungen und Todeszähler fertig (Test im Emulator offen). Offen: Prolog überspringen,
Spitznamen-Abfrage überspringen, Export des Todesprotokolls als Textdatei.

**Phase 5 – Randomizer:** nicht begonnen (Platzhalter `lua/rando`).
**Phase 6:** Klauseln 1–3 und 4 (Geschenke) in der Engine fertig. Folgemodus, Items im Kampf und
Textexport offen.
**Phase 7:** Vorlagen (eingebaut + speichern), Discord und Run-Übersicht fertig. Offen: Vorlage laden aus
dem Script, Bedienung in der Lobby.
**Phase 8:** Teams, Rangliste, Ausscheiden, Platzierungen und Siege in der Statistik fertig in der Engine.
Offen: Team-Einteilung bedienen, Bilanz pro Team-Konstellation.

## Verlauf

- 05.10.2026: Gerüst, Lua-Grundlagen, Regel-Engine, Server, Netz und Brücke, Speicherschicht,
  Emulator-Script-Gerüst, Run-Übersicht, Doku. Alles committet und gepusht auf
  `claude/soul-link-enforcer-desmumeee-oa1faz`.
