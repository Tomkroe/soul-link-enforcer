-- Overlay-Inhalt als Textzeilen. Rein (keine Emulator-API); app/init.lua zeichnet die Zeilen.

local R = require("core.rules")
local M = require("core.model")

local Overlay = {}

local function num(n) return string.format("%.0f", n or 0) end

--- Rückgabe: Liste von { text, color } (color: "weiss", "gelb", "rot", "gruen", "grau").
function Overlay.lines(ctx)
  local out = {}
  local function add(text, color) out[#out + 1] = { text = text, color = color or "weiss" } end
  local state, pid = ctx.state, ctx.pid

  add("Soul Link – " .. (ctx.net_status or "?"), ctx.online and "gruen" or "gelb")
  if ctx.read_only then add("LESEMODUS: " .. (ctx.profile_msg or "kein Profil"), "gelb") end
  if ctx.profile_info then add(ctx.profile_info, "grau") end
  for _, w in ipairs(ctx.warnings or {}) do add("! " .. w, "rot") end

  if not state then return out end
  if state.phase == "lobby" then
    add("Lobby " .. state.code .. ": " .. num(#state.order) .. " Spieler – warte auf Run-Start", "grau")
    return out
  end
  if state.phase == "finished" then
    add("Run beendet: " .. state.result, state.result == "gewonnen" and "gruen" or "rot")
  end

  local me = state.players[pid]
  if not me then return out end
  local catchup, off = R.catchup_active(state, pid)
  if catchup then
    local names = {}
    for _, q in ipairs(off) do names[#names + 1] = M.player_name(state, q) end
    add("AUFHOL-MODUS (offline: " .. table.concat(names, ", ") .. ")", "gelb")
    local ok, reason = R.gym_allowed(state, pid)
    if not ok then add(reason, "gelb") end
  end
  if ctx.level_cap then add("Level-Cap: " .. (type(ctx.level_cap) == "number" and num(ctx.level_cap) or ctx.level_cap), "weiss") end

  if ctx.compact then return out end

  -- Mitspieler
  for _, q in ipairs(M.teammates(state, pid)) do
    local p = state.players[q]
    add(string.format("%s: %s, %s Orden%s%s", p.name, p.area.name or "?", num(p.badges),
      p.in_battle and ", im Kampf" or "", p.online and "" or " – OFFLINE"), p.online and "weiss" or "grau")
  end

  -- Gruppen
  local team = M.team_of(state, pid)
  if team then
    local alive, dead = 0, 0
    for _, gid in ipairs(team.group_order) do
      if team.groups[gid].status == "tot" then dead = dead + 1 else alive = alive + 1 end
    end
    add("Gruppen: " .. num(alive) .. " lebend, " .. num(dead) .. " tot", "weiss")
    -- Todeszähler aller Spieler (dauerhaft, vom Server)
    local parts = {}
    for _, q in ipairs(state.order) do
      local s = ctx.stats and ctx.stats[q]
      parts[#parts + 1] = M.player_name(state, q) .. " " .. num(s and s.deaths or 0)
        .. (s and s.dragged and s.dragged > 0 and ("+" .. num(s.dragged)) or "")
    end
    add("Tode: " .. table.concat(parts, "  "), "weiss")
  end

  for _, r in ipairs(ctx.lock_reasons or {}) do add(r, "rot") end
  for _, m in ipairs(ctx.messages or {}) do add(m.text, m.level == "alarm" and "rot" or (m.level == "warn" and "gelb" or "weiss")) end
  return out
end

--- Friedhof-Ansicht.
function Overlay.graveyard(state, pid)
  local out = {}
  local team = state and M.team_of(state, pid)
  if not team then return out end
  out[#out + 1] = { text = "Friedhof", color = "rot" }
  for i = #team.graveyard, math.max(1, #team.graveyard - 12), -1 do
    local d = team.graveyard[i]
    out[#out + 1] = { text = string.format("%s (%s) Lv.%s %s", d.label, M.player_name(state, d.player), num(d.level),
      d.area ~= "" and ("– " .. d.area) or ""), color = "grau" }
  end
  return out
end

--- Gebiets-Übersicht.
function Overlay.areas(state, pid)
  local out = { { text = "Gebiete", color = "weiss" } }
  if not state then return out end
  for _, row in ipairs(R.area_overview(state, pid)) do
    local parts = {}
    for _, ps in ipairs(row.players) do parts[#parts + 1] = M.player_name(state, ps.player) .. ": " .. ps.status end
    out[#out + 1] = { text = (row.current and "> " or "  ") .. row.name .. " – " .. table.concat(parts, ", "),
      color = row.current and "gelb" or "weiss" }
  end
  return out
end

return Overlay
