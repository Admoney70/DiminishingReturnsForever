-- Config/Config.lua
-- Main configuration window with vertical tabs, styled like MiniCC. 

local ADDON, ns = ...
ns = ns or {}
ns.Config = ns.Config or {}

local C = ns.Config

local TITLE = "Diminishing Returns Forever"

function C:Init()
	local mini = ns.Framework

	-- Register a minimal WoW settings entry for discoverability.
	local redirectPanel = CreateFrame("Frame")
	redirectPanel.name = TITLE

	local category = mini:AddCategory(redirectPanel)
	if category then
		local redirectMsg = redirectPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		redirectMsg:SetPoint("TOPLEFT", 16, -16)
		redirectMsg:SetText("Use /dr to open the " .. TITLE .. " config window.")

		local redirectBtn = CreateFrame("Button", nil, redirectPanel, "UIPanelButtonTemplate")
		redirectBtn:SetSize(200, 26)
		redirectBtn:SetPoint("TOPLEFT", redirectMsg, "BOTTOMLEFT", 0, -12)
		redirectBtn:SetText("Open Settings")
		redirectBtn:SetScript("OnClick", function()
			C.Window:Show()
		end)
	end

	-- Standalone config window
	local windowWidth = 860
	local windowHeight = 600   -- tall enough that every DR sub-tab fits without scrolling

	local window = mini:CreateStandaloneWindow({
		Name = ADDON .. "ConfigFrame",
		Title = TITLE,
		Width = windowWidth,
		Height = windowHeight,
	})

	C.Window = window

	-- Center window on each show
	local previouslyHidden = true
	window:HookScript("OnHide", function() previouslyHidden = true end)
	window:HookScript("OnShow", function(self)
		if previouslyHidden then
			previouslyHidden = false
			self:ClearAllPoints()
			self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		end
	end)

	-- Tab layout calculations
	local contentPadding = 12
	local windowInset = 2 + contentPadding * 2 + 8
	local tabStripWidth = 130
	local tabHorizontalPadding = 12
	local contentWidth = windowWidth - windowInset - tabStripWidth - tabHorizontalPadding
	mini.ContentWidth = contentWidth
	mini.TextMaxWidth = contentWidth - windowInset

	-- Tabs
	local tabs = {
		{
			Key = "DRSettings",
			Title = "Arena DR",
			NoScroll = true,   -- the page has its own sub-tabs
			Build = function(content)
				C.DRSettings:Build(content)
			end,
		},
		{
			Key = "WorldDR",
			Title = "World DR",
			NoScroll = true,
			Build = function(content)
				C:BuildWorldDRTab(content)
			end,
		},
		{
			Key = "BlitzDR",
			Title = "Blitz DR",
			NoScroll = true,
			Build = function(content)
				C.BlitzDRSettings:Build(content)
			end,
		},
		{
			Key = "General",
			Title = "General",
			Build = function(content)
				C.General:Build(content)
			end,
		},
		{
			Key = "Profiles",
			Title = "Profiles",
			Build = function(content)
				C.Profiles:Build(content)
			end,
		},
	}

	local tabController = mini:CreateTabs({
		Parent = window.Content,
		InitialKey = "DRSettings",
		ScrollBody = true,
		ScrollContentWidth = contentWidth,
		ContentInsets = { Top = 4 },
		Vertical = true,
		StripWidth = tabStripWidth,
		TabHeight = 30,
		TabSpacing = 8,
		HorizontalPadding = tabHorizontalPadding,
		Tabs = tabs,
	})

	C.TabController = tabController

	-- Apply theme color to all registered elements
	mini:ApplyTheme()

	-- Confirmation dialog
	StaticPopupDialogs["DRFOREVER_CONFIRM"] = {
		text = "%s",
		button1 = YES,
		button2 = NO,
		OnAccept = function(_, data)
			if data and data.OnYes then data.OnYes() end
		end,
		OnCancel = function(_, data)
			if data and data.OnNo then data.OnNo() end
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
end

function C:RefreshAll()
	local mini = ns.Framework
	if mini then mini:ApplyTheme() end

	local tabController = C.TabController
	if not tabController then return end
	for i = 1, #tabController.Tabs do
		local content = tabController:GetContent(tabController.Tabs[i].Key)
		if content and content.SkeletonRefresh then
			content:SkeletonRefresh()
		end
	end
end
