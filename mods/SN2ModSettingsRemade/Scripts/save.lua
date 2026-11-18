-- SN2ModSettingsRemade: which save is being played. No UI in here.
--
-- The game's save subsystem (a game-instance subsystem, alive for the whole session) holds the loaded
-- save as SaveContext.SaveGameCollection; its ContainerInfo.SaveId is a GUID made when the save is
-- created. A new game started in a reused slot gets a new one; a save copied to another slot keeps it.
-- (Seen 2026-11-17: savegame_4 = E0EBB2B9-...; ActiveSave.MetaData.SaveId is a different GUID, one per
-- checkpoint, so it is not used.)
--
-- Where we are comes from the player's pawn: the main menu's is a camera pawn with "MainMenu" in its
-- class name, a loaded game's is the character. No pawn (loading, dying) changes nothing.
--
-- Rules as in ui.lua: every object checked with IsValid() before use; only paths are kept between checks,
-- and objects are found again by path, not by FindAllOf, while they last.
local M = {}

local SUBSYSTEM_CLASS = "UWESaveGameSubsystem"

local state = {
	sub_path = nil, -- the live subsystem's path (found once, looked up by path after that)
	next_find = 0, -- tick at which a lost subsystem is searched for again
	pc_path = nil, -- the local player controller's path, the same way
	next_pc_find = 0,
	where = nil, -- nil (not known yet), "menu", "game"
	id = nil, -- the SaveId while in a game, nil if the save has none yet
}

local function valid(o)
	if o == nil then
		return false
	end
	local ok, res = pcall(function()
		return o:IsValid()
	end)
	return ok and res == true
end

local function path_of(o)
	local full = o:GetFullName()
	return full:match("^%S+%s+(.+)$") or full
end

local function subsystem(tick)
	if state.sub_path then
		local s = StaticFindObject(state.sub_path)
		if valid(s) then
			return s
		end
		state.sub_path = nil
	end
	if tick < state.next_find then
		return nil
	end
	state.next_find = tick + 14 -- about two seconds
	for _, s in ipairs(FindAllOf(SUBSYSTEM_CLASS) or {}) do
		if valid(s) then
			local ok, p = pcall(path_of, s)
			if ok and not p:find("Default__", 1, true) then
				state.sub_path = p
				return s
			end
		end
	end
	return nil
end

-- "E0EBB2B9-4675FB33-9CEA25AA-14AE35B3", or nil (no save loaded, or a GUID of zeros: not made yet)
local function save_id(tick)
	local s = subsystem(tick)
	if not s then
		return nil
	end
	local id = nil
	pcall(function()
		local col = s.SaveContext.SaveGameCollection
		if not valid(col) then
			return
		end
		local g = col.ContainerInfo.SaveId
		-- the four parts come as signed 32-bit numbers: % makes them unsigned
		local U = 4294967296
		local a, b, c, d = g.A % U, g.B % U, g.C % U, g.D % U
		if a ~= 0 or b ~= 0 or c ~= 0 or d ~= 0 then
			id = string.format("%08X-%08X-%08X-%08X", a, b, c, d)
		end
	end)
	return id
end

-- The local player controller. Looked up by its path (cheap); FindAllOf only when it is gone (a level
-- change), at most every two seconds. (UEHelpers.GetPlayerController is a FindAllOf on every call:
-- FindAllOf is where UE4SS 3.0.1 crashed under load on 2026-11-17, so it isn't polled.)
local function player_controller(tick)
	if state.pc_path then
		local pc = StaticFindObject(state.pc_path)
		if valid(pc) then
			return pc
		end
		state.pc_path = nil
	end
	if tick < state.next_pc_find then
		return nil
	end
	state.next_pc_find = tick + 14
	for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
		local ok, mine = pcall(function()
			return pc:IsValid() and pc:IsLocalPlayerController()
		end)
		if ok and mine then
			local pok, p = pcall(path_of, pc)
			if pok and not p:find("Default__", 1, true) then
				state.pc_path = p
				return pc
			end
		end
	end
	return nil
end

-- "menu", "game", or nil (no pawn: loading, dying, starting up)
local function where_now(tick)
	local res = nil
	pcall(function()
		local pc = player_controller(tick)
		if not valid(pc) then
			return
		end
		local pawn = pc.Pawn
		if not valid(pawn) then
			return
		end
		local cls = pawn:GetClass()
		if valid(cls) and cls:GetFName():ToString():find("MainMenu", 1, true) then
			res = "menu"
		else
			res = "game"
		end
	end)
	return res
end

-- Called every few ticks. Returns changed, where, id: changed is true when the menu/game state or the
-- save changed since the last call.
function M.check(tick)
	local w = where_now(tick)
	if w == nil then
		return false, state.where, state.id
	end
	local id = nil
	if w == "game" then
		id = save_id(tick)
	end
	if w == state.where and id == state.id then
		return false, state.where, state.id
	end
	state.where, state.id = w, id
	return true, w, id
end

function M.current()
	return state.where, state.id
end

return M
