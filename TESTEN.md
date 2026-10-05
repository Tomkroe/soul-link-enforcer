# Prüfschritte im Emulator

Alles, was nur im Emulator geprüft werden kann. Bitte abhaken und Auffälligkeiten mit Datum notieren.
Automatische Tests (`npm test`) decken Regeln, Server, Netz, Ver-/Entschlüsselung und Ablauf schon ab.
Hier geht es um das Zusammenspiel mit DeSmuME und dem echten Spiel.

Legende: [ ] offen · [x] bestanden · [!] Problem (Notiz dahinter)

## 0. Machbarkeit (zuerst)

- [ ] `npm install` im Projektordner, dann `npm test`: alles grün.
- [ ] DeSmuME: *Tools > Lua Scripting > New Lua Script Window*, `lua/check.lua` ausführen. Notieren:
  - [ ] Lua-Version: ______ (erwartet „Lua 5.1“)
  - [ ] io.open / os.rename / os.execute: OK
  - [ ] LuaSocket vorhanden? ja / nein (beides in Ordnung)
  - [ ] „Datei schreiben/umbenennen“: OK
  - [ ] Game-Code: ______ (erwartet CPUD). Falls leer: Adresse 0x023FFE0C stimmt nicht,
        im Memory Viewer nach den 4 Buchstaben suchen und in `lua/mem/emu.lua` eintragen.
  - [ ] Selbsttest PK4/PK5: OK
  - [ ] Overlay-Text sichtbar und „Frames“ zählt hoch.
- [ ] `npm start`, dann `lua/main.lua` laden. Ein Fenster „Soul-Link-Brücke“ öffnet sich minimiert.
      Overlay: „Soul Link – Verbunden“, Zeile „LESEMODUS …“ mit Spielname.
- [ ] Browser <http://localhost:8080/>, Server `ws://localhost:8080/ws`, Lobby `SOUL01`: Spieler erscheint online.
- [ ] Script stoppen. Nach etwa 20 s steht der Spieler in der Übersicht auf „offline“.
- [ ] Emulator schließen. Die Brücke beendet sich nach etwa 90 s von selbst.

## 0b. Platin (CPUD): Adress-Suche mit `check.lua`

Das Profil `lua/profiles/CPUD.lua` enthält Kandidaten aus Werkzeugen für die US-Version. Alles ist ungetestet.

- [ ] Spielstand laden, **mindestens ein Monster im Team**, `lua/check.lua` ausführen.
- [ ] Zeile „Team: 0x…“ erscheint. Notieren, ob „Kandidat 1 (Ironmon US)“, „Kandidat 2 (yPokeStats …)“
      oder „Suche“ (Zeiger der deutschen Version weichen ab). Während der Suche kann das Bild kurz ruckeln.
- [ ] Art-Nummern und Level stimmen mit dem Team im Spiel überein (z. B. Chelast = Art 387, Panflam = 390,
      Plinfa = 393).
- [ ] Nach kurzer Zeit „Bericht: local/adressen_CPUD.txt“ – **diese Datei bitte mitschicken**, darin stehen auch
      gefundene Zeiger auf die Team-Basis.
- [ ] „Orden-Byte“: 0 vor dem ersten Orden, nach Orden 1 → 1, nach Orden 2 → 3 (Bitfeld).
      Stimmt es nicht, ist der Abstand Team → Orden (−0x1E) in der deutschen Version anders.
- [ ] „Karte“: ändert sich beim Wechsel von Route/Stadt/Gebäude (gleiche Zahl beim selben Ort).
- [ ] „Bälle“: 0 ohne Bälle, ungleich 0, sobald ein Ball im Beutel ist.
- [ ] „Kampf“: erster Wert 8448 (0x2100) oder 8449 im Kampf, sonst anders. Zweiter Wert 0 bei wildem Kampf,
      ungleich 0 bei Trainerkampf. Steht dort „nil“ oder ändert sich nichts → Adresse der deutschen Version fehlt.
- [ ] Werte, die stimmen, in `CPUD.lua` auf `tested = true` setzen (nur Lese-Einträge; `party` erst nach Abschnitt 3).

## 1. Lesen (Profil anlegen, siehe README „Neues Profil anlegen“)

Für jede Adresse im Profil. Erst danach `tested = true` setzen, Schreib-Adressen erst nach Abschnitt 3.

- [ ] `party_count`: Anzahl im Team stimmt (1 → 2 nach Fang).
- [ ] `party`: Overlay/Übersicht zeigt richtige Art und richtiges Level für jedes Team-Monster;
      Datensatz gilt als gültig (Prüfsumme). Kennung bleibt nach Neustart gleich.
- [ ] Spitzname wird korrekt angezeigt (Gen 4: zunächst nur Buchstaben/Ziffern).
- [ ] `boxes`: Monster in Box 1 werden erkannt (Fang mit vollem Team landet in der Box → `catch`).
- [ ] `area_id`: Gebietswechsel erzeugt Meldung „Fang offen in …“, Gebiets-Übersicht (Taste G) füllt sich.
- [ ] Gebietsnamen aus den Spieldaten (statt „Gebiet 123“) – Lesefunktion noch zu bauen.
- [ ] `badges`: Ordenzahl stimmt (Übersicht).
- [ ] `play_time`: läuft mit (Übersicht/Log); Savestate laden → Meldung „Alter Spielstand“.
- [ ] `bag_balls`: vor den ersten Bällen „noch keine Bälle“, danach Hinweis „Schonfrist vorbei“.
- [ ] `battle_flag` / `battle_type`: „im Kampf“ in der Übersicht, wild vs. Trainer korrekt.
- [ ] `battle_enemy`: Gegnername erscheint im Todesprotokoll.
- [ ] Fang im wilden Kampf → Ereignis `catch` (Log: „… hat … gefangen“).
- [ ] Wilder Kampf ohne Fang (besiegt/geflohen) → nach ≤ 20 s „Gebiet verbraucht“.
- [ ] Trainerkampf → kein Gebietsverbrauch.
- [ ] Geschenk (Starter, Ei) → `catch` mit Gebiet, in dem man es erhält.
- [ ] Monster fällt auf 0 KP → `faint` mit Level, Gebiet, Gegner.

## 2. Verbindung und Zustand (zwei Instanzen oder zwei PCs)

- [ ] Zwei Spieler, gleicher Lobby-Code: beide in der Übersicht. Taste N startet den Run für beide.
- [ ] Run läuft, ein dritter Spieler versucht beizutreten: Meldung „Run läuft bereits“.
- [ ] Script neu starten während des Runs: Wiedereinstieg ohne Datenverlust (Gruppen/Tote unverändert).
- [ ] PC/Emulator hart beenden, neu starten: Ereignisse aus der Warteschlange kommen nach (Log).
- [ ] Server neu starten (`Strg+C`, `npm start`): Zustand und Todeszähler unverändert.
- [ ] Spieler B offline: Overlay bei A zeigt „AUFHOL-MODUS (offline: B)“.
- [ ] Aufhol-Modus: A hat gleich viele Orden wie B → Overlay „Nächste Arena gesperrt“.
- [ ] Aufhol-Modus: Fang in einem Gebiet, in dem B schon gefangen hat → Gruppe sofort komplett.
- [ ] Aufhol-Modus: Fang in einem Gebiet ohne B-Fang → Monster gilt als gesperrt/tot, Gebiet bleibt offen.
- [ ] Aufhol-Modus: Tod bei A, B verbindet sich → B sieht Liste, Eingaben gesperrt bis Taste J.
- [ ] Alten Savestate laden → Meldung an alle, tote Monster werden sofort wieder auf 0 KP gesetzt.
- [ ] Abstimmung: Einstellung ändern/Todeszähler zurücksetzen nur, wenn alle mit Y zustimmen; U verwirft.

## 3. Regeln erzwingen (Schreibzugriff) – erst nach 1 und 2

Vorbereitung: `backups.save_path` setzen, `write_enabled = true`, nur `party` auf `tested = true`.

- [ ] Vor dem ersten Schreiben entsteht eine Sicherung in `backups/` (`…_vor-schreiben.dsv`).
- [ ] **Regel 3 – gekoppelter Tod:** A verliert ein Monster → B's Gruppenmitglied hat sofort 0 KP
      (außerhalb des Kampfes; im Kampf erst nach Kampfende, solange `battle_safe = false`).
- [ ] **Regel 4 – auf 0 KP halten:** Totes Monster mit Trank, Beleber, Pokécenter heilen → sofort wieder 0 KP.
- [ ] Regel 4: Totes Monster per Tausch/Box zurück ins Team → Sperre sofort, Overlay „Tot, muss in die Box“.
- [ ] Regel 4: Totes Monster im Team nach Kampfende → Eingaben gesperrt außer Start/X. Taste P gibt 30 s frei,
      um zum PC zu laufen. In die Box legen → Sperre weg.
- [ ] Regel 4: Lässt sich ein totes Monster auf irgendeinem Weg im Kampf einsetzen? (Beleber im Kampf,
      Tausch im Kampf, Doppelkampf) → Es darf nicht kämpfen können. Notieren, was passiert.
- [ ] **Regel 5 – Team-Gleichheit:** A nimmt Gruppe 2 aus dem Team, B nicht → bei beiden Sperre mit
      „Fehlt im Team“ bzw. „Zu viel im Team“; korrigieren → Sperre weg.
- [ ] `joypad.set`: Werden gesperrte Tasten wirklich unterdrückt? (Tastennamen, Wirkung von `false`)
- [ ] Unbekannte ROM (anderes Spiel laden): kein einziger Schreibzugriff, Overlay „LESEMODUS“.
- [ ] Adresse auf `tested = false` zurücksetzen → Schreiben wird abgelehnt (Overlay-Meldung).

## Solo-Modus

- [ ] `config.lua`: `mode = "solo"`. Nur `lua/main.lua` starten, kein Server, kein Brückenfenster.
      Overlay: „Soul Link – Solo (ohne Server)“, Run läuft automatisch mit der Vorlage aus `lobby_settings`.
- [ ] Fang → Gruppe sofort komplett (Taste H). Tod → Friedhof (F), „Tode: Tom 1“.
- [ ] Emulator neu starten → derselbe Zustand (Tote bleiben tot), `local/solo_<name>.json` vorhanden.
- [ ] Nach verlorenem Run: Taste N → neuer Versuch, Versuchszähler +1.

## Spieldaten aus der ROM (mit `rom_path`)

- [ ] `check.lua`: Zeile „Spieldaten“ zeigt für 1, 4, 7, 25, 387, 390, 393 die deutschen Namen mit Typen
      (z. B. 25 = Pikachu/Elektro, 387 = Chelast/Pflanze). Falsche Namen → Textbank-Nummer `texts.species` im
      Profil anpassen. Falsche Typnamen → `texts.types`.
- [ ] „Entwicklungsreihe“: Art 3 gehört zu Reihe 1.
- [ ] Umlaute in Namen korrekt (z. B. Art 116 Seemops, Art 44 Duflor – je nach Bank), sonst Zeichentabelle prüfen.
- [ ] Spitzname eines Monsters mit Umlaut wird im Overlay richtig angezeigt.

## Weitere Adressen mit `check.lua`

- [ ] „Spielzeit-Kandidat: Team -0x… = h:mm:ss“ erscheint nach einigen Sekunden und stimmt mit der Spielzeit im
      Trainerpass überein → als `play_time = { rel = "party", offset = -0x…, tested = false }` ins Profil.
- [ ] Spielername: Im Memory Viewer bei Team −0x38 steht der Name (Gen-4-Zeichen). Stimmt das, `trainer_name` testen.

## 3b. Level-Cap, Sonderbonbons, Folgemodus, Items im Kampf (nach Abschnitt 3)

- [ ] Level-Cap (`level_cap = true`, Spieldaten geladen): Monster am Cap-Level sammelt keine Erfahrung mehr über das
      Level hinaus (Erfahrung wird nach dem Kampf gedeckelt). Overlay „über dem Level-Cap“, wenn eines darüber ist.
      Notieren, ob ein Monster am Cap im Kampf trotzdem aufsteigt (dann Schreiben im Kampf nötig).
- [ ] Sonderbonbons (`rare_candies = true`, `bag_items` getestet): 999 Sonderbonbons in der Item-Tasche,
      nach Benutzung wieder 999.
- [ ] Folgemodus: Adresse der Optionen und Bit für den Kampfstil finden (Optionen umstellen, Memory Viewer),
      als `options = { ..., battle_style_bit = n, follow_value = 0|1 }` eintragen. Danach bleibt „Folgen“ eingestellt.
- [ ] Items im Kampf (`battle_items = { mode = "verboten" }`): Trank im Kampf benutzen → nach dem Kampf
      Meldung „Regelverstoß … Item(s) benutzt“ und Eintrag im Verlauf. Außerhalb des Kampfes: keine Meldung.
- [ ] Todesprotokoll: `local/todesprotokoll.txt` und `http://localhost:8080/api/SOUL01/todesprotokoll.txt`
      zeigen jeden Tod mit Gebiet, Level, Gegner.

## 5. Randomizer (erst nach Abschnitt 3)

- [ ] `config.lua`: `rom_path` auf die eigene Platin-ROM setzen. `check.lua`: „ROM gelesen“ mit Game-Code CPUD
      und Zahl der Begegnungstabellen. Fehlt die Datei, stimmt der Pfad `randomizer.encounter_narc` nicht.
- [ ] `check.lua` auf einer Route mit Gras: „Begegnungstabelle: 0x…“ gefunden. Notieren, ob die Adresse nach
      einem Kartenwechsel gleich bleibt (dann als feste Adresse ins Profil).
- [ ] Format prüfen: Die angezeigten Arten der Tabelle passen zu den Begegnungen der Route (Gras, Surfen, Angeln).
      Sonst stimmt `randomizer.encounter_layout` nicht.
- [ ] `encounter_table.tested = true`, `write_enabled = true`, in der Lobby `randomizer = { mode = "alle", seed = "test" }`.
      Overlay: „Randomizer aktiv (alle, <Fingerabdruck>)“.
- [ ] Wilde Begegnungen auf der Route sind andere Arten als normal. Gebiet verlassen und wieder betreten → wieder
      dieselben neuen Arten.
- [ ] Zwei Spieler, gleicher Seed: auf derselben Route dieselben Arten; gleicher Fingerabdruck im Overlay.
- [ ] Ein Spieler mit anderem Seed oder anderer Edition → Warnung „Zuordnung weicht ab“ bei allen.
- [ ] Im Kampf wird nichts geschrieben (Tabelle erst nach Kampfende).
- [ ] Modus `edition`: nur Arten, die es in Platin wild gibt.
- [ ] Erst wenn alles stabil ist: `randomizer.stage_a_stable = true` (Voraussetzung für Stufe B).

## 4. Komfort

- [ ] Sicherung bei neuem Orden (`…_orden<N>_orden.dsv`) und alle 15 Minuten; höchstens 20 Dateien.
- [ ] Sicherung zurückspielen wie im README beschrieben – Spiel lädt den alten Stand.
- [ ] Todeszähler im Overlay („Tode: …“) und in `local/todeszaehler.json`, auch nach Neustart.
- [ ] Overlay mit Taste O aus/ein, Friedhof mit F, Gebiete mit G.
- [ ] Partner-Zeile im Overlay: Gebiet, Orden, „im Kampf“, OFFLINE.
- [ ] Aufhol-Kasten (gelb hinterlegt) bei offline-Partner: „offline seit“, Orden-Grenze, Fang hier erlaubt/gesperrt,
      Liste freier Fanggebiete. Text passt in die Bildschirmbreite.
- [ ] Gruppen-Ansicht mit H, eigene Team-Monster mit *.
- [ ] Eingabe-Aufnahme: neues Spiel, K, Prolog bis zum ersten freien Schritt, K →
      `local/prolog_aufnahme_CPUD.lua` entsteht. Inhalt als `prologue.inputs` ins Profil.
- [ ] Merkmal „kann frei laufen“ finden (z. B. Bewegungs-/Menü-Sperre im RAM) und als `prologue.done` eintragen.
- [ ] Prolog überspringen (`skip_prologue = true`): neues Spiel, Schnellvorlauf startet, endet im Zimmer,
      Overlay „Prolog übersprungen“. Läuft der Schnellvorlauf (`emu.speedmode`) in dieser DeSmuME-Version?
- [ ] Name aus `config.lua` erscheint im Trainerpass (braucht `trainer_name`-Adresse, getestet).
- [ ] Spitznamen-Abfrage: Merkmal `nickname.prompt` finden; mit `skip_nickname = true` wird nach dem Fang
      automatisch „Nein“ gewählt.
