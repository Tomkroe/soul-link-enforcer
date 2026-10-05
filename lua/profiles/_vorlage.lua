-- VORLAGE für ein neues Spielprofil. Kopieren nach lua/profiles/<GAMECODE>.lua (z. B. CPUD.lua)
-- und Werte im Emulator ermitteln (Anleitung: README, Abschnitt "Neues Profil anlegen").
--
-- Jede Adresse trägt "tested": Nur Einträge mit tested = true werden jemals beschrieben.
-- Lesen ist auch bei tested = false erlaubt (das Overlay markiert solche Werte mit "?").
-- Adressen sind entweder fest ({ addr = 0x02... }) oder über einen Basiszeiger
-- ({ ptr = 0x02..., offset = 0x... }: Adresse = read32(ptr) + offset).

return {
  game_code = "XXXX",
  name = "Name der Edition",
  gen = 4,                        -- 4 oder 5

  addresses = {
    -- ROM-Header-Kopie im Arbeitsspeicher; Game-Code als 4 ASCII-Zeichen
    game_code   = { addr = 0x027FFE0C, tested = false },
    -- Team: Anzahl und erster Datensatz (Gen 4: 236 Byte, Gen 5: 220 Byte je Monster)
    party_count = { ptr = 0x00000000, offset = 0x0, tested = false },
    party       = { ptr = 0x00000000, offset = 0x0, tested = false, battle_safe = false },
    -- Boxen: erster Datensatz (136 Byte je Monster), Anzahl Boxen und Plätze
    boxes       = { ptr = 0x00000000, offset = 0x0, tested = false, count = 18, slots = 30 },
    -- Aktuelles Gebiet (Kartennummer) und Ordenstand (Bitfeld)
    area_id     = { ptr = 0x00000000, offset = 0x0, tested = false },
    badges      = { ptr = 0x00000000, offset = 0x0, tested = false },
    -- Spielzeit (Stunden u16, Minuten u8, Sekunden u8)
    play_time   = { ptr = 0x00000000, offset = 0x0, tested = false },
    -- Beutel: Ballfach (für Schonfrist) und Basis-Items (Sonderbonbons)
    bag_balls   = { ptr = 0x00000000, offset = 0x0, tested = false },
    bag_items   = { ptr = 0x00000000, offset = 0x0, tested = false },
    -- Kampf: Kennzeichen "im Kampf", wild/Trainer, Gegner, Ergebnis
    battle_flag = { ptr = 0x00000000, offset = 0x0, tested = false },
    battle_type = { ptr = 0x00000000, offset = 0x0, tested = false },
    battle_enemy = { ptr = 0x00000000, offset = 0x0, tested = false },
    -- Spieldaten im ROM-Abbild (Artnamen, Typen, Entwicklungen, Gebietsnamen) – zur Laufzeit lesen
    species_names = { ptr = 0x00000000, offset = 0x0, tested = false },
    area_names    = { ptr = 0x00000000, offset = 0x0, tested = false },
  },

  -- Höchstes Level des jeweiligen Arenaleiters (Index 1 = erster Orden). Für das Level-Cap.
  gym_levels = { tested = false },

  -- Eingabefolge für "Prolog überspringen" (Phase 4). Ende wird am Spielzustand erkannt.
  prologue = { tested = false, inputs = {} },
}
