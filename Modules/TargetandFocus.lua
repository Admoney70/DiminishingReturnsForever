-- Modules/TargetandFocus.lua
-- Arena DR tracking on the Target and Focus frames:
--  - Mirrors Blizzard SpellDiminishStatusTray items onto the TARGET frame
--    (when target = arena#) and the FOCUS frame (when focus = arena#),
--    each with independent offsets.
--  - Borders: thin pixel border (green) + red border driven by Blizzard's
--    ImmunityIndicator.
--  - The 16s DR countdown is tracked locally with GetTime() so it never
--    depends on Midnight secret values.

local ADDON, ns = ...
local Util = ns.Util
if not Util then return end -- stale .toc; Core.lua already warned

local Core = ns.Core
if not (Core and Core.NewModule) then return end

local Arena = Core:GetModule("TargetandFocus", true) or Core:NewModule("TargetandFocus", "AceEvent-3.0")
ns.TargetandFocus = Arena

local IsForbidden            = Util.IsForbidden
local SafeIndex              = Util.SafeIndex
local SafeChildren           = Util.SafeChildren
local IsSecret               = Util.IsSecret
local SafeUnitIsUnit         = Util.SafeUnitIsUnit
local SafeUnitGUID           = Util.SafeUnitGUID
local SafeUnitName           = Util.SafeUnitName
local UnitMaybeExists        = Util.UnitMaybeExists
local UnitIsConfirmedDead    = Util.UnitIsConfirmedDead
local FindFirstTextureRegion = Util.FindFirstTextureRegion
local FindCooldownChild      = Util.FindCooldownChild
local clamp                  = Util.Clamp

-- ─────────────────────────────────────────────────────────────────────────────
-- Constants / state
-- ─────────────────────────────────────────────────────────────────────────────

local MAX_DR_SLOTS    = 10
local MDR_FRAMELEVEL  = 9999
local TEST_IDX_TARGET = 6    -- test preview anchored to TargetFrame
local TEST_IDX_FOCUS  = 7    -- test preview anchored to FocusFrame
local ECHO_OFFSET     = 10   -- mirror i+10 = focus-frame copy when target == focus
local PLATE_OFFSET    = 20   -- mirror i+20 = nameplate copy for "Show on Both"
local TEST_IDX_TARGET_NP = 8 -- "Show on Both" test preview on the target's plate
local TEST_IDX_FOCUS_NP  = 9 -- "Show on Both" test preview on the focus's plate
local TEST_MIRRORS    = { 6, 7, 8, 9 }
local DR_RESET_TIME   = 20.0 -- Retail DR reset window in seconds (12.1)

-- Longest a DR icon may stay up with NO running timer. Blizzard shows the
-- tray item while the CC is up and only starts its cooldown when the CC ends,
-- so a brief timerless icon is normal; one that outlives any CC is a frozen
-- tray item (e.g. on an enemy hidden by Mass Invisibility).
local TIMERLESS_MAX   = 10

local DR_MIRROR = {}   -- [i] = { frame, slots, _last_bridge }
local DR_HOOKED = {}   -- [i] = { [tostring(item)] = true }

-- Blizzard tray items we've already hooked for Show/Hide. Kept in OUR table,
-- weak-keyed so recycled frames can be collected. Never write a field onto a
-- Blizzard frame (e.g. item._flag = true): that taints the frame, and when
-- Blizzard's arena code later iterates it, Midnight's protected tables reject
-- the tainted execution ("attempted to iterate a table that cannot be accessed
-- while tainted").
local VIS_HOOKED = setmetatable({}, { __mode = "k" })

-- Severity is counted locally: every DR timer restart within a running
-- window is another application in that category. Midnight DR has two
-- applications: 1/2 = first (next is halved), 2/2 = second (next is immune).
local SEVERITY_COLOR = { [1] = { 0, 1, 0 }, [2] = { 1, 0, 0 } }
local SEVERITY_TEXT  = { [1] = "1/2", [2] = "2/2" }

-- When a DR application lands, the DR window runs from the END of the CC, so
-- the timer is padded for the CC still to come: a full CC on the first
-- application in a window, a halved one after. Same values as sArena.
local DR_PAD_FULL = 4
local DR_PAD_HALF = 2

local UpdateDRText   -- defined in the DR state helpers section
local ApplySlotIcon  -- defined in the texture-copy section

local function DB()
  return (Core and Core.arenaDB and Core.arenaDB.profile and Core.arenaDB.profile.arena) or nil
end

-- Configurable DR reset window (sArena-style option)
local function DRResetTime()
  local a = DB()
  local t = a and tonumber(a.dr_reset_time)
  if t and t >= 15 and t <= 20 then return t end
  return DR_RESET_TIME
end

-- Length of a slot's CURRENT window. It varies: padded when armed at the CC's
-- application, exactly the reset time when armed at the CC's end.
local function SlotDur(slot)
  return (slot and slot._mdr_dr_dur) or DRResetTime()
end

-- Anchor mode. Unit-frame mode puts the rows on the Target/Focus frames;
-- nameplate mode puts each row above that unit's nameplate instead.
-- "Show on Both": rows on the Target/Focus frames AND on the nameplates.
local function ShowBoth()
  local a = DB()
  return (a and a.dr and a.dr.np_both == true) or false
end

-- Plate-ONLY mode: the primary row sits on the nameplate. With "Show on Both"
-- the primary row stays on the unit frame and a synced copy goes on the plate.
local function NameplateMode()
  local a = DB()
  return (a and a.dr and a.dr.anchor_nameplate == true and a.dr.np_both ~= true) or false
end

-- The frame a bridge's DR row anchors to in the current mode, or nil when
-- there is nothing to anchor to (no nameplate on screen, forbidden frame).
local function BridgeAnchor(bridge)
  if NameplateMode() then return Util.GetUnitNameplate(bridge) end
  local f = (bridge == "focus") and _G.FocusFrame or _G.TargetFrame
  if not f or IsForbidden(f) then return nil end
  return f
end

-- The frame a SPECIFIC mirror anchors to, judged by what that mirror is (a
-- plate row or a frame row) rather than by the current mode -- with "Show on
-- Both" both kinds exist at once.
local function MirrorAnchor(m, bridge)
  if m and m._onPlate then return Util.GetUnitNameplate(bridge) end
  local f = (bridge == "focus") and _G.FocusFrame or _G.TargetFrame
  if not f or IsForbidden(f) then return nil end
  return f
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Bridge resolution  (which arena# is "target" / "focus")
--
-- UnitIsUnit and UnitGUID are secret-gated for enemies in Midnight-protected
-- arenas, so identity is resolved in three passes:
--
--   Pass 1 – UnitIsUnit      (fast; works outside protected arenas)
--   Pass 2 – GUID comparison (works when UnitIsUnit is gated)
--   Pass 3 – Name comparison (the pass that resolves in protected arenas)
--
-- Ownership is exclusive: each bridge is owned by at most ONE arena index,
-- so DR rows can never stack on top of each other. The same enemy can still
-- own BOTH bridges when it is your target and your focus.
-- ─────────────────────────────────────────────────────────────────────────────

local BRIDGE_UNITS = { "target", "focus" }
local BRIDGE_OWNER = {}   -- [bridge] = arena index

-- true / false / nil, where nil means "everything was gated, unknown".
local function UnitsMatch(bridge, unit)
  if SafeUnitIsUnit(bridge, unit) == true then return true end

  local ag = SafeUnitGUID(unit)
  local bg = ag and SafeUnitGUID(bridge)
  if ag and bg then return ag == bg end

  local an = SafeUnitName(unit)
  local bn = an and SafeUnitName(bridge)
  if an and bn then return an == bn end

  return nil
end

-- Recomputes bridge ownership. Runs once per update rather than per index so
-- a single enemy can never be claimed twice, and missing/absent arena units
-- (a teammate or opponent that never zoned in) simply own nothing.
local function ResolveBridgeOwners()
  for _, bridge in ipairs(BRIDGE_UNITS) do
    if not UnitMaybeExists(bridge) then
      BRIDGE_OWNER[bridge] = nil
    else
      local found
      for i = 1, 5 do
        if UnitsMatch(bridge, "arena" .. i) == true then
          found = i
          break
        end
      end
      if found then
        BRIDGE_OWNER[bridge] = found
      elseif BRIDGE_OWNER[bridge] and not UnitMaybeExists("arena" .. BRIDGE_OWNER[bridge]) then
        -- Previous owner is gone (left / never joined) → release the bridge
        BRIDGE_OWNER[bridge] = nil
      end
    end
  end
end

local function InvalidateBridgeCacheFor(bridge)
  BRIDGE_OWNER[bridge] = nil
end

local function ClearBridgeOwners()
  BRIDGE_OWNER.target = nil
  BRIDGE_OWNER.focus = nil
end

local function IsArenaInstance()
  local ok, inInst, instType = pcall(IsInInstance)
  if not ok then return false end
  return inInst and instType == "arena"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Cooldown helpers
-- ─────────────────────────────────────────────────────────────────────────────

local EnsureCooldownText  -- forward decl

local function ApplyCooldownSwipe(cd)
  if not cd or IsForbidden(cd) then return end
  if EnsureCooldownText then EnsureCooldownText(cd) end
  local a = DB()
  local dr = (a and a.dr) or {}
  pcall(function()
    if cd.SetReverse              then cd:SetReverse(dr.reverse_swipe ~= false)             end
    if cd.SetDrawSwipe            then cd:SetDrawSwipe(dr.disable_swipe ~= true)            end
    if cd.SetDrawEdge             then cd:SetDrawEdge(false)                                end
    if cd.SetSwipeColor           then cd:SetSwipeColor(0, 0, 0, 0.55)                     end
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false)                    end
    if cd.SetSwipeTexture then cd:SetSwipeTexture("Interface\\Cooldown\\cooldown2") end
    if cd.SetAlpha                then cd:SetAlpha(1)                                       end
    if cd.Show                    then cd:Show()                                            end
  end)
end

EnsureCooldownText = function(cd)
  if not cd or IsForbidden(cd) then return nil end
  if cd.Text and cd.Text.GetFont then return cd.Text end
  local fs = nil
  if cd.GetCountdownFontString then
    local ok, r = pcall(function() return cd:GetCountdownFontString() end)
    if ok then fs = r end
  end
  if fs and fs.GetFont then
    cd.Text = fs
    local fontName, _, flags = fs:GetFont()
    cd.Text.fontFile  = cd.Text.fontFile  or fontName
    cd.Text.fontFlags = cd.Text.fontFlags or flags
    return fs
  end
  return nil
end

local function SetCooldownTextSize(cd, size)
  local fs = EnsureCooldownText(cd)
  if not fs then return end
  local fontName = fs.fontFile  or select(1, fs:GetFont())
  local flags    = fs.fontFlags or select(3, fs:GetFont())
  if fontName then pcall(function() fs:SetFont(fontName, size, flags) end) end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Reflow
-- ─────────────────────────────────────────────────────────────────────────────

local function ReflowDRSlots(i)
  local m = DR_MIRROR[i]
  if not m or not m.slots or not m.frame then return end
  local a      = DB() or {}
  local bridge = m._last_bridge or "target"
  local dr     = a.dr or {}
  local b      = (type(dr[bridge]) == "table" and dr[bridge]) or {}
  local spacing = b.spacing or dr.spacing or 2
  local grow    = b.grow    or dr.grow    or "RIGHT"

  -- Beside a plate the row grows AWAY from it, starting at the edge that
  -- touches the plate. Above a plate it is centred; on a unit frame it keeps
  -- the original left-aligned growth.
  local side = m._onPlate and (m._npGrow == "LTR" or m._npGrow == "RTL")
  if side then grow = (m._npGrow == "LTR") and "RIGHT" or "LEFT" end
  local centered = m._onPlate and not side and (grow == "LEFT" or grow == "RIGHT")
  local half = 0
  if centered then
    local n, size = 0, m._size or 26
    for s = 1, MAX_DR_SLOTS do
      local sl = m.slots[s]
      if sl and sl.frame and sl.frame:IsShown() then n = n + 1 end
    end
    half = (n * size + math.max(0, n - 1) * spacing) / 2
  end

  local prev
  for s = 1, MAX_DR_SLOTS do
    local slot = m.slots[s]
    if slot and slot.frame and slot.frame.IsShown and slot.frame:IsShown() then
      slot.frame:ClearAllPoints()
      if not prev then
        if centered and grow == "LEFT" then
          slot.frame:SetPoint("RIGHT", m.frame, "CENTER", half, 0)
        elseif centered then
          slot.frame:SetPoint("LEFT", m.frame, "CENTER", -half, 0)
        elseif side and grow == "LEFT" then
          slot.frame:SetPoint("RIGHT", m.frame, "RIGHT", 0, 0)
        elseif grow == "UP" then
          slot.frame:SetPoint("BOTTOM", m.frame, "BOTTOM", 0, 0)
        elseif grow == "DOWN" then
          slot.frame:SetPoint("TOP", m.frame, "TOP", 0, 0)
        else
          slot.frame:SetPoint("LEFT", m.frame, "LEFT", 0, 0)
        end
      else
        if grow == "LEFT" then
          slot.frame:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
        elseif grow == "UP" then
          slot.frame:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
        elseif grow == "DOWN" then
          slot.frame:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
        else
          slot.frame:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
        end
      end
      prev = slot.frame
    end
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Mirror frames
-- ─────────────────────────────────────────────────────────────────────────────

local function EnsureDRMirror(i)
  if DR_MIRROR[i] and DR_MIRROR[i].frame
     and DR_MIRROR[i].frame.IsObjectType
     and DR_MIRROR[i].frame:IsObjectType("Frame") then
    return DR_MIRROR[i]
  end

  local root = CreateFrame("Frame", nil, UIParent)
  root:SetSize(1, 1)
  root:SetFrameStrata(Util.FRAME_STRATA)
  root:SetFrameLevel(MDR_FRAMELEVEL)
  root:SetToplevel(true)
  root:EnableMouse(false)
  -- Set HERE, while the row is anchored to nothing. A row that sits on a
  -- nameplate is a restricted frame (anchoring to a restricted frame makes
  -- yours restricted too), and Blizzard then refuses SetMovable outright.
  root:SetMovable(true)
  -- NOT clamped to screen: live rows are parked offscreen (ExileIdx) to keep
  -- their timers running, and a clamped row would be dragged back into the
  -- bottom-left corner of the screen instead. Only test rows are clamped.
  root:Hide()

  local slots = {}
  for s = 1, MAX_DR_SLOTS do
    local f = CreateFrame("Frame", nil, root)
    f:SetSize(26, 26)
    f:SetFrameLevel(MDR_FRAMELEVEL)
    f:Hide()

    local icon = CreateFrame("Frame", nil, f)
    icon:SetAllPoints()
    icon:SetFrameLevel(MDR_FRAMELEVEL)
    icon:EnableMouse(false)

    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    -- sArena-style icon crop
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetFrameLevel(MDR_FRAMELEVEL + 1)
    ApplyCooldownSwipe(cd)
    EnsureCooldownText(cd)

    -- DR severity text (1/2, 2/2) bottom-right, sArena style
    local textHolder = CreateFrame("Frame", nil, icon)
    textHolder:SetAllPoints()
    textHolder:SetFrameLevel(MDR_FRAMELEVEL + 5)
    -- One string per stage, both stacked in the corner. Which one is visible
    -- is decided by Blizzard's immunity flag (a secret boolean, so it can only
    -- drive SetAlphaFromBoolean, never be read) -- exactly how sArena does it,
    -- and the same flag that turns the border red, so text and border always
    -- agree. Each gets a font NOW: a FontString with no font throws on
    -- SetText, and DR can start on an enemy before their row is laid out.
    local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local function StageText(stage)
      local fs = textHolder:CreateFontString(nil, "OVERLAY")
      fs:SetDrawLayer("OVERLAY", 7)
      fs:SetPoint("BOTTOMRIGHT", textHolder, "BOTTOMRIGHT", 4, -4)
      fs:SetJustifyH("RIGHT")
      fs:SetJustifyV("BOTTOM")
      fs:SetFont(fontPath, 12, "OUTLINE")
      local c = SEVERITY_COLOR[stage]
      fs:SetText(SEVERITY_TEXT[stage])
      fs:SetTextColor(c[1], c[2], c[3], 1)
      fs:Hide()
      return fs
    end
    local drText = StageText(1)        -- "1/2" green: next one is halved
    local drTextImmune = StageText(2)  -- "2/2" red:   next one is immune
    drText:SetAlpha(1)
    drTextImmune:SetAlpha(0)

    slots[s] = { frame=f, icon=icon, tex=tex, cd=cd, drText=drText, drTextImmune=drTextImmune }
  end

  -- Mouse starts OFF and is tracked, so turning it "off" again is a no-op
  -- that never touches a frame which may by then be restricted.
  DR_MIRROR[i] = { frame=root, slots=slots, _mdr_mouse_enabled = false }
  return DR_MIRROR[i]
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Settings
-- ─────────────────────────────────────────────────────────────────────────────

local function GetDRSettings(bridge)
  local a  = DB() or {}
  local dr = a.dr or {}
  local b  = (type(dr[bridge]) == "table" and dr[bridge]) or {}
  return {
    icon_size = clamp(b.icon_size or dr.icon_size or 26, 12, 80),
    spacing   = clamp(b.spacing   or dr.spacing   or 2,  0, 20),
    grow      = b.grow    or dr.grow    or "RIGHT",
    pos_x     = (b.pos_x ~= nil) and b.pos_x or 0,
    pos_y     = (b.pos_y ~= nil) and b.pos_y or 30,
    font_size = clamp(b.font_size or dr.font_size or 14, 8, 48),
    -- Style options are shared between target and focus (dr level)
    border_style      = dr.border_style or "GLOW",
    border_black      = dr.border_black == true,
    border_size       = clamp(dr.border_size or 1, 0, 24),
    pixel_border_size = clamp(dr.pixel_border_size or 2, 1, 4),
    reverse_swipe     = dr.reverse_swipe ~= false,
    disable_swipe     = dr.disable_swipe == true,
    color_cd_text     = dr.color_cd_text == true,
    show_dr_text      = dr.show_dr_text ~= false,
    anchor_nameplate  = dr.anchor_nameplate == true,
    np_pos_x          = tonumber(dr.np_pos_x) or 0,
    np_pos_y          = tonumber(dr.np_pos_y) or 10,
    np_grow           = dr.np_grow or "CENTER",
  }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Apply layout (anchor relative to TargetFrame or FocusFrame)
-- ─────────────────────────────────────────────────────────────────────────────

local function ApplyLayoutDR(i, anchor, bridge, onPlate)
  local d    = GetDRSettings(bridge)
  local m    = EnsureDRMirror(i)
  local root = m.frame

  m._last_bridge = bridge
  m._onPlate     = onPlate and true or false
  m._size        = d.icon_size
  m._npGrow      = onPlate and d.np_grow or nil

  -- Nameplates use their own offsets: a position tuned for the Target frame
  -- makes no sense on a plate, and keeping both lets the toggle flip freely.
  local ox, oy = d.pos_x, d.pos_y
  if onPlate then ox, oy = d.np_pos_x, d.np_pos_y end

  root:SetParent(UIParent)
  -- Plate rows go behind unit/party frames; frame rows stay on top of their
  -- frame. A row on a nameplate is RESTRICTED, so its strata is only changed
  -- while it is NOT on a plate: just before it moves onto one, or just after
  -- it moves off one (below, once it is re-anchored).
  local strata = onPlate and Util.PLATE_STRATA or Util.FRAME_STRATA
  local function ApplyStrata()
    if m._strata ~= strata then
      Util.SetStrataDeep(root, strata)
      m._strata = strata
      root:SetFrameLevel(MDR_FRAMELEVEL)
    end
  end
  if onPlate then ApplyStrata() end
  root:SetFrameLevel(MDR_FRAMELEVEL)
  root:ClearAllPoints()
  if m._npGrow == "LTR" then
    -- Beside the plate's RIGHT edge, growing right (away from the plate). The
    -- row is pinned at the plate, so the first icon never moves however many
    -- icons are showing. Vertically centred on the plate; offsets nudge.
    pcall(function() root:SetPoint("LEFT", anchor, "RIGHT", d.spacing + ox, oy) end)
  elseif m._npGrow == "RTL" then
    -- Mirror image: beside the plate's LEFT edge, growing left.
    pcall(function() root:SetPoint("RIGHT", anchor, "LEFT", -d.spacing + ox, oy) end)
  else
    pcall(function() root:SetPoint("BOTTOM", anchor, "TOP", ox, oy) end)
  end
  root:Show()
  if not onPlate then ApplyStrata() end

  local size    = d.icon_size
  local spacing = d.spacing
  local grow    = d.grow
  -- Beside the plate the row is always horizontal, whatever the unit-frame
  -- grow direction is set to.
  if m._npGrow == "LTR" then grow = "RIGHT" elseif m._npGrow == "RTL" then grow = "LEFT" end
  local total   = (size * MAX_DR_SLOTS) + (spacing * (MAX_DR_SLOTS - 1))

  if grow == "UP" or grow == "DOWN" then
    root:SetSize(size, total)
  else
    root:SetSize(total, size)
  end

  for s = 1, MAX_DR_SLOTS do
    local slot = m.slots[s]
    local f    = slot.frame
    f:SetParent(root)
    f:ClearAllPoints()
    f:SetSize(size, size)
    local base = MDR_FRAMELEVEL
    f:SetFrameLevel(base)
    if slot.icon          then slot.icon:SetFrameLevel(base)        end
    if slot.cd            then slot.cd:SetFrameLevel(base + 1)      end
    if slot.overlay       then slot.overlay:SetFrameLevel(base + 2) end
    if slot.greenBorder   then slot.greenBorder:SetFrameLevel(base + 3) end
    if slot.testRedBorder then slot.testRedBorder:SetFrameLevel(base + 4) end
    if slot.redBorder     then slot.redBorder:SetFrameLevel(base + 4) end

    local dx, dy = 0, 0
    if     grow == "RIGHT" then dx =  (s-1) * (size + spacing)
    elseif grow == "LEFT"  then dx = -(s-1) * (size + spacing)
    elseif grow == "UP"    then dy =  (s-1) * (size + spacing)
    elseif grow == "DOWN"  then dy = -(s-1) * (size + spacing)
    end
    pcall(function() f:SetPoint("LEFT", root, "LEFT", dx, dy) end)
    SetCooldownTextSize(slot.cd, d.font_size)

    if slot.drText then
      local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
      slot.drText:SetFont(fontPath, d.font_size, "OUTLINE")
      if slot.drTextImmune then slot.drTextImmune:SetFont(fontPath, d.font_size, "OUTLINE") end
      UpdateDRText(slot) -- test slots are re-populated right after layout
    end

    pcall(function()
      slot.cd:SetReverse(d.reverse_swipe)
      slot.cd:SetDrawSwipe(not d.disable_swipe)
    end)
    local fs = EnsureCooldownText(slot.cd)
    if fs then
      if d.color_cd_text then
        fs:SetTextColor(0, 1, 0, 1)
      else
        fs:SetTextColor(1, 1, 1, 1)
      end
    end
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Borders
--
-- Green = fresh DR remaining, red = diminished/immune.
-- ─────────────────────────────────────────────────────────────────────────────

local function SyncSlotBorders(slot)
  if not (slot and slot._mdr_borders_done and slot.icon) then return end
  local d = GetDRSettings("target") -- style options are shared across bridges
  local opts = {
    style       = d.border_style,
    black       = d.border_black,
    border_size = d.border_size,
    pixel_size  = d.pixel_border_size,
  }
  opts.r, opts.g, opts.b = 0, 1, 0
  slot.greenBorder:Configure(opts)
  opts.r, opts.g, opts.b = 1, 0, 0
  slot.redBorder:Configure(opts)
  slot.testRedBorder:Configure(opts)
end

local function ResyncAllBorders()
  for _, m in pairs(DR_MIRROR) do
    if m and m.slots then
      for s = 1, MAX_DR_SLOTS do
        SyncSlotBorders(m.slots[s])
      end
    end
  end
end

local function EnsureDRBorders(slot, immunityIndicator, ...)
  if not slot or not slot.icon then return end
  if not slot._mdr_borders_done then
    local overlay = CreateFrame("Frame", nil, slot.icon)
    overlay:SetAllPoints(slot.icon)
    local strata = slot.icon:GetFrameStrata()
    overlay:SetFrameStrata(strata)
    overlay:SetFrameLevel(MDR_FRAMELEVEL)
    slot.overlay = overlay

    local green = Util.CreateDRBorder(overlay)
    green:SetFrameStrata(strata); green:SetFrameLevel(MDR_FRAMELEVEL + 3); green:SetAlpha(1)
    slot.greenBorder = green

    local red = Util.CreateDRBorder(overlay)
    red:SetFrameStrata(strata); red:SetFrameLevel(MDR_FRAMELEVEL + 4); red:SetAlpha(0)
    slot.redBorder = red

    local testRed = Util.CreateDRBorder(overlay)
    testRed:SetFrameStrata(strata); testRed:SetFrameLevel(MDR_FRAMELEVEL + 4); testRed:Hide()
    slot.testRedBorder = testRed

    slot._mdr_borders_done = true
    SyncSlotBorders(slot)
  end

  if immunityIndicator and (not IsForbidden(immunityIndicator)) and (not slot._mdr_indicator_hooked) then
    slot._mdr_indicator_hooked = true
    -- Only the primary slot sees Blizzard's immunity indicator; mirror it
    -- onto every copy (focus echo, nameplate copy) so their borders agree.
    local linked = { slot }
    for k = 1, select("#", ...) do
      local copy = select(k, ...)
      if copy then
        EnsureDRBorders(copy, nil)
        linked[#linked + 1] = copy
      end
    end
    slot._linked = linked   -- so a window ending can reset every copy too
    hooksecurefunc(immunityIndicator, "SetShown", function(_, shown)
      for _, sl in ipairs(linked) do
        if sl.greenBorder  then sl.greenBorder:SetAlphaFromBoolean(shown, 0, 1)  end
        if sl.redBorder    then sl.redBorder:SetAlphaFromBoolean(shown, 1, 0)    end
        if sl.drText       then sl.drText:SetAlphaFromBoolean(shown, 0, 1)       end
        if sl.drTextImmune then sl.drTextImmune:SetAlphaFromBoolean(shown, 1, 0) end
      end
    end)
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Blizzard frame accessors
-- ─────────────────────────────────────────────────────────────────────────────

local function GetArenaMember(i)
  return _G["CompactArenaFrameMember" .. tostring(i)]
end

local function GetDRTray(i)
  local member = GetArenaMember(i)
  if not member or IsForbidden(member) then return nil end
  local tray = SafeIndex(member, "SpellDiminishStatusTray")
  if tray and IsForbidden(tray) then return nil end
  return tray
end

-- ─────────────────────────────────────────────────────────────────────────────
-- DR state helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function DRTimeRemaining(slot)
  if not (slot and slot._mdr_dr_active and slot._mdr_dr_start) then return 0 end
  local rem = (slot._mdr_dr_start + SlotDur(slot)) - GetTime()
  return rem > 0 and rem or 0
end

-- Shows/hides the 1/2 / 2/2 stage text with the option and the slot's state.
-- WHICH of the pair is visible is set by the immunity flag's alpha swap.
function UpdateDRText(slot)
  if not (slot and slot.drText) then return end
  local a = DB()
  local show = (a and a.dr and a.dr.show_dr_text ~= false and slot._mdr_dr_active) and true or false
  slot.drText:SetShown(show)
  if slot.drTextImmune then slot.drTextImmune:SetShown(show) end
end

-- Puts a slot -- and every copy linked to it -- back to the fresh-window look:
-- green border, "1/2". Blizzard's immunity flag only reports CHANGES, so a
-- window that ends while red must not leave the next window red.
local function ResetStage(slot)
  for _, sl in ipairs(slot._linked or { slot }) do
    if sl.greenBorder  then sl.greenBorder:SetAlpha(1)  end
    if sl.redBorder    then sl.redBorder:SetAlpha(0)    end
    if sl.drText       then sl.drText:SetAlpha(1)       end
    if sl.drTextImmune then sl.drTextImmune:SetAlpha(0) end
  end
end

local function ClearSlotState(slot)
  slot._mdr_src_shown = false
  slot._mdr_dr_active = false
  slot._mdr_dr_start  = nil
  slot._mdr_dr_dur    = nil
  slot._echo_start    = nil
  slot._echo_dur      = nil
  ResetStage(slot)
  slot._mdr_lastTex   = nil
  slot._mdr_lastAtlas = nil
  UpdateDRText(slot)
  if slot.redBorder     then slot.redBorder:SetAlpha(0) end
  if slot.testRedBorder then slot.testRedBorder:Hide()  end
  if slot.cd then pcall(function() slot.cd:SetCooldown(0, 0) end) end
  if slot.frame then slot.frame:Hide() end
end

local function ClearIdxState(i)
  local m = DR_MIRROR[i]
  if not (m and m.slots) then return end
  for s = 1, MAX_DR_SLOTS do
    local slot = m.slots[s]
    if slot then ClearSlotState(slot) end
  end
  ReflowDRSlots(i)
end

-- Self-healing pass, driven by the periodic ticker:
--  - re-shows slots whose local 16s DR window is still running (e.g. after
--    the enemy team vanished behind Mass Invisibility and reappeared)
--  - expires slots whose window ended while their frames were hidden and
--    OnCooldownDone never fired
local function SyncSlotVisibility(i)
  local m = DR_MIRROR[i]
  if not (m and m.slots) then return end
  local changed = false

  for s = 1, MAX_DR_SLOTS do
    local slot = m.slots[s]
    if slot and slot._mdr_dr_active then
      if DRTimeRemaining(slot) > 0 then
        if slot.frame and not slot.frame:IsShown() then
          -- Re-arm the visual cooldown in case it was cleared while hidden
          pcall(function()
            local startMs = slot.cd:GetCooldownTimes()
            if not startMs or startMs == 0 then
              slot.cd:SetCooldown(slot._mdr_dr_start, SlotDur(slot))
              ApplyCooldownSwipe(slot.cd)
            end
          end)
          ApplySlotIcon(slot) -- repaint in case Blizzard blanked the source
          slot.frame:Show()
          changed = true
        end
      else
        -- Window over; clean up even if OnCooldownDone was missed
        slot._mdr_dr_active = false
        slot._mdr_dr_start  = nil
        slot._mdr_dr_dur    = nil
        UpdateDRText(slot)
        ResetStage(slot)
        -- Same rule as OnCooldownDone: our window ending hides the icon
        -- whatever the (possibly frozen) source item says.
        slot._mdr_src_shown = false
        if slot.frame and slot.frame:IsShown() then
          slot.frame:Hide()
          changed = true
        end
      end
    elseif slot and slot.frame and slot.frame:IsShown() then
      -- Up with NO running timer. Normal for a moment (Blizzard shows the
      -- item during the CC and starts the DR cooldown when it ends), but never
      -- indefinitely: past TIMERLESS_MAX it is a frozen tray item.
      if GetTime() - (slot._mdr_shown_at or 0) > TIMERLESS_MAX then
        slot._mdr_src_shown = false
        slot.frame:Hide()
        changed = true
      end
    end
  end

  if changed then ReflowDRSlots(i) end
end

-- Mirrors the primary slots of index i onto the echo mirror (i+ECHO_OFFSET),
-- shown on the focus frame when the same enemy is both target and focus.
-- Everything copied here is our own non-secret state.
local function SyncEchoSlots(i, copyIdx)
  local pm = DR_MIRROR[i]
  local em = DR_MIRROR[copyIdx or (i + ECHO_OFFSET)]
  if not (pm and pm.slots and em and em.slots) then return end

  for s = 1, MAX_DR_SLOTS do
    local ps, es = pm.slots[s], em.slots[s]
    if ps and es then
      local shown = ps.frame and ps.frame:IsShown() and true or false
      if shown then
        -- Icon: mirror the primary slot's cached value (never re-read the
        -- live texture, which may be an atlas sheet or a secret)
        es._mdr_lastAtlas = ps._mdr_lastAtlas
        es._mdr_lastTex   = ps._mdr_lastTex
        ApplySlotIcon(es)

        -- Cooldown driven by our own timer
        if ps._mdr_dr_active and ps._mdr_dr_start then
          local dur = SlotDur(ps)
          if es._echo_start ~= ps._mdr_dr_start or es._echo_dur ~= dur then
            es._echo_start, es._echo_dur = ps._mdr_dr_start, dur
            pcall(function() es.cd:SetCooldown(ps._mdr_dr_start, dur) end)
            ApplyCooldownSwipe(es.cd)
          end
        elseif es._echo_start then
          es._echo_start, es._echo_dur = nil, nil
          pcall(function() es.cd:SetCooldown(0, 0) end)
        end

        -- Stage text: shown with the window; which stage comes from the
        -- immunity flag, already linked to every copy.
        es._mdr_dr_active = ps._mdr_dr_active
        UpdateDRText(es)

        if es.frame then es.frame:Show() end
      else
        if es.frame then es.frame:Hide() end
      end
    end
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Hook: DR item
-- ─────────────────────────────────────────────────────────────────────────────

-- Neutral icon used only if the source never gave us a usable texture, so a
-- visible DR slot can never render as an empty/placeholder square.
local FALLBACK_ICON = 132298

-- Copies the source icon onto texDst. An atlas and a plain texture are
-- mutually exclusive: setting the atlas and THEN calling SetTexture with
-- GetTexture() would paint the raw atlas sheet, which is what produced the
-- garbled "question mark" icons. When `cache` is given the winning value is
-- remembered there so the icon can be restored later.
local function CopyItemTexture(icon, texDst, cache)
  if not (icon and texDst) then return false end
  local applied = false

  pcall(function()
    if icon.GetAtlas and texDst.SetAtlas then
      local a = icon:GetAtlas()
      if a ~= nil and not IsSecret(a) and a ~= "" then
        texDst:SetAtlas(a, true)
        if cache then
          cache._mdr_lastAtlas = a
          cache._mdr_lastTex   = nil
        end
        applied = true
      end
    end
  end)
  if applied then return true end

  pcall(function()
    if icon.GetTexture and texDst.SetTexture then
      local t = icon:GetTexture()
      if t == nil then return end
      if not IsSecret(t) and (t == 0 or t == "") then return end
      texDst:SetTexture(t)
      if cache then
        cache._mdr_lastTex   = t
        cache._mdr_lastAtlas = nil
      end
      applied = true
    end
  end)

  return applied
end

-- Re-applies the last known-good icon. Blizzard clears the tray item's
-- texture when it hides the item (stealth, Mass Invisibility, end of CC),
-- but our DR window keeps running, so the mirror must repaint itself
-- instead of showing an empty square.
function ApplySlotIcon(slot)
  if not (slot and slot.tex) then return end
  pcall(function()
    if slot._mdr_lastAtlas then
      slot.tex:SetAtlas(slot._mdr_lastAtlas, true)
    elseif slot._mdr_lastTex ~= nil then
      slot.tex:SetTexture(slot._mdr_lastTex)
    else
      slot.tex:SetTexture(FALLBACK_ICON)
    end
  end)
end

local function HookDRItem(i, slotIdx, item)
  if not item or IsForbidden(item) then return end
  DR_HOOKED[i] = DR_HOOKED[i] or {}
  local key = tostring(item)
  if DR_HOOKED[i][key] then return end
  DR_HOOKED[i][key] = true

  local icon = SafeIndex(item, "Icon") or SafeIndex(item, "icon") or SafeIndex(item, "Texture")
  if icon and IsForbidden(icon) then icon = nil end
  local cd = SafeIndex(item, "Cooldown") or SafeIndex(item, "cooldown") or SafeIndex(item, "CooldownFrame")
  if cd and IsForbidden(cd) then cd = nil end
  if not icon then icon = FindFirstTextureRegion(item) end
  if not cd   then cd   = FindCooldownChild(item)      end

  local ind = SafeIndex(item, "ImmunityIndicator")
  if ind and IsForbidden(ind) then ind = nil end

  local m    = EnsureDRMirror(i)
  local slot = m.slots[slotIdx]
  if not slot then return end

  -- Focus-frame copy used when the same enemy is both target and focus
  local echoSlot = EnsureDRMirror(i + ECHO_OFFSET).slots[slotIdx]
  -- Nameplate copy used by "Show on Both"
  local plateSlot = EnsureDRMirror(i + PLATE_OFFSET).slots[slotIdx]

  -- Hooking a brand-new tray item while our DR window is running means the
  -- member frame was just recreated (e.g. Mass Invisibility ended). Its
  -- initial cooldown arm must continue the saved window, not restart it.
  if slot._mdr_dr_active then
    m._mdr_grace_until = math.max(m._mdr_grace_until or 0, GetTime() + 2)
  end

  local texDst = slot.tex
  local cdDst  = slot.cd
  local texEcho = echoSlot and echoSlot.tex

  ApplyCooldownSwipe(cdDst)

  -- Cleanup when OUR 16s DR cooldown finishes
  if not slot._mdr_done_hooked then
    slot._mdr_done_hooked = true
    pcall(function()
      cdDst:HookScript("OnCooldownDone", function()
        slot._mdr_dr_active = false
        slot._mdr_dr_start  = nil
        slot._mdr_dr_dur    = nil
        UpdateDRText(slot)
        ResetStage(slot)
        -- OUR window is over, so the icon goes -- even if Blizzard's tray item
        -- still reads "shown". That item freezes on an enemy who is unseen
        -- when their DR resets (Mass Invisibility, stealth); waiting on it is
        -- what left a timerless icon up until the next CC. sArena hides on its
        -- own cooldown finishing in exactly the same way.
        slot._mdr_src_shown = false
        if slot.redBorder     then slot.redBorder:SetAlpha(0) end
        if slot.testRedBorder then slot.testRedBorder:Hide()  end
        if slot.frame         then slot.frame:Hide()          end
        ReflowDRSlots(i)
      end)
    end)
  end

  -- Our DR window, timed with GetTime() so it never depends on secret values.
  -- Two Blizzard signals arm it, the same two sArena uses:
  --   * the IMMUNITY FLAG changing = a DR application just landed (the
  --     moment that turns the border red on a restun). Restart immediately,
  --     padded for the CC still to come.
  --   * the tray item's COOLDOWN starting = the CC just ended. Re-anchor to
  --     exactly the reset time from now.
  -- Waiting for the cooldown alone is what left a restun showing the OLD
  -- timer until the second CC ran out.
  local function ArmWindow(start, dur)
    slot._mdr_dr_start  = start
    slot._mdr_dr_dur    = dur
    slot._mdr_dr_active = true
    pcall(function() cdDst:SetCooldown(start, dur) end)
    ApplyCooldownSwipe(cdDst)
    UpdateDRText(slot)
    if slot.frame then slot.frame:Show() end
    ReflowDRSlots(i)
  end

  -- Visibility-change grace (Mass Invisibility, stealth): Blizzard re-arms
  -- the tray when the enemy is re-seen. That is not a new application, so
  -- keep the saved window instead of restarting it.
  local function InGrace()
    local g = m._mdr_grace_until
    return g and GetTime() < g and slot._mdr_dr_active and slot._mdr_dr_start
  end

  local function OnApplication()
    if InGrace() then ArmWindow(slot._mdr_dr_start, SlotDur(slot)); return end
    local pad = slot._mdr_dr_active and DR_PAD_HALF or DR_PAD_FULL
    ArmWindow(GetTime(), DRResetTime() + pad)
  end

  local function OnDRCooldown()
    if InGrace() then ArmWindow(slot._mdr_dr_start, SlotDur(slot)); return end
    ArmWindow(GetTime(), DRResetTime())
  end

  local ind0 = SafeIndex(item, "ImmunityIndicator")
  if ind0 and not IsForbidden(ind0) then
    pcall(function()
      hooksecurefunc(ind0, "SetShown", function() OnApplication() end)
    end)
  end

  -- Hook source cooldown to detect when Blizzard starts a DR timer.
  -- In Midnight-protected arenas cooldown durations are secret; we ignore
  -- the actual duration and always run our own DR_RESET_TIME (16s).
  if cd then
    pcall(function()
      hooksecurefunc(cd, "SetCooldown", function(_, start, duration)
        local clear = false
        if duration == nil then
          clear = true
        elseif not IsSecret(duration) then
          if duration <= 0 then clear = true end
        end
        if clear then return end
        OnDRCooldown()
      end)
    end)
    pcall(function()
      if cd.SetCooldownDuration then
        hooksecurefunc(cd, "SetCooldownDuration", function(_, duration)
          if duration ~= nil and (IsSecret(duration) or duration > 0) then
            OnDRCooldown()
          end
        end)
      end
    end)
    pcall(function()
      if cd.SetCooldownFromDurationObject then
        hooksecurefunc(cd, "SetCooldownFromDurationObject", function()
          OnDRCooldown()
        end)
      end
    end)
  end

  CopyItemTexture(icon, texDst, slot)
  if texEcho then CopyItemTexture(icon, texEcho, echoSlot) end

  -- Mirror source Show/Hide
  pcall(function()
    if not VIS_HOOKED[item] then
      VIS_HOOKED[item] = true
      hooksecurefunc(item, "Show", function()
        slot._mdr_src_shown = true
        slot._mdr_shown_at  = GetTime()
        -- Re-copy texture so the correct icon appears immediately
        if not CopyItemTexture(icon, texDst, slot) then ApplySlotIcon(slot) end
        if texEcho then CopyItemTexture(icon, texEcho, echoSlot) end
        if slot.frame then slot.frame:Show() end
        ReflowDRSlots(i)
      end)
      hooksecurefunc(item, "Hide", function()
        slot._mdr_src_shown = false
        if slot.redBorder     then slot.redBorder:SetAlpha(0) end
        if slot.testRedBorder then slot.testRedBorder:Hide()  end
        -- Blizzard also hides tray items when the unit merely becomes
        -- unseen (stealth, Mass Invisibility).  Only tear the mirror down
        -- on a confirmed death or once our DR window is over; otherwise
        -- keep the countdown visible.
        if UnitIsConfirmedDead("arena" .. tostring(i)) or not slot._mdr_dr_active then
          slot._mdr_dr_active = false
          slot._mdr_dr_start  = nil
          slot._mdr_dr_dur    = nil
          UpdateDRText(slot)
          ResetStage(slot)
          pcall(function() cdDst:SetCooldown(0, 0) end)
          if slot.frame then slot.frame:Hide() end
          ReflowDRSlots(i)
        end
      end)
    end
  end)

  -- If the item is already visible when first hooked (mid-match hookup)
  pcall(function()
    if item.IsShown and item:IsShown() then
      slot._mdr_src_shown = true
      slot._mdr_shown_at  = GetTime()
      if not CopyItemTexture(icon, texDst, slot) then ApplySlotIcon(slot) end
      if texEcho then CopyItemTexture(icon, texEcho, echoSlot) end
      if slot.frame then slot.frame:Show() end
      ReflowDRSlots(i)
    end
  end)

  -- Mirror texture changes
  if icon then
    pcall(function()
      hooksecurefunc(icon, "SetTexture", function(_, tex)
        local cleared = (tex == nil) or (not IsSecret(tex) and (tex == 0 or tex == ""))
        if cleared then
          -- Blizzard blanked the source icon. Keep our own icon while the
          -- DR window is still running; only hide once it has expired.
          if slot._mdr_dr_active then ApplySlotIcon(slot) else
            if slot.frame then slot.frame:Hide() end
            ReflowDRSlots(i)
          end
          return
        end
        texDst:SetTexture(tex)
        slot._mdr_lastTex, slot._mdr_lastAtlas = tex, nil
        if texEcho then pcall(function() texEcho:SetTexture(tex) end) end
        ReflowDRSlots(i)
      end)
    end)
    pcall(function()
      if icon.SetAtlas and texDst.SetAtlas then
        hooksecurefunc(icon, "SetAtlas", function(_, atlas)
          local cleared = (atlas == nil) or (not IsSecret(atlas) and atlas == "")
          if cleared then
            if slot._mdr_dr_active then ApplySlotIcon(slot) else
              if slot.frame then slot.frame:Hide() end
              ReflowDRSlots(i)
            end
            return
          end
          texDst:SetAtlas(atlas, true)
          slot._mdr_lastAtlas, slot._mdr_lastTex = atlas, nil
          if texEcho then pcall(function() texEcho:SetAtlas(atlas, true) end) end
          ReflowDRSlots(i)
        end)
      end
    end)
  end

  EnsureDRBorders(slot, ind, echoSlot, plateSlot)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Show / hide / exile helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function HideIdx(i)
  if DR_MIRROR[i] and DR_MIRROR[i].frame then DR_MIRROR[i].frame:Hide() end
end

-- Move the mirror offscreen but keep it shown so cooldowns keep running.
local function ExileIdx(i)
  local m = DR_MIRROR[i]
  if not (m and m.frame) or IsForbidden(m.frame) then return end
  pcall(function()
    m.frame:ClearAllPoints()
    -- Belt and braces: a row clamped to the screen can't be parked offscreen.
    m.frame:SetClampedToScreen(false)
    m.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -2000, -2000)
    m.frame:Show()
  end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Live update per arena index
-- ─────────────────────────────────────────────────────────────────────────────

-- Hooks every item in an enemy's Blizzard DR tray. Runs for ALL enemies on
-- every pass, not only the one you are targeting: a DR started on someone
-- you are not targeting must still be caught, or when you DO target them
-- their icon shows with no timer.
local function HookTray(i)
  local tray = GetDRTray(i)
  if not tray then return end
  local n = 0
  for _, item in ipairs(SafeChildren(tray)) do
    n = n + 1
    if n > MAX_DR_SLOTS then break end
    HookDRItem(i, n, item)
  end
  local m = DR_MIRROR[i]
  if m and m.slots then
    for s = n + 1, MAX_DR_SLOTS do
      local slot = m.slots[s]
      if slot and slot.frame then slot.frame:Hide() end
    end
  end
end

-- Hooks a tray item the instant Blizzard configures it -- BEFORE it starts
-- the item's cooldown -- so even the very first DR on an enemy is caught.
-- The per-pass HookTray scan alone could miss a cooldown started in the same
-- frame the item was created. Same approach as sArena.
local function HookTrayItemNow(item)
  if not item or IsForbidden(item) then return end
  local okP, tray = pcall(item.GetParent, item)
  if not okP or not tray then return end
  for i = 1, 5 do
    if GetDRTray(i) == tray then
      local n = 0
      for _, child in ipairs(SafeChildren(tray)) do
        n = n + 1
        if child == item then
          if n <= MAX_DR_SLOTS then HookDRItem(i, n, item) end
          return
        end
      end
      return
    end
  end
end

local trayHookInstalled = false

-- The tray item mixin can belong to a Blizzard addon that loads on demand,
-- so this is retried until it exists.
local function InstallTrayHook()
  if trayHookInstalled then return end
  local mixin = _G.SpellDiminishStatusTrayItemMixin
  if not (mixin and type(mixin.SetCategoryInfo) == "function") then return end
  trayHookInstalled = true
  hooksecurefunc(mixin, "SetCategoryInfo", function(item)
    pcall(HookTrayItemNow, item)
  end)
end

local function UpdateLiveIdx(i)
  local unit    = "arena" .. tostring(i)
  local echoIdx = i + ECHO_OFFSET

  -- Hook first, whether or not this enemy is shown anywhere right now.
  HookTray(i)

  local onPlate      = NameplateMode()
  local targetAnchor = (BRIDGE_OWNER.target == i) and BridgeAnchor("target") or nil
  local focusAnchor  = (BRIDGE_OWNER.focus == i) and BridgeAnchor("focus") or nil

  local anchor, bridge
  if targetAnchor then
    anchor, bridge = targetAnchor, "target"
  elseif focusAnchor then
    anchor, bridge = focusAnchor, "focus"
  end

  if not anchor then
    -- Nothing to sit on (e.g. the enemy's plate is off screen). Exile rather
    -- than hide so the DR timers keep running underneath.
    ExileIdx(i)
    HideIdx(echoIdx)
    HideIdx(i + PLATE_OFFSET)
    SyncSlotVisibility(i)
    return
  end

  ApplyLayoutDR(i, anchor, bridge, onPlate)

  SyncSlotVisibility(i)
  ReflowDRSlots(i)

  -- Same enemy is both target AND focus -> show a synced copy on the focus
  -- frame (the primary mirror is on the target frame). On nameplates both
  -- resolve to the SAME plate, so the copy would just stack on top: skip it.
  if targetAnchor and focusAnchor and focusAnchor ~= targetAnchor then
    ApplyLayoutDR(echoIdx, focusAnchor, "focus", onPlate)
    SyncEchoSlots(i)
    ReflowDRSlots(echoIdx)
  else
    HideIdx(echoIdx)
  end

  -- "Show on Both": a synced copy of this enemy's row on their nameplate (the
  -- primary row above stays on the unit frame). Target and focus on the same
  -- player share one plate, so a single copy covers both.
  local plateIdx = i + PLATE_OFFSET
  local plate, plateBridge
  if ShowBoth() then
    if BRIDGE_OWNER.target == i then
      plate, plateBridge = Util.GetUnitNameplate("target"), "target"
    end
    if not plate and BRIDGE_OWNER.focus == i then
      plate, plateBridge = Util.GetUnitNameplate("focus"), "focus"
    end
  end
  if plate then
    ApplyLayoutDR(plateIdx, plate, plateBridge, true)
    SyncEchoSlots(i, plateIdx)
    ReflowDRSlots(plateIdx)
  else
    HideIdx(plateIdx)
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Test mode
-- ─────────────────────────────────────────────────────────────────────────────

-- Computes the dragged mirror's offset from its anchor frame and writes it
-- to the profile (same values the X/Y Offset sliders use).
local function SaveDragPosition(idx, bridge)
  local m = DR_MIRROR[idx]
  local anchor = MirrorAnchor(m, bridge)
  if not (m and m.frame and anchor) then return end
  local root = m.frame

  local rs = root:GetEffectiveScale()
  local as = anchor:GetEffectiveScale()
  local rootLeft, rootBottom = root:GetLeft(), root:GetBottom()
  local anchorLeft, anchorTop = anchor:GetLeft(), anchor:GetTop()
  if not (rootLeft and rootBottom and anchorLeft and anchorTop) then return end

  -- Root is anchored BOTTOM → anchor TOP; offsets are in the root's space.
  local rootCX   = (rootLeft + root:GetWidth() / 2) * rs
  local anchorCX = (anchorLeft + anchor:GetWidth() / 2) * as
  local ox = Util.Clamp(math.floor((rootCX - anchorCX) / rs + 0.5), -1280, 1280)
  local oy = Util.Clamp(math.floor((rootBottom * rs - anchorTop * as) / rs + 0.5), -960, 960)

  -- Beside-the-plate modes pin a side edge of the row to the plate's opposite
  -- edge, vertically centred, so invert that geometry instead.
  if m._onPlate then
    local d = GetDRSettings(bridge)
    local aBottom = anchor:GetBottom()
    if (d.np_grow == "LTR" or d.np_grow == "RTL") and aBottom then
      local rootCY   = (rootBottom + root:GetHeight() / 2) * rs
      local anchorCY = (aBottom + anchor:GetHeight() / 2) * as
      oy = math.floor((rootCY - anchorCY) / rs + 0.5)
      if d.np_grow == "LTR" then
        ox = math.floor((root:GetLeft() * rs - anchor:GetRight() * as) / rs - d.spacing + 0.5)
      else
        ox = math.floor((root:GetRight() * rs - anchor:GetLeft() * as) / rs + d.spacing + 0.5)
      end
    end
  end

  local a = DB()
  if not a then return end
  a.dr = a.dr or {}
  if m._onPlate then
    -- Nameplate offsets are shared by target and focus: every plate has the
    -- same shape, so one position fits both.
    a.dr.np_pos_x = Util.Clamp(ox, -300, 300)
    a.dr.np_pos_y = Util.Clamp(oy, -200, 200)
  else
    a.dr[bridge] = (type(a.dr[bridge]) == "table" and a.dr[bridge]) or {}
    a.dr[bridge].pos_x = ox
    a.dr[bridge].pos_y = oy
  end

  Core:NotifyOptionsChanged()
end

-- One-time drag wiring for a test mirror: dragging any of its icons moves
-- the whole cluster.
local function EnsureTestDrag(idx, bridge)
  local m = EnsureDRMirror(idx)
  if m._mdr_drag_setup then return end
  m._mdr_drag_setup = true

  local root = m.frame
  -- Keeps a dragged test row on screen. Safe here: test rows are never
  -- exiled, and this only runs while the row is on a unit frame.
  root:SetClampedToScreen(true)

  for s = 1, MAX_DR_SLOTS do
    local f = m.slots[s].frame
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
      m._mdr_dragging = true
      root:StartMoving()
    end)
    f:SetScript("OnDragStop", function()
      root:StopMovingOrSizing()
      m._mdr_dragging = false
      SaveDragPosition(idx, bridge)
      local anchor = MirrorAnchor(m, bridge)
      if anchor then
        ApplyLayoutDR(idx, anchor, bridge, m._onPlate)
        ReflowDRSlots(idx)
      end
    end)
  end
end

-- Icons only react to the mouse while test mode is active, so live frames
-- never block clicks.
local function SetTestMouse(idx, enabled)
  local m = DR_MIRROR[idx]
  if not (m and m.slots) then return end
  if m._mdr_mouse_enabled == enabled then return end
  m._mdr_mouse_enabled = enabled
  for s = 1, MAX_DR_SLOTS do
    local f = m.slots[s].frame
    if f then f:EnableMouse(enabled) end
  end
end

-- Test preview: one icon for each DR category that can be tracked in
-- Midnight -- stun, incapacitate, fear and root, the same four as World and
-- Blitz -- alternating 1/2 (green) and 2/2 (red) so both stages show.
local TEST_CATEGORIES = {
  { name = "Stun",         icon = 132298 },
  { name = "Incapacitate", icon = 136071 },
  { name = "Fear",         icon = 136183 },
  { name = "Root",         icon = 136100 },
}

local function PopulateTestSlots(idx)
  local drm = EnsureDRMirror(idx)
  if not (drm and drm.slots) then return end
  for s = 1, MAX_DR_SLOTS do
    local slot = drm.slots[s]
    if slot then EnsureDRBorders(slot, nil) end
    if slot and slot.frame then
      local cat = TEST_CATEGORIES[s]
      if cat then
        slot.frame:Show()
        slot.tex:SetTexture(cat.icon)
        pcall(function() slot.cd:SetCooldown(GetTime(), 20) end)
        local sev = (s % 2 == 1) and 1 or 2  -- alternate 1/2 and 2/2
        if slot.drText then
          local a2 = DB() or {}
          local showText = not (a2.dr and a2.dr.show_dr_text == false)
          slot.drText:SetShown(showText)
          slot.drText:SetAlpha(sev == 1 and 1 or 0)
          if slot.drTextImmune then
            slot.drTextImmune:SetShown(showText)
            slot.drTextImmune:SetAlpha(sev == 2 and 1 or 0)
          end
        end
        local testRed = slot.testRedBorder
        local red     = slot.redBorder
        if sev == 2 then
          if testRed then testRed:Show()  elseif red then red:SetAlpha(1) end
          if slot.greenBorder then slot.greenBorder:Hide() end
        else
          if testRed then testRed:Hide() elseif red then red:SetAlpha(0) end
          if slot.greenBorder then slot.greenBorder:Show() end
        end
      else
        slot.frame:Hide()
      end
    end
  end
  ReflowDRSlots(idx)
end

local function UpdateTestMirror(idx, anchor, bridge, onPlate)
  if anchor and not IsForbidden(anchor) then
    local m = DR_MIRROR[idx]
    -- Nameplate rows can't be dragged: Blizzard blocks moving anything
    -- anchored to a nameplate. Take the mouse away BEFORE the row is moved
    -- onto the plate (afterwards even that call may be refused); these rows
    -- are positioned with the Nameplate X/Y Offset sliders instead.
    if onPlate then SetTestMouse(idx, false) end
    -- Don't re-anchor while the user is dragging the mirror around
    if not (m and m._mdr_dragging) then
      ApplyLayoutDR(idx, anchor, bridge, onPlate)
      PopulateTestSlots(idx)
    end
    if not onPlate then
      EnsureTestDrag(idx, bridge)
      SetTestMouse(idx, true)
    end
  else
    SetTestMouse(idx, false)
    HideIdx(idx)
  end
end

local function HideTestMirrors()
  for _, idx in ipairs(TEST_MIRRORS) do
    SetTestMouse(idx, false)
    HideIdx(idx)
  end
end

local function UpdateTest()
  local a    = DB() or {}
  local test = a.test or {}
  if not test.enabled then
    HideTestMirrors()
    return
  end

  -- Unit-frame mode anchors to TargetFrame/FocusFrame, which exist even with
  -- nothing targeted, so the offset can be positioned freely. Nameplate mode
  -- needs an actual plate: target (and focus) something to see the preview.
  local tAnchor = BridgeAnchor("target")
  local fAnchor = BridgeAnchor("focus")
  -- Target and focus on the same unit share one plate: show one preview.
  if fAnchor and fAnchor == tAnchor then fAnchor = nil end
  local plateOnly = NameplateMode()
  UpdateTestMirror(TEST_IDX_TARGET, tAnchor, "target", plateOnly)
  UpdateTestMirror(TEST_IDX_FOCUS,  fAnchor, "focus",  plateOnly)

  -- "Show on Both": a second preview on the nameplates.
  local tPlate, fPlate
  if ShowBoth() then
    tPlate = Util.GetUnitNameplate("target")
    fPlate = Util.GetUnitNameplate("focus")
    if fPlate and fPlate == tPlate then fPlate = nil end
  end
  UpdateTestMirror(TEST_IDX_TARGET_NP, tPlate, "target", true)
  UpdateTestMirror(TEST_IDX_FOCUS_NP,  fPlate, "focus",  true)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Main update
-- ─────────────────────────────────────────────────────────────────────────────

local function UpdateAll()
  local a    = DB() or {}
  local test = a.test or {}

  if test.enabled then
    UpdateTest()
    return
  end

  -- Test previews only exist in test mode (this also clears them when test
  -- mode is switched off while inside an arena).
  HideTestMirrors()

  if not IsArenaInstance() then
    for i = 1, 5 do
      HideIdx(i)
      HideIdx(i + ECHO_OFFSET)
      HideIdx(i + PLATE_OFFSET)
    end
    return
  end

  pcall(ResolveBridgeOwners)

  -- Each index is isolated: an arena slot with no unit or no Blizzard frame
  -- (a player who never joined) can't stop the others from updating.
  for i = 1, 5 do
    local ok, err = pcall(UpdateLiveIdx, i)
    if not ok and not Arena._mdr_warned then
      Arena._mdr_warned = true
      print("|cffff0000MidnightDiminish:|r DR update error: " .. tostring(err))
    end
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Module lifecycle
-- ─────────────────────────────────────────────────────────────────────────────

function Arena:OnEnable()
  self._mdr_initTries = 0
  self:EnsureInit()
end

function Arena:OnDisable()
  if self._mdr_ticker then
    pcall(function() self._mdr_ticker:Cancel() end)
    self._mdr_ticker = nil
  end
  for i = 1, 5 do
    HideIdx(i)
    HideIdx(i + ECHO_OFFSET)
    HideIdx(i + PLATE_OFFSET)
  end
  HideTestMirrors()
end

function Arena:EnsureInit()
  if self._mdr_initialized then return end

  if not DB() then
    self._mdr_initTries = (self._mdr_initTries or 0) + 1
    if self._mdr_initTries <= 5 then
      C_Timer.After(0.25, function() if Arena and Arena.EnsureInit then Arena:EnsureInit() end end)
    end
    return
  end

  self._mdr_initialized = true

  InstallTrayHook()
  self:RegisterEvent("ADDON_LOADED", function() InstallTrayHook() end)

  self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    InstallTrayHook()
    -- Clear per-match DR state so stale timers don't carry between arenas
    ClearBridgeOwners()
    for idx = 1, 5 do
      ClearIdxState(idx)
      ClearIdxState(idx + ECHO_OFFSET)
      ClearIdxState(idx + PLATE_OFFSET)
    end
    UpdateAll()
  end)
  self:RegisterEvent("PLAYER_TARGET_CHANGED", function()
    InvalidateBridgeCacheFor("target")
    UpdateAll()
  end)
  -- Nameplates are pooled and recycled: re-anchor as soon as a plate appears
  -- or goes away instead of waiting for the next ticker pass.
  local function OnPlateChanged()
    if NameplateMode() or ShowBoth() then UpdateAll() end
  end
  self:RegisterEvent("NAME_PLATE_UNIT_ADDED", OnPlateChanged)
  self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", OnPlateChanged)
  self:RegisterEvent("PLAYER_FOCUS_CHANGED", function()
    InvalidateBridgeCacheFor("focus")
    UpdateAll()
  end)
  self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() UpdateAll() end)
  self:RegisterEvent("ARENA_OPPONENT_UPDATE", function(_, unit, updateReason)
    -- "destroyed" fires when an opponent's frame is torn down.  That happens
    -- on death, but ALSO when units become unseen (e.g. the whole enemy team
    -- vanishing behind Mass Invisibility).  Only wipe DR state on a confirmed
    -- death — otherwise the running DR timers must survive and reappear.
    if unit then
      for idx = 1, 5 do
        if unit == "arena" .. idx then
          local m = DR_MIRROR[idx]
          -- Blizzard re-arms the tray around VISIBILITY changes; for a moment
          -- after one, a re-arm continues the saved window. Only for those
          -- reasons: granted on every opponent update, it swallowed genuine
          -- restuns and left the old timer running.
          if m and (updateReason == "seen" or updateReason == "unseen" or updateReason == "destroyed") then
            m._mdr_grace_until = GetTime() + 2
          end
          -- "destroyed" (frame torn down) and "unseen" (Mass Invisibility,
          -- stealth) both freeze this enemy's Blizzard tray: no Hide or
          -- SetCooldown arrives for it until they are seen again. Mass
          -- Invisibility is "unseen" -- previously unhandled.
          if updateReason == "destroyed" or updateReason == "unseen" then
            if updateReason == "destroyed" then
              if BRIDGE_OWNER.target == idx then BRIDGE_OWNER.target = nil end
              if BRIDGE_OWNER.focus == idx then BRIDGE_OWNER.focus = nil end
            end
            if updateReason == "destroyed" and UnitIsConfirmedDead(unit) then
              ClearIdxState(idx)
            elseif m and m.slots then
              -- Drop the frozen "shown" flags. Running DR timers keep going,
              -- like sArena's, and expire on their own; an icon with NO timer
              -- has nothing left to say about an enemy we cannot see.
              for s = 1, MAX_DR_SLOTS do
                local slot = m.slots[s]
                if slot then
                  slot._mdr_src_shown = false
                  if not slot._mdr_dr_active and slot.frame then slot.frame:Hide() end
                end
              end
              ReflowDRSlots(idx)
            end
          end
          break
        end
      end
    end
    UpdateAll()
  end)
  self:RegisterEvent("GROUP_ROSTER_UPDATE", function() UpdateAll() end)

  -- 0.25s ticker keeps frames positioned even when events are missed, and
  -- drives SyncSlotVisibility to restore timers after vanish effects.
  self._mdr_ticker = C_Timer.NewTicker(0.25, function() UpdateAll() end)

  UpdateAll()
end

-- Called by the settings UI
function Arena:OnConfigChanged()
  pcall(UpdateAll)
  pcall(ResyncAllBorders)
end

-- Prints diagnostic info for the /dr debug command.
function Arena:Debug()
  print("|cff00ff00MidnightDiminish:|r arena DR diagnostic")
  pcall(ResolveBridgeOwners)
  print(("  bridge owners: target=%s focus=%s"):format(
    tostring(BRIDGE_OWNER.target), tostring(BRIDGE_OWNER.focus)))
  local ok1, v1 = pcall(C_CVar.GetCVar, "spellDiminishPVPEnemiesEnabled")
  local ok2, v2 = pcall(C_CVar.GetCVar, "spellDiminishPVPOnlyTriggerableByMe")
  print(("  CVars: enemiesEnabled=%s onlyMine=%s"):format(
    ok1 and tostring(v1) or "?", ok2 and tostring(v2) or "?"))
  print("  in arena instance: " .. tostring(IsArenaInstance()))
  print(("  target: name=%s guid=%s | focus: name=%s guid=%s"):format(
    tostring(SafeUnitName("target")), tostring(SafeUnitGUID("target") ~= nil),
    tostring(SafeUnitName("focus")),  tostring(SafeUnitGUID("focus") ~= nil)))

  for i = 1, 5 do
    local unit = "arena" .. i
    if UnitMaybeExists(unit) or GetArenaMember(i) then
      local member = GetArenaMember(i)
      local tray = GetDRTray(i)
      local items = tray and #SafeChildren(tray) or 0
      local m = DR_MIRROR[i]
      local shownSlots = 0
      if m and m.slots then
        for s = 1, MAX_DR_SLOTS do
          local slot = m.slots[s]
          if slot and slot.frame and slot.frame:IsShown() then shownSlots = shownSlots + 1 end
        end
      end
      print(("  %s: member=%s tray=%s items=%d name=%s isUnit=%s | isTarget=%s isFocus=%s shown=%d"):format(
        unit, tostring(member ~= nil), tostring(tray ~= nil), items,
        tostring(SafeUnitName(unit)), tostring(SafeUnitIsUnit("target", unit)),
        tostring(BRIDGE_OWNER.target == i), tostring(BRIDGE_OWNER.focus == i),
        shownSlots))
    end
  end
end
