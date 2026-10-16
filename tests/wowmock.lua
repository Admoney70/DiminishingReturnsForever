-- Minimal World of Warcraft API mock: just enough to load the add-on and
-- watch what it does with DR events. Not a general-purpose emulator.
--
-- Frame methods it does not know are accepted and do nothing, so the options
-- UI can be built without modelling every widget.

local M = {}

unpack = unpack or table.unpack
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
string.trim = strtrim -- luacheck: ignore 142
strsplit = function(sep, s)
	local out = {}
	for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
	return unpack(out)
end
strmatch, format, tinsert, tremove = string.match, string.format, table.insert, table.remove
floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
YES, NO = "Yes", "No"
UNKNOWNOBJECT = "Unknown"
SlashCmdList, hash_SlashCmdList = {}, {}
StaticPopupDialogs = {}
function StaticPopup_Show() end

----------------------------------------------------------------------
-- Time, timers
----------------------------------------------------------------------

M.now = 1000
function GetTime() return M.now end
function GetTimePreciseSec() return M.now end

M.timers = {}
local function NewTimer(delay, fn, repeating)
	local t = { at = M.now + delay, fn = fn, every = repeating and delay or nil }
	function t:Cancel() self.cancelled = true end
	function t:IsCancelled() return self.cancelled end
	M.timers[#M.timers + 1] = t
	return t
end
C_Timer = {
	After = function(d, f) NewTimer(d, f) end,
	NewTimer = function(d, f) return NewTimer(d, f) end,
	NewTicker = function(d, f) return NewTimer(d, f, true) end,
}

----------------------------------------------------------------------
-- Secret values
----------------------------------------------------------------------

-- An opaque stand-in that errors like the real thing when add-on code tries
-- to read it.
local function secretError() error("attempt to use a secret value", 2) end
local SecretMT = {
	__lt = secretError, __le = secretError, __concat = secretError,
	__add = secretError, __sub = secretError, __mul = secretError, __div = secretError,
	__unm = secretError, __len = secretError, __index = secretError, __newindex = secretError,
	__tostring = function() return "<secret>" end,
}
function M.Secret() return setmetatable({}, SecretMT) end
function issecretvalue(v) return getmetatable(v) == SecretMT end
local function refuseSecret(...)
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then error("secret argument passed to a function that refuses them", 3) end
	end
end

----------------------------------------------------------------------
-- Errors
----------------------------------------------------------------------

M.errors = {}
function geterrorhandler() return function(e) M.errors[#M.errors + 1] = tostring(e) end end
function seterrorhandler() end
function securecallfunction(f, ...) return f(...) end
-- WoW's xpcall passes extra arguments on to the function; Lua 5.1's doesn't.
local xpcall51 = xpcall
xpcall = function(f, handler, ...)
	local args, n = { ... }, select("#", ...)
	return xpcall51(function() return f(unpack(args, 1, n)) end, handler)
end
M.printed = {}
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	M.printed[#M.printed + 1] = table.concat(parts, " ")
end

----------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------

M.frames = {}
M.eventFrames = {}

local Frame = {}
local function noop() end
local known = {}
for _, name in ipairs(require("widgetapi")) do known[name] = true end
-- Methods the client has but the mock doesn't model do nothing; anything
-- else is nil, as on a real frame.
local FrameMT = { __index = function(_, k) return Frame[k] or (known[k] and noop) or nil end }

local function New(kind, parent)
	local f = setmetatable({
		_type = kind, _parent = parent, _children = {}, _scripts = {},
		_shown = true, _alpha = 1, _w = 0, _h = 0, _events = {}, _unitEvents = {},
	}, FrameMT)
	if parent and kind ~= "Texture" and kind ~= "FontString" then
		parent._children[#parent._children + 1] = f
	end
	return f
end
M.New = New

function Frame:GetObjectType() return self._type end
function Frame:IsObjectType(t) return self._type == t or t == "Frame" and self._type ~= "Texture" and self._type ~= "FontString" end
function Frame:IsForbidden() return false end
function Frame:GetParent() return self._parent end
function Frame:SetParent(p)
	if self._parent and self._parent._children then
		for i, c in ipairs(self._parent._children) do
			if c == self then table.remove(self._parent._children, i) break end
		end
	end
	self._parent = p
	if p and p._children then p._children[#p._children + 1] = self end
end
function Frame:GetChildren() return unpack(self._children) end
function Frame:GetRegions() return unpack(self._regions or {}) end
function Frame:GetName() return self._name end

local function fire(self, script, ...)
	local f = self._scripts[script]
	if f then f(self, ...) end
end
function Frame:Show()
	local was = self._shown
	self._shown = true
	if not was then fire(self, "OnShow") end
end
function Frame:Hide()
	local was = self._shown
	self._shown = false
	if was then fire(self, "OnHide") end
end
function Frame:SetShown(v)
	refuseSecret(v)
	if v then self:Show() else self:Hide() end
end
function Frame:IsShown() return self._shown end
function Frame:IsVisible()
	local f = self
	while f do
		if not f._shown then return false end
		f = f._parent
	end
	return true
end
function Frame:SetAlpha(a) refuseSecret(a) self._alpha = a end
function Frame:GetAlpha() return self._alpha end
-- Accepts secrets, like the real one.
function Frame:SetAlphaFromBoolean(v, yes, no)
	self._alphaFrom = v
	if not issecretvalue(v) then self._alpha = v and (yes or 1) or (no or 0) end
end
function Frame:SetSize(w, h) self._w, self._h = w, h end
function Frame:SetWidth(w) self._w = w end
function Frame:SetHeight(h) self._h = h end
function Frame:GetWidth() return self._w end
function Frame:GetHeight() return self._h end
function Frame:GetSize() return self._w, self._h end
function Frame:SetPoint(...) self._point = { ... } end
function Frame:ClearAllPoints() self._point = nil end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetScale() return 1 end
function Frame:GetFrameLevel() return self._level or 0 end
function Frame:SetFrameLevel(l) self._level = l end
function Frame:GetFrameStrata() return self._strata or "MEDIUM" end
function Frame:SetFrameStrata(s) self._strata = s end
function Frame:SetScript(s, f) self._scripts[s] = f end
function Frame:GetScript(s) return self._scripts[s] end
function Frame:HookScript(s, f)
	local old = self._scripts[s]
	self._scripts[s] = function(...) if old then old(...) end f(...) end
end
function Frame:RegisterEvent(e)
	self._events[e] = true
	M.eventFrames[self] = true
end
function Frame:RegisterUnitEvent(e, ...)
	self._events[e] = true
	self._unitEvents[e] = { ... }
	M.eventFrames[self] = true
end
function Frame:UnregisterEvent(e) self._events[e] = nil; self._unitEvents[e] = nil end
function Frame:UnregisterAllEvents() self._events = {}; self._unitEvents = {} end
function Frame:IsEventRegistered(e) return self._events[e] or false end
function Frame:CreateTexture(_, layer)
	local t = New("Texture", self); t._layer = layer
	self._regions = self._regions or {}
	self._regions[#self._regions + 1] = t
	return t
end
function Frame:CreateFontString(_, layer)
	local t = New("FontString", self); t._layer = layer
	self._regions = self._regions or {}
	self._regions[#self._regions + 1] = t
	return t
end

-- textures
function Frame:SetTexture(t) refuseSecret(t) self._texture = t; self._atlas = nil end
function Frame:GetTexture() return self._texture end
function Frame:SetAtlas(a) self._atlas = a; self._texture = nil end
function Frame:GetAtlas() return self._atlas end
function Frame:SetDrawLayer(l) self._layer = l end
function Frame:GetDrawLayer() return self._layer end
-- font strings
function Frame:SetFont(file, size, flags) self._font = { file, size, flags } end
function Frame:GetFont()
	if not self._font then return nil end
	return unpack(self._font)
end
function Frame:SetText(t) self._text = t end
function Frame:GetText() return self._text end
function Frame:GetStringWidth() return 10 end
function Frame:GetUnboundedStringWidth() return 10 end
function Frame:GetLineHeight() return 12 end
function Frame:GetStringHeight() return 10 end
-- cooldowns: SetCooldown refuses secrets from add-on code
function Frame:SetCooldown(start, duration)
	refuseSecret(start, duration)
	self._cdStart, self._cdDuration = start, duration
end
function Frame:Clear() self._cdStart, self._cdDuration = nil, nil end
function Frame:GetCooldownTimes()
	return (self._cdStart or 0) * 1000, (self._cdDuration or 0) * 1000
end
function Frame:GetCountdownFontString()
	if not self._countdown then
		self._countdown = New("FontString", self)
		self._countdown._font = { STANDARD_TEXT_FONT, 12, "OUTLINE" }
	end
	return self._countdown
end
-- widgets used by the options UI
function Frame:GetValue() return self._value or 0 end
function Frame:SetValue(v) self._value = v end
function Frame:GetMinMaxValues() return 0, 1 end
function Frame:GetChecked() return self._checked end
function Frame:SetChecked(v) self._checked = v end
function Frame:IsEnabled() return true end
function Frame:GetNumPoints() return self._point and 1 or 0 end
function Frame:GetCenter() return 0, 0 end
function Frame:GetLeft() return 0 end
function Frame:GetRight() return 0 end
function Frame:GetTop() return 0 end
function Frame:GetBottom() return 0 end
function Frame:GetVerticalScrollRange() return 0 end
function Frame:SetThumbTexture() self._thumb = self._thumb or New("Texture", self) end
function Frame:GetThumbTexture() self._thumb = self._thumb or New("Texture", self); return self._thumb end
function Frame:IsOwned() return false end
function Frame:IsMouseOver() return false end
function Frame:GetFontString()
	self._fs = self._fs or New("FontString", self)
	return self._fs
end

local templates = {}
-- What CooldownFrameTemplate etc. would add.
function templates.CooldownFrameTemplate(f) f._type = "Cooldown" end
function templates.BackdropTemplate(f)
	f.SetBackdrop, f.SetBackdropColor, f.SetBackdropBorderColor = noop, noop, noop
	f.ApplyBackdrop = noop
end
function templates.WowStyle1DropdownTemplate(f)
	function f:SetupMenu(gen) self._gen = gen end
	f.Update, f.GenerateMenu, f.SetDefaultText, f.OverrideText = noop, noop, noop, noop
end
function templates.InputBoxTemplate() end
function templates.UICheckButtonTemplate(f) f.Text = f:CreateFontString() end
function templates.UIPanelButtonTemplate(f) f.Text = f:CreateFontString() end
function templates.OptionsSliderTemplate(f)
	f.Text = f:CreateFontString(); f.Low = f:CreateFontString(); f.High = f:CreateFontString()
end

function CreateFrame(kind, name, parent, template)
	local f = New(kind, parent)
	f._name = name
	if name then rawset(_G, name, f) end
	-- CreateFrame("Cooldown", ...) makes a cooldown without a template too.
	for t in tostring(template or ""):gmatch("[%w_]+") do
		if templates[t] then templates[t](f) end
	end
	M.frames[#M.frames + 1] = f
	return f
end

UIParent = New("Frame")
UIParent._name = "UIParent"
TargetFrame = New("Frame", UIParent)
FocusFrame = New("Frame", UIParent)
GameTooltip = New("GameTooltip", UIParent)
DEFAULT_CHAT_FRAME = New("Frame", UIParent)

-- Font objects (GameFontNormal, ...) are made on first use.
setmetatable(_G, { __index = function(g, k)
	if type(k) == "string" and k:match("Font") and not k:match("^Create") then
		local f = New("Font")
		f._font = { STANDARD_TEXT_FONT, 12, "" }
		rawset(g, k, f)
		return f
	end
end })

function hooksecurefunc(tbl, name, hook)
	if type(tbl) == "string" then tbl, name, hook = _G, tbl, name end
	local orig = tbl[name]
	assert(type(orig) == "function", "hooksecurefunc: no function " .. tostring(name))
	rawset(tbl, name, function(...)
		local a, b, c, d = orig(...)
		hook(...)
		return a, b, c, d
	end)
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

function M.Fire(event, ...)
	for f in pairs(M.eventFrames) do
		if f._events[event] then
			local units = f._unitEvents[event]
			local unit = ...
			local match = not units
			if units then
				for _, u in ipairs(units) do if u == unit then match = true end end
			end
			local h = f._scripts.OnEvent
			if match and h then
				local ok, err = pcall(h, f, event, ...)
				if not ok then M.errors[#M.errors + 1] = event .. ": " .. tostring(err) end
			end
		end
	end
end

-- Runs OnUpdate scripts of visible frames, as one rendered frame would.
local function RunOnUpdate(delta)
	for _, f in ipairs(M.frames) do
		local h = f._scripts.OnUpdate
		if h and f:IsVisible() then
			local ok, err = pcall(h, f, delta)
			if not ok then M.errors[#M.errors + 1] = "OnUpdate: " .. tostring(err) end
		end
	end
end

-- Advances the clock in rendered frames of at most 0.1 s, running timers,
-- cooldown completions and OnUpdate scripts on the way.
function M.Advance(seconds)
	while seconds > 0.1 + 1e-9 do
		M.Step(0.1)
		seconds = seconds - 0.1
	end
	M.Step(seconds)
end

function M.Step(seconds)
	local start = M.now
	local target = M.now + seconds
	while true do
		local nextAt, nextT = target, nil
		for _, t in ipairs(M.timers) do
			if not t.cancelled and t.at <= nextAt then nextAt, nextT = t.at, t end
		end
		M.now = nextAt
		-- cooldown completions
		for _, f in ipairs(M.frames) do
			if f._type == "Cooldown" and f._cdStart and f._cdDuration and f._cdDuration > 0
				and f._cdStart + f._cdDuration <= M.now and f:IsVisible() then
				f._cdStart, f._cdDuration = nil, nil
				local h = f._scripts.OnCooldownDone
				if h then
					local ok, err = pcall(h, f)
					if not ok then M.errors[#M.errors + 1] = "OnCooldownDone: " .. tostring(err) end
				end
			end
		end
		if not nextT then
			RunOnUpdate(M.now - start)
			break
		end
		if nextT.every then nextT.at = nextT.at + nextT.every else nextT.cancelled = true end
		local ok, err = pcall(nextT.fn, nextT)
		if not ok then M.errors[#M.errors + 1] = "timer: " .. tostring(err) end
	end
	local live = {}
	for _, t in ipairs(M.timers) do if not t.cancelled then live[#live + 1] = t end end
	M.timers = live
end

----------------------------------------------------------------------
-- Game state
----------------------------------------------------------------------

M.instanceType = "none"
function IsInInstance() return M.instanceType ~= "none", M.instanceType end
function IsLoggedIn() return M.loggedIn end
function InCombatLockdown() return false end
function GetLocale() return "enUS" end
function GetRealmName() return "Realm" end
function GetCurrentRegion() return 1 end
function UnitClass(unit)
	local x = unit and M.units and M.units[unit]
	if x and x.class then return x.class, x.class, 1 end
	return "Rogue", "ROGUE", 4
end
function UnitRace() return "Human", "Human" end
function UnitFactionGroup() return "Alliance", "Alliance" end

-- units[token] = { name = ..., guid = ..., dead = bool }
M.units = { player = { name = "Tester", guid = "Player-1" } }
local function unit(u) return M.units[u] end
function UnitExists(u) return unit(u) ~= nil end
function UnitName(u) local x = unit(u); return x and x.name end
function UnitGUID(u) local x = unit(u); return x and x.guid end
function UnitIsUnit(a, b) local x, y = unit(a), unit(b); return x ~= nil and x == y end
function UnitIsDeadOrGhost(u) local x = unit(u); return x and x.dead or false end
function UnitCanAttack(_, u) local x = unit(u); return x and x.enemy or false end
function UnitIsPlayer(u) return unit(u) ~= nil end

M.cvars = {}
C_CVar = {
	GetCVar = function(k) return M.cvars[k] end,
	GetCVarBool = function(k) return M.cvars[k] == "1" end,
	SetCVar = function(k, v) M.cvars[k] = tostring(v) end,
}

C_AddOns = { GetAddOnMetadata = function() return nil end, IsAddOnLoaded = function() return false end }
C_NamePlate = { GetNamePlateForUnit = function() return nil end }
C_Spell = {
	GetSpellTexture = function(id) return 100000 + id end,
	GetSpellName = function(id) return "Spell" .. id end,
	GetSpellInfo = function(id) return { iconID = 100000 + id, name = "Spell" .. id } end,
}
C_LossOfControl = {
	GetActiveLossOfControlDataCountByUnit = function() return 0 end,
	GetActiveLossOfControlDataByUnit = function() return nil end,
}
PixelUtil = {
	SetPoint = function(f, ...) f:SetPoint(...) end,
	SetHeight = function(f, h) f:SetHeight(h) end,
	SetWidth = function(f, w) f:SetWidth(w) end,
	SetSize = function(f, w, h) f:SetSize(w, h) end,
}
UISpecialFrames = {}
MenuUtil = { CreateRadioMenu = function() end }
C_Traits = {}
C_ClassTalents = { GetActiveConfigID = function() return nil end }
C_Item = {
	IsItemDataCachedByID = function() return true end,
	RequestLoadItemDataByID = function() end,
	IsItemInRange = function() return false end,
}

Enum = {
	SpellDiminishCategory = {
		Root = 0, Taunt = 1, Stun = 2, AoEKnockback = 3, Incapacitate = 4, Disorient = 5, Silence = 6, Disarm = 7,
	},
	SpellDiminishRuleset = { None = 0, PvE = 1, PvP = 2 },
	PowerType = { Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4 },
	SpellBookSpellBank = { Player = 0, Pet = 1 },
}

M.diminishIcons = { [0] = 136100, [2] = 132298, [4] = 136071, [5] = 136183 }
M.untrackedPvP = { [1] = true }
C_SpellDiminish = {
	IsSystemSupported = function() return true end,
	GetSpellDiminishCategoryInfo = function(category)
		refuseSecret(category)
		return { category = category, name = "Category" .. category, icon = M.diminishIcons[category] }
	end,
	-- Like the real one: the answer is always secret to add-on code.
	ShouldTrackSpellDiminishCategory = function(category)
		refuseSecret(category)
		return M.Secret()
	end,
	GetAllSpellDiminishCategories = function() return {} end,
}

function canaccesstable(t) return not issecretvalue(t) end
function GetBuildInfo() return "1.60.1", "70245", "Oct 1 2026", 16001 end
function GetCursorPosition() return 0, 0 end
function IsMouseButtonDown() return false end
function IsShiftKeyDown() return false end
function GetMinimapShape() return "ROUND" end
Minimap = New("Frame", UIParent)

function CreateColor(r, g, b, a)
	return { r = r, g = g, b = b, a = a, GetRGB = function(c) return c.r, c.g, c.b end,
		GetRGBA = function(c) return c.r, c.g, c.b, c.a end }
end
C_ClassColor = { GetClassColor = function() return CreateColor(0.2, 0.6, 1, 1) end }
C_Texture = { GetAtlasInfo = function() return nil end }
C_SpellBook = { IsSpellKnown = function() return false end }
C_Item.GetItemCount = function() return 0 end
C_EventUtils = { IsEventValid = function() return true end }
C_NamePlate.GetNamePlates = function() return {} end

-- Which CC auras' data is secret (by spell ID); everything else is readable.
M.secretAuras = {}
C_Secrets = {
	HasSecretRestrictions = function() return true end,
	ShouldAurasBeSecret = function() return false end,
	ShouldSpellAuraBeSecret = function(id) return M.secretAuras[id] == true end,
}
-- auras[unit][spellID] = AuraData
M.auras = {}
C_UnitAuras = {
	GetUnitAuraBySpellID = function(unit, id)
		local list = M.auras[unit]
		return list and list[id]
	end,
}
function M.AddAura(unit, id, duration, instance)
	M.auras[unit] = M.auras[unit] or {}
	M.auras[unit][id] = { spellId = id, auraInstanceID = instance, duration = duration,
		expirationTime = M.now + duration, sourceUnit = "arena1" }
	M.Fire("UNIT_AURA", unit)
end
function M.RemoveAura(unit, id)
	if M.auras[unit] then M.auras[unit][id] = nil end
	M.Fire("UNIT_AURA", unit)
end
-- The player's loss-of-control effects, as LossOfControlData.
M.loss = {}
C_LossOfControl.GetActiveLossOfControlDataCountByUnit = function(unit)
	return unit == "player" and #M.loss or 0
end
C_LossOfControl.GetActiveLossOfControlDataByUnit = function(unit, index)
	return unit == "player" and M.loss[index] or nil
end

----------------------------------------------------------------------
-- Loading
----------------------------------------------------------------------

-- Loads every file listed in the .toc, Lua and the Ace XML wrappers alike.
function M.LoadToc(toc, addonName, ns)
	local function loadLua(path)
		local chunk = assert(loadfile(path))
		chunk(addonName, ns)
	end
	for line in io.lines(toc) do
		line = line:gsub("\r", "")
		if line ~= "" and not line:match("^#") then
			local path = line:gsub("\\", "/")
			if path:match("%.xml$") then
				local dir = path:match("^(.*)/") or "."
				for l in io.lines(path) do
					local file = l:match('<Script file="([^"]+)"')
					if file then loadLua(dir .. "/" .. file:gsub("\\", "/")) end
				end
			else
				loadLua(path)
			end
		end
	end
end

return M
