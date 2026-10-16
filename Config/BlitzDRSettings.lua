-- Config/BlitzDRSettings.lua
-- Battleground (Blitz) DR page. Enable / Test Mode sit in a header that is
-- always visible; everything else is split into sub-tabs so nothing needs a
-- long scroll:
--   Position   – Target Frame | Focus Frame (size, offsets, grow)
--   Style      – Border | Text
--   Behavior   – Cooldown Swipe | About
--   Nameplates – anchor toggle | nameplate offsets

local ADDON, ns = ...
ns.Config = ns.Config or {}

local M = {}
ns.Config.BlitzDRSettings = M

local BORDER_STYLES = { "GLOW", "THIN", "THICK", "NONE" }
local BORDER_STYLE_TEXT = {
	GLOW  = "Glow (sArena)",
	THIN  = "Thin Pixel",
	THICK = "Thick Pixel",
	NONE  = "None",
}

-- Nameplate grow modes. CENTER sits above the plate; LTR / RTL sit beside it,
-- pinned to its edge and growing away from it.
local NP_GROW_ITEMS = { "CENTER", "LTR", "RTL" }
local NP_GROW_TEXT = {
	CENTER = "Centered (above plate)",
	LTR    = "Left to Right (right side)",
	RTL    = "Right to Left (left side)",
}

local function getDB()
	local Core = ns.Core
	if not (Core and Core.arenaDB and Core.arenaDB.profile and Core.arenaDB.profile.arena) then
		return nil
	end
	return Core.arenaDB.profile.arena
end

local function apply()
	local Core = ns.Core
	local mod = Core and Core:GetModule("BlitzDR", true)
	if mod and mod.OnConfigChanged then
		pcall(function() mod:OnConfigChanged() end)
	end
end

-- Shared (non per-frame) values
local function getValue(key, fallback)
	local a = getDB()
	if not a then return fallback end
	local cfg = a.blitz_dr
	if type(cfg) ~= "table" then return fallback end
	local v = cfg[key]
	if v == nil then return fallback end
	return v
end

local function setValue(key, v)
	local a = getDB()
	if not a then return end
	a.blitz_dr = a.blitz_dr or {}
	a.blitz_dr[key] = v
	apply()
end

local function boolSetter(key)
	return function(v) setValue(key, v and true or false) end
end

-- Per-frame (target/focus) values
local function getBridgeValue(bridge, key, fallback)
	local a = getDB()
	if not a then return fallback end
	local cfg = a.blitz_dr or {}
	local b = type(cfg[bridge]) == "table" and cfg[bridge] or {}
	local v = b[key]
	if v ~= nil then return v end
	v = cfg[key]
	if v ~= nil then return v end
	return fallback
end

local function setBridgeValue(bridge, key, v)
	local a = getDB()
	if not a then return end
	a.blitz_dr = a.blitz_dr or {}
	a.blitz_dr[bridge] = a.blitz_dr[bridge] or {}
	a.blitz_dr[bridge][key] = v
	apply()
end

-- One Target/Focus column of size, offset and grow controls.
local function BuildBridgeColumn(panel, bridge, label, x, width)
	local col = ns.Framework:Column(panel, x, width, label)

	local defs = {
		{ label = "Icon Size",       key = "icon_size", min = 12,   max = 80,  fallback = 26 },
		{ label = "Spacing",         key = "spacing",   min = 0,    max = 20,  fallback = 2 },
		{ label = "X Offset",        key = "pos_x",     min = -600, max = 600, fallback = 0 },
		{ label = "Y Offset",        key = "pos_y",     min = -400, max = 400, fallback = 40 },
		{ label = "Timer Font Size", key = "font_size", min = 8,    max = 48,  fallback = 12 },
	}
	for _, def in ipairs(defs) do
		col:Slider({
			LabelText = def.label,
			Min = def.min, Max = def.max, Step = 1,
			GetValue = function() return getBridgeValue(bridge, def.key, def.fallback) end,
			SetValue = function(v) setBridgeValue(bridge, def.key, v) end,
		})
	end

	col:Dropdown("Grow Direction", {
		Items = { "RIGHT", "LEFT", "UP", "DOWN" },
		GetValue = function() return getBridgeValue(bridge, "grow", "RIGHT") end,
		SetValue = function(v) setBridgeValue(bridge, "grow", v) end,
	})
end

function M:Build(page)
	local mini = ns.Framework
	local Core = ns.Core
	local contentWidth = mini.ContentWidth or 600
	local colOffset = math.floor(contentWidth / 4)
	local colWidth = math.floor(contentWidth / 2) - 24

	local function slider(col, label, key, min, max, fallback)
		col:Slider({
			LabelText = label,
			Min = min, Max = max, Step = 1,
			GetValue = function() return getValue(key, fallback) end,
			SetValue = function(v) setValue(key, v) end,
		})
	end

	mini:CreateSectionedPanel({
		Parent = page,

		-- ── Always visible: Enable / Test Mode ─────────────────────────────
		BuildHeader = function(header)
			local enableCB = mini:Checkbox({
				Parent = header,
				LabelText = "Enable",
				Tooltip = "Track diminishing returns on the Target and Focus frames inside battlegrounds, including Blitz.",
				GetValue = function() return getValue("enabled", true) end,
				SetValue = function(v)
					setValue("enabled", v and true or false)
					Core:ApplyModules()
				end,
			})
			enableCB:SetPoint("TOP", header, "TOP", -colOffset - 40, -4)

			local testCB = mini:Checkbox({
				Parent = header,
				LabelText = "Test Mode",
				Tooltip = "Show preview DR icons on the Target and Focus frames (or nameplates). Drag the Target/Focus frame icons to reposition them. Nameplate icons are placed with the Nameplate X/Y Offset sliders: Blizzard does not allow moving anything attached to a nameplate.",
				GetValue = function() return getValue("test_enabled", false) end,
				SetValue = boolSetter("test_enabled"),
			})
			testCB:SetPoint("TOP", header, "TOP", colOffset - 60, -4)
		end,

		Tabs = {
			-- ── Position ─────────────────────────────────────────────────────
			{
				Key = "position",
				Title = "Position",
				Build = function(panel)
					BuildBridgeColumn(panel, "target", "Target Frame", -colOffset, colWidth)
					BuildBridgeColumn(panel, "focus", "Focus Frame", colOffset, colWidth)
				end,
			},

			-- ── Style ────────────────────────────────────────────────────────
			{
				Key = "style",
				Title = "Style",
				Build = function(panel)
					local border = mini:Column(panel, -colOffset, colWidth, "Border")
					border:Dropdown("Border Style", {
						Items = BORDER_STYLES,
						GetText = function(v) return BORDER_STYLE_TEXT[v] or tostring(v) end,
						GetValue = function() return getValue("border_style", "GLOW") end,
						SetValue = function(v) setValue("border_style", v) end,
					})
					slider(border, "Border Size",       "border_size",       0, 8, 1)
					slider(border, "Pixel Border Size", "pixel_border_size", 1, 4, 2)
					border:Checkbox({
						LabelText = "Black Border",
						Tooltip = "Color the border black instead of the DR stage color (green = 1/2, red = 2/2).",
						GetValue = function() return getValue("border_black", false) end,
						SetValue = boolSetter("border_black"),
					})

					local text = mini:Column(panel, colOffset, colWidth, "Text")
					text:Checkbox({
						LabelText = "Show DR Text (1/2, 2/2)",
						Tooltip = "Show the DR stage in the icon corner: 1/2 = first application (next is halved), 2/2 = second (next is immune).",
						GetValue = function() return getValue("show_dr_text", true) end,
						SetValue = boolSetter("show_dr_text"),
					})
					text:Checkbox({
						LabelText = "Color Countdown Text",
						Tooltip = "Color the remaining-time text with the DR stage color.",
						GetValue = function() return getValue("color_cd_text", true) end,
						SetValue = boolSetter("color_cd_text"),
					})
					text:Checkbox({
						LabelText = "Show Decimals",
						Tooltip = "Show one decimal place on the countdown when it drops below the threshold.",
						GetValue = function() return getValue("show_decimals", true) end,
						SetValue = boolSetter("show_decimals"),
					})
					slider(text, "Decimal Threshold (seconds)", "decimal_threshold", 1, 10, 3)
				end,
			},

			-- ── Behavior ─────────────────────────────────────────────────────
			{
				Key = "behavior",
				Title = "Behavior",
				Build = function(panel)
					local swipe = mini:Column(panel, -colOffset, colWidth, "Cooldown Swipe")
					swipe:Checkbox({
						LabelText = "Reverse Cooldown Swipe",
						Tooltip = "Invert the direction of the cooldown swipe animation.",
						GetValue = function() return getValue("reverse_swipe", true) end,
						SetValue = boolSetter("reverse_swipe"),
					})
					swipe:Checkbox({
						LabelText = "Disable Cooldown Swipe",
						Tooltip = "Hide the dark swipe animation on the DR icons.",
						GetValue = function() return getValue("disable_swipe", false) end,
						SetValue = boolSetter("disable_swipe"),
					})

					local about = mini:Column(panel, colOffset, colWidth, "About")
					about:Text("Battlegrounds seal the aura APIs, so this tracks the crowd control YOU cast. "
						.. "A teammate's earlier CC is not visible and can diminish yours unseen. "
						.. "The DR reset time is shared with the Arena DR tab.")
				end,
			},

			-- ── Nameplates ───────────────────────────────────────────────────
			-- Nameplate mode keeps its OWN offsets, so the toggle can flip back
			-- and forth without losing the Target/Focus frame placement.
			{
				Key = "nameplates",
				Title = "Nameplates",
				Build = function(panel)
					local anchor = mini:Column(panel, -colOffset, colWidth, "Anchor")
					anchor:Checkbox({
						LabelText = "Anchor to Nameplates",
						Tooltip = "Show the DR icons above the enemy's nameplate instead of on the Target and Focus frames. Enemy nameplates must be enabled. In Test Mode, target (and focus) an enemy to see the preview on their plate.",
						GetValue = function() return getValue("anchor_nameplate", false) end,
						SetValue = boolSetter("anchor_nameplate"),
					})
					anchor:Checkbox({
						LabelText = "Show on Both",
						Tooltip = "Show the DR icons on the Target/Focus frames AND on the nameplate at the same time. Both copies share the same timers, so they always match.",
						GetValue = function() return getValue("np_both", false) end,
						SetValue = boolSetter("np_both"),
					})
					anchor:Dropdown("Nameplate Grow", {
						Items = NP_GROW_ITEMS,
						GetText = function(v) return NP_GROW_TEXT[v] or tostring(v) end,
						GetValue = function() return getValue("np_grow", "CENTER") end,
						SetValue = function(v) setValue("np_grow", v) end,
					})
					anchor:Text("Centered sits above the plate. Left to Right and Right to Left sit beside "
						.. "the plate and grow away from it, so the first icon always stays next to it. "
						.. "These offsets are separate from the Target/Focus offsets.")

					local offsets = mini:Column(panel, colOffset, colWidth, "Nameplate Offsets")
					slider(offsets, "Nameplate X Offset", "np_pos_x", -300, 300, 0)
					slider(offsets, "Nameplate Y Offset", "np_pos_y", -200, 200, 10)
				end,
			},
		},
	})
end
