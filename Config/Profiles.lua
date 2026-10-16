-- Config/Profiles.lua
-- Profile management tab: switch, create, copy, reset, delete profiles.

local ADDON, ns = ...
ns = ns or {}
ns.Config = ns.Config or {}

local M = {}
ns.Config.Profiles = M

local profileUI = { newName = "", copyFrom = "", deleteName = "" }

local function GetProfileList()
	local Core = ns.Core
	local profiles = Core:GetUnifiedProfileValues()
	local items = {}
	for name in pairs(profiles) do
		items[#items + 1] = name
	end
	table.sort(items, function(a, b) return a:lower() < b:lower() end)
	return items
end

function M:Build(panel)
	local mini = ns.Framework
	local Core = ns.Core
	local verticalSpacing = mini.VerticalSpacing
	local contentWidth = mini.ContentWidth or 600

	-- ── Current Profile ──────────────────────────────────────────────────

	local currentLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	currentLabel:SetText("Current Profile")
	currentLabel:SetPoint("TOP", panel, "TOP", 0, 0)

	local currentDD, isModern = mini:Dropdown({
		Parent = panel,
		Items = GetProfileList(),
		GetValue = function() return Core:GetUnifiedProfileName() end,
		SetValue = function(v)
			Core:ApplyProfileSync(v)
			if ns.Config and ns.Config.RefreshAll then
				ns.Config:RefreshAll()
			end
		end,
	})

	if isModern then
		currentDD:SetPoint("TOP", currentLabel, "BOTTOM", 0, -6)
	else
		currentDD:SetPoint("TOP", currentLabel, "BOTTOM", -8, -6)
	end

	local origCurrentRefresh = currentDD.SkeletonRefresh
	function currentDD.SkeletonRefresh(ddSelf)
		if ddSelf.SetupMenu then
			ddSelf:SetupMenu(function(_, rootDescription)
				for _, name in ipairs(GetProfileList()) do
					rootDescription:CreateRadio(name, function(x)
						return x == Core:GetUnifiedProfileName()
					end, function()
						Core:ApplyProfileSync(name)
						if ns.Config and ns.Config.RefreshAll then
							ns.Config:RefreshAll()
						end
					end, name)
				end
			end)
		end
		if origCurrentRefresh then origCurrentRefresh(ddSelf) end
	end

	-- ── Create Profile ───────────────────────────────────────────────────

	local createDivider = mini:Divider({ Parent = panel, Text = "Create Profile" })
	createDivider:SetWidth(contentWidth)
	createDivider:SetPoint("TOP", currentDD, "BOTTOM", 0, -verticalSpacing)

	local newNameBox = mini:EditBox({
		Parent = panel,
		LabelText = "New Profile Name",
		Width = 200,
		GetValue = function() return profileUI.newName end,
		SetValue = function(v) profileUI.newName = v or "" end,
	})
	newNameBox.Label:SetPoint("TOP", createDivider, "BOTTOM", 0, -10)
	newNameBox.EditBox:SetPoint("TOP", newNameBox.Label, "BOTTOM", 0, -4)

	local createBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	createBtn:SetSize(120, 22)
	createBtn:SetPoint("LEFT", newNameBox.EditBox, "RIGHT", 12, 0)
	createBtn:SetText("Create / Switch")
	createBtn:SetScript("OnClick", function()
		local name = (profileUI.newName or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if name ~= "" then
			Core:ApplyProfileSync(name)
			profileUI.newName = ""
			newNameBox.EditBox:SetText("")
			if ns.Config and ns.Config.RefreshAll then
				ns.Config:RefreshAll()
			end
		end
	end)

	-- ── Copy Profile ─────────────────────────────────────────────────────

	local copyDivider = mini:Divider({ Parent = panel, Text = "Copy Profile" })
	copyDivider:SetWidth(contentWidth)
	copyDivider:SetPoint("TOP", newNameBox.EditBox, "BOTTOM", 0, -verticalSpacing)

	local copyLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	copyLabel:SetText("Copy From")
	copyLabel:SetPoint("TOP", copyDivider, "BOTTOM", 0, -10)

	local copyDD, copyIsModern = mini:Dropdown({
		Parent = panel,
		Items = GetProfileList(),
		GetValue = function() return profileUI.copyFrom or "" end,
		SetValue = function(v) profileUI.copyFrom = v or "" end,
	})

	if copyIsModern then
		copyDD:SetPoint("TOP", copyLabel, "BOTTOM", 0, -6)
	else
		copyDD:SetPoint("TOP", copyLabel, "BOTTOM", -8, -6)
	end

	local origCopyRefresh = copyDD.SkeletonRefresh
	function copyDD.SkeletonRefresh(ddSelf)
		if ddSelf.SetupMenu then
			ddSelf:SetupMenu(function(_, rootDescription)
				for _, name in ipairs(GetProfileList()) do
					rootDescription:CreateRadio(name, function(x)
						return x == (profileUI.copyFrom or "")
					end, function()
						profileUI.copyFrom = name
					end, name)
				end
			end)
		end
		if origCopyRefresh then origCopyRefresh(ddSelf) end
	end

	local copyBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	copyBtn:SetSize(140, 22)
	copyBtn:SetText("Copy Into Current")
	copyBtn:SetPoint("TOP", copyDD, "BOTTOM", 0, -10)
	copyBtn:SetScript("OnClick", function()
		local from = profileUI.copyFrom or ""
		if from == "" then return end
		StaticPopup_Show("DRFOREVER_CONFIRM", "Copy profile '" .. from .. "' into the current profile?", nil, {
			OnYes = function()
				Core:CopyUnifiedProfile(from)
				if ns.Config and ns.Config.RefreshAll then
					ns.Config:RefreshAll()
				end
			end,
		})
	end)

	-- ── Reset ────────────────────────────────────────────────────────────

	local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	resetBtn:SetSize(180, 22)
	resetBtn:SetPoint("TOP", copyBtn, "BOTTOM", 0, -10)
	resetBtn:SetText("Reset Current to Defaults")
	resetBtn:SetScript("OnClick", function()
		StaticPopup_Show("DRFOREVER_CONFIRM", "Reset current profile to defaults?", nil, {
			OnYes = function()
				Core:ResetUnifiedProfile()
				if ns.Config and ns.Config.RefreshAll then
					ns.Config:RefreshAll()
				end
			end,
		})
	end)

	-- ── Delete Profile ───────────────────────────────────────────────────

	local deleteDivider = mini:Divider({ Parent = panel, Text = "Delete Profile" })
	deleteDivider:SetWidth(contentWidth)
	deleteDivider:SetPoint("TOP", resetBtn, "BOTTOM", 0, -verticalSpacing)

	local deleteLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	deleteLabel:SetText("Delete Profile")
	deleteLabel:SetPoint("TOP", deleteDivider, "BOTTOM", 0, -10)

	local deleteDD, deleteIsModern = mini:Dropdown({
		Parent = panel,
		Items = GetProfileList(),
		GetValue = function() return profileUI.deleteName or "" end,
		SetValue = function(v) profileUI.deleteName = v or "" end,
	})

	if deleteIsModern then
		deleteDD:SetPoint("TOP", deleteLabel, "BOTTOM", 0, -6)
	else
		deleteDD:SetPoint("TOP", deleteLabel, "BOTTOM", -8, -6)
	end

	local origDeleteRefresh = deleteDD.SkeletonRefresh
	function deleteDD.SkeletonRefresh(ddSelf)
		if ddSelf.SetupMenu then
			ddSelf:SetupMenu(function(_, rootDescription)
				for _, name in ipairs(GetProfileList()) do
					rootDescription:CreateRadio(name, function(x)
						return x == (profileUI.deleteName or "")
					end, function()
						profileUI.deleteName = name
					end, name)
				end
			end)
		end
		if origDeleteRefresh then origDeleteRefresh(ddSelf) end
	end

	local deleteBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	deleteBtn:SetSize(100, 22)
	deleteBtn:SetText("Delete")
	deleteBtn:SetPoint("TOP", deleteDD, "BOTTOM", 0, -10)
	deleteBtn:SetScript("OnClick", function()
		local name = profileUI.deleteName or ""
		local cur = Core:GetUnifiedProfileName()
		if name == "" then return end
		if name == cur then
			mini:Notify("Cannot delete the active profile.")
			return
		end
		StaticPopup_Show("DRFOREVER_CONFIRM", "Delete profile '" .. name .. "'?", nil, {
			OnYes = function()
				Core:DeleteUnifiedProfile(name)
				profileUI.deleteName = ""
				if ns.Config and ns.Config.RefreshAll then
					ns.Config:RefreshAll()
				end
			end,
		})
	end)
end
