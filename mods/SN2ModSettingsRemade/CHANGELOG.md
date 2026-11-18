# Changelog

## 0.2.1 (2026-11-17)

- Steadier: finding which save is played no longer searches every object in the game three times a
  second (UE4SS's FindAllOf, through UEHelpers.GetPlayerController). The player controller is found
  once and then looked up by its path. Under heavy testing UE4SS 3.0.1 crashed inside FindAllOf now and
  then; this mod no longer calls it while the game runs, only when something has to be found anew.
- A test suite (in the project, not in the download) checks every feature in the running game.

## 0.2.0 (2026-11-17)

- New: `main_menu_only = true` on a setting. Changeable only from the main menu; in a loaded game the
  row is plain text, presets and Reset leave it alone, and a section of only such rows has no Reset row.
- New: `per_save = true` on a setting. Each save keeps its own value, recorded the first time the save is
  played (`saves/<SaveId>.<ModId>.lua`); the main menu's value is for new games. Shared variables always
  hold the values in effect for the save being played. Saves are told apart by the game's own save id.
- New shared variables: `SN2ModSettingsRemade/__save` (`""` at the main menu, the save's id in a game,
  `"unsaved"` before the game gives it one) and `SN2ModSettingsRemade/__save_new`.
- Fixed: for a mod registered in the original's folder, saving failed when
  `SN2ModSettings/saved/` didn't exist (a legacy mod may only make `registrations/`). It is made now.

## 0.1.2 (2026-11-17)

- Fixed: only the first `header` row of a mod was shown (every header got the same made-up key, and the
  others were dropped as duplicates).
- Licence: public domain (the Unlicense) instead of MIT. No credit needed.
- `MODDING.md` for mod makers; `README.md` is for players now.
- DayNight is a mod of its own (separate download), using every feature: presets, headers, a slider,
  toggles, a greyed-out choice, a button and a key binding. `examples/ShowFPS` stays here as the
  smallest example.

## 0.1.1 (2026-11-17)

- Fixed: a choice or keybind row could save its first option over the real value when Settings opened
  (the row's display wasn't ready yet and was read as the player's choice). The row's own value is read
  now, and values are shown again once the rows are drawn.
- Fixed: moving the mouse over or off a "Reset to defaults" row reset that mod (hover events were taken
  for clicks). Only the click counts now.
- No engine references are kept while Settings is closed.
- Example mods: `examples/DayNight` (a slider, two toggles and a choice with `enabled_by`, all on the
  game's clock: day length, skip nights, stop the clock at noon / midnight / dawn / dusk; it reads its
  values when the `__changes` counter moves) and `examples/ShowFPS` (one toggle, one console command).

## 0.1.0 (2026-11-17)

First version. Tested on Subnautica 2 Experimental Build 0.2.0.0-138154 with UE4SS 3.0.1.

- A Mods tab on the game's Settings screen, from the pause menu and the main menu, built from the
  game's own row widgets.
- Reads registrations from `ue4ss/Mods/SN2ModSettingsRemade/registrations/` and, for mods written for
  the original SN2ModSettings, `ue4ss/Mods/SN2ModSettings/registrations/`. Each mod's values are saved and
  published where its registration is (one home per mod).
- Row kinds: toggle, slider (float, integer, percent), keybind (as a choice of key names, plus a second
  key), and new: choice, header, button. Presets with a switch to "Custom". `enabled_by`. `reload = true`
  notes "takes effect after the next load". A "Reset to defaults" row per mod.
- A change counter per mod: `<prefix><ModId>/__changes`.
- Registrations written after start-up appear the next time Settings is opened.
- No network access.
- If the game's Settings screen changes in an update, the tab doesn't appear and everything else keeps
  working.
