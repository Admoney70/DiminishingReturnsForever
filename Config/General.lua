-- Config/General.lua
-- General tab: title, description, enable/test toggles, reset, import/export

local ADDON, ns = ...
ns = ns or {}
ns.Config = ns.Config or {}

local M = {}
ns.Config.General = M

local profilePrefix = "!MDR!"
local profileIOWindow

local function ExportProfile()
	local Core = ns.Core
	if not (Core and Core.arenaDB and Core.arenaDB.profile and Core.arenaDB.profile.arena) then
		return ""
	end
	local arena = Core.arenaDB.profile.arena
	local serialized = C_EncodingUtil.SerializeCBOR(arena)
	local encoded = C_EncodingUtil.EncodeBase64(serialized)
	return profilePrefix .. encoded
end

local function ImportProfile(str)
	if str:sub(1, #profilePrefix) ~= profilePrefix then
		return false, "Invalid profile string."
	end

	local encoded = str:sub(#profilePrefix + 1)
	local decoded = C_EncodingUtil.DecodeBase64(encoded)
	if not decoded or decoded == "" then
		return false, "Failed to decode profile string."
	end

	local ok, importedTable = pcall(C_EncodingUtil.DeserializeCBOR, decoded)
	if not ok or type(importedTable) ~= "table" then
		return false, "Profile string is corrupted."
	end

	local Core = ns.Core
	if not (Core and Core.arenaDB and Core.arenaDB.profile) then
		return false, "Database not ready."
	end

	Core.arenaDB.profile.arena = importedTable
	Core:RepairDB()
	Core:ApplyModules()
	Core:NotifyOptionsChanged()

	return true
end

local function GetOrCreateProfileIOWindow()
	if profileIOWindow then return profileIOWindow end

	local mini = ns.Framework

	local win = CreateFrame("Frame", "DiminishingReturnsForeverProfileIOWindow", UIParent, "BackdropTemplate")
	win:SetSize(500, 240)
	win:SetFrameStrata("DIALOG")
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	win:Hide()

	win:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	win:SetBackdropColor(0, 0, 0, 0.9)

	local title = win:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOP", win, "TOP", 0, -10)
	title:SetText("Import/Export Profile")
	local tr, tg, tb = mini:GetThemeColor()
	title:SetTextColor(tr, tg, tb)
	mini:RegisterThemed(title, "SetTextColor")

	local divider = win:CreateTexture(nil, "ARTWORK")
	divider:SetHeight(1)
	divider:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -28)
	divider:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -28)
	divider:SetColorTexture(1, 1, 1, 0.15)

	local innerWidth = 500 - 32

	local exportLabel = win:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	exportLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -42)
	exportLabel:SetText("Export Profile")

	local exportBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
	exportBox:SetHeight(28)
	exportBox:SetWidth(innerWidth)
	exportBox:SetPoint("TOPLEFT", exportLabel, "BOTTOMLEFT", 0, -6)
	exportBox:SetAutoFocus(false)
	exportBox:SetMaxLetters(0)
	exportBox:SetScript("OnEscapePressed", function() win:Hide() end)
	exportBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

	local importLabel = win:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	importLabel:SetPoint("TOPLEFT", exportBox, "BOTTOMLEFT", 0, -16)
	importLabel:SetText("Import Profile")

	local importBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
	importBox:SetHeight(28)
	importBox:SetWidth(innerWidth)
	importBox:SetPoint("TOPLEFT", importLabel, "BOTTOMLEFT", 0, -6)
	importBox:SetAutoFocus(false)
	importBox:SetMaxLetters(0)
	importBox:SetScript("OnEscapePressed", function() win:Hide() end)

	local importBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
	importBtn:SetSize(100, 22)
	importBtn:SetPoint("TOPRIGHT", importBox, "BOTTOMRIGHT", 0, -12)
	importBtn:SetText("Import")
	importBtn:SetScript("OnClick", function()
		local str = importBox:GetText():gsub("%s+", "")
		if str == "" then
			mini:Notify("Please paste a profile string to import.")
			return
		end
		local ok, err = ImportProfile(str)
		if not ok then
			mini:Notify(err)
			return
		end
		if ns.Config and ns.Config.RefreshAll then
			ns.Config:RefreshAll()
		end
		mini:Notify("Profile imported successfully.")
		win:Hide()
	end)

	local closeBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
	closeBtn:SetSize(80, 22)
	closeBtn:SetPoint("TOPRIGHT", importBtn, "TOPLEFT", -8, 0)
	closeBtn:SetText(CLOSE)
	closeBtn:SetScript("OnClick", function() win:Hide() end)

	win.ExportBox = exportBox
	win.ImportBox = importBox
	profileIOWindow = win
	return win
end

local function ShowProfileIOWindow()
	local win = GetOrCreateProfileIOWindow()
	win.ExportBox:SetText(ExportProfile())
	win.ImportBox:SetText("")
	win:ClearAllPoints()
	win:SetPoint("CENTER", UIParent, "CENTER")
	win:Show()
end

function M:Build(panel)
	local mini = ns.Framework
	local Core = ns.Core
	local verticalSpacing = mini.VerticalSpacing

	-- Color Scheme picker
	local colorLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	colorLabel:SetText("Color Scheme")
	colorLabel:SetPoint("TOP", panel, "TOP", 0, -verticalSpacing)
	colorLabel:SetJustifyH("CENTER")

	local colorPresets = {
		{ name = "Gold",   r = 1.0,  g = 1.0,  b = 0.0  },
		{ name = "Red",    r = 0.9,  g = 0.2,  b = 0.2  },
		{ name = "Blue",   r = 0.3,  g = 0.6,  b = 1.0  },
		{ name = "Green",  r = 0.2,  g = 0.9,  b = 0.3  },
		{ name = "Purple", r = 0.7,  g = 0.3,  b = 1.0  },
		{ name = "Teal",   r = 0.0,  g = 0.8,  b = 0.8  },
	}

	local swatchSize = 22
	local swatchSpacing = 6
	local customBtnWidth = 70
	local totalSwatchWidth = #colorPresets * swatchSize + (#colorPresets - 1) * swatchSpacing + swatchSpacing + customBtnWidth

	local swatchRow = CreateFrame("Frame", nil, panel)
	swatchRow:SetSize(totalSwatchWidth, swatchSize)
	swatchRow:SetPoint("TOP", colorLabel, "BOTTOM", 0, -8)

	local swatches = {}

	local function updateSwatchSelection()
		local cr, cg, cb = mini:GetThemeColor()
		for _, sw in ipairs(swatches) do
			local matched = (math.abs(sw.r - cr) < 0.05 and math.abs(sw.g - cg) < 0.05 and math.abs(sw.b - cb) < 0.05)
			if matched then
				sw.border:SetColorTexture(1, 1, 1, 0.9)
			else
				sw.border:SetColorTexture(0.3, 0.3, 0.3, 0.6)
			end
		end
	end

	for i, preset in ipairs(colorPresets) do
		local sw = CreateFrame("Button", nil, swatchRow)
		sw:SetSize(swatchSize, swatchSize)
		if i == 1 then
			sw:SetPoint("LEFT", swatchRow, "LEFT", 0, 0)
		else
			sw:SetPoint("LEFT", swatches[i - 1], "RIGHT", swatchSpacing, 0)
		end

		local border = sw:CreateTexture(nil, "BACKGROUND")
		border:SetAllPoints()
		border:SetColorTexture(0.3, 0.3, 0.3, 0.6)

		local color = sw:CreateTexture(nil, "ARTWORK")
		color:SetPoint("TOPLEFT", 2, -2)
		color:SetPoint("BOTTOMRIGHT", -2, 2)
		color:SetColorTexture(preset.r, preset.g, preset.b, 1)

		sw.border = border
		sw.r = preset.r
		sw.g = preset.g
		sw.b = preset.b

		sw:SetScript("OnClick", function()
			mini:SetThemeColor(preset.r, preset.g, preset.b)
			updateSwatchSelection()
		end)

		sw:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(preset.name)
			GameTooltip:Show()
		end)
		sw:SetScript("OnLeave", function() GameTooltip:Hide() end)

		swatches[i] = sw
	end

	-- Custom color picker button
	local customBtn = CreateFrame("Button", nil, swatchRow, "UIPanelButtonTemplate")
	customBtn:SetSize(customBtnWidth, swatchSize)
	customBtn:SetPoint("LEFT", swatches[#swatches], "RIGHT", swatchSpacing, 0)
	customBtn:SetText("Custom")
	customBtn:SetScript("OnClick", function()
		local cr, cg, cb = mini:GetThemeColor()
		local info = {
			swatchFunc = function()
				local r, g, b = ColorPickerFrame:GetColorRGB()
				mini:SetThemeColor(r, g, b)
				updateSwatchSelection()
			end,
			hasOpacity = false,
			r = cr, g = cg, b = cb,
			cancelFunc = function()
				mini:SetThemeColor(cr, cg, cb)
				updateSwatchSelection()
			end,
		}
		if ColorPickerFrame.SetupColorPickerAndShow then
			ColorPickerFrame:SetupColorPickerAndShow(info)
		else
			ColorPickerFrame:SetColorRGB(cr, cg, cb)
			ColorPickerFrame.hasOpacity = false
			ColorPickerFrame.func = info.swatchFunc
			ColorPickerFrame.cancelFunc = info.cancelFunc
			ShowUIPanel(ColorPickerFrame)
		end
	end)

	updateSwatchSelection()

	-- Buttons centered below
	local btnContainer = CreateFrame("Frame", nil, panel)
	btnContainer:SetSize(260, 26)
	btnContainer:SetPoint("TOP", swatchRow, "BOTTOM", 0, -verticalSpacing * 2)

	local resetBtn = CreateFrame("Button", nil, btnContainer, "UIPanelButtonTemplate")
	resetBtn:SetSize(120, 26)
	resetBtn:SetPoint("RIGHT", btnContainer, "CENTER", -6, 0)
	resetBtn:SetText("Reset")
	resetBtn:SetScript("OnClick", function()
		if InCombatLockdown() then
			mini:NotifyCombatLockdown()
			return
		end
		StaticPopup_Show("DRFOREVER_CONFIRM", "Are you sure you wish to reset to factory settings?", nil, {
			OnYes = function()
				Core:ResetUnifiedProfile()
				if ns.Config and ns.Config.RefreshAll then
					ns.Config:RefreshAll()
				end
				mini:Notify("Settings reset to default.")
			end,
		})
	end)

	local importExportBtn = CreateFrame("Button", nil, btnContainer, "UIPanelButtonTemplate")
	importExportBtn:SetSize(120, 26)
	importExportBtn:SetPoint("LEFT", btnContainer, "CENTER", 6, 0)
	importExportBtn:SetText("Import/Export")
	importExportBtn:SetScript("OnClick", function()
		if InCombatLockdown() then
			mini:NotifyCombatLockdown()
			return
		end
		ShowProfileIOWindow()
	end)

	-- Refresh theme on profile switch
	panel.OnSkeletonRefresh = function()
		mini:ApplyTheme()
		updateSwatchSelection()
	end
end
