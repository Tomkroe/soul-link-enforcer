-- Einstellungen für das Emulator-Script. Jeder Spieler passt diese Datei für sich an.
return {
  -- Dein Name (so erscheinst du bei den anderen) und der gemeinsame Lobby-Code
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
  },

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
