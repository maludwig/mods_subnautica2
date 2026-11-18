-- SN2ModSettingsRemade: a "Mods" tab on Subnautica 2's Settings screen for every mod's settings.
-- Public domain (the Unlicense). Inspired by the now-removed original SN2ModSettings, thank you to Just-Chaldea for the
-- original. Written from a specification, without the original's code.
--
-- Files: store.lua (registrations, saved values, shared variables: no UI), ui.lua (the tab),
-- save.lua (which save is played), log.lua.
local VERSION = "0.2.1"

local log = require("log")
local store = require("store")
store.VERSION = VERSION

log.info("v" .. VERSION .. " starting")

-- Hot reload (Ctrl+R) starts a new Lua state while the game runs; the old state's loop and hooks may
-- outlive it. Every generation takes a number from a shared variable (those survive a reload), and
-- anything it left running checks that number and stops when it is no longer the newest.
local GEN_VAR = "SN2ModSettingsRemade/__generation"
local gen = (tonumber(store.get_shared(GEN_VAR)) or 0) + 1
store.set_shared(GEN_VAR, gen)
local function current()
	return tonumber(store.get_shared(GEN_VAR)) == gen
end

-- Stand down if the original SN2ModSettings is running (its enabled.txt and its scripts both there):
-- two tabs over the same files would fight. Our own folder's mods still get their values published.
local original = store.file_exists("./ue4ss/Mods/SN2ModSettings/enabled.txt")
	and store.file_exists("./ue4ss/Mods/SN2ModSettings/Scripts/main.lua")
if original then
	log.info(
		"the original SN2ModSettings is installed and enabled: no Mods tab from us, and legacy registrations are left to it"
	)
end

store.ensure_own_folders()

-- Which save is played is found again by every generation (a few ticks): until then mods are told
-- nothing is known, so none of them acts on the main menu's values in a save.
store.set_shared("SN2ModSettingsRemade/__save", "")
local save = require("save")

local regs = {}
-- One table per mod id for the whole session: a rescan updates it in place, so the UI's rows and the
-- disk check always look at the same values.
local known = {}

local function merge(r)
	local old = known[r.id]
	if not old then
		known[r.id] = r
		return r
	end
	-- what the files and the player gave us stays; what the registration says is replaced
	local KEEP = { values = true, extra = true, dirty = true, menu = true, unsaved = true, save_missing = true }
	for k in pairs(old) do
		if not KEEP[k] then
			old[k] = nil
		end
	end
	for k, v in pairs(r) do
		if not KEEP[k] then
			old[k] = v
		end
	end
	return old
end

local function load_all()
	local list = store.scan()
	for i, r in ipairs(list) do
		list[i] = merge(r)
	end
	if original then
		local only_ours = {}
		for _, r in ipairs(list) do
			if r.home.id == "ours" then
				only_ours[#only_ours + 1] = r
			end
		end
		list = only_ours
	end
	local before = {}
	for _, r in ipairs(regs) do
		before[r.id] = true
	end
	local names, fresh = {}, 0
	for _, r in ipairs(list) do
		if r.values then
			store.refresh_from_disk(r) -- publishes (and counts) only what changed on disk
		else
			store.load_values(r)
			store.publish_all(r)
		end
		store.record_missing(r) -- registered while a save is played that hasn't seen this mod yet
		if r.builtin then
			log.verbose = r.values.LogChanges == true
		end
		if not before[r.id] then
			fresh = fresh + 1
		end
		if not r.builtin then
			names[#names + 1] = r.id .. " (" .. r.home.id .. ", " .. #r.settings .. " settings)"
		end
	end
	regs = list
	if fresh > 0 then
		log.info(#names .. " mod(s) registered: " .. (#names > 0 and table.concat(names, ", ") or "none"))
	end
	return list
end

local ok, err = pcall(load_all)
if not ok then
	log.warn("loading registrations failed: " .. tostring(err))
end
store.set_shared("SN2ModSettingsRemade/__version", VERSION)

-- The tab. If anything it needs is missing, ui.lua says so once and the tab stays away; values are
-- already published above either way.
local ui = nil
if not original then
	local uok, mod = pcall(require, "ui")
	if uok then
		ui = mod
		local iok, ierr = pcall(ui.init, {
			store = store,
			log = log,
			version = VERSION,
			is_current = current,
			-- rescan when the screen opens: a registration written after startup shows up then
			rescan = function()
				local sok, serr = pcall(load_all)
				if not sok then
					log.warn("rescan failed: " .. tostring(serr))
				end
				return regs
			end,
		})
		if not iok then
			log.warn("the Mods tab is off: " .. tostring(ierr))
			ui = nil
		end
	else
		log.warn("the Mods tab is off: ui.lua did not load: " .. tostring(mod))
	end
end

-- One loop for everything. While the Settings screen is open, ui.tick() follows the rows; otherwise the
-- saved files are re-read every couple of seconds so a hand edit (or a mod writing its own file) is
-- published without the screen.
local TICK_MS = 150
local DISK_EVERY = 14 -- ticks: about two seconds
local SAVE_EVERY = 2 -- ticks: which save is played, checked every 300 ms
local n = 0
LoopInGameThreadWithDelay(TICK_MS, function()
	if not current() then
		return true
	end -- a newer generation runs: stop this loop for good
	n = n + 1
	if n % SAVE_EVERY == 0 then
		local sok, changed, where, id = pcall(save.check, n)
		if not sok then
			log.warn("save check: " .. tostring(changed))
		elseif changed then
			local in_game = where == "game"
			log.info(in_game and ("in a game: save " .. (id or "not saved yet")) or "at the main menu")
			local pok, perr = pcall(store.set_save, regs, in_game, id)
			if not pok then
				log.warn("switching to the save's values: " .. tostring(perr))
			end
		end
	end
	local busy = false
	if ui then
		local tok, res = pcall(ui.tick)
		if not tok then
			log.warn("tick: " .. tostring(res))
		else
			busy = res == true
		end
	end
	if not busy and n % DISK_EVERY == 0 then
		for _, r in ipairs(regs) do
			pcall(store.refresh_from_disk, r)
		end
	end
	return false
end)

log.info("ready (generation " .. gen .. ")")
