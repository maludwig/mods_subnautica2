# Day and Night

Change how the day goes in Subnautica 2: longer or shorter days, nights skipped, or the clock stopped at
noon, midnight, dawn or dusk. A key or a button jumps to the next morning whenever you like.

DayNight is an **example mod for [SN2ModSettingsRemade](../SN2ModSettingsRemade/README.md)**, the mod that
adds a Mods tab to the game's Settings screen. It's useful on its own, and it's also made to show mod
makers how settings mods work: every kind of setting the Mods tab has is used here once (see
[MODDING.md](MODDING.md)).

Version 1.0.1. Tested with Subnautica 2 Experimental Build 0.2.0.0-138154 and UE4SS 3.0.1.

## Installing

1. Install [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) for Subnautica 2, and
   [SN2ModSettingsRemade](../SN2ModSettingsRemade/README.md) for the settings.
2. Unpack the zip into `Subnautica2\Binaries\Win64\ue4ss\Mods\`. You should end up with
   `ue4ss\Mods\DayNight\Scripts\main.lua`.

Without SN2ModSettingsRemade, DayNight runs with its defaults, which leave the game's day exactly as it
is.

## The settings

Open **Settings**, pick the **Mods** tab, and find **Day and Night - v1.0.1**.

| Setting | What it does |
|---|---|
| **Style** | Sets several of the rows below at once: *Game default*, *Long days* (an hour-long day, nights skipped) or *Endless noon*. Change any of them by hand and it says *Custom*. |
| **Length of a day** | Minutes of real time for a whole day and night, from 5 to 120. The game's own is 24. |
| **Skip nights** | When night falls, jump straight to the next morning. |
| **Stop the clock** | Hold the time of day still. |
| **Stop it at** | Where the clock stops: noon, midnight, dawn or dusk. Greyed out until *Stop the clock* is on. |
| **Skip to morning** | A button: jump to the next morning right now. |
| **Skip to morning key** | A key that does the same in the game (F8 to start with), and an optional second key. |

Changes take effect within half a second, even with the game paused.

## Good to know

- Turning the settings back to *Game default* lets the day run on from wherever it is.
- In `ue4ss\UE4SS.log`, DayNight's lines start with `[DayNight]`.

## Changes

- **1.0.1**: steadier. The game's clock is found once and then looked up by its address, instead of
  searching every object in the game twice a second (a search UE4SS crashed inside now and then under
  heavy testing).
- **1.0.0**: first version.

## Licence

Public domain ([the Unlicense](LICENSE)). Do whatever you like with it, no credit needed.
