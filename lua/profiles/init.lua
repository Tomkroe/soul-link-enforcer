-- Spielprofile: ein Profil pro Game-Code unter lua/profiles/<CODE>.lua.
-- Erkennung über den Game-Code im ROM-Header. Unbekannte ROM -> kein Profil -> reiner Lesemodus.

local Profiles = {}

-- Deutsche Versionen der 4. und 5. Generation (Region "D"). Nur Namen, keine Spieldaten.
Profiles.KNOWN = {
  ADAD = { name = "Diamant", gen = 4 },
  APAD = { name = "Perl", gen = 4 },
  CPUD = { name = "Platin", gen = 4 },
  IPKD = { name = "HeartGold", gen = 4 },
  IPGD = { name = "SoulSilver", gen = 4 },
  IRBD = { name = "Schwarz", gen = 5 },
  IRAD = { name = "Weiß", gen = 5 },
  IRED = { name = "Schwarz 2", gen = 5 },
  IRDD = { name = "Weiß 2", gen = 5 },
}

local REQUIRED = { "game_code", "name", "gen", "addresses" }

--- Prüft ein Profil auf Pflichtfelder und Markierungen. Rückgabe: ok, Liste der Probleme.
function Profiles.validate(p)
  local problems = {}
  for _, k in ipairs(REQUIRED) do
    if p[k] == nil then problems[#problems + 1] = "Pflichtfeld fehlt: " .. k end
  end
  for name, entry in pairs(p.addresses or {}) do
    if type(entry) ~= "table" then
      problems[#problems + 1] = "Adresse " .. name .. " ist keine Tabelle"
    else
      if entry.tested ~= true and entry.tested ~= false then
        problems[#problems + 1] = "Adresse " .. name .. " ohne Markierung 'tested'"
      end
      if entry.addr == nil and entry.ptr == nil then
        problems[#problems + 1] = "Adresse " .. name .. " ohne addr/ptr"
      end
    end
  end
  return #problems == 0, problems
end

--- Lädt das Profil zum Game-Code. Rückgabe: profil|nil, meldung
function Profiles.load(code)
  if type(code) ~= "string" or not code:match("^[%w]+$") then
    return nil, "Kein gültiger Game-Code gelesen"
  end
  local ok, profile = pcall(require, "profiles." .. code)
  if not ok or type(profile) ~= "table" then
    local known = Profiles.KNOWN[code]
    if known then
      return nil, "Für " .. known.name .. " (" .. code .. ") gibt es noch kein Profil – reiner Lesemodus."
    end
    return nil, "Unbekannte ROM (" .. code .. ") – reiner Lesemodus."
  end
  local valid, problems = Profiles.validate(profile)
  if not valid then
    return nil, "Profil " .. code .. " fehlerhaft: " .. problems[1] .. " – reiner Lesemodus."
  end
  return profile, "Profil geladen: " .. profile.name
end

--- Zählt getestete und ungetestete Adressen (für das Overlay).
function Profiles.coverage(p)
  local tested, total = 0, 0
  for _, entry in pairs(p and p.addresses or {}) do
    total = total + 1
    if entry.tested == true then tested = tested + 1 end
  end
  return tested, total
end

return Profiles
