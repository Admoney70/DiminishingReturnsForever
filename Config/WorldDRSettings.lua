-- Config/WorldDRSettings.lua
-- World DR page. Enable / Test Mode sit in a header that is always visible;
-- everything else is split into sub-tabs so nothing needs a long scroll:
--   Position   – Size | Position
--   Style      – Border | Text
--   Behavior   – Cooldown Swipe | Tracked Categories
--   Nameplates – anchor toggle | nameplate offsets

local ADDON, ns = ...
ns.Config = ns.Config or {}

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

function ns.Config:BuildWorldDRTab(page)
	if not page then return end

	local mini = ns.Framework
	local Core = ns.Core
	if not (mini and Core) then return end

	local contentWidth = mini.ContentWidth or 600
	local colOffset = math.floor(contentWidth / 4)
	local colWidth = math.floor(contentWidth / 2) - 24

	-- Helpers
	local function getWP(key, fallback)
		local a = Core.arenaDB and Core.arenaDB.profile and Core.arenaDB.profile.arena
		if not a then return fallback end
		local wp = a.world_dr
		if type(wp) ~= "table" then return fallback end
		local v = wp[key]
		if v == nil then return fallback end
		return v
	end

	local function apply()
		local WPvP = Core:GetModule("WorldDR", true)
		if WPvP and WPvP.OnConfigChanged then
			pcall(function() WPvP:OnConfigChanged() end)
		end
	end

	local function setWP(key, v)
		if not (Core.arenaDB and Core.arenaDB.profile) then return end
		local a = Core.arenaDB.profile.arena or {}
		Core.arenaDB.profile.arena = a
		a.world_dr = a.world_dr or {}
		a.world_dr[key] = v
		apply()
	end

	local function boolSetter(key)
		return function(v) setWP(key, v and true or false) end
	end

	local function getCat(cat)
		local cats = getWP("categories", nil)
		if type(cats) ~= "table" then return true end
		return cats[cat] ~= false
	end

	local function setCat(cat, v)
		local a = Core.arenaDB and Core.arenaDB.profile and Core.arenaDB.profile.arena
		if not a then return end
		a.world_dr = a.world_dr or {}
		a.world_dr.categories = a.world_dr.categories or {}
		a.world_dr.categories[cat] = v and true or false
		apply()
	end

	local function slider(col, label, key, min, max, fallback)
		col:Slider({
			LabelText = label,
			Min = min, Max = max, Step = 1,
			GetValue = function() return getWP(key, fallback) end,
			SetValue = function(v) setWP(key, v) end,
		})
	end

	mini:CreateSectionedPanel({
		Parent = page,

		-- ── Always visible: Enable / Test Mode ─────────────────────────────
		BuildHeader = function(header)
			local enableCB = mini:Checkbox({
				Parent = header,
				LabelText = "Enable",
				Tooltip = "Show DR icons on the target frame in the open world.",
				GetValue = function() return getWP("enabled", true) end,
				SetValue = function(v)
					setWP("enabled", v and true or false)
					Core:ApplyModules()
				end,
			})
			enableCB:SetPoint("TOP", header, "TOP", -colOffset - 40, -4)

			local testCB = mini:Checkbox({
				Parent = header,
				LabelText = "Test Mode",
				Tooltip = "Show preview DR icons on the target frame or nameplate (requires a target). Drag the Target frame icons to reposition them. Nameplate icons are placed with the Nameplate X/Y Offset sliders: Blizzard does not allow moving anything attached to a nameplate.",
				GetValue = function() return getWP("test_enabled", false) end,
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
					local size = mini:Column(panel, -colOffset, colWidth, "Size")
					slider(size, "Icon Size",       "icon_size", 12, 64, 22)
					slider(size, "Spacing",         "spacing",   0,  20, 2)
					slider(size, "Timer Font Size", "font_size", 8,  32, 12)

					local pos = mini:Column(panel, colOffset, colWidth, "Position")
					slider(pos, "X Offset", "pos_x", -300, 300, 0)
					slider(pos, "Y Offset", "pos_y", -200, 200, 20)
					pos:Dropdown("Grow Direction", {
						Items = { "RIGHT", "LEFT", "UP", "DOWN" },
						GetValue = function() return getWP("grow", "RIGHT") end,
						SetValue = function(v) setWP("grow", v) end,
					})
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
						GetValue = function() return getWP("border_style", "GLOW") end,
						SetValue = function(v) setWP("border_style", v) end,
					})
					slider(border, "Border Size",       "border_size",       0, 8, 1)
					slider(border, "Pixel Border Size", "pixel_border_size", 1, 4, 2)
					border:Checkbox({
						LabelText = "Black Border",
						Tooltip = "Color the border black instead of the DR stage color (green = 1/2, red = 2/2).",
						GetValue = function() return getWP("border_black", false) end,
						SetValue = boolSetter("border_black"),
					})

					local text = mini:Column(panel, colOffset, colWidth, "Text")
					text:Checkbox({
						LabelText = "Show DR Text (1/2, 2/2)",
						Tooltip = "Show the DR stage in the icon corner: 1/2 = first application (next is halved), 2/2 = second (next is immune).",
						GetValue = function() return getWP("show_dr_text", true) end,
						SetValue = boolSetter("show_dr_text"),
					})
					text:Checkbox({
						LabelText = "Color Countdown Text",
						Tooltip = "Color the remaining-time text with the DR severity color.",
						GetValue = function() return getWP("color_cd_text", true) end,
						SetValue = boolSetter("color_cd_text"),
					})
					text:Checkbox({
						LabelText = "Show Decimals",
						Tooltip = "Show one decimal place on the countdown when it drops below the threshold.",
						GetValue = function() return getWP("show_decimals", true) end,
						SetValue = boolSetter("show_decimals"),
					})
					text:Checkbox({
						LabelText = "Static Category Icons",
						Tooltip = "Always use a fixed icon per DR category instead of the triggering spell's icon.",
						GetValue = function() return getWP("static_icons", false) end,
						SetValue = boolSetter("static_icons"),
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
						GetValue = function() return getWP("reverse_swipe", true) end,
						SetValue = boolSetter("reverse_swipe"),
					})
					swipe:Checkbox({
						LabelText = "Disable Cooldown Swipe",
						Tooltip = "Hide the dark swipe animation on the DR icons.",
						GetValue = function() return getWP("disable_swipe", false) end,
						SetValue = boolSetter("disable_swipe"),
					})

					local cats = mini:Column(panel, colOffset, colWidth, "Tracked Categories")
					local catDefs = {
						{ key = "stun",  label = "Stuns" },
						{ key = "incap", label = "Incapacitates" },
						{ key = "fear",  label = "Fears" },
						{ key = "root",  label = "Roots" },
					}
					for _, def in ipairs(catDefs) do
						cats:Checkbox({
							LabelText = def.label,
							GetValue = function() return getCat(def.key) end,
							SetValue = function(v) setCat(def.key, v) end,
						})
					end
				end,
			},

			-- ── Nameplates ───────────────────────────────────────────────────
			-- Nameplate mode keeps its OWN offsets, so the toggle can flip back
			-- and forth without losing the Target frame placement.
			{
				Key = "nameplates",
				Title = "Nameplates",
				Build = function(panel)
					local anchor = mini:Column(panel, -colOffset, colWidth, "Anchor")
					anchor:Checkbox({
						LabelText = "Anchor to Nameplates",
						Tooltip = "Show the DR icons above your target's nameplate instead of on the Target frame. Enemy nameplates must be enabled. In Test Mode, target an enemy to see the preview on their plate.",
						GetValue = function() return getWP("anchor_nameplate", false) end,
						SetValue = boolSetter("anchor_nameplate"),
					})
					anchor:Checkbox({
						LabelText = "Show on Both",
						Tooltip = "Show the DR icons on the Target frame AND on the nameplate at the same time. Both copies share the same timers, so they always match.",
						GetValue = function() return getWP("np_both", false) end,
						SetValue = boolSetter("np_both"),
					})
					anchor:Dropdown("Nameplate Grow", {
						Items = NP_GROW_ITEMS,
						GetText = function(v) return NP_GROW_TEXT[v] or tostring(v) end,
						GetValue = function() return getWP("np_grow", "CENTER") end,
						SetValue = function(v) setWP("np_grow", v) end,
					})
					anchor:Text("Centered sits above the plate. Left to Right and Right to Left sit beside "
						.. "the plate and grow away from it, so the first icon always stays next to it. "
						.. "These offsets are separate from the Target frame offsets.")

					local offsets = mini:Column(panel, colOffset, colWidth, "Nameplate Offsets")
					slider(offsets, "Nameplate X Offset", "np_pos_x", -300, 300, 0)
					slider(offsets, "Nameplate Y Offset", "np_pos_y", -200, 200, 10)
				end,
			},
		},
	})
end
