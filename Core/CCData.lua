-- Core/CCData.lua
-- Crowd-control spell data for Blitz battleground DR tracking.
--
-- PORTED from the BlitzFramesTargets addon (Extras/CCData.lua), which in turn
-- ported it from BlitzBrain. Durations were farmed empirically in live
-- battlegrounds by that author, so they carry roughly +/-20% noise; where a
-- value is uncertain the LONGER duration is preferred, because that pushes the
-- DR window later and errs toward holding a CC rather than throwing one into
-- diminishing returns.
--
-- Pure data. The logic lives in Modules/BlitzDR.lua.

local ADDON, ns = ...

-- One icon per BRACKET rather than per spell, the way Blizzard's arena DR tray
-- shows it: a stun reads as "stun" whichever stun it was.
ns.DR_CATEGORY_ICON = {
  stun      = [[Interface\Icons\Spell_Frost_Stun]],
  disorient = [[Interface\Icons\Spell_Shadow_Possession]],
  incap     = 136071,
  root      = 136100,
}

ns.DR_CATEGORY_LABEL = {
  stun      = "Stun",
  disorient = "Disorient",
  incap     = "Incapacitate",
  root      = "Root",
}

-- Display order for the icon row.
ns.DR_CATEGORY_ORDER = { "stun", "disorient", "incap", "root" }

-- Talent-dependent brackets: the category applies only while the talent entry
-- is selected.
ns.CC_TALENT_VARIANTS = {
  [88625] = { nodeID = 82619, entryID = 103753, spellID = 200199, name = "Censure", category = "stun" },
}

-- CAST-ID ALIASES. Some rows are keyed by the DEBUFF a spell applies rather
-- than the spell you press, while detection keys on UNIT_SPELLCAST_SUCCEEDED,
-- which reports the button. Where the two differ the cast ID points at the row.
ns.CC_CAST_ALIASES = {
  [5782] = 118699,   -- Fear (Warlock): cast 5782, debuff row 118699
  -- Freezing Cold (Mage): you press Cone of Cold and the talent turns its slow
  -- into a root, so the alias only counts while that talent is selected.
  [120] = { row = 386770, aoe = true, aoeRadius = 12, talentByName = true },
}

-- Item IDs whose use-spell has a 0..R yard range, used to answer "is this
-- plate within R yards" for AoE crowd control.
ns.DR_RADIUS_ITEMS = {
  [6] = { itemID = 219915, verified = "2026-08-31", notes = "author, NPC walk-out; the melee band the dispel clearance needs" },
  [8] = { itemID = 278557, verified = "2026-08-29", notes = "spare 274705" },
  [50] = { itemID = 116139, verified = "2026-08-29" },
  [100] = { itemID = 250225, verified = "2026-08-29", notes = "Void Execution Mandate" },
  [12] = { itemID = 208068, verified = "2026-08-29" },
  [15] = { itemID = 249688, verified = "2026-09-04", notes = "Felo'melorn Replica" },
  [10] = { itemID = 250854, verified = "2026-08-29", notes = "Sun's Focus" },
  [55] = { itemID = 74637, verified = "2026-09-01", notes = "Kiryn's Poison Vial; LibRangeCheck HarmItems[55], author-confirmed" },
  [60] = { itemID = 274496, verified = "2026-08-31", notes = "author, NPC walk-out; the far band the triangle needs" },
}

-- Only these four brackets are tracked and drawn.
ns.DR_TRACKED = { stun = true, disorient = true, incap = true, root = true }

ns.CC_SPELL_DATA = {
  [377048] = { name = "Absolute Zero", icon = 135782, baseDuration = 3, category = "stun", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, untrackable = true, reason = "talent proc (Frozen Orb / Frostwyrm's Fury)" },
  [221562] = { name = "Asphyxiate", icon = 538558, baseDuration = 3, category = "stun", playerClass = "UNKNOWN", dispelType = nil },
  [89766]  = { name = "Axe Toss", icon = 236316, baseDuration = 3, category = "stun", playerClass = "UNKNOWN", dispelType = nil, pet = true },
  [347008] = { name = "Axe Toss", icon = 236316, baseDuration = 4, category = "stun", playerClass = "UNKNOWN", dispelType = nil, pet = true },
  [117526] = { name = "Binding Shot", icon = 462650, baseDuration = 3, category = "stun", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, untrackable = true, reason = "delayed (tether)" },
  [255723] = { name = "Bull Rush", icon = 1723987, baseDuration = 1.5, category = "stun", playerClass = "UNKNOWN", dispelType = nil, aoe = true, untrackable = true, reason = "arrival (racial charge)" },
  [118905] = { name = "Capacitor Totem", icon = 136013, baseDuration = 3, category = "stun", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, untrackable = true, reason = "delayed (totem)" },
  [179057] = { name = "Chaos Nova", icon = 135795, baseDuration = 4, category = "stun", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, aoeRadius = 8 },
  [1833]   = { name = "Cheap Shot", icon = 132092, baseDuration = 4, category = "stun", playerClass = "UNKNOWN", dispelType = nil },
  [357021] = { name = "Consecutive Concussion", icon = 135860, baseDuration = 4, category = "stun", playerClass = "UNKNOWN", dispelType = nil, untrackable = true, reason = "proc" },
  [287250] = { name = "Dead of Winter", icon = 538770, baseDuration = 4, category = "stun", playerClass = "DEATHKNIGHT", dispelType = "magic", aoe = true, untrackable = true, reason = "stacking (Remorseless Winter)" },
  [202335] = { name = "Double Barrel", icon = 644378, baseDuration = 3, category = "stun", playerClass = "MONK", dispelType = nil, aoe = true, untrackable = true, reason = "talent trigger" },
  [77505]  = { name = "Earthquake", icon = 451165, baseDuration = 1.5, category = "stun", playerClass = "UNKNOWN", dispelType = nil, aoe = true, untrackable = true, reason = "proc chance" },
  [213688] = { name = "Fel Cleave", icon = 1109118, baseDuration = 1, category = "stun", playerClass = "UNKNOWN", dispelType = nil, aoe = true, untrackable = true, reason = "proc" },
  [211881] = { name = "Fel Eruption", icon = 1118739, baseDuration = 3, category = "stun", playerClass = "DEMONHUNTER", dispelType = nil },
  [91800]  = { name = "Gnaw", icon = 237524, baseDuration = 1, category = "stun", playerClass = "UNKNOWN", dispelType = nil, pet = true },
  [853]    = { name = "Hammer of Justice", icon = 135963, baseDuration = 5, category = "stun", playerClass = "UNKNOWN", dispelType = "magic" },
  [287712] = { name = "Haymaker", icon = 2447782, baseDuration = 3, category = "stun", playerClass = "UNKNOWN", dispelType = nil },
  [200200] = { name = "Holy Word: Chastise", icon = 135904, baseDuration = 3, category = "stun", playerClass = "UNKNOWN", dispelType = nil },
  [200196] = { name = "Holy Word: Chastise", icon = 135886, baseDuration = 4, category = "stun", playerClass = "UNKNOWN", dispelType = nil },
  [205630] = { name = "Illidan's Grasp", icon = 1380367, baseDuration = 2, category = "stun", playerClass = "UNKNOWN", dispelType = nil, channeled = true, untrackable = true, reason = "delayed (the throw)" },
  [24394]  = { name = "Intimidation", icon = 132111, baseDuration = 3, category = "stun", playerClass = "UNKNOWN", dispelType = nil },
  [408]    = { name = "Kidney Shot", icon = 132298, baseDuration = 5, category = "stun", playerClass = "UNKNOWN", dispelType = nil, variable = true },
  [119381] = { name = "Leg Sweep", icon = 642414, baseDuration = 4, category = "stun", playerClass = "UNKNOWN", dispelType = nil, aoe = true, aoeRadius = 10 },
  [305485] = { name = "Lightning Lasso", icon = 1385911, baseDuration = 5, category = "stun", playerClass = "UNKNOWN", dispelType = nil, channeled = true },
  [203123] = { name = "Maim", icon = 132134, baseDuration = 5, category = "stun", playerClass = "UNKNOWN", dispelType = nil, variable = true },
  [200166] = { name = "Metamorphosis", icon = 0, baseDuration = 3, category = "stun", playerClass = "DEMONHUNTER", dispelType = nil, aoe = true, untrackable = true, reason = "arrival (leap)" },
  [5211]   = { name = "Mighty Bash", icon = 132114, baseDuration = 4, category = "stun", playerClass = "UNKNOWN", dispelType = nil },
  [91797]  = { name = "Monstrous Blow", icon = 135860, baseDuration = 2, category = "stun", playerClass = "UNKNOWN", dispelType = nil, pet = true },
  [202246] = { name = "Overrun", icon = 1408833, baseDuration = 3, category = "stun", playerClass = "DRUID", dispelType = nil, aoe = true, untrackable = true, reason = "arrival (charge)" },
  [202244] = { name = "Overrun", icon = 1408833, baseDuration = 3, category = "stun", playerClass = "DRUID", dispelType = nil, aoe = true, untrackable = true, reason = "arrival (charge)" },
  [64044]  = { name = "Psychic Horror", icon = 237568, baseDuration = 3, category = "stun", playerClass = "PRIEST", dispelType = "magic" },
  [163505] = { name = "Rake", icon = 132122, baseDuration = 4, category = "stun", playerClass = "UNKNOWN", dispelType = nil },
  [210141] = { name = "Reanimation", icon = 1390947, baseDuration = 3, category = "stun", playerClass = "UNKNOWN", dispelType = nil, aoe = true, untrackable = true, reason = "delayed (ghoul)" },
  [30283]  = { name = "Shadowfury", icon = 607865, baseDuration = 3, category = "stun", playerClass = "UNKNOWN", dispelType = nil, aoe = true, untrackable = true, reason = "ground-targeted" },
  [385954] = { name = "Shield Charge", icon = 4667427, baseDuration = 4, category = "stun", playerClass = "UNKNOWN", dispelType = nil },
  [132168] = { name = "Shockwave", icon = 236312, baseDuration = 2, category = "stun", playerClass = "UNKNOWN", dispelType = nil, aoe = true, aoeRadius = 15, reason = "cone (16y, swept at 15)" },
  [389831] = { name = "Snowdrift", icon = 135783, baseDuration = 4, category = "stun", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, untrackable = true, reason = "channel + ground" },
  [132169] = { name = "Storm Bolt", icon = 613535, baseDuration = 3, category = "stun", playerClass = "UNKNOWN", dispelType = nil },
  [372245] = { name = "Terror of the Skies", icon = 4622477, baseDuration = 4, category = "stun", playerClass = "UNKNOWN", dispelType = nil, aoe = true, untrackable = true, reason = "talent proc (Deep Breath)" },
  [1234195] = { name = "Void Nova", icon = 7554172, baseDuration = 4, category = "stun", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, aoeRadius = 8 },
  [255941] = { name = "Wake of Ashes", icon = 0, baseDuration = 5, category = "stun", playerClass = "PALADIN", dispelType = "magic", aoe = true, untrackable = true, reason = "cone" },
  [20549]  = { name = "War Stomp", icon = 132368, baseDuration = 2, category = "stun", playerClass = "UNKNOWN", dispelType = nil, aoe = true, aoeRadius = 8 },
  [199085] = { name = "Warpath", icon = 947554, baseDuration = 3, category = "stun", playerClass = "WARRIOR", dispelType = nil, aoe = true, untrackable = true, reason = "arrival (leap talent)" },
  [210128] = { name = "Zombify", icon = 1390947, baseDuration = 3, category = "stun", playerClass = "DEATHKNIGHT", dispelType = nil, aoe = true, untrackable = true, reason = "delayed" },
  [2094]   = { name = "Blind", icon = 136175, baseDuration = 5, category = "disorient", playerClass = "UNKNOWN", dispelType = nil, breakable = true },
  [105421] = { name = "Blinding Light", icon = 571553, baseDuration = 4, category = "disorient", playerClass = "PALADIN", dispelType = "magic", aoe = true, aoeRadius = 10, breakable = true },
  [207167] = { name = "Blinding Sleet", icon = 135836, baseDuration = 4, category = "disorient", playerClass = "DEATHKNIGHT", dispelType = nil, aoe = true, breakable = true, aoeRadius = 10, reason = "cone (10y, measured 2026-09-04)" },
  [358861] = { name = "Cascading Horrors", icon = 132776, baseDuration = 2, category = "disorient", playerClass = "UNKNOWN", dispelType = "magic", breakable = true, untrackable = true, reason = "proc" },
  [33786]  = { name = "Cyclone", icon = 136022, baseDuration = 5, category = "disorient", playerClass = "UNKNOWN", dispelType = nil },
  [31661]  = { name = "Dragon's Breath", icon = 134153, baseDuration = 3, category = "disorient", playerClass = "MAGE", dispelType = "magic", aoe = true, breakable = true, aoeRadius = 10, reason = "cone (10y measured; the tooltip says 12)" },
  [118699] = { name = "Fear", icon = 136183, baseDuration = 6, category = "disorient", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [130616] = { name = "Fear", icon = 136183, baseDuration = 6, category = "disorient", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [202274] = { name = "Hot Trub", icon = 135860, baseDuration = 4, category = "disorient", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, breakable = true, untrackable = true, reason = "conditional (needs Stagger)" },
  [5484]   = { name = "Howl of Terror", icon = 607852, baseDuration = 6, category = "disorient", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, aoeRadius = 10, breakable = true },
  [202272] = { name = "Incendiary Breath", icon = 443394, baseDuration = 4, category = "disorient", playerClass = "MONK", dispelType = nil, aoe = true, breakable = true, untrackable = true, reason = "cone; talent not found 2026-09-04" },
  [5246]   = { name = "Intimidating Shout", icon = 132154, baseDuration = 6, category = "disorient", playerClass = "UNKNOWN", dispelType = nil, aoe = true, aoeRadius = 8, breakable = true },
  [115268] = { name = "Mesmerize", icon = 237185, baseDuration = 6, category = "disorient", playerClass = "WARLOCK", dispelType = "magic", breakable = true, pet = true },
  [605]    = { name = "Mind Control", icon = 136206, baseDuration = 6, category = "disorient", playerClass = "UNKNOWN", dispelType = nil, channeled = true },
  [8122]   = { name = "Psychic Scream", icon = 136184, baseDuration = 6, category = "disorient", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, aoeRadius = 8, breakable = true },
  [353084] = { name = "Ring of Fire", icon = 4067368, baseDuration = 3, category = "disorient", playerClass = "UNKNOWN", dispelType = nil, aoe = true, breakable = true, untrackable = true, reason = "ground" },
  [1513]   = { name = "Scare Beast", icon = 132118, baseDuration = 8, category = "disorient", playerClass = "HUNTER", dispelType = "magic", breakable = true },
  [6358]   = { name = "Seduction", icon = 1717715, baseDuration = 6, category = "disorient", playerClass = "UNKNOWN", dispelType = "magic", channeled = true, breakable = true, pet = true },
  [207685] = { name = "Sigil of Misery", icon = 1418287, baseDuration = 3, category = "disorient", playerClass = "UNKNOWN", dispelType = nil, aoe = true, breakable = true, untrackable = true, reason = "delayed" },
  [360806] = { name = "Sleep Walk", icon = 1396974, baseDuration = 6, category = "disorient", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [198909] = { name = "Song of Chi-Ji", icon = 332402, baseDuration = 6, category = "disorient", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, breakable = true, untrackable = true, reason = "projectile (can miss)" },
  [10326]  = { name = "Turn Evil", icon = 571559, baseDuration = 6, category = "disorient", playerClass = "PALADIN", dispelType = "magic", breakable = true },
  [710]    = { name = "Banish", icon = 136135, baseDuration = 6, category = "incap", playerClass = "WARLOCK", dispelType = "magic" },
  [205596] = { name = "Detainment", icon = 463560, baseDuration = 4, category = "incap", playerClass = "DEMONHUNTER", dispelType = nil },
  [3355]   = { name = "Freezing Trap", icon = 135834, baseDuration = 6, category = "incap", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, breakable = true, untrackable = true, reason = "delayed (trap)" },
  [203337] = { name = "Freezing Trap", icon = 236209, baseDuration = 4, category = "incap", playerClass = "UNKNOWN", dispelType = nil, aoe = true, breakable = true, untrackable = true, reason = "delayed (trap)" },
  [1776]   = { name = "Gouge", icon = 132155, baseDuration = 3, category = "incap", playerClass = "UNKNOWN", dispelType = nil, breakable = true },
  [51514]  = { name = "Hex", icon = 237579, baseDuration = 6, category = "incap", playerClass = "UNKNOWN", dispelType = "curse", breakable = true },
  [210873] = { name = "Hex", icon = 132193, baseDuration = 6, category = "incap", playerClass = "SHAMAN", dispelType = "curse", breakable = true },
  [2637]   = { name = "Hibernate", icon = 136090, baseDuration = 6, category = "incap", playerClass = "DRUID", dispelType = "magic", breakable = true },
  [88625]  = { name = "Holy Word: Chastise", icon = 135886, baseDuration = 3, category = "incap", playerClass = "PRIEST", dispelType = nil, breakable = true },
  [221527] = { name = "Imprison", icon = 1380368, baseDuration = 4, category = "incap", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [217832] = { name = "Imprison", icon = 1380368, baseDuration = 3, category = "incap", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [99]     = { name = "Incapacitating Roar", icon = 132121, baseDuration = 3, category = "incap", playerClass = "UNKNOWN", dispelType = nil, aoe = true, aoeRadius = 10, breakable = true },
  [6789]   = { name = "Mortal Coil", icon = 607853, baseDuration = 3, category = "incap", playerClass = "WARLOCK", dispelType = "magic" },
  [115078] = { name = "Paralysis", icon = 629534, baseDuration = 3, category = "incap", playerClass = "UNKNOWN", dispelType = nil, breakable = true },
  [118]    = { name = "Polymorph", icon = 136071, baseDuration = 6, category = "incap", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [28271]  = { name = "Polymorph", icon = 135997, baseDuration = 6, category = "incap", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [28272]  = { name = "Polymorph", icon = 135997, baseDuration = 6, category = "incap", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [61305]  = { name = "Polymorph", icon = 135997, baseDuration = 6, category = "incap", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [161351] = { name = "Polymorph", icon = 135997, baseDuration = 6, category = "incap", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [161352] = { name = "Polymorph", icon = 135997, baseDuration = 6, category = "incap", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [161353] = { name = "Polymorph", icon = 135997, baseDuration = 6, category = "incap", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [161354] = { name = "Polymorph", icon = 135997, baseDuration = 6, category = "incap", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [161355] = { name = "Polymorph", icon = 135997, baseDuration = 6, category = "incap", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [277792] = { name = "Polymorph", icon = 2027853, baseDuration = 6, category = "incap", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [107079] = { name = "Quaking Palm", icon = 572035, baseDuration = 4, category = "incap", playerClass = "UNKNOWN", dispelType = nil, breakable = true },
  [20066]  = { name = "Repentance", icon = 135942, baseDuration = 6, category = "incap", playerClass = "PALADIN", dispelType = "magic", breakable = true },
  [82691]  = { name = "Ring of Frost", icon = 464484, baseDuration = 6, category = "incap", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, breakable = true, untrackable = true, reason = "ground" },
  [6770]   = { name = "Sap", icon = 132310, baseDuration = 6, category = "incap", playerClass = "UNKNOWN", dispelType = nil, breakable = true, oocOnly = true },
  [213691] = { name = "Scatter Shot", icon = 132153, baseDuration = 3, category = "incap", playerClass = "HUNTER", dispelType = nil, breakable = true },
  [9484]   = { name = "Shackle Undead", icon = 136091, baseDuration = 6, category = "incap", playerClass = "PRIEST", dispelType = "magic", breakable = true },
  [197214] = { name = "Sundering", icon = 524794, baseDuration = 2, category = "incap", playerClass = "SHAMAN", dispelType = nil, aoe = true, breakable = true, reason = "cone/line" },
  [105771] = { name = "Charge", icon = 132337, baseDuration = 1, category = "root", playerClass = "UNKNOWN", dispelType = nil, untrackable = true, reason = "baseline root, DR unconfirmed" },
  [324312] = { name = "Clash", icon = 628134, baseDuration = 4, category = "root", playerClass = "MONK", dispelType = nil },
  [204085] = { name = "Deathchill", icon = 135842, baseDuration = 2, category = "root", playerClass = "UNKNOWN", dispelType = "magic", breakable = true, untrackable = true, reason = "talent (Death Chill)" },
  [233395] = { name = "Deathchill", icon = 135842, baseDuration = 4, category = "root", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, breakable = true, untrackable = true, reason = "talent (Death Chill)" },
  [116706] = { name = "Disable", icon = 132316, baseDuration = 3, category = "root", playerClass = "UNKNOWN", dispelType = nil, untrackable = true, reason = "stacking (needs its own snare first)" },
  [64695]  = { name = "Earthgrab", icon = 136100, baseDuration = 6, category = "root", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, breakable = true, untrackable = true, reason = "delayed (totem)" },
  [1258862] = { name = "Encasing Cold", icon = 236209, baseDuration = 4, category = "root", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [339]    = { name = "Entangling Roots", icon = 136100, baseDuration = 6, category = "root", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [460614] = { name = "Entangling Roots", icon = 136100, baseDuration = 3, category = "root", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [233581] = { name = "Entrenched in Flame", icon = 524795, baseDuration = 3, category = "root", playerClass = "WARLOCK", dispelType = "magic", breakable = true, untrackable = true, reason = "talent/proc" },
  [33395]  = { name = "Freeze", icon = 1698698, baseDuration = 8, category = "root", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, breakable = true, untrackable = true, reason = "ground-targeted (pet)" },
  [386770] = { name = "Freezing Cold", icon = 135840, baseDuration = 5, category = "root", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, breakable = true, reason = "talent + cone (cast 120, swept at 12)" },
  [122]    = { name = "Frost Nova", icon = 135848, baseDuration = 8, category = "root", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, aoeRadius = 12, breakable = true },
  [198120] = { name = "Frostbite", icon = 135842, baseDuration = 4, category = "root", playerClass = "MAGE", dispelType = "magic", breakable = true, untrackable = true, reason = "proc" },
  [55536]  = { name = "Frostweave Net", icon = 134325, baseDuration = 3, category = "root", playerClass = "UNKNOWN", dispelType = "magic", breakable = true },
  [190925] = { name = "Harpoon", icon = 1376040, baseDuration = 3, category = "root", playerClass = "UNKNOWN", dispelType = nil },
  [157997] = { name = "Ice Nova", icon = 1033909, baseDuration = 2, category = "root", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, partial = true, targetOnly = true, breakable = true },
  [454787] = { name = "Ice Prison", icon = 236214, baseDuration = 4, category = "root", playerClass = "UNKNOWN", dispelType = "magic", breakable = true, untrackable = true, reason = "talent" },
  [355689] = { name = "Landslide", icon = 1016245, baseDuration = 6, category = "root", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, breakable = true, untrackable = true, reason = "ground" },
  [102359] = { name = "Mass Entanglement", icon = 538515, baseDuration = 6, category = "root", playerClass = "UNKNOWN", dispelType = "magic", aoe = true, partial = true, targetOnly = true, breakable = true },
  [91807]  = { name = "Shambling Rush", icon = 237569, baseDuration = 2, category = "root", playerClass = "UNKNOWN", dispelType = nil, pet = true },
  [162488] = { name = "Steel Trap", icon = 1467588, baseDuration = 6, category = "root", playerClass = "HUNTER", dispelType = nil, aoe = true, untrackable = true, reason = "delayed (trap)" },
  [343247] = { name = "Steel Trap", icon = 1467588, baseDuration = 6, category = "root", playerClass = "HUNTER", dispelType = nil, aoe = true, untrackable = true, reason = "delayed (trap)" },
  [370970] = { name = "The Hunt", icon = 6035307, baseDuration = 2, category = "root", playerClass = "UNKNOWN", dispelType = "magic" },
  [212638] = { name = "Tracker's Net", icon = 1412207, baseDuration = 6, category = "root", playerClass = "HUNTER", dispelType = "magic", breakable = true },
}
