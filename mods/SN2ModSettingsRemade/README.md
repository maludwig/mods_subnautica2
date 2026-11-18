# SN2ModSettingsRemade

A **Mods** tab on Subnautica 2's own Settings screen, where every mod that supports it puts its settings.
Toggles, sliders, lists to pick from, key bindings, buttons: they look and work like the game's own.

Version 0.2.1. Tested with Subnautica 2 Experimental Build 0.2.0.0-138154 and UE4SS 3.0.1.

## Installing

1. Install [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) for Subnautica 2, if you haven't already.
2. Unpack the zip into `Subnautica2\Binaries\Win64\ue4ss\Mods\`. You should end up with
   `ue4ss\Mods\SN2ModSettingsRemade\Scripts\main.lua`.

That's all: the `enabled.txt` in its folder switches it on.

## Using it

Open **Settings** (from the pause menu or the main menu) and pick the **Mods** tab, the last one. Each
installed mod that has settings gets a section with its name and version.

- Changes are saved straight away. There is no Apply button.
- Point at a row to see what it does, on the right.
- Some rows are greyed out until another setting is on.
- Each section ends with **Reset to defaults**.
- Some settings can only be changed from the main menu. In a game they are shown as text.
- Some settings are kept **per save**: the main menu's value is for new games, and each save keeps the
  value it started with. Change it in the main menu and your older saves aren't affected.
- Mods installed while the game is running appear the next time you open Settings.

If no installed mod has settings, the tab says so.

## Want to see it working?

Install **[DayNight](../DayNight/README.md)** too. It's a small example mod made for this one: it puts
every kind of setting on the Mods tab (a slider for the length of a day, toggles to skip nights or stop
the clock, a choice of where the clock stops, a button and a key to jump to morning, and a "Style" row
that sets several of them at once), so you can see how they all work.

## Works with mods made for the original SN2ModSettings

Mods written for the original SN2ModSettings (removed by its author) work with this one unchanged: their
settings appear on the Mods tab and their values stay where those mods expect them.

**Don't run both.** If the original SN2ModSettings is installed and switched on, this mod notices,
writes a line in its log, and stays out of the way.

## Your settings

They are plain text files you can open in Notepad:

- `ue4ss\Mods\SN2ModSettingsRemade\saved\<mod name>.lua`
- or, for mods made for the original, `ue4ss\Mods\SN2ModSettings\saved\<mod name>.lua`
- per-save settings: `ue4ss\Mods\SN2ModSettingsRemade\saves\<save id>.<mod name>.lua`, one per save

A file you edit by hand is picked up within a couple of seconds.

## Good to know

- **No internet**, ever: no update checks, nothing sent anywhere.
- **If a game update breaks the Settings screen**, the Mods tab just doesn't appear (one line in
  `ue4ss\UE4SS.log` says why) and every mod still gets its saved settings.
- Problems or questions: the log, `ue4ss\UE4SS.log`, has lines starting with `[SN2ModSettingsRemade]`.

## For mod makers

See **[MODDING.md](MODDING.md)**: how to put your mod's settings on the tab, in a few lines.

## Thanks

Inspired by the now-removed original SN2ModSettings, thank you to Just-Chaldea for the original.

## Licence

Public domain ([the Unlicense](LICENSE)). Do whatever you like with it: copy it, change it, sell it, put
it in your own mod. You don't need to ask or give credit.
