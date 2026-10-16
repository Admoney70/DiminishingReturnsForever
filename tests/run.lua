-- Usage: lua5.1 tests/run.lua   (from the repository root)
-- Friendly DR tracking against a small WoW API mock.
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

local passed, failed = 0, 0
local function test(name, fn)
	local before = #M.errors
	local ok, err = pcall(fn)
	if ok and #M.errors > before then
		ok, err = false, "game error: " .. M.errors[before + 1]
	end
	if ok then passed = passed + 1 else failed = failed + 1; io.write("FAIL ", name, ": ", tostring(err), "\n") end
end
local function eq(a, b, msg)
	if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local ADDON = "Drpulse"
local ns = {}
M.units.party1 = { name = "Healer", guid = "Player-2", class = "PRIEST" }
M.LoadToc(ADDON .. ".toc", ADDON, ns)
M.Fire("ADDON_LOADED", ADDON)
M.loggedIn = true
M.Fire("PLAYER_LOGIN")
M.Fire("PLAYER_ENTERING_WORLD", true, false)
M.Advance(1)

local HOJ, POLY, ROOTS = 853, 118, 339

-- The friendly display's shown rows: { name = ..., icons = n, icon list }.
local function Rows()
	local out = {}
	local display = ns.friendlyDisplay
	if not display:IsShown() then return out end
	for _, row in ipairs(display._children) do
		if row ~= display.strip and row:IsShown() and row.name then
			local icons = {}
			for _, icon in ipairs(row.icons._children) do
				if icon:IsShown() then icons[#icons + 1] = icon end
			end
			out[#out + 1] = { name = row.name:GetText(), icons = icons }
		end
	end
	return out
end
local function RowFor(name)
	for _, row in ipairs(Rows()) do if row.name == name then return row end end
end

test("loads and watches you and your party", function()
	eq(#M.errors, 0, "errors while loading")
	eq(ns.db.friendly, true, "on by default")
	eq(ns.WatchedUnits().player ~= nil, true, "player watched")
	eq(ns.WatchedUnits().party1 ~= nil, true, "party1 watched")
	eq(ns.WatchedUnits().party2, nil, "empty party slot")
end)

test("nothing shows while nobody has DR", function()
	eq(#Rows(), 0)
	eq(ns.friendlyDisplay:IsShown(), false)
end)

test("a stun on a party member shows in their row", function()
	M.AddAura("party1", HOJ, 6, 101)
	M.Advance(0.5)
	local row = RowFor("Healer")
	assert(row, "Healer row")
	eq(#row.icons, 1, "icons")
	eq(row.icons[1].entry.category, "Stun")
	eq(row.icons[1].entry.count, 1)
	eq(row.icons[1].entry.confirmed, true)
end)

test("the DR window runs on after the stun ends, then the row goes", function()
	M.Advance(3)
	M.RemoveAura("party1", HOJ)
	M.Advance(0.5)
	local row = RowFor("Healer")
	assert(row, "still shown while the window runs")
	local e = row.icons[1].entry
	eq(e.active, false, "stun over")
	assert(math.abs(e.remaining - (ns.db.resetTime - 0.5)) < 0.3, "reset window " .. e.remaining)
	M.Advance(ns.db.resetTime + 1)
	eq(RowFor("Healer"), nil, "gone after reset")
end)

test("repeat CC moves the stage on", function()
	M.AddAura("party1", HOJ, 6, 102)
	M.Advance(0.5)
	M.RemoveAura("party1", HOJ)
	M.Advance(1)
	M.AddAura("party1", HOJ, 3, 103)
	M.Advance(0.5)
	eq(RowFor("Healer").icons[1].entry.count, 2)
	M.RemoveAura("party1", HOJ)
	M.Advance(30)
end)

test("your own loss of control shows in your row", function()
	M.loss = { { locType = "STUN_MECHANIC", spellID = HOJ, startTime = M.now, duration = 5,
		auraInstanceID = 7, displayType = 2, priority = 1 } }
	M.Fire("LOSS_OF_CONTROL_ADDED", "player", 1)
	M.Advance(0.2)
	local row = RowFor("You")
	assert(row, "You row")
	eq(row.icons[1].entry.category, "Stun")
	eq(row.icons[1].entry.source, "loss")
end)

test("the loss-of-control effect ending starts your reset window", function()
	M.Advance(4)
	M.loss = {}
	M.Fire("LOSS_OF_CONTROL_UPDATE", "player")
	M.Advance(0.2)
	local e = RowFor("You").icons[1].entry
	eq(e.active, false)
	M.Advance(30)
	eq(RowFor("You"), nil)
end)

test("an effect type with one DR category counts without a known spell", function()
	M.loss = { { locType = "ROOT", spellID = 999999, startTime = M.now, duration = 4, displayType = 2, priority = 1 } }
	M.Fire("LOSS_OF_CONTROL_ADDED", "player", 1)
	M.Advance(0.2)
	eq(RowFor("You").icons[1].entry.category, "Root")
	M.loss = {}
	M.Fire("LOSS_OF_CONTROL_UPDATE", "player")
	M.Advance(30)
end)

test("an ambiguous effect type without a known spell is skipped", function()
	M.loss = { { locType = "FEAR", spellID = 999998, startTime = M.now, duration = 4, displayType = 2, priority = 1 } }
	M.Fire("LOSS_OF_CONTROL_ADDED", "player", 1)
	M.Advance(0.2)
	eq(RowFor("You"), nil)
	M.loss = {}
	M.Fire("LOSS_OF_CONTROL_UPDATE", "player")
end)

test("secret data is skipped without errors", function()
	M.loss = { M.Secret() }
	M.Fire("LOSS_OF_CONTROL_ADDED", "player", 1)
	M.secretAuras[POLY] = true
	ns.InvalidateReadable()
	M.AddAura("party1", POLY, 6, 104)
	M.Advance(0.5)
	eq(#Rows(), 0)
	M.loss = {}
	M.RemoveAura("party1", POLY)
	M.secretAuras[POLY] = nil
	ns.InvalidateReadable()
end)

test("a category set to Never is hidden", function()
	ns.SetCategoryMode("Root", "never")
	M.AddAura("party1", ROOTS, 6, 105)
	M.Advance(0.5)
	eq(RowFor("Healer"), nil)
	ns.SetCategoryMode("Root", "auto")
	M.Advance(0.5)
	assert(RowFor("Healer"), "shown again on Auto")
	M.RemoveAura("party1", ROOTS)
	M.Advance(30)
end)

-- The target display's shown icons.
local function TargetIcons()
	local out = {}
	if not ns.targetDisplay:IsShown() then return out end
	for _, icon in ipairs(ns.targetDisplay.row._children) do
		if icon:IsShown() then out[#out + 1] = icon end
	end
	return out
end

test("a targeted party member's DR shows in their row and on the target display, counted once", function()
	M.units.target = M.units.party1
	M.Fire("PLAYER_TARGET_CHANGED")
	M.auras.target = M.auras.party1
	M.AddAura("party1", HOJ, 6, 106)
	M.Fire("UNIT_AURA", "target")
	M.Advance(0.5)
	eq(#RowFor("Healer").icons, 1, "friendly row")
	local icons = TargetIcons()
	eq(#icons, 1, "target display")
	eq(icons[1].entry.count, 1, "one application, not two")
	M.RemoveAura("party1", HOJ)
	M.Fire("UNIT_AURA", "target")
	M.auras.target = nil
	M.units.target = nil
	M.Fire("PLAYER_TARGET_CHANGED")
	M.Advance(30)
end)

test("watching a duel: a friendly player you target shows on the target display", function()
	M.units.duelist = { name = "Duelist", guid = "Player-20", enemy = false }
	M.units.target = M.units.duelist
	M.Fire("PLAYER_TARGET_CHANGED")
	-- Polymorph isn't the test character's own CC; a friendly player's DR
	-- shows whatever Only CC I can apply says.
	M.AddAura("target", POLY, 6, 120)
	M.Advance(0.5)
	local icons = TargetIcons()
	eq(#icons, 1, "target display")
	eq(icons[1].entry.category, "Incapacitate")
	eq(#Rows(), 0, "not a party row")
	M.RemoveAura("target", POLY)
	M.Advance(1)
	M.AddAura("target", POLY, 3, 121)
	M.Advance(0.5)
	eq(TargetIcons()[1].entry.count, 2, "second application")
	M.RemoveAura("target", POLY)
end)

test("the duelist's DR is kept when you look away and back", function()
	M.units.target = nil
	M.Fire("PLAYER_TARGET_CHANGED")
	M.Advance(2)
	eq(#TargetIcons(), 0, "no target")
	M.units.target = M.units.duelist
	M.Fire("PLAYER_TARGET_CHANGED")
	M.Advance(0.5)
	eq(TargetIcons()[1].entry.count, 2, "still tracked")
	M.Advance(30)
	eq(#TargetIcons(), 0, "reset")
	M.units.target = nil
	M.Fire("PLAYER_TARGET_CHANGED")
end)

test("a duelist on a friendly nameplate gets icons on the plate", function()
	M.units.nameplate1 = M.units.duelist
	local plate = M.New("Frame", UIParent)
	M.plates = { nameplate1 = plate }
	M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	M.AddAura("nameplate1", HOJ, 6, 122)
	M.Advance(0.5)
	local row
	for _, child in ipairs(plate._children) do if child:IsShown() then row = child end end
	assert(row, "plate row")
	eq(row.icons[1].entry.category, "Stun")
	M.RemoveAura("nameplate1", HOJ)
	M.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	M.units.nameplate1 = nil
	M.Advance(30)
end)

test("friendly players are not tracked with friendly tracking off", function()
	ns.Set("friendly", false)
	M.units.target = M.units.duelist
	M.Fire("PLAYER_TARGET_CHANGED")
	M.AddAura("target", HOJ, 6, 123)
	M.Advance(0.5)
	eq(#TargetIcons(), 0)
	M.RemoveAura("target", HOJ)
	M.units.target = nil
	M.Fire("PLAYER_TARGET_CHANGED")
	ns.Set("friendly", true)
	M.Advance(30)
end)

test("enemy tracking still goes to the target display only", function()
	-- Polymorph isn't the test character's own CC; show every category.
	ns.Set("filter", "all")
	M.units.arena1 = { name = "Enemy", guid = "Player-9", enemy = true }
	M.units.target = M.units.arena1
	M.Fire("PLAYER_TARGET_CHANGED")
	M.AddAura("target", POLY, 6, 107)
	M.Advance(0.5)
	eq(ns.targetDisplay:IsShown(), true, "target display")
	eq(#Rows(), 0, "no friendly rows")
	M.RemoveAura("target", POLY)
	ns.Set("filter", "mine")
	M.units.target = nil
	M.Fire("PLAYER_TARGET_CHANGED")
	M.Advance(30)
end)

test("party changes are followed", function()
	M.units.party2 = { name = "Rogue", guid = "Player-3", class = "ROGUE" }
	M.Fire("GROUP_ROSTER_UPDATE")
	eq(ns.WatchedUnits().party2 ~= nil, true, "party2 watched")
	M.units.party2 = nil
	M.Fire("GROUP_ROSTER_UPDATE")
	eq(ns.WatchedUnits().party2, nil, "party2 dropped")
end)

test("Include yourself off drops your row", function()
	ns.Set("friendlyPlayer", false)
	eq(ns.WatchedUnits().player, nil)
	M.loss = { { locType = "STUN_MECHANIC", spellID = HOJ, startTime = M.now, duration = 5, displayType = 2, priority = 1 } }
	M.Fire("LOSS_OF_CONTROL_ADDED", "player", 1)
	M.Advance(0.2)
	eq(RowFor("You"), nil)
	M.loss = {}
	ns.Set("friendlyPlayer", true)
	eq(ns.WatchedUnits().player ~= nil, true)
end)

test("unlocked, the display shows its strip and a sample row", function()
	ns.SetLocked(false)
	M.Advance(0.2)
	eq(ns.friendlyDisplay:IsShown(), true)
	eq(ns.friendlyDisplay.strip:IsShown(), true)
	eq(#Rows(), 1, "sample row")
	ns.SetLocked(true)
	M.Advance(0.2)
	eq(ns.friendlyDisplay:IsShown(), false)
end)

test("/drpulse friendly turns it off and on", function()
	SlashCmdList.DRPULSE("friendly")
	eq(ns.db.friendly, false)
	eq(ns.WatchedUnits().party1, nil, "party1 dropped")
	M.AddAura("party1", HOJ, 6, 108)
	M.Advance(0.5)
	eq(#Rows(), 0)
	M.RemoveAura("party1", HOJ)
	SlashCmdList.DRPULSE("friendly")
	eq(ns.db.friendly, true)
	eq(ns.WatchedUnits().party1 ~= nil, true, "party1 watched again")
end)

test("saved settings with friendly values load; bad ones are rejected", function()
	local saved = ns.LoadSettings(nil)
	saved.friendlySize = 40
	eq(ns.LoadSettings(saved) ~= nil, true, "valid")
	saved.friendlySize = 400
	local db, problem = ns.LoadSettings(saved)
	eq(db, nil)
	eq(problem, "invalid setting friendlySize")
end)

test("/drpulse status reports friendly tracking", function()
	M.printed = {}
	SlashCmdList.DRPULSE("status")
	local found = false
	for _, line in ipairs(M.printed) do if line:find("Friendly DR on; watching player, party1") then found = true end end
	eq(found, true)
end)

test("no game errors were raised", function()
	eq(#M.errors, 0, M.errors[1])
end)

io.write(passed, " passed, ", failed, " failed\n")
os.exit(failed == 0 and 0 or 1)
