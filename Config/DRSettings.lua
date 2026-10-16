-- Config/DRSettings.lua
-- Arena DR page. Enable / Test Mode sit in a header that is always visible;
-- everything else is split into sub-tabs so nothing needs a long scroll:
--   Position   – Target Frame | Focus Frame (size, offsets, grow)
--   Style      – Border | Text
--   Behavior   – Cooldown Swipe | Tracking
--   Nameplates – anchor toggle | nameplate offsets

local ADDON, ns = ...
ns.Config = ns.Config or {}

local M = {}
ns.Config.DRSettings = M

local function getDB()
	local Core = ns.Core
	if not (Core and Core.arenaDB and Core.arenaDB.profile and Core.arenaDB.profile.arena) then
		return nil
	end
	return Core.arenaDB.profile.arena
end

local function apply()
	local Core = ns.Core
	local Arena = Core and Core:GetModule("TargetandFocus", true)
	if Arena and Arena.OnConfigChanged then
		pcall(function() Arena:OnConfigChanged() end)
	end
end

local function getBridgeValue(bridge, key, fallback)
	local a = getDB()
	if not a then return fallback end
	local dr = a.dr or {}
	local b = type(dr[bridge]) == "table" and dr[bridge] or {}
	local v = b[key]
	if v ~= nil then return v end
	v = dr[key]
	if v ~= nil then return v end
	return fallback
end

local function setBridgeValue(bridge, key, value)
	local a = getDB()
	if not a then return end
	a.dr = a.dr or {}
	a.dr[bridge] = a.dr[bridge] or {}
	a.dr[bridge][key] = value
	apply()
end

-- Options shared by both frames (stored at the dr level)
local function getDRValue(key, fallback)
	local a = getDB()
	if not a then return fallback end
	local dr = a.dr or {}
	local v = dr[key]
	if v == nil then return fallback end
	return v
end

local function setDRValue(key, value)
	local a = getDB()
	if not a then return end
	a.dr = a.dr or {}
	a.dr[key] = value
	apply()
end

local function boolSetter(key)
	return function(v) setDRValue(key, v and true or false) end
end

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

-- One Target/Focus column of size, offset and grow controls.
local function BuildBridgeColumn(panel, bridge, label, x, width)
	local col = ns.Framework:Column(panel, x, width, label)

	local defs = {
		{ label = "Icon Size",       key = "icon_size", min = 12,    max = 80,   fallback = 26 },
		{ label = "Spacing",         key = "spacing",   min = 0,     max = 20,   fallback = 2 },
		{ label = "X Offset",        key = "pos_x",     min = -1280, max = 1280, fallback = 0 },
		{ label = "Y Offset",        key = "pos_y",     min = -960,  max = 960,  fallback = 30 },
		{ label = "Timer Font Size", key = "font_size", min = 8,     max = 48,   fallback = 14 },
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

	mini:CreateSectionedPanel({
		Parent = page,

		-- ── Always visible: Enable / Test Mode ─────────────────────────────
		BuildHeader = function(header)
			local enableCB = mini:Checkbox({
				Parent = header,
				LabelText = "Enable",
				Tooltip = "Enable or disable the arena DR tracking module.",
				GetValue = function()
					local a = getDB()
					return a and a.enabled ~= false
				end,
				SetValue = function(v)
					local a = getDB()
					if not a then return end
					a.enabled = not not v
					Core:ApplyModules()
				end,
			})
			enableCB:SetPoint("TOP", header, "TOP", -colOffset - 40, -4)

			local testCB = mini:Checkbox({
				Parent = header,
				LabelText = "Test Mode",
				Tooltip = "Show preview DR icons on the Target and Focus frames (or nameplates). Drag the Target/Focus frame icons to reposition them. Nameplate icons are placed with the Nameplate X/Y Offset sliders: Blizzard does not allow moving anything attached to a nameplate.",
				GetValue = function()
					local a = getDB()
					return a and a.test and a.test.enabled or false
				end,
				SetValue = function(v)
					local a = getDB()
					if not a then return end
					a.test = a.test or {}
					a.test.enabled = v and true or false
					apply()
				end,
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
						GetValue = function() return getDRValue("border_style", "GLOW") end,
						SetValue = function(v) setDRValue("border_style", v) end,
					})
					border:Slider({
						LabelText = "Border Size",
						Min = 0, Max = 8, Step = 1,
						GetValue = function() return getDRValue("border_size", 1) end,
						SetValue = function(v) setDRValue("border_size", v) end,
					})
					border:Slider({
						LabelText = "Pixel Border Size",
						Min = 1, Max = 4, Step = 1,
						GetValue = function() return getDRValue("pixel_border_size", 2) end,
						SetValue = function(v) setDRValue("pixel_border_size", v) end,
					})
					border:Checkbox({
						LabelText = "Black Border",
						Tooltip = "Color the border black instead of the DR state color (green = DR active, red = immune).",
						GetValue = function() return getDRValue("border_black", false) end,
						SetValue = boolSetter("border_black"),
					})

					local text = mini:Column(panel, colOffset, colWidth, "Text")
					text:Checkbox({
						LabelText = "Show DR Text (1/2, 2/2)",
						Tooltip = "Show the DR stage in the icon corner: 1/2 = first application (next is halved), 2/2 = second (next is immune).",
						GetValue = function() return getDRValue("show_dr_text", true) end,
						SetValue = boolSetter("show_dr_text"),
					})
					text:Checkbox({
						LabelText = "Color Countdown Text",
						Tooltip = "Color the DR countdown text green instead of white.",
						GetValue = function() return getDRValue("color_cd_text", false) end,
						SetValue = boolSetter("color_cd_text"),
					})
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
						GetValue = function() return getDRValue("reverse_swipe", true) end,
						SetValue = boolSetter("reverse_swipe"),
					})
					swipe:Checkbox({
						LabelText = "Disable Cooldown Swipe",
						Tooltip = "Hide the dark swipe animation on the DR icons.",
						GetValue = function() return getDRValue("disable_swipe", false) end,
						SetValue = boolSetter("disable_swipe"),
					})

					local tracking = mini:Column(panel, colOffset, colWidth, "Tracking")
					-- Blizzard CVar: restrict the DR tray to CC the player cast
					tracking:Checkbox({
						LabelText = "Only Track My Own CC",
						Tooltip = "Only show DRs triggered by your own crowd control (Blizzard setting; applies account-wide).",
						GetValue = function()
							local ok, v = pcall(C_CVar.GetCVarBool, "spellDiminishPVPOnlyTriggerableByMe")
							return ok and v or false
						end,
						SetValue = function(v)
							pcall(C_CVar.SetCVar, "spellDiminishPVPOnlyTriggerableByMe", v and "1" or "0")
						end,
					})
					tracking:Slider({
						LabelText = "DR Reset Time (shared with World & Blitz)",
						Min = 15, Max = 20, Step = 0.1,
						GetValue = function()
							local a = getDB()
							return (a and a.dr_reset_time) or 20
						end,
						SetValue = function(v)
							local a = getDB()
							if not a then return end
							a.dr_reset_time = v
							apply()
						end,
					})
				end,
			},

			-- ── Nameplates ───────────────────────────────────────────────────
			-- Nameplate mode keeps its OWN offsets: a position tuned for a unit
			-- frame makes no sense on a plate, and separate values let the
			-- toggle flip back and forth without losing either placement.
			{
				Key = "nameplates",
				Title = "Nameplates",
				Build = function(panel)
					local anchor = mini:Column(panel, -colOffset, colWidth, "Anchor")
					anchor:Checkbox({
						LabelText = "Anchor to Nameplates",
						Tooltip = "Show the DR icons above the enemy's nameplate instead of on the Target and Focus frames. Enemy nameplates must be enabled. In Test Mode, target (and focus) an enemy to see the preview on their plate.",
						GetValue = function() return getDRValue("anchor_nameplate", false) end,
						SetValue = boolSetter("anchor_nameplate"),
					})
					anchor:Checkbox({
						LabelText = "Show on Both",
						Tooltip = "Show the DR icons on the Target/Focus frames AND on the nameplate at the same time. Both copies share the same timers, so they always match.",
						GetValue = function() return getDRValue("np_both", false) end,
						SetValue = boolSetter("np_both"),
					})
					anchor:Dropdown("Nameplate Grow", {
						Items = NP_GROW_ITEMS,
						GetText = function(v) return NP_GROW_TEXT[v] or tostring(v) end,
						GetValue = function() return getDRValue("np_grow", "CENTER") end,
						SetValue = function(v) setDRValue("np_grow", v) end,
					})
					anchor:Text("Centered sits above the plate. Left to Right and Right to Left sit beside "
						.. "the plate and grow away from it, so the first icon always stays next to it. "
						.. "These offsets are separate from the Target/Focus offsets.")

					local offsets = mini:Column(panel, colOffset, colWidth, "Nameplate Offsets")
					offsets:Slider({
						LabelText = "Nameplate X Offset",
						Min = -300, Max = 300, Step = 1,
						GetValue = function() return getDRValue("np_pos_x", 0) end,
						SetValue = function(v) setDRValue("np_pos_x", v) end,
					})
					offsets:Slider({
						LabelText = "Nameplate Y Offset",
						Min = -200, Max = 200, Step = 1,
						GetValue = function() return getDRValue("np_pos_y", 10) end,
						SetValue = function(v) setDRValue("np_pos_y", v) end,
					})
				end,
			},
		},
	})
end
