-- Adapted from Forever DR PreviewKit.lua (MIT, Copyright 2026 Tarolg).
-- Drpulse integration and visual adaptations: Copyright 2026 Joaqoz.
-- The workspace's preview kit: the live preview boxes on the settings pages
-- (AGENTS.md "Previews in settings"; the user's choices of 11 October 2026).
-- The master is tools/preview-kit/PreviewKit.lua. Each addon whose settings
-- page shows a preview keeps an identical copy at its root, listed in its TOC
-- before Settings.lua. Change only the master, test it with
--   lua5.1 tools/preview-kit/tests/run.lua
-- and copy it out with tools/preview-kit/Sync-PreviewKit.ps1. A file new to a
-- TOC loads only after the game restarts, so a page must work without it
-- (ns.PreviewKit nil: no preview, nothing else changes).
--
-- A preview box is a grey line saying what the samples are (with a Show on
-- screen button at its end when the samples can be played on the real
-- screen), over a strip the samples stand on: a dim strip of world (a dusk
-- sky over grass and earth, drawn here, no art of its own), or a plain fill
-- for things that are opaque in game. The samples are the addon's own frames,
-- drawn by its own code from fixed plain values; the kit only holds them.
--
-- Calls:
--   ns.PreviewKit.New(frame, options) -> preview. frame is the box's frame
--     (a settings block or a pinned header). options:
--       x, width     the strip's left edge and width in frame (14, 508)
--       onScreen     function: the Show on screen button calls it
--       screenTip    that button's tooltip text
--       plain        a colour { r, g, b } for an opaque strip instead of world
--       resize       function(height): the box needs this height
--   preview.holder   samples hang from it; preview.top is where they start
--                    below its top, preview.left where they start across it
--   preview.text     a layer above the samples; preview.Caption(width) makes
--                    a grey caption on it: one line without width, wrapped
--                    to width (and as many lines as it needs) with it
--   preview.SetLabel(text)   the grey line (it wraps; the strip moves down
--                            by preview.labelDrop, also kept as
--                            preview.extra, which is the kit's name: give
--                            an addon's own fields other names)
--   preview.Fit(bottom)      the lowest sample edge below the holder's top;
--                            calls options.resize with the box's height
--   preview.Lift()   keeps the captions, outlines, tag and Show on screen
--                    above every sample, however high the addon set a
--                    sample's frame level (Settle, Fit and Point call it)
--   preview.loops[i] = { play(now, first), step(now), done(), still(), stop() }
--                    motion: a sample plays (first: the first run after a
--                    change, which may start part-way), steps each frame
--                    until done, waits a moment and plays again. Loops run
--                    only while the box is on screen and nothing is pointed.
--   preview.parts[part] = function() return regions, whole end
--                    what a settings row's part names; whole is outlined
--                    instead (tagged "not shown") when no region shows
--   preview.Settle() after any change: samples start again (or are drawn
--                    still while a row is pointed) and a pointed part is
--                    outlined where it is now
--   preview.Point(part, name)  a row is hovered (nil: left): samples hold
--                    still, a gold box round each shown region of the part,
--                    the row's name in a gold tag
--   ns.PreviewKit.MatchStrata(sample, holder)  a sample takes its holder's
--                    strata (settings windows are HIGH; addon frames often
--                    set MEDIUM, which would draw behind the page)
--   ns.PreviewKit.Scale(width, scale, notes, room, height, roomHeight)  the
--                    scale to draw a sample at, shrunk to fit room across
--                    (496) and, given height and roomHeight, roomHeight
--                    down; notes gets what to say
--   ns.PreviewKit.Flow(sizes, room, gap, lineGap) -> places, height, width
--                    samples side by side, a new line when the next would
--                    pass room (496): sizes[i] = { width, height } as drawn,
--                    places[i] = { x = , y = } from the first's top left,
--                    height and width of the whole (gap 12, lineGap 6)
--   ns.PreviewKit.Copy(settings)  a shallow copy of a settings table
--   ns.PreviewKit.GREY, .AMBER  colour codes for the grey line

local _, ns = ...

local Kit = {}
ns.PreviewKit = Kit
Kit.VERSION = 2

local WHITE = "Interface\\Buttons\\WHITE8X8"
local GOLD = { 0.38, 0.85, 1.00 }
local GREY = { 0.55, 0.55, 0.58 }
local BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }
local EDGE = { edgeFile = WHITE, edgeSize = 1 }
Kit.GREY, Kit.AMBER = "|cff8c8c94", "|cffff9f1a"

local LABEL_TOP, SAMPLE_TOP, SAMPLE_LEFT = 4, 24, 6
local SCREEN_W, SCREEN_H = 104, 16
local LOOP_GAP = 0.6
-- The world strip: a dusk sky over grass and earth.
local SKY, HORIZON, GROUND = { 0.2, 0.25, 0.3 }, { 0.25, 0.28, 0.22 }, { 0.16, 0.15, 0.12 }

local function Gradient(texture, top, bottom)
    texture:SetColorTexture(1, 1, 1, 1)
    texture:SetGradient("VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1))
end

-- The workspace's flat button: a black edge, and on hover a gold line
-- inside it.
local function FlatButton(parent, text, width, height, tip)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, height)
    button:SetBackdrop(BACKDROP)
    button:SetBackdropColor(0.14, 0.145, 0.16, 1)
    button:SetBackdropBorderColor(0, 0, 0, 1)
    local gold = CreateFrame("Frame", nil, button, "BackdropTemplate")
    gold:SetPoint("TOPLEFT", 1, -1)
    gold:SetPoint("BOTTOMRIGHT", -1, 1)
    gold:SetBackdrop(EDGE)
    gold:SetBackdropBorderColor(0.24, 0.65, 0.82, 1)
    gold:Hide()
    button.gold = gold
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", 0, 0)
    label:SetText(text)
    label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    button.label = label
    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.10, 0.20, 0.27, 1)
        gold:Show()
        if tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text)
            GameTooltip:AddLine(tip, 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.14, 0.145, 0.16, 1)
        gold:Hide()
        if tip then GameTooltip:Hide() end
    end)
    return button
end

-- The kit's layers sit at least this many levels above the holder: the
-- captions, then the outlines and their tag. Lift raises them further when
-- a sample stands higher. The walk over the samples is bounded.
local TEXT_ABOVE, OUTLINE_ABOVE, LIFT_LIMIT = 20, 30, 2000

-- A frame's level as a plain number, or nil (GetFrameLevel can return a
-- secret: SecretReturnsForAspect FrameLevel).
local function Level(frame)
    if type(frame) ~= "table" or type(frame.GetFrameLevel) ~= "function" then return nil end
    local level = frame:GetFrameLevel()
    if issecretvalue and issecretvalue(level) then return nil end
    if type(level) ~= "number" then return nil end
    return level
end

-- The highest level among frame's descendants, leaving out the kit's own
-- layers (own) and stopping after LIFT_LIMIT frames.
local function Highest(frame, own, top, count)
    if type(frame.GetChildren) ~= "function" then return top, count end
    for _, child in ipairs({ frame:GetChildren() }) do
        if count >= LIFT_LIMIT then break end
        if type(child) == "table" and not own[child] then
            count = count + 1
            local level = Level(child)
            if level and level > top then top = level end
            top, count = Highest(child, own, top, count)
        end
    end
    return top, count
end

local function SetLevel(frame, level)
    if Level(frame) ~= level then frame:SetFrameLevel(level) end
end

-- A thin gold box round a region, drawn above the samples.
local function Outline(holder, level)
    local box = CreateFrame("Frame", nil, holder)
    box:SetFrameLevel(level or (holder:GetFrameLevel() + OUTLINE_ABOVE))
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local line = box:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        line:SetPoint(side[1])
        line:SetPoint(side[2])
        if side[3] then line:SetHeight(1) else line:SetWidth(1) end
    end
    box:Hide()
    return box
end

function Kit.New(frame, options)
    options = options or {}
    local x, width = options.x or 14, options.width or 508
    local preview = { frame = frame, parts = {}, loops = {}, outlines = {}, top = SAMPLE_TOP, left = x + SAMPLE_LEFT, width = width,
        labelDrop = 0, extra = 0 }

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x + 2, -LABEL_TOP)
    label:SetWidth(options.onScreen and (width - SCREEN_W - 8) or width)
    label:SetJustifyH("LEFT")
    label:SetTextColor(GREY[1], GREY[2], GREY[3])
    preview.label = label
    if options.onScreen then
        local button = FlatButton(frame, "Show on screen", SCREEN_W, SCREEN_H, options.screenTip)
        button:SetPoint("TOPLEFT", x + width - SCREEN_W, -1)
        button:SetScript("OnClick", function() options.onScreen() end)
        preview.screen = button
    end

    local holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints(frame)
    holder.settingsPreview = true
    preview.holder = holder
    local stage = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    stage:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -(SAMPLE_TOP - 6))
    stage:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", x + width, 4)
    stage:SetFrameLevel(holder:GetFrameLevel())
    stage:SetBackdrop(EDGE)
    stage:SetBackdropBorderColor(0, 0, 0, 1)
    preview.stage = stage
    if options.plain then
        local fill = stage:CreateTexture(nil, "BACKGROUND")
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", -1, 1)
        fill:SetColorTexture(options.plain[1], options.plain[2], options.plain[3], 1)
        preview.fill = fill
    else
        local sky = stage:CreateTexture(nil, "BACKGROUND")
        sky:SetPoint("TOPLEFT", 1, -1)
        sky:SetPoint("BOTTOMRIGHT", stage, "RIGHT", -1, 0)
        Gradient(sky, SKY, HORIZON)
        local ground = stage:CreateTexture(nil, "BACKGROUND")
        ground:SetPoint("TOPLEFT", stage, "LEFT", 1, 0)
        ground:SetPoint("BOTTOMRIGHT", -1, 1)
        Gradient(ground, HORIZON, GROUND)
        preview.sky, preview.ground = sky, ground
    end
    local text = CreateFrame("Frame", nil, holder)
    text:SetAllPoints(holder)
    text:SetFrameLevel(holder:GetFrameLevel() + TEXT_ABOVE)
    preview.text = text
    -- The kit's own frames, which Lift leaves out of the samples.
    local own = { [stage] = true, [text] = true }

    -- A caption is one line unless it is given a width: a font string
    -- wraps only at a width of its own, so a wrapped caption needs one.
    function preview.Caption(width)
        local caption = text:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        caption:SetJustifyH("LEFT")
        if type(width) == "number" and width > 0 then
            caption:SetWidth(width)
            caption:SetWordWrap(true)
        else
            caption:SetWordWrap(false)
        end
        return caption
    end

    -- The grey line wraps when it is long, so the samples hang below
    -- however many lines it takes: the holder, strip and all, moves down by
    -- what the line needs beyond one. The text is the addon's own.
    local extra = 0
    function preview.SetLabel(value)
        label:SetText(value or "")
        local height = label:GetStringHeight()
        extra = 0
        if type(height) == "number" then extra = math.max(0, math.ceil(LABEL_TOP + height + 2 - (SAMPLE_TOP - 6))) end
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -extra)
        holder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        -- labelDrop is the name to read; extra stays for pages that read it.
        preview.labelDrop, preview.extra = extra, extra
        return extra
    end
    function preview.Fit(bottom)
        preview.Lift()
        local height = math.ceil(extra + bottom + 6)
        preview.height = height
        if options.resize then options.resize(height) end
        return height
    end

    -- Motion. The runner is set only while samples move and the box is on
    -- screen: holding still or hiding the box takes it away.
    local function Run()
        local now = GetTime()
        for _, loop in ipairs(preview.loops) do
            if loop.active then
                if loop.step then loop.step(now) end
                if loop.done() then loop.active, loop.next = false, now + LOOP_GAP end
            elseif loop.next and now >= loop.next then
                loop.active, loop.next = true, nil
                loop.play(now, false)
            end
        end
    end
    function preview.Restart()
        local now = GetTime()
        holder:SetScript("OnUpdate", (not preview.holding and #preview.loops > 0) and Run or nil)
        for _, loop in ipairs(preview.loops) do
            loop.stop()
            loop.active, loop.next = false, nil
            if preview.holding then
                loop.still()
            else
                loop.active = true
                loop.play(now, true)
            end
        end
    end
    function preview.Hold(on)
        on = on == true
        if preview.holding == on then return end
        preview.holding = on
        preview.Restart()
    end
    holder:SetScript("OnHide", function()
        holder:SetScript("OnUpdate", nil)
        for _, loop in ipairs(preview.loops) do
            loop.stop()
            loop.active, loop.next = false, nil
        end
    end)

    -- Hover a row, see its part.
    local tag = CreateFrame("Frame", nil, holder)
    tag:SetFrameLevel(holder:GetFrameLevel() + OUTLINE_ABOVE + 1)
    own[tag] = true
    tag:SetHeight(14)
    local tagFill = tag:CreateTexture(nil, "BACKGROUND")
    tagFill:SetAllPoints()
    tagFill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    local tagText = tag:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tagText:SetPoint("CENTER", 0, 0)
    tagText:SetTextColor(0, 0, 0, 1)
    tag:Hide()
    preview.tag, preview.tagText = tag, tagText

    -- Samples are the addon's own frames, at whatever level its drawing
    -- code gives them; one at or above the caption layer would draw over
    -- the captions, outlines and tag. The layers keep their usual places
    -- (20, 30 and 31 above the holder) and rise only past a higher sample,
    -- and Show on screen with them, in case a sample reaches up to it.
    local outlineLevel = holder:GetFrameLevel() + OUTLINE_ABOVE
    function preview.Lift()
        local base = Level(holder)
        if not base then return end
        local top = Highest(holder, own, base, 0)
        local textLevel = math.max(base + TEXT_ABOVE, top + 1)
        outlineLevel = math.max(base + OUTLINE_ABOVE, textLevel + 1)
        SetLevel(text, textLevel)
        for _, box in ipairs(preview.outlines) do SetLevel(box, outlineLevel) end
        SetLevel(tag, outlineLevel + 1)
        local screen = preview.screen
        if screen then
            local frameLevel = Level(frame)
            local wanted = math.max(frameLevel and frameLevel + 1 or 0, top + 1)
            SetLevel(screen, wanted)
            SetLevel(screen.gold, wanted + 1)
        end
        return textLevel
    end

    function preview.Point(part, name)
        for _, box in ipairs(preview.outlines) do box:Hide() end
        tag:Hide()
        local find = part and preview.parts[part]
        preview.pointed, preview.pointedName = find and part or nil, find and name or nil
        preview.Hold(find ~= nil)
        if not find then return end
        local regions, whole = find()
        local shown = {}
        for _, region in ipairs(regions or {}) do
            if region and region:IsShown() ~= false then shown[#shown + 1] = region end
        end
        local off = #shown == 0
        if off then shown[1] = whole end
        if not shown[1] then return end
        preview.Lift()
        for index, region in ipairs(shown) do
            local box = preview.outlines[index]
            if not box then
                box = Outline(holder, outlineLevel)
                own[box] = true
                preview.outlines[index] = box
            end
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", region, "TOPLEFT", -2, 2)
            box:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 2, -2)
            box:Show()
        end
        tagText:SetText(off and ((name or "") .. ": not shown") or (name or ""))
        tag:SetWidth((tagText:GetStringWidth() or 60) + 8)
        tag:ClearAllPoints()
        local right, edge = preview.outlines[1]:GetRight(), stage:GetRight()
        if type(right) == "number" and type(edge) == "number" and right + 4 + tag:GetWidth() > edge then
            tag:SetPoint("BOTTOMRIGHT", preview.outlines[1], "TOPRIGHT", 0, 1)
        else
            tag:SetPoint("LEFT", preview.outlines[1], "RIGHT", 4, 0)
        end
        tag:Show()
    end
    function preview.Settle()
        preview.Restart()
        preview.Lift()
        if preview.pointed then preview.Point(preview.pointed, preview.pointedName) end
    end
    return preview
end

-- GetFrameStrata can return a secret (1.60.1.70291); the strata is then left.
function Kit.MatchStrata(sample, holder)
    local strata = holder:GetFrameStrata()
    if issecretvalue and issecretvalue(strata) then return end
    if type(strata) ~= "string" then return end
    sample:SetFrameStrata(strata)
end

-- Across, the sample must fit room; down, given height and roomHeight, it
-- must fit roomHeight too, and the smaller of the two scales wins.
function Kit.Scale(width, scale, notes, room, height, roomHeight)
    room = room or 496
    scale = scale or 1
    local fit
    if width * scale > room then fit = room / width end
    if type(height) == "number" and type(roomHeight) == "number" and height > 0 and height * scale > roomHeight then
        local down = roomHeight / height
        if not fit or down < fit then fit = down end
    end
    if fit then
        if notes then notes[#notes + 1] = "shrunk to fit" end
        return fit
    elseif scale ~= 1 and notes then
        notes[#notes + 1] = math.floor(scale * 100 + 0.5) .. "%"
    end
    return scale
end

-- Samples side by side, left to right, each line as tall as its tallest;
-- one that would pass room starts a new line (a sample wider than room
-- still gets a line of its own).
function Kit.Flow(sizes, room, gap, lineGap)
    room, gap, lineGap = room or 496, gap or 12, lineGap or 6
    local places, x, y, line, widest = {}, 0, 0, 0, 0
    for index, size in ipairs(sizes or {}) do
        local w, h = size[1] or size.width or 0, size[2] or size.height or 0
        if x > 0 and x + w > room then x, y, line = 0, y + line + lineGap, 0 end
        places[index] = { x = x, y = y }
        widest = math.max(widest, x + w)
        x = x + w + gap
        line = math.max(line, h)
    end
    return places, y + line, widest
end

function Kit.Copy(settings)
    local copy = {}
    for key, value in pairs(settings or {}) do copy[key] = value end
    return copy
end
