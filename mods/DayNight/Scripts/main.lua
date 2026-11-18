--[[
DayNight: an example mod for SN2ModSettingsRemade, the mod that adds a "Mods" tab to Subnautica 2's
Settings screen.

What it does in the game: it changes how the day goes. The day can be made longer or shorter, nights
can be skipped, and the clock can be stopped at noon, midnight, dawn or dusk.

What it's for: showing other mod makers how a mod puts its settings on the Mods tab and reads them
back. Every kind of row the Mods tab has is used once.

How a mod and SN2ModSettingsRemade work together, in three steps (each one is a part of this file):
  1. The mod hands over a list of its settings (the file registration.lua, in this mod's folder).
  2. The player changes settings on the Mods tab. SN2ModSettingsRemade saves them, and puts each
     value where every mod can read it ("shared variables": like a notice board all mods can see).
  3. The mod reads the values from that board and does something with them.

A few words used below:
  - "Lua" is the language this file is written in. Lines starting with two dashes (--) are notes for
    people, like this one; the game skips them.
  - A "function" is a named list of steps that can be run whenever it's needed.
  - "local" just means "this name belongs to this file only".
  - UE4SS is the tool that loads mods like this one into the game.
]]

-- The name of this mod. It must be the same as the mod's folder name (ue4ss/Mods/DayNight).
local NAME = "DayNight"

------------------------------------------------------------------------------------------------------
-- STEP 1: hand our list of settings to SN2ModSettingsRemade.
--
-- Our list is in registration.lua, in our own folder. SN2ModSettingsRemade looks for lists in its
-- "registrations" folder, so we copy the file there each time the game starts. (If SN2ModSettingsRemade
-- isn't installed, that folder doesn't exist, nothing gets copied, and DayNight simply uses its defaults.)
------------------------------------------------------------------------------------------------------
local source = io.open("./ue4ss/Mods/" .. NAME .. "/registration.lua", "r") -- open our list to read it
if source then
	local text = source:read("a") -- read the whole file into "text"
	source:close()
	local copy = io.open("./ue4ss/Mods/SN2ModSettingsRemade/registrations/" .. NAME .. ".lua", "w")
	if copy then -- only if the folder is there
		copy:write(text)
		copy:close()
	end
end

------------------------------------------------------------------------------------------------------
-- STEP 2: read the values the player picked.
--
-- SN2ModSettingsRemade puts each value on the shared notice board under a name made of three parts:
--     SN2ModSettingsRemade / DayNight / DayLength
-- (its own name, our mod's name, and the setting's "key" from registration.lua).
------------------------------------------------------------------------------------------------------

-- Look up one of our values on the board. Returns nothing (nil) if it isn't there yet.
local function get(key)
	local value = nil
	-- pcall means "try this, and don't stop the mod if it goes wrong"
	pcall(function()
		value = ModRef:GetSharedVariable("SN2ModSettingsRemade/" .. NAME .. "/" .. key)
	end)
	return value
end

-- Our copy of the values. It starts empty and is filled in by read_values() below.
local values = {}

-- The keys we read: the same keys as in registration.lua. (Headers have no value. The button doesn't
-- either: we read its press count separately, further down.) "SkipKey_Alt" is the second key a player
-- can pick for the keybind row: the settings mod adds "_Alt" to the key's name for it.
local KEYS = { "Style", "DayLength", "SkipNights", "Stop", "StopAt", "SkipKey", "SkipKey_Alt" }

-- SN2ModSettingsRemade also keeps a counter for each mod, "__changes", that goes up by one every time
-- one of that mod's values changes. Instead of re-reading all our values every time, we only re-read
-- them when the counter has moved. This is the counter we last read them at:
local counter_when_read = nil

-- Re-read our values if the counter moved. Answers true if they were re-read.
local function read_values()
	local counter = get("__changes") or 0 -- "or 0": no change has happened yet
	if counter == counter_when_read then
		return false -- nothing changed since last time
	end
	for _, key in ipairs(KEYS) do -- for each key in the list above...
		values[key] = get(key) -- ...copy its value from the board
	end
	-- If SN2ModSettingsRemade hasn't put anything on the board yet (it may start a moment after us),
	-- forget the counter, so we try again next time.
	if values.DayLength == nil then
		counter_when_read = nil
	else
		counter_when_read = counter
	end
	return true
end

------------------------------------------------------------------------------------------------------
-- STEP 3: do something with the values. Here: change the game's clock.
--
-- The game keeps the time of day in a "time of day component" (the game's clock). It counts the day
-- from 0 (midnight) to 1 (the next midnight): 0.5 is noon, 0.25 is six in the morning. It also knows
-- at which hour dawn, day, dusk and night begin.
------------------------------------------------------------------------------------------------------

-- Find the game's clock.
--
-- We never keep the clock itself from one check to the next: it is thrown away and made anew whenever
-- a game is loaded, and using a thrown-away one crashes the game. Instead we keep its "address" in the
-- game, a line of text like "/Game/Maps/.../L_Main:PersistentLevel.GameState.TimeOfDay", and ask the
-- game for whatever is at that address each time (StaticFindObject). That is quick, and when the clock
-- has been thrown away the answer is simply "nothing there".
--
-- Only then do we search for it with FindAllOf, which goes through every object of that kind in the
-- game. That search is slow, and doing it twice a second, all the time, is what made the game crash
-- now and then when we tested (UE4SS itself went wrong inside it). So we search at most every two
-- seconds, and only while we have no clock.
local clock_address = nil -- the clock's address, once found
local next_search = 0 -- when we may search again (the clock on the wall, in seconds: os.time)

local function find_clock()
	if clock_address then
		local clock = StaticFindObject(clock_address)
		if clock and clock:IsValid() then
			return clock
		end
		clock_address = nil -- thrown away: a game was loaded or left
	end
	if os.time() < next_search then
		return nil
	end
	next_search = os.time() + 2
	-- FindAllOf lists every object of that kind. One of them is a blank "template" (its name has
	-- "Default__" in it) that isn't the real clock, so we skip it.
	for _, clock in ipairs(FindAllOf("UWETimeOfDayComponent") or {}) do
		if clock:IsValid() and not clock:GetFullName():find("Default__", 1, true) then
			-- GetFullName gives "kind address": keep the part after the first space
			clock_address = clock:GetFullName():match("^%S+%s+(.+)$")
			return clock
		end
	end
	return nil -- no clock: we're in a menu, not in a game
end

-- Jump to the next morning: the hour the game's own "day" begins, turned into a part of a day.
local function skip_to_morning(clock)
	clock:SetTimeOfDay(clock.HourStartDay / 24)
end

-- These remember a few things between one check and the next:
local stopped_by_us = false -- did we stop the clock? (so we know to start it again)
local last_clock = nil -- which clock we last set the day length on (a new game has a new one)
local presses_seen = nil -- how many times the "Skip" button had been pressed when we last looked
local key_pressed = false -- set to true when the player presses the skip key (see below)

-- Look at the settings and the clock, and change the clock where needed. This is run twice a second.
local function update()
	local changed = read_values()
	local clock = find_clock()
	if clock == nil then
		return -- not in a game right now: nothing to do
	end

	-- The length of a day (the slider). Only set it when the value changed, or when a game has been
	-- loaded since last time (a new clock), not twice a second.
	local new_game = clock:GetAddress() ~= last_clock
	last_clock = clock:GetAddress()
	if (changed or new_game) and values.DayLength ~= nil then
		clock:SetDayLengthInMinutes(values.DayLength)
	end

	-- Stop the clock (a toggle), at the time the "Stop it at" choice says.
	if values.Stop == true then
		local where = { -- each option, as a part of a day
			["Noon"] = 0.5,
			["Midnight"] = 0.0,
			["Dawn"] = clock.HourStartDawn / 24,
			["Dusk"] = clock.HourStartDusk / 24,
		}
		clock:SetTimeOfDay(where[values.StopAt] or 0.5) -- "or 0.5": noon if anything is odd
		clock:FreezeTime(true)
		stopped_by_us = true
	elseif stopped_by_us then
		clock:FreezeTime(false) -- the toggle was turned off: let time run again
		stopped_by_us = false
	end

	-- Skip nights (a toggle). While the clock is stopped this has nothing to do.
	if values.SkipNights == true and values.Stop ~= true and clock:IsNight() then
		skip_to_morning(clock)
	end

	-- The "Skip" button. A button has no value; instead, SN2ModSettingsRemade counts its presses on the
	-- board under the button's key. When the count is higher than when we last looked, it was pressed.
	local presses = get("SkipNow") or 0
	if presses_seen ~= nil and presses > presses_seen then
		skip_to_morning(clock)
	end
	presses_seen = presses -- (the first time, this just notes the count: no skip at start-up)

	-- The skip key (see "listen_for_keys" below): it only notes that the key was pressed; we act here.
	if key_pressed then
		key_pressed = false
		skip_to_morning(clock)
	end
end

------------------------------------------------------------------------------------------------------
-- The keybind row: listening for the key the player picked.
--
-- UE4SS can run a function whenever a key is pressed in the game ("RegisterKeyBind"). It can't be
-- told to stop listening, so we start listening to each key the first time it's picked, and when a
-- key is pressed we check whether it's still one of the player's skip keys.
--
-- The Mods tab saves keys by their name in the game engine ("F8", "Home"). UE4SS names them in capital
-- letters ("F8", "HOME"); a few keys have other names there, and those just aren't listened for.
------------------------------------------------------------------------------------------------------
local listening = {} -- the keys we already listen to

local function listen_for_keys()
	for _, name in ipairs({ values.SkipKey, values.SkipKey_Alt }) do -- the first and second key
		if type(name) == "string" and name ~= "" and not listening[name] then
			local key = Key[name:upper()] -- the same key, in UE4SS's list of keys
			if key ~= nil then
				RegisterKeyBind(key, function()
					-- this runs when the key is pressed: is it (still) one of our skip keys?
					if name == values.SkipKey or name == values.SkipKey_Alt then
						key_pressed = true
					end
				end)
				print("[DayNight] listening for the key " .. name .. "\n")
			else
				print("[DayNight] can't listen for the key " .. name .. " (UE4SS has no key by that name)\n")
			end
			listening[name] = true -- don't try this key again
		end
	end
end

------------------------------------------------------------------------------------------------------
-- Start: run update() and listen_for_keys() twice a second (every 500 milliseconds), for as long as
-- the game runs. "return false" means "keep going".
------------------------------------------------------------------------------------------------------
LoopInGameThreadWithDelay(500, function()
	update()
	listen_for_keys()
	return false
end)

print("[DayNight] started\n")
