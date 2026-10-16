-- Adapted from Forever DR Display.lua (MIT, Copyright 2026 Tarolg).
-- Drpulse integration and visual adaptations: Copyright 2026 Joaqoz.
local _, ns = ...
-- Stage colors by meaning: the next CC in this category lasts 50% (yellow),
-- 25% (orange), or the target is immune to it (red).
local STAGE = { { 1, 0.82, 0 }, { 1, 0.5, 0 }, { 1, 0.13, 0.13 } }
local NEXT_TEXT = { "50%", "25%", "IMM" }
local SPACING = 5
local TICK = 0.1
local driver, target, strip
local plates, sparePlates = {}, {}
local refreshQueued, elapsed = false, 0
local previewUntil = 0
local redColor, stageColors
-- Defined under Driver; the resize grip redraws at once with it.
local Refresh

local function Stage(entry)
    if entry.immune then return 3 end
    return math.min(entry.count, 3)
end

local function Tooltip(icon)
    local e = icon.entry
    if not e then return end
    GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.CATEGORY_LABELS[e.category] or e.category)
    local stage = Stage(e)
    GameTooltip:AddLine(e.immune and (e.confirmed and "Immune to this category" or "Estimated immunity (landing unconfirmed)") or
        ("Next " .. (ns.CATEGORY_LABELS[e.category] or e.category) .. " lasts " .. NEXT_TEXT[stage]), 1, 1, 1)
    GameTooltip:AddLine("Applications: " .. e.count, 0.85, 0.85, 0.85)
    GameTooltip:AddLine(string.format("Resets in %.1f s%s", math.max(0, e.remaining), e.estimated and " (estimated)" or ""), 0.85, 0.85, 0.85)
    if e.spellID then GameTooltip:AddLine("Last: " .. ns.SpellName(e.spellID), 0.85, 0.85, 0.85) end
    GameTooltip:AddLine("Evidence: " .. (e.source or "unknown") .. (e.confirmed and "" or " (landing unconfirmed)"), 0.65, 0.65, 0.65)
    GameTooltip:Show()
end

local function NewIcon(parent, tooltips)
    local icon = CreateFrame("Frame", nil, parent)
    -- Drpulse shell: quiet navy frame, cyan identity, semantic status rail.
    icon.shell = icon:CreateTexture(nil, "BACKGROUND")
    icon.shell:SetAllPoints()
    icon.shell:SetColorTexture(0.035, 0.06, 0.085, 0.98)
    icon.border = icon:CreateTexture(nil, "BORDER")
    icon.border:SetPoint("BOTTOMLEFT", 1, 0)
    icon.border:SetPoint("BOTTOMRIGHT", -1, 0)
    icon.border:SetHeight(2)
    icon.border:SetColorTexture(1, 1, 1, 1)
    icon.accent = icon:CreateTexture(nil, "BORDER")
    icon.accent:SetPoint("TOPLEFT", 1, 0)
    icon.accent:SetSize(7, 2)
    icon.accent:SetColorTexture(0.38, 0.85, 1, 1)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetPoint("TOPLEFT", 2, -2)
    icon.texture:SetPoint("BOTTOMRIGHT", -2, 3)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints(icon.texture)
    icon.cooldown:SetHideCountdownNumbers(true)
    icon.cooldown:SetDrawEdge(false)
    icon.cooldown:SetReverse(true)
    icon.cooldown:SetSwipeColor(0, 0, 0, 0.65)
    local overlay = CreateFrame("Frame", nil, icon)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(icon.cooldown:GetFrameLevel() + 2)
    icon.time = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    icon.time:SetPoint("CENTER", 0, 1)
    icon.time:SetShadowColor(0, 0, 0, 1)
    icon.time:SetShadowOffset(1, -1)
    icon.count = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    icon.count:SetPoint("TOPRIGHT", -1, -1)
    icon.next = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    icon.next:SetPoint("BOTTOM", 0, 3)
    icon.pipBackdrop = overlay:CreateTexture(nil, "ARTWORK")
    icon.pipBackdrop:SetPoint("BOTTOMLEFT", 1, 2)
    icon.pipBackdrop:SetPoint("BOTTOMRIGHT", -1, 2)
    icon.pipBackdrop:SetColorTexture(0.015, 0.025, 0.035, 0.96)
    icon.pips = {}
    for i = 1, 3 do
        local pip = overlay:CreateTexture(nil, "OVERLAY")
        pip:SetColorTexture(1, 1, 1, 1)
        icon.pips[i] = pip
    end
    if tooltips then
        icon:EnableMouse(true)
        icon:SetMouseClickEnabled(false)
        icon:SetScript("OnEnter", Tooltip)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        icon:EnableMouse(false)
    end
    icon:Hide()
    return icon
end

local function StyleIcon(icon, size)
    icon:SetSize(size, size)
    icon.defaultFont = icon.defaultFont or icon.time:GetFont()
    local font = ns.FONT_PATHS[ns.db.font] or icon.defaultFont
    local timeSize = math.max(8, math.floor(size * 0.42))
    local smallSize = math.max(7, math.floor(size * 0.3))
    for _, region in ipairs({ icon.time, icon.count, icon.next }) do
        local fontSize = region == icon.time and timeSize or smallSize
        if not region:SetFont(font, fontSize, "OUTLINE") then
            region:SetFont(icon.defaultFont, fontSize, "OUTLINE")
        end
    end
    local gap = size >= 20 and 2 or 1
    local width = math.max(2, math.floor((size - 6 - 2 * gap) / 3))
    local height = math.max(3, math.min(7, math.floor(size * 0.16)))
    local left = math.floor((size - (3 * width + 2 * gap)) / 2)
    icon.pipBackdrop:SetHeight(height + 4)
    for i, texture in ipairs(icon.pips) do
        texture:SetSize(width, height)
        texture:ClearAllPoints()
        texture:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", left + (i - 1) * (width + gap), 4)
    end
end

local function FormatTime(seconds)
    if seconds >= 10 then return tostring(math.ceil(seconds)) end
    return string.format("%.1f", math.max(0, seconds))
end

-- still: a sample's still picture. Its swipe is paused before SetCooldown, as
-- Blizzard's CooldownFrame_SetDisplayAsPercentage (Blizzard_FrameXMLUtil/
-- Cooldown.lua) does; a live draw resumes first, so a live swipe never stays
-- frozen in a pooled icon.
local function UpdateIcon(icon, e, guid, still)
    icon.entry = e
    still = still == true
    if (icon.still == true) ~= still then
        if still then icon.cooldown:Pause() else icon.cooldown:Resume() end
        icon.still = still
    end
    local db = ns.db
    local icons = db.iconSource == "spell" and e.spellID and ns.SpellIcon(e.spellID)
    icon.texture:SetTexture(icons or ns.CategoryIcon(e.category))
    local stage = Stage(e)
    local color = STAGE[stage]
    local secret = guid and not e.immune and ns.secretImmune[guid .. ":" .. e.category]
    if secret and secret.resetAt == e.resetAt then
        icon.border:SetVertexColorFromBoolean(secret.box.value, redColor, stageColors[stage])
    else
        icon.border:SetVertexColor(color[1], color[2], color[3], 1)
    end
    icon.texture:SetDesaturated(e.immune)
    -- Timer: seconds until the category resets. Grey while any part is estimated.
    if db.timer then
        icon.time:SetText((e.estimated and "~" or "") .. FormatTime(e.remaining))
        if e.estimated then icon.time:SetTextColor(0.72, 0.79, 0.84) else icon.time:SetTextColor(0.96, 0.99, 1) end
        icon.time:Show()
    else icon.time:Hide() end
    local style = db.stackStyle
    icon.pipBackdrop:SetShown(style == "pips")
    icon.count:SetShown(style == "number")
    icon.count:SetText(e.immune and "!" or tostring(math.min(e.count, 9)))
    icon.count:SetTextColor(color[1], color[2], color[3])
    icon.next:SetShown(style == "next")
    icon.next:SetText(NEXT_TEXT[stage])
    icon.next:SetTextColor(color[1], color[2], color[3])
    for i, pip in ipairs(icon.pips) do
        pip:SetShown(style == "pips" and i <= stage)
        pip:SetVertexColor(color[1], color[2], color[3], 1)
    end
    -- Only public numbers from the tracker ever reach the cooldown swipe.
    if db.swipe and not e.active and e.windowLength > 0 then
        if icon.swipeStart ~= e.windowStart or icon.swipeLength ~= e.windowLength then
            icon.cooldown:SetCooldown(e.windowStart, e.windowLength)
            icon.swipeStart, icon.swipeLength = e.windowStart, e.windowLength
        end
        icon.cooldown:Show()
    elseif icon.swipeStart then
        icon.cooldown:Clear()
        icon.swipeStart, icon.swipeLength = nil, nil
    end
    icon:Show()
end

local function Filter(list)
    if not list then return nil end
    local shown
    for _, e in ipairs(list) do
        if ns.ShouldShow(e.category) then shown = shown or {}; shown[#shown + 1] = e end
    end
    return shown
end

local function LayoutRow(row, entries, size, guid, tooltips, still)
    row.icons = row.icons or {}
    local count = entries and #entries or 0
    for index = 1, count do
        local icon = row.icons[index]
        if not icon then icon = NewIcon(row, tooltips); row.icons[index] = icon end
        if icon.size ~= size or icon.font ~= ns.db.font then
            StyleIcon(icon, size)
            icon.size, icon.font = size, ns.db.font
        end
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", row, "LEFT", (index - 1) * (size + SPACING), 0)
        UpdateIcon(icon, entries[index], guid, still)
    end
    for index = count + 1, #row.icons do row.icons[index]:Hide(); row.icons[index].entry = nil end
    row:SetSize(math.max(1, count * (size + SPACING) - SPACING), size)
    return count
end
-- The settings page's previews (0.5.0) draw their sample rows with the same
-- code as the target display and the plates: LayoutRow (guid nil, so the
-- secret immune border is never involved) and PlaceRow.
ns.LayoutRow = LayoutRow
ns.ICON_SPACING = SPACING

-- The settings page's samples (0.5.0): your target with Stun at 50%,
-- Incapacitate at 25% and Disorient immune, each confirmed and counting down
-- to its reset, and apart an unconfirmed cast, whose timer is grey (Show
-- unconfirmed casts). started: when the preview's loop began, each sample
-- then having left seconds to its reset and dropping out once reset, as a
-- live category does; nil for the still picture (still seconds left). The
-- last spells are not the categories' own icons (CATEGORY_ICON_SPELLS), so
-- Icon: Last spell or Category shows a difference.
local SETTINGS_SAMPLES = {
    { category = "Stun", count = 1, spellID = 853, left = 6, still = 14 },         -- Hammer of Justice
    { category = "Incapacitate", count = 2, spellID = 6770, left = 4.5, still = 9 }, -- Sap
    { category = "Disorient", count = 3, immune = true, spellID = 5484, left = 7.5, still = 16 }, -- Howl of Terror
}
local UNCONFIRMED_SAMPLE = { category = "Root", count = 1, spellID = 339, left = 5, still = 11, estimated = true } -- Entangling Roots
-- How long the loop runs: the last sample resets just before.
ns.SETTINGS_SAMPLE_LOOP = 8
function ns.SettingsSamples(now, started)
    local window = ns.db and ns.db.resetTime or 18
    local function Make(spec)
        local resetAt = started and (started + spec.left) or (now + spec.still)
        if resetAt <= now then return nil end
        return { category = spec.category, count = spec.count, immune = spec.immune == true, remaining = resetAt - now,
            resetAt = resetAt, windowStart = resetAt - window, windowLength = window, estimated = spec.estimated == true,
            confirmed = spec.estimated ~= true, active = false, spellID = spec.spellID, source = "preview" }
    end
    local target = {}
    for _, spec in ipairs(SETTINGS_SAMPLES) do
        local entry = Make(spec)
        if entry then target[#target + 1] = entry end
    end
    return target, Make(UNCONFIRMED_SAMPLE)
end

-- Target display --------------------------------------------------------------
-- 0.8.0 (the user's choice of 11 October 2026, shared with Forever Cooldowns'
-- bars and Forever Enemy Buffs' Target's buffs bar): locked, the display is
-- its icons only, click-through but for their tooltips, and hidden while
-- there is nothing to show. Unlocked, a thin strip sits just above the icons:
-- a 1-pixel gold edge around a dark fill, the name "Target DR" in gold at its
-- left and the gear at its right end, nothing else. Sample icons count down
-- and loop under it, a grip of six dots at the bar's bottom right corner
-- drags the target icon size, the strip or the bar drags the display (out of
-- combat), and a right-click locks it. Before 0.8.0 the strip read "Target
-- DR - drag, right-click to lock" and the samples stood still; those words
-- are now the strip's tooltip.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local STRIP_NAME = "DRPULSE / TARGET"
local STRIP_H, STRIP_GAP = 14, 2
local STRIP_EDGE = { 0.24, 0.65, 0.82 }
local STRIP_FILL = { 0.075, 0.08, 0.09, 0.75 }
local TEXT_GOLD = { 0.38, 0.85, 1.00 }
-- Blizzard's menu gear (MenuVariants.GearButtonTexture, Blizzard_Menu/
-- MenuVariants.lua) on a flat button inside the strip's edge.
local GEAR_ART = "Interface\\WorldMap\\GEAR_64GREY"
local GEAR = 12
-- The grip: six 2x2 dots, grey, gold on hover, as Forever Threat's.
local GRIP = 12
local GRIP_DOTS = { { 0, 0 }, { 4, 0 }, { 8, 0 }, { 0, 4 }, { 4, 4 }, { 0, 8 } }
local GRIP_GREY, GRIP_GOLD = { 0.55, 0.55, 0.58 }, { 0.38, 0.85, 1.00 }
local GRIP_HINT = "Drag to resize. Double-click to reset to the default size."
-- How many icons the display drew last (the grip shares a drag's width out
-- over them), and when the samples' loop began (nil while none show).
local drawnCount, sampleStart = 0, nil

-- The samples on the real display, t seconds into their loop: the settings
-- page's own (ns.SettingsSamples), counting down to their resets and starting
-- again once the loop has run.
local function Samples(now)
    if not sampleStart or now - sampleStart >= ns.SETTINGS_SAMPLE_LOOP then sampleStart = now end
    return (ns.SettingsSamples(now, sampleStart))
end

local function SavePosition()
    target:StopMovingOrSizing()
    target.moving = false
    local x, y = target:GetCenter()
    local px, py = UIParent:GetCenter()
    if ns.Number(x) and ns.Number(y) and ns.Number(px) and ns.Number(py) then
        -- Keep within the saved-setting limits: a value outside them would
        -- fail validation on the next load and pause the addon.
        local limitX, limitY = ns.LIMITS.x, ns.LIMITS.y
        ns.db.x = math.max(limitX[1], math.min(limitX[2], math.floor(x - px + 0.5)))
        ns.db.y = math.max(limitY[1], math.min(limitY[2], math.floor(y - py + 0.5)))
    end
    ns.PositionTarget()
end

function ns.PositionTarget()
    if not target then return end
    target:ClearAllPoints()
    target:SetPoint("CENTER", UIParent, "CENTER", ns.db.x, ns.db.y)
end

-- Moving: from the strip or the bar, unlocked and out of combat, as before.
local function StartMove()
    if ns.db.locked or InCombatLockdown() or target.moving then return end
    target.moving = true
    target:StartMoving()
end
local function StopMove()
    if target.moving then SavePosition() end
end

-- The bar's own tooltip lists only how to control it (AGENTS.md window
-- format), each line only while it works: no drag in combat.
local function ShowBarTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText("Drpulse")
    if not InCombatLockdown() then GameTooltip:AddLine("Drag: move", 0.85, 0.85, 0.85) end
    GameTooltip:AddLine("Drag the corner: resize", 0.85, 0.85, 0.85)
    GameTooltip:AddLine("Right-click: lock", 0.85, 0.85, 0.85)
    GameTooltip:AddLine("Gear: settings", 0.85, 0.85, 0.85)
    GameTooltip:Show()
end
local function HideBarTooltip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

-- What the strip and the bar do with the mouse.
local function Handle(frame)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", StartMove)
    frame:SetScript("OnDragStop", StopMove)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and not ns.db.locked then ns.SetLocked(true) end
    end)
    frame:SetScript("OnEnter", ShowBarTooltip)
    frame:SetScript("OnLeave", HideBarTooltip)
end

-- The gear opens the bar's quick menu (ns.FillTargetMenu, Settings.lua), or
-- the settings page without FlatMenu.lua.
local function OpenGear(gear)
    GameTooltip:Hide()
    if ns.FlatMenu and ns.FillTargetMenu then
        ns.FlatMenu.Open(gear, function(_, root) ns.FillTargetMenu(root) end)
    elseif ns.OpenSettings then
        ns.OpenSettings()
    end
end

local function NewGear(parent)
    local gear = CreateFrame("Button", nil, parent, "BackdropTemplate")
    gear:SetSize(GEAR, GEAR)
    gear:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, -1)
    gear:SetFrameLevel(parent:GetFrameLevel() + 2)
    gear:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    gear:SetBackdropColor(0.14, 0.145, 0.16, 1)
    gear:SetBackdropBorderColor(0, 0, 0, 1)
    gear.art = gear:CreateTexture(nil, "ARTWORK")
    gear.art:SetTexture(GEAR_ART)
    gear.art:SetSize(GEAR - 2, GEAR - 2)
    gear.art:SetPoint("CENTER")
    -- The gold line inside the black edge on hover.
    gear.line = CreateFrame("Frame", nil, gear, "BackdropTemplate")
    gear.line:SetPoint("TOPLEFT", 1, -1)
    gear.line:SetPoint("BOTTOMRIGHT", -1, 1)
    gear.line:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
    gear.line:SetBackdropBorderColor(STRIP_EDGE[1], STRIP_EDGE[2], STRIP_EDGE[3], 1)
    gear.line:Hide()
    gear:EnableMouse(true)
    gear:RegisterForClicks("LeftButtonUp")
    gear:SetScript("OnEnter", function(self)
        self.line:Show()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Settings")
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function(self)
        self.line:Hide()
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    gear:SetScript("OnClick", OpenGear)
    return gear
end

local function NewStrip()
    local frame = CreateFrame("Frame", nil, target, "BackdropTemplate")
    frame:SetPoint("BOTTOMLEFT", target, "TOPLEFT", 0, STRIP_GAP)
    frame:SetHeight(STRIP_H)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    frame:SetBackdropColor(STRIP_FILL[1], STRIP_FILL[2], STRIP_FILL[3], STRIP_FILL[4])
    frame:SetBackdropBorderColor(STRIP_EDGE[1], STRIP_EDGE[2], STRIP_EDGE[3], 1)
    frame:EnableMouse(true)
    Handle(frame)
    frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.label:SetPoint("LEFT", 4, 0)
    frame.label:SetJustifyH("LEFT")
    frame.label:SetText(STRIP_NAME)
    frame.label:SetTextColor(TEXT_GOLD[1], TEXT_GOLD[2], TEXT_GOLD[3])
    frame.gear = NewGear(frame)
    frame:Hide()
    return frame
end

-- The narrowest the strip can be: its name, then the gear.
local function StripMin()
    local width = strip.label:GetStringWidth()
    if not ns.Number(width, 0, 2000) then width = 60 end
    return math.ceil(width) + 4 + 4 + GEAR + 1
end

-- Resize grip (0.8.0; AGENTS.md window format, Forever Threat's grip) --------
-- Dragging the dots changes Target icon size through ns.Set, snapped and
-- clamped as its slider (1 px, 16 to 64), while the bar's top left corner
-- stays where it was; a double-click sets the default size. The cursor's
-- travel is in screen pixels, divided by the bar's effective scale, and a
-- drag across is shared out over the icons drawn when it began. The grip is
-- never registered for drags (a frame that starts a drag never gets its
-- mouse-up), and a drag also ends on the first OnUpdate that finds the left
-- button up (IsMouseButtonDown, InputDocumentation.lua), on OnHide and on
-- PLAYER_LEAVING_WORLD. The display is a plain frame, so this works in combat.
local function TopLeft()
    local x, y = target:GetCenter()
    local width, height = target:GetWidth(), target:GetHeight()
    if not (ns.Number(x) and ns.Number(y) and ns.Number(width) and ns.Number(height)) then return nil end
    return { left = x - width / 2, top = y + height / 2 }
end

-- Puts the top left corner back at corner, saved in the usual db.x/db.y form.
local function KeepCorner(corner)
    local px, py = UIParent:GetCenter()
    local width, height = target:GetWidth(), target:GetHeight()
    if not (corner and ns.Number(px) and ns.Number(py) and ns.Number(width) and ns.Number(height)) then return end
    local limitX, limitY = ns.LIMITS.x, ns.LIMITS.y
    ns.db.x = math.max(limitX[1], math.min(limitX[2], math.floor(corner.left + width / 2 - px + 0.5)))
    ns.db.y = math.max(limitY[1], math.min(limitY[2], math.floor(corner.top - height / 2 - py + 0.5)))
    ns.PositionTarget()
end

local function SnapSize(value)
    local limits = ns.LIMITS.iconSize
    return math.max(limits[1], math.min(limits[2], math.floor(value + 0.5)))
end

-- The new size through the setter, drawn at once, then the corner back.
local function ResizeTo(size, corner)
    if not corner or size == ns.db.iconSize then return end
    ns.Set("iconSize", size)
    Refresh()
    KeepCorner(corner)
end

local function PaintGrip(grip, color)
    for _, dot in ipairs(grip.dots) do dot:SetVertexColor(color[1], color[2], color[3], 1) end
end

local function StopGrip(grip)
    grip.drag = nil
    grip:SetScript("OnUpdate", nil)
end

local function NewGrip()
    local grip = CreateFrame("Button", nil, target)
    grip:SetSize(GRIP, GRIP)
    -- On the bar's bottom right corner, mostly outside it, so it covers no
    -- icon's count or timer.
    grip:SetPoint("CENTER", target, "BOTTOMRIGHT", 3, -3)
    grip:SetFrameLevel(target:GetFrameLevel() + 10)
    grip.dots = {}
    for _, at in ipairs(GRIP_DOTS) do
        local dot = grip:CreateTexture(nil, "OVERLAY")
        dot:SetTexture(WHITE)
        dot:SetSize(2, 2)
        dot:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -1 - at[1], 1 + at[2])
        grip.dots[#grip.dots + 1] = dot
    end
    PaintGrip(grip, GRIP_GREY)
    local function Release(self)
        StopGrip(self)
        local over = self:IsMouseOver()
        if not (ns.Bool(over) and over) then PaintGrip(self, GRIP_GREY) end
    end
    grip:SetScript("OnEnter", function(self)
        PaintGrip(self, GRIP_GOLD)
        if self.drag then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(GRIP_HINT)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function(self)
        if not self.drag then PaintGrip(self, GRIP_GREY) end
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    grip:RegisterForClicks("LeftButtonUp")
    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or not ns.db or ns.db.locked then return end
        if self.drag then StopGrip(self) end
        local corner, scale = TopLeft(), target:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        if not corner or not ns.Number(scale) or scale <= 0 or not ns.Number(cx) or not ns.Number(cy) then return end
        GameTooltip:Hide()
        self.drag = { cx = cx, cy = cy, scale = scale, corner = corner, count = math.max(1, drawnCount),
            size = ns.db.iconSize }
        self:SetScript("OnUpdate", function()
            local drag = self.drag
            if not drag or ns.db.locked then StopGrip(self); return end
            if not IsMouseButtonDown("LeftButton") then Release(self); return end
            local x, y = GetCursorPosition()
            if not ns.Number(x) or not ns.Number(y) then return end
            local across = (x - drag.cx) / drag.scale / drag.count
            local down = (drag.cy - y) / drag.scale
            ResizeTo(SnapSize(drag.size + (math.abs(across) > math.abs(down) and across or down)), drag.corner)
        end)
    end)
    grip:SetScript("OnMouseUp", Release)
    grip:SetScript("OnHide", function(self)
        StopGrip(self)
        PaintGrip(self, GRIP_GREY)
    end)
    grip:SetScript("OnDoubleClick", function()
        if not ns.db or ns.db.locked then return end
        ResizeTo(ns.Default("iconSize"), TopLeft())
    end)
    grip:Hide()
    return grip
end

local function CreateTarget()
    target = CreateFrame("Frame", nil, UIParent)
    target:SetFrameStrata("MEDIUM")
    target:SetClampedToScreen(true)
    target:SetMovable(true)
    target:SetSize(100, 30)
    target:EnableMouse(false)
    target.takesMouse = false
    target.row = CreateFrame("Frame", nil, target)
    target.row:SetPoint("LEFT")
    Handle(target)
    -- A display hidden mid-drag keeps where it got to.
    target:SetScript("OnHide", StopMove)
    strip = NewStrip()
    target.strip = strip
    target.grip = NewGrip()
    -- For the tests.
    ns.targetDisplay = target
    ns.PositionTarget()
end

function ns.SetLocked(locked)
    if target then StopMove() end
    ns.Set("locked", locked == true)
    ns.RequestRefresh()
    if ns.RefreshSettings then ns.RefreshSettings() end
end

local function DrawTarget(entries, guid)
    local db = ns.db
    local unlocked = not db.locked and db.target
    local count = LayoutRow(target.row, entries, db.iconSize, guid, true)
    drawnCount = count
    -- The strip is at least as wide as the icons, and the bar as the strip,
    -- locked or not, so the icons do not shift when it locks.
    local width = math.max(target.row:GetWidth(), StripMin())
    target:SetSize(width, db.iconSize)
    strip:SetWidth(width)
    strip:SetShown(unlocked)
    target.grip:SetShown(unlocked)
    -- Locked, the bar is click-through but for its icons' tooltips.
    if target.takesMouse ~= unlocked then
        target.takesMouse = unlocked
        target:EnableMouse(unlocked)
        if not unlocked then HideBarTooltip(target) end
    end
    target:SetShown(count > 0 or unlocked)
    return count
end

-- Whether the display needs the driver: something drawn, or the unlocked
-- display whose samples loop (between loops it may draw none).
local function RefreshTarget(now)
    local db = ns.db
    local entries, guid
    local sampling = false
    if db.target then
        guid = ns.ReadEnemy("target")
        entries = Filter(ns.tracker:Snapshot(guid, now))
        if not entries and (now < previewUntil or not db.locked) then
            entries, guid, sampling = Samples(now), nil, true
        end
    end
    if not sampling then sampleStart = nil end
    local count = DrawTarget(entries, guid)
    return count > 0 or sampling
end

-- Nameplates -----------------------------------------------------------------

local function PlateRow(unit)
    -- A token can move to another plate frame (removed and re-added in the
    -- same frame, or after zoning) before the deferred refresh runs, so a
    -- pooled row follows the plate that currently hosts its unit.
    local plate = C_NamePlate.GetNamePlateForUnit(unit, false)
    if not plate then return end
    local row = plates[unit]
    if row and row.plate == plate then return row end
    row = row or table.remove(sparePlates) or CreateFrame("Frame")
    row:ClearAllPoints()
    row:SetParent(plate)
    row:SetFrameLevel(plate:GetFrameLevel() + 20)
    row.plate = plate
    plates[unit] = row
    return row
end

-- Shared by live plates and the settings page's stand-in plate (0.5.0).
local function PlaceRow(row, plate)
    local db = ns.db
    row:ClearAllPoints()
    if db.plateAnchor == "TOP" then row:SetPoint("BOTTOM", plate, "TOP", db.plateX, db.plateOffset + db.plateY)
    else row:SetPoint("TOP", plate, "BOTTOM", db.plateX, -db.plateOffset + db.plateY) end
end
ns.PlaceRow = PlaceRow

local function ReleasePlate(unit)
    local row = plates[unit]
    if not row then return end
    plates[unit] = nil
    row:Hide()
    row:ClearAllPoints()
    row:SetParent(UIParent)
    row.plate = nil
    sparePlates[#sparePlates + 1] = row
end

local function RefreshPlates(now)
    local any = false
    local watched = ns.WatchedUnits()
    for unit in pairs(plates) do
        if not watched[unit] or not ns.db.nameplates or not ns.db.enabled then ReleasePlate(unit) end
    end
    if not ns.db.nameplates or not ns.db.enabled then return false end
    for unit in pairs(watched) do
        if unit:match("^nameplate%d+$") then
            local guid = ns.ReadEnemy(unit)
            local entries = guid and Filter(ns.tracker:Snapshot(guid, now))
            if entries then
                local row = PlateRow(unit)
                if row then
                    LayoutRow(row, entries, ns.db.plateSize, guid, false)
                    PlaceRow(row, row.plate)
                    row:Show()
                    any = true
                else
                    ReleasePlate(unit)
                end
            elseif plates[unit] then
                plates[unit]:Hide()
            end
        end
    end
    return any
end

-- Driver -------------------------------------------------------------------------

function Refresh()
    refreshQueued = false
    if not target then return end
    local now = GetTime()
    if not ns.db.enabled then
        target:Hide()
        if ns.HideFriendly then ns.HideFriendly() end
        RefreshPlates(now)
        driver:SetScript("OnUpdate", nil)
        return
    end
    local shown = RefreshTarget(now)
    local plateShown = RefreshPlates(now)
    local friendlyShown = ns.RefreshFriendly and ns.RefreshFriendly(now) or false
    local live = shown or plateShown or friendlyShown or ns.tracker:HasLive(now) or now < previewUntil
    if not live then ns.tracker:Prune(now) end
    -- Timers tick only while something is on screen or still counting down.
    driver:SetScript("OnUpdate", live and ns.OnDisplayUpdate or nil)
end

function ns.OnDisplayUpdate(_, delta)
    elapsed = elapsed + delta
    if elapsed >= TICK then elapsed = 0; Refresh() end
end

function ns.RequestRefresh()
    if refreshQueued or not driver then return end
    refreshQueued = true
    C_Timer.After(0, Refresh)
end

-- Show on screen and /drpulse preview: the samples on the real display, their
-- loop from the start.
function ns.Preview(seconds)
    previewUntil = GetTime() + (seconds or 20)
    sampleStart = nil
    ns.RequestRefresh()
end

function ns.StartDisplay()
    redColor = CreateColor(STAGE[3][1], STAGE[3][2], STAGE[3][3], 1)
    stageColors = {}
    for i, color in ipairs(STAGE) do stageColors[i] = CreateColor(color[1], color[2], color[3], 1) end
    driver = CreateFrame("Frame")
    -- Leaving the world ends a move or a resize, saving where it got to.
    driver:RegisterEvent("PLAYER_LEAVING_WORLD")
    driver:SetScript("OnEvent", function()
        if not target then return end
        StopMove()
        if target.grip.drag then StopGrip(target.grip) end
    end)
    CreateTarget()
    ns.OnSettingChanged(function(key)
        if key == "position" or key == "x" or key == "y" then ns.PositionTarget() end
        ns.RequestRefresh()
    end)
    ns.RequestRefresh()
end
