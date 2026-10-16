-- Core.lua
-- Addon bootstrap: saved-variables database, profile management and module
-- lifecycle. Feature code lives in Modules/, UI code in Config/.

local ADDON, ns = ...
local Util = ns.Util

-- Core\Util.lua loads first (see the .toc). If it's missing, the .toc file
-- list is stale: WoW only reads the .toc at client launch, so new files
-- require a full restart, not a /reload.
if not Util then
  print("|cffff0000DR Forever:|r core files failed to load. Fully restart the game client (a /reload is not enough after an addon update).")
  return
end

local LS = LibStub
local AceAddon = LS and LS("AceAddon-3.0", true)
local AceDB    = LS and LS("AceDB-3.0", true)
if not (AceAddon and AceDB) then
  print("DR Forever: embedded Ace3 libs missing. Check .toc load order.")
  return
end

local Core = AceAddon:NewAddon("DiminishingReturnsForever", "AceEvent-3.0", "AceConsole-3.0")
ns.Core = Core
_G.DiminishingReturnsForever = Core

local MODULE_NAMES = { "TargetandFocus", "WorldDR", "BlitzDR" }

local defaults = {
  profile = {
    arena = {
      enabled = true,
      test = { enabled = false },
      dr_reset_time = 20,
      dr = {
        pos_x = 0, pos_y = 0, icon_size = 26, font_size = 14, grow = "RIGHT",
        border_style = "GLOW", border_black = false,
        border_size = 1, pixel_border_size = 2,
        reverse_swipe = true, disable_swipe = false, color_cd_text = false,
        show_dr_text = true,
        anchor_nameplate = false, np_pos_x = 0, np_pos_y = 10, np_grow = "CENTER", np_both = false,
      },
      theme = { r = 1, g = 1, b = 0 },
      world_dr = {
        enabled = true,
        icon_size = 22, font_size = 12, spacing = 2,
        pos_x = 0, pos_y = 20, grow = "RIGHT",
        border_style = "GLOW", border_black = false,
        border_size = 1, pixel_border_size = 2,
        show_dr_text = true, color_cd_text = true, static_icons = false,
        show_decimals = true, decimal_threshold = 3,
        reverse_swipe = true, disable_swipe = false,
        categories = { stun = true, incap = true, fear = true, root = true },
        anchor_nameplate = false, np_pos_x = 0, np_pos_y = 10, np_grow = "CENTER", np_both = false,
      },
      -- Battleground (Blitz) DR shown on the Target and Focus unit frames.
      blitz_dr = {
        enabled = true,
        border_style = "GLOW", border_black = false,
        border_size = 1, pixel_border_size = 2,
        show_dr_text = true, color_cd_text = true,
        show_decimals = true, decimal_threshold = 3,
        reverse_swipe = true, disable_swipe = false,
        anchor_nameplate = false, np_pos_x = 0, np_pos_y = 10, np_grow = "CENTER", np_both = false,
        target = { icon_size = 26, spacing = 2, pos_x = 0, pos_y = 40, grow = "RIGHT", font_size = 12 },
        focus  = { icon_size = 26, spacing = 2, pos_x = 0, pos_y = 40, grow = "RIGHT", font_size = 12 },
      },
    },
  },
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Database
-- ─────────────────────────────────────────────────────────────────────────────

function Core:RepairDB()
  if not (self.arenaDB and self.arenaDB.profile) then return end
  local a = self.arenaDB.profile.arena
  if type(a) ~= "table" then
    self.arenaDB.profile.arena = Util.DeepCopy(defaults.profile.arena)
    a = self.arenaDB.profile.arena
  end
  Util.ApplyDefaults(a, defaults.profile.arena)
  if a.enabled == nil then a.enabled = true end

  -- 12.1: the DR reset window changed from 16s to 20s. Profiles created
  -- before then have 16 persisted; migrate it once to the new default.
  if not a.dr_reset_time_migrated_20 then
    a.dr_reset_time_migrated_20 = true
    if a.dr_reset_time == 16 then
      a.dr_reset_time = 20
    end
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Profile management
-- ─────────────────────────────────────────────────────────────────────────────

function Core:NotifyOptionsChanged()
  if ns.Config and ns.Config.RefreshAll then
    ns.Config:RefreshAll()
  end
end

function Core:GetUnifiedProfileName()
  if not self.arenaDB then return "Default" end
  return self.arenaDB:GetCurrentProfile() or "Default"
end

function Core:GetUnifiedProfileValues()
  local set = {}
  if self.arenaDB and self.arenaDB.GetProfiles then
    for _, n in ipairs(self.arenaDB:GetProfiles()) do set[n] = true end
  end
  local names = {}
  for n in pairs(set) do
    names[#names + 1] = n
  end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  local values = {}
  for _, n in ipairs(names) do
    values[n] = n
  end
  return values
end

-- Repair the DB, re-apply module state and notify modules/UI after any
-- profile operation.
function Core:OnProfileApplied()
  self:RepairDB()
  self:ApplyModules()
  for _, name in ipairs(MODULE_NAMES) do
    local mod = self:GetModule(name, true)
    if mod and mod.OnConfigChanged then
      pcall(function() mod:OnConfigChanged() end)
    end
  end
  self:NotifyOptionsChanged()
end

-- Runs a database operation with re-entrancy protection, then refreshes.
local function RunProfileOperation(self, op)
  if not self.arenaDB or self._profileSyncing then return end
  self._profileSyncing = true
  pcall(op)
  self._profileSyncing = false
  self:OnProfileApplied()
end

function Core:ApplyProfileSync(profileName)
  if not profileName or profileName == "" then return end
  RunProfileOperation(self, function() self.arenaDB:SetProfile(profileName) end)
end

function Core:CopyUnifiedProfile(fromProfile)
  if not fromProfile or fromProfile == "" then return end
  RunProfileOperation(self, function() self.arenaDB:CopyProfile(fromProfile) end)
end

function Core:ResetUnifiedProfile()
  RunProfileOperation(self, function() self.arenaDB:ResetProfile() end)
end

function Core:DeleteUnifiedProfile(profileName)
  if not profileName or profileName == "" then return end
  if profileName == self:GetUnifiedProfileName() then
    self:ApplyProfileSync("Default")
  end
  RunProfileOperation(self, function() self.arenaDB:DeleteProfile(profileName) end)
end

function Core:OnAnyProfileEvent(_, database, profileName)
  if self._profileSyncing then return end
  local target = profileName
  if not target or target == "" then
    if database and database.GetCurrentProfile then
      target = database:GetCurrentProfile()
    else
      target = self:GetUnifiedProfileName()
    end
  end
  self:ApplyProfileSync(target)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Lifecycle
-- ─────────────────────────────────────────────────────────────────────────────

function Core:OnInitialize()
  self.arenaDB = AceDB:New("DiminishingReturnsForeverDB", { profile = { arena = defaults.profile.arena } })
  ns.arenaDB = self.arenaDB

  if self.arenaDB.RegisterCallback then
    pcall(function() self.arenaDB:RegisterCallback(self, "OnProfileChanged", "OnAnyProfileEvent") end)
    pcall(function() self.arenaDB:RegisterCallback(self, "OnProfileCopied", "OnAnyProfileEvent") end)
    pcall(function() self.arenaDB:RegisterCallback(self, "OnProfileReset", "OnAnyProfileEvent") end)
  end

  self:RepairDB()

  if ns.Config and ns.Config.Init then
    ns.Config:Init()
  end

  self:RegisterChatCommand("dr", function(input)
    local cmd = type(input) == "string" and input:trim():lower() or ""
    if cmd == "blitz" then
      local B = self:GetModule("BlitzDR", true)
      if B and B.Debug then B:Debug() end
      return
    end
    if cmd == "debug" then
      local Arena = self:GetModule("TargetandFocus", true)
      if Arena and Arena.Debug then Arena:Debug() end
      return
    end
    if ns.Config and ns.Config.Window then
      ns.Config.Window:Toggle()
    end
  end)

  -- NO unconditional chat output. print() routes through
  -- DEFAULT_CHAT_FRAME:AddMessage, so printing from addon code touches the
  -- chat frame from an insecure call and taints it. Blizzard's own handler on
  -- that same frame then inherits the taint, and the next message carrying a
  -- SECRET string (a Battle.net whisper target) dies with "attempt to perform
  -- string conversion on a secret string value". The addon is discoverable
  -- through its entry in the Settings panel instead; /dr still works.
end

function Core:OnEnable()
  -- 12.1: Blizzard's enemy DR tray (SpellDiminishStatusTray) is gated
  -- behind this CVar. Without it the tray never shows anything and there
  -- is nothing for the arena module to mirror.
  -- Only WRITE when it is actually off, and never in combat: a CVar written by
  -- an addon is marked tainted, and Blizzard code that later reads it inherits
  -- that taint. Rewriting an already-correct value every login bought nothing
  -- and spread taint into Blizzard's arena code.
  if not InCombatLockdown() then
    local ok, cur = pcall(C_CVar.GetCVar, "spellDiminishPVPEnemiesEnabled")
    if ok and cur ~= "1" then
      pcall(C_CVar.SetCVar, "spellDiminishPVPEnemiesEnabled", "1")
    end
  end

  self:RegisterEvent("PLAYER_ENTERING_WORLD", "ApplyModules")
  self:ApplyModules()
end

function Core:ApplyModules()
  self:RepairDB()

  local aprof = self.arenaDB and self.arenaDB.profile and self.arenaDB.profile.arena or nil

  local Arena = self:GetModule("TargetandFocus", true)
  if Arena then
    local enabled = aprof and aprof.enabled ~= false
    if enabled then
      self:EnableModule("TargetandFocus")
      if Arena.EnsureInit then pcall(function() Arena:EnsureInit() end) end
    else
      self:DisableModule("TargetandFocus")
    end
  end

  local BDR = self:GetModule("BlitzDR", true)
  if BDR then
    local enabled = true
    if aprof and aprof.blitz_dr then
      enabled = aprof.blitz_dr.enabled ~= false
    end
    if enabled then
      self:EnableModule("BlitzDR")
    else
      self:DisableModule("BlitzDR")
    end
  end

  local WDR = self:GetModule("WorldDR", true)
  if WDR then
    local enabled = true
    if aprof and aprof.world_dr then
      enabled = aprof.world_dr.enabled ~= false
    end
    if enabled then
      self:EnableModule("WorldDR")
    else
      self:DisableModule("WorldDR")
    end
  end
end
