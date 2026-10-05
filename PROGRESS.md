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
| Projektgerüst | Ordnerstruktur, `package.json`, IntelliJ-Startkonfigurationen (`.run/`), CI (GitHub Actions, Lua 5.1 + fengari), Pages-Workflow, Render-Blueprint | – |
| `lua/lib` | JSON (deterministisch), Bit-Operationen ohne native Operatoren | `tests/lib` |
| `lua/core` | Zustandsmodell, Reducer, Abfragen: Lobby (1–4 Spieler, Einstellungen, Vorlagen, Teams), Link-Gruppen, Gebietsverbrauch, gekoppelter Tod, Team-Prüfung (Regeln 4/5), Level-Cap-Abfrage, Run verloren/gewonnen, **Aufhol-Modus** komplett (Orden-Sperre, Fang-Sperre, Abwesenheitsliste), Savestate-Erkennung, Abstimmungen (Einstellungen, Zähler zurücksetzen, aufgeben), Duplikat-/Schillernd-Klausel, Schonfrist, Wettkampf-Teams mit Rangliste | `tests/core`: jede Regel für 1, 2, 3 und 4 Spieler, Aufhol-Modus mit 2/3/4 Spielern, 2v2 und 1v1 |
| `server/` | Lobby per Code, Lua-Engine über fengari, Herzschlag (offline nach 20 s), Wiedereinstieg mit Sequenznummern, Speicherung als JSON (Datei oder Upstash), Statistik dauerhaft und lobbyübergreifend, Discord-Webhook (je Art abschaltbar), Zuschauer schreibgeschützt, eigene Vorlagen speichern, liefert die Run-Übersicht aus | `server/test`: inkl. Neustart-Persistenz, Herzschlag, Abwesenheitsliste |
| `bridge/` + `lua/net` | Brücke Script ↔ Server (Dateiaustausch, startet automatisch, beendet sich ohne Lebenszeichen), Client mit Warteschlange, Bestätigungen, Ping, lokaler Kopie der Todeszähler | `tests/net`, `server/test/e2e.test.js` (**echtes Lua 5.1 → Brücke → Server**) |
| `lua/mem` | PK4/PK5: Entschlüsselung, Blockreihenfolge, Prüfsumme, Felder, KP schreiben, Erfahrung deckeln; Schreibschutz (`guard`); Ereigniserkennung aus Schnappschüssen (Fang, Tod, verpasste Begegnung, Geschenk, Ei); Spiel-Leser aus Profil-Adressen; Emulator-Adapter | `tests/mem` (synthetische Datensätze, alle 24 Blockreihenfolgen) |
| `lua/app` + `main.lua` | Ablauf im Script: Prüfzyklus, Ereignisse senden, tote Monster auf 0 KP (nur über Schreibschutz), Eingabesperre mit Begründung, Overlay (Status, Aufhol-Modus, Partner, Gruppen, Todeszähler, Friedhof, Gebiete), Tasten, Run-Start/Abstimmung per Taste, automatische Sicherungen (vor erstem Schreiben, Orden, 15 min, letzte 20) | `tests/app` inkl. `main.lua`/`check.lua` gegen nachgebaute DeSmuME-API |
| `lua/profiles` | Laden nach Game-Code, Prüfung der `tested`-Markierungen, Vorlage, Liste der deutschen Editionen; **Platin (CPUD)**: Kandidaten aus Ironmon-Tracker und yPokeStats (US/PAL), Werte relativ zum Team, Arena-Level – alles ungetestet | `tests/mem/reader_test.lua` |
| Adress-Suche | Team per Signatur im ganzen Speicher finden (unabhängig von Sprachversion/Zeigern), Zeigerketten, Suche nach Zeigern auf die Team-Basis, Live-Anzeige und Bericht in `check.lua` | `tests/mem/finder_test.lua` |
| `web/` | Run-Übersicht: Spieler, Online-Status, Orden, Gruppen, Gebiete, Friedhof/Todesprotokoll, Regeln, Verlauf, frühere Versuche, Rangliste; live; nur Text; im Browser geprüft (Desktop/Mobil) | Server-Test für Auslieferung |
| Doku | README (alle geforderten Abschnitte), DECISIONS.md, TESTEN.md | – |

Abnahmekriterien, die schon automatisch belegt sind: Tests für core und mem grün ohne Emulator (1–4 Spieler,
Aufhol-Modus), Server startet mit einem Befehl (`npm start`), Verbindung per Lobby-Code, unbekannte ROM bzw.
ungetestete Adresse führt nie zu Schreibzugriffen (`tests/mem/guard_test.lua`, `tests/app/app_test.lua`),
Todeszähler und Protokoll überstehen einen Server-Neustart (`server/test`).

## Offen (nach Phasen)

**Phase 0 – Machbarkeit** (heute Abend, siehe oben): `check.lua` ausführen, Entscheidung E3 bestätigen.

**Phase 1 – Lesen:**
- Platin-Profil im Emulator bestätigen bzw. deutsche Adressen eintragen (Bericht aus `check.lua`).
  Ohne Quelle sind bisher: Spielzeit (Savestate-Erkennung läuft bis dahin nur über die Orden), Boxen,
  Spieldaten-Tabellen.
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

**Phase 4:** fertig im Code, Test im Emulator offen. Umfang: Sicherungen, Todeszähler (Server und lokal,
auch ohne Verbindung angezeigt), Overlay mit Aufhol-Kasten, Gruppen-, Friedhof- und Gebiets-Ansicht,
Partner-Anzeige, Prolog überspringen (Abspieler mit Schnellvorlauf, Ende am Spielzustand, Name aus
config.lua, Aufnahme-Funktion für die Eingabefolge) und Spitznamen-Abfrage ablehnen.
Für Platin fehlen im Profil noch: Eingabefolge (per Aufnahme), Merkmal „kann frei laufen“, Adresse des
Spielernamens, Merkmal „Spitznamen-Abfrage offen“. Bis dahin sind die Automatiken aus und das Overlay sagt das.
Export des Todesprotokolls als Textdatei gehört zu Phase 6 und ist offen.

**Solo-Modus:** fertig. `mode = "solo"` in config.lua: lokale Regel-Engine im Script, ohne Server und Brücke,
Zustand und Zähler in `local/`, Run startet automatisch. Alternativ allein über den Server (mit Übersicht
und Discord).

**Phase 5 – Randomizer:** nicht begonnen (Platzhalter `lua/rando`).
**Phase 6:** Klauseln 1–3 und 4 (Geschenke) in der Engine fertig. Folgemodus, Items im Kampf und
Textexport offen.
**Phase 7:** Vorlagen (eingebaut + speichern), Discord und Run-Übersicht fertig. Offen: Vorlage laden aus
dem Script, Bedienung in der Lobby.
**Phase 8:** Teams, Rangliste, Ausscheiden, Platzierungen und Siege in der Statistik fertig in der Engine.
Offen: Team-Einteilung bedienen, Bilanz pro Team-Konstellation.

## Verlauf

- 05.10.2026 (3): Aufhol-Modus-Overlay (Kasten mit Grenze, Fang hier, freie Gebiete, „offline seit“),
  Phase 4 (Gruppen-Ansicht, Automatiken Prolog/Spitzname, Eingabe-Aufnahme, lokale Todeszähler),
  Solo-Modus ohne Server.
- 05.10.2026 (2): Platin-Profil CPUD (ungetestet, mit Quellen), Adress-Suche per Signatur, Zeigerketten,
  Header-Adresse korrigiert (0x023FFE0C statt Spiegeladresse 0x027FFE0C), `check.lua` mit Live-Anzeige und Bericht.
- 05.10.2026: Gerüst, Lua-Grundlagen, Regel-Engine, Server, Netz und Brücke, Speicherschicht,
  Emulator-Script-Gerüst, Run-Übersicht, Doku. Alles committet und gepusht auf
  `claude/soul-link-enforcer-desmumeee-oa1faz`.
