-- Hauptlogik des Emulator-Scripts, unabhängig von der DeSmuME-API (die steckt im Emu-Adapter).
-- main.lua erzeugt den Adapter und ruft frame()/draw() aus den Emulator-Rückrufen auf.

local json = require("lib.json")
local Profiles = require("profiles")
local Guard = require("mem.guard")
local Reader = require("mem.reader")
local Detect = require("mem.detect")
local P = require("mem.pkm")
local Transport = require("net.transport_file")
local Client = require("net.client")
local Launcher = require("net.launcher")
local R = require("core.rules")
local Enforce = require("app.enforce")
local Overlay = require("app.overlay")
local Backup = require("app.backup")
local Inputs = require("app.inputs")
local Automation = require("app.automation")
local LocalHub = require("net.local_hub")
local Rando = require("rando")

local App = {}
App.__index = App

App.TICK_FRAMES = 10        -- Prüfzyklus alle 10 Frames (6x pro Sekunde)
App.BOX_EVERY_TICKS = 30    -- Boxen seltener lesen (teuer)
App.MESSAGE_MS = 8000

--- Selbsttest der Schreibfunktionen (Voraussetzung für jedes Schreiben, siehe Phase 3).
function App.selftest()
  local ok = pcall(function()
    for _, gen in ipairs({ 4, 5 }) do
      local b = {}
      for i = 1, P.PARTY_SIZE[gen] do b[i] = (i * 37) % 256 end
      P.set_u32(b, 0, 2882400001)
      P.set_u16(b, 0x90, 50)
      P.set_u16(b, 0x06, P.checksum(b))
      local raw = P.encrypt(P.set_hp(b, 0))
      local back = P.parse(P.decrypt(raw), gen)
      assert(back.valid and back.hp == 0 and back.max_hp == 50)
    end
  end)
  return ok
end

--- opts: config, emu, fs, root, now (ms), launch (Funktion oder nil), date
function App.new(opts)
  local self = setmetatable({}, App)
  local cfg = opts.config
  self.cfg = cfg
  self.emu = opts.emu
  self.fs = opts.fs
  self.now = opts.now
  self.messages = {}
  self.warnings = {}
  self.show = { overlay = true, graveyard = false, areas = false }
  self.prev_keys = {}
  self.tick_no = 0
  self.absence = nil
  self.override_until = 0

  -- Spiel erkennen
  self.game_code = self.emu.game_code()
  self.profile, self.profile_msg = Profiles.load(self.game_code)
  self.read_only = self.profile == nil

  -- Schreibschutz
  self.guard = Guard.new({
    profile = self.profile, emu = self.emu, enabled = cfg.write_enabled == true,
    resolve = self.emu.resolve, log = function(m) self:note(m, "warn") end,
  })
  self.guard:set_selftest(App.selftest())
  if not self.guard.selftest_ok then self.warnings[#self.warnings + 1] = "Selbsttest der Schreibfunktionen fehlgeschlagen" end

  if self.profile then
    self.reader = Reader.new({ profile = self.profile, emu = self.emu, guard = self.guard })
  end
  self.detect = Detect.new()

  -- Netz: Server über die Brücke, oder Solo-Modus mit lokalem Vermittler (ohne Server)
  local root = opts.root
  local local_dir = root .. "/local"
  self.solo = cfg.mode == "solo"
  local lobby = cfg.lobby_code
  if self.solo then
    local solo = cfg.solo or {}
    self.transport = LocalHub.new({
      fs = self.fs, dir = local_dir, name = cfg.player_name, now = self.now,
      settings = cfg.lobby_settings, auto_start = solo.auto_start,
    })
    lobby = "SOLO"
  else
    local dir = cfg.bridge and cfg.bridge.exchange_dir or (root .. "/bridge/exchange")
    local session = string.format("%012.0f", self.now())
    self.transport = Transport.new({ dir = dir, fs = self.fs, session = session, nonce = session .. cfg.player_name })
    if cfg.bridge and cfg.bridge.autostart and opts.launch then
      opts.launch({ node = cfg.bridge.node, root = root, url = cfg.server_url, dir = dir })
    end
  end
  self.client = Client.new({
    transport = self.transport, name = cfg.player_name, lobby = lobby, now = self.now, fs = self.fs,
    queue_path = local_dir .. (self.solo and "/warteschlange_solo.json" or "/warteschlange.json"),
    stats_path = local_dir .. "/todeszaehler.json",
  })

  -- Automatiken (Phase 4): Prolog überspringen, Spitznamen-Abfrage ablehnen, Eingabe-Aufnahme
  self.local_dir = local_dir
  self.inputs = Inputs.new()
  self.recorder = nil
  self.auto = Automation.new({
    profile = self.profile, inputs = self.inputs,
    read = function(name)
      if not self.reader or not self.reader:entry(name) then return nil end
      local ok, v = pcall(self.reader.read, self.reader, name, 16)
      return ok and v or nil
    end,
    note = function(text, level) self:note(text, level) end,
    set_speed = function(mode) return self.emu.set_speed and self.emu.set_speed(mode) end,
    write_name = function(name) return self:write_trainer_name(name) end,
  })

  -- Randomizer (Phase 5)
  if self.profile then
    self.rando = Rando.new({
      profile = self.profile, emu = self.emu, guard = self.guard, reader = self.reader, fs = self.fs,
      local_dir = local_dir, rom_path = cfg.rom_path, rom = opts.rom,
      note = function(text, level) self:note(text, level) end,
      backup = function() self.backup:before_first_write(self.snap and self.snap.badges) end,
    })
  end

  -- Sicherungen
  local b = cfg.backups or {}
  self.backup = Backup.new({
    fs = self.fs, save_path = b.save_path, dir = b.dir or (root .. "/backups"), keep = b.keep or 20,
    interval_ms = (b.interval_min or 15) * 60000, date = opts.date,
  })
  if not self.backup:enabled() then
    self.warnings[#self.warnings + 1] = "Sicherungen aus: save_path in config.lua fehlt"
  end
  return self
end

--- Spielername aus config.lua in den Spielstand schreiben (nur über den Schreibschutz).
function App:write_trainer_name(name)
  if not self.reader or not self.reader:entry("trainer_name") then return false, "Adresse fehlt im Profil" end
  local ok, reason = self.guard:can_write("trainer_name")
  if not ok then return false, reason end
  local bytes, err = P.encode_gen4_name(name)
  if not bytes then return false, err end
  self.backup:before_first_write(0)
  return self.guard:write_bytes("trainer_name", 0, bytes)
end

--- Einstellung aus dem Run (Lobby), sonst Ersatzwert aus config.lua.
function App:setting(key)
  local state = self.client.state
  if state and state.settings and state.settings[key] ~= nil then return state.settings[key] end
  return (self.cfg.automation or {})[key] == true
end

function App:note(text, level)
  self.messages[#self.messages + 1] = { text = text, level = level or "info", t = self.now() }
  while #self.messages > 5 do table.remove(self.messages, 1) end
end

function App:pid()
  return self.client.player
end

function App:handle_effects()
  local pid = self:pid()
  for _, e in ipairs(self.client:take_effects()) do
    if e.type == "notify" then
      local mine = e.to == nil
      for _, q in ipairs(e.to or {}) do if q == pid then mine = true end end
      if mine then self:note(e.text, e.level) end
    elseif e.type == "absence_report" and e.player == pid then
      self.absence = e.deaths
    elseif e.type == "rollback" then
      self:note(e.text, "alarm")
    end
  end
  for _, err in ipairs(self.client.errors) do self:note(err, "warn") end
  self.client.errors = {}
end

function App:key_pressed(name)
  return name and self.keys[name] and not self.prev_keys[name]
end

function App:handle_keys()
  local hk = self.cfg.hotkeys or {}
  self.keys = self.emu.keys() or {}
  if self:key_pressed(hk.overlay) then self.show.overlay = not self.show.overlay end
  if self:key_pressed(hk.graveyard) then self.show.graveyard = not self.show.graveyard end
  if self:key_pressed(hk.areas) then self.show.areas = not self.show.areas end
  if self:key_pressed(hk.groups) then self.show.groups = not self.show.groups end
  if self:key_pressed(hk.record) then self:toggle_recording() end
  if self:key_pressed(hk.confirm) and self.absence then
    self.absence = nil
    self.client:send_event({ type = "ack_absence" })
  end
  local state = self.client.state
  if self:key_pressed(hk.start) and state then
    if state.phase == "lobby" then
      local ls = self.cfg.lobby_settings
      if ls and (ls.preset or ls.changes) then
        self.client:send_event({ type = "set_settings", preset = ls.preset, changes = ls.changes })
      end
      self.client:send_event({ type = "start_run" })
      self:note("Run-Start angefordert.")
    elseif state.phase == "finished" then
      self.client:send_event({ type = "new_attempt" })
      self:note("Neuer Versuch angefordert – zurück in die Lobby.")
    end
  end
  local prop = self:open_proposal()
  if prop and (self:key_pressed(hk.vote_yes) or self:key_pressed(hk.vote_no)) then
    self.client:send_event({ type = "vote", id = prop.id, accept = self:key_pressed(hk.vote_yes) and true or false })
  end
  if self:key_pressed(hk.pc_pass) then
    self.override_until = self.now() + 30000
    self:note("Sperre für 30 s ausgesetzt (Weg zum PC).", "warn")
  end
  self.prev_keys = self.keys
end

--- Eingabe-Aufnahme (für die Prolog-Eingabefolge im Profil) starten/beenden.
function App:toggle_recording()
  if not self.recorder then
    self.recorder = Inputs.recorder()
    self:note("Aufnahme läuft – Prolog jetzt von Hand durchspielen, danach Taste " .. tostring((self.cfg.hotkeys or {}).record) .. ".", "warn")
    return
  end
  local path = self.local_dir .. "/prolog_aufnahme_" .. tostring(self.game_code) .. ".lua"
  local src = "-- Aufnahme " .. os.date("%Y-%m-%d %H:%M") .. ": als prologue.inputs ins Profil übernehmen\nreturn "
    .. self.recorder:source() .. "\n"
  self.recorder = nil
  if self.fs.write_atomic(path, src) then
    self:note("Aufnahme gespeichert: " .. path)
  else
    self:note("Aufnahme konnte nicht gespeichert werden: " .. path, "warn")
  end
end

--- Älteste offene Abstimmung, bei der man selbst noch nicht zugestimmt hat.
function App:open_proposal()
  local state, pid = self.client.state, self:pid()
  if not state or not pid then return nil end
  local best
  for _, prop in pairs(state.proposals or {}) do
    if not prop.votes[pid] and (not best or prop.created_at < best.created_at) then best = prop end
  end
  return best
end

--- Ein Prüfzyklus: Netz, Spielzustand lesen, Ereignisse melden, Regeln durchsetzen.
function App:tick()
  self.tick_no = self.tick_no + 1
  self.client:poll()
  self:handle_effects()
  local state, pid = self.client.state, self:pid()

  local snap
  if self.reader then
    local ok, res = pcall(self.reader.snapshot, self.reader, self.now(), self.tick_no % App.BOX_EVERY_TICKS == 1)
    if ok then snap = res else self:note("Lesefehler: " .. tostring(res), "warn") end
  end
  self.snap = snap

  local dead = {}
  if state and pid and state.players[pid] then
    for _, uid in ipairs(R.dead_uids(state, pid)) do dead[uid] = true end
  end
  if snap and state and state.phase == "running" and pid then
    if not self.seeded then
      local known = {}
      for uid in pairs(state.players[pid] and state.players[pid].mons or {}) do known[#known + 1] = uid end
      self.detect:seed_known(known)
      self.seeded = true
    end
    local fp = self.rando and self.rando.fingerprint or ""
    local sent_status = false
    for _, ev in ipairs(self.detect:update(snap, dead)) do
      if ev.type == "status" then
        ev.rando_fp = fp
        sent_status = true
      end
      self.client:send_event(ev)
    end
    local me = state.players[pid]
    if not sent_status and me and fp ~= (me.rando_fp or "") and fp ~= self.sent_fp then
      self.sent_fp = fp
      self.client:send_event({ type = "status", rando_fp = fp })
    end
  end

  if self.rando and snap and state and state.phase == "running" then
    local ok, err = pcall(self.rando.tick, self.rando, state.settings, snap)
    if not ok then self:note("Randomizer-Fehler: " .. tostring(err), "warn") end
  end

  if snap and self.profile then
    self.auto:prologue_tick(self:setting("skip_prologue"), snap, self.cfg.player_name)
    self.auto:nickname_tick(self:setting("skip_nickname"))
  end

  self.plan = Enforce.plan(state, pid, snap, {
    absence_pending = self.absence ~= nil, override_until = self.override_until, now = self.now(),
  })
  local in_battle = snap and snap.battle ~= nil
  for _, uid in ipairs(self.plan.hp_zero) do
    if self.guard:can_write("party", in_battle) then
      self.backup:before_first_write(snap and snap.badges)
      self.reader:set_hp(uid, 0, in_battle)
    end
  end

  local name = self.backup:tick(self.now(), snap and snap.badges)
  if name then self:note("Sicherung angelegt: " .. name) end
end

function App:frame()
  self:handle_keys()
  if self.recorder and self.emu.get_joypad then self.recorder:frame(self.emu.get_joypad()) end
  if self.emu.frame() % App.TICK_FRAMES == 0 then self:tick() end
  -- Automatik-Eingaben haben Vorrang vor der Sperre (sie sind Teil der Regeldurchsetzung bzw. des Komforts).
  local auto_keys = self.inputs:next_frame()
  if auto_keys then
    self.emu.set_joypad(auto_keys)
  elseif self.plan and self.plan.lock then
    self.emu.set_joypad(Enforce.joypad_mask(self.plan, self.snap and self.snap.in_menu) or {})
  end
end

local COLORS = { weiss = "white", gelb = "yellow", rot = "red", gruen = "green", grau = "gray", schwarz = "black" }
local BG = { gelb = "#FFD84AE0", rot = "#FF6060E0" }

function App:profile_info()
  if not self.profile then return nil end
  local tested, total = Profiles.coverage(self.profile)
  local text = "Profil " .. self.profile.name .. ": " .. tested .. "/" .. total .. " Adressen getestet"
  if not (self.guard.enabled and tested > 0) then text = text .. " – nur lesen" end
  if self.reader and not self.reader.party_addr then
    text = text .. (self.reader.scan and " – suche Team im Speicher" or " – Team nicht gefunden")
  end
  return text
end

--- Overlay-Zeilen für den aktuellen Zustand (auch für Tests).
function App:lines()
  local state, pid = self.client.state, self:pid()
  local now = self.now()
  local msgs = {}
  for _, m in ipairs(self.messages) do
    if now - m.t < App.MESSAGE_MS then msgs[#msgs + 1] = m end
  end
  local cap
  if state and pid and self.profile and self.profile.gym_levels then
    cap = R.level_cap(state, pid, self.profile.gym_levels)
    if cap and self.profile.gym_levels.tested ~= true then cap = cap .. " (ungeprüft)" end
  end
  local lines = Overlay.lines({
    state = state, pid = pid, net_status = self.client:status_text(), online = self.client:online(),
    read_only = self.read_only, profile_msg = self.profile_msg, warnings = self.warnings,
    profile_info = self:profile_info(),
    stats = self.client.stats, lock_reasons = self.plan and self.plan.lock and self.plan.reasons or nil,
    messages = msgs, level_cap = cap, compact = self.cfg.overlay and self.cfg.overlay.compact,
    area_key = self.snap and self.snap.area and self.snap.area.key or (state and pid and state.players[pid]
      and state.players[pid].area.key),
    now_server = self.client:server_now(), extra = self:extra_lines(),
  })
  local hk = self.cfg.hotkeys or {}
  if state and state.phase == "lobby" then
    lines[#lines + 1] = { text = "Taste " .. tostring(hk.start) .. ": Run starten (Einstellungen aus config.lua)", color = "gelb" }
  elseif state and state.phase == "finished" then
    lines[#lines + 1] = { text = "Taste " .. tostring(hk.start) .. ": neuer Versuch", color = "gelb" }
  end
  local prop = self:open_proposal()
  if prop then
    local names = { settings = "Einstellungen ändern", reset_counters = "Todeszähler zurücksetzen", abandon = "Run aufgeben" }
    lines[#lines + 1] = { text = "Abstimmung: " .. (names[prop.kind] or prop.kind) .. " – " .. tostring(hk.vote_yes)
      .. " = ja, " .. tostring(hk.vote_no) .. " = nein", color = "gelb" }
  end
  if self.absence then
    lines[#lines + 1] = { text = "In deiner Abwesenheit gestorben:", color = "rot" }
    for _, d in ipairs(self.absence) do
      lines[#lines + 1] = { text = "  " .. d.label .. (d.by ~= "" and (" – mitgerissen von " .. d.by) or ""), color = "rot" }
    end
    lines[#lines + 1] = { text = "Bestätigen mit Taste " .. tostring((self.cfg.hotkeys or {}).confirm), color = "gelb" }
  end
  if self.show.groups and state then
    for _, l in ipairs(Overlay.groups(state, pid)) do lines[#lines + 1] = l end
  end
  if self.show.graveyard and state then
    for _, l in ipairs(Overlay.graveyard(state, pid)) do lines[#lines + 1] = l end
  end
  if self.show.areas and state then
    for _, l in ipairs(Overlay.areas(state, pid)) do lines[#lines + 1] = l end
  end
  return lines
end

function App:extra_lines()
  local out = {}
  local s = self.auto:status_line()
  if s then out[#out + 1] = { text = s, color = "gelb" } end
  local r = self.rando and self.rando:status_line()
  if r then out[#out + 1] = { text = r, color = self.rando.status == "aktiv" and "gruen" or "gelb" } end
  if self.recorder then
    out[#out + 1] = { text = "AUFNAHME läuft (Taste " .. tostring((self.cfg.hotkeys or {}).record) .. " beendet)", color = "rot" }
  end
  return out
end

function App:draw()
  if not self.show.overlay then return end
  local o = self.cfg.overlay or {}
  local x, y = o.x or 2, o.y or 2
  for i, l in ipairs(self:lines()) do
    local ly = y + (i - 1) * 9
    if l.bg and BG[l.bg] then self.emu.box(x - 1, ly - 1, x + 252, ly + 8, BG[l.bg], BG[l.bg]) end
    self.emu.text(x, ly, l.text, COLORS[l.color] or "white")
  end
end

App.json = json
return App
