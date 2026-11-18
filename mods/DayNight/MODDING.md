# DayNight for mod makers

DayNight is an example of a mod with settings on [SN2ModSettingsRemade](../SN2ModSettingsRemade/MODDING.md)'s
Mods tab. It uses every kind of row (toggle, slider, choice, key binding, button, header), presets and
greyed-out rows, and reads its values the recommended way. The code explains itself line by line; this
page is the map.

**To make your own mod from it:** copy the folder, rename it (and `NAME` in `main.lua`, and `name` in
`registration.lua`), replace the settings in `registration.lua`, and replace step 3 in `main.lua` with
what your mod does.

## The files

| File | What it is |
|---|---|
| `registration.lua` | The list of settings: what the Mods tab shows. Plain data, one table |
| `Scripts/main.lua` | The mod: hands over the list, reads the values, changes the game's clock |
| `enabled.txt` | Empty. Its presence tells UE4SS to load the mod |

## The three steps, and where they are in `main.lua`

1. **Hand over the list.** At start-up `main.lua` copies `registration.lua` to
   `ue4ss/Mods/SN2ModSettingsRemade/registrations/DayNight.lua`. If SN2ModSettingsRemade isn't installed,
   that folder doesn't exist, the copy fails quietly, and the mod uses its defaults.
2. **Read the values.** Each one is a UE4SS shared variable named
   `SN2ModSettingsRemade/DayNight/<key>`. `read_values()` re-reads them only when the change counter
   `SN2ModSettingsRemade/DayNight/__changes` has moved.
3. **Use them.** `update()` runs twice a second: it finds the game's clock and applies the settings.

## Every feature, and where to find it

| Feature | In `registration.lua` | In `main.lua` |
|---|---|---|
| Choice row + presets | `Style`, `preset_key`, `presets` | nothing: the settings mod applies presets itself |
| Header rows | `type = "header"` (3 of them) | nothing: they have no value |
| Slider | `DayLength`, `format = "integer"` | `SetDayLengthInMinutes`, only when changed or after a game loads |
| Toggles | `SkipNights`, `Stop` | `values.SkipNights`, `values.Stop` |
| Greyed-out row | `StopAt` with `enabled_by = "Stop"` | `values.StopAt` (a choice: the option's text) |
| Button | `SkipNow`, `button_text` | its press count on the board: more presses than last time = pressed |
| Key binding | `SkipKey`, `default = "F8"` | `listen_for_keys()`: `RegisterKeyBind` for each key picked, `SkipKey` and `SkipKey_Alt` |
| Change counter | | `read_values()` and `__changes` |

## Things worth copying

- **Look game objects up again every time** (`find_clock()`), never keep them: loading a game throws them
  away, and touching a thrown-away object crashes the game in a way Lua can't catch.
- **Act on change, not all the time**: the day length is only set when it changed or a new game loaded.
- **Don't act on a button at start-up**: the first look at the press count only notes it.
- **Keys**: UE4SS can't stop listening to a key, so DayNight listens to each key the first time it's
  picked and checks on every press whether it's still the chosen one.

## The game's clock

`UWETimeOfDayComponent`, one per loaded game (on the game state):

| | |
|---|---|
| `SetTimeOfDay(fraction)` | 0 = midnight, 0.5 = noon, 1 = the next midnight. **Not hours** |
| `FreezeTime(true / false)` | stop / start the clock |
| `SetDayLengthInMinutes(n)` | real minutes per game day (the game's own: 24) |
| `IsNight()` | true at night |
| `HourStartDawn`, `HourStartDay`, `HourStartDusk`, `HourStartNight` | hours (3, 4, 20 and 21 in this build) |

The sky (`BP_UWESky_C`, a day-sequence actor) follows the clock; pausing the sky doesn't stop time.

## Licence

Public domain ([the Unlicense](LICENSE)): take any of it, no credit needed.
