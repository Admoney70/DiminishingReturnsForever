std = "lua51"
max_line_length = false
exclude_files = { "Libs/", ".release/" }
-- Upstream style: `local ADDON, ns = ...` in every file, unused callback
-- arguments, and `self` shadowed by nested methods.
ignore = { "211/ADDON", "212", "432/self", "614" }
globals = {
	"DiminishingReturnsForever", "StaticPopupDialogs", "ColorPickerFrame", "UISpecialFrames",
}
read_globals = {
	"CLOSE", "C_CVar", "C_ClassTalents", "C_EncodingUtil", "C_Item", "C_LossOfControl", "C_NamePlate",
	"C_Spell", "C_SpellDiminish", "C_Timer", "C_Traits", "CreateFrame", "Enum", "GameFontNormal",
	"GameTooltip", "GetInstanceInfo", "GetTime", "InCombatLockdown", "InterfaceOptions_AddCategory",
	"IsActiveBattlefieldArena", "IsInInstance", "IsStealthed", "LibStub", "MenuUtil", "NO", "PixelUtil",
	"STANDARD_TEXT_FONT", "Settings", "ShowUIPanel", "StaticPopup_Show", "UIDropDownMenu_AddButton",
	"UIDropDownMenu_CreateInfo", "UIDropDownMenu_Initialize", "UIDropDownMenu_SetText", "UIParent",
	"UNKNOWNOBJECT", "UnitCanAttack", "UnitExists", "UnitGUID", "UnitIsDeadOrGhost", "UnitIsPlayer",
	"UnitIsUnit", "UnitName", "UnitPower", "UnitPowerMax", "YES", "hooksecurefunc", "wipe",
}
files["tests/"] = { std = "+max", globals = { "_G" }, allow_defined_top = true, ignore = { "111", "112", "113", "121", "122", "131", "143" } }
