-- SN2ModSettingsRemade: the Mods tab on the game's Settings screen.
--
-- Rules kept everywhere in this file:
--   * every engine object is checked with IsValid() before anything is called on it (a call on a null
--     object crashes natively, and pcall can't catch that);
--   * nothing is touched until every member and class needed has been found (fail soft: one log line);
--   * everything created is attached to the screen; nothing is ever removed from it (ours or the game's).
--
-- The screen object lives for the whole session (opening Settings again re-activates the same one), so
-- the tab is built once per screen; each later opening re-reads the values and appends sections for mods
-- that registered since.
local M = {}

local ctx, store, log

local SCREEN_CLASS = "/Game/Blueprints/UI/Settings2/WBP_Settings2Screen.WBP_Settings2Screen_C"
local BUTTON_ROW_CLASS = "/Game/Blueprints/UI/Settings2/WBP_SettingsButton.WBP_SettingsButton_C"
-- The settings button row binds three events of its inner button with the same signature; only _1 is
-- the click (tested 2026-11-17: a pure click fires _1 alone). _0 and _2 come with the mouse moving over
-- and off it, and hooking them made hovering a "Reset to defaults" row reset that mod.
local BUTTON_ROW_EVENTS = {
	"BndEvt__WBP_SettingsButton_WBP_GenericButtonBig_K2Node_ComponentBoundEvent_1_CommonButtonBaseClicked__DelegateSignature",
}
local TAB_NAME = "Mods"
local HOOKS_VAR = "SN2ModSettingsRemade/__hooks"
local LIVE_VAR = "SN2ModSettingsRemade/__live"
local DEBUG_MISSING_FILE = "./ue4ss/Mods/SN2ModSettingsRemade/debug_missing.txt"

-- Key names offered by keybind rows (Unreal key names). A saved key not in here is added to its row.
local KEY_NAMES = {
	"None",
	"F1",
	"F2",
	"F3",
	"F4",
	"F5",
	"F6",
	"F7",
	"F8",
	"F9",
	"F10",
	"F11",
	"F12",
	"A",
	"B",
	"C",
	"D",
	"E",
	"F",
	"G",
	"H",
	"I",
	"J",
	"K",
	"L",
	"M",
	"N",
	"O",
	"P",
	"Q",
	"R",
	"S",
	"T",
	"U",
	"V",
	"W",
	"X",
	"Y",
	"Z",
	"Zero",
	"One",
	"Two",
	"Three",
	"Four",
	"Five",
	"Six",
	"Seven",
	"Eight",
	"Nine",
	"NumPadZero",
	"NumPadOne",
	"NumPadTwo",
	"NumPadThree",
	"NumPadFour",
	"NumPadFive",
	"NumPadSix",
	"NumPadSeven",
	"NumPadEight",
	"NumPadNine",
	"Insert",
	"Delete",
	"Home",
	"End",
	"PageUp",
	"PageDown",
	"Tab",
	"CapsLock",
	"Backspace",
	"Enter",
	"LeftShift",
	"RightShift",
	"LeftControl",
	"RightControl",
	"LeftAlt",
	"RightAlt",
	"Up",
	"Down",
	"Left",
	"Right",
	"Hyphen",
	"Equals",
	"LeftBracket",
	"RightBracket",
	"Semicolon",
	"Apostrophe",
	"Comma",
	"Period",
	"Slash",
	"Backslash",
	"Tilde",
	"MiddleMouseButton",
	"ThumbMouseButton",
	"ThumbMouseButton2",
}

local state = {
	hooked = false, -- the screen's BP_OnActivated hook is in
	button_hooked = false,
	hooks = {}, -- { path, pre, post } registered by this generation
	pending = nil, -- a screen that was activated: handled on the next tick
	screen = nil, -- the screen our tab is on
	screen_path = nil,
	box = nil, -- our tab's content
	shown = {}, -- mod ids that have a section
	rows = {}, -- every row we follow
	by_addr = {}, -- button rows by widget address
	clicks = {}, -- button rows clicked since the last tick
	regs = {},
	warned = {},
	ticks = 0,
	in_game = false, -- the screen our tab is on belongs to a loaded game (main_menu_only rows are text)
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

local function warn_once(key, msg)
	if state.warned[key] then
		return
	end
	state.warned[key] = true
	log.warn(msg)
end

local function path_of(o)
	-- "Class /Path.To:Object" -> "/Path.To:Object"
	local full = o:GetFullName()
	return full:match("^%S+%s+(.+)$") or full
end

local function is_live(o)
	if not valid(o) then
		return false
	end
	local ok, full = pcall(function()
		return o:GetFullName()
	end)
	return ok and type(full) == "string" and full:find("/Engine/Transient", 1, true) ~= nil
end

-- Is this Settings screen the one of a loaded game, or the main menu's? The main menu's player drives a
-- camera pawn whose class name has "MainMenu" in it (the bridge's swim/walk checks rely on the same).
-- No pawn at all (dying, loading) counts as in game unless the world's name says menu: when unsure the
-- main_menu_only rows are locked, never the other way round.
local function in_game_of(scr)
	local function name_of(o)
		local ok, n = pcall(function()
			return o:GetFName():ToString()
		end)
		return ok and n or ""
	end
	local owner
	pcall(function()
		owner = scr:GetOwningPlayer()
	end)
	if not valid(owner) then
		return true
	end
	local pawn
	pcall(function()
		pawn = owner.Pawn
	end)
	if valid(pawn) then
		local cls
		pcall(function()
			cls = pawn:GetClass()
		end)
		if valid(cls) and name_of(cls):find("MainMenu", 1, true) then
			return false
		end
		return true
	end
	local world
	pcall(function()
		world = owner:GetWorld()
	end)
	if valid(world) and name_of(world):find("Menu", 1, true) then
		return false
	end
	return true
end

local function addr(o)
	local ok, a = pcall(function()
		return o:GetAddress()
	end)
	if ok then
		return a
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- hooks (kept few; their ids are handed to the next generation so it can try to remove them)

local function remember_hooks()
	local parts = {}
	for _, h in ipairs(state.hooks) do
		parts[#parts + 1] = h.path .. "|" .. tostring(h.pre) .. "|" .. tostring(h.post)
	end
	store.set_shared(HOOKS_VAR, table.concat(parts, "\n"))
end

local function drop_old_hooks()
	local old = store.get_shared(HOOKS_VAR)
	if type(old) ~= "string" or old == "" then
		return
	end
	local removed, failed, why = 0, 0, nil
	for line in old:gmatch("[^\n]+") do
		local path, pre, post = line:match("^(.-)|(%-?%d+)|(%-?%d+)$")
		if path then
			local ok, err = pcall(UnregisterHook, path, tonumber(pre), tonumber(post))
			if ok then
				removed = removed + 1
			else
				failed = failed + 1
				why = err
			end
		end
	end
	store.set_shared(HOOKS_VAR, "")
	log.info(
		"hooks of the previous generation: "
			.. removed
			.. " removed"
			.. (failed > 0 and (", " .. failed .. " could not be (they stay and do nothing): " .. tostring(why)) or "")
	)
end

local function hook(path, fn)
	local ok, pre, post = pcall(RegisterHook, path, fn)
	if not ok then
		return false, pre
	end
	state.hooks[#state.hooks + 1] = { path = path, pre = pre, post = post }
	remember_hooks()
	return true
end

---------------------------------------------------------------------------------------------------
-- what building needs: all found, or nothing is touched

local function debug_missing()
	-- test aid: a member named in this file is treated as missing (acceptance test 8)
	local f = io.open(DEBUG_MISSING_FILE, "rb")
	if not f then
		return nil
	end
	local s = f:read("a") or ""
	f:close()
	s = s:match("^%s*(.-)%s*$")
	if s == "" then
		return nil
	end
	return s
end

local function collect(scr)
	local miss = debug_missing()
	local need = {}
	local function get(label, fn)
		if label == miss then
			error(label .. " (named in debug_missing.txt)", 0)
		end
		local ok, v = pcall(fn)
		if not ok or not valid(v) then
			error(label, 0)
		end
		need[label] = v
		return v
	end
	local ok, err = pcall(function()
		get("WidgetBlueprintLibrary", function()
			return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
		end)
		get("VerticalBox class", function()
			return StaticFindObject("/Script/UMG.VerticalBox")
		end)
		get("HorizontalBox class", function()
			return StaticFindObject("/Script/UMG.HorizontalBox")
		end)
		get("TabSelectors", function()
			return scr.TabSelectors
		end)
		get("TabButtonGroup", function()
			return scr.TabButtonGroup
		end)
		get("Contents", function()
			return scr.Contents
		end)
		get("WidgetTree", function()
			return scr.WidgetTree
		end)
		get("InfoSelector", function()
			return scr.InfoSelector
		end)
		get("SidePanel_CommonTextBlock", function()
			return scr.SidePanel_CommonTextBlock
		end)
		local acc = get("WBP_TabAccessibilitySettings", function()
			return scr.WBP_TabAccessibilitySettings
		end)
		get("UWESimpleGrid", function()
			return acc.UWESimpleGrid
		end)
		get("TextScaleToggle", function()
			return acc.TextScaleToggle
		end)
		get("ApplicationScaleSlider", function()
			return acc.ApplicationScaleSlider
		end)
		get("ColorDeficiencyRotator", function()
			return acc.ColorDeficiencyRotator
		end)
		get("WBP_SettingsButton", function()
			return acc.WBP_SettingsButton
		end)
		get("Line", function()
			return acc.Line
		end)
		get("heading text", function()
			-- Accessibility: Overlay_0 > VerticalBox_0 > HorizontalBox_0 > the heading's text block
			local root = acc.WidgetTree.RootWidget
			if not valid(root) then
				return nil
			end
			local vb = root:GetChildAt(0)
			if not valid(vb) then
				return nil
			end
			local hb = vb:GetChildAt(0)
			if not valid(hb) then
				return nil
			end
			return hb:GetChildAt(0)
		end)
		local mapping = scr.TabMapping
		if mapping == nil or #mapping < 1 then
			error("TabMapping", 0)
		end
		need.owner = scr:GetOwningPlayer()
		if not valid(need.owner) then
			error("owning player", 0)
		end
	end)
	if not ok then
		return nil, tostring(err)
	end
	return need
end

---------------------------------------------------------------------------------------------------
-- widgets

local function ftext(s)
	return FText(tostring(s))
end

local function template_copy(need, src)
	local o = StaticConstructObject(src:GetClass(), need.WidgetTree, FName("None"), 0, 0, false, false, src)
	if not valid(o) then
		error("copy of " .. src:GetFName():ToString() .. " failed", 0)
	end
	return o
end

local function create(need, src)
	local o = need.WidgetBlueprintLibrary:Create(state.screen, src:GetClass(), need.owner)
	if not valid(o) then
		error("could not create a " .. src:GetClass():GetFName():ToString(), 0)
	end
	return o
end

local function add_heading(need, box, text, top)
	local head = StaticConstructObject(need["HorizontalBox class"], need.WidgetTree)
	if not valid(head) then
		error("HorizontalBox", 0)
	end
	local t = template_copy(need, need["heading text"])
	t:SetText(ftext(text))
	local s1 = head:AddChild(t)
	if valid(s1) then
		s1:SetPadding({ Left = 0, Top = 0, Right = 20, Bottom = 0 })
		s1:SetVerticalAlignment(2)
	end
	local line = template_copy(need, need.Line)
	local s2 = head:AddChild(line)
	if valid(s2) then
		s2:SetSize({ SizeRule = 1, Value = 1.0 })
		s2:SetVerticalAlignment(2)
	end
	local hs = box:AddChild(head)
	if valid(hs) then
		hs:SetPadding({ Left = 0, Top = top, Right = 0, Bottom = 10 })
	end
end

local function add_note(need, box, text)
	local t = template_copy(need, need.SidePanel_CommonTextBlock)
	t:SetText(ftext(text))
	local s = box:AddChild(t)
	if valid(s) then
		s:SetPadding({ Left = 50, Top = 5, Right = 0, Bottom = 10 })
	end
end

local function add_grid(need, box)
	local grid = StaticConstructObject(need.UWESimpleGrid:GetClass(), need.WidgetTree)
	if not valid(grid) then
		error("grid", 0)
	end
	grid:SetNumColumns(1)
	grid:SetSlotPadding({ Left = 0, Top = 5, Right = 0, Bottom = 5 })
	box:AddChild(grid)
	return grid
end

local function index_of(list, v)
	for i, x in ipairs(list) do
		if x == v then
			return i
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- rows: reading and showing values

local function quantise(s, raw)
	local v = s.min + math.floor((raw - s.min) / s.step + 0.5) * s.step
	v = math.max(s.min, math.min(s.max, v))
	if s.format == "integer" then
		return math.floor(v + 0.5)
	end
	return tonumber(string.format("%.6g", v))
end

local function read_row(row)
	local w = row.widget
	if not valid(w) then
		return nil
	end
	if row.kind == "toggle" then
		return w.Value == true
	elseif row.kind == "slider" then
		local raw = tonumber(w.Value)
		if not raw then
			return nil
		end
		return quantise(row.s, raw)
	elseif row.kind == "rotator" then
		-- the row's own Value (it follows the player's clicks). Not the inner rotator's index: that one
		-- ignores a selection made before the widget is drawn and reads 0, which was taken for the
		-- player's choice and saved the first option (fixed 2026-11-17)
		local i = tonumber(w.Value)
		if not i then
			return nil
		end
		return row.options[i + 1]
	end
	return nil
end

-- A main_menu_only setting as text, for a loaded game: "Title: value".
local function key_text(v)
	if v == nil or v == "" then
		return "None"
	end
	return tostring(v)
end

local function text_of(row)
	local s, values = row.s, row.reg.values or {}
	local v = values[s.key]
	local shown
	if s.type == "toggle" then
		shown = v == true and "On" or "Off"
	elseif s.type == "slider" then
		v = tonumber(v) or s.default
		if s.format == "integer" then
			shown = string.format("%d", math.floor(v + 0.5))
		elseif s.format == "percent" then
			shown = string.format("%d%%", math.floor(v * 100 + 0.5))
		else
			shown = string.format("%g", v)
		end
	elseif s.type == "keybind" then
		shown = key_text(v)
		local alt = values[s.key .. "_Alt"]
		if alt ~= nil and alt ~= "" then
			shown = shown .. ", " .. key_text(alt)
		end
	elseif s.type == "button" then
		return s.title .. " (from the main menu)"
	else
		shown = v ~= nil and tostring(v) or ""
	end
	return s.title .. ": " .. shown
end

local function show_row(row, v)
	local w = row.widget
	if row.kind == "text" then
		if valid(w) and row.s and row.s.title then
			pcall(function()
				w:SetText(ftext(text_of(row)))
			end)
		end
		return
	end
	if not valid(w) or v == nil then
		return
	end
	if row.kind == "toggle" then
		pcall(function()
			w:SetValue(v == true)
		end)
		w.Value = v == true
	elseif row.kind == "slider" then
		w.Value = v
		pcall(function()
			w.WBP_Slider:SetValue(v)
		end)
	elseif row.kind == "rotator" then
		local i = index_of(row.options, v)
		if not i then
			row.options[#row.options + 1] = v
			local opts = w.Options
			opts[#opts + 1] = ftext(v)
			pcall(function()
				w.WBP_Rotator_65:PopulateTextLabels(w.Options)
			end)
			i = #row.options
		end
		w.Value = i - 1
		-- the row's own setter (Value, CurrentOption and the inner rotator together); the inner one too
		pcall(function()
			w:SetSelectedOption(i - 1)
		end)
		pcall(function()
			w.WBP_Rotator_65:SetSelectedItem(i - 1)
		end)
	end
	-- what a read will give back: a slider is compared on its step grid, so a saved value between
	-- steps is kept until the player moves the slider
	if row.kind == "slider" and type(v) == "number" then
		row.shown = quantise(row.s, v)
	else
		row.shown = v
	end
end

local function stored_to_shown(row)
	local v = row.reg.values and row.reg.values[row.value_key]
	if row.is_key and (v == nil or v == "") then
		return "None"
	end
	return v
end

local function shown_to_stored(row, v)
	if row.is_key and v == "None" then
		return ""
	end
	return v
end

-- What a row was built for. A rescan that changes it leaves the row dead (greyed) until the screen is
-- made again (next game session).
local function signature(s)
	if not s then
		return ""
	end
	local parts = { s.type }
	if s.main_menu_only then
		parts[#parts + 1] = "main_menu_only"
	end
	if s.type == "slider" then
		parts[#parts + 1] = table.concat({ s.min, s.max, s.step, s.format }, ",")
	elseif s.type == "choice" then
		parts[#parts + 1] = table.concat(s.options, "\1")
	end
	return table.concat(parts, ":")
end

---------------------------------------------------------------------------------------------------
-- rows: making them

local function base_row(need, src, title, description)
	local w = create(need, src)
	w.Title = ftext(title)
	w.Description = ftext(description or "")
	return w
end

local function attach(grid, w, title)
	grid:AddChild(w)
	pcall(function()
		w.WBP_SettingsLabel:SetTitle(ftext(title))
	end)
end

local function make_rows(need, grid, reg, s)
	local made = {}
	if s.main_menu_only and state.in_game then
		-- text only: nothing to click, so nothing can change it in a loaded game
		local t = template_copy(need, need.SidePanel_CommonTextBlock)
		grid:AddChild(t)
		made[#made + 1] = { kind = "text", widget = t }
	elseif s.type == "toggle" then
		local w = base_row(need, need.TextScaleToggle, s.title, s.description)
		w.Value = reg.values[s.key] == true
		attach(grid, w, s.title)
		made[#made + 1] = { kind = "toggle", widget = w }
	elseif s.type == "slider" then
		local w = base_row(need, need.ApplicationScaleSlider, s.title, s.description)
		w["Min Value"] = s.min
		w["Max Value"] = s.max
		w["Step Size (Rounding)"] = s.step
		w["Display As Percentage"] = s.format == "percent"
		w.Value = reg.values[s.key]
		attach(grid, w, s.title)
		pcall(function()
			w.WBP_Slider:SetMinValue(s.min, true)
			w.WBP_Slider:SetMaxValue(s.max, true)
		end)
		made[#made + 1] = { kind = "slider", widget = w }
	elseif s.type == "choice" or s.type == "keybind" then
		local function rotator(title, options, value_key, is_key)
			local w = base_row(need, need.ColorDeficiencyRotator, title, s.description)
			local opts = w.Options
			for i, o in ipairs(options) do
				opts[i] = ftext(o)
			end
			attach(grid, w, title)
			pcall(function()
				w.WBP_Rotator_65:PopulateTextLabels(w.Options)
			end)
			made[#made + 1] =
				{ kind = "rotator", widget = w, options = options, value_key = value_key, is_key = is_key }
		end
		if s.type == "choice" then
			local o = {}
			for i, x in ipairs(s.options) do
				o[i] = x
			end
			rotator(s.title, o, s.key, false)
		else
			local o1, o2 = {}, {}
			for i, x in ipairs(KEY_NAMES) do
				o1[i] = x
				o2[i] = x
			end
			rotator(s.title, o1, s.key, true)
			rotator(s.title .. " (second key)", o2, s.key .. "_Alt", true)
		end
	elseif s.type == "button" then
		local w = base_row(need, need.WBP_SettingsButton, s.title, s.description)
		w.ButtonText = ftext(s.button_text)
		attach(grid, w, s.title)
		pcall(function()
			w.WBP_GenericButtonBig:SetText(ftext(s.button_text))
		end)
		made[#made + 1] = { kind = "button", widget = w, action = "button" }
	end
	for _, r in ipairs(made) do
		r.reg, r.s, r.sig = reg, s, signature(s)
		r.value_key = r.value_key or s.key
	end
	return made
end

local function add_reset_row(need, grid, reg)
	local w = base_row(
		need,
		need.WBP_SettingsButton,
		"Reset to defaults",
		"Puts every setting of " .. reg.display .. " back to its default."
	)
	w.ButtonText = ftext("Reset")
	attach(grid, w, "Reset to defaults")
	pcall(function()
		w.WBP_GenericButtonBig:SetText(ftext("Reset"))
	end)
	return { kind = "button", widget = w, action = "reset", reg = reg }
end

local function heading_text(reg)
	if reg.version then
		return reg.display .. " - v" .. reg.version
	end
	return reg.display
end

local function update_enabled(reg)
	for _, row in ipairs(state.rows) do
		if
			row.reg == reg
			and row.kind ~= "text"
			and not row.dead
			and row.s
			and row.s.enabled_by
			and valid(row.widget)
		then
			local v = reg.values[row.s.enabled_by]
			local on = v == true or (type(v) == "number" and v ~= 0)
			if row.enabled ~= on then
				pcall(function()
					row.widget:SetIsEnabled(on)
				end)
				row.enabled = on
			end
		end
	end
end

local function add_row(row)
	-- the path is what we keep while Settings is closed (no object references then)
	local ok, p = pcall(path_of, row.widget)
	row.path = ok and p or nil
	state.rows[#state.rows + 1] = row
	if row.kind == "button" then
		local a = addr(row.widget)
		if a then
			state.by_addr[a] = row
		end
	else
		show_row(row, stored_to_shown(row))
	end
end

-- One mod's section, appended to our box.
local function add_section(need, box, reg, first)
	add_heading(need, box, heading_text(reg), first and 0 or 30)
	local grid = add_grid(need, box)
	local has_values = false
	for _, s in ipairs(reg.settings) do
		if s.type == "header" then
			add_heading(need, box, s.title, 15)
			grid = add_grid(need, box)
		else
			for _, row in ipairs(make_rows(need, grid, reg, s)) do
				add_row(row)
			end
			-- Reset only for values it can change (in a game, main_menu_only ones are text)
			if s.has_value and not (s.main_menu_only and state.in_game) then
				has_values = true
			end
		end
	end
	if has_values and not reg.builtin then
		add_row(add_reset_row(need, grid, reg))
	end
	state.shown[reg.id] = true
	update_enabled(reg)
end

---------------------------------------------------------------------------------------------------
-- remembering what we built (a hot reload hands it to the next generation by object path)

local function record_live()
	local ids = {}
	for id in pairs(state.shown) do
		ids[#ids + 1] = id
	end
	local lines = { state.screen_path or "", state.box_path or "", table.concat(ids, "\1") }
	for _, row in ipairs(state.rows) do
		local p = row.path
		if p then
			lines[#lines + 1] = table.concat({
				p,
				row.reg.id,
				row.s and row.s.key or "",
				row.value_key or "",
				row.kind,
				row.action or "",
				row.is_key and "1" or "",
				row.sig or "",
			}, "\t")
		end
	end
	store.set_shared(LIVE_VAR, table.concat(lines, "\n"))
end

local hook_button_rows -- below

---------------------------------------------------------------------------------------------------
-- the three ways a screen gets our tab: built, refreshed, taken over

local function build(scr, need)
	state.in_game = in_game_of(scr)
	state.regs = ctx.rescan()
	state.rows, state.by_addr, state.clicks, state.shown = {}, {}, {}, {}
	-- the content, built before anything is attached to the screen
	local box = StaticConstructObject(need["VerticalBox class"], need.WidgetTree)
	if not valid(box) then
		error("VerticalBox", 0)
	end
	for i, reg in ipairs(state.regs) do
		add_section(need, box, reg, i == 1)
		if reg.builtin and #state.regs == 1 then
			add_note(need, box, "No installed mod has registered settings.")
		end
	end
	-- attach: content, then the button, its group entry and its name
	need.Contents:AddChild(box)
	local btn = need.WidgetBlueprintLibrary:Create(scr, need.InfoSelector:GetClass(), need.owner)
	if not valid(btn) then
		error("tab button", 0)
	end
	btn.DefaultText = ftext(TAB_NAME)
	btn.IconTextureNormal = need.InfoSelector.IconTextureNormal
	need.TabSelectors:AddChild(btn)
	pcall(function()
		btn.TextBlock_Tab:SetText(ftext(TAB_NAME))
	end)
	need.TabButtonGroup:AddWidget(btn)
	local mapping = scr.TabMapping
	mapping[#mapping + 1] = FName(TAB_NAME)
	state.box = box
	state.box_path = path_of(box)
	state.screen_path = path_of(scr)
	record_live()
	state.reshow = true
	log.info(
		"Mods tab added: "
			.. (#state.regs - 1)
			.. " mod(s), "
			.. #state.rows
			.. " rows ("
			.. (state.in_game and "in game: main_menu_only rows are text" or "main menu")
			.. ")"
	)
end

-- A later opening of the same screen: values from disk, sections for new mods, rows whose setting
-- changed shape greyed out.
local function refresh(scr, need)
	state.regs = ctx.rescan()
	local by_id = {}
	for _, r in ipairs(state.regs) do
		by_id[r.id] = r
	end
	local dead = 0
	for _, row in ipairs(state.rows) do
		if not row.dead then
			local reg = by_id[row.reg.id]
			local s = reg and row.s and reg.by_key[row.s.key]
			if row.action == "reset" then
				if not reg then
					row.dead = true
				end
			elseif not s or signature(s) ~= row.sig then
				row.dead = true
			else
				row.s = s
			end
			if row.dead then
				dead = dead + 1
				pcall(function()
					row.widget:SetIsEnabled(false)
				end)
			elseif row.kind ~= "button" then
				show_row(row, stored_to_shown(row))
			end
		end
	end
	if dead > 0 then
		log.info(dead .. " row(s) no longer match their registration: greyed out until the next game session")
	end
	local added = 0
	for _, reg in ipairs(state.regs) do
		if not state.shown[reg.id] then
			if need and valid(state.box) then
				add_section(need, state.box, reg, false)
				added = added + 1
			end
		else
			update_enabled(reg)
		end
	end
	if added > 0 then
		log.info(added .. " newly registered mod(s) added to the Mods tab")
	end
	state.reshow = true
	record_live()
end

local function adopt(scr)
	local live = store.get_shared(LIVE_VAR)
	if type(live) ~= "string" or live == "" then
		return false
	end
	local lines = {}
	for line in (live .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = line
	end
	if lines[1] ~= path_of(scr) then
		return false
	end
	local box = lines[2] ~= "" and StaticFindObject(lines[2]) or nil
	state.screen, state.screen_path = scr, lines[1]
	state.box = valid(box) and box or nil
	state.box_path = lines[2] ~= "" and lines[2] or nil
	state.in_game = in_game_of(scr)
	state.regs = ctx.rescan()
	local by_id = {}
	for _, r in ipairs(state.regs) do
		by_id[r.id] = r
	end
	state.rows, state.by_addr, state.clicks, state.shown = {}, {}, {}, {}
	for id in (lines[3] or ""):gmatch("[^\1]+") do
		state.shown[id] = true
	end
	local kept, lost = 0, 0
	for i = 4, #lines do
		local p, modid, key, vkey, kind, action, is_key, sig =
			lines[i]:match("^(.-)\t(.-)\t(.-)\t(.-)\t(.-)\t(.-)\t(.-)\t(.*)$")
		local w = p and StaticFindObject(p)
		local reg = modid and by_id[modid]
		if valid(w) and reg then
			local s = key ~= "" and reg.by_key[key] or nil
			local row = {
				widget = w,
				path = p,
				reg = reg,
				s = s,
				value_key = vkey ~= "" and vkey or key,
				kind = kind,
				action = action ~= "" and action or nil,
				is_key = is_key == "1",
				sig = sig,
			}
			if kind == "rotator" then
				row.options = {}
				local src = (s and s.type == "choice") and s.options or KEY_NAMES
				for j, o in ipairs(src) do
					row.options[j] = o
				end
				-- keys or options the last generation had added to this rotator
				pcall(function()
					local opts = w.Options
					for j = #row.options + 1, #opts do
						row.options[j] = opts[j]:ToString()
					end
				end)
			end
			if not s and action ~= "reset" then
				row.s = { key = key }
			end
			state.rows[#state.rows + 1] = row
			if kind == "button" then
				local a = addr(w)
				if a then
					state.by_addr[a] = row
				end
			end
			kept = kept + 1
		else
			lost = lost + 1
		end
	end
	log.info(
		"took over the Mods tab built before the reload: "
			.. kept
			.. " rows"
			.. (lost > 0 and (", " .. lost .. " gone") or "")
	)
	return true
end

-- While Settings isn't activated we hold no engine objects at all, only paths: a screen that dies (the
-- pause menu's, when the game goes back to the main menu) can't leave us pointing at freed memory.
local function release()
	for _, row in ipairs(state.rows) do
		row.widget = nil
	end
	state.screen, state.box, state.by_addr = nil, nil, {}
end

-- Find our widgets again by path (the screen itself comes alive from the hook). Returns the time taken.
local function reacquire(scr)
	local t0 = os.clock()
	state.screen = scr
	state.box = state.box_path and StaticFindObject(state.box_path) or nil
	if not valid(state.box) then
		state.box = nil
	end
	local found, lost = 0, 0
	for _, row in ipairs(state.rows) do
		local w = row.path and StaticFindObject(row.path) or nil
		if valid(w) then
			row.widget = w
			found = found + 1
			if row.kind == "button" then
				local a = addr(w)
				if a then
					state.by_addr[a] = row
				end
			end
		else
			row.widget = nil
			row.dead = true
			lost = lost + 1
		end
	end
	return (os.clock() - t0) * 1000, found, lost
end

-- Once per session: os.clock() counts whole milliseconds, so time 100 passes of the same lookups.
local measured = false
local function measure_lookups()
	if measured then
		return
	end
	measured = true
	local paths = {}
	for _, row in ipairs(state.rows) do
		if row.path then
			paths[#paths + 1] = row.path
		end
	end
	local t0 = os.clock()
	for _ = 1, 100 do
		for _, p in ipairs(paths) do
			StaticFindObject(p)
		end
	end
	local ms = (os.clock() - t0) * 1000
	log.info(
		string.format(
			"lookup timing: %d paths x 100 passes = %.0f ms, so %.3f ms per pass, %.1f us per lookup",
			#paths,
			ms,
			ms / 100,
			#paths > 0 and ms * 1000 / (100 * #paths) or 0
		)
	)
end

-- A screen was activated (first opening, a later one, or after a dialog over it closed).
local function on_screen(scr)
	local p = path_of(scr)
	if p == state.screen_path then
		local ms, found, lost = reacquire(scr)
		local t1 = os.clock()
		refresh(scr, collect(scr))
		log.info(
			string.format(
				"reopened: %d rows found again in %.0f ms%s; refresh (rescan, disk, show) %.0f ms",
				found,
				ms,
				lost > 0 and (", " .. lost .. " gone") or "",
				(os.clock() - t1) * 1000
			)
		)
		measure_lookups()
		return
	end
	if adopt(scr) then
		refresh(scr, collect(scr))
		hook_button_rows()
		return
	end
	local need, why = collect(scr)
	if not need then
		warn_once(
			"collect:" .. why,
			"no Mods tab: the Settings screen has no "
				.. why
				.. " (a game update?). Saved values and shared variables still work."
		)
		return
	end
	state.screen = scr
	local ok, err = pcall(build, scr, need)
	if not ok then
		warn_once("build:" .. tostring(err), "building the Mods tab failed: " .. tostring(err))
		state.screen, state.screen_path = nil, nil
		return
	end
	hook_button_rows()
end

---------------------------------------------------------------------------------------------------
-- following the rows

local function set(reg, key, v)
	if store.set_value(reg, key, v) then
		log.debug(reg.id .. "." .. key .. " = " .. tostring(v))
		if reg.builtin and key == "LogChanges" then
			log.verbose = v == true
		end
		return true
	end
	return false
end

local function show_value(reg, key)
	for _, row in ipairs(state.rows) do
		local mine = row.value_key == key or (row.kind == "text" and row.s and row.s.key .. "_Alt" == key)
		if row.reg == reg and mine and row.kind ~= "button" and not row.dead then
			show_row(row, stored_to_shown(row))
		end
	end
end

-- In a loaded game a main_menu_only setting is never changed from here: not by a preset, not by Reset.
local function locked(s)
	return s and s.main_menu_only and state.in_game
end

local function after_change(reg, key)
	if reg.presets then
		if key == reg.preset_key then
			local p = reg.presets[reg.values[key]]
			if p then
				for k, v in pairs(p) do
					local s = reg.by_key[k]
					if s and not locked(s) and set(reg, k, store.coerce(s, v)) then
						show_value(reg, k)
					end
				end
			end
		else
			local listed = false
			for _, p in pairs(reg.presets) do
				if p[key] ~= nil then
					listed = true
					break
				end
			end
			if listed then
				local want = store.matching_preset(reg) or reg.custom_option
				if want and want ~= reg.values[reg.preset_key] then
					set(reg, reg.preset_key, want)
					show_value(reg, reg.preset_key)
				end
			end
		end
	end
	update_enabled(reg)
end

local function reset(reg)
	for _, s in ipairs(reg.settings) do
		if s.has_value and not locked(s) then
			set(reg, s.key, s.default)
			show_value(reg, s.key)
			if s.type == "keybind" then
				set(reg, s.key .. "_Alt", s.default_alt)
				show_value(reg, s.key .. "_Alt")
			end
		end
	end
	update_enabled(reg)
	log.info(reg.id .. ": reset to defaults" .. (state.in_game and " (main_menu_only settings kept)" or ""))
end

local function press(row)
	if row.dead then
		return
	end
	if row.action == "reset" then
		reset(row.reg)
	else
		-- a button setting: its shared variable counts presses
		local name = store.var_name(row.reg, row.s.key)
		local n = (tonumber(store.get_shared(name)) or 0) + 1
		store.set_shared(name, n)
		store.bump(row.reg)
		log.debug(row.reg.id .. "." .. row.s.key .. " pressed (" .. n .. ")")
	end
end

local function poll()
	for _, row in ipairs(state.rows) do
		if row.kind ~= "button" and not row.dead then
			local v = read_row(row)
			if v ~= nil and v ~= row.shown then
				row.shown = v
				if set(row.reg, row.value_key, shown_to_stored(row, v)) then
					after_change(row.reg, row.value_key)
				end
			end
		end
	end
	local clicks = state.clicks
	state.clicks = {}
	for _, row in ipairs(clicks) do
		press(row)
	end
	for _, reg in ipairs(state.regs) do
		if reg.dirty then
			reg.dirty = false
			store.save_values(reg)
		end
	end
end

hook_button_rows = function()
	if state.button_hooked then
		return
	end
	if not valid(StaticFindObject(BUTTON_ROW_CLASS)) then
		return
	end
	state.button_hooked = true
	local last = {}
	local n = 0
	for _, ev in ipairs(BUTTON_ROW_EVENTS) do
		local ok, err = hook(BUTTON_ROW_CLASS .. ":" .. ev, function(self)
			if not ctx.is_current() then
				return
			end
			local a = addr(self:get())
			local row = a and state.by_addr[a]
			if not row then
				return
			end
			-- count a click once even if the event comes twice
			local now = os.clock()
			if last[a] and now - last[a] < 0.25 then
				return
			end
			last[a] = now
			state.clicks[#state.clicks + 1] = row
		end)
		if ok then
			n = n + 1
		else
			log.debug("no hook on " .. ev .. ": " .. tostring(err))
		end
	end
	if n == 0 then
		log.warn("buttons on the Mods tab won't respond: no click event of WBP_SettingsButton could be hooked")
	end
end

---------------------------------------------------------------------------------------------------

local function find_screen()
	for _, w in ipairs(FindAllOf("WBP_Settings2Screen_C") or {}) do
		if is_live(w) then
			return w
		end
	end
	return nil
end

local function try_hook()
	if not valid(StaticFindObject(SCREEN_CLASS)) then
		return false
	end
	local ok, err = hook(SCREEN_CLASS .. ":BP_OnActivated", function(self)
		if not ctx.is_current() then
			return
		end
		local scr = self:get()
		if is_live(scr) then
			state.pending = scr
		end
	end)
	if not ok then
		warn_once("hook", "no Mods tab: could not hook the Settings screen: " .. tostring(err))
		return false
	end
	state.hooked = true
	log.debug("hooked " .. SCREEN_CLASS)
	-- A screen that exists already: made before the hook was in (the class loads with the first
	-- opening), or carrying the last generation's tab. Take it over, or build if it is open now.
	local scr = find_screen()
	if scr then
		local active = false
		pcall(function()
			active = scr:IsActivated()
		end)
		if adopt(scr) then
			hook_button_rows()
			if not active then
				release()
			end -- closed: keep the paths only
		elseif active then
			state.pending = scr
		end
	end
	return true
end

function M.init(c)
	ctx, store, log = c, c.store, c.log
	drop_old_hooks()
	try_hook()
end

-- Called every 150 ms. Returns true while the screen is open (the caller then skips its disk checks).
function M.tick()
	state.ticks = state.ticks + 1
	if not state.hooked then
		if state.ticks % 14 == 0 then
			try_hook()
		end
		return false
	end
	if state.pending then
		local scr = state.pending
		state.pending = nil
		if is_live(scr) then
			local ok, err = pcall(on_screen, scr)
			if not ok then
				warn_once("open:" .. tostring(err), "opening the Mods tab: " .. tostring(err))
			end
		end
	end
	-- state.screen is only ever held from an activation (the hook's own object, alive then) until the
	-- first tick that finds it no longer activated
	if not state.screen then
		return false
	end
	local active = false
	if valid(state.screen) then
		pcall(function()
			active = state.screen:IsActivated()
		end)
	end
	if not active then
		if #state.clicks > 0 then
			poll()
		end -- a click in the last moment: rows are still alive now
		release()
		return false
	end
	if state.reshow then
		-- a tick after building or refreshing the widgets exist: show the values again so the rotators'
		-- own display takes them (before that it ignores a selection)
		state.reshow = false
		for _, row in ipairs(state.rows) do
			if row.kind ~= "button" and not row.dead and row.widget then
				show_row(row, stored_to_shown(row))
			end
		end
	end
	poll()
	return true
end

return M
