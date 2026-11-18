-- This file is DayNight's list of settings: what appears on the Mods tab of the game's Settings screen.
--
-- It isn't run by DayNight itself. When the game starts, DayNight copies it into the folder where
-- SN2ModSettingsRemade looks for these lists:
--     ue4ss/Mods/SN2ModSettingsRemade/registrations/DayNight.lua
-- SN2ModSettingsRemade then draws one row on the Mods tab for each entry below, saves what the player
-- picks, and tells DayNight about it.
--
-- The whole file is one table (the part between the outer { and }). Every row has:
--     key         the name DayNight uses to read the value (never shown to the player)
--     title       the text on the left of the row
--     type        what kind of row: toggle, slider, choice, keybind, button or header
--     default     the value before the player changes anything
--     description the text shown on the right while the row is highlighted
-- and some kinds have a few more fields, explained where they are used.
return {
	name = "DayNight", -- must be the same as the mod's folder name in ue4ss/Mods
	display = "Day and Night", -- the heading of this mod's section on the Mods tab
	version = "1.0.1", -- shown after the heading: "Day and Night - v1.0.1"

	settings = {
		-- A CHOICE row: the player steps through a list of named options with arrows.
		-- This one is special: it is the "preset" row (see preset_key at the bottom). Picking an option
		-- here changes several of the rows below at once.
		{
			key = "Style",
			title = "Style",
			type = "choice",
			options = { "Game default", "Long days", "Endless noon", "Custom" },
			default = "Game default",
			description = "Sets the rows below in one go. Change any of them by hand and this says Custom.",
		},

		-- A HEADER row: just a sub-heading with a line, to group the rows under it. It has no value.
		{ type = "header", title = "The day" },

		-- A SLIDER row: a number the player drags. min and max are the ends; format = "integer" means
		-- whole numbers only (others are "float" for decimals and "percent").
		{
			key = "DayLength",
			title = "Length of a day",
			type = "slider",
			format = "integer",
			min = 5,
			max = 120,
			default = 24,
			description = "Minutes of real time for one whole day and night. The game's own is 24.",
		},

		-- A TOGGLE row: on or off.
		{
			key = "SkipNights",
			title = "Skip nights",
			type = "toggle",
			default = false,
			description = "When night falls, jump straight to the next morning.",
		},

		{ type = "header", title = "Stopping the clock" },

		{
			key = "Stop",
			title = "Stop the clock",
			type = "toggle",
			default = false,
			description = "Hold the time of day where the next row says.",
		},

		-- enabled_by = "Stop" greys this row out while the "Stop" toggle above is off: picking where
		-- the clock stops only makes sense once it is stopped.
		{
			key = "StopAt",
			title = "Stop it at",
			type = "choice",
			options = { "Noon", "Midnight", "Dawn", "Dusk" },
			default = "Noon",
			enabled_by = "Stop",
			description = "Greyed out while the clock runs.",
		},

		{ type = "header", title = "Shortcuts" },

		-- A BUTTON row: pressing it doesn't store anything; DayNight is told it was pressed.
		{
			key = "SkipNow",
			title = "Skip to morning",
			type = "button",
			button_text = "Skip",
			description = "Jump to the next morning right now.",
		},

		-- A KEYBIND row: the player picks a key from a list. A second row underneath (added by the
		-- settings mod) lets them pick a second key too.
		{
			key = "SkipKey",
			title = "Skip to morning key",
			type = "keybind",
			default = "F8",
			description = "Press this key in the game to jump to the next morning.",
		},
	},

	-- The presets for the "Style" row: for each of its options, the values it sets. "Custom" isn't
	-- listed: the settings mod switches to it by itself when a listed value is changed by hand.
	preset_key = "Style",
	presets = {
		["Game default"] = { DayLength = 24, SkipNights = false, Stop = false },
		["Long days"] = { DayLength = 60, SkipNights = true, Stop = false },
		["Endless noon"] = { DayLength = 24, SkipNights = false, Stop = true, StopAt = "Noon" },
	},
}
