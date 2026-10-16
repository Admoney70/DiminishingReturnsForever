-- Modules/WorldDR.lua
-- Open-world PvP DR icons on the target frame:
--   • Tracks CC the PLAYER lands on the current target (spell-cast based)
--   • sArena-style 3-stage severity: green = next is ½, yellow = next is ¼,
--     red = next is immune — shown via border color and the ½/¼/% text
--   • World zones only (arena has its own module)

local ADDON, ns = ...
local Util = ns.Util
if not Util then return end -- stale .toc; Core.lua already warned

local Core = ns.Core
if not (Core and Core.NewModule) then return end

local WP = Core:GetModule("WorldDR", true) or Core:NewModule("WorldDR", "AceEvent-3.0")
ns.WorldDR = WP

local IsForbidden         = Util.IsForbidden
local GetSpellTextureSafe = Util.GetSpellTextureSafe

local function IsWorld()
  local _, it = IsInInstance()
  return it == "none"
end

local function DB()
  return Core.arenaDB and Core.arenaDB.profile and Core.arenaDB.profile.arena or nil
end

local function WPSettings()
  local a = DB()
  return a and a.world_dr or {}
end

local function ResetTime()
  local a = DB()
  local t = a and tonumber(a.dr_reset_time)
  if t and t >= 15 and t <= 20 then return t end
  return 20
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Severity: Midnight DR has two applications.
--   1/2 = first application (next is halved), green
--   2/2 = second application (next is immune), red
-- ─────────────────────────────────────────────────────────────────────────────
local SEVERITY_COLOR = {
  [1] = { 0, 1, 0 },
  [2] = { 1, 0, 0 },
}
local SEVERITY_TEXT = { [1] = "1/2", [2] = "2/2" }
local SEVERITY_MAX  = 2

-- ─────────────────────────────────────────────────────────────────────────────
-- Spell tables
-- ─────────────────────────────────────────────────────────────────────────────
local SPELLS = {
  stun = {
    [408] = 5.0, [853] = 5.0, [1833] = 4.0, [5211] = 4.0, [19577] = 3.0,
    [20549] = 3.0, [24394] = 3.0, [30283] = 3.0, [46968] = 3.0, [64044] = 3.0,
    [89766] = 3.0, [91797] = 3.0, [91800] = 3.0, [107570] = 3.0, [108194] = 3.0,
    [109248] = 3.0, [117526] = 3.0, [118345] = 3.0, [118905] = 3.0, [119381] = 5.0,
    [132168] = 3.0, [132169] = 3.0, [145047] = 3.0, [163505] = 4.0, [171017] = 3.0,
    [171018] = 3.0, [179057] = 4.0, [199085] = 3.0, [200166] = 3.0, [200200] = 3.0,
    [202244] = 3.0, [202346] = 3.0, [203123] = 3.0, [205630] = 3.0, [208618] = 3.0,
    [210141] = 3.0, [211881] = 3.0, [221562] = 3.0, [255723] = 3.0, [255941] = 3.0,
    [287254] = 3.0, [287712] = 3.0, [305485] = 3.0, [325321] = 3.0, [332423] = 3.0,
    [357021] = 3.0, [372245] = 3.0, [377048] = 3.0, [385954] = 3.0, [389831] = 3.0,
    [357210] = 3.0, [408544] = 3.0, [458605] = 3.0,
  },
  incap = {
    [99] = 3.0, [118] = 6.0, [710] = 6.0, [1776] = 3.0, [2637] = 6.0,
    [3355] = 6.0, [6770] = 6.0, [6789] = 3.0, [9484] = 6.0, [20066] = 6.0,
    [28271] = 6.0, [28272] = 6.0, [51514] = 6.0, [61025] = 6.0, [61305] = 6.0,
    [61721] = 6.0, [61780] = 6.0, [82691] = 6.0, [107079] = 6.0, [115078] = 3.0,
    [126819] = 6.0, [161353] = 6.0, [161354] = 6.0, [161355] = 6.0, [161372] = 6.0,
    [196942] = 6.0, [197214] = 6.0, [200196] = 3.0, [203337] = 6.0, [210873] = 6.0,
    [211004] = 6.0, [211010] = 6.0, [211015] = 6.0, [213691] = 6.0, [217832] = 3.0,
    [221527] = 6.0, [269352] = 6.0, [277778] = 6.0, [277784] = 6.0, [277787] = 6.0,
    [277792] = 6.0, [309328] = 6.0, [321395] = 6.0, [357768] = 6.0, [378441] = 6.0,
    [383121] = 6.0, [391622] = 6.0, [460396] = 6.0, [461489] = 6.0,
  },
  fear = {
    [605] = 6.0, [1513] = 6.0, [2094] = 5.0, [5246] = 5.0, [5484] = 6.0,
    [5782] = 6.0, [6358] = 6.0, [8122] = 6.0, [10326] = 6.0, [31661] = 4.0,
    [33786] = 5.0, [105421] = 6.0, [115750] = 4.0, [118699] = 6.0, [130616] = 6.0,
    [198909] = 6.0, [202274] = 6.0, [205364] = 6.0, [207167] = 4.0, [207685] = 6.0,
    [261589] = 6.0, [316593] = 6.0, [316595] = 6.0, [324263] = 6.0, [331866] = 6.0,
    [360806] = 6.0,
  },
  root = {
    [122] = 6.0, [339] = 6.0, [33395] = 6.0, [39965] = 6.0, [55536] = 6.0,
    [64695] = 6.0, [75148] = 6.0, [102359] = 6.0, [114404] = 6.0, [116706] = 6.0,
    [162480] = 6.0, [170855] = 6.0, [190927] = 6.0, [199042] = 6.0, [201158] = 6.0,
    [204085] = 6.0, [212638] = 6.0, [233395] = 6.0, [235963] = 6.0, [268966] = 6.0,
    [285515] = 6.0, [324382] = 6.0, [342375] = 6.0, [355689] = 6.0, [356356] = 6.0,
    [356738] = 6.0, [378760] = 6.0, [386770] = 6.0, [393456] = 6.0, [454787] = 6.0,
  },
}

-- World PvP only tracks stun, incap, fear, root (silence/disarm don't apply)
local CATEGORY_ORDER = { "stun", "incap", "fear", "root" }
local CATEGORY_FALLBACK_ICON = {
  stun  = 132298,
  incap = 136071,
  fear  = 136183,
  root  = 136100,
}

local SPELL_MAP = {}
for cat, tbl in pairs(SPELLS) do
  for spellID, dur in pairs(tbl) do
    SPELL_MAP[spellID] = { cat = cat, dur = dur }
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────────────────────
local active = {}   -- [guid][cat] = { start, finish, severity, spellID, tex }
local ticker        -- C_Timer ticker

-- Two rows, both fed by the SAME DR state: kind "frame" on the Target frame
-- and kind "plate" on the target's nameplate. With "Show on Both" they always
-- agree because they read the same entries.
local widgets = {}  -- [kind] = widget
local KINDS = { "frame", "plate" }

-- Where rows are drawn. "Show on Both" overrides the anchor toggle.
local function KindEnabled(kind)
  local cfg = WPSettings()
  if kind == "plate" then
    return cfg.anchor_nameplate == true or cfg.np_both == true
  end
  return cfg.anchor_nameplate ~= true or cfg.np_both == true
end

-- What a row anchors to, or nil when there is nothing to sit on (no target,
-- or its plate is off screen / forbidden).
local function AnchorFor(kind)
  if kind == "plate" then return Util.GetUnitNameplate("target") end
  local tf = _G.TargetFrame
  if not tf then return nil end
  if IsForbidden(tf) then return nil end
  if not tf:IsShown() then return nil end
  return tf
end

local function HideAll()
  for _, w in pairs(widgets) do w:Hide() end
end

local function AnyDragging()
  for _, w in pairs(widgets) do
    if w._mdr_dragging then return true end
  end
  return false
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Test-mode drag support
-- ─────────────────────────────────────────────────────────────────────────────

-- Converts a dragged row's position back into the offsets the sliders use.
-- Frame rows write the frame offsets, plate rows the nameplate offsets.
local function SaveDragPosition(w)
  local tf = w and AnchorFor(w.kind)
  if not tf then return end

  local wx, wy = w:GetCenter()
  local tx, ty = tf:GetCenter()
  if not (wx and wy and tx and ty) then return end
  local ws, ts = w:GetEffectiveScale(), tf:GetEffectiveScale()

  local a = DB()
  if not a then return end
  a.world_dr = a.world_dr or {}

  if w.kind == "plate" then
    -- Inverse of ApplyLayout for whichever nameplate grow mode is active.
    local mode = w._npGrow or "CENTER"
    local half = (w._npSize or 22) / 2
    local gap  = w._npSpacing or 2
    local nx, ny
    if mode == "LTR" then
      local right = tf:GetRight()
      if not right then return end
      nx = (wx * ws - right * ts) / ws - gap - half
      ny = (wy * ws - ty * ts) / ws
    elseif mode == "RTL" then
      local left = tf:GetLeft()
      if not left then return end
      nx = (wx * ws - left * ts) / ws + gap + half
      ny = (wy * ws - ty * ts) / ws
    else
      local top = tf:GetTop()
      if not top then return end
      nx = (wx * ws - tx * ts) / ws - (w._npShift or 0)
      ny = (wy * ws - top * ts) / ws - half
    end
    a.world_dr.np_pos_x = Util.Clamp(math.floor(nx + 0.5), -300, 300)
    a.world_dr.np_pos_y = Util.Clamp(math.floor(ny + 0.5), -200, 200)
  else
    -- Offsets are in the widget's (scaled) space: CENTER -> target CENTER.
    a.world_dr.pos_x = Util.Clamp(math.floor((wx * ws - tx * ts) / ws + 0.5), -300, 300)
    a.world_dr.pos_y = Util.Clamp(math.floor((wy * ws - ty * ts) / ws + 0.5), -200, 200)
  end

  Core:NotifyOptionsChanged()
end

-- Icons only react to the mouse while test mode is active.
local function SetDragEnabled(w, enabled)
  if not w then return end
  if w._mdr_drag_enabled == enabled then return end
  w._mdr_drag_enabled = enabled
  for _, f in ipairs(w.icons) do
    f:EnableMouse(enabled)
  end
end

local function SetDragEnabledAll(enabled)
  for _, w in pairs(widgets) do SetDragEnabled(w, enabled) end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Borders
-- ─────────────────────────────────────────────────────────────────────────────
local function BorderOpts()
  local cfg = WPSettings()
  return {
    style       = cfg.border_style or "GLOW",
    black       = cfg.border_black == true,
    border_size = tonumber(cfg.border_size) or 1,
    pixel_size  = tonumber(cfg.pixel_border_size) or 2,
    r = 0, g = 1, b = 0,
  }
end

local function ResyncBorders()
  local opts = BorderOpts()
  for _, w in pairs(widgets) do
    for _, f in ipairs(w.icons) do
      f.drBorder:Configure(opts)
    end
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Widget creation (one per kind)
-- ─────────────────────────────────────────────────────────────────────────────
local function EnsureWidget(kind)
  local w = widgets[kind]
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
  w._mdr_drag_enabled = false
  w:Hide()
  w.icons = {}
  w.kind = kind

  for i = 1, 4 do
    local f = CreateFrame("Frame", nil, w)
    f:SetSize(22, 22)
    f:SetFrameStrata(strata)
    f:SetFrameLevel(w:GetFrameLevel() + 1)
    f:EnableMouse(false)

    f.texture = f:CreateTexture(nil, "ARTWORK")
    f.texture:SetAllPoints()
    -- sArena-style icon crop
    f.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown:SetAllPoints()
    f.cooldown:SetDrawEdge(false)
    f.cooldown:SetDrawSwipe(true)
    f.cooldown:SetReverse(true)
    f.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    f.cooldown:SetHideCountdownNumbers(true)
    f.cooldown:SetFrameLevel(f:GetFrameLevel() + 1)

    -- Text holder above cooldown swipe (remaining time)
    f.textHolder = CreateFrame("Frame", nil, f)
    f.textHolder:SetAllPoints()
    f.textHolder:SetFrameStrata(f:GetFrameStrata())
    f.textHolder:SetFrameLevel(f:GetFrameLevel() + 10)

    f.text = f.textHolder:CreateFontString(nil, "OVERLAY")
    f.text:SetDrawLayer("OVERLAY", 7)
    f.text:SetPoint("CENTER", f.textHolder, "CENTER", 0, 0)
    f.text:SetJustifyH("CENTER")
    f.text:SetJustifyV("MIDDLE")

    -- DR stage text (1/2, 2/2) bottom-right, sArena style
    f.drText = f.textHolder:CreateFontString(nil, "OVERLAY")
    f.drText:SetDrawLayer("OVERLAY", 7)
    f.drText:SetPoint("BOTTOMRIGHT", f.textHolder, "BOTTOMRIGHT", 4, -4)
    f.drText:SetJustifyH("RIGHT")
    f.drText:SetJustifyV("BOTTOM")

    -- Stage border (green = 1/2, red = 2/2)
    f.borderFrame = CreateFrame("Frame", nil, f)
    f.borderFrame:SetAllPoints()
    f.borderFrame:SetFrameStrata(f:GetFrameStrata())
    f.borderFrame:SetFrameLevel(f:GetFrameLevel() + 5)
    f.drBorder = Util.CreateDRBorder(f.borderFrame)

    -- Test-mode drag: dragging any icon moves the whole row
    if kind ~= "plate" then
      f:RegisterForDrag("LeftButton")
      f:SetScript("OnDragStart", function()
        w._mdr_dragging = true
        w:StartMoving()
      end)
      f:SetScript("OnDragStop", function()
        w:StopMovingOrSizing()
        w._mdr_dragging = false
        SaveDragPosition(w)
      end)
    end

    f:Hide()
    w.icons[i] = f
  end

  widgets[kind] = w
  ResyncBorders()
  return w
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Layout
-- ─────────────────────────────────────────────────────────────────────────────
local function ApplyLayout(w, anchor, count)
  if not w or not anchor then return end
  local cfg = WPSettings()

  local size     = tonumber(cfg.icon_size)  or 26
  local spacing  = tonumber(cfg.spacing)    or 2
  local px       = tonumber(cfg.pos_x)      or 0
  local py       = tonumber(cfg.pos_y)      or 20
  local grow     = cfg.grow                 or "RIGHT"
  local fontSize = tonumber(cfg.font_size)  or 12

  w:ClearAllPoints()
  if w.kind == "plate" then
    local nx = tonumber(cfg.np_pos_x) or 0
    local ny = tonumber(cfg.np_pos_y) or 10
    local npGrow = cfg.np_grow or "CENTER"
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
      -- Centre the VISIBLE icons over the plate (icon 1 sits at the widget's
      -- centre and the rest grow away from it), and lift the row so its
      -- bottom edge rests np_pos_y above the plate's top.
      local step  = size + spacing
      local n     = math.max(1, count or 1)
      local shift = 0
      if grow == "RIGHT" then shift = -(n - 1) * step / 2
      elseif grow == "LEFT" then shift = (n - 1) * step / 2 end
      w._npShift = shift
      w:SetPoint("CENTER", anchor, "TOP", nx + shift, ny + size / 2)
    end
    -- Plates scale with distance; keep the icons at the size you configured.
    w:SetScale(1)
  else
    w:SetPoint("CENTER", anchor, "CENTER", px, py)
    local us = (anchor.GetEffectiveScale and anchor:GetEffectiveScale()) or 1
    local ps = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    local sc = us / ps
    if sc < 0.1 then sc = 0.1 elseif sc > 10 then sc = 10 end
    w:SetScale(sc)
  end
  w:SetAlpha(1)

  local reverse = cfg.reverse_swipe ~= false
  local drawSwipe = cfg.disable_swipe ~= true

  local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  for i, f in ipairs(w.icons) do
    f:SetSize(size, size)
    f.text:SetFont(fontPath, fontSize, "OUTLINE")
    f.drText:SetFont(fontPath, fontSize, "OUTLINE")

    f.cooldown:SetReverse(reverse)
    f.cooldown:SetDrawSwipe(drawSwipe)

    f:ClearAllPoints()
    local dx, dy = 0, 0
    if     grow == "LEFT"  then dx = -(i-1) * (size + spacing)
    elseif grow == "UP"    then dy =  (i-1) * (size + spacing)
    elseif grow == "DOWN"  then dy = -(i-1) * (size + spacing)
    else   dx = (i-1) * (size + spacing) end
    f:SetPoint("CENTER", w, "CENTER", dx, dy)
  end
end

local function ClearWidgetIcons(w)
  if not w then return end
  for _, f in ipairs(w.icons) do
    f:Hide()
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Render
-- ─────────────────────────────────────────────────────────────────────────────
local function FormatRemaining(rem, showDecimals, threshold)
  if type(rem) ~= "number" or rem <= 0 then return nil end
  if showDecimals and rem < threshold then
    if rem < 0.1 then rem = 0.1 end
    return string.format("%.1f", math.floor(rem * 10) / 10)
  end
  return tostring(math.floor(rem))
end

-- Draws `states` onto one row.
local function RenderStates(kind, anchor, states)
  local w = EnsureWidget(kind)
  if not w then return end

  local cfg = WPSettings()

  local visible, nowCount = 0, GetTime()
  for _, cat in ipairs(CATEGORY_ORDER) do
    local st = states and states[cat]
    if st and st.finish and st.finish > nowCount then visible = visible + 1 end
  end

  ApplyLayout(w, anchor, math.min(visible, 4))
  ClearWidgetIcons(w)

  local showDRText   = cfg.show_dr_text ~= false
  local colorCDText  = cfg.color_cd_text ~= false
  local showDecimals = cfg.show_decimals ~= false
  local threshold    = tonumber(cfg.decimal_threshold) or 3

  local now = GetTime()
  local shown = 0

  for _, cat in ipairs(CATEGORY_ORDER) do
    if shown >= 4 then break end
    local st = states and states[cat]
    if st and st.finish and st.finish > now then
      shown = shown + 1
      local f = w.icons[shown]
      if f then
        local tex = st.tex or GetSpellTextureSafe(st.spellID) or CATEGORY_FALLBACK_ICON[cat]
        if tex then f.texture:SetTexture(tex) end

        local dur = st.finish - st.start; if dur < 0 then dur = 0 end
        f.cooldown:SetCooldown(st.start, dur)

        local rem = st.finish - now; if rem < 0 then rem = 0 end
        f.text:SetText(FormatRemaining(rem, showDecimals, threshold) or "")

        local sev = Util.Clamp(tonumber(st.severity) or 1, 1, SEVERITY_MAX)
        local c = SEVERITY_COLOR[sev]

        f.drBorder:SetStateColor(c[1], c[2], c[3])

        if showDRText then
          f.drText:SetText(SEVERITY_TEXT[sev])
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

  if shown > 0 then w:Show() else w:Hide() end
end

-- Draws `states` on every enabled row; hides rows with nothing to sit on.
local function RenderRows(states)
  for _, kind in ipairs(KINDS) do
    local anchor = KindEnabled(kind) and AnchorFor(kind) or nil
    if anchor then
      RenderStates(kind, anchor, states)
    elseif widgets[kind] then
      SetDragEnabled(widgets[kind], false)
      widgets[kind]:Hide()
    end
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Test mode
-- ─────────────────────────────────────────────────────────────────────────────
local function RenderTest()
  local cfg = WPSettings()
  if not cfg.test_enabled then
    SetDragEnabledAll(false)
    HideAll()
    return
  end

  -- Test preview: one icon for EVERY tracked category (minus any you have
  -- switched off under Tracked Categories, so the preview matches what you
  -- will see), alternating 1/2 (green) and 2/2 (red).
  local now   = GetTime()
  local cats  = cfg.categories
  local states = {}
  for idx, cat in ipairs(CATEGORY_ORDER) do
    if type(cats) ~= "table" or cats[cat] ~= false then
      states[cat] = {
        start    = now - 1,
        finish   = now + 18 - idx,
        spellID  = nil,
        tex      = CATEGORY_FALLBACK_ICON[cat],
        severity = (idx % 2 == 1) and 1 or 2,
      }
    end
  end
  RenderRows(states)

  -- Only rows that are actually showing take the mouse (for dragging).
  for _, w in pairs(widgets) do
    SetDragEnabled(w, w.kind ~= "plate" and w:IsShown())
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Tick (periodic update)
-- ─────────────────────────────────────────────────────────────────────────────
local function CleanupExpired()
  local now = GetTime()
  for guid, cats in pairs(active) do
    local any = false
    for cat, st in pairs(cats) do
      if not st.finish or st.finish <= now then
        cats[cat] = nil
      else
        any = true
      end
    end
    if not any then active[guid] = nil end
  end
end

local function Tick()
  -- Freeze rendering while the user drags a row in test mode
  if AnyDragging() then return end

  local cfg = WPSettings()
  if cfg.enabled == false then
    HideAll()
    return
  end

  RenderTest()
  if cfg.test_enabled then return end

  if not IsWorld() then
    HideAll()
    return
  end

  CleanupExpired()

  -- Only the current hostile target is displayed
  if UnitExists("target") and UnitCanAttack("player", "target") then
    local guid = UnitGUID("target")
    local states = guid and active[guid]
    if states and next(states) then
      RenderRows(states)
      return
    end
  end

  HideAll()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- DR recording
-- ─────────────────────────────────────────────────────────────────────────────
local function AddOrRefreshTimer(spellID, guid)
  local cfg = WPSettings()
  if cfg.enabled == false then return end

  local info = SPELL_MAP[spellID]
  if not info then return end
  local cat = info.cat

  -- Per-category enable toggles
  local cats = cfg.categories
  if type(cats) == "table" and cats[cat] == false then return end

  local now = GetTime()
  active[guid] = active[guid] or {}

  -- Two applications per window: 1 = full duration applied (next is
  -- halved), 2 = half applied (next is immune). No tracking past that.
  local st = active[guid][cat]
  local severity
  if st and st.finish and st.finish > now then
    local s = tonumber(st.severity) or 1
    if s >= SEVERITY_MAX then return end  -- target is immune to further applications
    severity = s + 1
  else
    severity = 1
  end

  local d = info.dur / (2 ^ (severity - 1))
  if d < 0.5 then d = 0.5 end
  local total = d + ResetTime()  -- aura duration + DR reset window

  local tex
  if cfg.static_icons then
    tex = CATEGORY_FALLBACK_ICON[cat]
  else
    tex = GetSpellTextureSafe(spellID) or CATEGORY_FALLBACK_ICON[cat]
  end

  active[guid][cat] = {
    start    = now,
    finish   = now + total,
    severity = severity,
    spellID  = spellID,
    tex      = tex,
  }

  -- Immediately render if this guid is the current target
  local targetGuid = UnitExists("target") and UnitGUID("target")
  if targetGuid == guid then
    RenderRows(active[guid])
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Module lifecycle
-- ─────────────────────────────────────────────────────────────────────────────
function WP:OnEnable()
  -- Deferred init escapes AceAddon's protected context
  C_Timer.After(0, function()
    if WP then WP:DeferredInit() end
  end)
end

function WP:OnDisable()
  self._wp_initialized = false
  self._wp_worldActive = false
  self:UnregisterAllEvents()
  if ticker then ticker:Cancel(); ticker = nil end
  HideAll()
end

function WP:DeferredInit()
  if self._wp_initialized then return end

  if not DB() then
    self._wp_initTries = (self._wp_initTries or 0) + 1
    if self._wp_initTries <= 20 then
      C_Timer.After(0.25, function()
        if WP and WP.DeferredInit then WP:DeferredInit() end
      end)
    end
    return
  end

  self._wp_initialized = true

  self:RegisterEvent("PLAYER_ENTERING_WORLD", "WP_ZoneChange")
  self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "WP_ZoneChange")

  self:EvaluateWorldMode(true)
end

function WP:StartWorldMode()
  if self._wp_worldActive then return end
  self._wp_worldActive = true

  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "WP_SpellcastSucceeded")

  if not ticker then
    ticker = C_Timer.NewTicker(0.05, Tick)
  end
  Tick()
end

function WP:StopWorldMode()
  self._wp_worldActive = false

  if ticker then ticker:Cancel(); ticker = nil end

  pcall(function() self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED") end)

  SetDragEnabledAll(false)
  HideAll()
end

function WP:EvaluateWorldMode(forceRescan)
  local cfg = WPSettings()
  if cfg.enabled == false then
    self:StopWorldMode()
    return
  end
  if not IsWorld() then
    if cfg.test_enabled then
      if not self._wp_worldActive then self:StartWorldMode() end
      return
    end
    self:StopWorldMode()
    return
  end

  self:StartWorldMode()
  if forceRescan then
    Tick()
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- AceEvent handlers
-- ─────────────────────────────────────────────────────────────────────────────
function WP:WP_ZoneChange()
  self:EvaluateWorldMode(true)
end

function WP:WP_SpellcastSucceeded(_, unit, _, spellID)
  if not self._wp_worldActive then return end
  if unit ~= "player" then return end
  if type(spellID) ~= "number" then return end
  if not IsWorld() then return end

  if not UnitExists("target") or not UnitCanAttack("player", "target") then return end

  local guid = UnitGUID("target")
  if type(guid) ~= "string" then return end

  AddOrRefreshTimer(spellID, guid)
end

-- Called by the settings UI
function WP:OnConfigChanged()
  self:EvaluateWorldMode(false)
  pcall(ResyncBorders)
  pcall(Tick)
end
