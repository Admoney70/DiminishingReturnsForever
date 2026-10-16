-- Usage: lua5.1 tests/run.lua   (from the repository root)
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

-- Load the add-on in TOC order, as a WoW Forever client would: no
-- CompactArenaFrame code, so no Blizzard arena DR trays.
local ADDON = "DiminishingReturnsForever"
local ns = {}
M.LoadToc(ADDON .. ".toc", ADDON, ns)
M.Fire("ADDON_LOADED", ADDON)
M.loggedIn = true
M.Fire("PLAYER_LOGIN")
M.Fire("PLAYER_ENTERING_WORLD", true, false)
M.Advance(1)

local EVENT = "UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED"
local STUN, ROOT = Enum.SpellDiminishCategory.Stun, Enum.SpellDiminishCategory.Root

-- The DR icons currently drawn on a unit frame, in row order. Each entry has
-- the slot frame, its icon texture, its cooldown and its red border.
local function Icons(anchor)
	local out = {}
	for _, root in ipairs(M.frames) do
		local p = root._point
		if root:IsShown() and p and p[2] == anchor and root._parent == UIParent then
			for _, slot in ipairs(root._children) do
				if slot:IsShown() then
					local icon = slot._children[1]
					local cd, overlay
					for _, c in ipairs(icon._children) do
						if c._type == "Cooldown" then cd = c end
						if c._children[3] then overlay = c end
					end
					out[#out + 1] = {
						frame = slot, tex = icon._regions[1], cd = cd,
						red = overlay and overlay._children[2], green = overlay and overlay._children[1],
					}
				end
			end
		end
	end
	return out
end

local function DR(unit, category, fields)
	local state = { category = category, startTime = 0, duration = 0, showCountdown = false, isImmune = false }
	for k, v in pairs(fields or {}) do state[k] = v end
	M.Fire(EVENT, unit, state)
end

local function EnterArena()
	M.instanceType = "arena"
	M.units.arena1 = { name = "Enemy-One", guid = "Player-11", enemy = true }
	M.units.arena2 = { name = "Enemy-Two", guid = "Player-12", enemy = true }
	M.units.target = M.units.arena1
	M.Fire("PLAYER_ENTERING_WORLD", false, false)
	M.Fire("PLAYER_TARGET_CHANGED")
	M.Advance(0.3)
end

test("loads on a client without Blizzard arena frames", function()
	eq(#M.errors, 0, "errors while loading")
	eq(ns.NativeTray:IsNeeded(), true, "native trays")
	eq(M.cvars.spellDiminishPVPEnemiesEnabled, "1", "DR CVar")
	assert(SlashCmdList.ACECONSOLE_DR, "/dr registered")
end)

test("uses Blizzard's trays where the client has them", function()
	CompactArenaFrameMixin = {}
	eq(ns.NativeTray:IsNeeded(), false)
	CompactArenaFrameMixin = nil
end)

test("one tray per arena unit listens for DR updates", function()
	for i = 1, 5 do
		local tray = ns.NativeTray:Get(i)
		eq(tray:IsEventRegistered(EVENT), true, "arena" .. i)
		eq(tray._unitEvents[EVENT][1], "arena" .. i)
	end
end)

test("nothing shows outside an arena", function()
	DR("arena1", STUN)
	M.Advance(0.3)
	eq(#Icons(TargetFrame), 0)
end)

test("a stun on the targeted enemy shows on the target frame", function()
	EnterArena()
	DR("arena1", STUN)
	M.Advance(0.3)
	local icons = Icons(TargetFrame)
	eq(#icons, 1, "icons")
	eq(icons[1].tex:GetTexture(), 132298, "stun icon")
	eq(#Icons(FocusFrame), 0, "focus frame")
end)

test("the DR window starts when the stun ends", function()
	M.Advance(3)
	DR("arena1", STUN, { startTime = M.now, duration = 20, showCountdown = true })
	M.Advance(0.3)
	local icon = Icons(TargetFrame)[1]
	assert(icon, "icon still shown")
	eq(icon.cd._cdDuration, 20, "reset window")
	eq(icon.red._alpha, 0, "first application is not red")
end)

test("a second stun turns the icon red", function()
	DR("arena1", STUN, { isImmune = true })
	M.Advance(0.3)
	local icon = Icons(TargetFrame)[1]
	eq(icon.red._alpha, 1, "red border")
	eq(icon.green._alpha, 0, "green border")
end)

test("the icon goes away once the window has run out", function()
	DR("arena1", STUN, { startTime = M.now, duration = 20, showCountdown = true, isImmune = true })
	M.Advance(25)
	eq(#Icons(TargetFrame), 0)
end)

test("each category gets its own icon", function()
	DR("arena1", ROOT)
	DR("arena1", STUN)
	M.Advance(0.3)
	local icons = Icons(TargetFrame)
	eq(#icons, 2)
	local seen = {}
	for _, icon in ipairs(icons) do seen[icon.tex:GetTexture()] = true end
	eq(seen[136100], true, "root")
	eq(seen[132298], true, "stun")
	M.Advance(30)
end)

test("secret times and flags are handled without errors", function()
	DR("arena1", STUN, {
		startTime = M.Secret(), duration = M.Secret(), showCountdown = M.Secret(), isImmune = M.Secret(),
	})
	M.Advance(0.3)
	local icon = Icons(TargetFrame)[1]
	assert(icon, "icon shown")
	eq(icon.cd._cdDuration, 20, "window timed locally")
	assert(issecretvalue(icon.red._alphaFrom), "red border driven by the secret flag")
	M.Advance(30)
	eq(#Icons(TargetFrame), 0, "expired")
end)

test("a secret category is skipped", function()
	DR("arena1", M.Secret())
	M.Advance(0.3)
	eq(#Icons(TargetFrame), 0)
end)

test("DR on another enemy follows them to the focus frame", function()
	M.units.focus = M.units.arena2
	M.Fire("PLAYER_FOCUS_CHANGED")
	DR("arena2", ROOT)
	M.Advance(0.3)
	eq(#Icons(FocusFrame), 1, "focus")
	eq(#Icons(TargetFrame), 0, "target")
	M.Advance(30)
end)

test("DR on an enemy you aren't targeting is waiting when you target them", function()
	M.units.focus = nil
	M.Fire("PLAYER_FOCUS_CHANGED")
	DR("arena2", STUN, { startTime = M.now, duration = 20, showCountdown = true })
	M.Advance(0.3)
	eq(#Icons(TargetFrame), 0, "not targeted yet")
	M.units.target = M.units.arena2
	M.Fire("PLAYER_TARGET_CHANGED")
	M.Advance(0.3)
	eq(#Icons(TargetFrame), 1, "after targeting")
	M.Advance(30)
end)

test("leaving the arena clears everything", function()
	DR("arena2", STUN)
	M.Advance(0.3)
	M.instanceType = "none"
	M.Fire("PLAYER_ENTERING_WORLD", false, false)
	M.Advance(0.3)
	eq(#Icons(TargetFrame), 0)
	for _, item in pairs(ns.NativeTray:Get(2).items) do eq(item:IsShown(), false, "tray item") end
end)

test("/dr debug reports which trays are in use", function()
	M.printed = {}
	SlashCmdList.ACECONSOLE_DR("debug")
	local found = false
	for _, line in ipairs(M.printed) do
		if line:find("own %(no Blizzard arena frames%)") then found = true end
	end
	eq(found, true)
end)

test("no game errors were raised", function()
	eq(#M.errors, 0, M.errors[1])
end)

io.write(passed, " passed, ", failed, " failed\n")
os.exit(failed == 0 and 0 or 1)
