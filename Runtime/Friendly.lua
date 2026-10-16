-- Friendly DR display: you and your party, one row each.
-- Copyright 2026 admoney70; MIT, as the rest of Drpulse.
local _, ns = ...
-- The rows use the target display's icons (ns.LayoutRow), so stacks, timers,
-- swipe, font and the secret immune border look and behave the same. Locked,
-- the display is its rows only, click-through but for the icons' tooltips,
-- and hidden while nobody has DR. Unlocked (the same Lock setting as the
-- target display), a strip sits above it to drag it, and a sample row shows
-- when nobody has DR. Rows are drawn from the tracker, which the friendly
-- watchers in Tracking.lua feed.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local STRIP_NAME = "DRPULSE / FRIENDLY"
local STRIP_H, STRIP_GAP = 14, 2
local STRIP_EDGE = { 0.24, 0.65, 0.82 }
local STRIP_FILL = { 0.075, 0.08, 0.09, 0.75 }
local TEXT_ACCENT = { 0.38, 0.85, 1.00 }
local NAME_W, NAME_GAP, ROW_GAP = 72, 6, 4
local display, strip
local rows = {}
local sampleStart

-- Friendly CC is applied by enemies, so "Only CC I can apply" has nothing to
-- say about it: every category shows unless set to Never.
local function Filter(list) return ns.FilterEntries(list, true) end

local function NameOf(unit)
    if unit == "player" then return "You" end
    local name = UnitName(unit)
    if ns.Text(name) and name ~= _G.UNKNOWNOBJECT then return name end
    return unit
end

local function ClassColor(unit)
    local _, class = UnitClass(unit)
    if ns.Text(class) then
        local color = C_ClassColor and C_ClassColor.GetClassColor(class)
        if ns.Public(color) and color and color.GetRGB then return color:GetRGB() end
    end
    return 0.85, 0.85, 0.85
end

local function SavePosition()
    display:StopMovingOrSizing()
    display.moving = false
    local x, y = display:GetCenter()
    local px, py = UIParent:GetCenter()
    if ns.Number(x) and ns.Number(y) and ns.Number(px) and ns.Number(py) then
        local width, height = display:GetWidth(), display:GetHeight()
        -- Saved as the top left corner, so rows added or removed later grow
        -- the display down and right instead of moving it.
        if ns.Number(width) and ns.Number(height) then x, y = x - width / 2, y + height / 2 end
        local limitX, limitY = ns.LIMITS.friendlyX, ns.LIMITS.friendlyY
        ns.db.friendlyX = math.max(limitX[1], math.min(limitX[2], math.floor(x - px + 0.5)))
        ns.db.friendlyY = math.max(limitY[1], math.min(limitY[2], math.floor(y - py + 0.5)))
    end
    ns.PositionFriendly()
end

function ns.PositionFriendly()
    if not display then return end
    display:ClearAllPoints()
    display:SetPoint("TOPLEFT", UIParent, "CENTER", ns.db.friendlyX, ns.db.friendlyY)
end

local function StartMove()
    if ns.db.locked or InCombatLockdown() or display.moving then return end
    display.moving = true
    display:StartMoving()
end
local function StopMove()
    if display.moving then SavePosition() end
end

local function Handle(frame)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", StartMove)
    frame:SetScript("OnDragStop", StopMove)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and not ns.db.locked then ns.SetLocked(true) end
    end)
    frame:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        GameTooltip:SetText("Drpulse: friendly DR")
        if not InCombatLockdown() then GameTooltip:AddLine("Drag: move", 0.85, 0.85, 0.85) end
        GameTooltip:AddLine("Right-click: lock", 0.85, 0.85, 0.85)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(owner)
        if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
    end)
end

local function NewStrip()
    local frame = CreateFrame("Frame", nil, display, "BackdropTemplate")
    frame:SetPoint("BOTTOMLEFT", display, "TOPLEFT", 0, STRIP_GAP)
    frame:SetHeight(STRIP_H)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    frame:SetBackdropColor(STRIP_FILL[1], STRIP_FILL[2], STRIP_FILL[3], STRIP_FILL[4])
    frame:SetBackdropBorderColor(STRIP_EDGE[1], STRIP_EDGE[2], STRIP_EDGE[3], 1)
    frame:EnableMouse(true)
    Handle(frame)
    frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.label:SetPoint("LEFT", 4, 0)
    frame.label:SetText(STRIP_NAME)
    frame.label:SetTextColor(TEXT_ACCENT[1], TEXT_ACCENT[2], TEXT_ACCENT[3])
    frame:Hide()
    return frame
end

local function Row(index)
    local row = rows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, display)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 0, 0)
    row.name:SetWidth(NAME_W)
    row.name:SetJustifyH("RIGHT")
    row.name:SetWordWrap(false)
    row.icons = CreateFrame("Frame", nil, row)
    row.icons:SetPoint("LEFT", row, "LEFT", NAME_W + NAME_GAP, 0)
    row:Hide()
    rows[index] = row
    return row
end

local function CreateDisplay()
    display = CreateFrame("Frame", nil, UIParent)
    display:SetFrameStrata("MEDIUM")
    display:SetClampedToScreen(true)
    display:SetMovable(true)
    display:SetSize(100, 30)
    display:EnableMouse(false)
    display.takesMouse = false
    Handle(display)
    display:SetScript("OnHide", StopMove)
    strip = NewStrip()
    display.strip = strip
    -- For the tests.
    ns.friendlyDisplay = display
    ns.PositionFriendly()
end

-- The rows to draw now: { unit, name, guid, entries }, in party order.
local function Collect(now)
    local list = {}
    for _, unit in ipairs(ns.FRIEND_UNITS) do
        if ns.FriendlyOn(unit) then
            local guid = ns.ReadFriend(unit)
            local entries = guid and Filter(ns.tracker:Snapshot(guid, now))
            if entries then list[#list + 1] = { unit = unit, guid = guid, entries = entries } end
        end
    end
    return list
end

-- Draws the display; returns whether anything on it needs the timer.
function ns.RefreshFriendly(now)
    if not display then return false end
    local db = ns.db
    if not (db.enabled and db.friendly) then display:Hide(); sampleStart = nil; return false end
    local unlocked = not db.locked
    local list = Collect(now)
    if #list == 0 and unlocked then
        if not sampleStart or now - sampleStart >= ns.SETTINGS_SAMPLE_LOOP then sampleStart = now end
        list = { { unit = "player", entries = (ns.SettingsSamples(now, sampleStart)) } }
    else
        sampleStart = nil
    end
    local size = db.friendlySize
    local width, y = 0, 0
    for index, item in ipairs(list) do
        local row = Row(index)
        local count = ns.LayoutRow(row.icons, item.entries, size, item.guid, true)
        row.name:SetText(NameOf(item.unit))
        row.name:SetTextColor(ClassColor(item.unit))
        row:SetSize(NAME_W + NAME_GAP + row.icons:GetWidth(), size)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", display, "TOPLEFT", 0, -y)
        row:SetShown(count > 0)
        width = math.max(width, row:GetWidth())
        y = y + size + ROW_GAP
    end
    for index = #list + 1, #rows do rows[index]:Hide() end
    local stripWidth = math.ceil(strip.label:GetStringWidth() or 0) + 8
    width = math.max(width, ns.Number(stripWidth, 0, 2000) and stripWidth or 120)
    display:SetSize(width, math.max(size, y - ROW_GAP))
    strip:SetWidth(width)
    strip:SetShown(unlocked)
    if display.takesMouse ~= unlocked then
        display.takesMouse = unlocked
        display:EnableMouse(unlocked)
    end
    display:SetShown(#list > 0)
    return #list > 0
end

function ns.HideFriendly()
    if display then display:Hide() end
end

function ns.StartFriendly()
    CreateDisplay()
    ns.OnSettingChanged(function(key)
        if key == "position" or key == "friendlyX" or key == "friendlyY" then ns.PositionFriendly() end
    end)
end
