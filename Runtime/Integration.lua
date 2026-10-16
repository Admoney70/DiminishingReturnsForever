local _, ns = ...

-- Product-specific integration is deliberately separate from the tracking engine.
local categoryNames = { [0] = "Root", "Taunt", "Stun", "AoEKnockback", "Incapacitate", "Disorient", "Silence", "Disarm" }

function ns.LoadDrpulseSettings(saved)
    local db, problem = ns.LoadSettings(saved)
    if not db then return nil, problem end
    if saved == nil then
        local legacy = type(DrpulseDB) == "table" and DrpulseDB or DRiftDB
        local profile = type(legacy) == "table" and legacy.profile
        if type(profile) == "table" then
            for old, new in pairs({ enabled = "enabled", locked = "locked", showText = "timer", showSwipe = "swipe" }) do
                if type(profile[old]) == "boolean" then db[new] = profile[old] end
            end
            if type(profile.surfaces) == "table" then
                for _, key in ipairs({ "target", "nameplates" }) do
                    if type(profile.surfaces[key]) == "boolean" then db[key] = profile.surfaces[key] end
                end
            end
            if ns.Number(profile.resetSeconds, 10, 30) then db.resetTime = profile.resetSeconds end
            if ns.Number(profile.iconSize, 16, 64) then db.iconSize = profile.iconSize end
            if type(profile.customSpells) == "table" then
                for id, category in pairs(profile.customSpells) do
                    if ns.Number(id, 1, 10000000) and id % 1 == 0 and type(category) == "number" and categoryNames[category] then
                        db.custom[id] = categoryNames[category]
                    end
                end
            end
            if type(profile.categories) == "table" then
                db.filter = "all"
                for id, category in pairs(categoryNames) do
                    if profile.categories[id] == false then db.categories[category] = "never"
                    elseif profile.categories[id] == true then db.categories[category] = "always" end
                end
            end
            local anchor = type(profile.anchors) == "table" and profile.anchors.target
            if type(anchor) == "table" and anchor.point == "CENTER" and anchor.relativePoint == "CENTER"
                and ns.Number(anchor.x, -3000, 3000) and ns.Number(anchor.y, -3000, 3000) then
                db.x, db.y = anchor.x, anchor.y
            end
            local minimap = type(profile.minimap) == "table" and profile.minimap or {}
            db.profile = { minimap = {
                hide = minimap.hide == true,
                angle = ns.Number(minimap.angle) and minimap.angle % 360 or 225,
            } }
        end
    end
    -- Retain the existing Drpulse minimap launcher without loading the old engine.
    if type(db.profile) ~= "table" then db.profile = {} end
    if type(db.profile.minimap) ~= "table" then db.profile.minimap = {} end
    db.profile.minimap.hide = db.profile.minimap.hide == true
    db.profile.minimap.angle = ns.Number(db.profile.minimap.angle) and db.profile.minimap.angle % 360 or 225
    db.profile.locked = db.locked
    return db
end

local readyCallbacks = {}
function ns:On(event, callback)
    if event == "READY" then readyCallbacks[#readyCallbacks + 1] = callback end
end
function ns:IsFinite(value) return ns.Number(value) end
ns.UI = { SetLocked = function(_, value) ns.SetLocked(value) end }
ns.Options = { Toggle = function() ns.OpenSettings() end }

function Drpulse_OnCompartmentClick()
    if ns.OpenSettings then ns.OpenSettings() end
end

function ns.StartDrpulseIntegration()
    ns.OnSettingChanged(function(key)
        if key == "locked" then ns.db.profile.locked = ns.db.locked end
    end)
    for _, callback in ipairs(readyCallbacks) do callback() end
    ns.Print("v" .. ns.VERSION .. " ready. /drpulse for settings, /drpulse status for diagnostics.")
end
