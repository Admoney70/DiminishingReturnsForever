std = "lua51"
max_line_length = false
exclude_files = { ".release/" }
-- Upstream style: unused callback arguments and `self`, shadowed upvalues.
ignore = { "212", "431", "432", "581" }
globals = {
	"DrpulseV2DB", "Drpulse_OnCompartmentClick", "SLASH_DRPULSE1", "SLASH_DRPULSE2", "SlashCmdList", "UISpecialFrames",
}
read_globals = {
	"C_CVar", "C_ClassColor", "C_EventUtils", "C_Item", "C_LossOfControl", "C_NamePlate", "C_Secrets", "C_Spell",
	"C_SpellBook", "C_SpellDiminish", "C_Texture", "C_Timer", "C_UnitAuras", "CreateColor", "CreateFrame", "DRiftDB",
	"DrpulseDB", "Enum", "GameTooltip", "GetBuildInfo", "GetCursorPosition", "GetMinimapShape", "GetTime",
	"InCombatLockdown", "IsMouseButtonDown", "IsShiftKeyDown", "MenuResponse", "Minimap", "UIParent", "UnitCanAttack",
	"UnitClass", "UnitExists", "UnitGUID", "UnitIsPlayer", "UnitName", "canaccesstable", "issecretvalue",
}
files["tests/"] = { std = "+max", globals = { "_G" }, allow_defined_top = true,
	ignore = { "111", "112", "113", "121", "122", "131", "142", "143" } }
