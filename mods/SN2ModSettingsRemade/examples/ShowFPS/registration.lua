-- ShowFPS's settings for SN2ModSettingsRemade's Mods tab: one toggle. ShowFPS copies this file into
-- ue4ss/Mods/SN2ModSettingsRemade/registrations/ when the game starts.
return {
	name = "ShowFPS",
	display = "Show FPS",
	version = "1.0.0",
	settings = {
		{
			key = "Show",
			title = "Show the frame rate",
			type = "toggle",
			default = false,
			description = "Frames per second in the corner of the screen.",
		},
	},
}
