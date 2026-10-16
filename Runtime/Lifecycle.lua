-- Adapted from Forever DR Core.lua (MIT, Copyright 2026 Tarolg).
-- Drpulse integration and visual adaptations: Copyright 2026 Joaqoz.
local addonName, ns = ...
local events = CreateFrame("Frame")
local paused

function ns.PrintStatus()
    local s = ns.stats
    ns.Print(ns.VERSION .. "; build " .. tostring((GetBuildInfo())) .. "; secret restrictions "
        .. tostring(C_Secrets.HasSecretRestrictions()) .. "; auras secret now " .. tostring(C_Secrets.ShouldAurasBeSecret()))
    ns.Print("Blizzard feed: " .. ns.nativeStatus .. "; data seen: " .. ns.nativeMode)
    ns.Print(string.format("Native %d (readable %d, category-only %d, secret %d, opaque %d, unknown category %d)",
        s.native, s.nativePublic, s.nativePartial, s.nativeSecret, s.nativeOpaque, s.nativeUnknownCategory))
    ns.Print(string.format("Auras applied %d ended %d; casts %d, group %d; confirmed %d, assumed %d, missed %d, immune hits %d, signals %d",
        s.auraApplied, s.auraEnded, s.casts, s.groupCasts, s.confirmed, s.assumed, s.notLanded, s.immuneHits, s.signals))
    local friends = {}
    for _, unit in ipairs(ns.FRIEND_UNITS) do
        if ns.WatchedUnits()[unit] then friends[#friends + 1] = unit end
    end
    ns.Print(string.format("Friendly DR %s; watching %s; friendly auras %d, loss of control on you %d",
        ns.db.friendly and "on" or "off", #friends > 0 and table.concat(friends, ", ") or "nobody",
        s.friendlyAuras, s.lossApplied))
    local enabled, onlyMine = ns.GetBlizzardOption(ns.CVAR_ENABLED), ns.GetBlizzardOption(ns.CVAR_ONLY_MINE)
    ns.Print("Blizzard options: enemies " .. tostring(enabled) .. ", only mine " .. tostring(onlyMine))
    local names = {}
    for _, category in ipairs(ns.CATEGORIES) do if ns.mine[category] then names[#names + 1] = category end end
    ns.Print("Your categories: " .. (#names > 0 and table.concat(names, ", ") or "none") .. "; filter " .. ns.db.filter)
    for index = 1, math.min(#ns.samples, 5) do ns.Print("  " .. ns.samples[index]) end
end

-- Every command, for /drpulse and /drpulse help: a reply to a typed command, so it
-- always prints; one coloured header instead of ns.Print's prefix on every
-- line.
local function PrintHelp()
    print("|cff61dafbDrpulse|r commands:")
    print("/drpulse - open settings and list these commands")
    print("/drpulse unlock - show the target display so you can drag it")
    print("/drpulse lock - lock the target display in place")
    print("/drpulse reset - put the target display back in its default place")
    print("/drpulse preview - show sample icons on the target display for 20 seconds")
    print("/drpulse clear - forget every tracked DR")
    print("/drpulse all - show every category")
    print("/drpulse mine - show only categories you can apply")
    print("/drpulse friendly - turn friendly DR (you and your party) on or off")
    print("/drpulse status - show the version, build and what the addon sees")
end

local function Command(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    if paused then ns.Print("Paused: " .. paused .. ". Original settings preserved."); return end
    if command == "" then
        ns.OpenSettings()
        PrintHelp()
    elseif command == "options" or command == "config" then ns.OpenSettings()
    elseif command == "unlock" then ns.SetLocked(false); ns.Print("Drag the blue strip above the target display, or the dots at its corner to resize it; right-click it or /drpulse lock when done.")
    elseif command == "lock" then ns.SetLocked(true)
    elseif command == "reset" then ns.ResetPosition(); ns.Print("Target display position reset.")
    elseif command == "preview" or command == "test" then ns.Preview(20)
    elseif command == "clear" then ns.ClearTracking(); ns.Print("Tracked DR cleared.")
    elseif command == "all" then ns.Set("filter", "all"); ns.Print("Showing every category.")
    elseif command == "mine" then ns.Set("filter", "mine"); ns.Print("Showing only categories you can apply.")
    elseif command == "friendly" or command == "friends" then
        ns.Set("friendly", not ns.db.friendly)
        ns.Print("Friendly DR " .. (ns.db.friendly and "on." or "off."))
    elseif command == "status" then ns.PrintStatus()
    else
        PrintHelp()
    end
end

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        local db, problem = ns.LoadDrpulseSettings(DrpulseV2DB)
        if not db then
            paused = problem
            ns.Print("Paused: " .. problem .. ". Original settings preserved.")
            return
        end
        DrpulseV2DB = db
        ns.db = db
        ns.tracker = ns.NewTracker(function() return ns.db.resetTime end, ns.Learned)
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        SLASH_DRPULSE1 = "/drpulse"
        SLASH_DRPULSE2 = nil
        SlashCmdList.DRPULSE = Command
        if paused or not ns.db then return end
        ns.StartDisplay()
        ns.StartFriendly()
        ns.StartSources()
        ns.BuildSettings()
        ns.StartDrpulseIntegration()
        ns.OnSettingChanged(function(key)
            if key == "enabled" and not ns.db.enabled then ns.ClearTracking() end
        end)
    end
end)
