-- Adapted from Forever DR Settings.lua (MIT, Copyright 2026 Tarolg).
-- Drpulse integration and visual adaptations: Copyright 2026 Joaqoz.
local _, ns = ...
-- /drpulse opens a standalone, movable control deck. Five fixed
-- tabs replace the inherited accordion: General, Appearance, Detection,
-- Tools and Guide. Each tab keeps related settings in a short workspace so
-- players do not have to scan one long stack of collapsed headings.
-- 0.3.4: the page answers Forever Settings' search (panel.ForeverSettingsSearch).
-- 0.5.0: previews first under Size and placement, Icon style and Categories
-- (the workspace's PreviewKit.lua; see Previews below); Preview 20 s is their
-- Show on screen.

local WHITE = "Interface\\Buttons\\WHITE8X8"
local PAYPAL_URL = "https://www.paypal.com/paypalme/sebiten"
local backdrop = {
    bgFile = WHITE, edgeFile = WHITE,
    edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
}
local edgeOnly = { edgeFile = WHITE, edgeSize = 1 }
local GOLD = { 0.38, 0.85, 1.00 }
local GREY = { 0.55, 0.55, 0.58 }
local GREY_TEXT = "|cff8c8c94"
local AMBER_TEXT = "|cffff9f1a"
local GREEN_TEXT = "|cff80ff80"
local ROW = 30
local NAME_X, NAME_W = 14, 196
local C1, C2, CW = 216, 372, 150
local FULL = C2 + CW - NAME_X
-- A read-out from the first control column to the right edge.
local WIDE = FULL - (C1 - NAME_X) - 4
-- The always-open last heading (page.Help, 0.6.0).
local HELP = "How to use"
local SECTION_ORDER = { "general", "appearance", "detection", "tools", "guide" }
local SECTION_LABELS = {
    general = "GENERAL", appearance = "APPEARANCE", detection = "DETECTION",
    tools = "TOOLS", guide = "GUIDE",
}
local SECTION_OF = {
    Displays = "general", ["Friendly DR"] = "general", ["What to show"] = "general",
    Categories = "appearance", ["Size and placement"] = "appearance", ["Icon style"] = "appearance",
    ["Tracking sources"] = "detection", ["Blizzard data"] = "detection",
    ["Custom spells"] = "tools", Advanced = "tools", Diagnostics = "tools",
    [HELP] = "guide",
}

-- Value buttons: the choices in order, and their labels.
local CHOICES = {
    plateAnchor = { "TOP", "BOTTOM" },
    font = { "default", "friz", "arial", "morpheus", "skurri" },
    stackStyle = { "pips", "number", "next" },
    iconSource = { "spell", "category" },
}
local MODES = { "auto", "always", "never" }
local MODE_LABELS = { auto = "Auto", always = "Always", never = "Never" }

-- Widgets -----------------------------------------------------------------------
local function Text(parent, text, x, y, color, width)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y)
    if width then label:SetWidth(width) else label:SetPoint("TOPRIGHT", -14, y) end
    label:SetJustifyH("LEFT")
    label:SetText(text)
    if color then label:SetTextColor(color[1], color[2], color[3]) end
    return label
end
-- point(true/false), when given, is told the mouse is over the control or
-- has left it (0.5.0: a row's part outlined in its heading's preview).
local function Tooltip(control, title, detail, point)
    if not detail and not point then return end
    control:HookScript("OnEnter", function(self)
        if point then point(true) end
        if not detail then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(detail, 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    control:HookScript("OnLeave", function()
        if point then point(false) end
        if detail then GameTooltip:Hide() end
    end)
end
-- Controls use the addon's navy/cyan vocabulary rather than the inherited
-- black strips from the reference settings page.
local function Skin(control, hover)
    control:SetBackdropColor(hover and 0.055 or 0.035, hover and 0.20 or 0.105, hover and 0.29 or 0.16, 1)
    control:SetBackdropBorderColor(hover and 0.24 or 0.10, hover and 0.65 or 0.24, hover and 0.82 or 0.34, 1)
    if not control.gold then
        local gold = CreateFrame("Frame", nil, control, "BackdropTemplate")
        gold:SetPoint("TOPLEFT", 1, -1)
        gold:SetPoint("BOTTOMRIGHT", -1, 1)
        gold:SetBackdrop(edgeOnly)
        gold:SetBackdropBorderColor(0.38, 0.85, 1.00, 1)
        control.gold = gold
    end
    control.gold:SetShown(hover)
end
local function Hover(control)
    Skin(control, false)
    control:SetScript("OnEnter", function(self) Skin(self, true) end)
    control:SetScript("OnLeave", function(self) Skin(self, false) end)
end
-- A row's name is deliberately quiet; the value remains the affordance.
local function Strip(parent, x, y, width, text)
    local strip = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    strip:SetPoint("TOPLEFT", x, y)
    strip:SetSize(width, 22)
    strip:SetBackdrop(backdrop)
    strip:SetBackdropColor(0.035, 0.055, 0.075, 0.72)
    strip:SetBackdropBorderColor(0.08, 0.16, 0.22, 0.9)
    strip:EnableMouse(true)
    strip.label = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    strip.label:SetPoint("LEFT", 8, 0)
    strip.label:SetPoint("RIGHT", -8, 0)
    strip.label:SetJustifyH("LEFT")
    strip.label:SetText(text)
    return strip
end
local function ButtonWidget(parent, x, y, width, text)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(width, 22)
    button:SetBackdrop(backdrop)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.label:SetPoint("LEFT", 8, 0)
    button.label:SetPoint("RIGHT", -8, 0)
    button.label:SetText(text or "")
    button.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    Hover(button)
    return button
end

-- A setting key, or { key, get, set, options, limits, default } for a value
-- kept elsewhere (a tracking source, a category mode, the lock); a key's
-- default is its saved default.
local function Adapter(key)
    if type(key) == "table" then return key end
    return { key = key, get = function() return ns.db[key] end, set = function(value) ns.Set(key, value) end,
        options = CHOICES[key], limits = ns.LIMITS[key], default = ns.Default(key) }
end

-- A slider's reset arrow (AGENTS.md, "Gears and quick settings"; Forever
-- Battle Map 0.9.0's): Blizzard's undo icon (ModelSceneControlFrame.lua's
-- reset button, Blizzard_SharedXML), or its refresh arrows on a build without
-- the atlas; in colour while the value differs from its default by half a
-- step or more, when a click sets the default, and grey once it is the
-- default.
local RESET_ATLAS, RESET_FILE = "common-icon-undo", "Interface\\Buttons\\UI-RefreshButton"
local function ResetArt(texture, changed)
    if not texture.resetArt then
        if C_Texture.GetAtlasInfo(RESET_ATLAS) then texture:SetAtlas(RESET_ATLAS) else texture:SetTexture(RESET_FILE) end
        texture.resetArt = true
    end
    texture:SetDesaturated(not changed)
    if changed then texture:SetVertexColor(1, 1, 1, 1) else texture:SetVertexColor(0.5, 0.5, 0.52, 1) end
end
local function Differs(value, default, step)
    if type(value) ~= "number" or type(default) ~= "number" then return false end
    return math.abs(value - default) >= math.max((step or 0) / 2, 1e-6)
end

-- Pages -----------------------------------------------------------------------------
local pages = {}
-- Every page by name, each with its rows by name (read by the tests).
ns.SettingsPages = pages

local function NewPage(name)
    local panel = CreateFrame("Frame", "DrpulseSettingsWindow", UIParent, "BackdropTemplate")
    panel:SetSize(640, 680)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(80)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetBackdrop(backdrop)
    panel:SetBackdropColor(0.012, 0.022, 0.034, 0.99)
    panel:SetBackdropBorderColor(0.10, 0.28, 0.38, 1)
    panel:Hide()
    table.insert(UISpecialFrames, "DrpulseSettingsWindow")
    local page = { name = name, panel = panel, rows = {}, notes = {}, blocks = {}, refreshers = {},
        selectedSection = "general", tabs = {} }
    pages[name] = page

    local titleBar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(42)
    titleBar:SetBackdrop({ bgFile = WHITE })
    titleBar:SetBackdropColor(0.025, 0.085, 0.12, 1)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() panel:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)
    local windowTitle = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    windowTitle:SetPoint("LEFT", 16, 5)
    windowTitle:SetText("DRPULSE")
    windowTitle:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    local windowHint = titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    windowHint:SetPoint("TOPLEFT", windowTitle, "BOTTOMLEFT", 0, -1)
    windowHint:SetText("Settings · drag this bar to move")
    windowHint:SetTextColor(0.52, 0.62, 0.68)
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() panel:Hide() end)
    page.titleBar, page.close = titleBar, close

    local nav = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", 18, -52)
    nav:SetPoint("TOPRIGHT", -18, -52)
    nav:SetHeight(36)
    nav:SetBackdrop(backdrop)
    nav:SetBackdropColor(0.025, 0.045, 0.065, 0.98)
    nav:SetBackdropBorderColor(0.08, 0.20, 0.28, 1)
    page.nav = nav

    local function PaintTabs()
        for key, tab in pairs(page.tabs) do
            local active = page.selectedSection == key
            tab:SetBackdropColor(active and 0.04 or 0.02, active and 0.18 or 0.07, active and 0.26 or 0.10, 1)
            tab:SetBackdropBorderColor(active and GOLD[1] or 0.06, active and GOLD[2] or 0.14,
                active and GOLD[3] or 0.19, 1)
            tab.label:SetTextColor(active and 0.82 or 0.48, active and 0.94 or 0.58, active and 1.00 or 0.64)
            tab.rail:SetShown(active)
        end
    end

    for index, key in ipairs(SECTION_ORDER) do
        local tab = CreateFrame("Button", nil, nav, "BackdropTemplate")
        tab:SetPoint("TOPLEFT", 5 + (index - 1) * 101, -5)
        tab:SetSize(97, 26)
        tab:SetBackdrop(backdrop)
        tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tab.label:SetPoint("CENTER")
        tab.label:SetText(SECTION_LABELS[key])
        tab.rail = tab:CreateTexture(nil, "OVERLAY")
        tab.rail:SetPoint("BOTTOMLEFT", 5, 1)
        tab.rail:SetPoint("BOTTOMRIGHT", -5, 1)
        tab.rail:SetHeight(2)
        tab.rail:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        tab:SetScript("OnClick", function()
            page.selectedSection = key
            PaintTabs()
            if page.scroll then page.scroll:SetVerticalScroll(0) end
            page.Layout()
            page.Refresh()
        end)
        page.tabs[key] = tab
    end
    PaintTabs()

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -96)
    scroll:SetPoint("BOTTOMRIGHT", -38, 76)
    local body = CreateFrame("Frame", nil, scroll, "BackdropTemplate")
    body:SetSize(566, 400)
    body:SetBackdrop(backdrop)
    body:SetBackdropColor(0.018, 0.028, 0.042, 0.98)
    body:SetBackdropBorderColor(0.07, 0.16, 0.22, 1)
    scroll:SetScrollChild(body)
    scroll:SetScript("OnSizeChanged", function(_, width) body:SetWidth(width) end)
    page.body, page.scroll = body, scroll

    local support = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    support:SetPoint("BOTTOMLEFT", 18, 14)
    support:SetPoint("BOTTOMRIGHT", -18, 14)
    support:SetHeight(48)
    support:SetBackdrop(backdrop)
    support:SetBackdropColor(0.025, 0.065, 0.09, 1)
    support:SetBackdropBorderColor(0.10, 0.24, 0.32, 1)
    local coin = support:CreateTexture(nil, "ARTWORK")
    coin:SetPoint("LEFT", 12, 0)
    coin:SetSize(22, 22)
    coin:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    coin:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local supportTitle = support:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    supportTitle:SetPoint("TOPLEFT", coin, "TOPRIGHT", 9, 2)
    supportTitle:SetText("Support Drpulse")
    supportTitle:SetTextColor(0.82, 0.94, 1)
    local supportHint = support:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    supportHint:SetPoint("TOPLEFT", supportTitle, "BOTTOMLEFT", 0, -2)
    supportHint:SetText("Optional one-time donation")
    supportHint:SetTextColor(0.50, 0.58, 0.64)
    local donation = CreateFrame("EditBox", nil, support, "BackdropTemplate")
    donation:SetPoint("LEFT", 190, 0)
    donation:SetSize(286, 24)
    donation:SetBackdrop(backdrop)
    donation:SetBackdropColor(0.012, 0.026, 0.04, 1)
    donation:SetBackdropBorderColor(0.10, 0.30, 0.40, 1)
    donation:SetFontObject("GameFontHighlightSmall")
    donation:SetTextInsets(8, 8, 0, 0)
    donation:SetAutoFocus(false)
    donation:SetText(PAYPAL_URL)
    donation:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    donation:SetScript("OnEnterPressed", function(self) self:HighlightText() end)
    donation:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)
    local selectLink = ButtonWidget(support, 486, -12, 100, "Select link")
    selectLink:SetScript("OnClick", function()
        donation:SetText(PAYPAL_URL)
        donation:SetFocus()
        donation:HighlightText()
    end)
    Tooltip(selectLink, "Select donation link", "Select the PayPal link, then press Ctrl+C to copy it.")
    page.support, page.donation = support, donation

    function page.OnRefresh(fn) page.refreshers[#page.refreshers + 1] = fn end
    function page.Refresh()
        if not ns.db then return end
        for _, fn in ipairs(page.refreshers) do fn() end
    end

    -- Blocks stack top to bottom; a group's blocks show while it is open. A
    -- block with measure() takes the height it returns (the custom spell list).
    local group
    -- While Forever Settings' search box holds words (0.3.4): the blocks to
    -- draw, else nil and the page draws as usual.
    local found
    function page.Block(height)
        local frame = CreateFrame("Frame", nil, body)
        frame:SetHeight(height)
        local block = { frame = frame, height = height, shown = true, group = group,
            section = group and group.section or "general" }
        page.blocks[#page.blocks + 1] = block
        if group then
            group.members[#group.members + 1] = block
            block.shown = group.open
        end
        return frame, block
    end
    local function Visible(block)
        if not found then return block.shown and block.section == page.selectedSection end
        return found[block] == true and not (block.group and block.group.folded)
    end
    function page.Layout()
        local y = -6
        for _, block in ipairs(page.blocks) do
            if block.measure then
                block.height = block.measure()
                block.frame:SetHeight(block.height)
            end
            if Visible(block) then
                block.frame:ClearAllPoints()
                block.frame:SetPoint("TOPLEFT", 0, y)
                block.frame:SetPoint("TOPRIGHT", 0, y)
                block.frame:Show()
                y = y - block.height
            else
                block.frame:Hide()
            end
        end
        body:SetHeight(-y + 12)
    end

    -- A preview box, the first block under the heading just made (0.5.0;
    -- the workspace's preview kit, PreviewKit.lua, as Forever Cast's), kept
    -- as its group's preview so its rows can point at their parts. nil
    -- without the kit.
    function page.Preview(onScreen, screenTip)
        if not ns.PreviewKit then return nil end
        local frame, block = page.Block(60)
        block.preview = true
        local preview = ns.PreviewKit.New(frame, { x = NAME_X, width = FULL, onScreen = onScreen, screenTip = screenTip,
            resize = function(height)
                if height == block.height then return end
                block.height = height
                frame:SetHeight(height)
                page.Layout()
            end })
        preview.block = block
        if block.group then block.group.preview = preview end
        return preview
    end

    -- Static workspace heading. Navigation now decides which groups are on
    -- screen, so headings describe state instead of duplicating navigation.
    function page.Group(title, open, summary, detail)
        group = nil
        local frame, block = page.Block(46)
        local members = {}
        local section = SECTION_OF[title] or "general"
        block.section = section
        local this = { open = true, members = members, title = title, block = block, section = section }
        block.heading = this
        local toggle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        toggle:SetPoint("TOPLEFT", NAME_X, -5)
        toggle:SetSize(FULL, 37)
        toggle:SetBackdrop(backdrop)
        toggle:SetBackdropColor(0.025, 0.075, 0.105, 0.92)
        toggle:SetBackdropBorderColor(0.08, 0.25, 0.34, 1)
        toggle:EnableMouse(true)
        local pulse = toggle:CreateTexture(nil, "ARTWORK")
        pulse:SetPoint("LEFT", 9, 0)
        pulse:SetSize(7, 7)
        pulse:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        local heading = toggle:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        heading:SetPoint("TOPLEFT", 25, -7)
        heading:SetText(title)
        local count = toggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        count:SetPoint("TOPLEFT", 25, -22)
        count:SetPoint("RIGHT", -10, 0)
        count:SetJustifyH("LEFT")
        count:SetTextColor(GREY[1], GREY[2], GREY[3])
        local down = toggle:CreateTexture(nil, "OVERLAY")
        down:Hide()
        local hovered = false
        local function Paint()
            local lit = hovered and GOLD or { 0.88, 0.91, 0.94 }
            heading:SetTextColor(lit[1], lit[2], lit[3])
            toggle:SetBackdropBorderColor(hovered and GOLD[1] or 0.08, hovered and GOLD[2] or 0.25,
                hovered and GOLD[3] or 0.34, 1)
        end
        toggle:SetScript("OnEnter", function() hovered = true; Paint() end)
        toggle:SetScript("OnLeave", function() hovered = false; Paint() end)
        Tooltip(toggle, title, detail)
        page.OnRefresh(function()
            count:SetText(summary and summary() or "")
            Paint()
        end)
        -- Preserve the public fields consumed by the settings integration.
        this.toggle, this.summary, this.plus = toggle, count, down
        page.groups = page.groups or {}
        page.groups[title] = this
        group = this
        return this
    end

    -- Guide workspace: mouse controls and commands in readable note rows.
    function page.Help(summary, detail)
        assert(not (page.groups and page.groups[HELP]), "two How to use sections")
        group = nil
        local frame, block = page.Block(46)
        block.section = "guide"
        local this = { title = HELP, open = true, always = true, members = {}, block = block, section = "guide" }
        block.heading = this
        local head = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        head:SetPoint("TOPLEFT", NAME_X, -5)
        head:SetSize(FULL, 37)
        head:SetBackdrop(backdrop)
        head:SetBackdropColor(0.025, 0.075, 0.105, 0.92)
        head:SetBackdropBorderColor(0.08, 0.25, 0.34, 1)
        head:EnableMouse(true)
        local pulse = head:CreateTexture(nil, "ARTWORK")
        pulse:SetPoint("LEFT", 9, 0)
        pulse:SetSize(7, 7)
        pulse:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        local heading = head:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        heading:SetPoint("TOPLEFT", 25, -7)
        heading:SetText(HELP)
        heading:SetTextColor(0.92, 0.92, 0.92)
        local count = head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        count:SetPoint("TOPLEFT", 25, -22)
        count:SetPoint("RIGHT", -10, 0)
        count:SetJustifyH("LEFT")
        count:SetTextColor(GREY[1], GREY[2], GREY[3])
        Tooltip(head, HELP, detail)
        page.OnRefresh(function() count:SetText(summary and summary() or "") end)
        -- head: the heading; summary: its grey state; detail: its tooltip
        -- (read by the tests).
        this.head, this.summary, this.detail = head, count, detail
        page.groups = page.groups or {}
        page.groups[HELP] = this
        group = this
        return this
    end
    -- A small gold label inside How to use: what the notes after it are about.
    function page.Topic(title)
        assert(group and group.always, "a topic belongs under How to use")
        local frame, block = page.Block(22)
        block.topic = title
        Text(frame, title, NAME_X + 2, -8, GOLD, FULL - 4)
        return block
    end
    -- One line of How to use: what, then how in grey; plain text, no strip,
    -- so it reads as a note and not a setting. detail is its tooltip; a line
    -- too long for its column wraps and the note grows to fit.
    function page.Note(label, how, detail)
        assert(group and group.always, "a note belongs under How to use")
        local frame, block = page.Block(20)
        local note = { frame = frame, label = label, detail = detail, block = block }
        page.notes[#page.notes + 1] = note
        block.row = note
        frame:EnableMouse(true)
        note.name = Text(frame, label, NAME_X + 2, -4, nil, NAME_W - 4)
        note.how = Text(frame, how, C1 + 4, -4, GREY, WIDE)
        local tall = math.max(note.name:GetStringHeight() or 0, note.how:GetStringHeight() or 0)
        if tall > 14 then
            block.height = math.ceil(tall) + 8
            frame:SetHeight(block.height)
        end
        Tooltip(frame, label, detail)
        return note
    end

    -- Hover a row, see its part (0.5.0; AGENTS.md "Previews in settings"):
    -- the preview under the row's heading holds still and outlines what the
    -- row changes. nil clears it.
    local pointed
    function page.Point(row)
        local preview = row and row.block.group and row.block.group.preview
        if pointed and pointed ~= preview then pointed.Point(nil) end
        pointed = preview
        if preview then preview.Point(row.part, row.label) end
    end

    -- One setting: its name, then its controls. part (0.5.0): what the row
    -- changes in its heading's preview (preview.parts), if anything. height:
    -- a taller row for a read-out that may take two lines.
    function page.Row(label, detail, part, height)
        local frame, block = page.Block(height or ROW)
        -- keys: the settings its controls change (read by the tests).
        local row = { frame = frame, label = label, detail = detail, controls = {}, keys = {}, part = part, block = block }
        page.rows[label] = row
        block.row = row
        local point = part and function(over) page.Point(over and row or nil) end or nil
        row.name = Strip(frame, NAME_X, -2, NAME_W, label)
        Tooltip(row.name, label, detail, point)
        local function Keep(control)
            row.controls[#row.controls + 1] = control
            Tooltip(control, label, detail, point)
            return control
        end
        local function Track(setting)
            if setting.key then row.keys[#row.keys + 1] = setting.key end
            return setting
        end
        -- On or Off; a click switches.
        function row:Toggle(x, key, width)
            local setting = Track(Adapter(key))
            local button = Keep(ButtonWidget(frame, x, -2, width or CW, ""))
            button.label:SetJustifyH("CENTER")
            button:SetScript("OnClick", function()
                setting.set(not (setting.get() == true))
                page.Refresh()
            end)
            page.OnRefresh(function()
                local on = setting.get() == true
                button.label:SetText(on and "On" or "Off")
                button.label:SetTextColor(on and GOLD[1] or GREY[1], on and GOLD[2] or GREY[2], on and GOLD[3] or GREY[3])
            end)
            return button
        end
        -- < Value >: a click picks the next choice, a right-click the one before.
        -- With four or more choices (or setting.dropdown) a click opens a
        -- dropdown list under the button instead (0.3.2); since 0.4.0 it is
        -- the workspace's flat menu (FlatMenu.lua): the current choice's box
        -- is gold, a click on a row picks it, and a click elsewhere, the
        -- button again or Escape (out of combat) closes it, as does the
        -- button hiding. Without FlatMenu.lua (a /reload after updating,
        -- before the client restart a new file needs) every choice steps.
        function row:Choice(x, key, labels, width)
            local setting = Track(Adapter(key))
            local button = Keep(ButtonWidget(frame, x, -2, width or CW, ""))
            button.label:SetJustifyH("CENTER")
            local listed = (setting.dropdown or #setting.options >= 4) and ns.FlatMenu ~= nil
            button.dropdown = listed
            if listed then
                button.label:SetJustifyH("LEFT")
                button.label:SetPoint("RIGHT", -20, 0)
                ns.FlatMenu.DownArrow(button)
            end
            button:SetScript("OnClick", function(_, mouse)
                local options = setting.options
                if listed then
                    ns.FlatMenu.Open(button, function(_, root)
                        for _, value in ipairs(setting.options) do
                            root:CreateRadio(labels[value] or tostring(value),
                                function() return setting.get() == value end,
                                function() setting.set(value); page.Refresh() end)
                        end
                    end)
                    return
                end
                local index = 1
                for i, option in ipairs(options) do
                    if option == setting.get() then index = i end
                end
                index = index + (mouse == "RightButton" and -1 or 1)
                if index > #options then index = 1 elseif index < 1 then index = #options end
                setting.set(options[index])
                page.Refresh()
            end)
            page.OnRefresh(function()
                local value = setting.get()
                if listed then
                    button.label:SetText(labels[value] or tostring(value))
                else
                    button.label:SetText(GREY_TEXT .. "<|r  " .. (labels[value] or tostring(value)) .. "  " .. GREY_TEXT .. ">|r")
                end
            end)
            return button
        end
        -- A flat track with a gold thumb, the value after it, and the reset
        -- arrow at the end.
        function row:Slider(x, key, step, unit, width)
            local setting = Track(Adapter(key))
            unit = unit or ""
            width = width or CW
            local low, high = setting.limits[1], setting.limits[2]
            local default = type(setting.default) == "number" and setting.default or nil
            local control = Keep(CreateFrame("Slider", nil, frame))
            control:SetPoint("TOPLEFT", x + 4, -4)
            control:SetSize(width - (default and 74 or 56), 18)
            control:SetOrientation("HORIZONTAL")
            control:SetMinMaxValues(low, high)
            control:SetValueStep(step)
            control:SetObeyStepOnDrag(true)
            control:SetThumbTexture(WHITE)
            control:GetThumbTexture():SetSize(8, 16)
            control:GetThumbTexture():SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
            local track = control:CreateTexture(nil, "BACKGROUND")
            track:SetPoint("LEFT")
            track:SetPoint("RIGHT")
            track:SetHeight(4)
            track:SetColorTexture(0.22, 0.24, 0.27, 1)
            local value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            value:SetPoint("LEFT", control, "RIGHT", 4, 0)
            value:SetWidth(default and 46 or 48)
            value:SetJustifyH("RIGHT")
            control.readout = value
            local reset, changed
            if default then
                reset = CreateFrame("Button", nil, frame)
                reset:SetSize(14, 14)
                reset:SetPoint("LEFT", value, "RIGHT", 2, 0)
                reset.art = reset:CreateTexture(nil, "ARTWORK")
                reset.art:SetAllPoints()
                reset:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Reset to default")
                    GameTooltip:Show()
                end)
                reset:SetScript("OnLeave", function() GameTooltip:Hide() end)
                reset:SetScript("OnClick", function()
                    if not changed then return end
                    setting.set(default)
                    page.Refresh()
                end)
                control.reset = reset
            end
            local function Paint()
                if not reset then return end
                changed = Differs(setting.get(), default, step)
                ResetArt(reset.art, changed)
            end
            local refreshing = false
            page.OnRefresh(function()
                refreshing = true
                local current = setting.get() or low
                control:SetValue(math.max(low, math.min(high, current)))
                value:SetText(tostring(current) .. unit)
                refreshing = false
                Paint()
            end)
            control:SetScript("OnValueChanged", function(_, raw)
                local number = math.max(low, math.min(high, math.floor(raw / step + 0.5) * step))
                value:SetText(tostring(number) .. unit)
                if refreshing then return end
                setting.set(number)
                Paint()
            end)
            return control
        end
        function row:Button(x, text, onClick, width)
            local button = Keep(ButtonWidget(frame, x, -2, width or CW, text))
            button:SetScript("OnClick", function(clicked, mouse) onClick(clicked, mouse); page.Refresh() end)
            return button
        end
        -- Short grey text after a single control (or in the control column when
        -- x is given: a read-only row, or a Mouse entry).
        function row:Status(fn, x, width)
            local status = Text(frame, "", (x or C2) + 4, -7, GREY, width or (CW + 30))
            row.status = status
            page.OnRefresh(function() status:SetText(fn() or "") end)
            return status
        end
        return row
    end

    -- Forever Settings' search (0.3.4). Its window hands the page the
    -- lower-case words typed in its search box, less those in the page's
    -- name: Count says how many rows hold every word, Show draws only those
    -- rows under their headings (nil draws the whole page again). A row is
    -- found by what it draws (its name, value or status), its tooltip and its
    -- heading's title, so a heading's title brings all its rows; a block that
    -- is not a row (the custom spell list) goes with the row before it, and
    -- the header waits.
    local function Drawn(frame, parts)
        for _, region in ipairs({ frame:GetRegions() }) do
            if region:IsObjectType("FontString") then parts[#parts + 1] = region:GetText() end
        end
        for _, child in ipairs({ frame:GetChildren() }) do Drawn(child, parts) end
        return parts
    end
    local function Holds(text, words)
        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
        for _, word in ipairs(words) do
            if not text:find(word, 1, true) then return false end
        end
        return true
    end
    local function Match(words)
        local set, count, whole, last = {}, 0, false, false
        for _, block in ipairs(page.blocks) do
            if block.heading then
                whole = Holds(block.heading.title, words)
                last = whole
            elseif block.topic then
                last = whole
            elseif block.row then
                local detail = block.row.detail
                local parts = Drawn(block.frame, { type(detail) == "string" and detail or "",
                    block.group and block.group.title or "" })
                last = whole or Holds(table.concat(parts, "\n"), words)
                if last then count = count + 1 end
            end
            if last then
                set[block] = true
                if block.group then set[block.group.block] = true end
            end
        end
        -- A How to use topic shows whenever a note under it does (0.6.0).
        local topic
        for _, block in ipairs(page.blocks) do
            if block.topic then topic = block
            elseif block.heading then topic = nil
            elseif topic and set[block] then set[topic] = true end
        end
        -- A preview shows whenever a row under its heading does (0.5.0).
        for _, block in ipairs(page.blocks) do
            if block.preview and block.group and set[block.group.block] then set[block] = true end
        end
        return set, count
    end
    panel.ForeverSettingsSearch = {
        Count = function(words)
            local _, count = Match(words)
            return count
        end,
        Show = function(words)
            local count = 0
            found = nil
            if type(words) == "table" and #words > 0 then found, count = Match(words) end
            for _, block in ipairs(page.blocks) do
                if block.heading then block.heading.folded = nil end
            end
            scroll:SetVerticalScroll(0)
            page.Layout()
            page.Refresh()
            return count
        end,
    }

    panel:SetScript("OnShow", function()
        page.Layout()
        page.Refresh()
    end)
    panel:SetScript("OnHide", function()
        donation:ClearFocus()
    end)
    return page
end

-- Two clicks within 5 seconds for a reset; the first one asks.
local function TwoClicks(label, action)
    local armed
    return function(self)
        if armed and GetTime() - armed <= 5 then
            armed = nil
            self.label:SetText(label)
            action()
            return
        end
        armed = GetTime()
        self.label:SetText("Click again")
        C_Timer.After(5, function()
            if armed and GetTime() - armed >= 5 then
                armed = nil
                self.label:SetText(label)
            end
        end)
    end
end

-- Labels for the heading summaries.
local STACK_LABELS = { pips = "Pips", number = "Count", next = "Next duration" }
local ICON_LABELS = { spell = "Last spell", category = "Category" }

-- Rows the target display's gear menu repeats (0.8.0): their tooltips, the
-- same words on the page and in the menu.
local TIPS = {
    locked = "Off shows a thin blue strip above the target display, with sample icons counting down under it: drag the strip to move the display, drag the dots at its corner to resize the icons, click its gear for quick settings, right-click it to lock. On locks the display in place again: icons only, click-through, hidden while there is nothing to show.",
    iconSize = "Size of the icons on the target display. Dragging the dots at the corner of the unlocked display changes it too.",
    stackStyle = "Pips: one coloured mark per application. Count: the number of applications. Next duration: 50%, 25% or IMM for the next CC. The border colour always shows the stage: yellow 50%, orange 25%, red immune.",
    iconSource = "Last spell shows the most recent CC in the category (for example Polymorph). Category shows one fixed icon per category.",
    timer = "Seconds until the category resets. Grey means part of the timing is estimated.",
    swipe = "Darken the icon as the reset window runs down.",
    filter = "Show only categories your known spells, pet or carried items can cause (a warlock does not see Polymorph). Off shows every category. Per-category choices under Categories override this.",
}
local STACK_TIPS = {
    pips = "One coloured mark per application.",
    number = "The number of applications.",
    next = "50%, 25% or IMM: how long the next CC in the category lasts.",
}
local ICON_TIPS = {
    spell = "The most recent CC in the category (for example Polymorph).",
    category = "One fixed icon per category.",
}

-- The target display's gear (0.8.0; AGENTS.md "Gears and quick settings"):
-- what a player changes while playing, with the page rows' labels, through
-- the page's own setters, ending in All options... Every entry explains
-- itself. Nothing here is protected, so nothing greys in combat.
function ns.FillTargetMenu(root)
    root:CreateTitle("Target DR")
    root:CreateCheckbox("Lock target display", function() return ns.db.locked == true end,
        function() ns.SetLocked(not ns.db.locked) end):SetTooltip(TIPS.locked)
    local limits = ns.LIMITS.iconSize
    root:CreateSlider("Target icon size", function() return ns.db.iconSize end, function(value) ns.Set("iconSize", value) end,
        limits[1], limits[2], 1, nil, ns.Default("iconSize")):SetTooltip(TIPS.iconSize)
    root:CreateTitle("Icon style")
    local stacks = root:CreateButton("Stacks")
    stacks:SetTooltip(TIPS.stackStyle)
    for _, value in ipairs(CHOICES.stackStyle) do
        stacks:CreateRadio(STACK_LABELS[value], function() return ns.db.stackStyle == value end,
            function() ns.Set("stackStyle", value) end):SetTooltip(STACK_TIPS[value])
    end
    local icon = root:CreateButton("Icon")
    icon:SetTooltip(TIPS.iconSource)
    for _, value in ipairs(CHOICES.iconSource) do
        icon:CreateRadio(ICON_LABELS[value], function() return ns.db.iconSource == value end,
            function() ns.Set("iconSource", value) end):SetTooltip(ICON_TIPS[value])
    end
    root:CreateCheckbox("Reset timer text", function() return ns.db.timer == true end,
        function() ns.Set("timer", not ns.db.timer) end):SetTooltip(TIPS.timer)
    root:CreateCheckbox("Countdown swipe", function() return ns.db.swipe == true end,
        function() ns.Set("swipe", not ns.db.swipe) end):SetTooltip(TIPS.swipe)
    root:CreateTitle("What to show")
    root:CreateCheckbox("Only CC I can apply", function() return ns.db.filter == "mine" end,
        function() ns.Set("filter", ns.db.filter == "mine" and "all" or "mine") end):SetTooltip(TIPS.filter)
    root:CreateDivider()
    root:CreateButton("All options...", function() ns.OpenSettings() end)
        :SetTooltip("Opens every Drpulse setting on its settings page.")
end

-- Previews (0.5.0) ---------------------------------------------------------------------
-- AGENTS.md "Previews in settings" (the user's choices of 11 October 2026):
-- a preview first under Size and placement and under Icon style, drawn by
-- Display.lua's own LayoutRow and PlaceRow from the same settings as the
-- target display and the plates: your target's row (Stun at 50%,
-- Incapacitate at 25%, Disorient immune) counting down to each reset with
-- its swipe, and beside it a stand-in nameplate (a bar and a name, not
-- Blizzard's) with its smaller row over or under it. Icon style adds an
-- unconfirmed cast, whose timer is grey (Show unconfirmed casts). Show on
-- screen plays the samples on the real target display for 20 seconds, as
-- Preview 20 s did. Categories starts with a strip of the eight category
-- icons at the target icon size, the ones not shown greyed. Samples are
-- fixed values (ns.SettingsSamples) with no unit, so the secret immune
-- border is never involved. Without PreviewKit.lua (a /reload before the
-- restart a file new to the TOC needs) there are no previews and the
-- Target display row keeps its Preview 20 s button.

local PLATE_W, PLATE_H, BAR_H = 110, 22, 8
local CAPTION_H, COLUMN_GAP = 14, 16
local SCREEN_TIP = "Show the sample icons (50%, 25% and immune) on your real target display where it sits on your screen for 20 seconds, without affecting tracking. The same as /drpulse preview."

-- A stand-in nameplate: a name over a bar in a black edge.
local function StandInPlate(parent)
    local plate = CreateFrame("Frame", nil, parent)
    plate:SetSize(PLATE_W, PLATE_H)
    plate.name = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    plate.name:SetPoint("TOP", 0, 0)
    plate.name:SetText("Varok")
    local edge = plate:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("BOTTOMLEFT", 0, 0)
    edge:SetPoint("BOTTOMRIGHT", 0, 0)
    edge:SetHeight(BAR_H)
    edge:SetColorTexture(0, 0, 0, 1)
    local bar = plate:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", edge, "TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -1, 1)
    bar:SetColorTexture(0.85, 0.15, 0.15, 1)
    return plate
end

-- The target display's samples and a stand-in plate's (and with unconfirmed,
-- an unconfirmed cast), counting down; key names it in page.previews.
local function DisplayPreview(page, key, unconfirmed)
    local preview = page.Preview(function() ns.Preview(20) end, SCREEN_TIP)
    if not preview then return end
    local holder = preview.holder
    page.previews = page.previews or {}
    page.previews[key] = preview
    local target = CreateFrame("Frame", nil, holder)
    local extra = unconfirmed and CreateFrame("Frame", nil, holder) or nil
    local column = CreateFrame("Frame", nil, holder)
    local plate = StandInPlate(column)
    local plateRow = CreateFrame("Frame", nil, column)
    local gap = CreateFrame("Frame", nil, column)
    local extraCaption = extra and preview.Caption()
    local captions = { target = preview.Caption(), plate = preview.Caption(), extra = extraCaption or nil }
    -- (preview.extra is the kit's: the label's extra height.)
    preview.target, preview.unconfirmed, preview.plate, preview.plateRow, preview.gap, preview.captions =
        target, extra, plate, plateRow, gap, captions

    -- The rows t seconds into the loop (started), or still.
    local started, drawn = 0, 0
    local function Draw(now, still)
        local db = ns.db
        local entries, cast = ns.SettingsSamples(now, (not still) and started or nil)
        ns.LayoutRow(target, entries, db.iconSize, nil, false, still)
        ns.LayoutRow(plateRow, entries, db.plateSize, nil, false, still)
        if extra then
            ns.LayoutRow(extra, (cast and ns.GetSource("assume")) and { cast } or nil, db.iconSize, nil, false, still)
        end
    end
    preview.loops[1] = {
        play = function(now, first)
            started, drawn = now - (first and 1.5 or 0), now
            Draw(now, false)
        end,
        -- As the live display, the timers are redrawn ten times a second;
        -- the swipes run by themselves.
        step = function(now)
            if now - drawn < 0.1 then return end
            drawn = now
            Draw(now, false)
        end,
        done = function() return GetTime() - started >= ns.SETTINGS_SAMPLE_LOOP end,
        still = function() Draw(GetTime(), true) end,
        stop = function() end,
    }

    -- What each row changes: the rows, the gap, and parts of every icon.
    local function Icons()
        local icons = {}
        for _, row in ipairs({ target, plateRow, extra }) do
            for _, icon in ipairs(row.icons or {}) do
                if icon:IsShown() then icons[#icons + 1] = icon end
            end
        end
        return icons
    end
    local function Each(pick)
        local regions = {}
        for _, icon in ipairs(Icons()) do pick(icon, regions) end
        return regions
    end
    preview.parts.target = function() return { target } end
    preview.parts.platerow = function() return { plateRow }, plate end
    preview.parts.plategap = function()
        if gap:IsShown() then return { gap }, plateRow end
        return { plateRow }, plate
    end
    preview.parts.stacks = function()
        return Each(function(icon, regions)
            for _, region in ipairs({ icon.count, icon.next, icon.pips[1], icon.pips[2], icon.pips[3] }) do
                if region:IsShown() then regions[#regions + 1] = region end
            end
        end), target
    end
    preview.parts.picture = function() return Each(function(icon, regions) regions[#regions + 1] = icon.texture end), target end
    preview.parts.timer = function()
        return Each(function(icon, regions) if icon.time:IsShown() then regions[#regions + 1] = icon.time end end), target
    end
    preview.parts.font = function()
        return Each(function(icon, regions)
            for _, region in ipairs({ icon.time, icon.count, icon.next }) do
                if region:IsShown() then regions[#regions + 1] = region end
            end
        end), target
    end
    preview.parts.swipe = function()
        if not ns.db.swipe then return {}, target end
        return Each(function(icon, regions) regions[#regions + 1] = icon.cooldown end), target
    end

    page.OnRefresh(function()
        local db = ns.db
        local size, plateSize, offset, above = db.iconSize, db.plateSize, db.plateOffset, db.plateAnchor == "TOP"
        offset = offset + (above and db.plateY or -db.plateY)
        local spacing = ns.ICON_SPACING
        local top, x = preview.top, preview.left
        Draw(GetTime(), true)
        -- Your target.
        captions.target:ClearAllPoints()
        captions.target:SetPoint("TOPLEFT", preview.text, "TOPLEFT", x, -top)
        local width = math.max(3 * size + 2 * spacing, 90)
        captions.target:SetWidth(width)
        captions.target:SetText("Your target" .. (db.target and "" or " · off"))
        target:ClearAllPoints()
        target:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -(top + CAPTION_H))
        local bottom = top + CAPTION_H + size
        x = x + width + COLUMN_GAP
        -- An unconfirmed cast.
        if extra and extraCaption then
            local on = ns.GetSource("assume")
            width = math.max(size, 100)
            extraCaption:ClearAllPoints()
            extraCaption:SetPoint("TOPLEFT", preview.text, "TOPLEFT", x, -top)
            extraCaption:SetWidth(width)
            extraCaption:SetText("Unconfirmed cast" .. (on and "" or " · off"))
            extra:ClearAllPoints()
            extra:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -(top + CAPTION_H))
            x = x + width + COLUMN_GAP
        end
        -- A stand-in plate with its row hung as PlaceRow hangs a live one, in
        -- the column's units with the plate's top at 0.
        local rowTop, rowBottom
        if above then
            rowBottom = -offset
            rowTop = rowBottom - plateSize
        else
            rowTop = PLATE_H + offset
            rowBottom = rowTop + plateSize
        end
        local first, last = math.min(0, rowTop), math.max(PLATE_H, rowBottom)
        local rowWidth = 3 * plateSize + 2 * spacing
        local left = math.min(0, (PLATE_W - rowWidth) / 2 + db.plateX)
        local right = math.max(PLATE_W, (PLATE_W + rowWidth) / 2 + db.plateX)
        width = right - left
        -- Keep extreme offsets inside the preview without changing saved values.
        local room = preview.left + preview.width - 12 - x
        if room < 140 or width > room then
            x, top = preview.left, bottom + COLUMN_GAP
            room = preview.width - 12
        end
        local scale = math.min(1, room / width, 180 / (last - first))
        captions.plate:ClearAllPoints()
        captions.plate:SetPoint("TOPLEFT", preview.text, "TOPLEFT", x, -top)
        captions.plate:SetWidth(math.max(110, width * scale))
        captions.plate:SetText("Enemy nameplate" .. (db.nameplates and "" or " · off"))
        column:ClearAllPoints()
        column:SetScale(scale)
        column:SetPoint("TOPLEFT", holder, "TOPLEFT", x / scale, -(top + CAPTION_H) / scale)
        column:SetSize(width, last - first)
        plate:ClearAllPoints()
        plate:SetPoint("TOPLEFT", column, "TOPLEFT", -left, first)
        ns.PlaceRow(plateRow, plate)
        gap:ClearAllPoints()
        if offset > 0 then
            if above then gap:SetPoint("BOTTOM", plate, "TOP", 0, 0) else gap:SetPoint("TOP", plate, "BOTTOM", 0, 0) end
            gap:SetSize(PLATE_W, offset)
            gap:Show()
        else
            gap:Hide()
        end
        bottom = math.max(bottom, top + CAPTION_H + (last - first) * scale)
        local notes = {}
        if scale < 1 then notes[#notes + 1] = "nameplate preview scaled to fit" end
        if not db.enabled then
            notes[#notes + 1] = AMBER_TEXT .. "Drpulse is off|r" .. GREY_TEXT
        end
        preview.SetLabel("Preview: your target's DR icons counting down to their reset"
            .. (extra and ", an unconfirmed cast" or "") .. " and a stand-in nameplate's"
            .. (#notes > 0 and (" · " .. table.concat(notes, " · ")) or ""))
        preview.Settle()
        preview.Fit(bottom + 4)
    end)
end

-- The Categories heading's strip: every category's icon at the target icon
-- size, the ones not shown greyed, and a line saying which and why. Looks
-- only, so it stays still.
local function CategoriesPreview(page)
    local preview = page.Preview()
    if not preview then return end
    local holder = preview.holder
    page.previews = page.previews or {}
    page.previews.categories = preview
    local icons = {}
    for _, category in ipairs(ns.CATEGORIES) do
        local icon = CreateFrame("Frame", nil, holder)
        icon.edge = icon:CreateTexture(nil, "BACKGROUND")
        icon.edge:SetAllPoints()
        icon.edge:SetColorTexture(0, 0, 0, 1)
        icon.texture = icon:CreateTexture(nil, "ARTWORK")
        icon.texture:SetPoint("TOPLEFT", 1, -1)
        icon.texture:SetPoint("BOTTOMRIGHT", -1, 1)
        icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icons[category] = icon
        preview.parts["category." .. category] = function() return { icon } end
    end
    local caption = preview.Caption()
    caption:SetWordWrap(true)
    preview.icons, preview.caption = icons, caption
    page.OnRefresh(function()
        local size, gap = ns.db.iconSize, 4
        local notes = {}
        local room = FULL - 12
        local scale = ns.PreviewKit.Scale(#ns.CATEGORIES * (size + gap) - gap, 1, notes, room)
        local shown, never, notYours = {}, {}, {}
        for index, category in ipairs(ns.CATEGORIES) do
            local icon = icons[category]
            local on = ns.ShouldShow(category)
            icon:SetScale(scale)
            icon:SetSize(size, size)
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", holder, "TOPLEFT", (preview.left + (index - 1) * (size + gap) * scale) / scale,
                -preview.top / scale)
            icon.texture:SetTexture(ns.CategoryIcon(category))
            icon.texture:SetDesaturated(not on)
            icon:SetAlpha(on and 1 or 0.35)
            local name = ns.CATEGORY_LABELS[category]
            if on then
                shown[#shown + 1] = name
            elseif ns.GetCategoryMode(category) == "never" then
                never[#never + 1] = name
            else
                notYours[#notYours + 1] = name
            end
        end
        local hidden = {}
        if #notYours > 0 then hidden[#hidden + 1] = table.concat(notYours, ", ") .. " (Auto: not yours)" end
        if #never > 0 then hidden[#hidden + 1] = table.concat(never, ", ") .. " (Never)" end
        caption:SetText("Shown: " .. (#shown > 0 and table.concat(shown, ", ") or "none")
            .. (#hidden > 0 and (" · not shown: " .. table.concat(hidden, "; ")) or ""))
        local y = preview.top + size * scale + 4
        caption:ClearAllPoints()
        caption:SetPoint("TOPLEFT", preview.text, "TOPLEFT", preview.left, -y)
        caption:SetWidth(room)
        local height = caption:GetStringHeight()
        y = y + ((type(height) == "number" and height > 0) and height or 12)
        preview.SetLabel("Preview: every category's icon at your target icon size, the ones not shown greyed"
            .. (#notes > 0 and (" · " .. table.concat(notes, " · ")) or ""))
        preview.Settle()
        preview.Fit(y + 2)
    end)
end

-- The page ---------------------------------------------------------------------------
local function Build()
    local page = NewPage("Drpulse")
    local header = page.Block(78)
    local brand = CreateFrame("Frame", nil, header, "BackdropTemplate")
    brand:SetPoint("TOPLEFT", NAME_X, -7)
    brand:SetSize(FULL, 62)
    brand:SetBackdrop(backdrop)
    brand:SetBackdropColor(0.025, 0.085, 0.12, 1)
    brand:SetBackdropBorderColor(0.10, 0.30, 0.40, 1)
    local mark = brand:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", 0, 0)
    mark:SetPoint("BOTTOMLEFT", 0, 0)
    mark:SetWidth(3)
    mark:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    local title = brand:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -10)
    title:SetText("TRACKING STATUS")
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    local version = brand:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    version:SetPoint("LEFT", title, "RIGHT", 9, 0)
    version:SetText("v" .. ns.VERSION)
    version:SetTextColor(GREY[1], GREY[2], GREY[3])
    local command = brand:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    command:SetPoint("TOPRIGHT", -14, -12)
    command:SetText("/drpulse")
    command:SetTextColor(0.72, 0.89, 0.96)
    local purpose = brand:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    purpose:SetPoint("TOPLEFT", 16, -29)
    purpose:SetText("Enemy and friendly diminishing returns control deck")
    purpose:SetTextColor(0.67, 0.73, 0.78)
    local status = brand:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 16, 9)
    status:SetPoint("BOTTOMRIGHT", -14, 9)
    status:SetJustifyH("LEFT")
    page.OnRefresh(function()
        if not ns.db.enabled then
            status:SetText(AMBER_TEXT .. "Drpulse is off: nothing is tracked or shown.|r")
        elseif ns.GetBlizzardOption(ns.CVAR_ENABLED) == false and ns.GetSource("native") then
            status:SetText(AMBER_TEXT .. "Blizzard's DR option is off; Drpulse turns it back on out of combat.|r")
        elseif ns.GetBlizzardOption(ns.CVAR_ENABLED) == false then
            status:SetText(AMBER_TEXT .. "Blizzard's DR data is off; Blizzard data has a button to turn it on.|r")
        else
            status:SetText(GREY_TEXT .. "Blizzard DR data seen: " .. tostring(ns.nativeMode) .. "|r")
        end
    end)

    page.Group("Displays", true, function()
        if not ns.db.enabled then return "Off" end
        local where = {}
        if ns.db.target then where[#where + 1] = "target" end
        if ns.db.nameplates then where[#where + 1] = "nameplates" end
        if ns.db.friendly then where[#where + 1] = "friendly" end
        return "On · " .. (#where > 0 and table.concat(where, ", ") or "no display")
            .. (ns.db.npcs and " · NPCs" or "") .. (ns.db.locked and "" or " · unlocked")
    end, "Where the DR icons show, and the target display's place.")
    page.Row("Enable Drpulse", "Master switch. Turning it off stops tracking and hides every display.")
        :Toggle(C1, "enabled")
    page.Row("On your target", "Show your current enemy target's DR icons in a movable display.")
        :Toggle(C1, "target")
    page.Row("On enemy nameplates", "Show DR icons above or below every visible enemy player's nameplate.")
        :Toggle(C1, "nameplates")
    page.Row("Also track NPCs", "Track and show DR on hostile NPCs too. PvP DR rules are applied to them, which may not match PvE rules.")
        :Toggle(C1, "npcs")
    page.Row("Lock target display", TIPS.locked)
        :Toggle(C1, { key = "locked", get = function() return ns.db.locked end, set = function(value) ns.SetLocked(value) end })
    -- 0.5.0: Preview 20 s moved to Show on screen on the Size and placement
    -- and Icon style previews; it stays here until a restart loads the kit.
    local kit = ns.PreviewKit ~= nil
    local targetDisplay = page.Row("Target display", "Reset position moves the target display back to its default position."
        .. (kit and " To see sample icons on it, use Show on screen on the preview under Size and placement or Icon style (or /drpulse preview)."
            or " Preview 20 s shows sample icons (50%, 25% and immune) on it without affecting tracking."))
    targetDisplay:Button(C1, "Reset position", TwoClicks("Reset position", function() ns.ResetPosition() end))
    if not kit then targetDisplay:Button(C2, "Preview 20 s", function() ns.Preview(20) end) end

    page.Group("Friendly DR", true, function()
        if not ns.db.friendly then return "Off" end
        local watched = 0
        for _, unit in ipairs(ns.FRIEND_UNITS) do
            if ns.WatchedUnits()[unit] then watched = watched + 1 end
        end
        return "On · " .. (ns.db.friendlyPlayer and "you and " or "") .. "party · watching " .. watched
            .. " · " .. ns.db.friendlySize .. " px"
    end, "DR on you and your party members, in a display of its own: a row per player with DR, hidden while nobody has any.")
    page.Row("Track friendly DR", "Track the DR enemies put on you and your party, and show it in the friendly display: one row per player, their name, then their DR icons. It moves and locks with Lock target display; /drpulse friendly turns it on or off. Every category shows there unless set to Never under Categories.")
        :Toggle(C1, "friendly")
    page.Row("Include yourself", "Show a row for your own DR. Your own crowd control comes from Loss of control on you (Tracking sources), which Forever keeps readable for you even where auras are secret.")
        :Toggle(C1, "friendlyPlayer")
    page.Row("Friendly icon size", "Size of the icons in the friendly display.")
        :Slider(C1, "friendlySize", 1, " px")

    page.Group("What to show", true, function()
        if ns.db.filter ~= "mine" then return "Every category" end
        return "Only CC you can apply" .. (ns.db.items and " · bag items count" or "")
    end, "Which DR categories show. Each category's own choice is under Categories.")
    page.Row("Only CC I can apply", TIPS.filter)
        :Toggle(C1, { key = "filter", get = function() return ns.db.filter == "mine" end,
            set = function(value) ns.Set("filter", value and "mine" or "all") end })
    page.Row("Count CC items in bags", "Grenades, bombs, Net-o-Matic, Tidal Charm and similar items in your bags make their category yours.")
        :Toggle(C1, "items")

    page.Group("Categories", false, function()
        local shown, yours = 0, 0
        for _, category in ipairs(ns.CATEGORIES) do
            if ns.ShouldShow(category) then shown = shown + 1 end
            if ns.mine[category] then yours = yours + 1 end
        end
        return shown .. " of " .. #ns.CATEGORIES .. " shown · " .. yours .. " yours"
    end, "Auto, Always or Never for each DR category, and which ones you can apply now. A strip at the top shows every category's icon, the ones not shown greyed.")
    CategoriesPreview(page)
    page.Row("You can apply", "The categories your known spells, pet and (with Count CC items in bags) bag items can cause, as detected now.", nil, 36)
        :Status(function()
            local names = {}
            for _, category in ipairs(ns.CATEGORIES) do
                if ns.mine[category] then names[#names + 1] = ns.CATEGORY_LABELS[category] end
            end
            return #names > 0 and table.concat(names, ", ") or "none detected"
        end, C1, WIDE)
    for _, category in ipairs(ns.CATEGORIES) do
        local label = ns.CATEGORY_LABELS[category]
        local row = page.Row(label, "Auto follows Only CC I can apply. Always shows this category regardless; Never hides it.",
            "category." .. category)
        local icon = row.name:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("LEFT", 4, 0)
        icon:SetSize(16, 16)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon = icon
        row.name.label:ClearAllPoints()
        row.name.label:SetPoint("LEFT", 26, 0)
        row.name.label:SetPoint("RIGHT", -8, 0)
        row:Choice(C1, { key = "categories." .. category, options = MODES,
            get = function() return ns.GetCategoryMode(category) end,
            set = function(mode) ns.SetCategoryMode(category, mode) end }, MODE_LABELS)
        row:Status(function()
            return (ns.mine[category] and (GREEN_TEXT .. "yours|r  ") or "") .. (ns.ShouldShow(category) and "shown" or "hidden")
        end)
        page.OnRefresh(function() icon:SetTexture(ns.CategoryIcon(category)) end)
    end

    local function Source(key)
        return { key = "sources." .. key, get = function() return ns.GetSource(key) end,
            set = function(value) ns.SetSource(key, value) end }
    end
    page.Group("Tracking sources", false, function()
        local on, total = 0, 0
        for key in pairs(ns.SOURCE_KEYS) do
            total = total + 1
            if ns.GetSource(key) then on = on + 1 end
        end
        return on .. " of " .. total .. " on · reset " .. tostring(ns.db.resetTime) .. " s"
    end, "Where Drpulse learns about CC; each can be switched off. Also how long a category takes to reset.")
    page.Row("Blizzard DR feed", "Blizzard's own DR tracker (UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED). When its data is readable it is authoritative for timers and immunity. When Forever hides the values, it still confirms which of your casts landed. While this is on, Drpulse keeps Blizzard's 'diminishing returns on PvP enemies' option on; turn this off to leave that option alone.")
        :Toggle(C1, Source("native"))
    page.Row("Enemy CC auras", "Readable CC auras on enemies, from anyone: you, your group, items and racials. Gives exact start and end times, and infers the DR stage from a shortened duration.")
        :Toggle(C1, Source("auras"))
    page.Row("My and my pet's casts", "Your and your pet's successful CC casts. Confirmed by an aura or the Blizzard feed when possible.")
        :Toggle(C1, Source("casts"))
    page.Row("Group members' CC", "Count CC from party and raid members: their readable casts on their target, and CC auras cast by someone other than you. DR is shared, so your group's CC shortens yours.")
        :Toggle(C1, Source("group"))
    page.Row("Immune / resist feedback", "An IMMUNE response to your CC when the enemy is one application from immunity marks the category immune. A miss or resist cancels an unconfirmed cast.")
        :Toggle(C1, Source("feedback"))
    page.Row("Loss of control on you", "Your own loss-of-control effects (the alert in the middle of the screen) for friendly DR: exact spell, start and length, readable for you even where CC auras are secret. A spell outside the catalog counts only when its effect type has one DR category (stun, root, silence, disarm).")
        :Toggle(C1, Source("loss"))
    page.Row("Show unconfirmed casts", "If nothing can confirm whether your CC landed, count it anyway. Its timer is grey (the Icon style preview shows one). Casts are never assumed when a confirming source was available and stayed silent.")
        :Toggle(C1, Source("assume"))
    page.Row("DR reset time", "Seconds after the last CC in a category ends before its DR resets (10 to 30; 18 by default).")
        :Slider(C1, "resetTime", 1, " s")

    local function BlizzardState(name)
        local value = ns.GetBlizzardOption(name)
        return "Blizzard: " .. (value == nil and "not in this client" or (value and "on" or "off"))
    end
    page.Group("Blizzard data", false, function()
        local enabled = ns.GetBlizzardOption(ns.CVAR_ENABLED)
        if enabled == nil then return "Not in this client" end
        if not enabled then return "DR option off" end
        return "DR option on · " .. (ns.GetBlizzardOption(ns.CVAR_ONLY_MINE) == true and "only your CC" or "all CC")
    end, "Blizzard's own DR feed: whether it is listening, what its updates carry, and the two Blizzard options it depends on.")
    page.Row("Blizzard feed", "Whether Blizzard's DR feed is listening on this client, or why it is unavailable.", nil, 36)
        :Status(function() return ns.nativeStatus end, C1, WIDE)
    page.Row("Data seen", "What Blizzard's DR updates have carried so far: readable, category only, secret (display only) or opaque (event only).")
        :Status(function() return ns.nativeMode end, C1, WIDE)
    local enemies = page.Row("Blizzard DR data", "Blizzard sends DR updates only while its own 'diminishing returns on PvP enemies' option (Options -> Gameplay -> Advanced) is on, so while Blizzard DR feed (Tracking sources) is on Drpulse turns it on itself, out of combat, and again whenever it is turned off. Turn on sets it now. On Forever it draws nothing else: Blizzard's DR tray belongs to arena frames Forever does not load. Beside it: the option's state now.")
    enemies:Button(C1, "Turn on", function()
        if ns.SetBlizzardOption(ns.CVAR_ENABLED, true) then ns.Notice("Blizzard enemy DR option enabled.") end
    end)
    enemies:Status(function() return BlizzardState(ns.CVAR_ENABLED) end)
    local onlyMine = page.Row("Blizzard: only my CC", "Blizzard's 'only CC triggerable by me' filter hides group CC from Drpulse. Report all CC turns it off so group CC arrives; Drpulse's own Only CC I can apply still decides what is shown. Beside it: the filter's state now.")
    onlyMine:Button(C1, "Report all CC", function()
        if ns.SetBlizzardOption(ns.CVAR_ONLY_MINE, false) then ns.Notice("Blizzard now reports every DR category; Drpulse filters them itself.") end
    end)
    onlyMine:Status(function() return BlizzardState(ns.CVAR_ONLY_MINE) end)

    page.Group("Size and placement", false, function()
        return "Target " .. ns.db.iconSize .. " px · plates " .. ns.db.plateSize .. " px "
            .. (ns.db.plateAnchor == "BOTTOM" and "below" or "above")
    end, "How large the icons are, and where they sit on nameplates, with a preview at the top that follows every change here.")
    DisplayPreview(page, "size")
    page.Row("Target icon size", TIPS.iconSize, "target")
        :Slider(C1, "iconSize", 1, " px")
    page.Row("Nameplate icon size", "Size of the icons on enemy nameplates.", "platerow")
        :Slider(C1, "plateSize", 1, " px")
    page.Row("Nameplate offset", "Distance between the nameplate and its DR icons.", "plategap")
        :Slider(C1, "plateOffset", 1, " px")
    page.Row("Nameplate icons", "Place nameplate DR icons above or below the nameplate.", "platerow")
        :Choice(C1, "plateAnchor", { TOP = "Above", BOTTOM = "Below" })
    page.Row("Nameplate horizontal", "Move all nameplate DR icons left (negative) or right (positive), relative to their nameplate.", "platerow")
        :Slider(C1, "plateX", 1, " px")
    page.Row("Nameplate vertical", "Move all nameplate DR icons down (negative) or up (positive), in addition to the above/below separation.", "platerow")
        :Slider(C1, "plateY", 1, " px")

    page.Group("Icon style", false, function()
        return (STACK_LABELS[ns.db.stackStyle] or tostring(ns.db.stackStyle)) .. " · "
            .. (ICON_LABELS[ns.db.iconSource] or tostring(ns.db.iconSource)):lower()
            .. (ns.db.timer and " · timer" or " · no timer") .. (ns.db.swipe and " · swipe" or "")
    end, "What each icon shows: its stacks, its picture, the reset timer and the swipe, with a preview at the top that follows every change here.")
    DisplayPreview(page, "style", true)
    page.Row("Icon font", "Font for timer, application count and next-CC text on the target and nameplates. Game default restores the client's font; unavailable fonts fall back to it.", "font")
        :Choice(C1, "font", ns.FONT_LABELS)
    page.Row("Stacks", TIPS.stackStyle, "stacks")
        :Choice(C1, "stackStyle", STACK_LABELS)
    page.Row("Icon", TIPS.iconSource, "picture")
        :Choice(C1, "iconSource", ICON_LABELS)
    page.Row("Reset timer text", TIPS.timer, "timer")
        :Toggle(C1, "timer")
    page.Row("Countdown swipe", TIPS.swipe, "swipe")
        :Toggle(C1, "swipe")

    page.Group("Custom spells", false, function()
        local count = 0
        for _ in pairs(ns.db.custom) do count = count + 1 end
        if count == 0 then return "No custom spells" end
        return count == 1 and "1 custom spell" or (count .. " custom spells")
    end, "Add or correct a spell's category, for Forever changes or missing effects. Up to 128 spells.")
    local customCategory = "Stun"
    local spell = page.Row("Spell and category", "Add or correct a spell's category, for Forever changes or missing effects: the numeric spell ID of the CC effect, as shown by the aura, and the category to assign.")
    local edit = CreateFrame("EditBox", nil, spell.frame, "BackdropTemplate")
    edit:SetPoint("TOPLEFT", C1, -2)
    edit:SetSize(CW, 22)
    edit:SetBackdrop(backdrop)
    edit:SetBackdropColor(0.04, 0.04, 0.05, 1)
    edit:SetBackdropBorderColor(0, 0, 0, 1)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetTextInsets(8, 8, 0, 0)
    edit:SetAutoFocus(false)
    edit:SetNumeric(true)
    edit:SetMaxLetters(8)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    Tooltip(edit, "Spell ID", "Numeric spell ID of the CC effect, as shown by the aura.")
    spell.edit = edit
    spell:Choice(C2, { options = ns.CATEGORIES, get = function() return customCategory end,
        set = function(value) customCategory = value end }, ns.CATEGORY_LABELS)
    local custom = page.Row("Custom spell", "Add / update saves this spell ID with the selected category, overriding the bundled category. Remove deletes its custom category; the bundled category (if any) applies again.")
    custom:Button(C1, "Add / update", function()
        local id = tonumber(edit:GetText())
        if id and ns.SetCustomSpell(id, customCategory) then ns.Notice(ns.SpellName(id) .. " (" .. id .. ") -> " .. ns.CATEGORY_LABELS[customCategory])
        else ns.Print("Enter a valid spell ID (limit 128 custom spells).") end
    end)
    custom:Button(C2, "Remove", function()
        local id = tonumber(edit:GetText())
        if id and ns.db.custom[id] then ns.SetCustomSpell(id, nil); ns.Notice("Removed custom spell " .. id .. ".") end
    end)
    -- The saved custom spells, three to a line, the first twelve.
    local function CustomLines()
        local ids = {}
        for id in pairs(ns.db and ns.db.custom or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        local parts = {}
        for index = 1, math.min(#ids, 12) do
            parts[#parts + 1] = ids[index] .. " " .. ns.CATEGORY_LABELS[ns.db.custom[ids[index]]]
        end
        if #ids > 12 then parts[#parts + 1] = "+" .. (#ids - 12) .. " more" end
        local lines = {}
        for index = 1, #parts, 3 do
            lines[#lines + 1] = table.concat({ parts[index], parts[index + 1], parts[index + 2] }, ",  ")
        end
        return lines
    end
    local listFrame, listBlock = page.Block(19)
    local list = Text(listFrame, "", NAME_X + 8, -3, nil, FULL - 8)
    listBlock.measure = function() return 6 + 13 * math.max(1, #CustomLines()) end
    page.customList = list
    page.OnRefresh(function()
        local lines = CustomLines()
        list:SetText(#lines > 0 and table.concat(lines, "\n") or (GREY_TEXT .. "No custom spells.|r"))
    end)

    page.Group("Advanced", false, function()
        return "Chat messages " .. (ns.db.chat and "on" or "off")
    end, "Chat messages, clearing tracked DR, the status report and the appearance reset.")
    page.Row("Chat messages", "Print Drpulse's own messages in chat (Blizzard DR option changes, custom spells added or removed). Turn off to keep chat quiet; replies to slash commands you type and warnings when something fails still show.")
        :Toggle(C1, "chat")
    local tracked = page.Row("Tracked DR", "Clear tracked DR forgets all current DR states, for example after a duel or when testing. Print status to chat prints the Blizzard feed mode, evidence counters and recent readable native samples; include it when reporting problems.")
    tracked:Button(C1, "Clear tracked DR", function() ns.ClearTracking() end)
    tracked:Button(C2, "Print status to chat", function() ns.PrintStatus() end)
    page.Row("Appearance", "Restore icon sizes, placement and style defaults. Position and tracking settings are kept.")
        :Button(C1, "Reset appearance", TwoClicks("Reset appearance", function() ns.ResetDisplaySettings() end))

    page.Group("Diagnostics", false, function()
        local s = ns.stats
        return s.confirmed .. " confirmed, " .. s.assumed .. " assumed, " .. s.notLanded .. " missed"
    end, "What the tracking sources have seen since the last reload. Print status to chat under Advanced has more.")
    local function Counter(label, detail, fn)
        page.Row(label, detail):Status(fn, C1, WIDE)
    end
    Counter("Blizzard updates", "DR updates from Blizzard's feed, and how many of them were readable.",
        function() return string.format("%d (%d readable)", ns.stats.native, ns.stats.nativePublic) end)
    Counter("CC auras", "Readable CC auras seen landing on tracked enemies.",
        function() return tostring(ns.stats.auraApplied) end)
    Counter("Friendly CC", "CC seen landing on you and your party: readable CC auras on them, and your own loss-of-control effects.",
        function() return string.format("%d auras, %d on you", ns.stats.friendlyAuras, ns.stats.lossApplied) end)
    Counter("CC casts", "CC casts seen from you, your pet and your group.",
        function() return tostring(ns.stats.casts + ns.stats.groupCasts) end)
    Counter("Confirmed", "Casts confirmed by an aura or the Blizzard feed.",
        function() return tostring(ns.stats.confirmed) end)
    Counter("Assumed", "Casts counted with nothing to confirm them (shown grey).",
        function() return tostring(ns.stats.assumed) end)
    Counter("Missed", "Casts that did not land: missed, resisted, or a confirming source stayed silent.",
        function() return tostring(ns.stats.notLanded) end)

    -- How to use, always open at the bottom (0.6.0): the mouse, then the
    -- commands and the tracking commands, each a line of text: what it does,
    -- then how in grey.
    local Control = page.Note
    page.Help(function() return "11 controls · 12 commands" end,
        "What the mouse does on the target display and on this page, and the chat shortcuts. Hover a line for more.")
    page.Topic("Mouse")
    Control("Move the target display", "Drag the blue strip above it", "With Lock target display off, a thin blue strip sits above the target display: drag it, or the icons under it, to move the display. Not in combat.")
    Control("Resize the icons", "Drag the dots at its corner", "With Lock target display off, six dots sit at the target display's bottom right corner: drag them to make the icons bigger or smaller (Target icon size). The top left corner stays put.")
    Control("Default icon size", "Double-click the corner dots", "Puts Target icon size back to its default.")
    Control("Lock the target display", "Right-click the unlocked display", "Locks the target display in place again, like turning Lock target display on. Locked, it shows only its icons and lets clicks through.")
    Control("Quick settings", "The gear on the strip", "Lock, icon size, icon style and what to show in a short menu, ending in All options... for this page.")
    Control("Move the friendly display", "Drag the blue strip above it", "With Lock target display off, the friendly display shows a blue strip too, with a sample row when nobody has DR: drag it to move the display, right-click it to lock. Not in combat.")
    Control("Icon details", "Hover a target display icon", "Applications, time to reset, last spell and which evidence produced it.")
    Control("Pick from a list", "Click a value with many choices", "A value button with four or more choices (the custom spell's category) opens a list under it; click a row to pick it; a click anywhere else, or Escape out of combat, closes the list.")
    Control("Next or previous value", "2 or 3 choices: click; right-click goes back", "A value button with two or three choices steps to its next choice, or back to the one before.")
    Control("Slider back to its default", "The arrow at the end of a slider", "In colour once you have moved the slider: a click puts the default back. Grey when it is already the default.")
    Control("What a setting does", "Hover its row", "Each row's tooltip explains its setting.")

    page.Topic("Commands")
    Control("Settings and command list", "/drpulse", "Opens this page and lists every command in chat.")
    Control("Open settings", "/drpulse options", "Opens this page without listing the commands (also /drpulse config).")
    Control("List commands", "/drpulse help", "Lists every command in chat.")
    Control("Unlock the target display", "/drpulse unlock", "Shows the blue strip, the corner dots and moving sample icons so you can move and resize the target display.")
    Control("Lock the display", "/drpulse lock", "Locks the target display in place.")
    Control("Reset its position", "/drpulse reset", "Puts the target display back in its default place.")
    Control("Preview the display", "/drpulse preview", "Shows sample icons on the target display for 20 seconds (also /drpulse test), like Show on screen on a preview.")

    page.Topic("Tracking commands")
    Control("Forget tracked DR", "/drpulse clear", "Forgets every tracked DR, like Clear tracked DR.")
    Control("Friendly DR on or off", "/drpulse friendly", "Turns Track friendly DR on or off.")
    Control("Show every category", "/drpulse all", "Turns Only CC I can apply off.")
    Control("Only what you can apply", "/drpulse mine", "Turns Only CC I can apply on.")
    Control("Status report", "/drpulse status", "Prints the version, build and what the addon sees, like Print status to chat.")
    return page
end

-- Standalone window ------------------------------------------------------------------
function ns.BuildSettings()
    local page = Build()
    local panel = page.panel
    ns.RefreshSettings = function()
        if panel:IsShown() then
            page.Layout()
            page.Refresh()
        end
    end
    ns.OnSettingChanged(function() ns.RefreshSettings() end)
    function ns.OpenSettings()
        panel:Show()
    end
end
