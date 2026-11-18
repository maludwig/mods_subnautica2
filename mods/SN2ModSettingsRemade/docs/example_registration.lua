-- An example registration file: what a mod puts in
--   ue4ss/Mods/SN2ModSettingsRemade/registrations/ExampleMod.lua
-- (or, for mods written for the original SN2ModSettings, ue4ss/Mods/SN2ModSettings/registrations/).
-- The file returns one table. This example is made up for this project; it shows the format only.
--
-- The first block uses only what the original understood (slider, toggle, keybind). The second block
-- uses what SN2ModSettingsRemade adds (choice, header, button, reload, default_alt, presets, per_save,
-- main_menu_only). Unknown
-- types are skipped by both, so a file can use the new kinds and still load with the original.
return {
	name = "ExampleMod", -- the mod's id: its folder name under ue4ss/Mods
	display = "Example Mod", -- the section heading
	version = "1.0.0", -- shown as "Example Mod - v1.0.0"
	-- nexus_id = "123",               -- optional
	-- github = "someone/example-mod", -- optional; SN2ModSettingsRemade ignores it (no network)

	settings = {
		-- a toggle: boolean
		{
			key = "Enabled",
			title = "Enable the mod",
			type = "toggle",
			default = true,
			description = "Text for the side panel while this row is highlighted.",
		},

		-- a slider: number; format is "float" (default), "integer" or "percent"
		{
			key = "Speed",
			title = "Swim speed",
			type = "slider",
			default = 1.0,
			min = 0.5,
			max = 3.0,
			step = 0.1,
			format = "float",
			description = "Greyed out while Enabled is off.",
			enabled_by = "Enabled",
		},

		{ key = "Count", title = "How many", type = "slider", default = 4, min = 1, max = 16, format = "integer" },

		-- a key binding: the saved value is the key's name; a second binding is saved as "Hotkey_Alt"
		{ key = "Hotkey", title = "Toggle key", type = "keybind", default = "F5" },

		-- ---- SN2ModSettingsRemade only ----------------------------------------------------------
		-- a sub-heading inside this mod's section
		{ type = "header", title = "Difficulty" },

		-- a choice of named options: the saved value is the option's text
		{
			key = "Difficulty",
			title = "Difficulty",
			type = "choice",
			options = { "Easy", "Normal", "Hard", "Custom" },
			default = "Normal",
			description = "Sets the two settings below. Changing one by hand switches this to Custom.",
		},
		{ key = "Damage", title = "Damage", type = "choice", options = { "x1", "x2", "x3" }, default = "x1" },
		-- reload = true adds "Takes effect after the next load." to the description
		{ key = "Hunger", title = "Hunger", type = "toggle", default = true, reload = true },
		-- per_save = true: each save keeps its own value (the main menu's is for new games);
		-- main_menu_only = true: changeable only from the main menu, shown as text in a game
		{
			key = "StartDepth",
			title = "Start depth",
			type = "choice",
			options = { "Surface", "Shallow", "Deep" },
			default = "Surface",
			per_save = true,
			main_menu_only = true,
		},

		{ type = "header", title = "Other" },

		-- a keybind's second key has its own default; "" means none (saved as "Hotkey2_Alt")
		{ key = "Hotkey2", title = "Second toggle key", type = "keybind", default = "F6", default_alt = "G" },

		-- a button: each press adds 1 to the shared variable SN2ModSettingsRemade/ExampleMod/Teleport
		{
			key = "Teleport",
			title = "Teleport home",
			type = "button",
			button_text = "Go",
			description = "Your mod watches the counter and acts when it goes up.",
		},
	},

	-- presets: the choice named by preset_key picks a row; every value in the row is set
	preset_key = "Difficulty",
	presets = {
		Easy = { Damage = "x1", Hunger = false },
		Normal = { Damage = "x1", Hunger = true },
		Hard = { Damage = "x3", Hunger = true },
	},
}
