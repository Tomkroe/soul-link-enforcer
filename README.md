# Soul-Link-Enforcer für DeSmuME

Ein Lua-Script für den Emulator **DeSmuME** (Windows), das Soul-Link-Regeln direkt im laufenden Spiel
durchsetzt, plus ein kleiner **Vermittlungsserver**, über den 1 bis 4 Spieler verbunden sind, und eine
**Run-Übersicht** im Browser.

Zielspiele: DS-Hauptspiele der 4. und 5. Generation, deutsche Versionen. Jeder spielt mit seiner eigenen
Spielkopie. Das Projekt enthält und lädt **keine ROMs, keine Spielgrafiken, keine Spieltexte**.

> **Stand:** Regel-Engine, Server, Netzanbindung, Run-Übersicht und Script-Gerüst sind fertig und
> automatisch getestet. Für Platin (CPUD) gibt es ein erstes, noch ungetestetes Profil mit automatischer
> Adress-Suche. Solange keine Adresse im Emulator bestätigt ist, schreibt das Script nichts. Details in [PROGRESS.md](PROGRESS.md), Begründungen
> in [DECISIONS.md](DECISIONS.md), Prüfschritte im Emulator in [TESTEN.md](TESTEN.md).

## Inhalt

1. [Aufbau](#aufbau)
2. [Installation](#installation)
3. [Server starten](#server-starten)
4. [Server erreichbar machen](#server-erreichbar-machen)
5. [Script im Emulator starten](#script-im-emulator-starten)
   · [Solo-Modus](#solo-modus-allein-spielen) · [Komfort-Automatiken](#komfort-automatiken)
6. [Run-Übersicht](#run-übersicht)
7. [Regeln](#regeln)
8. [Schalter und Vorlagen](#schalter-und-vorlagen)
9. [Discord einrichten](#discord-einrichten)
10. [Sicherungen zurückspielen](#sicherungen-zurückspielen)
11. [Neues Profil anlegen](#neues-profil-anlegen)
12. [Randomizer (Phase 5)](#randomizer-phase-5) · [für Trainer und Attacken](#randomizer-für-trainer-und-attacken)
13. [Entwicklung und Tests](#entwicklung-und-tests)

## Aufbau

```
lua/main.lua         Einstieg im Emulator (Frame-Schleife, Overlay)
lua/check.lua        Machbarkeitsprüfung: Lua-Umgebung, Game-Code, Dateiaustausch
lua/app/             Ablauf im Script: Overlay, Sperren, Sicherungen (ohne Emulator-API testbar)
lua/core/            Regel-Engine und Zustandsmodell (rein, ohne Emulator-API)
lua/mem/             Lesen/Schreiben, Ent-/Verschlüsselung, Prüfsummen, Schreibschutz
lua/net/             Verbindung zum Server über die lokale Brücke
lua/profiles/        ein Profil pro Spiel (Game-Code), Vorlage: _vorlage.lua
lua/rando/           Randomizer: Zufall, Zuordnung, Begegnungstabellen, ROM-Dateisystem
bridge/bridge.js     lokale Brücke Script <-> Server (startet automatisch mit)
server/              Vermittlungsserver (Node.js), Discord, Speicherung
web/                 Run-Übersicht (statische Seite)
tests/               Lua-Tests (core, mem, net, app) mit synthetischen Daten
config.lua           Spielername, Lobby-Code, Server-Adresse, Tasten
server/config.json   Port, Discord-Webhook, Speicherort
```

Die Regeln existieren **nur einmal**, in `lua/core`. Der Server führt genau diesen Lua-Code aus
(über [fengari](https://github.com/fengari-lua/fengari), Lua in JavaScript). Dadurch können Script und
Server nie unterschiedliche Regeln anwenden.

Datenfluss:

```
DeSmuME + lua/main.lua  <-Dateien->  bridge.js  <-WebSocket (wss)->  Server  <-WebSocket->  Run-Übersicht
                                                                     │
                                                    Lua-Regel-Engine, JSON-Speicher, Discord
```

Warum eine Brücke? Lua in DeSmuME kann kein TLS (`wss://`), und LuaSocket ist dort nicht verlässlich
vorhanden. Die Brücke ist ein kleiner Node-Prozess, den das Script beim Start selbst mitstartet.

## Installation

Jeder Spieler braucht:

1. **DeSmuME** (Windows, 64-Bit) und die eigene Spielkopie.
2. **Node.js** ab Version 20 (<https://nodejs.org>, „LTS“). Wird für die Brücke gebraucht, beim
   Server-Betreiber auch für den Server.
3. Dieses Repository, z. B. per `git clone` oder als ZIP von GitHub.
4. Im Projektordner einmal: `npm install`

Dann `config.lua` anpassen:

```lua
player_name = "Tom",                       -- so erscheinst du bei den anderen
lobby_code  = "SOUL01",                    -- bei allen gleich
server_url  = "wss://dein-server/ws",      -- vom Server-Betreiber, immer mit /ws am Ende
backups = { save_path = "C:/DeSmuME/Battery/Pokemon Platin.dsv" },
```

`write_enabled` bleibt auf `false`, bis die Schritte in [TESTEN.md](TESTEN.md) abgehakt sind.

### IntelliJ

Das Projekt lässt sich direkt als Ordner öffnen. Unter `.run/` liegen Startkonfigurationen
(„Server starten“, „Alle Tests“, „Lua-Tests“, „Server-Tests“, „Brücke (lokal)“). Sie nutzen npm und
brauchen das JavaScript/Node.js-Plugin (in IntelliJ IDEA Ultimate enthalten). In der Community-Edition
dieselben Befehle im Terminal ausführen (`npm start`, `npm test`).

## Solo-Modus (allein spielen)

Wer allein spielen will, braucht weder Server noch Brücke. In `config.lua`:

```lua
mode = "solo",
player_name = "Tom",
lobby_settings = { preset = "klassisch" },   -- oder "locker" / "hardcore", dazu changes = { ... }
```

Dann nur `lua/main.lua` in DeSmuME starten. Das Script führt dieselbe Regel-Engine lokal aus und startet den Run
automatisch (abschaltbar mit `solo = { auto_start = false }`, dann startet Taste `N`). Jede Gruppe hat genau ein
Monster, alle Regeln ohne Partner gelten: Gebiet verbraucht, Tod endgültig, tote Monster auf 0 KP, Level-Cap,
Schonfrist, Klauseln, Sicherungen und Todeszähler. Zustand und Zähler liegen in `local/solo_<name>.json` und
`local/todeszaehler.json` und überstehen Neustarts. Nach einem verlorenen Run beginnt Taste `N` einen neuen Versuch.

Ohne Server gibt es keine Run-Übersicht im Browser und keine Discord-Meldungen. Wer beides möchte, spielt allein
über den Server: `mode = "server"`, Server starten, allein in die Lobby, Taste `N`.

## Server starten

Einer betreibt den Server, die anderen verbinden sich. Auf dem eigenen PC:

```
npm start
```

Ausgabe: `Soul-Link-Server läuft auf Port 8080`. Die Run-Übersicht ist dann unter
<http://localhost:8080/> erreichbar, der WebSocket unter `ws://localhost:8080/ws`.

Einstellungen in `server/config.json`:

| Schlüssel | Bedeutung |
|---|---|
| `port` | Port (Umgebungsvariable `PORT` hat Vorrang) |
| `storage.type` / `storage.dir` | `file` mit Ordner (Standard `server/data`) |
| `heartbeat_timeout_s` | nach so vielen Sekunden ohne Lebenszeichen gilt ein Spieler als offline |
| `discord.webhook_url` | Discord-Webhook, leer = aus |
| `discord.events` | jede Meldungsart einzeln an/aus |

Der Run-Zustand wird nach jeder Änderung (gebündelt, höchstens einmal pro Sekunde) als JSON gespeichert.
Er übersteht einen Neustart von Server, Script, Emulator und PC.

## Server erreichbar machen

Es gibt zwei Wege, beide ohne Codeänderung.

### a) Eigener PC mit kostenlosem Tunnel (Cloudflare Quick Tunnel)

Kein Konto nötig, kein Router-Umbau. Die Adresse ändert sich bei jedem Start des Tunnels.

1. `cloudflared` installieren:
   <https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/>
   (unter Windows z. B. `winget install --id Cloudflare.cloudflared`).
2. Server starten: `npm start`
3. In einem zweiten Terminal: `cloudflared tunnel --url http://localhost:8080`
4. In der Ausgabe steht eine Adresse wie `https://irgendwas-zufaellig.trycloudflare.com`.
5. Diese Adresse an die Mitspieler geben. In deren `config.lua` steht dann
   `server_url = "wss://irgendwas-zufaellig.trycloudflare.com/ws"` (Achtung: `wss://` statt `https://`, `/ws` am Ende).
6. Run-Übersicht für alle: `https://irgendwas-zufaellig.trycloudflare.com/`

Der Server-PC muss während des Spielens laufen. Die Daten liegen in `server/data/`.

### b) Cloud-Dienst: Render (kostenlos) + Upstash Redis (kostenlos)

Stand der Recherche (Oktober 2026):

| Anbieter | kostenlos? | dauerhafte Verbindungen | dauerhafter Speicher |
|---|---|---|---|
| **Render** Free Web Service | ja | ja, WebSockets halten den Dienst wach | nein, Dateisystem flüchtig |
| Koyeb Free Instance | ja | ja | nein, Volumes nicht für Free-Instanzen |
| Fly.io | nein, für neue Konten nur nutzungsbasiert | – | – |
| Railway | nur Start- bzw. kleines Monatsguthaben | – | – |
| **Upstash Redis** Free | ja (256 MB, 500.000 Befehle/Monat) | – | ja |

Deshalb: **Render** für den Server, **Upstash** als dauerhafter Speicher. Der Server erkennt Upstash
automatisch an zwei Umgebungsvariablen. Ohne sie speichert er in Dateien.

1. Bei <https://upstash.com> registrieren, eine Redis-Datenbank anlegen (Free).
   Unter „REST API“ `UPSTASH_REDIS_REST_URL` und `UPSTASH_REDIS_REST_TOKEN` kopieren.
2. Bei <https://render.com> registrieren, „New > Blueprint“ wählen, dieses GitHub-Repository verbinden.
   Render liest `render.yaml` und legt den Dienst „soul-link-server“ im Tarif *Free* an.
3. Beim Anlegen die Umgebungsvariablen eintragen: die beiden Upstash-Werte, optional `DISCORD_WEBHOOK_URL`.
4. Nach dem Deploy hat der Dienst eine Adresse wie `https://soul-link-server.onrender.com`.
   In `config.lua`: `server_url = "wss://soul-link-server.onrender.com/ws"`.

Hinweise: Ein kostenloser Render-Dienst schläft nach 15 Minuten ohne Anfragen ein und braucht beim
nächsten Verbinden etwa eine Minute zum Aufwachen. Solange jemand spielt, halten die Lebenszeichen der
Scripts (alle 5 Sekunden) ihn wach. Der Speicherverbrauch ist klein: gespeichert wird höchstens einmal
pro Sekunde und nur bei Änderungen. **Es wird nichts Kostenpflichtiges eingerichtet**; beide Tarife
sind kostenlos. Vor einem Wechsel auf einen bezahlten Tarif bitte selbst entscheiden.

Quellen: [Render Free](https://render.com/docs/free),
[Render-Changelog zu WebSockets](https://render.com/changelog/free-web-services-now-remain-active-while-receiving-websocket-messages),
[Koyeb Volumes](https://www.koyeb.com/docs/reference/volumes),
[Upstash Free Plan](https://upstash.com/docs/redis/overall/billing),
[Cloudflare Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/).

## Script im Emulator starten

1. Spiel in DeSmuME laden.
2. **Beim ersten Mal:** *Tools > Lua Scripting > New Lua Script Window*, `lua/check.lua` wählen, *Run*.
   Das Script zeigt, ob alles da ist (Game-Code, Dateizugriff, Selbsttest). Ergebnis bitte in
   [TESTEN.md](TESTEN.md) festhalten.
3. Danach `lua/main.lua` starten. Die Brücke startet automatisch (ein minimiertes Fenster
   „Soul-Link-Brücke“). Alternativ von Hand: `npm run bridge -- --url wss://.../ws`.
4. Im Overlay oben links stehen Verbindungsstatus, Lesemodus-Hinweis, Aufhol-Modus, Gruppen und Todeszähler.

Tasten (änderbar in `config.lua`):

| Taste | Wirkung |
|---|---|
| `O` | Overlay ein/aus |
| `F` | Friedhof |
| `G` | Gebiets-Übersicht |
| `J` | Liste „in deiner Abwesenheit gestorben“ bestätigen |
| `P` | Sperre 30 Sekunden aussetzen, um zum PC zu laufen (wird angezeigt) |
| `N` | Lobby: Run starten (mit `lobby_settings` aus `config.lua`) / nach Run-Ende: neuer Versuch |
| `Y` / `U` | offene Abstimmung annehmen / ablehnen |
| `H` | Gruppen-Ansicht (alle Gruppen mit Mitgliedern und Status, * = im eigenen Team) |
| `K` | Eingabe-Aufnahme starten/beenden (für „Prolog überspringen“) |

Lobby und Run-Start: Wer sich zuerst mit einem Lobby-Code verbindet, legt die Lobby an. Bis zu 4 Spieler
treten mit demselben Code bei. Sind alle da, drückt einer `N`. Seine `lobby_settings` gelten dann für
alle, und die Spielerzahl steht fest. Teams für den Wettkampf und Vorschläge während des Runs gibt es
in der Engine bereits. Eine Bedienoberfläche dafür fehlt noch (siehe PROGRESS.md).

### Aufhol-Modus im Overlay

Ist ein Mitspieler deiner Gruppe offline, erscheint ein gelb hinterlegter Kasten:
- wer offline ist, seit wann, mit wie vielen Orden und wo zuletzt;
- die Orden-Grenze („frei bis 3“) oder „Nächste Arena GESPERRT“;
- ob im aktuellen Gebiet ein Fang erlaubt ist (dann ist die Gruppe sofort komplett) oder gesperrt;
- in welchen Gebieten du noch fangen darfst (der Partner hat dort schon gefangen, du noch nicht);
- der Hinweis, dass Tode beim Partner nachgetragen werden.

### Komfort-Automatiken

Beide Schalter werden in der Lobby gesetzt (`skip_prologue`, `skip_nickname` in `lobby_settings.changes`). Vor dem
Run-Start gelten die Ersatzwerte unter `automation` in `config.lua`.

- **Prolog überspringen:** Bei einem neuen Spielstand (kein Team, Spielzeit unter 2 Minuten) spielt das Script die
  Eingabefolge aus dem Profil im Schnellvorlauf ab. Es hört auf, sobald das Profil-Merkmal „Spieler kann frei
  laufen“ erfüllt ist, also am Spielzustand und nicht nach einer festen Framezahl. Danach wird der Name aus
  `config.lua` in den Spielstand geschrieben (nur A–Z, a–z, 0–9, max. 7 Zeichen, nur mit getesteter Adresse).
  **Eingabefolge erzeugen:** neues Spiel beginnen, Taste `K`, den Prolog von Hand bis zum ersten freien Schritt
  durchspielen, Taste `K`. Die Datei `local/prolog_aufnahme_<CODE>.lua` als `prologue.inputs` ins Profil übernehmen.
- **Spitznamen-Abfrage überspringen:** Erkennt das Profil die Abfrage (`nickname.prompt`), drückt das Script „Nein“
  (B), höchstens fünfmal hintereinander.

Ohne die nötigen Profilangaben bleiben beide Funktionen aus. Das Overlay sagt dann, was fehlt.

## Run-Übersicht

`web/index.html` ist eine eigenständige statische Seite. Sie verbindet sich per Server-Adresse und
Lobby-Code als Zuschauer (nur lesen) und aktualisiert sich live. Sie zeigt Spieler und Online-Status,
Orden, Gruppen, Teams, Friedhof und Todesprotokoll, Gebiets-Übersicht, aktive Regeln, Verlauf und
frühere Versuche, bei Wettkampf auch die Rangliste. Monster erscheinen nur als Text (Name, Typ).

- Vom Server ausgeliefert: `http(s)://<server>/`
- Über GitHub Pages: Workflow `.github/workflows/pages.yml` (einmalig unter *Settings > Pages > Source*
  „GitHub Actions“ wählen). Aufruf mit `?server=wss://<server>/ws&lobby=SOUL01`.

## Regeln

Umgesetzt in `lua/core` (getestet für 1, 2, 3 und 4 Spieler pro Gruppe):

1. **Link-Gruppe:** Der erste Fang jedes Spielers pro Gebiet bildet zusammen eine Gruppe
   (2 Spieler: Paar, 4 Spieler: Vierergruppe, Solo: Gruppe der Größe 1).
2. **Gebiet verbraucht:** Fängt ein Spieler bei der ersten Begegnung nichts, ist das Gebiet für alle
   verbraucht. Bereits gefangene Gruppenmitglieder sterben. Jeder weitere Fang dort ist sofort tot,
   ebenso ein zweiter Fang desselben Spielers im selben Gebiet.
3. **Gekoppelter Tod:** Fällt ein Monster, fallen alle Mitglieder seiner Gruppe in den anderen Spielen.
   Gezählt wird der eigene Tod beim Verursacher, „mitgerissen“ separat bei den anderen.
4. **Endgültig:** Tote Monster werden auf 0 KP gehalten. Ein totes Monster im Team führt nach dem Kampf
   zur Eingabesperre (Menü bleibt bedienbar), bis es in der Box liegt.
5. **Team-Gleichheit:** Alle Teams müssen aus denselben Gruppen bestehen. Bei Abweichung zeigt das
   Overlay, was fehlt oder zu viel ist, und sperrt. Monster offener Gruppen (Partner hat noch nicht
   gefangen) sind erlaubt.
6. **Level-Cap:** höchstes Level des nächsten Arenaleiters (Arena-Level im Profil).
7. **Alle Gruppen tot:** Run verloren, Statistik im Verlauf.

**Aufhol-Modus** (ein Mitspieler der eigenen Gruppe ist offline): Trainieren ist frei. Neue Orden gibt
es nur bis zum Ordenstand des Abwesenden. Fänge sind nur in Gebieten erlaubt, in denen er schon
gefangen hat, und die Gruppe ist dann sofort komplett. Ein Fang woanders ist gesperrt (gilt als tot,
verbraucht das Gebiet aber nicht). Tode werden beim Abwesenden sofort gespeichert. Beim Wiederverbinden
sieht er die Liste und muss sie bestätigen, bevor er weiterspielt.

**Savestate-Erkennung:** Geht die Spielzeit oder der Ordenstand im Spiel zurück, bekommen alle eine
Meldung. Der Server-Zustand gilt weiter, und die Regeln (z. B. tote Monster auf 0 KP) greifen sofort.

**Einstellungen** werden in der Lobby festgelegt. Während des Runs ändern sie sich nur, wenn alle
Spieler zustimmen. Das gilt auch für „Todeszähler zurücksetzen“ und „Run aufgeben“.

**Todeszähler** (pro Spieler: Tode, mitgerissen, Versuche, Siege) liegen dauerhaft auf dem Server und
zusätzlich lokal in `local/todeszaehler.json`. Sie überstehen Neustarts und neue Runs.

## Schalter und Vorlagen

| Schalter | Locker | Klassisch | Hardcore |
|---|---|---|---|
| Level-Cap (`level_cap`) | aus | an | an |
| Sonderbonbons (`rare_candies`) | an | an | aus |
| Schonfrist (`grace`) | an | an | aus |
| Duplikat-Klausel (`dupes_clause`) | an | an | aus |
| Schillernd-Klausel (`shiny_clause`) | an | an | an |
| Folgemodus (`follow_mode`) | aus | an | an |
| Items im Kampf (`battle_items.mode`) | erlaubt | erlaubt | verboten |

Weitere Schalter: `gifts_count` (Geschenke zählen als Gebietsfang), `death_log`, `skip_prologue`,
`skip_nickname`, `randomizer.mode` (`aus` | `alle` | `edition`), `goal` (`spielende` oder
`orden` mit Zahl), `scoring` (`rennen` | `ueberleben`), `discord.*`.
Eigene Vorlagen speichert der Server (`template_save`). Teile davon (Sonderbonbons, Folgemodus, Prolog,
Randomizer) wirken erst, wenn die zugehörigen Phasen umgesetzt sind (siehe PROGRESS.md).

## Discord einrichten

1. In Discord: *Servereinstellungen > Integrationen > Webhooks > Neuer Webhook*, Kanal wählen,
   *Webhook-URL kopieren*.
2. In `server/config.json` bei `discord.webhook_url` eintragen (oder Umgebungsvariable
   `DISCORD_WEBHOOK_URL`, z. B. bei Render).
3. Meldungsarten einzeln abschaltbar: `discord.events.death`, `group`, `badge`, `run_start`, `run_end`
   (Server) und zusätzlich pro Lobby in den Einstellungen (`discord.*`).

Ohne Webhook-Adresse passiert nichts.

## Sicherungen zurückspielen

Das Script legt Kopien der Speicherdatei an (vor dem ersten Schreibzugriff jeder Sitzung, bei jedem
neuen Orden, alle 15 Minuten) und behält die letzten 20. Sie liegen in `backups/`, Namensschema
`<Datum>_<Uhrzeit>_orden<N>_<Grund>.dsv`. Voraussetzung: `backups.save_path` in `config.lua`.

Zurückspielen:

1. DeSmuME schließen (oder das Spiel beenden), damit die Speicherdatei nicht überschrieben wird.
2. Die aktuelle Speicherdatei (z. B. `C:/DeSmuME/Battery/Pokemon Platin.dsv`) zur Sicherheit umbenennen.
3. Die gewünschte Sicherung aus `backups/` dorthin kopieren und genau wie die Original-Datei benennen.
4. Spiel starten und laden. Der Server bemerkt den älteren Stand (Spielzeit/Orden) und meldet ihn allen.
   Der Server-Zustand (Tote, Gruppen) bleibt gültig.

## Neues Profil anlegen

1. Game-Code mit `lua/check.lua` ablesen (z. B. `CPUD` für Platin, deutsch).
2. `lua/profiles/_vorlage.lua` nach `lua/profiles/<CODE>.lua` kopieren.
3. Adressen ermitteln (DeSmuME *Tools > RAM Search / Memory Viewer*). Formen:
   `{ addr = A }` fest, `{ ptr = P, offset = O }` hinter einem Zeiger,
   `{ chain = { S, o1 }, offset = O }` Zeigerkette, `{ rel = "party", offset = O }` relativ zum Team.
   Für das Team selbst können `candidates` angegeben werden, dazu `scan = true`. Dann sucht das Script das Team
   über seine Signatur im Speicher, falls kein Kandidat passt. `lua/check.lua` zeigt die gefundene Team-Adresse
   und die Profilwerte live an und schreibt einen Bericht nach `local/adressen_<CODE>.txt`.
4. Jede Adresse bleibt auf `tested = false`, bis ihr Prüfschritt in TESTEN.md erfolgreich war.
   Nur `tested = true` erlaubt Schreibzugriffe; Lesen geht immer.
5. `gym_levels` mit den höchsten Leveln der Arenaleiter füllen.
6. `npm test` ausführen. Die Profilprüfung (`Profiles.validate`) meldet fehlende Markierungen.

Unbekannte ROM oder fehlerhaftes Profil: klare Meldung im Overlay, das Script bleibt im Lesemodus.

## Randomizer (Phase 5)

Einstellung in der Lobby (`lobby_settings.changes`): `randomizer = { mode = "alle", seed = "" }`.
- `mode`: `aus` | `alle` (alle Arten der Generation) | `edition` (nur Arten, die in den Begegnungsdaten deines
  Spiels vorkommen; die Liste liest das Script beim Start aus der ROM).
- `seed`: beliebiger Text. Leer = der Server vergibt beim Run-Start einen festen Seed für diesen Versuch.

**Stufe A (umgesetzt):** Beim Betreten eines Gebiets überschreibt das Script die geladene Begegnungstabelle.
Die Zuordnung ist pro Gebiet fest: Jede Originalart wird zu einer festen neuen Art, verschiedene Originalarten
werden zu verschiedenen neuen Arten (Seltenheitsstufen bleiben). Level und Raten ändern sich nicht. Geschrieben
wird nur außerhalb von Kämpfen und nur, wenn `encounter_table` im Profil getestet und `write_enabled` an ist.

**Gleiche Begegnungen bei allen:** Die Zuordnung hängt nur von Seed, Modus und Artenliste ab und ist in jeder
Lua-Version gleich (automatisch getestet). Jedes Script meldet einen Fingerabdruck davon an den Server. Weicht
er bei einem Spieler ab (z. B. andere Edition im Modus `edition`), bekommen alle eine Warnung.

**Was dafür nötig ist:** `rom_path` in `config.lua` (Pfad zu deiner eigenen ROM, wird nur gelesen). Das Script
liest daraus die Begegnungsdateien und findet über einen exakten Abgleich die gerade geladene Tabelle im
Speicher. `lua/check.lua` zeigt, ob das klappt.

**Stufen B und C** (Starter/Geschenke/feste Begegnungen bzw. geschenkte Items): Die Zuordnungen sind fertig und
getestet, ebenso die Ausschlussliste für Items. Ausgeschlossen sind VM/TM-Tasche und Basis-Items, abgeleitet aus
den Taschen des Spiels. Die Schreibzugriffe kommen erst, wenn Stufe A im Emulator stabil läuft
(Profil: `randomizer.stage_a_stable = true`) bzw. Stufe B (`stage_b_stable`).

## Randomizer für Trainer und Attacken

Trainer-Teams und Attacken randomisiert das Script nicht. Dafür vorab ein Randomizer-Programm auf die
eigene ROM anwenden (z. B. den „Universal Pokemon Randomizer“ in einer aktuellen Fork-Version) und
allen dieselben Einstellungen und denselben Seed geben. Das Script liest Arten, Typen und Begegnungen
zur Laufzeit aus dem geladenen Spiel und funktioniert deshalb auch mit vorab randomisierten Spielen.

## Entwicklung und Tests

```
npm test             # alles
npm run test:lua     # Lua-Tests unter fengari (Lua 5.3) und, falls installiert, Lua 5.1
npm run test:server  # Server, Brücke, Ende-zu-Ende
```

Die Lua-Tests brauchen keine Installation (fengari kommt mit `npm install`). Ist zusätzlich ein Lua 5.1
im PATH, laufen sie auch darunter, also mit der Lua-Version von DeSmuME. GitHub Actions führt beides bei
jedem Push aus.

Hinweise zum Lua-Code (beide Laufzeiten): keine Bit-Operatoren (`lib/bits.lua` nutzen), keine
Hex-Literale ab `0x80000000`, große Zahlen als Gleitkomma rechnen (fengari hat 32-Bit-Ganzzahlen),
Zahlen über `string.format("%.0f")` statt `tostring` in Text wandeln.
