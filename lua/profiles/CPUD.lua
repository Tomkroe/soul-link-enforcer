-- Pokémon Platin, deutsche Version (Game-Code CPUD).
--
-- ALLE Adressen sind ungetestet (tested = false). Für die deutsche Version gibt es keine öffentliche
-- Quelle. Die Werte stammen aus Werkzeugen für die US- bzw. PAL-Version und sind deshalb nur Kandidaten:
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
    game_code = { addr = 0x023FFE0C, tested = false },

    -- Team: erster Datensatz (236 Byte je Monster). Davor u32 Kapazität (6) und u32 Anzahl.
    party = {
      tested = false, battle_safe = false, scan = true,
      candidates = {
        { chain = CHAIN, offset = 0xB4, quelle = "Ironmon US" },
        { ptr = 0x02101D2C, offset = 0xD094, quelle = "yPokeStats US/PAL" },
      },
    },
    party_count = { rel = "party", offset = -4, width = 32, tested = false },

    -- Trainer-Daten liegen laut [IM] direkt vor dem Team (Orden bei Basis +0x96, Team bei +0xB4). Daraus
    -- abgeleitet (Aufbau Name 16 Byte, ID, Geld, Geschlecht, Region, Orden): Spielername bei Team -0x38.
    trainer_name = { rel = "party", offset = -0x38, tested = false },

    -- Orden (Bitfeld, 8 Bit). [IM] Basis +0x96 = Team -0x1E
    badges = { rel = "party", offset = -0x1E, width = 8, tested = false },

    -- Beutel. [IM] Medizin-Tasche bei Basis +0xB60; Ball-Tasche abgeleitet aus der Taschenreihenfolge der
    -- Decompilation (Medizin 40 Plätze, Beeren 64 Plätze, je 4 Byte): +0xB60 + 0x1A0 = +0xD00 = Team +0xC4C.
    bag_balls = { rel = "party", offset = 0xC4C, width = 16, slots = 15, tested = false },
    -- Medizin-Tasche ([IM] Basis +0xB60 = Team +0xAAC, 40 Plätze) und Kampf-Tasche (nach Bällen: +0xD3C = Team +0xC88,
    -- 30 Plätze, abgeleitet). Für "Items im Kampf" (Bestand vor/nach dem Kampf).
    bag_medicine = { rel = "party", offset = 0xAAC, slots = 40, tested = false },
    bag_battle = { rel = "party", offset = 0xC88, slots = 30, tested = false },
    -- Item-Tasche (Beginn des Beutels, abgeleitet: Medizin - (165+50+100+12)*4 = Team +0x590, 165 Plätze)
    -- für Sonderbonbons.
    bag_items = { rel = "party", offset = 0x590, slots = 165, tested = false },

    -- Aktuelle Karte (Kartennummer, u16). [IM] childMapHeader
    area_id = { chain = CHAIN, offset = 0x239B0, width = 16, tested = false },

    -- Kampf. [IM] Kampfstatus ist eine feste Adresse der US-Version – in der deutschen Version vermutlich
    -- verschoben. Gegner-Trainer-ID 0 = wilder Kampf (Annahme).
    battle_flag = { addr = 0x0224A55A, width = 16, values = { [0x2100] = true, [0x2101] = true }, tested = false },
    battle_type = { chain = CHAIN, offset = 0x4189E, width = 16, wild_if_zero = true, tested = false },
    battle_enemy = { chain = CHAIN, offset = 0x4BE5C, tested = false },

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

  prologue = { tested = false, inputs = {} },
}
