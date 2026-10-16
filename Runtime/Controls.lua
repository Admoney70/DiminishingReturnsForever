-- Adapted from Forever DR FlatMenu.lua (MIT, Copyright 2026 Tarolg).
-- Drpulse integration and visual adaptations: Copyright 2026 Joaqoz.
local _, ns = ...
-- Forever flat menu, kit 6 (11 October 2026; kit 1, 10 October). The workspace's one look for
-- dropdown lists and right-click menus (AGENTS.md, "Shared UI style"): a dark
-- panel in a 1-pixel black edge, flat rows each in a black edge, a gold line
-- inside the row under the mouse, a small box that fills gold for a choice
-- that is on, and submenus that fly out to the side. Every addon that draws a
-- menu carries an identical copy of this file; tools/flat-menu/FlatMenu.lua is
-- the master, and tools/flat-menu/Sync-FlatMenu.ps1 copies it out and checks
-- the copies. Change the master, never a copy.
--
-- A menu is described as Blizzard's are (MenuUtil.CreateContextMenu,
-- Blizzard_Menu/MenuUtil.lua): Open calls generator(owner, root), and root and
-- every entry it makes take
--   CreateTitle(text), CreateDivider(),
--   CreateButton(text, callback, data),
--   CreateRadio(text, isSelected, setSelected, data),
--   CreateCheckbox(text, isSelected, setSelected, data),
--   CreateSlider(text, get, set, min, max, step, format, default),
--   CreateInput(text, get, set, options),
--   SetScrollMode(height),
-- and each entry SetEnabled(enabled or fn(entry)), SetTooltip(fn(tooltip,
-- entry)), SetOnEnter(fn(row, entry)), SetOnLeave(fn(row, entry)) and
-- GetData(). An entry given entries of its own is a submenu,
-- flown out beside it while the mouse is on it. root:AddMenuReleasedCallback(fn)
-- runs when the menu closes. Callbacks get (data, { buttonName }, ns.FlatMenu)
-- as Blizzard's do, and may return a MenuResponse (Blizzard_Menu/
-- MenuConstants.lua): Open or Refresh keep the menu open, Close or CloseAll
-- close it. Otherwise a button or a radio closes it and a tick box, a slider
-- or an input keeps it open; options.keepOpen keeps it open for radios too.
--
-- ns.FlatMenu.Open(owner, generator, options) opens a dropdown under owner;
-- opening it again from the same owner closes it. ns.FlatMenu.OpenAtCursor
-- opens a right-click menu at the cursor (owner may be nil). options:
--   minWidth  at least this wide (a dropdown is at least its owner's width)
--   point     { point, relativePoint, x, y } against owner instead of below
--   keepOpen  radios leave the menu open
--   onClose   called once the menu has closed
--
-- A click anywhere else closes it (GLOBAL_MOUSE_DOWN, as Blizzard's menus,
-- Blizzard_Menu/Menu.lua; the click still reaches what was under it), and so
-- does its owner hiding. Escape closes it out of combat:
-- SetPropagateKeyboardInput is restricted in combat (SimpleFrameAPIDocumentation,
-- HasRestrictions), so in combat it takes no keys and Escape reaches the game,
-- as Forever Settings' window does. Nothing here touches Blizzard's menus or
-- Blizzard's Escape handlers, and every frame is the addon's own.
--
-- Kit 2: a slider given its default has a reset arrow at the end of its row
-- (AGENTS.md, "Gears and quick settings"): gold while the value differs from
-- the default, when a click sets the default; grey once it is the default.
-- Its tooltip says "Reset to default". ns.FlatMenu.ResetArt(texture, changed)
-- draws that arrow on any texture, for the settings pages that carry the kit.
--
-- Kit 3: a slider's name and value take the room their text needs (the
-- widest name and value in that list), and a dropdown stays where it opened
-- when its owner moves while it is open (a slider that resizes or rescales
-- its owner's box no longer drags the menu away from the cursor).
--
-- Kit 4 (11 October 2026, the user: "it doesn't make sense that some are
-- gold and some aren't"): actions are no longer gold. Every row's name is
-- light grey; gold is kept for headings and for the name of a choice or tick
-- box that is on.
--
-- Kit 5 (11 October 2026, AGENTS.md "Previews in settings", try a choice
-- before picking it): SetOnEnter and SetOnLeave, as on Blizzard's menu
-- descriptions (MenuElementDescriptionProxyMixin in Blizzard_Menu/Menu.lua),
-- call fn(row, entry) as the mouse comes onto an enabled row and leaves it,
-- so a settings page can show the choice under the mouse in its preview and
-- put its own back on leave (and on AddMenuReleasedCallback).
--
-- Kit 6 (11 October 2026, the user: "when i hover over an option in our
-- gears menus, it should have a tooltip explaining it"): SetTooltip also
-- takes a plain string, drawn under the entry's name in light grey and
-- wrapped, so a menu can give every entry its explanation in one call.
-- ns.FlatMenu.Untipped(owner, generator) lists, for the offline tests, the
-- names of every entry in a menu and its submenus that has no tooltip
-- (headings and dividers need none).

local Menu = {}
ns.FlatMenu = Menu

local WHITE = "Interface\\Buttons\\WHITE8X8"
local BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } }
local EDGE = { edgeFile = WHITE, edgeSize = 1 }
local PANEL = { 0.075, 0.08, 0.09, 0.98 }
local ROW_BG, HOVER = { 0.14, 0.145, 0.16 }, { 0.10, 0.20, 0.27 }
local LINE = { 0.24, 0.65, 0.82 }
local GOLD, TEXT = { 0.38, 0.85, 1.00 }, { 0.92, 0.92, 0.92 }
local GREY, OFF = { 0.55, 0.55, 0.58 }, { 0.45, 0.45, 0.47 }
local EMPTY, FIELD = { 0.05, 0.05, 0.06 }, { 0.1, 0.105, 0.12 }
local HEIGHTS = { title = 18, divider = 7, button = 20, radio = 20, check = 20, slider = 24, input = 24 }
local POOLS = { title = "title", divider = "divider", button = "row", radio = "row", check = "row", slider = "slider", input = "input" }
local PAD, MIN_WIDTH, MAX_WIDTH, BAR = 3, 120, 360, 8
local SLIDER_WIDTH, INPUT_WIDTH = 200, 200
local CLOSE_DELAY = 0.15

local state = { open = false, serial = 0, closeToken = 0, hovered = 0 }
local panels = {}
local watcher
local Close, Refresh, Draw, OpenSub, CloseFrom, Activate, Remember

-- Helpers ----------------------------------------------------------------------
local function Number(value)
    if type(value) ~= "number" then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function Flag(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function Over(frame)
    if type(frame) ~= "table" or type(frame.IsMouseOver) ~= "function" then return false end
    return Flag(frame:IsMouseOver()) == true
end

local function Response(name)
    -- Blizzard_Menu/MenuConstants.lua's global, absent from the LuaLS annotations.
    ---@diagnostic disable-next-line: undefined-global
    local responses = MenuResponse
    return type(responses) == "table" and responses[name] or nil
end

local function Clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- Descriptions -------------------------------------------------------------------
local Description = {}
Description.__index = Description

local function Add(parent, entry)
    entry.parent = parent
    entry.children = {}
    parent.children[#parent.children + 1] = entry
    return setmetatable(entry, Description)
end

function Description:CreateTitle(text) return Add(self, { kind = "title", text = text }) end
function Description:CreateDivider() return Add(self, { kind = "divider" }) end
function Description:CreateButton(text, callback, data)
    return Add(self, { kind = "button", text = text, callback = callback, data = data })
end
function Description:CreateRadio(text, isSelected, setSelected, data)
    return Add(self, { kind = "radio", text = text, isSelected = isSelected, setSelected = setSelected, data = data })
end
function Description:CreateCheckbox(text, isSelected, setSelected, data)
    return Add(self, { kind = "check", text = text, isSelected = isSelected, setSelected = setSelected, data = data })
end
-- get() returns the value now; set(value) is called as the thumb moves;
-- format(value) is the text after the track (the value, rounded, by default);
-- default, when given, adds the reset arrow.
function Description:CreateSlider(text, get, set, low, high, step, format, default)
    return Add(self, { kind = "slider", text = text, get = get, set = set, low = low, high = high,
        step = step, format = format, default = Number(default) })
end
-- An edit box. get() returns its text; set(text) is called on Enter, on its
-- button and when the menu closes with the text changed. options: width,
-- numeric, maxLetters, button (a label for a button that sets and closes), and
-- stayOpen (Enter keeps the menu open).
function Description:CreateInput(text, get, set, options)
    return Add(self, { kind = "input", text = text, get = get, set = set, options = options or {} })
end
function Description:SetScrollMode(height) self.scrollHeight = Number(height) end
function Description:SetEnabled(enabled) self.enabled = enabled end
function Description:SetTooltip(tooltip) self.tooltip = tooltip end
function Description:SetOnEnter(onEnter) self.onEnter = onEnter end
function Description:SetOnLeave(onLeave) self.onLeave = onLeave end
function Description:GetData() return self.data end
function Description:AddMenuReleasedCallback(callback)
    local root = self
    while root.parent do root = root.parent end
    root.released[#root.released + 1] = callback
end
function Description:IsEnabled()
    local enabled = self.enabled
    if type(enabled) == "function" then enabled = enabled(self) end
    return Flag(enabled) ~= false
end
function Description:IsSelected()
    if type(self.isSelected) ~= "function" then return false end
    return Flag(self.isSelected(self.data)) and true or false
end
function Description:HasSubmenu() return self.kind ~= "root" and #self.children > 0 end

local function Build(owner, generator)
    local root = setmetatable({ kind = "root", children = {}, released = {} }, Description)
    generator(owner, root)
    return root
end

local function IndexOf(list, item)
    for index, value in ipairs(list) do
        if value == item then return index end
    end
end

-- Rows ----------------------------------------------------------------------------
local function Paint(frame, color)
    frame:SetBackdropColor(color[1], color[2], color[3], 1)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
end

-- A row's look: flat in a black edge, a gold line inside while lit.
local function Skin(row, lit)
    Paint(row, lit and HOVER or ROW_BG)
    row.line:SetShown(lit and true or false)
end

local function GoldLine(frame)
    local line = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    line:SetPoint("TOPLEFT", 1, -1)
    line:SetPoint("BOTTOMRIGHT", -1, 1)
    line:SetBackdrop(EDGE)
    line:SetBackdropBorderColor(LINE[1], LINE[2], LINE[3], 1)
    line:Hide()
    return line
end

local function Label(frame, font)
    local label = frame:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    return label
end

local function IsOpenParent(row)
    local next = panels[row.menuLevel + 1]
    return next ~= nil and next:IsShown() and next.menuEntry ~= nil and next.menuEntry == row.menuEntry
end

local function HideTip()
    if state.tipRow then
        state.tipRow = nil
        GameTooltip:Hide()
    end
end

-- A row's tooltip sits beside the menu, never over it: left of the menu for
-- a submenu's row (its flyout is on the right), right of it otherwise.
local function ShowTip(row)
    local entry = row.menuEntry
    local tip = entry.tooltip
    if type(tip) ~= "function" and type(tip) ~= "string" then return end
    GameTooltip:SetOwner(row, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    if entry:HasSubmenu() then
        GameTooltip:SetPoint("TOPRIGHT", row.menuPanel, "TOPLEFT", -2, 0)
    else
        GameTooltip:SetPoint("TOPLEFT", row.menuPanel, "TOPRIGHT", 2, 0)
    end
    if type(tip) == "string" then
        -- Kit 6: the entry's name, then the explanation.
        GameTooltip:SetText(entry.text or "", 1, 1, 1)
        GameTooltip:AddLine(tip, TEXT[1] * 0.92, TEXT[2] * 0.92, TEXT[3] * 0.92, true)
    else
        tip(GameTooltip, entry)
    end
    GameTooltip:Show()
    state.tipRow = row
end

-- Closes the flyouts from level on, unless the mouse has moved into them by
-- the time CLOSE_DELAY has passed (crossing a row on the way to a flyout).
local function ScheduleClose(level)
    local panel = panels[level]
    if not (panel and panel:IsShown()) then return end
    state.closeToken = state.closeToken + 1
    local token = state.closeToken
    local function Run()
        if state.closeToken ~= token or not state.open then return end
        if state.hovered < level then CloseFrom(level) end
    end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(CLOSE_DELAY, Run)
    else
        Run()
    end
end

local function RowEnter(row)
    state.hovered = row.menuLevel
    local entry = row.menuEntry
    if not entry then return end
    local enabled = entry:IsEnabled()
    if enabled then Skin(row, true) end
    if enabled and entry:HasSubmenu() then
        OpenSub(row.menuLevel + 1, entry, row)
    else
        ScheduleClose(row.menuLevel + 1)
    end
    ShowTip(row)
    if enabled and type(entry.onEnter) == "function" then
        row.entered = entry
        entry.onEnter(row, entry)
    end
end

local function RowLeave(row)
    if state.tipRow == row then HideTip() end
    if row.menuEntry then Skin(row, IsOpenParent(row)) end
    local entered = row.entered
    row.entered = nil
    if entered and type(entered.onLeave) == "function" then entered.onLeave(row, entered) end
end

local function RowClick(row, mouse)
    if row.menuEntry then Activate(row.menuEntry, row.menuLevel, mouse) end
end

local function NewRow(panel)
    local row = CreateFrame("Button", nil, panel, "BackdropTemplate")
    row:SetBackdrop(BACKDROP)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.line = GoldLine(row)
    -- The choice box: black edge, gold inside when on.
    row.box = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.box:SetSize(10, 10)
    row.box:SetPoint("LEFT", 6, 0)
    row.box:SetBackdrop(BACKDROP)
    row.label = Label(row)
    -- A submenu's arrow: three grey bars, 7, 5 and 3 tall, pointing right.
    row.arrow = {}
    for index, height in ipairs({ 7, 5, 3 }) do
        local bar = row:CreateTexture(nil, "OVERLAY")
        bar:SetColorTexture(GREY[1], GREY[2], GREY[3], 1)
        bar:SetSize(1, height)
        bar:SetPoint("RIGHT", row, "RIGHT", -11 + index, 0)
        row.arrow[index] = bar
    end
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    row:SetScript("OnClick", RowClick)
    Skin(row, false)
    return row
end

local function NewTitle(panel)
    local row = CreateFrame("Frame", nil, panel)
    row.label = Label(row, "GameFontNormalSmall")
    row.label:SetPoint("LEFT", 6, 0)
    row.label:SetPoint("RIGHT", -6, 0)
    row.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    return row
end

local function NewDivider(panel)
    local row = CreateFrame("Frame", nil, panel)
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetPoint("LEFT", 2, 0)
    line:SetPoint("RIGHT", -2, 0)
    line:SetHeight(1)
    line:SetColorTexture(0, 0, 0, 1)
    return row
end

-- The reset arrow: Blizzard's undo icon (ModelSceneControlFrame.lua's reset
-- button, Blizzard_SharedXML), or its refresh arrows on a build without the
-- atlas; in colour while the value differs from its default, grey once it is
-- the default.
local RESET_ATLAS, RESET_FILE = "common-icon-undo", "Interface\\Buttons\\UI-RefreshButton"
function Menu.ResetArt(texture, changed)
    if not texture.resetArt then
        local atlas = type(C_Texture) == "table" and type(C_Texture.GetAtlasInfo) == "function"
            and C_Texture.GetAtlasInfo(RESET_ATLAS)
        if atlas then texture:SetAtlas(RESET_ATLAS) else texture:SetTexture(RESET_FILE) end
        texture.resetArt = true
    end
    texture:SetDesaturated(not changed)
    if changed then
        texture:SetVertexColor(1, 1, 1, 1)
    else
        texture:SetVertexColor(0.5, 0.5, 0.52, 1)
    end
end

-- A slider's value as its row shows it.
local function SliderText(entry, value)
    if entry.format then return entry.format(value) end
    return tostring(math.floor(value * 100 + 0.5) / 100)
end

-- Whether a value differs from its default by half a step or more.
function Menu.Differs(value, default, step)
    value, default = Number(value), Number(default)
    if not (value and default) then return false end
    local slack = (Number(step) or 0) / 2
    if slack < 1e-6 then slack = 1e-6 end
    return math.abs(value - default) >= slack
end

local function PaintReset(row)
    local entry = row.menuEntry
    if not (entry and entry.default) then return end
    row.resetChanged = Menu.Differs(entry.get and entry.get(), entry.default, entry.step)
    Menu.ResetArt(row.reset.art, row.resetChanged)
end

-- A slider row: the name, a flat track with a gold thumb, the value after it,
-- as the settings pages' sliders, and the reset arrow when it has a default.
-- Disabled (SetEnabled), its name, value and thumb are grey and it takes no
-- drag; its tooltip, if any, says why.
local function NewSlider(panel)
    local row = CreateFrame("Frame", nil, panel)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        state.hovered = self.menuLevel
        ScheduleClose(self.menuLevel + 1)
        if self.menuEntry then ShowTip(self) end
    end)
    row:SetScript("OnLeave", function(self) if state.tipRow == self then HideTip() end end)
    row.label = Label(row)
    row.label:SetPoint("LEFT", 6, 0)
    row.label:SetWidth(60)
    local reset = CreateFrame("Button", nil, row)
    reset:SetSize(14, 14)
    reset:SetPoint("RIGHT", -4, 0)
    reset.art = reset:CreateTexture(nil, "ARTWORK")
    reset.art:SetAllPoints()
    reset:SetScript("OnEnter", function(self)
        state.hovered = row.menuLevel
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", row.menuPanel, "TOPRIGHT", 2, 0)
        GameTooltip:SetText("Reset to default")
        GameTooltip:Show()
        state.tipRow = self
    end)
    reset:SetScript("OnLeave", function(self) if state.tipRow == self then HideTip() end end)
    reset:SetScript("OnClick", function()
        local entry = row.menuEntry
        if not (entry and entry.default and row.resetChanged and entry:IsEnabled()) then return end
        if entry.set then entry.set(entry.default) end
        row.filling = true
        row.control:SetValue(Clamp(entry.default, entry.low, entry.high))
        row.filling = false
        PaintReset(row)
    end)
    row.reset = reset
    row.valueText = Label(row)
    row.valueText:SetWidth(36)
    row.valueText:SetJustifyH("RIGHT")
    local control = CreateFrame("Slider", nil, row)
    control:SetPoint("LEFT", row.label, "RIGHT", 4, 0)
    control:SetPoint("RIGHT", row.valueText, "LEFT", -6, 0)
    control:SetHeight(16)
    control:SetOrientation("HORIZONTAL")
    control:SetObeyStepOnDrag(true)
    control:SetThumbTexture(WHITE)
    local thumb = control:GetThumbTexture()
    if thumb then
        thumb:SetSize(8, 14)
        thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    end
    row.thumb = thumb
    local track = control:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    track:SetColorTexture(0.22, 0.24, 0.27, 1)
    control:SetScript("OnValueChanged", function(_, raw)
        local entry = row.menuEntry
        if not entry then return end
        local value = Number(raw) or entry.low
        if entry.step and entry.step > 0 then value = math.floor(value / entry.step + 0.5) * entry.step end
        value = Clamp(value, entry.low, entry.high)
        row.valueText:SetText(SliderText(entry, value))
        if row.filling or not entry.set then return end
        entry.set(value)
        PaintReset(row)
    end)
    row.control = control
    return row
end

local function Commit(entry, text)
    entry.pending = nil
    if type(entry.set) == "function" then entry.set(text) end
end

local function CommitInputs(entry)
    if not entry then return end
    for _, child in ipairs(entry.children) do
        if child.kind == "input" and child.pending ~= nil then Commit(child, child.pending) end
        CommitInputs(child)
    end
end

local function InputDone(row, close)
    local entry = row.menuEntry
    if not entry then return end
    local serial = state.serial
    Commit(entry, row.box:GetText() or "")
    if state.serial ~= serial or not state.open then return end
    if close then Close() else row.box:ClearFocus(); Refresh() end
end

-- An input row: an optional name, a flat edit box (gold line inside while
-- typing), and an optional button.
local function NewInput(panel)
    local row = CreateFrame("Frame", nil, panel)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self) state.hovered = self.menuLevel; ScheduleClose(self.menuLevel + 1) end)
    row.label = Label(row)
    row.label:SetPoint("LEFT", 6, 0)
    local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    box:SetBackdrop(BACKDROP)
    Paint(box, FIELD)
    box.line = GoldLine(box)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextInsets(5, 5, 0, 0)
    box:SetAutoFocus(false)
    box:SetHeight(20)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function()
        InputDone(row, not (row.menuEntry and row.menuEntry.options.stayOpen))
    end)
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput and row.menuEntry then row.menuEntry.pending = self:GetText() or "" end
    end)
    -- Clicking into a box selects its text, as Blizzard's edit boxes do.
    box:SetScript("OnEditFocusGained", function(self)
        self.line:Show()
        self:HighlightText()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self.line:Hide()
        self:HighlightText(0, 0)
    end)
    box:SetScript("OnHide", function(self) self:ClearFocus() end)
    -- Tab moves to the next input in the same list, Shift+Tab to the one before.
    box:SetScript("OnTabPressed", function()
        local inputs = {}
        for _, other in ipairs(panel.pools.input) do
            if other:IsShown() and other.menuEntry then inputs[#inputs + 1] = other end
        end
        for index, other in ipairs(inputs) do
            if other == row and #inputs > 1 then
                local step = (type(IsShiftKeyDown) == "function" and IsShiftKeyDown()) and -1 or 1
                inputs[(index - 1 + step) % #inputs + 1].box:SetFocus()
                return
            end
        end
    end)
    row.box = box
    local button = CreateFrame("Button", nil, row, "BackdropTemplate")
    button:SetBackdrop(BACKDROP)
    button.line = GoldLine(button)
    button.label = Label(button)
    button.label:SetPoint("CENTER")
    button.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    button:SetSize(44, 20)
    button:SetPoint("RIGHT", -2, 0)
    button:SetScript("OnEnter", function(self) Skin(self, true) end)
    button:SetScript("OnLeave", function(self) Skin(self, false) end)
    button:SetScript("OnClick", function() InputDone(row, true) end)
    Skin(button, false)
    row.button = button
    return row
end

local MAKERS = { row = NewRow, title = NewTitle, divider = NewDivider, slider = NewSlider, input = NewInput }

local function Fill(row, entry)
    row.menuEntry = entry
    local kind = entry.kind
    if kind == "divider" then return end
    if kind == "title" then
        row.label:SetText(entry.text or "")
        return
    end
    if kind == "slider" then
        row.label:SetText(entry.text or "")
        local panel = row.menuPanel
        row.label:SetWidth(panel and panel.sliderLabel or 60)
        row.valueText:SetWidth(panel and panel.sliderValue or 36)
        local resettable = entry.default ~= nil
        row.reset:SetShown(resettable)
        row.valueText:ClearAllPoints()
        if resettable then
            row.valueText:SetPoint("RIGHT", row.reset, "LEFT", -3, 0)
        else
            row.valueText:SetPoint("RIGHT", -6, 0)
        end
        row.filling = true
        row.control:SetMinMaxValues(entry.low, entry.high)
        row.control:SetValueStep(entry.step or 1)
        local current = Number(entry.get and entry.get()) or entry.low
        row.control:SetValue(Clamp(current, entry.low, entry.high))
        row.valueText:SetText(SliderText(entry, current))
        row.filling = false
        PaintReset(row)
        local enabled = entry:IsEnabled()
        row.control:SetEnabled(enabled)
        local color = enabled and TEXT or OFF
        row.label:SetTextColor(color[1], color[2], color[3])
        row.valueText:SetTextColor(color[1], color[2], color[3])
        local thumbColor = enabled and GOLD or OFF
        if row.thumb then row.thumb:SetColorTexture(thumbColor[1], thumbColor[2], thumbColor[3], 1) end
        if not enabled then Menu.ResetArt(row.reset.art, false) end
        return
    end
    if kind == "input" then
        local options = entry.options
        local named = entry.text ~= nil and entry.text ~= ""
        row.label:SetText(named and entry.text or "")
        row.label:SetShown(named)
        local box = row.box
        box:ClearAllPoints()
        if named then
            box:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
        else
            box:SetPoint("LEFT", 2, 0)
        end
        row.button:SetShown(options.button ~= nil)
        if options.button then
            row.button.label:SetText(options.button)
            box:SetPoint("RIGHT", row.button, "LEFT", -2, 0)
        else
            box:SetPoint("RIGHT", -2, 0)
        end
        box:SetNumeric(options.numeric and true or false)
        box:SetMaxLetters(options.maxLetters or 0)
        local text = entry.pending
        if text == nil and entry.get then text = entry.get() end
        box:SetText(type(text) == "string" and text or (text ~= nil and tostring(text) or ""))
        return
    end
    local enabled = entry:IsEnabled()
    local choice = kind == "radio" or kind == "check"
    local on = choice and entry:IsSelected()
    local submenu = entry:HasSubmenu()
    row.box:SetShown(choice)
    if on then
        local dim = enabled and 1 or 0.55
        row.box:SetBackdropColor(GOLD[1] * dim, GOLD[2] * dim, GOLD[3] * dim, 1)
    else
        row.box:SetBackdropColor(EMPTY[1], EMPTY[2], EMPTY[3], 1)
    end
    row.box:SetBackdropBorderColor(0, 0, 0, 1)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", choice and 22 or 8, 0)
    row.label:SetPoint("RIGHT", submenu and -18 or -8, 0)
    row.label:SetText(entry.text or "")
    -- Kit 4: every row's name is the same light grey, actions and submenus
    -- alike; gold marks only headings and a choice that is on.
    local color = TEXT
    if not enabled then
        color = OFF
    elseif on then
        color = GOLD
    end
    row.label:SetTextColor(color[1], color[2], color[3])
    for _, bar in ipairs(row.arrow) do bar:SetShown(submenu) end
    Skin(row, IsOpenParent(row))
end

-- How wide an entry wants to be.
local function Wanted(panel, entry)
    local kind = entry.kind
    if kind == "divider" then return 0 end
    if kind == "slider" then
        return SLIDER_WIDTH + (panel.sliderLabel - 60) + (panel.sliderValue - 36) + (entry.default and 18 or 0)
    end
    if kind == "input" then return entry.options.width or INPUT_WIDTH end
    panel.measure:SetText(entry.text or "")
    local text = Number(panel.measure:GetStringWidth()) or 0
    if kind == "title" then return text + 12 end
    local left = (kind == "radio" or kind == "check") and 22 or 8
    return left + text + (entry:HasSubmenu() and 20 or 10)
end

-- Panels --------------------------------------------------------------------------
local function ScrollTo(panel, first)
    first = Clamp(first, 1, panel.last or 1)
    if first == panel.first then return end
    panel.first = first
    Draw(panel)
end

local function NewPanel(level)
    local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel:Hide()
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetFrameLevel(10 + level * 30)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:SetBackdrop(BACKDROP)
    panel:SetBackdropColor(PANEL[1], PANEL[2], PANEL[3], PANEL[4])
    panel:SetBackdropBorderColor(0, 0, 0, 1)
    panel.menuLevel = level
    panel.first = 1
    panel.pools = { row = {}, title = {}, divider = {}, slider = {}, input = {} }
    panel.drawn = {}
    -- Measures labels; shown but clear, so its width is always computed.
    panel.measure = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.measure:SetPoint("TOPLEFT")
    panel.measure:SetWordWrap(false)
    panel.measure:SetAlpha(0)
    panel:SetScript("OnMouseWheel", function(self, delta)
        ScrollTo(self, self.first + ((Number(delta) or 0) > 0 and -2 or 2))
    end)
    -- The scroll bar of a long list: a thin track with a gold thumb.
    local bar = CreateFrame("Slider", nil, panel)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(5)
    bar:SetPoint("TOPRIGHT", -PAD, -PAD)
    bar:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    bar:SetObeyStepOnDrag(true)
    bar:SetValueStep(1)
    bar:SetThumbTexture(WHITE)
    local thumb = bar:GetThumbTexture()
    if thumb then
        thumb:SetSize(5, 24)
        thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    end
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(ROW_BG[1], ROW_BG[2], ROW_BG[3], 1)
    bar:SetScript("OnValueChanged", function(_, value)
        if panel.filling then return end
        ScrollTo(panel, math.floor((Number(value) or 1) + 0.5))
    end)
    bar:Hide()
    panel.bar = bar
    if level == 1 then
        panel:SetScript("OnKeyDown", function(self, key)
            if InCombatLockdown() then return end
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                Close()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)
    end
    return panel
end

local function Panel(level)
    if not panels[level] then panels[level] = NewPanel(level) end
    return panels[level]
end

-- Draws panel.menuEntry's entries from panel.first, scrolling when they are
-- taller than the entry's scroll height (SetScrollMode) or most of the screen.
function Draw(panel)
    local entries = panel.menuEntry and panel.menuEntry.children or {}
    for _, pool in pairs(panel.pools) do
        for _, row in ipairs(pool) do
            row:Hide()
            row.menuEntry = nil
        end
    end
    panel.drawn = {}
    -- Sliders' names and values: as wide as the widest in this list needs.
    local labelWidth, valueWidth = 60, 36
    for _, entry in ipairs(entries) do
        if entry.kind == "slider" then
            panel.measure:SetText(entry.text or "")
            labelWidth = math.max(labelWidth, (Number(panel.measure:GetStringWidth()) or 0) + 4)
            for _, value in ipairs({ entry.low, entry.high, entry.default or entry.low, Number(entry.get and entry.get()) or entry.low }) do
                panel.measure:SetText(SliderText(entry, value))
                valueWidth = math.max(valueWidth, (Number(panel.measure:GetStringWidth()) or 0) + 4)
            end
        end
    end
    panel.sliderLabel, panel.sliderValue = math.min(labelWidth, 150), math.min(valueWidth, 90)
    local total, width = 0, math.max(MIN_WIDTH, panel.minWidth or 0)
    for _, entry in ipairs(entries) do
        total = total + (HEIGHTS[entry.kind] or HEIGHTS.button)
        width = math.max(width, Wanted(panel, entry) + 2 * PAD)
    end
    width = math.min(width, math.max(MAX_WIDTH, panel.minWidth or 0))
    local scale = Number(panel:GetScale()) or 1
    if scale <= 0 then scale = 1 end
    local screen = Number(UIParent:GetHeight()) or 768
    local limit = (panel.menuEntry and panel.menuEntry.scrollHeight) or math.floor(screen * 0.8 / scale)
    local scrolling = total + 2 * PAD > limit
    panel.last = 1
    if scrolling then
        -- The first entry that still fills the list to its end.
        local height, last = 0, #entries
        for index = #entries, 1, -1 do
            height = height + (HEIGHTS[entries[index].kind] or HEIGHTS.button)
            if height > limit - 2 * PAD then break end
            last = index
        end
        panel.last = last
        width = width + BAR
    end
    panel.first = Clamp(panel.first or 1, 1, panel.last)
    local inner = width - 2 * PAD - (scrolling and BAR or 0)
    local used, y = {}, PAD
    for index = scrolling and panel.first or 1, #entries do
        local entry = entries[index]
        local height = HEIGHTS[entry.kind] or HEIGHTS.button
        if scrolling and y + height > limit - PAD then break end
        local pool = POOLS[entry.kind] or "row"
        used[pool] = (used[pool] or 0) + 1
        local row = panel.pools[pool][used[pool]]
        if not row then
            row = MAKERS[pool](panel)
            row.menuPanel = panel
            panel.pools[pool][used[pool]] = row
        end
        row.menuLevel = panel.menuLevel
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y)
        row:SetSize(inner, height)
        row:SetFrameLevel(panel:GetFrameLevel() + 2)
        Fill(row, entry)
        row:Show()
        panel.drawn[entry] = row
        y = y + height
    end
    panel:SetSize(width, (scrolling and limit or y + PAD))
    panel.bar:SetShown(scrolling)
    if scrolling then
        panel.filling = true
        panel.bar:SetMinMaxValues(1, panel.last)
        panel.bar:SetValue(panel.first)
        panel.filling = false
    end
end

function CloseFrom(level)
    for index = level, #panels do
        local panel = panels[index]
        if panel:IsShown() then panel:Hide() end
        panel.menuEntry, panel.parentRow = nil, nil
    end
    local parent = panels[level - 1]
    if parent and parent:IsShown() then
        for entry, row in pairs(parent.drawn) do
            if entry:HasSubmenu() and not Over(row) then Skin(row, false) end
        end
    end
end

-- Off the right edge of the screen, a flyout opens on the left instead.
local function OffRight(panel)
    local right, scale = Number(panel:GetRight()), Number(panel:GetEffectiveScale())
    local screen, screenScale = Number(UIParent:GetRight()), Number(UIParent:GetEffectiveScale())
    if not (right and scale and screen and screenScale) then return false end
    return right * scale > screen * screenScale + 0.5
end

function OpenSub(level, entry, row)
    state.closeToken = state.closeToken + 1
    local panel = Panel(level)
    if panel:IsShown() and panel.menuEntry == entry then return end
    CloseFrom(level)
    panel.menuEntry, panel.parentRow, panel.first, panel.minWidth = entry, row, 1, 0
    panel:SetScale(panels[1]:GetScale() or 1)
    Draw(panel)
    panel:ClearAllPoints()
    if row then
        panel:SetPoint("TOPLEFT", row, "TOPRIGHT", PAD + 1, PAD + 1)
        if OffRight(panel) then
            panel:ClearAllPoints()
            panel:SetPoint("TOPRIGHT", row, "TOPLEFT", -(PAD + 1), PAD + 1)
        end
        Skin(row, true)
    else
        panel:SetPoint("TOPLEFT", panels[level - 1], "TOPRIGHT", 1, 0)
    end
    panel:Show()
end

-- Runs an entry as a click on its row would.
function Activate(entry, level, mouse)
    if not (state.open and entry) or not entry:IsEnabled() then return end
    local kind = entry.kind
    if kind ~= "button" and kind ~= "radio" and kind ~= "check" then return end
    if entry:HasSubmenu() and not entry.callback then
        local panel = panels[level]
        OpenSub(level + 1, entry, panel and panel.drawn[entry])
        return
    end
    local input = { buttonName = mouse or "LeftButton" }
    local serial = state.serial
    local response, keep
    if kind == "button" then
        if entry.callback then response = entry.callback(entry.data, input, Menu) end
        keep = false
    else
        if entry.setSelected then response = entry.setSelected(entry.data, input, Menu) end
        keep = kind == "check" or (state.options and state.options.keepOpen) or false
    end
    -- The callback may have closed this menu or opened another.
    if state.serial ~= serial or not state.open then return end
    if response ~= nil and (response == Response("Close") or response == Response("CloseAll")) then
        keep = false
    elseif response ~= nil and (response == Response("Refresh") or response == Response("Open")) then
        keep = true
    end
    if keep then Refresh() else Close() end
end

-- Draws the menu anew from its generator, keeping open flyouts that still exist.
function Refresh()
    if not state.open then return end
    CommitInputs(state.root)
    local path = {}
    for level = 2, #panels do
        local panel = panels[level]
        if not (panel:IsShown() and panel.menuEntry and panel.menuEntry.parent) then break end
        path[level - 1] = IndexOf(panel.menuEntry.parent.children, panel.menuEntry)
    end
    state.root = Build(state.owner, state.generator)
    local entry = state.root
    panels[1].menuEntry = entry
    Draw(panels[1])
    for level = 2, #panels do
        local index = path[level - 1]
        local child = index and entry.children[index]
        if not (child and child:HasSubmenu() and panels[level]:IsShown()) then
            CloseFrom(level)
            break
        end
        panels[level].menuEntry = child
        Draw(panels[level])
        entry = child
    end
end

-- Watching for a click elsewhere, the owner hiding, and the end of combat.
local function Keys(on)
    local panel = panels[1]
    if not panel then return end
    if on then
        if InCombatLockdown() then return end
        panel:EnableKeyboard(true)
        panel:SetPropagateKeyboardInput(true)
    else
        panel:EnableKeyboard(false)
    end
end

-- A dropdown stays where it opened: it is placed against its owner, and
-- should the owner move or rescale while it is open (a slider in its own
-- menu resizing its box), it is held at the spot where it opened, under the
-- cursor, instead of following.
local function Edge(frame, method)
    if type(frame) ~= "table" or type(frame[method]) ~= "function" then return nil end
    return Number(frame[method](frame))
end

local function OwnerSpot(owner)
    return Edge(owner, "GetLeft"), Edge(owner, "GetTop"), Edge(owner, "GetEffectiveScale")
end

function Remember(panel, owner)
    state.held = nil
    local left, top = Edge(panel, "GetLeft"), Edge(panel, "GetTop")
    local ownerLeft, ownerTop, ownerScale = OwnerSpot(owner)
    if not (left and top and ownerLeft and ownerTop and ownerScale) then return end
    state.held = { left = left, top = top, ownerLeft = ownerLeft, ownerTop = ownerTop, ownerScale = ownerScale }
end

local function Hold()
    local held, panel = state.held, panels[1]
    if not (held and panel) then return end
    local left, top, scale = OwnerSpot(state.owner)
    if not (left and top and scale) then return end
    if math.abs(left - held.ownerLeft) < 0.5 and math.abs(top - held.ownerTop) < 0.5
        and math.abs(scale - held.ownerScale) < 0.001 then
        return
    end
    state.held = nil
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", held.left, held.top)
end

local function Visible(frame)
    if type(frame) ~= "table" or type(frame.IsVisible) ~= "function" then return true end
    local visible = Flag(frame:IsVisible())
    return visible ~= false
end

local function Watch(on)
    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", function(_, event, button)
            if not state.open then return end
            if event == "PLAYER_REGEN_ENABLED" then
                Keys(true)
                return
            end
            if button ~= "LeftButton" and button ~= "RightButton" then return end
            -- The click that opened the menu, when it opened on a press.
            if state.openedAt and GetTime() == state.openedAt then return end
            for _, panel in ipairs(panels) do
                if panel:IsShown() and Over(panel) then return end
            end
            -- A press on a dropdown's owner leaves its click to close the menu
            -- (Open toggles). A right-click menu closes on any press outside it,
            -- its owner included, as Blizzard's do; its owner's click may then
            -- open it again at the cursor.
            if state.owner and not state.atCursor and Over(state.owner) then return end
            Close()
        end)
    end
    if on then
        watcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
        watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        watcher:SetScript("OnUpdate", function()
            if state.open and state.owner and not Visible(state.owner) then Close() return end
            if state.open then Hold() end
        end)
    else
        watcher:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        watcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
        watcher:SetScript("OnUpdate", nil)
    end
end

function Close()
    if not state.open then return end
    local root, options = state.root, state.options
    state.open = false
    state.serial = state.serial + 1
    state.closeToken = state.closeToken + 1
    HideTip()
    Keys(false)
    Watch(false)
    for _, panel in ipairs(panels) do
        panel:Hide()
        panel.menuEntry, panel.parentRow = nil, nil
    end
    state.owner, state.generator, state.root, state.options, state.held = nil, nil, nil, nil, nil
    -- Text typed in an input and not yet saved is kept, as Enter would.
    CommitInputs(root)
    for _, released in ipairs(root and root.released or {}) do released() end
    if options and options.onClose then options.onClose() end
end

local function Place(panel, owner, options, atCursor)
    panel:ClearAllPoints()
    if atCursor or not owner then
        local x, y = GetCursorPosition()
        local scale = Number(panel:GetEffectiveScale()) or 1
        if scale <= 0 then scale = 1 end
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (Number(x) or 0) / scale, (Number(y) or 0) / scale)
        return
    end
    local point = options.point
    if point then
        panel:SetPoint(point[1], owner, point[2], point[3] or 0, point[4] or 0)
        return
    end
    panel:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    -- Below the screen's bottom edge it opens above its owner instead.
    local bottom = Number(panel:GetBottom())
    if bottom and bottom < 0 then
        panel:ClearAllPoints()
        panel:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
    end
end

local function OpenMenu(owner, generator, options, atCursor)
    options = options or {}
    if not atCursor and state.open and owner ~= nil and state.owner == owner then
        Close()
        return false
    end
    Close()
    local root = Build(owner, generator)
    if #root.children == 0 then return false end
    GameTooltip:Hide()
    state.open, state.owner, state.generator, state.options, state.root = true, owner, generator, options, root
    state.atCursor = atCursor and true or false
    state.serial = state.serial + 1
    state.hovered = 0
    state.openedAt = GetTime()
    local panel = Panel(1)
    local scale = 1
    if type(owner) == "table" and type(owner.GetEffectiveScale) == "function" then
        local own, base = Number(owner:GetEffectiveScale()), Number(UIParent:GetEffectiveScale())
        if own and base and own > 0 and base > 0 then scale = own / base end
    end
    panel:SetScale(scale)
    local minWidth = options.minWidth
    if not minWidth and not atCursor and type(owner) == "table" and type(owner.GetWidth) == "function" then
        minWidth = Number(owner:GetWidth())
    end
    panel.menuEntry, panel.first, panel.minWidth = root, 1, minWidth or 0
    Draw(panel)
    Place(panel, owner, options, atCursor)
    panel:Show()
    if not atCursor then Remember(panel, owner) end
    Keys(true)
    Watch(true)
    return true
end

-- Public ---------------------------------------------------------------------------
function Menu.Open(owner, generator, options) return OpenMenu(owner, generator, options, false) end
function Menu.OpenAtCursor(owner, generator, options) return OpenMenu(owner, generator, options, true) end
Menu.Close = function() Close() end
Menu.Refresh = function() Refresh() end
function Menu.IsOpen(owner) return state.open and (owner == nil or state.owner == owner) end
function Menu.Owner() return state.open and state.owner or nil end

-- The small down arrow on a dropdown's button: three grey bars, 7, 5 and 3
-- wide, as the settings pages draw it.
function Menu.DownArrow(button)
    local bars = {}
    for index, width in ipairs({ 7, 5, 3 }) do
        local bar = button:CreateTexture(nil, "OVERLAY")
        bar:SetColorTexture(GREY[1], GREY[2], GREY[3], 1)
        bar:SetSize(width, 1)
        bar:SetPoint("RIGHT", button, "RIGHT", -8 - (7 - width) / 2, 2 - index)
        bars[index] = bar
    end
    return bars
end

-- For the offline tests: the entries at a level of the open menu (1 is the
-- menu, 2 its open flyout), an entry by its text, clicking or hovering one as
-- the mouse would, a panel, and a generator's entries without opening it.
function Menu.Entries(level)
    local panel = panels[level or 1]
    if not (state.open and panel and panel:IsShown() and panel.menuEntry) then return nil end
    return panel.menuEntry.children
end
function Menu.Find(text, level)
    for _, entry in ipairs(Menu.Entries(level) or {}) do
        if entry.text == text then return entry end
    end
end
function Menu.Click(target, level, mouse)
    local entry = type(target) == "table" and target or Menu.Find(target, level)
    if not entry then return false end
    Activate(entry, level or 1, mouse)
    return true
end
function Menu.Hover(target, level)
    level = level or 1
    local entry = type(target) == "table" and target or Menu.Find(target, level)
    if not (entry and entry:HasSubmenu() and entry:IsEnabled()) then return false end
    local panel = panels[level]
    OpenSub(level + 1, entry, panel and panel.drawn[entry])
    return true
end
function Menu.Row(target, level)
    local panel = panels[level or 1]
    local entry = type(target) == "table" and target or Menu.Find(target, level)
    return panel and entry and panel.drawn[entry] or nil
end
function Menu.Panel(level) return panels[level or 1] end
function Menu.Build(owner, generator) return Build(owner, generator) end
-- Kit 6: the names of the entries in generator's menu, submenus included,
-- that have no tooltip; empty when every one explains itself.
function Menu.Untipped(owner, generator)
    local missing = {}
    local function Walk(entry)
        for _, child in ipairs(entry.children or {}) do
            if child.kind ~= "title" and child.kind ~= "divider"
                and type(child.tooltip) ~= "function" and type(child.tooltip) ~= "string" then
                missing[#missing + 1] = child.text or child.kind
            end
            Walk(child)
        end
    end
    Walk(Build(owner, generator))
    return missing
end
