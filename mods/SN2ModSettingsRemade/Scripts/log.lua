-- Log lines to UE4SS.log, prefixed so they can be found among other mods' output.
local M = {}

M.verbose = false

local function out(level, msg)
	print(string.format("[SN2ModSettingsRemade] %s%s\n", level, tostring(msg)))
end

function M.info(msg)
	out("", msg)
end
function M.warn(msg)
	out("WARNING: ", msg)
end
function M.debug(msg)
	if M.verbose then
		out("debug: ", msg)
	end
end

return M
