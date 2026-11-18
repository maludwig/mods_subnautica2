# SN2ModSettingsRemade for mod makers

How to put your UE4SS Lua mod's settings on the Mods tab, and read them back.

**The quickest way in is [DayNight](../DayNight/MODDING.md)**: a small mod made as an example, using
every feature below, with every line explained. Copy it and change it. For the very smallest version,
see [`examples/ShowFPS`](examples/ShowFPS/Scripts/main.lua) (one toggle, under 40 lines).

## How it works

1. Your mod hands over a list of its settings: a Lua file in
   `ue4ss/Mods/SN2ModSettingsRemade/registrations/<YourMod>.lua`.
2. The player changes them on the Mods tab. SN2ModSettingsRemade saves them to a file and publishes each
   one as a UE4SS **shared variable** (readable from every mod).
3. Your mod reads them.

Your mod works without SN2ModSettingsRemade installed too: the registration folder isn't there, your
copy fails quietly, nothing is published, and you use your defaults.

## 1. The registration

A Lua file that returns one table. Either ship it and copy it into the folder at start-up (DayNight
does), or write it from your code.

```lua
return {
    name    = "MyMod",      -- required: your mod's folder name under ue4ss/Mods
    display = "My Mod",     -- the section heading (default: name)
    version = "1.0.0",      -- shown as "My Mod - v1.0.0"
    settings = {
        { key = "Enabled", title = "Enabled", type = "toggle", default = true,
          description = "Shown on the right while the row is highlighted." },
        { key = "Speed", title = "Speed", type = "slider", min = 0.5, max = 3, step = 0.25, default = 1,
          enabled_by = "Enabled" },
    },
}
```

A registration is only shown when its mod is installed: `ue4ss/Mods/<name>/enabled.txt` exists, or
`ue4ss/Mods/mods.txt` has the line `<name> : 1`. Registrations are read again every time Settings
opens, so one written after start-up appears then. A mistake in one registration (a Lua error, a missing
field) costs only that mod its section, with a line in `UE4SS.log`.

A file with every field: [`docs/example_registration.lua`](docs/example_registration.lua).

### Kinds of row

| `type` | Value you read | Fields |
|---|---|---|
| `toggle` | `true` / `false` | `default` (missing means false) |
| `slider` | a number | `min`, `max`, `step` (default 1 for integer, 0.1 otherwise), `format`: `"float"`, `"integer"` or `"percent"` (shown as a percentage) |
| `choice` | the option's text | `options = { "A", "B", ... }`, `default` (one of them) |
| `keybind` | a key name (`"F8"`) | `default`, `default_alt`. Two rows: the key, and a second key saved as `<key>_Alt`. No key is `""` |
| `button` | (none) | `button_text`. Each press adds 1 to the shared variable `…/<key>` |
| `header` | (none) | `title`: a sub-heading inside your section |

Every row takes `key` (not needed for headers), `title` (default: the key) and `description`. Also:

- `enabled_by = "<another key>"`: the row is greyed out while that toggle is off (or that number is 0).
- `reload = true`: adds "Takes effect after the next load." to the description.
- `main_menu_only = true`: the row can only be changed from the main menu's Settings. In a loaded game it
  is shown as plain text ("Oxygen: 45"), presets and Reset leave it alone, and a section whose rows are
  all like this gets no Reset row.
- `per_save = true`: each save keeps its own value (see [Per-save settings](#per-save-settings)).
- An unknown `type` is skipped with a line in the log, so a registration can use newer kinds and still
  load in older versions.

Key names are the game engine's (`"F8"`, `"A"`, `"Home"`, `"NumPadOne"`). UE4SS's `Key` table mostly
uses the same names in capitals (`Key.F8`, `Key.HOME`); DayNight shows how to listen for the chosen key.

### Presets

```lua
preset_key = "Style",                       -- the key of a choice row
presets = {
    ["Easy"] = { Damage = 1, Hunger = false },
    ["Hard"] = { Damage = 3, Hunger = true },
},
```

Picking an option of that choice sets every value listed for it. Changing a listed value by hand switches
the choice to its option `"Custom"`, if it has one.

## 2. Reading your values

- **Shared variables** (the usual way):
  `ModRef:GetSharedVariable("SN2ModSettingsRemade/<YourMod>/<key>")`. Published at start-up and at every
  change; numbers, booleans and strings. `nil` until published: use your default.
- **The change counter**: `SN2ModSettingsRemade/<YourMod>/__changes` goes up by one at every change of
  your values. Poll it, and re-read your values only when it moves.
- **The saved file**: `ue4ss/Mods/SN2ModSettingsRemade/saved/<YourMod>.lua` returns a flat table
  (`key = value` per line). Handy at start-up, or without SN2ModSettingsRemade running. It holds the main
  menu's values: with `per_save` settings, read the shared variables instead. If you load it yourself,
  load it as data: `load(text, "@" .. path, "t", {})` (no globals, no bytecode).

## Per-save settings

For settings a game should keep from start to finish (a difficulty, a starting spot), mark them
`per_save = true`, usually together with `main_menu_only = true`:

- **In the main menu** the row shows the value new games start with; that's what the saved file holds.
- **The first time a save is played** (a new game, or an older save seen for the first time) its values
  are recorded: `ue4ss/Mods/SN2ModSettingsRemade/saves/<SaveId>.<YourMod>.lua`.
- **While that save is played** its values are the ones published, so your shared variables always hold
  the values in effect. Change the main menu's value and older saves keep theirs.
- A `per_save` setting that isn't `main_menu_only` can be changed in a game; the change goes to that
  save's file only.

The save is told apart by the game's own id for it (a GUID made with the save): a new game in a reused
slot is a new save, and a save copied to another slot keeps its values.

Your mod needs nothing new: read the shared variables as usual. Two more tell you where the player is:

| Shared variable | Value |
|---|---|
| `SN2ModSettingsRemade/__save` | `""` at the main menu (and for a moment after start-up or a hot reload, until SN2ModSettingsRemade knows), the save's id while a game is played, `"unsaved"` if the game has no id for it yet |
| `SN2ModSettingsRemade/__save_new` | `true` right after a save's values were recorded (its first time) |

If your mod acts once when a game loads, wait until `__save` is not `""` before reading: then the
values are that save's. Mods can't hand each other functions (each UE4SS mod has its own Lua state), so
this is the "a save was loaded" event: watch `__save` change. Deathrun does exactly that.

## Mods made for the original SN2ModSettings

A registration in the original's folder, `ue4ss/Mods/SN2ModSettings/registrations/`, works unchanged and
keeps the original's paths and names: values in `ue4ss/Mods/SN2ModSettings/saved/<YourMod>.lua`, shared
variables `SN2ModSettings/<YourMod>/<key>`. Each mod has one home, the folder its registration is in; if
it is registered in both, ours wins and the log says so. If `SN2ModSettings/saved/` doesn't exist it is
made on the first save into it. Per-save files are always in SN2ModSettingsRemade's `saves/` folder.

## Tips

- **Don't keep game objects between ticks** (an actor, a widget, a component): look them up again each
  time. Loading a game throws them away, and using a thrown-away object crashes the game in a way Lua
  can't catch. DayNight finds the clock again twice a second.
- Wrap calls that may fail in `pcall` so one error doesn't stop your mod.
- The game's day clock (`UWETimeOfDayComponent`) counts in **fractions of a day**: 0.5 is noon.

## Licence

Public domain ([the Unlicense](LICENSE)): copy any of this into your own mod, no credit needed.
