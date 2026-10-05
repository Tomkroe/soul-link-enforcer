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

## 4. Komfort

- [ ] Sicherung bei neuem Orden (`…_orden<N>_orden.dsv`) und alle 15 Minuten; höchstens 20 Dateien.
- [ ] Sicherung zurückspielen wie im README beschrieben – Spiel lädt den alten Stand.
- [ ] Todeszähler im Overlay („Tode: …“) und in `local/todeszaehler.json`, auch nach Neustart.
- [ ] Overlay mit Taste O aus/ein, Friedhof mit F, Gebiete mit G.
- [ ] Partner-Zeile im Overlay: Gebiet, Orden, „im Kampf“, OFFLINE.
