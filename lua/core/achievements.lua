-- Erfolge pro Spieler (Idee für später, umgesetzt): Schwellen auf die dauerhaften Zähler der Bilanz.
-- Die Engine liefert die Zähler als "stat"-Effekte; core/ledger.lua schaltet frei.

local A = {}

A.LIST = {
  { id = "erster_fang", name = "Erster Fang", text = "Ein Monster in eine Gruppe gefangen", key = "catches", min = 1 },
  { id = "sammler", name = "Sammler", text = "25 Gruppenfänge insgesamt", key = "catches", min = 25 },
  { id = "glitzer", name = "Glitzer", text = "Ein schillerndes Monster gefangen", key = "shinies", min = 1 },
  { id = "erster_orden", name = "Erster Orden", text = "Den ersten Orden geholt", key = "badges", min = 1 },
  { id = "ordensjaeger", name = "Ordensjäger", text = "24 Orden insgesamt", key = "badges", min = 24 },
  { id = "achtfach", name = "Achtfach", text = "Alle 8 Orden in einem Versuch", key = "all_badges", min = 1 },
  { id = "makellos", name = "Makellos", text = "Einen Orden geholt, ohne im Versuch ein eigenes Monster verloren zu haben", key = "flawless_badge", min = 1 },
  { id = "aufholjagd", name = "Aufholjagd", text = "Einen Orden im Aufhol-Modus geholt (regelkonform)", key = "catchup_badge", min = 1 },
  { id = "volles_haus", name = "Volles Haus", text = "Sechs komplette, lebende Gruppen gleichzeitig", key = "full_team", min = 1 },
  { id = "sieger", name = "Sieger", text = "Einen Run gewonnen", key = "wins", min = 1 },
  { id = "hattrick", name = "Hattrick", text = "Drei Runs gewonnen", key = "wins", min = 3 },
  { id = "durchhalter", name = "Durchhalter", text = "10 Runs beendet", key = "runs", min = 10 },
  { id = "pechvogel", name = "Pechvogel", text = "10 eigene Tode", key = "deaths", min = 10 },
  { id = "friedhofsgaertner", name = "Friedhofsgärtner", text = "50 eigene Tode", key = "deaths", min = 50 },
  { id = "seelenverwandt", name = "Seelenverwandt", text = "10 Monster mitgerissen", key = "dragged", min = 10 },
  { id = "tippkoenig", name = "Tippkönig", text = "10 Punkte in Tipprunden", key = "tip_points", min = 10 },
  { id = "kaempfer", name = "Kämpfer", text = "100 Gegner besiegt", key = "kos", min = 100 },
}

A.BY_ID = {}
for _, a in ipairs(A.LIST) do A.BY_ID[a.id] = a end

--- Prüft einen Spieler-Eintrag der Bilanz. Rückgabe: Liste neu freigeschalteter Erfolge (und trägt sie ein).
function A.check(player, t)
  player.achievements = player.achievements or {}
  local new = {}
  for _, a in ipairs(A.LIST) do
    if not player.achievements[a.id] and (player[a.key] or 0) >= a.min then
      player.achievements[a.id] = t or 0
      new[#new + 1] = a
    end
  end
  return new
end

return A
