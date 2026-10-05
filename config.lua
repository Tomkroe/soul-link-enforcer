-- Einstellungen für das Emulator-Script. Jeder Spieler passt diese Datei für sich an.
return {
  -- Spielmodus: "server" (mit Mitspielern über den Vermittlungsserver) oder "solo" (allein, ganz ohne Server
  -- und Brücke; Regeln, Todeszähler und Sicherungen laufen lokal, Zustand in local/solo_<name>.json)
  mode = "server",
  solo = { auto_start = true },   -- Solo: Run beim ersten Start automatisch beginnen

  -- Dein Name (so erscheinst du bei den anderen; Spielstand-Name bei "Prolog überspringen", max. 7 Zeichen)
  -- und der gemeinsame Lobby-Code
  player_name = "Spieler1",
  lobby_code = "SOUL01",

  -- Adresse des Vermittlungsservers (ws:// lokal, wss:// über Tunnel oder Cloud), immer mit /ws am Ende
  server_url = "ws://localhost:8080/ws",

  -- Lokale Brücke (Node.js) zwischen Script und Server; startet automatisch mit
  bridge = {
    autostart = true,
    node = "node",            -- Pfad zu node.exe, falls nicht im PATH
    exchange_dir = nil,       -- Standard: <Projekt>/bridge/exchange
  },

  -- Pfad zur eigenen ROM-Datei (nur lesen): für den Randomizer-Modus "edition" und die Suche nach der
  -- Begegnungstabelle. Die ROM wird nie kopiert oder verschickt.
  rom_path = "",          -- z. B. "C:/ROMs/Pokemon Platin.nds"

  -- Schreibzugriffe auf den Spielspeicher. Erst einschalten, wenn TESTEN.md abgehakt ist!
  -- Auch dann wird nur an Adressen geschrieben, die im Profil als getestet markiert sind.
  write_enabled = false,

  -- Tasten (Tastatur) für das Overlay
  hotkeys = {
    overlay = "O",      -- Overlay ein/aus
    graveyard = "F",    -- Friedhof
    areas = "G",        -- Gebiets-Übersicht
    confirm = "J",      -- Abwesenheitsliste bestätigen
    pc_pass = "P",      -- Sperre 30 s aussetzen, um zum PC zu laufen
    start = "N",        -- Lobby: Run starten / nach Run-Ende: neuer Versuch
    vote_yes = "Y",     -- offene Abstimmung annehmen
    vote_no = "U",      -- offene Abstimmung ablehnen
    groups = "H",       -- Gruppen-Ansicht
    record = "K",       -- Eingabe-Aufnahme starten/beenden (für die Prolog-Eingabefolge im Profil)
  },

  -- Ersatzwerte für Automatiken, solange noch kein Run-Zustand da ist (sonst gelten die Lobby-Einstellungen)
  automation = { skip_prologue = false, skip_nickname = false },

  -- Einstellungen, die beim Run-Start (Taste N) für alle gesetzt werden.
  -- Vorlagen: "locker", "klassisch", "hardcore". Einzelne Schalter danach in changes, z. B.
  -- changes = { level_cap = false, goal = { kind = "orden", value = 8 } }
  lobby_settings = { preset = "klassisch", changes = nil },

  overlay = { x = 2, y = 2, compact = false },

  -- Automatische Sicherungen der Speicherdatei (DeSmuME: Ordner "Battery", Endung .dsv)
  backups = {
    save_path = "",     -- z. B. "C:/DeSmuME/Battery/Pokemon Platin.dsv"
    dir = nil,          -- Standard: <Projekt>/backups
    keep = 20,
    interval_min = 15,
  },
}
