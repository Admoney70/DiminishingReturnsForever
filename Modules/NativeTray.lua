-- Modules/NativeTray.lua
-- Stand-in for Blizzard's arena DR trays on clients that never build them.
--
-- The Target/Focus module mirrors the SpellDiminishStatusTray that Blizzard
-- puts on each CompactArenaFrame member. WoW Forever (the "camelot" game
-- type) excludes CompactArenaFrame from its unit frames, so those trays never
-- exist there and the mirror has nothing to copy. The DR system itself is
-- present (C_SpellDiminish, UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED), so
-- this file builds one tray per arena index from our own frames, laid out
-- like Blizzard's tray items (Icon, Cooldown, ImmunityIndicator) and driven by
-- the same event. The mirror hooks them exactly as it hooks Blizzard's.
--
-- Only used when Blizzard's arena frame code is not loaded; on retail the
-- real trays are mirrored as before.

local _, ns = ...
local Util = ns.Util
if not Util then return end -- stale .toc; Core.lua already warned

local IsSecret = Util.IsSecret

local NativeTray = {}
ns.NativeTray = NativeTray

local EVENT          = "UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED"
local FALLBACK_ICON  = "Interface\\Icons\\INV_Misc_QuestionMark"
local DEFAULT_RESET  = 20

local trays = {}      -- [arena index] = tray frame
local onNewItem       -- function(item), set by Init

-- True when this client has no Blizzard arena frames to borrow trays from.
-- CompactArenaFrame itself is created lazily, so test for its code instead.
function NativeTray:IsNeeded()
  if _G.CompactArenaFrameMixin then return false end
  return C_SpellDiminish ~= nil and type(C_SpellDiminish.GetSpellDiminishCategoryInfo) == "function"
end

-- opts.onNewItem(item): called for each new item BEFORE it is first shown or
--   timed, so the mirror can hook it in time to see its very first DR.
-- opts.resetTime(): the DR window used when the event's times are secret.
function NativeTray:Init(opts)
  opts = opts or {}
  onNewItem = opts.onNewItem
  self.resetTime = opts.resetTime
end

local function ResetTime()
  local fn = NativeTray.resetTime
  local t = fn and fn()
  return (type(t) == "number" and t > 0) and t or DEFAULT_RESET
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Items
-- ─────────────────────────────────────────────────────────────────────────────

local function CreateItem(tray)
  local item = CreateFrame("Frame", nil, tray)
  item:SetSize(26, 26)
  item:EnableMouse(false)
  item:Hide()

  item.Icon = item:CreateTexture(nil, "OVERLAY")
  item.Icon:SetAllPoints()

  item.Cooldown = CreateFrame("Cooldown", nil, item, "CooldownFrameTemplate")
  item.Cooldown:SetAllPoints()
  item.Cooldown:SetReverse(true)

  -- The immunity flag may be a secret boolean, and the stock SetShown refuses
  -- secrets from add-on code. This is our own frame, so give it a SetShown
  -- that accepts one: the mirror hooks this method and drives its borders
  -- from the value with SetAlphaFromBoolean, which does take secrets.
  local ind = CreateFrame("Frame", nil, item)
  ind:SetAllPoints()
  ind:Hide()
  function ind:SetShown(shown)
    if IsSecret(shown) then return end
    if shown then self:Show() else self:Hide() end
  end
  item.ImmunityIndicator = ind

  -- Same lifetime as Blizzard's items: gone once the DR window has run out.
  item.Cooldown:SetScript("OnCooldownDone", function() item:Hide() end)
  return item
end

-- Mirrors SpellDiminishStatusTrayItemMixin:UpdateState without handing a
-- secret to any API that refuses one.
local function UpdateState(item, state)
  item.ImmunityIndicator:SetShown(state.isImmune)

  local start, duration, countdown = state.startTime, state.duration, state.showCountdown
  if IsSecret(start) or IsSecret(duration) or IsSecret(countdown) then
    -- SetCooldown rejects secret times from add-on code. Time the window
    -- locally instead, the way the mirror already does: every update re-arms
    -- it, and the update sent when the CC ends lands it on the reset time.
    item.Cooldown:SetCooldown(GetTime(), ResetTime())
  elseif countdown and type(start) == "number" and type(duration) == "number"
      and start > 0 and duration > 0 then
    item.Cooldown:SetCooldown(start, duration)
  else
    -- CC still running: the DR window starts when it ends.
    item.Cooldown:Clear()
  end
end

-- Blizzard's PvP tray leaves some categories out. Its answer can be secret,
-- in which case the category is shown rather than guessed away.
local function ShouldTrack(category)
  local ruleset = Enum and Enum.SpellDiminishRuleset and Enum.SpellDiminishRuleset.PvP
  if not (ruleset and C_SpellDiminish.ShouldTrackSpellDiminishCategory) then return true end
  local ok, tracked = pcall(C_SpellDiminish.ShouldTrackSpellDiminishCategory, category, ruleset)
  if not ok or IsSecret(tracked) then return true end
  return tracked ~= false
end

local function OnStateUpdated(tray, state)
  if type(state) ~= "table" then return end
  local category = state.category
  -- Without a readable category there is no telling which icon this is.
  if category == nil or IsSecret(category) then return end
  if not ShouldTrack(category) then return end

  local item = tray.items[category]
  if not item then
    local ok, info = pcall(C_SpellDiminish.GetSpellDiminishCategoryInfo, category)
    if not ok or type(info) ~= "table" then return end
    item = CreateItem(tray)
    tray.items[category] = item
    if onNewItem then pcall(onNewItem, item) end
    item.Icon:SetTexture(info.icon or FALLBACK_ICON)
  end

  if not item:IsShown() then item:Show() end
  UpdateState(item, state)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Trays
-- ─────────────────────────────────────────────────────────────────────────────

-- Hides every item, as Blizzard's tray does when its arena frame goes away.
local function ResetTray(tray)
  for _, item in pairs(tray.items) do
    item.ImmunityIndicator:Hide()
    item.Cooldown:Clear()
    item:Hide()
  end
end

local function CreateTray(i)
  local tray = CreateFrame("Frame", nil, UIParent)
  tray:SetSize(1, 1)
  tray:SetPoint("CENTER", UIParent, "CENTER")
  -- Never seen: the mirror draws the icons. Kept shown so the item
  -- cooldowns run and finish.
  tray:SetAlpha(0)
  tray:EnableMouse(false)
  tray.items = {}

  local unit = "arena" .. i
  -- The engine filters by unit, so no (possibly secret) unit token is ever
  -- compared here.
  local ok = pcall(tray.RegisterUnitEvent, tray, EVENT, unit)
  if not ok then pcall(tray.RegisterEvent, tray, EVENT) end
  tray:RegisterEvent("PLAYER_ENTERING_WORLD")
  tray:SetScript("OnEvent", function(self, event, eventUnit, state)
    if event == "PLAYER_ENTERING_WORLD" then
      ResetTray(self)
    elseif ok or (not IsSecret(eventUnit) and eventUnit == unit) then
      OnStateUpdated(self, state)
    end
  end)
  return tray
end

-- The tray for arena index i, created on first use.
function NativeTray:Get(i)
  if not trays[i] then trays[i] = CreateTray(i) end
  return trays[i]
end
