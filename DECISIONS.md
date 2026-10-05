# Entscheidungen

Jede Entscheidung mit Datum, Begründung und dem, was sie offen lässt.

## E1 – Regel-Engine nur einmal, in Lua; der Server führt sie über fengari aus (05.10.2026)

Arbeitsregel: „Regel-Logik nur in /lua/core und auf dem Server, nie doppelt.“ Der Server braucht die Regeln
autoritativ, weil er bei gleichzeitigen Ereignissen mehrerer Spieler die Reihenfolge festlegt.
Das Script braucht sie für Sofortprüfungen (tote Monster, Team-Gleichheit, Aufhol-Sperren).
Lösung: `lua/core` ist ein reiner Reducer `apply(state, event) -> effects` plus Abfragen. Der Node-Server
lädt genau diese Dateien mit fengari (Lua 5.3 in JavaScript) und ruft sie über eine schmale JSON-Schnittstelle
(`lua/core/api.lua`) auf. JavaScript enthält keine Regel. Die Run-Übersicht bekommt abgeleitete Werte
(Rangliste, Gebiets-Übersicht, Aufhol-Status) fertig vom Server.

## E2 – Lua-Code läuft unter 5.1 (DeSmuME) und 5.3/fengari (05.10.2026)

Gefundene Fallstricke von fengari: Ganzzahlen sind 32 Bit breit und laufen über (auch `a * b` mit zwei
Ganzzahlen), Hex-Literale ab `0x80000000` werden negativ, `tostring(3.0)` ergibt `"3.0"`, es gibt kein `io.open`.
Regeln für den Code: große Werte als Gleitkomma rechnen (`lib/bits.lua`, `mem/pkm.lua`), Zahlen über
`string.format("%.0f")` in Text wandeln, Hex-Ausgabe von Hand (`pkm.hex`). Dateizugriffe laufen über
einen austauschbaren Adapter, damit die Tests unter fengari ohne Dateisystem laufen.
Die Tests laufen automatisch unter beiden Laufzeiten (`npm run test:lua`, CI mit Lua 5.1).

## E3 – Netz: lokale Brücke mit Dateiaustausch als Standard (05.10.2026, vorläufig bis Phase 0)

Phase 0 wurde in der Cloud-Sitzung übersprungen (kein Emulator). Unabhängig vom Ergebnis gilt:
LuaSocket kann kein TLS. Kostenlose Tunnel und Cloud-Dienste bieten aber nur HTTPS/WSS.
Deshalb spricht das Script nie direkt mit dem Server, sondern mit einer lokalen Brücke
(`bridge/bridge.js`). Austausch über Dateien (je Nachricht eine Datei, atomar per Umbenennen), weil das
nur `io`/`os` braucht, die DeSmuME immer hat. Die Brücke startet automatisch mit (`start /MIN node ...`)
und beendet sich nach 90 Sekunden ohne Lebenszeichen. Ein Reset mit Nonce beim Script-Start verhindert,
dass alte Dateien gelesen werden.
Offen für heute Abend: `lua/check.lua` zeigt, ob LuaSocket vorhanden ist. Falls ja, ist ein Socket-Transport
zur Brücke (localhost) eine mögliche Verbesserung, aber nicht nötig. Trägt DeSmuME grundsätzlich nicht,
wird BizHawk vorgeschlagen und erst nach Rückfrage gewechselt.

## E4 – Zuverlässige Übertragung: Sequenznummern und Bestätigungen (05.10.2026)

Jedes Spielereignis bekommt eine fortlaufende Nummer, liegt in einer lokalen Warteschlange
(`local/warteschlange.json`) und wird bis zur Bestätigung (`ack`) nach jedem Verbinden erneut gesendet.
Der Server merkt sich pro Spieler die letzte Nummer, verwirft Doppelte und meldet sie in `welcome.last_seq`.
Der Client zählt von dort weiter. Das deckt Neustart von Script, Emulator, Brücke und PC ab.

## E5 – Speicherung: Datei oder Upstash Redis; Cloud-Empfehlung Render Free + Upstash Free (05.10.2026)

Recherche Oktober 2026: Render Free unterstützt WebSockets und bleibt wach, solange WebSocket-Nachrichten
kommen. Das Dateisystem ist aber flüchtig. Koyeb Free hat keine Volumes. Fly.io und Railway bieten für neue
Konten kein dauerhaft kostenloses Angebot. Upstash Redis Free (256 MB, 500.000 Befehle/Monat) ist dauerhaft.
Daher zwei austauschbare Speicher mit gleicher Schnittstelle: `FileStore` (eigener PC, Standard) und
`UpstashStore` (wird automatisch genutzt, wenn `UPSTASH_REDIS_REST_URL`/`_TOKEN` gesetzt sind).
Gespeichert wird gebündelt (höchstens alle 1 s) und nur bei Änderungen. FileStore schreibt atomar und behält
eine `.bak`-Kopie. Nichts Kostenpflichtiges eingerichtet.

## E6 – Teams von Anfang an im Zustandsmodell (05.10.2026)

Auch der normale Soul Link ist intern „ein Team mit allen Spielern“. Solo ist ein Team der Größe 1
(Gruppe der Größe 1, ohne Sonderfall). Damit ist der Wettkampf-Modus (Phase 8) im Modell schon angelegt
(eigene Gruppen, Friedhof, Gebiete pro Team; Rangliste; Aufhol-Modus nur innerhalb eines Teams) und
wird später nicht verbaut.

## E7 – Auslegung der Regeln (05.10.2026)

- **Zweiter Fang desselben Spielers im selben Gebiet** gilt als tot (nur der erste Fang zählt).
- **Gebietsverbrauch** tötet bereits gefangene Gruppenmitglieder. Das zählt nicht als eigener Tod und nicht
  als „mitgerissen“, steht aber im Friedhof (Ursache „Gebiet verbraucht“).
- **Begegnungen ohne Bälle** verbrauchen kein Gebiet (unabhängig von der Schonfrist). Die Schonfrist betrifft
  nur Tode.
- **Gesperrter Fang im Aufhol-Modus** (Partner hat dort nicht gefangen) gilt als tot (Ursache „gesperrt“) und
  verbraucht die Gebietschance nicht. Verpasste Begegnungen dort werden ignoriert, damit kein Gebiet einseitig
  verbraucht wird.
- **Team-Gleichheit** vergleicht nur komplette, lebende Gruppen und nur mit Mitspielern, die online sind und
  schon ein Team gemeldet haben. Monster offener Gruppen (Partner hat noch nicht gefangen) sind erlaubt und
  werden als „wartet“ geführt. Sonst wäre z. B. der Starter vor dem Partnerfang nicht nutzbar.
- **Schillernde Monster** (Klausel an) sind „frei“: kein Gebietsfang, keine Gruppe, im Team erlaubt.
- **Unbekannte Monster** (vor Script-Start erhalten, ohne Fang-Ereignis) gelten im Team als „nicht verknüpft“.
  Fällt eines, zählt es als eigener Tod ohne Mitreißen.
- **Ein Fang in einer Gruppe, die schon tot ist**, ist sofort tot („gesperrt“).
- **Alle Gruppen tot** (mindestens eine Gruppe vorhanden) = Team verloren. Der Run endet, wenn kein Team mehr aktiv ist.
- **Ziel erreicht** heißt: alle Mitglieder eines Teams haben die Ordenzahl bzw. das Spielende erreicht.
  Rennen: Platz nach Reihenfolge. Überleben: Fortschritt, dann weniger Tode.
- **Abstimmungen** brauchen alle Spieler des Runs, auch abwesende. Eine Ablehnung verwirft den Vorschlag.
- **Savestate-Erkennung:** Spielzeit (Toleranz 5 s) oder gemeldeter Ordenstand sinkt. Meldung an alle, einmal
  pro Rücksprung. Der erreichte Ordenstand auf dem Server sinkt nicht.

## E8 – Eingabesperre (05.10.2026, im Emulator zu prüfen)

Bei der 4./5. Generation kommt man nur am PC an die Boxen, also muss man dorthin laufen können. Sperre
„Menü“: nur Start/X (Menü öffnen); im Menü auch Steuerkreuz und A/B, sofern das Profil „im Menü“ erkennen kann.
Für den Weg zum PC gibt es eine sichtbare 30-Sekunden-Freigabe (Taste P). Die Abwesenheitsliste sperrt
vollständig, bis sie bestätigt ist. Wie `joypad.set` in DeSmuME Tasten unterdrückt, ist noch zu prüfen (TESTEN.md).

## E9 – Schreibschutz in einer einzigen Schicht (05.10.2026)

Jeder Schreibzugriff läuft über `mem/guard.lua`. Bedingungen: Profil vorhanden, Adresse mit `tested = true`,
`write_enabled = true` in `config.lua`, Selbsttest der Schreibfunktionen bestanden, im Kampf nur bei
`battle_safe = true`. Unbekannte ROM bedeutet Lesemodus. Vor dem ersten Schreiben jeder Sitzung wird die
Speicherdatei gesichert.

## E10 – Statistik pro Spieler-ID, lobbyübergreifend (05.10.2026)

Spieler-ID = Name aus `config.lua` in Kleinbuchstaben. Todeszähler, mitgerissen, Versuche und Siege liegen
in `stats` auf dem Server (unabhängig von Lobby und Run) und als Kopie lokal. Zurücksetzen nur per Abstimmung aller.

## E11 – Ereigniserkennung aus Schnappschüssen (05.10.2026)

Das Script meldet keine Rohdaten, sondern Ereignisse (`catch`, `faint`, `encounter_failed`, `status`,
`party`), erkannt durch Vergleich aufeinanderfolgender Schnappschüsse (`mem/detect.lua`, rein und getestet).
Kennung eines Monsters: PID + Trainer-ID + geheime ID (über Sitzungen stabil). Wilder Kampf ohne Fang: Liefert
das Profil ein Kampfergebnis, wird sofort entschieden. Sonst wartet die Erkennung 20 s auf einen Fang
(Spitznamen-Abfrage). Eier zählen beim Schlüpfen als Geschenk im aktuellen Gebiet.

## E12 – Keine Subagents angelegt (05.10.2026)

Die Aufgaben dieser Sitzung waren eng verzahnt (Zustandsmodell, Engine, Server und Tests hängen direkt
voneinander ab). Eigene Agents unter `.claude/agents/` hätten keinen Nutzen gebracht.

## E13 – Platin: Kandidaten aus US-Quellen plus Signatursuche (05.10.2026)

Für die deutsche Platin-Version (CPUD) gibt es keine öffentlichen Adresslisten. Die Werkzeuge
NDS-Ironmon-Tracker und yPokeStats unterstützen nur US/PAL bzw. Englisch und sagen ausdrücklich, dass andere
Sprachversionen abweichen können. Deshalb:
- Das Profil nennt deren Zeigerketten als **Kandidaten** (mit Quelle). Alle Einträge stehen auf `tested = false`.
- Das Team wird über seine Struktur gefunden (u32 Kapazität 6, u32 Anzahl 1–6, erster Datensatz mit gültiger
  Prüfsumme und plausiblen Werten). Das funktioniert unabhängig von Zeigern und Sprache und läuft schrittweise
  über mehrere Frames.
- Werte im Spielstand (Orden, Beutel) stehen relativ zum Team (`rel = "party"`). Der Spielstand-Aufbau ist
  zwischen Sprachversionen vermutlich gleich; geprüft wird das in TESTEN.md Abschnitt 0b.
- Werte außerhalb des Spielstands (Karte, Kampf) bleiben Zeigerketten bzw. feste Adressen. Liefern sie nichts
  Plausibles, erscheinen sie als fehlend (nil) statt mit falschen Werten.
- Header-Adresse: `0x023FFE0C` (so in beiden Quellen) statt der Spiegeladresse `0x027FFE0C`.
- Arena-Level für das Level-Cap stammen aus allgemeinem Spielwissen und sind als ungeprüft markiert. Das
  Overlay zeigt „(ungeprüft)“ hinter dem Cap.

## E14 – Solo-Modus: lokaler Vermittler im Script statt eigener Regeln (05.10.2026)

Solo nutzt dieselbe Regel-Engine und dasselbe Protokoll wie der Mehrspielerbetrieb. `net/local_hub.lua`
verhält sich für den Client wie ein Transport, führt `core.engine` direkt in DeSmuME (Lua 5.1) aus und speichert
den Zustand in `local/solo_<name>.json`. Dadurch gibt es keinen Sonderfall in den Regeln (Gruppen der Größe 1),
keinen zweiten Code-Pfad im Script und keinen Server-Zwang beim Alleinspielen. Was ohne Server fehlt
(Run-Übersicht, Discord), bekommt man, indem man allein über den Server spielt.

## E15 – Aufhol-Kasten: Inhalte aus core, nur Darstellung im Script (05.10.2026)

`core.rules.catchup_info` liefert Orden-Grenze, Fang-Erlaubnis im aktuellen Gebiet, freie Fanggebiete und
Abwesende. `app/overlay.lua` stellt nur dar (gelber Hintergrund, Umbruch auf 42 Zeichen für die DS-Breite).
„Offline seit“ rechnet mit der Serverzeit (Versatz aus der letzten Zustandsnachricht), damit unterschiedliche
Uhren der PCs nicht stören.

## E16 – Automatiken über Eingabefolgen, Ende am Spielzustand (05.10.2026)

Prolog und Spitznamen-Abfrage werden über Tasteneingaben gesteuert, nicht über Speicher-Hacks. Die Eingabefolge
entsteht per Aufnahme (Taste K) beim ersten Durchspielen und steht danach im Profil. Beendet wird über ein
Merkmal im Spielzustand (`prologue.done`); läuft die Folge vorher aus, schaltet das Script zurück auf normale
Geschwindigkeit und meldet es. Automatik-Eingaben haben Vorrang vor der Eingabesperre. Den Namen aus
`config.lua` schreibt das Script nach dem Prolog in den Spielstand, weil die Bildschirmtastatur je Sprache
anders aufgebaut ist; das geschieht nur über den Schreibschutz und mit getesteter Adresse.

## E17 – Randomizer: Zuordnung pro Gebiet über Originalart, Daten aus der eigenen ROM (05.10.2026)

- **Zuordnung:** Pro Gebiet wird die Artenliste mit einem aus „Seed|A|Gebiet“ abgeleiteten Zufall gemischt.
  Die sortierten Originalarten des Gebiets bekommen der Reihe nach die gemischten Arten. Gleiche Originalart heißt
  damit gleiche neue Art, und verschiedene Originalarten werden verschiedene Arten, sodass die Seltenheitsstufen
  erhalten bleiben. Die Zuordnung hängt nicht von der Reihenfolge der Besuche ab.
- **Determinismus:** FNV-1a + 32-Bit-LCG nur über `lib/bits.lua`. Ein Test mit Referenzwerten läuft unter Lua 5.1
  und fengari. Er hat beim Bau einen Ganzzahlüberlauf unter fengari aufgedeckt, der sonst zu unterschiedlichen
  Begegnungen geführt hätte.
- **Gleichheit zwischen Spielern:** Fingerabdruck aus Seed, Modus und Artenliste im Status; die Engine warnt bei
  Abweichung. Im Modus `edition` müssen alle dieselbe Edition spielen.
- **Seed:** leer = beim Run-Start vom Zustand vergeben (Lobby-Code, Versuch, Zeit). Er steht im Run-Zustand und
  gilt damit für alle.
- **Spieldaten zur Laufzeit:** Die Artenliste für `edition` und die Begegnungsdateien kommen aus der ROM des
  Spielers (`rom_path`, nur lesen). Kein Datensatz liegt im Projekt.
- **Tabelle im Speicher:** Es gibt keine Quelle für die Adresse. Das Script sucht einen Block, der exakt einer
  ROM-Begegnungsdatei entspricht. Bereits geänderte Tabellen werden nicht noch einmal geändert: Die
  geschriebenen Arten pro Gebiet werden gemerkt, auch über Neustarts (`local/rando_<CODE>.json`).
- **Stufen-Reihenfolge:** B und C haben nur Zuordnungen und Sperren. Speicherzugriffe dafür werden laut Vorgabe
  erst gebaut, wenn die vorige Stufe stabil getestet ist.
- **Item-Ausschlüsse (C):** „VMs und Basis-Items“ als ganze Taschen ausgeschlossen (VM/TM-Tasche, Basis-Items-Tasche).
  Die Tasche allein trennt TM und VM nicht sicher, deshalb bleiben auch TMs unverändert. Das lässt sich lockern,
  sobald die Item-Daten aus der ROM gelesen werden.
