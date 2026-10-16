-- Core/Util.lua
-- Shared helpers used across modules: table utilities, Midnight secret-value
-- guards, safe unit queries and small frame/texture factories.

local ADDON, ns = ...

local Util = {}
ns.Util = Util

-- ─────────────────────────────────────────────────────────────────────────────
-- Table helpers
-- ─────────────────────────────────────────────────────────────────────────────

function Util.DeepCopy(src)
  if type(src) ~= "table" then return src end
  local dst = {}
  for k, v in pairs(src) do
    dst[k] = Util.DeepCopy(v)
  end
  return dst
end

-- Fill in missing keys of dst from def (recursive, never overwrites).
function Util.ApplyDefaults(dst, def)
  if type(dst) ~= "table" or type(def) ~= "table" then return end
  for k, v in pairs(def) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      Util.ApplyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

function Util.Clamp(v, lo, hi)
  if v == nil then return lo end
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Secret-value / forbidden-frame guards (Midnight protected arenas)
-- ─────────────────────────────────────────────────────────────────────────────

function Util.IsSecret(v)
  local fn = _G.issecretvalue
  if type(fn) ~= "function" then return false end
  local ok, r = pcall(fn, v)
  return ok and r and true or false
end

function Util.IsForbidden(obj)
  if not obj then return true end
  local ok, res = pcall(function()
    if obj.IsForbidden then return obj:IsForbidden() end
    return false
  end)
  if not ok then return true end
  return res and true or false
end

function Util.SafeIndex(obj, key)
  if Util.IsForbidden(obj) then return nil end
  local ok, v = pcall(function() return obj[key] end)
  if ok then return v end
  return nil
end

function Util.SafeChildren(obj)
  if Util.IsForbidden(obj) then return {} end
  local fn = Util.SafeIndex(obj, "GetChildren")
  if type(fn) ~= "function" then return {} end
  local ok, t = pcall(function() return { fn(obj) } end)
  if ok and t then return t end
  return {}
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Safe unit queries
-- ─────────────────────────────────────────────────────────────────────────────

function Util.SafeUnitIsUnit(a, b)
  local ok, r = pcall(UnitIsUnit, a, b)
  if not ok then return nil end
  if type(r) ~= "boolean" or Util.IsSecret(r) then return nil end
  return r
end

function Util.SafeUnitExists(unit)
  local ok, r = pcall(UnitExists, unit)
  if not ok or type(r) ~= "boolean" or Util.IsSecret(r) then return false end
  return r
end

function Util.SafeUnitGUID(unit)
  local ok, g = pcall(UnitGUID, unit)
  if not ok or type(g) ~= "string" then return nil end
  if Util.IsSecret(g) then return nil end
  local okL, n = pcall(function() return #g end)
  if not okL or type(n) ~= "number" or n < 1 then return nil end
  return g
end

-- Readable unit name, or nil when secret/unavailable. In Midnight-protected
-- arenas UnitIsUnit and UnitGUID are secret-gated but names stay readable,
-- so this is what makes unit identity resolvable there.
function Util.SafeUnitName(unit)
  local ok, n = pcall(UnitName, unit)
  if not ok or type(n) ~= "string" then return nil end
  if Util.IsSecret(n) then return nil end
  local okL, len = pcall(function() return #n end)
  if not okL or type(len) ~= "number" or len < 1 then return nil end
  if n == UNKNOWNOBJECT or n == "Unknown" then return nil end
  return n
end

-- True unless the unit definitively does not exist. Secret or unreadable
-- results count as "maybe", so callers never bail out on a gated answer.
function Util.UnitMaybeExists(unit)
  local ok, r = pcall(UnitExists, unit)
  if not ok then return true end
  if Util.IsSecret(r) then return true end
  return r and true or false
end

-- Realm-qualified unit name, or nil when it cannot be read.
--
-- ORDER IS LOAD-BEARING: the secret guard runs before every other test,
-- because `not name`, `name == UNKNOWNOBJECT` and `realm ~= ""` are all reads
-- that throw on a secret value. A guard placed second is not a guard.
-- Used as the DR state key in battlegrounds, where aura APIs are sealed and a
-- name is the only stable identity available.
function Util.NormalizeUnitName(unit)
  local ok, name, realm = pcall(UnitName, unit)
  if not ok then return nil end
  if Util.IsSecret(name) then return nil end
  if not name or type(name) ~= "string" then return nil end
  if name == UNKNOWNOBJECT or name == "" then return nil end
  if Util.IsSecret(realm) then return name end
  if realm and realm ~= "" then return name .. "-" .. realm end
  return name
end

-- The nameplate frame for a unit, or nil when it has none (off screen, out of
-- range, nameplates disabled) or the plate is forbidden. Friendly plates
-- inside instances are forbidden, and anchoring a frame to a forbidden frame
-- throws, so the check is not optional.
function Util.GetUnitNameplate(unit)
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
  local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
  if not ok or not plate then return nil end
  if Util.IsForbidden(plate) then return nil end
  return plate
end

-- Strata for DR rows that sit on NAMEPLATES: the plates' own strata, so the
-- rows draw BEHIND unit frames and party frames (LOW and above). They keep a
-- high frame level within it, which keeps them above the plate bodies.
-- Rows on the Target/Focus frames stay HIGH so they draw over their frame.
Util.PLATE_STRATA = "BACKGROUND"
Util.FRAME_STRATA = "HIGH"

-- Applies a strata to one of OUR frames and every frame beneath it.
function Util.SetStrataDeep(frame, strata)
  if not frame then return end
  frame:SetFrameStrata(strata)
  for _, child in ipairs({ frame:GetChildren() }) do
    Util.SetStrataDeep(child, strata)
  end
end

-- True only when the unit verifiably exists AND is dead. Unseen/invisible
-- units (e.g. behind Mass Invisibility) return false, never true.
function Util.UnitIsConfirmedDead(unit)
  if not Util.SafeUnitExists(unit) then return false end
  local ok, r = pcall(UnitIsDeadOrGhost, unit)
  if not ok or type(r) ~= "boolean" or Util.IsSecret(r) then return false end
  return r
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Frame / texture helpers
-- ─────────────────────────────────────────────────────────────────────────────

function Util.FindFirstTextureRegion(frame)
  if Util.IsForbidden(frame) then return nil end
  local fn = Util.SafeIndex(frame, "GetRegions")
  if type(fn) ~= "function" then return nil end
  local ok, regions = pcall(function() return { fn(frame) } end)
  if not ok or not regions then return nil end
  local fallback = nil
  for _, r in ipairs(regions) do
    if r and (not Util.IsForbidden(r)) and r.GetTexture then
      local ok2, layer = pcall(function() return r.GetDrawLayer and r:GetDrawLayer() or nil end)
      if ok2 and (layer == "ARTWORK" or layer == "OVERLAY") then return r end
      if not fallback then fallback = r end
    end
  end
  return fallback
end

function Util.FindCooldownChild(frame)
  if Util.IsForbidden(frame) then return nil end
  local children = Util.SafeChildren(frame)
  for _, c in ipairs(children) do
    if c and (not Util.IsForbidden(c)) and c.SetCooldown and c.GetCooldownTimes then return c end
  end
  for _, c in ipairs(children) do
    if c and (not Util.IsForbidden(c)) and c.SetCooldown then return c end
  end
  return nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- DR border (sArena-style)
--
-- A multi-style state border used by both DR modules. Styles:
--   "GLOW"  – sArena's default: UI-Quickslot-Depress glow texture extending
--             border_size px beyond the icon, vertex-colored by DR state
--   "THIN"  – thin pixel-style atlas border (Blizzard atlas)
--   "THICK" – solid pixel lines with configurable thickness
--   "NONE"  – no border
-- ─────────────────────────────────────────────────────────────────────────────

local GLOW_TEXTURE = "Interface\\Buttons\\UI-Quickslot-Depress"
local THIN_ATLAS   = "communities-create-avatar-border-selected"

function Util.CreateDRBorder(parent)
  local b = CreateFrame("Frame", nil, parent)
  b:SetAllPoints(parent)

  b.glow = b:CreateTexture(nil, "OVERLAY")
  b.glow:SetTexture(GLOW_TEXTURE)
  b.glow:Hide()

  b.thin = b:CreateTexture(nil, "OVERLAY")
  b.thin:SetAtlas(THIN_ATLAS)
  b.thin:Hide()

  local function line()
    local t = b:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 1, 1, 1)
    t:Hide()
    return t
  end
  b.top    = line(); b.top:SetPoint("TOPLEFT", b, 0, 0);       b.top:SetPoint("TOPRIGHT", b, 0, 0);       b.top:SetHeight(1)
  b.bottom = line(); b.bottom:SetPoint("BOTTOMLEFT", b, 0, 0); b.bottom:SetPoint("BOTTOMRIGHT", b, 0, 0); b.bottom:SetHeight(1)
  b.left   = line(); b.left:SetPoint("TOPLEFT", b, 0, 0);      b.left:SetPoint("BOTTOMLEFT", b, 0, 0);    b.left:SetWidth(1)
  b.right  = line(); b.right:SetPoint("TOPRIGHT", b, 0, 0);    b.right:SetPoint("BOTTOMRIGHT", b, 0, 0);  b.right:SetWidth(1)

  -- Recolors whichever style is currently active. Honors the black-border
  -- option set at Configure time.
  function b.SetStateColor(self, r, g, bl)
    self._r, self._g, self._b = r, g, bl
    if self._black then r, g, bl = 0, 0, 0 end
    self.glow:SetVertexColor(r, g, bl, 1)
    self.thin:SetVertexColor(r, g, bl, 1)
    for _, ln in ipairs({ self.top, self.bottom, self.left, self.right }) do
      ln:SetColorTexture(r, g, bl, 1)
    end
  end

  -- opts: style, black, border_size (glow/thin pad), pixel_size (line px),
  --       r/g/b (state color)
  function b.Configure(self, opts)
    opts = opts or {}
    self._black = opts.black and true or false
    local pad = tonumber(opts.border_size) or 1
    local px  = tonumber(opts.pixel_size) or 2
    if px < 1 then px = 1 end
    local style = opts.style or "GLOW"

    self.glow:Hide()
    self.thin:Hide()
    self.top:Hide(); self.bottom:Hide(); self.left:Hide(); self.right:Hide()

    if style == "GLOW" then
      self.glow:ClearAllPoints()
      self.glow:SetPoint("TOPLEFT", self, "TOPLEFT", -pad, pad)
      self.glow:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", pad, -pad)
      self.glow:Show()
    elseif style == "THIN" then
      self.thin:ClearAllPoints()
      self.thin:SetPoint("TOPLEFT", self, "TOPLEFT", -pad, pad)
      self.thin:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", pad, -pad)
      self.thin:Show()
    elseif style == "THICK" then
      self.top:SetHeight(px);    self.top:Show()
      self.bottom:SetHeight(px); self.bottom:Show()
      self.left:SetWidth(px);    self.left:Show()
      self.right:SetWidth(px);   self.right:Show()
    end

    self:SetStateColor(opts.r or self._r or 1, opts.g or self._g or 1, opts.b or self._b or 1)
  end

  return b
end

function Util.GetSpellTextureSafe(spellID)
  if not spellID then return nil end
  if C_Spell and C_Spell.GetSpellTexture then
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
    if ok and tex then return tex end
  end
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
    if ok and info and info.iconID then return info.iconID end
  end
  return nil
end
