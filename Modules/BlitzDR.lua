-- Modules/BlitzDR.lua
-- Diminishing-returns tracking on the TARGET and FOCUS unit frames inside
-- battlegrounds (Blitz included). Arena has its own module; this one never
-- runs there.
--
-- DETECTION MODEL -- ported from the BlitzFramesTargets addon (Extras/DR.lua).
-- In a battleground the aura APIs are sealed: GetAuraDataByIndex throws
-- ("Auras cannot be accessed when secret") and GetUnitAuraBySpellID returns
-- nil, so a debuff can never be read directly. Three inputs remain:
--
--   UNIT_SPELLCAST_SUCCEEDED  arg3 spellID is PLAIN in a pvp instance, so a
--     table lookup on it works. Registered with RegisterUnitEvent(.., "player",
--     "pet") so the ENGINE filters to our own casts.
--   NormalizeUnitName(token)  the state key. Token-to-token on both the record
--     and the render side, so it never crosses a name-format boundary.
--   C_LossOfControl.GetActiveLossOfControlDataByUnit  counted, never read.
--
-- THE HARD LIMIT: loss-of-control is category-blind and source-blind. locType
-- is secret and there is no caster field, so "did MY cast land" is answered by
-- a COUNT DELTA across a short grace window:
--
--   count went up   = ours landed   (holds even on an already-CC'd target)
--   count unchanged = ours bounced  (already diminished / immune)
--
-- WHAT THIS CANNOT DO, by design:
--   * Only OUR casts are visible. A teammate's earlier CC halves ours unseen,
--     so read the output as "my DR contribution", not absolute truth.
--   * A cast into an immune target still SUCCEEDS, so with no live entry we
--     assume the full undiminished duration -- the worst case, which errs
--     toward holding a CC rather than throwing one into immunity.
--   * The CC's real end is unobservable (trinket, dispel, damage breaks), so
--     the modelled duration places the DR window. DR starts when the CC ENDS.

local ADDON, ns = ...
local Util = ns.Util
if not Util then return end

local Core = ns.Core
if not (Core and Core.NewModule) then return end

local BDR = Core:GetModule("BlitzDR", true) or Core:NewModule("BlitzDR", "AceEvent-3.0")
ns.BlitzDR = BDR

local IsForbidden       = Util.IsForbidden
local IsSecret          = Util.IsSecret
local NormalizeUnitName = Util.NormalizeUnitName
local clamp             = Util.Clamp

-- ─────────────────────────────────────────────────────────────────────────────
-- Constants
-- ─────────────────────────────────────────────────────────────────────────────

-- Escalating landed-checks. A single fixed wait forces a choice between fast
-- detection and false negatives; escalating gets both in at most 3 calls.
-- Apply latency measured 0-150ms, ~20ms typical.
local DR_CHECKS = { 0.05, 0.10, 0.15 }

local TRACKED        = ns.DR_TRACKED or {}
local CATEGORY_ORDER = ns.DR_CATEGORY_ORDER or { "stun", "disorient", "incap", "root" }
local MAX_ICONS      = 4
local BRIDGES        = { "target", "focus" }

-- Ladder rungs mapped onto the two-stage display used elsewhere in the addon.
-- rung 0 = full duration applied (the next one is halved), rung 1 = halved
-- applied (the next is immune), rung 2 = immune.
local RUNG_COLOR = { [0] = { 0, 1, 0 }, [1] = { 1, 0, 0 }, [2] = { 1, 0, 0 } }
local RUNG_TEXT  = { [0] = "1/2", [1] = "2/2", [2] = "2/2" }

-- ─────────────────────────────────────────────────────────────────────────────
-- Settings
-- ─────────────────────────────────────────────────────────────────────────────

local function DB()
  return (Core and Core.arenaDB and Core.arenaDB.profile and Core.arenaDB.profile.arena) or nil
end

local function Cfg()
  local a = DB()
  return (a and a.blitz_dr) or {}
end

-- Shared with the arena module so one slider governs both venues.
local function ResetWindow()
  local a = DB()
  local t = a and tonumber(a.dr_reset_time)
  if t and t >= 15 and t <= 20 then return t end
  return 20
end

-- Per-bridge value with a shared fallback, matching the arena module's shape.
local function BridgeValue(bridge, key, fallback)
  local cfg = Cfg()
  local b = type(cfg[bridge]) == "table" and cfg[bridge] or {}
  local v = b[key]
  if v ~= nil then return v end
  v = cfg[key]
  if v ~= nil then return v end
  return fallback
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Venue
-- ─────────────────────────────────────────────────────────────────────────────

-- Battlegrounds only. arena1-5 tokens exist in battlegrounds too, so the
-- discriminator has to be IsActiveBattlefieldArena rather than a unit token.
local function InBattleground()
  local ok, _, instanceType = pcall(GetInstanceInfo)
  if not ok then return false end
  if instanceType ~= "pvp" then return false end
  local okA, isArena = pcall(IsActiveBattlefieldArena)
  if okA and isArena then return false end
  return true
end

local function DetectionActive()
  local cfg = Cfg()
  if cfg.enabled == false then return false end
  if cfg.test_enabled then return false end
  return InBattleground()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────────────────────
-- Keyed by name rather than by frame: DR must outlive visibility. Someone gets
-- stunned and walks out of range, and the window keeps running with nothing
-- pointing at them.
local drState = {}   -- [fullName] = { [category] = entry }

-- Expire LAZILY on read, never on a ticker: costs nothing while nobody looks.
local function GetDR(fullName, category)
  local byName = fullName and drState[fullName]
  local e = byName and byName[category]
  if not e then return nil end
  if GetTime() >= e.expiresAt then byName[category] = nil; return nil end
  return e
end

local function WipeDR()
  for k in pairs(drState) do drState[k] = nil end
end

local function IconFor(spellID, cat)
  local catIcon = cat and ns.DR_CATEGORY_ICON and ns.DR_CATEGORY_ICON[cat]
  if catIcon then return catIcon end
  local info = ns.CC_SPELL_DATA and ns.CC_SPELL_DATA[spellID]
  local icon = info and info.icon
  -- 0 is truthy in Lua and draws a blank, so it must be rejected explicitly.
  if icon and icon ~= 0 then return icon end
  local tex = spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
  if tex and tex ~= 0 then return tex end
  return nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Loss-of-control counting
-- ─────────────────────────────────────────────────────────────────────────────
-- No field is ever read; the COUNT is the entire signal. A secret return counts
-- as present, since nil is never secret.
local function LoCCount(unit)
  if not (unit and C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataByUnit) then
    return 0
  end
  local countFn = C_LossOfControl.GetActiveLossOfControlDataCountByUnit
  if countFn then
    local ok, c = pcall(countFn, unit)
    if ok and type(c) == "number" and not IsSecret(c) then return c end
  end
  local n = 0
  for i = 1, 8 do
    local ok, data = pcall(C_LossOfControl.GetActiveLossOfControlDataByUnit, unit, i)
    if not ok then break end
    if data == nil then break end   -- secret or table: both count as present
    n = n + 1
  end
  return n
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Ladder
-- ─────────────────────────────────────────────────────────────────────────────

local function Landed(fullName, info, spellID)
  local cat    = info.category
  local byName = drState[fullName]
  if not byName then byName = {}; drState[fullName] = byName end

  local prev = GetDR(fullName, cat)
  -- full -> half -> immune. A third application lands nothing, so it must NOT
  -- refresh the window; otherwise spamming CC into an immune target would
  -- extend the DR forever.
  if prev and prev.rung >= 1 then
    prev.rung = 2
    return
  end

  local rung = prev and 1 or 0
  local base = info.baseDuration or 4
  local dur  = (rung == 0) and base or (base / 2)
  local now  = GetTime()
  byName[cat] = {
    rung       = rung,
    spellID    = spellID,
    icon       = IconFor(spellID, cat),
    name       = info.name,
    category   = cat,
    appearedAt = now,
    assumedDur = dur,
    expiresAt  = now + dur + ResetWindow(),   -- DR starts when the CC ENDS
  }
end

local function Immune(fullName, info, spellID)
  local cat    = info.category
  local byName = drState[fullName]
  if not byName then byName = {}; drState[fullName] = byName end

  local prev = GetDR(fullName, cat)
  if prev then
    -- A live entry at FULL whose count did not move: either it bounced (they
    -- were further along than we knew) or it broke the previous CC and landed
    -- as the second application. Both mean the next one is immune, so rung 1
    -- is right under either reading. The window takes the later of the two.
    if prev.rung == 0 then
      prev.rung = 1
      local now       = GetTime()
      local half      = (info.baseDuration or 4) / 2
      local restarted = now + half + ResetWindow()
      if restarted > prev.expiresAt then
        -- A RESTART, not an extension: move the start too. Only moving the
        -- end left the swipe ring half-spent, so the timer looked as if the
        -- restun had not reset it.
        prev.expiresAt  = restarted
        prev.appearedAt = now
        prev.assumedDur = half
      end
    end
    return
  end

  -- WORST CASE, and intentional: nothing landed, so they were already
  -- diminished by someone we never saw. Assume the highest rung and the
  -- longest window. Over-estimating costs a held CC; under-estimating throws
  -- one into immunity.
  local now  = GetTime()
  local base = info.baseDuration or 4
  byName[cat] = {
    rung       = 2,
    spellID    = spellID,
    icon       = IconFor(spellID, cat),
    name       = info.name,
    category   = cat,
    appearedAt = now,
    assumed    = true,
    assumedDur = base,
    expiresAt  = now + base + ResetWindow(),
  }
end

-- `cands` is an ordered list of { name, unit, before, primary }: the primary
-- victim first, then focus when it is a different player. The FIRST candidate
-- whose count rose is the inferred victim. None rising by the last check
-- assumes the original primary as immune.
local function CheckLanded(cands, info, spellID, attempt)
  if not DetectionActive() then return end
  local multiTarget = info.aoe and not info.targetOnly

  for i = 1, #cands do
    local c = cands[i]
    if not c.landed then
      -- Tokens can change occupant during the grace window; never use a new
      -- target/focus as evidence for this name.
      local unit = c.unit
      if unit and NormalizeUnitName(unit) == c.name and LoCCount(unit) > c.before then
        c.landed = true
        Landed(c.name, info, spellID)
        if not multiTarget then return end
      end
    end
  end

  local nextAt = DR_CHECKS[attempt + 1]
  if nextAt then
    local pending = false
    for i = 1, #cands do if not cands[i].landed then pending = true; break end end
    if pending then
      C_Timer.After(nextAt - DR_CHECKS[attempt], function()
        CheckLanded(cands, info, spellID, attempt + 1)
      end)
    end
    return
  end

  -- Single-victim fallback: only the primary captured at cast time is updated,
  -- never an existing focus ladder as well.
  if not multiTarget then
    if cands[1] and cands[1].primary then Immune(cands[1].name, info, spellID) end
    return
  end
  -- AoE fallback: the unlanded primary files as immune (worst case). A
  -- secondary with NO entry gets nothing -- filing it immune would invent a
  -- ladder on a player we may never have cast at.
  if cands[1] and not cands[1].landed then Immune(cands[1].name, info, spellID) end
  for i = 2, #cands do
    if not cands[i].landed and GetDR(cands[i].name, info.category) then
      Immune(cands[i].name, info, spellID)
    end
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Spell resolution (talent variants, aliases, variable durations)
-- ─────────────────────────────────────────────────────────────────────────────

local variantCategory = {}   -- [spellID] = category while the talent is selected
local aliasGateOff    = {}   -- [castID] = true when a gated alias is NOT selected
local nameToRow              -- lazily built name -> row id index
local castAliases     = {}   -- harvested [castID] = rowID

local function SelectedTalentSpellNames(configID)
  local names = {}
  if not (configID and C_Traits) then return names end
  local ok, info = pcall(C_Traits.GetConfigInfo, configID)
  if not ok or not info then return names end
  for _, treeID in ipairs(info.treeIDs or {}) do
    local okN, nodes = pcall(C_Traits.GetTreeNodes, treeID)
    if okN and nodes then
      for _, nodeID in ipairs(nodes) do
        local okI, node = pcall(C_Traits.GetNodeInfo, configID, nodeID)
        local ae = okI and node and node.activeEntry
        if ae and (ae.rank or 0) > 0 then
          local okE, e = pcall(C_Traits.GetEntryInfo, configID, ae.entryID)
          local d = okE and e and e.definitionID and C_Traits.GetDefinitionInfo(e.definitionID)
          local nm = d and d.spellID and C_Spell.GetSpellName(d.spellID)
          if nm then names[nm] = true end
        end
      end
    end
  end
  return names
end

local function EntrySelected(configID, nodeID, entryID)
  if not (configID and nodeID and entryID) then return false end
  local ok, node = pcall(C_Traits.GetNodeInfo, configID, nodeID)
  local ae = ok and node and node.activeEntry
  return (ae and ae.entryID == entryID and (ae.rank or 0) > 0) and true or false
end

local function RefreshTalentVariants()
  local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
  local selectedNames = SelectedTalentSpellNames(configID)

  for spellID, v in pairs(ns.CC_TALENT_VARIANTS or {}) do
    -- NAME FIRST, ids as the fallback: a trait tree is renumbered on every
    -- rework, after which a nodeID gate fails silently and the variant simply
    -- stops applying. Asking "is a selected entry called X" survives that, and
    -- compares game-name to game-name so it holds on any locale.
    local gateSpell = v.talentSpell or v.spellID
    local named = gateSpell and selectedNames[C_Spell.GetSpellName(gateSpell) or ""]
    local on = named or EntrySelected(configID, v.nodeID, v.entryID)
    variantCategory[spellID] = on and v.category or nil
  end

  wipe(aliasGateOff)
  for castID, a in pairs(ns.CC_CAST_ALIASES or {}) do
    if type(a) == "table" then
      if a.talentSpell then
        local tn = C_Spell.GetSpellName(a.talentSpell)
        aliasGateOff[castID] = not (tn and selectedNames[tn])
      elseif a.talentByName then
        local rowName = a.row and C_Spell.GetSpellName(a.row)
        aliasGateOff[castID] = not (rowName and selectedNames[rowName])
      elseif a.nodeID and a.entryID then
        aliasGateOff[castID] = not EntrySelected(configID, a.nodeID, a.entryID)
      end
    end
  end
end

local function BuildNameIndex()
  nameToRow = {}
  if not (ns.CC_SPELL_DATA and C_Spell and C_Spell.GetSpellName) then return end
  for id, info in pairs(ns.CC_SPELL_DATA) do
    if TRACKED[info.category] then
      local nm = C_Spell.GetSpellName(id)
      -- First row wins; same-named rows share a bracket in practice.
      if nm and not nameToRow[nm] then nameToRow[nm] = id end
    end
  end
end

-- Rows keyed by the debuff a spell applies rather than the button pressed are
-- resolved by NAME -- the game's name on both sides, so it works on any locale
-- -- and the pair is remembered for the session.
local function HarvestCastAlias(spellID)
  if not nameToRow then BuildNameIndex() end
  local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
  local rowID = nm and nameToRow[nm]
  if not rowID then return nil end
  castAliases[spellID] = rowID
  return rowID
end

-- Rake stuns ONLY from stealth; tracked unconditionally it would credit a stun
-- for every Rake. Cheap Shot needs no entry: it cannot be cast unstealthed.
local STEALTH_ONLY = { [1822] = true, [163505] = true }

local function EffectiveInfo(spellID)
  local alias = ns.CC_CAST_ALIASES and ns.CC_CAST_ALIASES[spellID]
  local over
  if type(alias) == "table" then
    -- A gated alias whose talent is not selected is not an alias at all; bail
    -- rather than fall through to the harvester, which would resolve the cast
    -- by name onto the row and track someone who never took the talent.
    if aliasGateOff[spellID] then return nil end
    over = alias; alias = alias.row
  end

  local rowID = alias or castAliases[spellID] or spellID
  if not (ns.CC_SPELL_DATA and ns.CC_SPELL_DATA[rowID]) then
    rowID = HarvestCastAlias(spellID) or rowID
  end
  local info = ns.CC_SPELL_DATA and ns.CC_SPELL_DATA[rowID]
  if not info then return nil end

  local cat = variantCategory[spellID] or variantCategory[rowID]
  if (not cat or cat == info.category) and not over then return info end

  local out = {}
  for k, v in pairs(info) do out[k] = v end
  if cat then
    out.category = cat
    -- The bracket changed, so bracket-bound flags must not carry over: stuns
    -- never break on damage.
    if cat == "stun" then out.breakable = nil end
  end
  if over then
    if over.baseDuration then out.baseDuration = over.baseDuration end
    if over.aoe ~= nil then out.aoe = over.aoe end
    if over.aoeRadius then out.aoeRadius = over.aoeRadius end
  end
  return out
end

-- VARIABLE DURATIONS (Kidney Shot, Maim). The combo points are OURS, so they
-- are plain. UNIT_SPELLCAST_SUCCEEDED can fire after the spend, so the value
-- used is the last NON-ZERO reading: a finisher cannot succeed on zero points.
local lastComboPoints = 0

local function ComboPointsForCast()
  local ok, cp = pcall(UnitPower, "player", Enum.PowerType.ComboPoints)
  if ok and type(cp) == "number" and cp > 0 then return cp end
  return lastComboPoints > 0 and lastComboPoints or 5
end

local function VariableDuration(info)
  local okM, maxCP = pcall(UnitPowerMax, "player", Enum.PowerType.ComboPoints)
  if not okM or type(maxCP) ~= "number" or maxCP < 1 then maxCP = 5 end
  local cp = math.max(1, math.min(ComboPointsForCast(), maxCP))
  -- The row's baseDuration is the FULL duration; scale by points spent.
  return info.baseDuration * cp / 5
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Rendering
-- ─────────────────────────────────────────────────────────────────────────────

-- One row per (bridge, kind): kind "frame" sits on the Target/Focus unit
-- frame, kind "plate" on that unit's nameplate. Both read the SAME DR state,
-- so with "Show on Both" the two rows always agree.
local widgets = {}   -- [bridge .. ":" .. kind] = frame with .icons
local KINDS = { "frame", "plate" }

local function WidgetKey(bridge, kind) return bridge .. ":" .. kind end

-- Where rows are drawn. "Show on Both" overrides the anchor toggle.
local function KindEnabled(kind)
  local cfg = Cfg()
  if kind == "plate" then
    return cfg.anchor_nameplate == true or cfg.np_both == true
  end
  return cfg.anchor_nameplate ~= true or cfg.np_both == true
end

-- The frame a row anchors to, or nil when there is nothing to sit on (no
-- plate on screen, forbidden frame).
local function RawAnchor(bridge, kind)
  if kind == "plate" then return Util.GetUnitNameplate(bridge) end
  local f = (bridge == "focus") and _G.FocusFrame or _G.TargetFrame
  if not f or IsForbidden(f) then return nil end
  return f
end

-- As RawAnchor, but the focus row yields when it would sit on the TARGET's
-- anchor: on nameplates, target and focus on the same player resolve to one
-- plate, and two identical rows would stack on top of each other.
local function AnchorFor(bridge, kind)
  local f = RawAnchor(bridge, kind)
  if f and bridge == "focus" and f == RawAnchor("target", kind) then return nil end
  return f
end

local function BorderOpts()
  local cfg = Cfg()
  return {
    style       = cfg.border_style or "GLOW",
    black       = cfg.border_black == true,
    border_size = tonumber(cfg.border_size) or 1,
    pixel_size  = tonumber(cfg.pixel_border_size) or 2,
  }
end

local function ResyncBorders()
  local opts = BorderOpts()
  for _, w in pairs(widgets) do
    for _, f in ipairs(w.icons) do f.drBorder:Configure(opts) end
  end
end

local function FontPath()
  if STANDARD_TEXT_FONT then return STANDARD_TEXT_FONT end
  return GameFontNormal and GameFontNormal:GetFont() or nil
end

local function SetDragEnabled(w, enabled)
  if not w or w._dragEnabled == enabled then return end
  w._dragEnabled = enabled
  for _, f in ipairs(w.icons) do f:EnableMouse(enabled) end
end

local function EnsureWidget(bridge, kind)
  local key = WidgetKey(bridge, kind)
  local w = widgets[key]
  if w and IsForbidden(w) then w = nil end
  if w then return w end

  w = CreateFrame("Frame", nil, UIParent)
  -- Plate rows go behind unit/party frames; frame rows stay on top.
  local strata = (kind == "plate") and Util.PLATE_STRATA or Util.FRAME_STRATA
  w:SetFrameStrata(strata)
  w:SetFrameLevel(1000)
  w:SetSize(1, 1)
  -- Only frame rows are draggable: a plate row is anchored to a nameplate,
  -- which makes it a restricted frame that Blizzard refuses to move.
  if kind ~= "plate" then
    w:SetMovable(true)
    w:SetClampedToScreen(true)
  end
  -- Icons start with the mouse off; tracking that makes turning it off
  -- again a no-op that never touches a (possibly restricted) plate row.
  w._dragEnabled = false
  w:Hide()
  w.icons = {}
  w.bridge = bridge
  w.kind = kind

  for i = 1, MAX_ICONS do
    local f = CreateFrame("Frame", nil, w)
    f:SetSize(26, 26)
    f:SetFrameStrata(strata)
    f:SetFrameLevel(w:GetFrameLevel() + 1)
    f:EnableMouse(false)

    f.texture = f:CreateTexture(nil, "ARTWORK")
    f.texture:SetAllPoints()
    f.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown:SetAllPoints()
    f.cooldown:SetDrawEdge(false)
    f.cooldown:SetDrawSwipe(true)
    f.cooldown:SetReverse(true)
    f.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    f.cooldown:SetHideCountdownNumbers(true)
    f.cooldown:SetFrameLevel(f:GetFrameLevel() + 1)

    f.textHolder = CreateFrame("Frame", nil, f)
    f.textHolder:SetAllPoints()
    f.textHolder:SetFrameStrata(f:GetFrameStrata())
    f.textHolder:SetFrameLevel(f:GetFrameLevel() + 10)

    f.text = f.textHolder:CreateFontString(nil, "OVERLAY")
    f.text:SetDrawLayer("OVERLAY", 7)
    f.text:SetPoint("CENTER", f.textHolder, "CENTER", 0, 0)
    f.text:SetJustifyH("CENTER")

    f.drText = f.textHolder:CreateFontString(nil, "OVERLAY")
    f.drText:SetDrawLayer("OVERLAY", 7)
    f.drText:SetPoint("BOTTOMRIGHT", f.textHolder, "BOTTOMRIGHT", 4, -4)
    f.drText:SetJustifyH("RIGHT")
    f.drText:SetJustifyV("BOTTOM")

    f.borderFrame = CreateFrame("Frame", nil, f)
    f.borderFrame:SetAllPoints()
    f.borderFrame:SetFrameStrata(f:GetFrameStrata())
    f.borderFrame:SetFrameLevel(f:GetFrameLevel() + 5)
    f.drBorder = Util.CreateDRBorder(f.borderFrame)

    -- Test-mode drag: dragging any icon moves the whole row.
    if kind ~= "plate" then
      f:RegisterForDrag("LeftButton")
      f:SetScript("OnDragStart", function()
        w._dragging = true
        w:StartMoving()
      end)
      f:SetScript("OnDragStop", function()
        w:StopMovingOrSizing()
        w._dragging = false
        BDR:SaveDragPosition(w)
      end)
    end

    f:Hide()
    w.icons[i] = f
  end

  widgets[key] = w
  ResyncBorders()
  return w
end

-- Converts a dragged row's position back into the offsets the sliders use.
-- Frame rows write that bridge's frame offsets; plate rows write the shared
-- nameplate offsets.
function BDR:SaveDragPosition(w)
  if not w then return end
  local bridge = w.bridge
  local anchor = AnchorFor(bridge, w.kind)
  if not anchor then return end
  local wx, wy = w:GetCenter()
  local ax, ay = anchor:GetCenter()
  if not (wx and wy and ax and ay) then return end
  local ws, as = w:GetEffectiveScale(), anchor:GetEffectiveScale()

  local a = DB()
  if not a then return end
  a.blitz_dr = a.blitz_dr or {}

  if w.kind == "plate" then
    -- Inverse of ApplyLayout for whichever nameplate grow mode is active.
    -- Shared by both rows: every plate is the same shape, so one position
    -- fits target and focus alike.
    local mode = w._npGrow or "CENTER"
    local half = (w._npSize or 26) / 2
    local gap  = w._npSpacing or 2
    local nx, ny
    if mode == "LTR" then
      local right = anchor:GetRight()
      if not right then return end
      nx = (wx * ws - right * as) / ws - gap - half
      ny = (wy * ws - ay * as) / ws
    elseif mode == "RTL" then
      local left = anchor:GetLeft()
      if not left then return end
      nx = (wx * ws - left * as) / ws + gap + half
      ny = (wy * ws - ay * as) / ws
    else
      local top = anchor:GetTop()
      if not top then return end
      nx = (wx * ws - ax * as) / ws - (w._npShift or 0)
      ny = (wy * ws - top * as) / ws - half
    end
    a.blitz_dr.np_pos_x = clamp(math.floor(nx + 0.5), -300, 300)
    a.blitz_dr.np_pos_y = clamp(math.floor(ny + 0.5), -200, 200)
  else
    a.blitz_dr[bridge] = a.blitz_dr[bridge] or {}
    a.blitz_dr[bridge].pos_x = clamp(math.floor((wx * ws - ax * as) / ws + 0.5), -600, 600)
    a.blitz_dr[bridge].pos_y = clamp(math.floor((wy * ws - ay * as) / ws + 0.5), -400, 400)
  end
  Core:NotifyOptionsChanged()
end

local function ApplyLayout(w, anchor, count)
  local bridge  = w.bridge
  local size    = clamp(tonumber(BridgeValue(bridge, "icon_size", 26)) or 26, 12, 80)
  local spacing = clamp(tonumber(BridgeValue(bridge, "spacing", 2)) or 2, 0, 20)
  local px      = tonumber(BridgeValue(bridge, "pos_x", 0)) or 0
  local py      = tonumber(BridgeValue(bridge, "pos_y", 40)) or 40
  local grow    = BridgeValue(bridge, "grow", "RIGHT")
  local font    = clamp(tonumber(BridgeValue(bridge, "font_size", 12)) or 12, 8, 48)

  w:ClearAllPoints()
  if w.kind == "plate" then
    local cfgNp  = Cfg()
    local nx     = tonumber(cfgNp.np_pos_x) or 0
    local ny     = tonumber(cfgNp.np_pos_y) or 10
    local npGrow = cfgNp.np_grow or "CENTER"
    w._npGrow, w._npSize, w._npSpacing = npGrow, size, spacing
    if npGrow == "LTR" then
      -- Beside the plate's RIGHT edge, growing right (away from the plate).
      -- Icon 1 is pinned next to the plate, so it never moves however many
      -- icons are showing. Vertically centred on the plate; offsets nudge.
      grow = "RIGHT"
      w._npShift = 0
      w:SetPoint("CENTER", anchor, "RIGHT", spacing + size / 2 + nx, ny)
    elseif npGrow == "RTL" then
      -- Mirror image: beside the plate's LEFT edge, growing left.
      grow = "LEFT"
      w._npShift = 0
      w:SetPoint("CENTER", anchor, "LEFT", -(spacing + size / 2) + nx, ny)
    else
      -- Centre the VISIBLE icons over the plate and rest the row's bottom
      -- edge np_pos_y above the plate's top.
      local step  = size + spacing
      local n     = math.max(1, count or 1)
      local shift = 0
      if grow == "RIGHT" then shift = -(n - 1) * step / 2
      elseif grow == "LEFT" then shift = (n - 1) * step / 2 end
      w._npShift = shift
      w:SetPoint("CENTER", anchor, "TOP", nx + shift, ny + size / 2)
    end
    -- Plates scale with distance; keep the icons at the configured size.
    w:SetScale(1)
  else
    w:SetPoint("CENTER", anchor, "CENTER", px, py)
    local us = (anchor.GetEffectiveScale and anchor:GetEffectiveScale()) or 1
    local ps = (UIParent and UIParent:GetEffectiveScale()) or 1
    w:SetScale(clamp(us / ps, 0.1, 10))
  end

  local cfg      = Cfg()
  local reverse  = cfg.reverse_swipe ~= false
  local swipe    = cfg.disable_swipe ~= true
  local fontPath = FontPath()

  for i, f in ipairs(w.icons) do
    f:SetSize(size, size)
    if fontPath then
      f.text:SetFont(fontPath, font, "OUTLINE")
      f.drText:SetFont(fontPath, font, "OUTLINE")
    end
    f.cooldown:SetReverse(reverse)
    f.cooldown:SetDrawSwipe(swipe)

    f:ClearAllPoints()
    local dx, dy = 0, 0
    if     grow == "LEFT" then dx = -(i - 1) * (size + spacing)
    elseif grow == "UP"   then dy =  (i - 1) * (size + spacing)
    elseif grow == "DOWN" then dy = -(i - 1) * (size + spacing)
    else                       dx =  (i - 1) * (size + spacing) end
    f:SetPoint("CENTER", w, "CENTER", dx, dy)
  end
end

local function FormatRemaining(rem, showDecimals, threshold)
  if type(rem) ~= "number" or rem <= 0 then return nil end
  if showDecimals and rem < threshold then
    if rem < 0.1 then rem = 0.1 end
    return string.format("%.1f", math.floor(rem * 10) / 10)
  end
  return tostring(math.floor(rem))
end

-- Draws `states` (a category -> entry map) onto one row.
local function RenderStates(bridge, kind, anchor, states)
  local w = EnsureWidget(bridge, kind)
  if not w then return end

  local visible, tnow = 0, GetTime()
  for _, cat in ipairs(CATEGORY_ORDER) do
    local e = states and states[cat]
    if e and e.expiresAt and e.expiresAt > tnow then visible = visible + 1 end
  end
  ApplyLayout(w, anchor, math.min(visible, MAX_ICONS))

  local cfg          = Cfg()
  local showDRText   = cfg.show_dr_text ~= false
  local colorCDText  = cfg.color_cd_text ~= false
  local showDecimals = cfg.show_decimals ~= false
  local threshold    = tonumber(cfg.decimal_threshold) or 3

  local now, shown = GetTime(), 0
  for _, cat in ipairs(CATEGORY_ORDER) do
    if shown >= MAX_ICONS then break end
    local e = states and states[cat]
    if e and e.expiresAt and e.expiresAt > now then
      shown = shown + 1
      local f = w.icons[shown]
      if f then
        local tex = e.icon or IconFor(e.spellID, cat)
        if tex then f.texture:SetTexture(tex) end

        -- The swipe spans the CC plus the DR window, which is exactly the
        -- entry's lifetime.
        local start = e.appearedAt or now
        local dur   = e.expiresAt - start
        if dur > 0 then f.cooldown:SetCooldown(start, dur) end

        f.text:SetText(FormatRemaining(e.expiresAt - now, showDecimals, threshold) or "")

        local rung = clamp(tonumber(e.rung) or 0, 0, 2)
        local c = RUNG_COLOR[rung]
        f.drBorder:SetStateColor(c[1], c[2], c[3])
        -- Immune reads differently from "diminished": desaturate the icon so
        -- it is obvious at a glance that another cast lands nothing.
        f.texture:SetDesaturated(rung >= 2)

        if showDRText then
          f.drText:SetText(RUNG_TEXT[rung])
          f.drText:SetTextColor(c[1], c[2], c[3], 1)
          f.drText:Show()
        else
          f.drText:Hide()
        end

        if colorCDText then
          f.text:SetTextColor(c[1], c[2], c[3], 1)
        else
          f.text:SetTextColor(1, 1, 1, 1)
        end

        f:Show()
      end
    end
  end

  for i = shown + 1, MAX_ICONS do w.icons[i]:Hide() end
  if shown > 0 then w:Show() else w:Hide() end
end

local function HideRow(bridge, kind)
  local w = widgets[WidgetKey(bridge, kind)]
  if w then SetDragEnabled(w, false); w:Hide() end
end

local function HideBridge(bridge)
  for _, kind in ipairs(KINDS) do HideRow(bridge, kind) end
end

-- Test preview: one icon for EVERY tracked bracket, alternating 1/2 (green,
-- rung 0) and 2/2 (red, rung 1) so both stages are visible.
local function RenderTest()
  local now = GetTime()
  local states = {}
  for idx, cat in ipairs(CATEGORY_ORDER) do
    states[cat] = {
      appearedAt = now - 1,
      expiresAt  = now + 19 - idx,
      rung       = (idx % 2 == 1) and 0 or 1,
      icon       = IconFor(nil, cat),
      category   = cat,
    }
  end
  for _, bridge in ipairs(BRIDGES) do
    for _, kind in ipairs(KINDS) do
      local anchor = KindEnabled(kind) and AnchorFor(bridge, kind) or nil
      if anchor then
        local w = EnsureWidget(bridge, kind)
        if not w._dragging then RenderStates(bridge, kind, anchor, states) end
        SetDragEnabled(w, kind ~= "plate")
      else
        HideRow(bridge, kind)
      end
    end
  end
end

local function Render()
  local cfg = Cfg()
  if cfg.enabled == false then
    for _, b in ipairs(BRIDGES) do HideBridge(b) end
    return
  end

  if cfg.test_enabled then
    RenderTest()
    return
  end

  if not InBattleground() then
    for _, b in ipairs(BRIDGES) do HideBridge(b) end
    return
  end

  for _, bridge in ipairs(BRIDGES) do
    -- One identity check per bridge, shared by its frame and plate rows.
    local name   = NormalizeUnitName(bridge)
    local states = name and drState[name] or nil

    local live = false
    if states then
      local okA, canAttack = pcall(UnitCanAttack, "player", bridge)
      local okP, isPlayer  = pcall(UnitIsPlayer, bridge)
      if okA and canAttack and okP and isPlayer then live = true end
    end

    for _, kind in ipairs(KINDS) do
      local w = widgets[WidgetKey(bridge, kind)]
      if w then SetDragEnabled(w, false) end
      local anchor = live and KindEnabled(kind) and AnchorFor(bridge, kind) or nil
      if anchor then
        RenderStates(bridge, kind, anchor, states)
      else
        HideRow(bridge, kind)
      end
    end
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Cast handling
-- ─────────────────────────────────────────────────────────────────────────────

local lastChannel   -- { name, cat, spellID }

local function OnCastSucceeded(unit, spellID)
  if IsSecret(spellID) then return end

  local info = EffectiveInfo(spellID)
  if not info or not info.category then return end
  if not TRACKED[info.category] then return end

  -- Sheet-driven gates.
  if (STEALTH_ONLY[spellID] or info.stealthOnly) and not IsStealthed() then return end
  if info.untrackable then return end
  if (info.pet and unit ~= "pet") or (not info.pet and unit == "pet") then return end

  if info.variable then
    local copy = {}
    for k, v in pairs(info) do copy[k] = v end
    copy.baseDuration = VariableDuration(info)
    info = copy
  end

  -- Candidate victims: a pet's is its own target; a player's is the target,
  -- plus focus when that is a different hostile player (the @focus-macro case
  -- the cast event cannot name). Players only -- loss-of-control reads nil on
  -- NPCs, so a mob would file "immune" on every cast.
  local primary = (unit == "pet") and "pettarget" or "target"
  local cands = {}

  local function consider(tok)
    local okE, exists = pcall(UnitExists, tok)
    if not okE or not exists then return end
    local okA, canAttack = pcall(UnitCanAttack, "player", tok)
    if not okA or not canAttack then return end
    local okP, isPlayer = pcall(UnitIsPlayer, tok)
    if not okP or not isPlayer then return end
    local name = NormalizeUnitName(tok)
    if not name then return end
    for i = 1, #cands do if cands[i].name == name then return end end
    -- Snapshot the count BEFORE the grace window: the count rising is the
    -- landed signal, whatever was already on them.
    cands[#cands + 1] = {
      name = name, unit = tok, primary = (tok == primary),
      before = LoCCount(tok),
    }
  end

  consider(primary)
  if unit ~= "pet" then consider("focus") end

  -- AoE sweep: a tracked AoE row with a radius adds every hostile player plate
  -- within that radius. The item whose use-spell has a 0..R yard range answers
  -- "within R" exactly. Hostile players are filtered BEFORE the range call --
  -- an item range check against a FRIENDLY unit is protected in combat.
  if info.aoe and not info.targetOnly and info.aoeRadius and unit ~= "pet" then
    local it = ns.DR_RADIUS_ITEMS and ns.DR_RADIUS_ITEMS[info.aoeRadius]
    if it and C_Item and C_Item.IsItemDataCachedByID then
      if not C_Item.IsItemDataCachedByID(it.itemID) then
        pcall(C_Item.RequestLoadItemDataByID, it.itemID)
      else
        for i = 1, 40 do
          local tok = "nameplate" .. i
          local okE, exists = pcall(UnitExists, tok)
          if okE and exists then
            local okA, canAttack = pcall(UnitCanAttack, "player", tok)
            local okP, isPlayer  = pcall(UnitIsPlayer, tok)
            if okA and canAttack and okP and isPlayer then
              local okR, inRange = pcall(C_Item.IsItemInRange, it.itemID, tok)
              if okR and inRange then consider(tok) end
            end
          end
        end
      end
    end
  end

  if #cands == 0 then return end

  if info.channeled then
    lastChannel = { name = cands[1].name, cat = info.category, spellID = spellID }
  end

  CheckLanded(cands, info, spellID, 1)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Module lifecycle
-- ─────────────────────────────────────────────────────────────────────────────

local driver, ticker

local function EnsureDriver()
  if driver then return driver end
  driver = CreateFrame("Frame")
  -- "pet" too: Seduction, Intimidation and the like are PET casts and never
  -- reach a "player"-only registration.
  driver:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
  driver:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
  driver:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
  driver:RegisterEvent("PLAYER_ENTERING_WORLD")
  driver:RegisterEvent("TRAIT_CONFIG_UPDATED")
  driver:SetScript("OnEvent", function(_, event, unit, arg2, spellID)
    if event == "PLAYER_ENTERING_WORLD" then
      WipeDR(); RefreshTalentVariants(); BuildNameIndex(); lastChannel = nil
      local ok, cp = pcall(UnitPower, "player", Enum.PowerType.ComboPoints)
      if ok and type(cp) == "number" and cp > 0 then lastComboPoints = cp end
      -- IsItemInRange answers nil until the item's data is cached, so ask for
      -- it now rather than at the first cast.
      if ns.DR_RADIUS_ITEMS and C_Item and C_Item.RequestLoadItemDataByID then
        for _, it in pairs(ns.DR_RADIUS_ITEMS) do
          pcall(C_Item.RequestLoadItemDataByID, it.itemID)
        end
      end
      return
    end

    if event == "TRAIT_CONFIG_UPDATED" then RefreshTalentVariants(); return end

    if event == "UNIT_POWER_UPDATE" then
      if arg2 == "COMBO_POINTS" then
        local ok, cp = pcall(UnitPower, "player", Enum.PowerType.ComboPoints)
        if ok and type(cp) == "number" and cp > 0 then lastComboPoints = cp end
      end
      return
    end

    if not DetectionActive() then lastChannel = nil; return end

    if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
      -- The CC ends when OUR channel ends, so a stop before the assumed
      -- duration explains an early end, and the DR window starts there.
      local lc = lastChannel
      if not lc then return end
      lastChannel = nil
      local e = GetDR(lc.name, lc.cat)
      if not e or e.spellID ~= lc.spellID then return end
      local now = GetTime()
      if now < (e.appearedAt or 0) + (e.assumedDur or 0) then
        local earlier = now + ResetWindow()
        if earlier < e.expiresAt then e.expiresAt = earlier end
      end
      return
    end

    OnCastSucceeded(unit, spellID)
  end)
  return driver
end

function BDR:OnEnable()
  C_Timer.After(0, function()
    if not BDR then return end
    EnsureDriver()
    RefreshTalentVariants()
    BuildNameIndex()
    if not ticker then
      ticker = C_Timer.NewTicker(0.1, function() pcall(Render) end)
    end
    pcall(Render)
  end)
end

function BDR:OnDisable()
  if ticker then ticker:Cancel(); ticker = nil end
  for _, b in ipairs(BRIDGES) do HideBridge(b) end
end

-- Called by the settings UI
function BDR:OnConfigChanged()
  pcall(ResyncBorders)
  pcall(Render)
end

function BDR:Debug()
  print("|cff00ff00DR Forever:|r Blitz/BG DR diagnostic")
  print(("  in battleground: %s   detection active: %s"):format(
    tostring(InBattleground()), tostring(DetectionActive())))
  local rows = 0
  for name, cats in pairs(drState) do
    for cat, e in pairs(cats) do
      rows = rows + 1
      print(("  %s [%s] rung=%s left=%.1fs%s"):format(
        name, cat, tostring(e.rung), math.max(0, e.expiresAt - GetTime()),
        e.assumed and " (assumed)" or ""))
    end
  end
  if rows == 0 then print("  no tracked DR entries") end
  for _, b in ipairs(BRIDGES) do
    print(("  %s: name=%s"):format(b, tostring(NormalizeUnitName(b))))
  end
end
