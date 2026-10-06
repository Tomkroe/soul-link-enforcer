-- Pokémon Platin, deutsche Version (Game-Code CPUD).
--
-- Ein Teil der Adressen ist im Emulator bestätigt (tested = true, mit Datum), der Rest ist ungetestet. Für die
-- deutsche Version gibt es keine öffentliche Quelle. Die Werte stammen aus Werkzeugen für die US- bzw. PAL-Version und sind deshalb nur Kandidaten:
--   [IM]  NDS-Ironmon-Tracker (Brian0255), constants/MemoryAddresses.lua, Platinum US:
--         Basis = read32(read32(0x02000BA8) + 0x20); Team +0xB4, Orden +0x96, Medizin-Tasche +0xB60,
--         Karte +0x239B0, Gegner-Trainer +0x4189E, Gegner-Team +0x4BE5C; Kampfstatus absolut 0x0224A55A
--         (u16, 0x2100/0x2101 = im Kampf).
--   [YP]  yPokeStats (yling), data/gamesdata.lua, Platinum US/PAL: Team = read32(0x02101D2C) + 0xD094.
-- Das Team wird außerdem per Signatur im ganzen Speicher gesucht (mem/finder.lua), damit es auch dann
-- gefunden wird, wenn die deutschen Zeiger anders liegen. Werte relativ zum Team (rel = "party") gelten,
-- wenn der Spielstand-Aufbau zwischen den Sprachversionen gleich ist – das ist zu prüfen (TESTEN.md).

local CHAIN = { 0x02000BA8, 0x20 } -- [IM] Zeigerkette zur Basis

return {
  game_code = "CPUD",
  name = "Platin",
  gen = 4,

  addresses = {
    game_code = { addr = 0x023FFE0C, tested = true }, -- bestätigt 05.10.2026 (check.lua: "CPUD")

    -- Team: erster Datensatz (236 Byte je Monster). Davor u32 Kapazität (6) und u32 Anzahl.
    party = {
      tested = false, battle_safe = false, scan = true,
      candidates = {
        { chain = CHAIN, offset = 0xB4, quelle = "Ironmon US" },
        { ptr = 0x02101D2C, offset = 0xD094, quelle = "yPokeStats US/PAL" },
      },
    },
    -- Bestätigt 05.10.2026: 1 -> 2 nach einem Fang (Bidaf). Davor Kapazität u32 (6) bei -8.
    party_count = { rel = "party", offset = -4, width = 32, tested = true },

    -- Trainer-Daten liegen laut [IM] direkt vor dem Team (Orden bei Basis +0x96, Team bei +0xB4). Daraus
    -- abgeleitet (Aufbau Name 16 Byte, ID, Geld, Geschlecht, Region, Orden): Spielername bei Team -0x38.
    -- Bestätigt 05.10.2026: liest den Trainernamen "TOM" (0x013E 0x0139 0x0137), Gen-4-Zeichensatz korrekt.
    trainer_name = { rel = "party", offset = -0x38, tested = true },

    -- Orden (Bitfeld, 8 Bit). [IM] Basis +0x96 = Team -0x1E
    badges = { rel = "party", offset = -0x1E, width = 8, tested = false },

    -- Beutel. [IM] Medizin-Tasche bei Basis +0xB60; Ball-Tasche abgeleitet aus der Taschenreihenfolge der
    -- Decompilation (Medizin 40 Plätze, Beeren 64 Plätze, je 4 Byte): +0xB60 + 0x1A0 = +0xD00 = Team +0xC4C.
    -- Bestätigt 05.10.2026: vor dem Kauf balls=false, nach dem Ball-Kauf balls=true.
    bag_balls = { rel = "party", offset = 0xC4C, width = 16, slots = 15, tested = true },
    -- Medizin-Tasche ([IM] Basis +0xB60 = Team +0xAAC, 40 Plätze) und Kampf-Tasche (nach Bällen: +0xD3C = Team +0xC88,
    -- 30 Plätze, abgeleitet). Für "Items im Kampf" (Bestand vor/nach dem Kampf).
    bag_medicine = { rel = "party", offset = 0xAAC, slots = 40, tested = false },
    bag_battle = { rel = "party", offset = 0xC88, slots = 30, tested = false },
    -- Item-Tasche (Beginn des Beutels, abgeleitet: Medizin - (165+50+100+12)*4 = Team +0x590, 165 Plätze)
    -- für Sonderbonbons.
    -- Taschen-Layout bestätigt 05.10.2026: bag_balls (+0xC4C) liest Poké Ball (ID 4) x6.
    -- bag_items (+0x590) ist die Items-Tasche daneben (Sonderbonbons). tested = true für den Schreibzugriff.
    bag_items = { rel = "party", offset = 0x590, slots = 165, tested = true },

    -- Aktuelle Karte (Kartennummer, u16). [IM] childMapHeader
    -- Bestätigt 05.10.2026: wechselt beim Kartenwechsel (See 334 <-> Route 342), stabil am selben Ort.
    area_id = { chain = CHAIN, offset = 0x239B0, width = 16, tested = true },

    -- Kampf. US-Adresse war 0x0224A55A; in der deutschen Version +6 verschoben: 0x0224A560.
    -- Bestätigt 05.10.2026 (wilder Kampf): out-of-battle 0xD116, im Kampf 0x2102. High-Byte 0x21 = im Kampf
    -- (Low-Byte ist nur die Phase, US war 0x2100/0x2101). Trainer-Kampf noch gegenzuprüfen.
    battle_flag = { addr = 0x0224A560, width = 16, high_byte = 0x21, tested = true },
    -- Bestätigt 05.10.2026: wild = 0, Trainerkampf = 1 (wild_if_zero).
    battle_type = { chain = CHAIN, offset = 0x4189E, width = 16, wild_if_zero = true, tested = true },
    -- Bestätigt 05.10.2026: wilder Kampf gegen Staralili -> opp = Art 396, Lv. 3.
    battle_enemy = { chain = CHAIN, offset = 0x4BE5C, tested = true },
    -- Kampfstatistik: PID des aktiven eigenen Monsters ([IM] playerBattleMonPID, Basis +0x47620) und
    -- Gegner-Team (6 Datensätze ab battle_enemy) für besiegte Gegner.
    battle_active_pid = { chain = CHAIN, offset = 0x47620, width = 32, tested = false },

    -- Spielzeit: NICHT gefunden. Der sekündlich steigende Wert nahe dem Team (Team -0x13/-0x12) ist die
    -- Echtzeituhr (Wanduhr-Minuten/-Sekunden), nicht die Spielzeit. Die echte Spielzeit liegt im Save-Block
    -- (andere Stelle; check.lua sortiert RTC-Werte inzwischen aus). Kein play_time-Eintrag -> Savestate-Erkennung läuft über Ordenstand.

    -- Boxen: keine Quelle. check.lua findet den Anfang (Monster in Box 1, Platz 1 legen); dann hier eintragen:
    -- boxes = { rel = "party", offset = <aus dem Bericht>, count = 18, slots = 30, tested = false },

    -- Kampfkopie des Teams ([IM] playerBattleBase, Basis +0x4B8AC): tote Monster auch im Kampf auf 0 KP halten.
    -- Nur mit battle_safe = true (nach Test im Emulator).
    battle_party = { chain = CHAIN, offset = 0x4B8AC, tested = false, battle_safe = false },

    -- Geladene Begegnungstabelle der aktuellen Karte: keine Quelle. Das Script sucht sie im Speicher
    -- (exakter Abgleich mit den Begegnungsdateien aus der eigenen ROM, rom_path in config.lua).
    encounter_table = { scan = true, tested = false },

    -- Noch offen (keine Quelle): Spielzeit, Boxen, Spieldaten-Tabellen (Artnamen, Gebietsnamen).
  },

  -- Spieldaten aus der eigenen ROM (rom_path). Pfade und Textbank-Nummern aus Werkzeugen für die US-Version,
  -- ungeprüft – check.lua zeigt Beispiele zur Kontrolle.
  gamedata = {
    personal_narc = "poketool/personal/pl_personal.narc",
    evo_narc = "poketool/personal/evo.narc",
    msg_narc = "msgdata/pl_msg.narc",
    texts = { species = 412, types = 624 },
  },

  -- Item-Nummern (Gen 4): Sonderbonbon = 50. getestet: nein
  items = { rare_candy = 50 },

  -- Randomizer (Phase 5). Pfad und Format aus Erinnerung an die DPPt-Struktur, ungeprüft (TESTEN.md).
  randomizer = {
    encounter_narc = "fielddata/encountdata/pl_enc_data.narc",
    encounter_layout = {
      size = 0x1A8,
      slots = {
        { offset = 0x08, count = 12, stride = 8, width = 32 },  -- Gras: 12 x (Level u32, Art u32)
        { offset = 0x64, count = 10, stride = 4, width = 32 },  -- Schwarm 2, Tag 2, Nacht 2, Radar 4
        { offset = 0xA4, count = 10, stride = 4, width = 32 },  -- GBA-Einschub (je 2: R, S, Sm, FR, BG)
        { offset = 0xD4, count = 5, stride = 8, width = 32 },   -- Surfen
        { offset = 0x100, count = 5, stride = 8, width = 32 },  -- (Zertrümmerer, in DPPt ungenutzt)
        { offset = 0x12C, count = 5, stride = 8, width = 32 },  -- Angel
        { offset = 0x158, count = 5, stride = 8, width = 32 },  -- Profiangel
        { offset = 0x184, count = 5, stride = 8, width = 32 },  -- Superangel
      },
    },
    exclude = {},               -- Arten, die nie als Ersatz vorkommen sollen
    stage_a_stable = false,     -- erst true, wenn Stufe A im Emulator stabil getestet ist
    stage_b_stable = false,
  },

  -- Höchstes Level des jeweiligen Arenaleiters in Platin (Index 1 = erster Orden), danach Top Vier und Champ.
  -- Aus allgemeinem Spielwissen, nicht aus dem ROM gelesen – bitte gegenprüfen. getestet: nein
  gym_levels = {
    14, 22, 26, 32, 37, 41, 44, 50, -- Arenen 1–8
    53, 55, 57, 59, 62,             -- Top Vier und Champ
    tested = false,
  },

  -- Prolog-Eingabefolge aus der Aufnahme (Taste K) vom 05.10.2026. Endet am ersten freien Schritt;
  -- ohne done-Merkmal beendet die Automatik den Prolog, wenn die Aufnahme durch ist.
  prologue = { tested = true, inputs = require("profiles.CPUD_prologue") },
}
