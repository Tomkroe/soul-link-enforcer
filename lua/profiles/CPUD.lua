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

    -- Orden (Bitfeld, 8 Bit). [IM] Basis +0x96 = Team -0x1E
    badges = { rel = "party", offset = -0x1E, width = 8, tested = false },

    -- Beutel. [IM] Medizin-Tasche bei Basis +0xB60; Ball-Tasche abgeleitet aus der Taschenreihenfolge der
    -- Decompilation (Medizin 40 Plätze, Beeren 64 Plätze, je 4 Byte): +0xB60 + 0x1A0 = +0xD00 = Team +0xC4C.
    bag_balls = { rel = "party", offset = 0xC4C, width = 16, tested = false },

    -- Aktuelle Karte (Kartennummer, u16). [IM] childMapHeader
    area_id = { chain = CHAIN, offset = 0x239B0, width = 16, tested = false },

    -- Kampf. [IM] Kampfstatus ist eine feste Adresse der US-Version – in der deutschen Version vermutlich
    -- verschoben. Gegner-Trainer-ID 0 = wilder Kampf (Annahme).
    battle_flag = { addr = 0x0224A55A, width = 16, values = { [0x2100] = true, [0x2101] = true }, tested = false },
    battle_type = { chain = CHAIN, offset = 0x4189E, width = 16, wild_if_zero = true, tested = false },
    battle_enemy = { chain = CHAIN, offset = 0x4BE5C, tested = false },

    -- Noch offen (keine Quelle): Spielzeit, Boxen, Spieldaten-Tabellen (Artnamen, Gebietsnamen).
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
