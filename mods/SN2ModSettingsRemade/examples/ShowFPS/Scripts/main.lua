-- ShowFPS: the smallest example for SN2ModSettingsRemade. One toggle on the Mods tab that runs a console
-- command: "stat fps" shows the frame rate in the corner, "stat none" hides it (and any other stats).
local UEHelpers = require("UEHelpers")
local NAME = "ShowFPS"

-- Register: copy our settings list (registration.lua, in this mod's folder) to where SN2ModSettingsRemade
-- looks. Nothing happens if SN2ModSettingsRemade isn't installed: its folder isn't there.
local source = io.open("./ue4ss/Mods/" .. NAME .. "/registration.lua", "r")
if source then
	local text = source:read("a")
	source:close()
	local copy = io.open("./ue4ss/Mods/SN2ModSettingsRemade/registrations/" .. NAME .. ".lua", "w")
	if copy then
		copy:write(text)
		copy:close()
	end
end

-- Follow the toggle: run the command whenever what's shown differs from what's wanted.
local shown = false
LoopInGameThreadWithDelay(500, function()
	local want = false
	pcall(function()
		want = ModRef:GetSharedVariable("SN2ModSettingsRemade/" .. NAME .. "/Show") == true
	end)
	if want ~= shown then
		local pc = UEHelpers.GetPlayerController()
		if pc and pc:IsValid() then
			local command = want and "stat fps" or "stat none"
			UEHelpers.GetKismetSystemLibrary():ExecuteConsoleCommand(pc, command, pc)
			print('[ShowFPS] ran "' .. command .. '"\n')
			shown = want
		end
	end
	return false
end)
