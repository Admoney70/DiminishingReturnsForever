local _, ns = ...

local Launcher = {}
ns.Minimap = Launcher

function Launcher:UpdatePosition()
    if not self.button or not Minimap or not ns.db then return end
    local angle = math.rad(ns.db.profile.minimap.angle)
    local x, y = math.cos(angle), math.sin(angle)
    if GetMinimapShape and GetMinimapShape() == "SQUARE" then
        local edge = math.max(math.abs(x), math.abs(y))
        x, y = x / edge, y / edge
    end
    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER",
        x * (Minimap:GetWidth() / 2 + 8), y * (Minimap:GetHeight() / 2 + 8))
end

function Launcher:Drag()
    local cx, cy = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    if not ns:IsFinite(cx) or not ns:IsFinite(cy) or not ns:IsFinite(scale) or scale <= 0
        or not ns:IsFinite(mx) or not ns:IsFinite(my) then return end
    local x, y = mx / scale - cx, my / scale - cy
    if x == 0 and y == 0 then return end
    local angle
    if x == 0 then
        angle = y > 0 and math.pi / 2 or -math.pi / 2
    else
        angle = math.atan(y / x)
        if x < 0 then angle = angle + math.pi end
    end
    ns.db.profile.minimap.angle = math.deg(angle) % 360
    self:UpdatePosition()
end

function Launcher:Create()
    if self.button or not Minimap then return end
    local button = CreateFrame("Button", "DrpulseMinimapButton", Minimap)
    self.button = button
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(24, 24)
    background:SetPoint("TOPLEFT", 5, -3)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    icon:SetTexture("Interface\\Icons\\Spell_Frost_FrostNova")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function(_, mouseButton)
        if button.suppressClick then button.suppressClick = nil return end
        if mouseButton == "RightButton" then
            ns.UI:SetLocked(not ns.db.profile.locked)
            if ns.Options.frame then ns.Options.frame:Refresh() end
        else
            ns.Options:Toggle()
        end
    end)
    button:SetScript("OnMouseDown", function() button.suppressClick = nil end)
    button:SetScript("OnDragStart", function(self)
        self.suppressClick = true
        if GameTooltip then GameTooltip:Hide() end
        self:SetScript("OnUpdate", function() Launcher:Drag() end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        Launcher:Drag()
    end)
    button:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Drpulse", 0.38, 0.85, 1)
        GameTooltip:AddLine("Left-click: settings", 0.9, 0.92, 0.95)
        GameTooltip:AddLine("Right-click: lock / unlock bars", 0.9, 0.92, 0.95)
        GameTooltip:AddLine("Drag: move around the minimap", 0.65, 0.7, 0.78)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    Minimap:HookScript("OnSizeChanged", function() Launcher:UpdatePosition() end)
end

function Launcher:Refresh()
    if not ns.db then return end
    self:Create()
    if not self.button then return end
    self:UpdatePosition()
    self.button:SetShown(not ns.db.profile.minimap.hide)
end

ns:On("READY", function() Launcher:Refresh() end)
