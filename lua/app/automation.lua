-- Komfort-Automatiken (Phase 4): Prolog überspringen und Spitznamen-Abfrage ablehnen.
-- Rein bis auf die übergebenen Funktionen; Bedingungen kommen aus dem Profil (Spielzustand, nie feste Framezahl).
--
-- Profil:
--   prologue = {
--     tested = false,
--     inputs = { ...Schritte (app/inputs.lua)... },   -- per Aufnahme erzeugt (Taste K)
--     start = { entry = "name", equals = Wert } | nil,  -- neuer Spielstand erkannt (zusätzlich: kein Team, Spielzeit < 2 min)
--     done  = { entry = "name", equals = Wert },        -- Spieler kann frei laufen
--   }
--   nickname = { prompt = { entry = "name", equals = Wert }, decline = { ...Schritte... } }
--   addresses.trainer_name = { ..., tested = ... }      -- Spielername aus config.lua (Schreibzugriff)

local Inputs = require("app.inputs")

local Auto = {}
Auto.__index = Auto

Auto.NEW_GAME_MAX_PLAYTIME = 120     -- Sekunden
Auto.NICKNAME_DEFAULT = { { keys = "B", frames = 2 }, { wait = 10 } } -- B = "Nein"
Auto.NICKNAME_MAX_TRIES = 5

--- opts: profile, inputs (Inputs-Objekt), read (Funktion entry_name -> Wert|nil), note (Funktion text, level),
---       set_speed (Funktion "turbo"|"normal"), write_name (Funktion name -> ok, grund)
function Auto.new(opts)
  local self = setmetatable({}, Auto)
  self.profile = opts.profile or {}
  self.inputs = opts.inputs or Inputs.new()
  self.read = opts.read
  self.note = opts.note or function() end
  self.set_speed = opts.set_speed or function() end
  self.write_name = opts.write_name
  self.prologue_state = "bereit" -- bereit | läuft | fertig | aus | nicht_verfügbar
  self.nickname_tries = 0
  return self
end

function Auto:check(cond)
  if not cond then return false end
  local v = self.read(cond.entry)
  if v == nil then return false end
  if cond.equals ~= nil then return v == cond.equals end
  if cond.not_equals ~= nil then return v ~= cond.not_equals end
  return v ~= 0
end

--- Ist die Funktion im Profil vorhanden? Rückgabe: ok, grund
function Auto:prologue_available()
  local p = self.profile.prologue
  if not p or not p.inputs or #p.inputs == 0 then return false, "keine Eingabefolge im Profil (Aufnahme mit Taste K)" end
  -- done ist optional: ohne Ende-Bedingung endet der Prolog, wenn die Aufnahme durch ist
  -- (die Aufnahme endet genau am ersten freien Schritt).
  return true
end

local function new_game(snap)
  return snap and (snap.party == nil or #snap.party == 0)
    and (snap.play_time == nil or snap.play_time < Auto.NEW_GAME_MAX_PLAYTIME)
end

--- Pro Prüfzyklus aufrufen. enabled: Schalter skip_prologue; snap: Schnappschuss.
function Auto:prologue_tick(enabled, snap, player_name)
  local p = self.profile.prologue or {}
  if self.prologue_state == "fertig" or self.prologue_state == "aus" then return end
  if not enabled then return end
  if self.prologue_state == "bereit" then
    if not new_game(snap) then
      self.prologue_state = "aus" -- kein neuer Spielstand: nichts tun
      return
    end
    if p.start and not self:check(p.start) then return end
    local ok, reason = self:prologue_available()
    if not ok then
      self.prologue_state = "nicht_verfügbar"
      self.note("Prolog überspringen nicht möglich: " .. reason, "warn")
      return
    end
    self.inputs:play("prolog", p.inputs)
    self.set_speed("turbo")
    self.prologue_state = "läuft"
    self.note("Prolog wird übersprungen (Schnellvorlauf) ...")
    return
  end
  if self.prologue_state == "läuft" then
    if p.done and self:check(p.done) then
      self:finish_prologue(player_name, "Prolog übersprungen – du kannst frei laufen.")
    elseif not self.inputs:busy() then
      if p.done then
        self:finish_prologue(player_name, "Eingabefolge zu Ende, Ende-Bedingung nicht erreicht – bitte selbst weiterspielen.", "warn")
      else
        self:finish_prologue(player_name, "Prolog übersprungen (Aufnahme zu Ende) – du kannst frei laufen.")
      end
    end
  end
end

function Auto:finish_prologue(player_name, text, level)
  if self.inputs.name == "prolog" then self.inputs:stop() end
  self.set_speed("normal")
  self.prologue_state = "fertig"
  if self.write_name and player_name then
    local ok, reason = self.write_name(player_name)
    if not ok then text = text .. " Name nicht gesetzt (" .. tostring(reason) .. ")." end
  end
  self.note(text, level)
end

--- Spitznamen-Abfrage automatisch ablehnen (Schalter skip_nickname).
function Auto:nickname_tick(enabled)
  local n = self.profile.nickname
  if not enabled or not n or not n.prompt then return end
  if self.inputs:busy() then return end
  if self:check(n.prompt) then
    if self.nickname_tries >= Auto.NICKNAME_MAX_TRIES then return end
    self.nickname_tries = self.nickname_tries + 1
    self.inputs:play("spitzname", n.decline or Auto.NICKNAME_DEFAULT)
  else
    self.nickname_tries = 0
  end
end

--- Statuszeile für das Overlay (oder nil).
function Auto:status_line()
  if self.prologue_state == "läuft" then return "Prolog wird übersprungen ..." end
  return nil
end

return Auto
