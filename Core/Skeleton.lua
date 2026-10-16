-- Skeleton for Diminishing Returns Forever (from MidnightDiminish)

local addonName, ns = ...
ns = ns or {}

local dropDownId = 1
local sliderId = 1

---@class Skeleton
local M = {
	VerticalSpacing = 16,
	HorizontalSpacing = 20,
	TextMaxWidth = 600,
	ThemedElements = {},
	ThemeCallbacks = {},
}
ns.Framework = M

function M:GetThemeColor()
	local Core = ns.Core
	if Core and Core.arenaDB and Core.arenaDB.profile and Core.arenaDB.profile.arena then
		local t = Core.arenaDB.profile.arena.theme
		if t then return t.r or 1, t.g or 1, t.b or 0 end
	end
	return 1, 1, 0
end

function M:SetThemeColor(r, g, b)
	local Core = ns.Core
	if Core and Core.arenaDB and Core.arenaDB.profile and Core.arenaDB.profile.arena then
		Core.arenaDB.profile.arena.theme = { r = r, g = g, b = b }
	end
	M:ApplyTheme(r, g, b)
end

function M:ApplyTheme(r, g, b)
	if not r then r, g, b = M:GetThemeColor() end
	for _, entry in ipairs(M.ThemedElements) do
		if entry.element and entry.method then
			pcall(function()
				if entry.method == "SetTextColor" then
					entry.element:SetTextColor(r, g, b, entry.alpha or 1)
				elseif entry.method == "SetColorTexture" then
					entry.element:SetColorTexture(r, g, b, entry.alpha or 1)
				end
			end)
		end
	end
	for _, cb in ipairs(M.ThemeCallbacks) do
		pcall(cb, r, g, b)
	end
end

function M:RegisterThemed(element, method, alpha)
	M.ThemedElements[#M.ThemedElements + 1] = { element = element, method = method, alpha = alpha }
end

local function AddControlForRefresh(panel, control)
	panel.SkeletonControls = panel.SkeletonControls or {}
	panel.SkeletonControls[#panel.SkeletonControls + 1] = control

	if panel.SkeletonRefresh then
		return
	end

	panel.SkeletonRefresh = function(panelSelf)
		for _, c in ipairs(panelSelf.SkeletonControls or {}) do
			if c.SkeletonRefresh then
				c:SkeletonRefresh()
			end
		end
		if panel.OnSkeletonRefresh then
			panel:OnSkeletonRefresh()
		end
	end
end

local function ConfigureNumericBox(box, allowNegative)
	if not allowNegative then
		box:SetNumeric(true)
		return
	end

	box:HookScript("OnTextChanged", function(boxSelf, userInput)
		if not userInput then return end
		local text = boxSelf:GetText()
		if text == "" or text == "-" or text:match("^%-?%d+$") then return end
		text = text:gsub("[^%d%-]", "")
		text = text:gsub("%-+", "-")
		if text:sub(1, 1) ~= "-" then
			text = text:gsub("%-", "")
		else
			text = "-" .. text:sub(2):gsub("%-", "")
		end
		boxSelf:SetText(text)
	end)
end

function M:Notify(msg, ...)
	local formatted = string.format(msg, ...)
	print(addonName .. " - " .. formatted)
end

function M:NotifyCombatLockdown()
	M:Notify("Can't do that during combat.")
end

function M:AddCategory(panel)
	if not panel then error("AddCategory - panel must not be nil.") end
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
		Settings.RegisterAddOnCategory(category)
		return category
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
		return panel
	end
	return nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Widgets
-- ─────────────────────────────────────────────────────────────────────────────

function M:Divider(options)
	if not options or not options.Parent then
		error("Divider - invalid options.")
	end

	local container = CreateFrame("Frame", nil, options.Parent)
	container:SetHeight(26)

	local leftLine = container:CreateTexture(nil, "ARTWORK")
	leftLine:SetColorTexture(1, 1, 1, 0.15)
	PixelUtil.SetHeight(leftLine, 1)

	local rightLine = container:CreateTexture(nil, "ARTWORK")
	rightLine:SetColorTexture(1, 1, 1, 0.15)
	PixelUtil.SetHeight(rightLine, 1)

	local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	label:SetText(options.Text or "")
	label:SetTextColor(1, 1, 1, 1)
	label:SetPoint("CENTER", container, "CENTER")

	PixelUtil.SetPoint(leftLine, "LEFT", container, "LEFT", 0, 0)
	PixelUtil.SetPoint(leftLine, "RIGHT", label, "LEFT", -8, 0)
	PixelUtil.SetPoint(rightLine, "LEFT", label, "RIGHT", 8, 0)
	PixelUtil.SetPoint(rightLine, "RIGHT", container, "RIGHT", 0, 0)

	return container
end

function M:EditBox(options)
	if not options or not options.Parent or not options.GetValue or not options.SetValue then
		error("EditBox - invalid options.")
	end

	local label = options.Parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetText(options.LabelText or "")

	local box = CreateFrame("EditBox", nil, options.Parent, "InputBoxTemplate")
	box:SetSize(options.Width or 80, options.Height or 20)
	box:SetAutoFocus(false)

	if options.Numeric then
		ConfigureNumericBox(box, options.AllowNegatives)
	end

	local function Commit()
		local new = box:GetText()
		options.SetValue(new)
		local value = options.GetValue() or ""
		box:SetText(tostring(value))
		box:SetCursorPosition(0)
	end

	box:SetScript("OnEnterPressed", function(boxSelf)
		boxSelf:ClearFocus()
		Commit()
	end)
	box:SetScript("OnEditFocusLost", Commit)

	function box.SkeletonRefresh(boxSelf)
		local value = options.GetValue()
		boxSelf:SetText(tostring(value))
		boxSelf:SetCursorPosition(0)
	end

	box:SkeletonRefresh()
	AddControlForRefresh(options.Parent, box)

	return { EditBox = box, Label = label }
end

function M:Dropdown(options)
	if not options or not options.Parent or not options.GetValue or not options.SetValue or not options.Items then
		error("Dropdown - invalid options.")
	end

	if MenuUtil and MenuUtil.CreateRadioMenu then
		local dd = CreateFrame("DropdownButton", nil, options.Parent, "WowStyle1DropdownTemplate")
		dd:SetupMenu(function(_, rootDescription)
			for _, value in ipairs(options.Items) do
				local text = options.GetText and options.GetText(value) or tostring(value)
				rootDescription:CreateRadio(text, function(x)
					return x == options.GetValue()
				end, function()
					options.SetValue(value)
				end, value)
			end
		end)

		function dd.SkeletonRefresh(ddSelf) ddSelf:Update() end
		AddControlForRefresh(options.Parent, dd)
		return dd, true
	end

	local libDD = LibStub and LibStub:GetLibrary("LibUIDropDownMenu-4.0", true)
	if libDD then
		local dd = libDD:Create_UIDropDownMenu(addonName .. "Dropdown" .. dropDownId, options.Parent)
		dropDownId = dropDownId + 1

		libDD:UIDropDownMenu_Initialize(dd, function()
			for _, value in ipairs(options.Items) do
				local info = libDD:UIDropDownMenu_CreateInfo()
				info.text = options.GetText and options.GetText(value) or tostring(value)
				info.value = value
				info.checked = function() return options.GetValue() == value end
				local id = dd:GetID(info)
				info.func = function()
					local text = options.GetText and options.GetText(value) or tostring(value)
					libDD:UIDropDownMenu_SetSelectedID(dd, id)
					libDD:UIDropDownMenu_SetText(dd, text)
					options.SetValue(value)
				end
				libDD:UIDropDownMenu_AddButton(info, 1)
				if options.GetValue() == value then
					libDD:UIDropDownMenu_SetSelectedID(dd, id)
				end
			end
		end)

		function dd.SkeletonRefresh()
			local value = options.GetValue()
			local text = options.GetText and options.GetText(value) or tostring(value)
			libDD:UIDropDownMenu_SetText(dd, text)
		end
		AddControlForRefresh(options.Parent, dd)
		return dd, false
	end

	if UIDropDownMenu_Initialize then
		local dd = CreateFrame("Frame", addonName .. "Dropdown" .. dropDownId, options.Parent, "UIDropDownMenuTemplate")
		dropDownId = dropDownId + 1

		UIDropDownMenu_Initialize(dd, function()
			for _, value in ipairs(options.Items) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = options.GetText and options.GetText(value) or tostring(value)
				info.value = value
				info.checked = function() return options.GetValue() == value end
				info.func = function()
					local text = options.GetText and options.GetText(value) or tostring(value)
					UIDropDownMenu_SetText(dd, text)
					options.SetValue(value)
				end
				UIDropDownMenu_AddButton(info, 1)
			end
		end)

		function dd.SkeletonRefresh()
			local value = options.GetValue()
			local text = options.GetText and options.GetText(value) or tostring(value)
			UIDropDownMenu_SetText(dd, text)
		end
		AddControlForRefresh(options.Parent, dd)
		return dd, false
	end

	error("Failed to create a dropdown control")
end

function M:Checkbox(options)
	if not options or not options.Parent or not options.GetValue or not options.SetValue then
		error("Checkbox - invalid options.")
	end

	local checkbox = CreateFrame("CheckButton", nil, options.Parent, "UICheckButtonTemplate")
	checkbox.Text:SetText(" " .. (options.LabelText or ""))
	checkbox.Text:SetFontObject("GameFontNormal")
	checkbox:SetChecked(options.GetValue())
	checkbox:HookScript("OnClick", function()
		options.SetValue(checkbox:GetChecked())
		checkbox:SetChecked(options.GetValue())
	end)

	if options.Tooltip then
		checkbox:SetScript("OnEnter", function(chkSelf)
			GameTooltip:SetOwner(chkSelf, "ANCHOR_RIGHT")
			local tooltipTitle = options.LabelText
			if not tooltipTitle or tooltipTitle:match("^%s*$") then tooltipTitle = "Information" end
			GameTooltip:SetText(tooltipTitle, 1, 0.82, 0)
			GameTooltip:AddLine(options.Tooltip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		checkbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end

	function checkbox.SkeletonRefresh()
		checkbox:SetChecked(options.GetValue())
	end

	AddControlForRefresh(options.Parent, checkbox)
	return checkbox
end

function M:Slider(options)
	if not options or not options.Parent or not options.GetValue or not options.SetValue
		or not options.Min or not options.Max or not options.Step then
		error("Slider - invalid options.")
	end

	local slider = CreateFrame("Slider", addonName .. "Slider" .. sliderId, options.Parent, "OptionsSliderTemplate")
	sliderId = sliderId + 1

	local label = slider:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 8)
	label:SetText(options.LabelText)

	slider:SetOrientation("HORIZONTAL")
	slider:SetMinMaxValues(options.Min, options.Max)
	slider:SetValue(options.GetValue())
	slider:SetValueStep(options.Step)
	slider:SetObeyStepOnDrag(true)
	slider:SetHeight(20)
	slider:SetWidth(options.Width or 400)

	local low = _G[slider:GetName() .. "Low"]
	local high = _G[slider:GetName() .. "High"]
	if low and high then
		low:SetText(options.Min)
		high:SetText(options.Max)
	end

	local hasFloat = math.floor(options.Step) ~= options.Step
	local box = CreateFrame("EditBox", nil, options.Parent, "InputBoxTemplate")

	if not hasFloat then
		ConfigureNumericBox(box, options.Min < 0)
	end

	local function GetDecimalPlaces(step)
		local s = tostring(step)
		local dot = s:find("%.")
		if not dot then return 0 end
		return #s - dot
	end

	local function GetMaxLetters(min, max, step)
		local decimals = GetDecimalPlaces(step)
		local maxAbs = math.max(math.abs(min), math.abs(max))
		local intDigits = #tostring(math.floor(maxAbs))
		local letters = intDigits
		if decimals > 0 then letters = letters + 1 + decimals end
		if min < 0 then letters = letters + 1 end
		return letters
	end

	box:SetPoint("CENTER", slider, "CENTER", 0, 30)
	box:SetFontObject("GameFontWhite")
	box:SetSize(50, 20)
	box:SetAutoFocus(false)
	box:SetMaxLetters(GetMaxLetters(options.Min, options.Max, options.Step))
	box:SetText(tostring(options.GetValue()))
	box:SetJustifyH("CENTER")
	box:SetCursorPosition(0)

	slider:SetScript("OnValueChanged", function(_, sliderValue, userInput)
		if userInput ~= nil and not userInput then return end
		box:SetText(tostring(sliderValue))
		options.SetValue(sliderValue)
	end)

	box:SetScript("OnTextChanged", function(_, userInput)
		if not userInput then return end
		local value = tonumber(box:GetText())
		if not value then return end
		slider:SetValue(value)
		options.SetValue(value)
	end)

	function box.SkeletonRefresh(boxSelf)
		local value = options.GetValue()
		boxSelf:SetText(tostring(value))
		boxSelf:SetCursorPosition(0)
	end

	function slider.SkeletonRefresh(sliderSelf)
		local value = options.GetValue()
		sliderSelf:SetValue(value)
	end

	AddControlForRefresh(options.Parent, slider)
	AddControlForRefresh(options.Parent, box)

	return { Slider = slider, EditBox = box, Label = label }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabs
-- ─────────────────────────────────────────────────────────────────────────────

function M:CreateTabs(options)
	assert(options and options.Parent, "CreateTabs: options.Parent required")
	assert(options.Tabs and #options.Tabs > 0, "CreateTabs: options.Tabs required")

	local parent = options.Parent
	local tabHeight = options.TabHeight or 22
	local tabMinWidth = options.TabMinWidth or 80
	local tabSpacing = options.TabSpacing or 6
	local stripHeight = options.StripHeight or 28
	local vertical = options.Vertical
	local stripWidth = options.StripWidth or 130
	local horizontalPadding = options.HorizontalPadding or 0

	local insets = options.ContentInsets or {}
	local insetL = insets.Left or 0
	local insetR = insets.Right or 0
	local insetT = insets.Top or 0
	local insetB = insets.Bottom or 10

	local strip = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	if vertical then
		strip:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
		strip:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
		strip:SetWidth(stripWidth)
	else
		strip:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
		strip:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
		strip:SetHeight(stripHeight)
	end

	local body = CreateFrame("Frame", nil, parent)
	if vertical then
		body:SetPoint("TOPLEFT", strip, "TOPRIGHT", horizontalPadding + insetL, -insetT)
		body:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -insetR, insetB)
	else
		body:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", insetL, -insetT)
		body:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -insetR, insetB)
	end

	local tabs = {}
	local keyToIndex = {}
	local selectedKey

	local function GetIndex(keyOrIndex)
		if type(keyOrIndex) == "number" then return keyOrIndex end
		if type(keyOrIndex) == "string" then return keyToIndex[keyOrIndex] end
	end

	local normalR, normalG, normalB = GameFontNormal:GetTextColor()

	-- Vertical mode: static right-edge separator line.
	if vertical then
		local vLine = strip:CreateTexture(nil, "OVERLAY")
		vLine:SetWidth(1)
		vLine:SetColorTexture(0.35, 0.35, 0.35, 0.8)
		vLine:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)
		vLine:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 0)
	end

	local function SetSelected(btn, isSelected)
		if isSelected then
			local sr, sg, sb = M:GetThemeColor()
			btn.Text:SetTextColor(sr, sg, sb, 1)
			btn.Highlight:SetAlpha(0)
			if vertical then
				btn:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
				btn:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.8)
				if btn.Indicator then btn.Indicator:Show() end
			else
				btn:SetBackdropColor(0, 0, 0, 0)
				btn:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
			end
		else
			btn:SetBackdropColor(0, 0, 0, 0)
			btn:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)
			btn.Text:SetTextColor(normalR, normalG, normalB, 1)
			btn.Highlight:SetAlpha(0.06)
			if vertical then
				if btn.Indicator then btn.Indicator:Hide() end
			end
		end
	end

	local controller = {}

	function controller.GetSelected(_) return selectedKey end

	function controller.GetContent(_, keyOrIndex)
		local i = GetIndex(keyOrIndex)
		return i and tabs[i] and tabs[i].Content
	end

	function controller.GetTabButton(_, keyOrIndex)
		local i = GetIndex(keyOrIndex)
		return i and tabs[i] and tabs[i].Button
	end

	function controller.Select(_, keyOrIndex)
		local i = GetIndex(keyOrIndex)
		if not i or not tabs[i] then return end

		selectedKey = tabs[i].Key

		for j = 1, #tabs do
			local isSel = (j == i)
			tabs[j].Container:SetShown(isSel)
			SetSelected(tabs[j].Button, isSel)
		end

		if tabs[i].Container.SetVerticalScroll then
			tabs[i].Container:SetVerticalScroll(0)
		end

		if options.OnTabChanged then
			options.OnTabChanged(selectedKey, i)
		end
	end

	controller.Tabs = tabs

	local prev
	for i, def in ipairs(options.Tabs) do
		assert(def.Key and def.Key ~= "", "CreateTabs: each tab needs Key")
		assert(not keyToIndex[def.Key], "CreateTabs: duplicate Key: " .. def.Key)

		local btn = CreateFrame("Button", nil, strip, "BackdropTemplate")
		btn:SetHeight(tabHeight)
		btn:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Buttons\\WHITE8X8",
			edgeSize = 1,
		})

		btn.Text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		btn.Text:SetPoint("CENTER", btn, "CENTER", 0, 0)
		btn.Text:SetText(def.Title or def.Key)

		btn.Highlight = btn:CreateTexture(nil, "HIGHLIGHT")
		btn.Highlight:SetAllPoints(btn)
		btn.Highlight:SetColorTexture(1, 1, 1, 1)

		if vertical then
			btn.Indicator = btn:CreateTexture(nil, "OVERLAY")
			btn.Indicator:SetWidth(3)
			btn.Indicator:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
			btn.Indicator:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
			local ir, ig, ib = M:GetThemeColor()
			btn.Indicator:SetColorTexture(ir, ig, ib, 1.0)
			M:RegisterThemed(btn.Indicator, "SetColorTexture")
			btn.Indicator:Hide()

			if not prev then
				btn:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
				btn:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)
			else
				btn:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -tabSpacing)
				btn:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -tabSpacing)
			end
		else
			local fs = btn.Text
			local w = tabMinWidth
			if fs and fs.GetUnboundedStringWidth then
				w = math.max(tabMinWidth, fs:GetUnboundedStringWidth() + 26)
			elseif fs and fs.GetStringWidth then
				w = math.max(tabMinWidth, fs:GetStringWidth() + 26)
			end
			btn:SetWidth(w)

			if not prev then
				btn:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 1)
			else
				btn:SetPoint("LEFT", prev, "RIGHT", tabSpacing, 0)
			end
		end

		prev = btn

		local container, content

		-- A tab can opt out of the scroll body (NoScroll) when it lays out its
		-- own scrolling, e.g. a page split into sub-tabs.
		if options.ScrollBody and not def.NoScroll then
			local scrollContainer = CreateFrame("Frame", nil, body)
			scrollContainer:SetAllPoints(body)

			local scrollFrame = CreateFrame("ScrollFrame", nil, scrollContainer)
			scrollFrame:SetPoint("TOPLEFT", scrollContainer, "TOPLEFT", 0, 0)
			scrollFrame:SetPoint("BOTTOMRIGHT", scrollContainer, "BOTTOMRIGHT", -14, 0)
			scrollFrame:EnableMouseWheel(true)
			scrollFrame:SetScript("OnMouseWheel", function(sf, delta)
				local step = 40
				local cur = sf:GetVerticalScroll()
				local maxScroll = sf:GetVerticalScrollRange()
				sf:SetVerticalScroll(delta > 0 and math.max(cur - step, 0) or math.min(cur + step, maxScroll))
			end)

			local scrollChild = CreateFrame("Frame", nil, scrollFrame)
			local childWidth = options.ScrollContentWidth or 800
			scrollChild:SetSize(childWidth, options.ScrollContentHeight or 100)
			scrollFrame:SetScrollChild(scrollChild)

			local scrollBar = CreateFrame("Slider", nil, scrollContainer, "BackdropTemplate")
			scrollBar:SetWidth(10)
			scrollBar:SetPoint("TOPRIGHT", scrollContainer, "TOPRIGHT", 0, -2)
			scrollBar:SetPoint("BOTTOMRIGHT", scrollContainer, "BOTTOMRIGHT", 0, 2)
			scrollBar:SetMinMaxValues(0, 1)
			scrollBar:SetValue(0)
			scrollBar:SetObeyStepOnDrag(true)
			scrollBar:SetBackdrop({
				bgFile = "Interface\\Buttons\\WHITE8X8",
				edgeFile = "Interface\\Buttons\\WHITE8X8",
				edgeSize = 1,
			})
			scrollBar:SetBackdropColor(0.10, 0.10, 0.10, 0.6)
			scrollBar:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)

			local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
			thumb:SetColorTexture(0.55, 0.55, 0.55, 0.85)
			scrollBar:SetThumbTexture(thumb)

			local function UpdateScrollBar()
				local frameH = scrollFrame:GetHeight()
				local childH = scrollChild:GetHeight()
				if frameH == 0 then return end
				local maxScroll = math.max(0, childH - frameH)
				if maxScroll > 0.5 then
					scrollBar:Show()
					scrollBar:SetMinMaxValues(0, maxScroll)
					scrollBar:SetValue(math.min(scrollFrame:GetVerticalScroll(), maxScroll))
					thumb:SetHeight(math.max(20, scrollBar:GetHeight() * (frameH / childH)))
				else
					scrollBar:Hide()
				end
			end

			scrollBar:SetScript("OnValueChanged", function(_, val)
				scrollFrame:SetVerticalScroll(val)
			end)

			scrollFrame:SetScript("OnScrollRangeChanged", function()
				UpdateScrollBar()
			end)

			scrollFrame:HookScript("OnMouseWheel", function()
				scrollBar:SetValue(scrollFrame:GetVerticalScroll())
			end)

			scrollBar:Hide()

			if not options.ScrollContentHeight then
				scrollContainer:SetScript("OnShow", function(scrollSelf)
					scrollSelf:SetScript("OnShow", nil)
					local top = scrollChild:GetTop()
					if not top then return end
					local minBottom = top
					for _, child in ipairs({ scrollChild:GetChildren() }) do
						local b = child:GetBottom()
						if b and b < minBottom then minBottom = b end
					end
					local needed = math.ceil(top - minBottom) + 20
					scrollChild:SetHeight(math.max(needed, scrollFrame:GetHeight()))
					UpdateScrollBar()
				end)
			end

			container = scrollContainer
			content = scrollChild
		else
			local contentFrame = CreateFrame("Frame", nil, body)
			contentFrame:SetAllPoints(body)
			container = contentFrame
			content = contentFrame
		end

		container:Hide()

		local tab = { Key = def.Key, Title = def.Title or def.Key, Button = btn, Content = content, Container = container }
		tabs[i] = tab
		keyToIndex[def.Key] = i

		btn:SetScript("OnClick", function()
			controller:Select(i)
		end)

		if type(def.Build) == "function" then
			def.Build(content)
		end
	end

	local initialIndex = 1
	if options.InitialKey and keyToIndex[options.InitialKey] then
		initialIndex = keyToIndex[options.InitialKey]
	end

	for i = 1, #tabs do
		local isSel = (i == initialIndex)
		tabs[i].Container:SetShown(isSel)
		SetSelected(tabs[i].Button, isSel)
	end
	selectedKey = tabs[initialIndex].Key

	-- Re-color selected tab text when theme changes
	M.ThemeCallbacks[#M.ThemeCallbacks + 1] = function(r, g, b)
		for j = 1, #tabs do
			if tabs[j].Key == selectedKey then
				tabs[j].Button.Text:SetTextColor(r, g, b, 1)
			end
		end
	end

	if options.OnTabChanged then
		options.OnTabChanged(selectedKey, initialIndex)
	end

	if options.TabFitToParent then
		if vertical then
			local function DistributeTabs(h)
				if h == 0 or #tabs == 0 then return end
				local btnH = math.floor((h - tabSpacing * (#tabs - 1)) / #tabs)
				for _, tab in ipairs(tabs) do
					tab.Button:SetHeight(math.max(16, btnH))
				end
			end
			strip:SetScript("OnSizeChanged", function(_, _, h) DistributeTabs(h) end)
			local h = strip:GetHeight()
			if h and h > 0 then DistributeTabs(h) end
		else
			local function DistributeTabs(w)
				if w == 0 or #tabs == 0 then return end
				local btnW = math.floor((w - tabSpacing * (#tabs - 1)) / #tabs)
				for _, tab in ipairs(tabs) do
					tab.Button:SetWidth(btnW)
				end
			end
			strip:SetScript("OnSizeChanged", function(_, w) DistributeTabs(w) end)
			local w = strip:GetWidth()
			if w and w > 0 then DistributeTabs(w) end
		end
	end

	return controller
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Column layout
-- ─────────────────────────────────────────────────────────────────────────────
-- Stacks controls down one column of a settings page, anchoring each new
-- control under the previous one with consistent spacing. `x` is the column's
-- centre relative to the panel's centre line.

function M:Column(panel, x, width, title)
	local vs = M.VerticalSpacing
	local col = { SliderWidth = math.min(260, width - 30) }

	local top
	if title then
		top = M:Divider({ Parent = panel, Text = title })
		top:SetWidth(width)
	else
		top = CreateFrame("Frame", nil, panel)
		top:SetSize(1, 1)
	end
	top:SetPoint("TOP", panel, "TOP", x, -8)

	-- last: the control the next one anchors under. back: x shift from last's
	-- centre back to the column centre line. kind: what `last` is.
	local last, back, kind = top, 0, "top"

	function col.Checkbox(_, opts)
		opts.Parent = panel
		local cb = M:Checkbox(opts)
		if kind == "check" then
			cb:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -4)
		else
			-- The box sits left of centre so box + label read as centred.
			cb:SetPoint("TOP", last, "BOTTOM", back - 90, (kind == "top") and -vs or -vs * 1.5)
		end
		last, back, kind = cb, 90, "check"
		return cb
	end

	function col.Slider(_, opts)
		opts.Parent = panel
		opts.Width = opts.Width or col.SliderWidth
		local s = M:Slider(opts)
		-- Sliders draw their label and value box ABOVE the bar, so they need
		-- more headroom than other controls.
		s.Slider:SetPoint("TOP", last, "BOTTOM", back, (kind == "slider") and -vs * 2.5 or -vs * 2)
		last, back, kind = s.Slider, 0, "slider"
		return s
	end

	function col.Dropdown(_, labelText, opts)
		opts.Parent = panel
		local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		label:SetText(labelText)
		local gap = (kind == "slider") and -vs * 2.5 or ((kind == "top") and -vs or -vs * 1.5)
		label:SetPoint("TOP", last, "BOTTOM", back, gap)
		local dd, isModern = M:Dropdown(opts)
		dd:SetPoint("TOP", label, "BOTTOM", isModern and 0 or -8, -4)
		last, back, kind = dd, isModern and 0 or 8, "dropdown"
		return dd
	end

	function col.Text(_, text)
		local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		fs:SetWidth(width - 20)
		fs:SetJustifyH("CENTER")
		fs:SetText(text)
		fs:SetPoint("TOP", last, "BOTTOM", back, -vs)
		-- The scroll height is measured from child FRAMES only; a FontString
		-- is a region, so pin a 1px frame under it to keep it measured.
		local pin = CreateFrame("Frame", nil, panel)
		pin:SetSize(1, 1)
		pin:SetPoint("TOP", fs, "BOTTOM", 0, -4)
		last, back, kind = pin, 0, "text"
		return fs
	end

	return col
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Sectioned panel
-- ─────────────────────────────────────────────────────────────────────────────
-- A settings page split into sub-tabs instead of one long scroll: a fixed
-- header row (always visible, for toggles like Enable / Test Mode) above a
-- strip of horizontal sub-tabs, each with its own scroll body.
--
-- options.Parent       the page frame (a tab created with NoScroll = true)
-- options.BuildHeader  function(header) that builds the always-visible row
-- options.Tabs         { { Key, Title, Build = function(panel) }, ... }

function M:CreateSectionedPanel(options)
	assert(options and options.Parent, "CreateSectionedPanel: options.Parent required")
	local parent = options.Parent

	local header = CreateFrame("Frame", nil, parent)
	header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
	header:SetHeight(options.HeaderHeight or 38)
	if options.BuildHeader then options.BuildHeader(header) end

	local host = CreateFrame("Frame", nil, parent)
	host:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
	host:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	local inner = M:CreateTabs({
		Parent = host,
		Tabs = options.Tabs,
		ScrollBody = true,
		ScrollContentWidth = options.ContentWidth or M.ContentWidth,
		StripHeight = 26,
		TabHeight = 22,
		TabSpacing = 4,
		TabMinWidth = 96,
		ContentInsets = { Top = 6, Bottom = 0 },
	})

	-- Controls register for refresh on the frame they were built on, which is
	-- now the header and each sub-tab's own panel rather than the page. Forward
	-- the page-level refresh (profile switch, drag-to-move save) to all of them.
	parent.SkeletonRefresh = function()
		if header.SkeletonRefresh then header:SkeletonRefresh() end
		for _, t in ipairs(inner.Tabs) do
			if t.Content.SkeletonRefresh then t.Content:SkeletonRefresh() end
		end
	end

	return inner, header
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Standalone Window
-- ─────────────────────────────────────────────────────────────────────────────

function M:CreateStandaloneWindow(options)
	local width = options.Width or 860
	local height = options.Height or 680
	local frameName = options.Name or (addonName .. "ConfigFrame")

	local window = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
	window:SetSize(width, height)
	window:SetPoint("CENTER", UIParent, "CENTER")
	window:SetFrameStrata("HIGH")
	window:SetMovable(true)
	window:EnableMouse(true)
	window:SetToplevel(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", function(windowSelf) windowSelf:StartMoving() end)
	window:SetScript("OnDragStop", function(windowSelf)
		windowSelf:StopMovingOrSizing()
		local point, relativeTo, relativePoint, x, y = windowSelf:GetPoint()
		windowSelf:ClearAllPoints()
		windowSelf:SetPoint(point, relativeTo, relativePoint, x, y)
	end)
	window:Hide()

	window:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 1,
	})
	window:SetBackdropColor(0, 0, 0, 0.75)
	window:SetBackdropBorderColor(0.20, 0.20, 0.24, 1)

	-- Title bar
	local titleBar = CreateFrame("Frame", nil, window, "BackdropTemplate")
	titleBar:SetPoint("TOPLEFT", window, "TOPLEFT", 1, -1)
	titleBar:SetPoint("TOPRIGHT", window, "TOPRIGHT", -1, -1)
	titleBar:SetHeight(40)
	titleBar:SetBackdropColor(0, 0, 0, 0)
	titleBar:SetBackdropBorderColor(0, 0, 0, 0)

	local accentLine = window:CreateTexture(nil, "ARTWORK")
	accentLine:SetHeight(1)
	accentLine:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
	accentLine:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
	local tr, tg, tb = M:GetThemeColor()
	accentLine:SetColorTexture(tr, tg, tb, 0.25)
	M:RegisterThemed(accentLine, "SetColorTexture", 0.25)

	local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	titleText:SetText(options.Title or "")
	titleText:SetTextColor(tr, tg, tb, 1)
	M:RegisterThemed(titleText, "SetTextColor")

	if options.Subtitle then
		local subtitleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		subtitleText:SetText(options.Subtitle)
		subtitleText:SetTextColor(0.80, 0.80, 0.80, 1)
		window.SubtitleText = subtitleText

		-- Center the title + subtitle combo in the title bar
		local subWidth = subtitleText:GetStringWidth() or 0
		titleText:SetPoint("CENTER", titleBar, "CENTER", -(subWidth + 8) / 2, 0)
		subtitleText:SetPoint("LEFT", titleText, "RIGHT", 8, -1)
	else
		titleText:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
	end

	-- Close button
	local closeBtn = CreateFrame("Button", nil, titleBar)
	closeBtn:SetSize(28, 28)
	closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)

	local closeHighlight = closeBtn:CreateTexture(nil, "HIGHLIGHT")
	closeHighlight:SetAllPoints(closeBtn)
	closeHighlight:SetColorTexture(1, 1, 1, 0.07)

	local closeLabel = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	closeLabel:SetAllPoints(closeBtn)
	closeLabel:SetJustifyH("CENTER")
	closeLabel:SetJustifyV("MIDDLE")
	closeLabel:SetText("\195\151") -- multiplication sign (x)
	closeLabel:SetTextColor(0.5, 0.5, 0.5, 1)

	closeBtn:SetScript("OnEnter", function()
		local cr, cg, cb = M:GetThemeColor()
		closeLabel:SetTextColor(cr, cg, cb, 1)
	end)
	closeBtn:SetScript("OnLeave", function() closeLabel:SetTextColor(0.5, 0.5, 0.5, 1) end)
	closeBtn:SetScript("OnClick", function()
		window:Hide()
		if options.OnClose then options.OnClose() end
	end)

	-- Content area
	local pad = options.ContentPadding or 12
	local content = CreateFrame("Frame", nil, window)
	content:SetPoint("TOPLEFT", accentLine, "BOTTOMLEFT", pad, -(pad + 1))
	content:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -(pad + 1), pad + 1)

	-- ESC closes window (OnKeyDown avoids tainting UISpecialFrames).
	-- SetPropagateKeyboardInput is protected during combat, so it must not
	-- be called then; in combat ESC still closes the window but also
	-- propagates to the game menu.
	window:EnableKeyboard(true)
	if not InCombatLockdown() then
		window:SetPropagateKeyboardInput(true)
	end
	window:SetScript("OnKeyDown", function(windowSelf, key)
		if not InCombatLockdown() then
			windowSelf:SetPropagateKeyboardInput(key ~= "ESCAPE")
		end
		if key == "ESCAPE" then
			windowSelf:Hide()
		end
	end)
	if options.OnClose then
		window:SetScript("OnHide", function()
			options.OnClose()
		end)
	end

	window.TitleBar = titleBar
	window.TitleText = titleText
	window.Content = content
	window.CloseButton = closeBtn

	function window.Toggle(windowSelf)
		if windowSelf:IsShown() then
			windowSelf:Hide()
		else
			windowSelf:Show()
		end
	end

	return window
end
