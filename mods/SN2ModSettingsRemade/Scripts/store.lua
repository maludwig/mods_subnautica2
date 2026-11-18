-- SN2ModSettingsRemade: registrations, saved values and shared variables. No UI in here: everything
-- in this file works even when the game's Settings screen can't be found.
--
-- Each mod has one "home": the folder its registration was found in. Its values are saved there and
-- published under that home's shared-variable prefix, never anywhere else.
local log = require("log")

local M = {}

local MODS_DIR = "./ue4ss/Mods/"

-- Registrations are scanned again at every opening of Settings: say each problem once per session.
local said = {}
local function once(fn, msg)
	if said[msg] then
		return
	end
	said[msg] = true
	fn(msg)
end

M.HOMES = {
	ours = {
		id = "ours",
		dir = MODS_DIR .. "SN2ModSettingsRemade/",
		prefix = "SN2ModSettingsRemade/",
	},
	legacy = {
		id = "legacy",
		dir = MODS_DIR .. "SN2ModSettings/",
		prefix = "SN2ModSettings/",
	},
}

M.SELF_ID = "SN2ModSettingsRemade"

local KNOWN_TYPES = { toggle = true, slider = true, keybind = true, choice = true, header = true, button = true }
-- types that carry a value
local VALUE_TYPES = { toggle = true, slider = true, keybind = true, choice = true }

---------------------------------------------------------------------------------------------------
-- small file helpers

local function file_exists(path)
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true
	end
	return false
end
M.file_exists = file_exists

local function read_file(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("a")
	f:close()
	return s
end

-- A folder exists if a file can be created in it.
local function dir_exists(dir)
	local probe = dir .. ".sn2msr_probe"
	local f = io.open(probe, "wb")
	if not f then
		return false
	end
	f:close()
	os.remove(probe)
	return true
end
M.dir_exists = dir_exists

-- Write, then replace: a reader never sees half a file.
local function write_file(path, text)
	local tmp = path .. ".tmp"
	local f, err = io.open(tmp, "wb")
	if not f then
		return false, err
	end
	f:write(text)
	f:close()
	if file_exists(path) then
		os.remove(path)
	end
	local ok, rerr = os.rename(tmp, path)
	if not ok then
		os.remove(tmp)
		return false, rerr
	end
	return true
end

local function mkdir(dir)
	-- only ever called for our own folders, and only when they are missing (first launch)
	local win = dir:gsub("^%./", ""):gsub("/+$", ""):gsub("/", "\\")
	os.execute('mkdir "' .. win .. '" >NUL 2>NUL')
	return dir_exists(dir)
end

-- Our own registrations/, saved/ and saves/ folders. Never the legacy folder: legacy mods make it
-- themselves (its saved/ is made on the first save into it, see save_values).
function M.ensure_own_folders()
	local home = M.HOMES.ours
	for _, sub in ipairs({ "registrations/", "saved/", "saves/" }) do
		local d = home.dir .. sub
		if not dir_exists(d) then
			if mkdir(d) then
				log.info("created " .. d)
			else
				log.warn("could not create " .. d)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- listing a folder's .lua files (UE4SS's IterateGameDirectories, no shell)

local function lua_files_in(home)
	local names = {}
	local ok, err = pcall(function()
		local dirs = IterateGameDirectories()
		local node = dirs.Game.Binaries.Win64.ue4ss.Mods
		local folder = home.dir:match("Mods/([^/]+)/$")
		node = node and node[folder]
		node = node and node.registrations
		if not node then
			return
		end
		for _, file in pairs(node.__files or {}) do
			local n = file.__name
			if type(n) == "string" and n:sub(-4):lower() == ".lua" then
				names[#names + 1] = n
			end
		end
	end)
	if not ok then
		log.warn("could not list " .. home.dir .. "registrations/: " .. tostring(err))
	end
	table.sort(names)
	return names
end

---------------------------------------------------------------------------------------------------
-- "is this mod installed?"

local mods_txt_cache = nil

local function mods_txt_enabled()
	if mods_txt_cache then
		return mods_txt_cache
	end
	local set = {}
	local text = read_file(MODS_DIR .. "mods.txt") or ""
	for line in text:gmatch("[^\r\n]+") do
		if not line:match("^%s*;") then
			local name, flag = line:match("^%s*([^:]-)%s*:%s*(%d+)")
			if name and name ~= "" and tonumber(flag) == 1 then
				set[name:lower()] = true
			end
		end
	end
	mods_txt_cache = set
	return set
end

local function installed(id)
	if type(id) ~= "string" or id == "" then
		return false
	end
	if file_exists(MODS_DIR .. id .. "/enabled.txt") then
		return true
	end
	return mods_txt_enabled()[id:lower()] == true
end
M.installed = installed

---------------------------------------------------------------------------------------------------
-- loading Lua data files (registrations, saved values) without giving them the mod's globals

local SAFE_ENV_KEYS =
	{ "string", "math", "table", "pairs", "ipairs", "tostring", "tonumber", "type", "select", "next", "unpack" }

local function data_env()
	local env = {}
	for _, k in ipairs(SAFE_ENV_KEYS) do
		env[k] = _G[k]
	end
	return env
end

local function load_data_file(path)
	local text = read_file(path)
	if not text then
		return nil, "missing"
	end
	text = text:gsub("^\239\187\191", "") -- a UTF-8 byte order mark from a text editor
	local chunk, err = load(text, "@" .. path, "t", data_env())
	if not chunk then
		return nil, err
	end
	local ok, res = pcall(chunk)
	if not ok then
		return nil, res
	end
	if type(res) ~= "table" then
		return nil, "did not return a table"
	end
	return res
end

---------------------------------------------------------------------------------------------------
-- registrations: read, check, normalise

local function str(v)
	if type(v) == "string" and v ~= "" then
		return v
	end
	return nil
end
local function num(v)
	if type(v) == "number" and v == v then
		return v
	end
	return nil
end

local function normalise_setting(raw, modid, keys_seen, position)
	if type(raw) ~= "table" then
		return nil, "a setting that is not a table"
	end
	local t = str(raw.type) and raw.type:lower() or nil
	if not t or not KNOWN_TYPES[t] then
		return nil, "unknown type " .. tostring(raw.type) .. " (key " .. tostring(raw.key) .. ")"
	end
	local key = str(raw.key)
	if not key then
		if t == "header" then
			-- headers need no key: name them by their place in the list (keys_seen is a set, so its
			-- length was always 0 and every header after the first was dropped as a duplicate: 0.1.1)
			key = "__header" .. tostring(position)
		else
			return nil, "a " .. t .. " without a key"
		end
	end
	if keys_seen[key] then
		return nil, "key " .. key .. " appears twice"
	end
	local s = {
		key = key,
		type = t,
		title = str(raw.title) or (t == "header" and "" or key),
		description = str(raw.description) or "",
		enabled_by = str(raw.enabled_by),
		reload = raw.reload == true,
		-- ours: changeable only from the main menu's Settings; in a loaded game the row is shown as text
		main_menu_only = raw.main_menu_only == true and t ~= "header",
		-- ours: each save keeps its own value (taken from the main menu's when the save is first seen)
		per_save = raw.per_save == true and VALUE_TYPES[t] == true,
		has_value = VALUE_TYPES[t] == true,
	}
	if t == "toggle" then
		s.default = raw.default == true
	elseif t == "slider" then
		s.format = (raw.format == "integer" or raw.format == "percent") and raw.format or "float"
		s.min = num(raw.min) or 0
		s.max = num(raw.max) or (s.format == "percent" and 1 or 100)
		if s.min > s.max then
			s.min, s.max = s.max, s.min
		end
		local step = num(raw.step)
		if not step or step <= 0 then
			step = (s.format == "integer") and 1 or 0.1
		end
		s.step = step
		local d = num(raw.default) or s.min
		s.default = math.max(s.min, math.min(s.max, d))
	elseif t == "keybind" then
		s.default = str(raw.default) or ""
		s.default_alt = str(raw.default_alt) or ""
	elseif t == "choice" then
		local opts = {}
		if type(raw.options) == "table" then
			for _, o in ipairs(raw.options) do
				if type(o) == "string" or type(o) == "number" then
					opts[#opts + 1] = tostring(o)
				end
			end
		end
		if #opts == 0 then
			return nil, "choice " .. key .. " has no options"
		end
		s.options = opts
		s.default = opts[1]
		for _, o in ipairs(opts) do
			if o == raw.default then
				s.default = o
			end
		end
	elseif t == "button" then
		s.button_text = str(raw.button_text) or s.title
	end
	if s.reload then
		local note = "Takes effect after the next load."
		s.description = (s.description ~= "" and (s.description .. " ") or "") .. note
	end
	if s.main_menu_only or s.per_save then
		local note
		if s.main_menu_only and s.per_save then
			note = "Set in the main menu for new games; each save keeps the value it started with."
		elseif s.main_menu_only then
			note = "Can only be changed from the main menu."
		else
			note = "Each save keeps its own value; the main menu's is for new games."
		end
		s.description = (s.description ~= "" and (s.description .. " ") or "") .. note
	end
	keys_seen[key] = true
	return s
end

local function normalise_registration(raw, file_id, home)
	local name = str(raw.name)
	if not name then
		return nil, "no name"
	end
	local reg = {
		id = name,
		file_id = file_id,
		home = home,
		display = str(raw.display) or name,
		version = str(raw.version) or (type(raw.version) == "number" and tostring(raw.version)) or nil,
		nexus_id = (type(raw.nexus_id) == "string" or type(raw.nexus_id) == "number") and tostring(raw.nexus_id) or nil,
		settings = {},
		by_key = {},
	}
	local keys_seen = {}
	for i, rs in ipairs(type(raw.settings) == "table" and raw.settings or {}) do
		local s, why = normalise_setting(rs, name, keys_seen, i)
		if s then
			reg.settings[#reg.settings + 1] = s
			reg.by_key[s.key] = s
			if s.per_save then
				reg.has_per_save = true
			end
		else
			once(log.info, name .. ": setting " .. i .. " skipped: " .. why)
		end
	end
	-- enabled_by must name another setting of this mod that has a value
	for _, s in ipairs(reg.settings) do
		if s.enabled_by then
			local dep = reg.by_key[s.enabled_by]
			if not dep or not dep.has_value or dep == s then
				once(
					log.info,
					name
						.. ": "
						.. s.key
						.. ".enabled_by names "
						.. s.enabled_by
						.. ", which isn't a setting here: ignored"
				)
				s.enabled_by = nil
			end
		end
	end
	-- presets (ours): a choice named by preset_key; each preset lists values for other settings
	local pk = str(raw.preset_key)
	if pk and type(raw.presets) == "table" then
		local chooser = reg.by_key[pk]
		if chooser and chooser.type == "choice" then
			reg.preset_key = pk
			reg.presets = {}
			for option, values in pairs(raw.presets) do
				if type(option) == "string" and type(values) == "table" then
					local p = {}
					for k, v in pairs(values) do
						local target = reg.by_key[k]
						if target and target.has_value and k ~= pk then
							p[k] = v
						end
					end
					reg.presets[option] = p
				end
			end
			for _, o in ipairs(chooser.options) do
				if o == "Custom" then
					reg.custom_option = o
				end
			end
		else
			once(log.info, name .. ": preset_key " .. pk .. " is not a choice: presets ignored")
		end
	end
	return reg
end

-- The built-in registration for our own section (always shown first).
local function own_registration()
	local reg = normalise_registration({
		name = M.SELF_ID,
		settings = {
			{
				key = "LogChanges",
				title = "Log every change",
				type = "toggle",
				default = false,
				description = "Write a line to UE4SS.log for every value changed on this tab. For mod authors.",
			},
		},
	}, M.SELF_ID, M.HOMES.ours)
	reg.display = "Mod Settings"
	reg.version = M.VERSION
	reg.builtin = true
	return reg
end

-- Find every registration that counts. Ours wins over legacy for the same mod id.
function M.scan()
	mods_txt_cache = nil
	local found, order = {}, {}
	for _, homeid in ipairs({ "ours", "legacy" }) do
		local home = M.HOMES[homeid]
		for _, fname in ipairs(lua_files_in(home)) do
			local file_id = fname:sub(1, -5)
			local path = home.dir .. "registrations/" .. fname
			local raw, err = load_data_file(path)
			if not raw then
				once(log.warn, path .. ": " .. tostring(err))
			elseif not str(raw.name) then
				once(log.info, path .. ": no name, ignored")
			elseif raw.name == M.SELF_ID or raw.name == "SN2ModSettings" then
				-- the settings mods' own files (the original wrote one for itself): not a mod section
			elseif not (installed(file_id) or installed(raw.name)) then
				log.debug(path .. ": " .. raw.name .. " is not installed, skipped")
			else
				local reg, why = normalise_registration(raw, file_id, home)
				if not reg then
					once(log.warn, path .. ": " .. tostring(why))
				elseif found[reg.id] then
					once(
						log.info,
						reg.id
							.. " is registered in both folders: using "
							.. found[reg.id].home.dir
							.. ", ignoring "
							.. path
					)
				else
					found[reg.id] = reg
					order[#order + 1] = reg
				end
			end
		end
	end
	table.sort(order, function(a, b)
		local x, y = a.display:lower(), b.display:lower()
		if x ~= y then
			return x < y
		end
		return a.id < b.id
	end)
	table.insert(order, 1, own_registration())
	return order
end

---------------------------------------------------------------------------------------------------
-- values

local function saved_path(reg)
	return reg.home.dir .. "saved/" .. reg.id .. ".lua"
end
M.saved_path = saved_path

-- The value to use for a setting, given what the saved file holds (wrong type: the default).
local function coerce(s, v)
	if v == nil then
		return s.default
	end
	if s.type == "toggle" then
		if type(v) == "boolean" then
			return v
		end
		return s.default
	elseif s.type == "slider" then
		if type(v) == "number" and v == v then
			return v
		end
		return s.default
	elseif s.type == "keybind" then
		if type(v) == "string" then
			return v
		end
		return s.default
	elseif s.type == "choice" then
		if type(v) == "number" then
			v = tostring(v)
		end
		if type(v) == "string" then
			for _, o in ipairs(s.options) do
				if o == v then
					return o
				end
			end
		end
		return s.default
	end
	return nil
end
M.coerce = coerce

---------------------------------------------------------------------------------------------------
-- per-save values (ours). While a save is played, a per_save setting's value comes from
-- saves/<SaveId>.<ModId>.lua (always in our own folder, whichever home the mod has) instead of the
-- mod's saved file; the saved file keeps the main menu's value, the one new games start with.
-- reg.values is always the value in effect, so shared variables (what mods read) follow the save.

M.save = { in_game = false, id = nil }

local function save_path(reg, id)
	return M.HOMES.ours.dir .. "saves/" .. id .. "." .. reg.id .. ".lua"
end
M.save_path = save_path

-- The setting a value key belongs to (a keybind's second key is <key>_Alt).
local function setting_of(reg, k)
	local s = reg.by_key[k]
	if s then
		return s
	end
	local base = type(k) == "string" and k:match("^(.+)_Alt$")
	s = base and reg.by_key[base]
	if s and s.type == "keybind" then
		return s
	end
	return nil
end

local function is_per_save(reg, k)
	local s = setting_of(reg, k)
	return s ~= nil and s.per_save == true
end
M.is_per_save = is_per_save

-- Read the saved file into reg.values (and reg.extra: keys we don't know, kept as they are). In a save,
-- per_save values are then taken from the save's file (the main menu's stay in reg.menu).
function M.load_values(reg)
	local raw = load_data_file(saved_path(reg))
	if type(raw) ~= "table" then
		raw = {}
	end
	local function fill(values, t, only_per_save)
		for _, s in ipairs(reg.settings) do
			if s.has_value and (not only_per_save or s.per_save) then
				if not only_per_save or t[s.key] ~= nil then
					values[s.key] = coerce(s, t[s.key])
				end
				if s.type == "keybind" then
					local alt = t[s.key .. "_Alt"]
					if type(alt) == "string" then
						values[s.key .. "_Alt"] = alt
					elseif not only_per_save then
						values[s.key .. "_Alt"] = s.default_alt
					end
				end
			end
		end
	end
	local values, extra = {}, {}
	fill(values, raw, false)
	reg.menu = {}
	reg.save_missing = false
	if reg.has_per_save then
		for k, v in pairs(values) do
			if is_per_save(reg, k) then
				reg.menu[k] = v
			end
		end
		local unsaved = M.save.in_game and reg.unsaved or nil
		if M.save.in_game and M.save.id then
			local sraw = load_data_file(save_path(reg, M.save.id))
			if type(sraw) == "table" then
				fill(values, sraw, true)
				unsaved = nil
			else
				-- first time this save is seen: it keeps the main menu's values (and whatever was changed
				-- in it before the game gave it an id); record_missing writes them
				reg.save_missing = true
			end
		end
		-- a new game the game hasn't given an id yet: changes made in it so far
		for k, v in pairs(unsaved or {}) do
			values[k] = v
		end
	end
	for k, v in pairs(raw) do
		if
			type(k) == "string"
			and values[k] == nil
			and not reg.by_key[k]
			and (type(v) == "number" or type(v) == "boolean" or type(v) == "string")
		then
			extra[k] = v
		end
	end
	reg.values, reg.extra = values, extra
	return values
end

local IDENT = "^[%a_][%w_]*$"
local LUA_WORDS = {}
for w in
	("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"):gmatch(
		"%a+"
	)
do
	LUA_WORDS[w] = true
end

local function fmt_key(k)
	if k:match(IDENT) and not LUA_WORDS[k] then
		return k
	end
	return "[" .. string.format("%q", k) .. "]"
end

local function fmt_value(v)
	if type(v) == "boolean" then
		return tostring(v)
	end
	if type(v) == "number" then
		if math.type(v) == "integer" then
			return tostring(v)
		end
		if v == math.floor(v) and math.abs(v) < 1e15 then
			return string.format("%d", v)
		end
		return string.format("%.10g", v)
	end
	return string.format("%q", tostring(v))
end

-- The legacy format: a comment line, then `return {`, one `key = value,` per line in key order, `}`.
local function write_values(path, all, comment)
	local keys = {}
	for k in pairs(all) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local out = { comment, "return {" }
	for _, k in ipairs(keys) do
		out[#out + 1] = "    " .. fmt_key(k) .. " = " .. fmt_value(all[k]) .. ","
	end
	out[#out + 1] = "}"
	local ok, err = write_file(path, table.concat(out, "\n") .. "\n")
	if not ok then
		log.warn("could not save " .. path .. ": " .. tostring(err))
	end
	return ok
end

-- The save's own file: its per_save values.
local function save_save_file(reg)
	local mine = {}
	for k, v in pairs(reg.values or {}) do
		if is_per_save(reg, k) then
			mine[k] = v
		end
	end
	return write_values(
		save_path(reg, M.save.id),
		mine,
		"-- Generated by SN2ModSettingsRemade: " .. reg.id .. "'s settings kept with save " .. M.save.id .. "."
	)
end

function M.save_values(reg)
	local all = {}
	for k, v in pairs(reg.extra or {}) do
		all[k] = v
	end
	for k, v in pairs(reg.values or {}) do
		all[k] = v
	end
	-- the saved file keeps the main menu's values of per_save settings
	for k, v in pairs(reg.menu or {}) do
		all[k] = v
	end
	local comment =
		"-- Generated by SN2ModSettingsRemade. You can edit this file; it is read again when the Settings screen opens."
	-- A legacy mod makes SN2ModSettings/registrations/ itself, but maybe not saved/ (the original did
	-- that): make it, inside the folder the mod already made, the first time a value is saved there.
	local dir = reg.home.dir .. "saved/"
	if reg.home.id == "legacy" and not dir_exists(dir) and dir_exists(reg.home.dir .. "registrations/") then
		if mkdir(dir) then
			log.info("created " .. dir)
		end
	end
	local ok = write_values(saved_path(reg), all, comment)
	if reg.has_per_save and M.save.in_game and M.save.id then
		ok = save_save_file(reg) and ok
	end
	return ok
end

---------------------------------------------------------------------------------------------------
-- shared variables

local function set_shared(name, value)
	local ok, err = pcall(function()
		ModRef:SetSharedVariable(name, value)
	end)
	if not ok then
		log.warn("SetSharedVariable " .. name .. ": " .. tostring(err))
	end
end
M.set_shared = set_shared

function M.get_shared(name)
	local v = nil
	pcall(function()
		v = ModRef:GetSharedVariable(name)
	end)
	return v
end

function M.var_name(reg, key)
	return reg.home.prefix .. reg.id .. "/" .. key
end

-- Publish one value (and bump the mod's change counter unless told not to).
function M.publish(reg, key, value)
	if value == nil then
		return
	end
	set_shared(M.var_name(reg, key), value)
end

function M.bump(reg)
	local name = M.var_name(reg, "__changes")
	local n = tonumber(M.get_shared(name)) or 0
	set_shared(name, n + 1)
end

function M.publish_all(reg)
	for k, v in pairs(reg.values or {}) do
		M.publish(reg, k, v)
	end
end

-- Re-read a mod's saved file; publish what changed behind our back. Returns true if anything did.
function M.refresh_from_disk(reg)
	local before = reg.values or {}
	local copy = {}
	for k, v in pairs(before) do
		copy[k] = v
	end
	M.load_values(reg)
	local changed = false
	for k, v in pairs(reg.values) do
		if copy[k] ~= v then
			changed = true
			M.publish(reg, k, v)
		end
	end
	if changed then
		M.bump(reg)
	end
	return changed
end

-- Change one value from the UI: remember, publish, bump. Saving is batched by the caller.
function M.set_value(reg, key, value)
	reg.values = reg.values or {}
	if reg.values[key] == value then
		return false
	end
	reg.values[key] = value
	if is_per_save(reg, key) then
		if not M.save.in_game then
			reg.menu = reg.menu or {}
			reg.menu[key] = value
		elseif not M.save.id then
			reg.unsaved = reg.unsaved or {}
			reg.unsaved[key] = value
		end
	end
	M.publish(reg, key, value)
	M.bump(reg)
	reg.dirty = true
	return true
end

-- The menu/game state or the save changed: values in effect follow it, the shared variables with them.
-- A save seen for the first time gets its file now, holding the values it starts with. Then
-- __save is published: "" in the main menu, the SaveId in a game, "unsaved" in a new game the game
-- hasn't given an id yet; and __save_new, true when this save's values were just recorded.
-- After load_values: a save seen for the first time gets its file. Returns true if it was written.
function M.record_missing(reg)
	if not (reg.save_missing and M.save.in_game and M.save.id) then
		return false
	end
	reg.save_missing = false
	reg.unsaved = nil
	save_save_file(reg)
	log.info(reg.id .. ": settings recorded for save " .. M.save.id)
	return true
end

function M.set_save(regs, in_game, id)
	local was_unsaved = M.save.in_game and not M.save.id
	M.save.in_game, M.save.id = in_game, id
	local recorded = false
	for _, reg in ipairs(regs) do
		if reg.has_per_save and reg.values then
			-- changes made in an unsaved new game are kept only into that game's first id
			if not (was_unsaved and in_game) then
				reg.unsaved = nil
			end
			M.refresh_from_disk(reg)
			if M.record_missing(reg) then
				recorded = true
			end
			reg.unsaved = (in_game and not id) and reg.unsaved or nil
		end
	end
	set_shared("SN2ModSettingsRemade/__save_new", recorded)
	set_shared("SN2ModSettingsRemade/__save", in_game and (id or "unsaved") or "")
	return recorded
end

-- Presets: the option that matches the current values, or nil.
function M.matching_preset(reg)
	if not reg.presets then
		return nil
	end
	local chooser = reg.by_key[reg.preset_key]
	for _, option in ipairs(chooser.options) do
		local p = reg.presets[option]
		if p then
			local all = true
			for k, v in pairs(p) do
				local s = reg.by_key[k]
				if coerce(s, v) ~= reg.values[k] then
					all = false
					break
				end
			end
			if all then
				return option
			end
		end
	end
	return nil
end

return M
