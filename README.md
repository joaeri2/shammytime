# ShammyTime - Enhancement Shaman Addon for WoW TBC Anniversary

ShammyTime is an Enhancement Shaman combat UI package built for The Burning Crusade Anniversary.

It gives you fast, readable, high-impact visuals for the things that actually matter in combat: Windfury procs, pressure spikes, totem uptime, imbues, shield charges, ICD timing, focus windows, and swing stagger.

## Built For

- **Interface:** `20505`
- **Compatible clients:** `20501` to `20505`
- **Game version:** WoW Classic - TBC Anniversary

## Feature Showcase

### Windfury Bubbles

Your core Windfury proc hub with a center impact ring plus 6 live stat bubbles (`MIN`, `MAX`, `AVG`, `PROCS`, `PROC%`, `CRIT%`).
Includes an electric Windfury strike animation on proc for instant visual feedback.
Use it to instantly judge proc quality and compare builds, weapons, and pulls in real time.

![Windfury Bubbles No Numbers](<Screenshots/Example Windfury Bubbles No Numbers.png>)
![Windfury Bubbles With Numbers](<Screenshots/Example Windfury Bubbles with numbers.png>)

### Pressure Visual

A live momentum meter driven by your outgoing damage, with clear low-to-overload pressure states.
Use it to read your burst windows fast and push harder when your pressure peaks.

![Pressure 50](<Screenshots/Example Pressure 50.png>)
![Pressure 75](<Screenshots/Example Pressure 75.png>)
![Pressure 100 Overload](<Screenshots/Example Pressure 100 Overload.png>)

### Totem Bar + WF Totem Impact

Shows all 4 totem slots with timers and range state, plus a live Windfury Totem bonus damage feed.
Includes range fadeout behavior so you can quickly tell when you are in range of your totems or not.
Use it to maintain clean totem uptime and track exactly how much extra damage your totem adds.

![Totem Bar 4 Totems Up](<Screenshots/Example Totem Bar 4 totems up.png>)
![Totem Bar No Totems](<Screenshots/Example Totem Bar No Totems.png>)
![WF Totem Procs](<Screenshots/Example Totem Bar with Windfury Totem Procs .png>)
![WF Totem Procs Tooltip Stats](<Screenshots/Example Totem Bar with Windfury Totem Procs Statistics Right Mouseover.png>)

### Weapon Imbues

Tracks main-hand and off-hand imbues with remaining duration.
Use it to refresh early, avoid dead uptime, and keep your weapon buffs battle-ready.

![Imbue Bar Empty](<Screenshots/Example Imbue Bar Empty.png>)
![Imbue Bar Windfury](<Screenshots/Example Imbue Bar Windfury 4min left.png>)

### Shield Indicator

Shows Lightning/Water Shield status with clear charge count.
Use it to keep shield uptime tight and avoid getting caught without charges.

![Lightning Shield Charges](<Screenshots/Example Lightning Shield with 3 charges.png>)
![Lightning Shield Off](<Screenshots/Example Lightning Shield off.png>)

### Windfury ICD + Shamanistic Focus

Dual readiness tracker: Windfury ICD lamp (ready vs cooldown with timer) plus Shamanistic Focus state with shock cooldown context.
Use it to time shocks cleaner and know exactly when your next big Windfury moment is available.

![WF ICD With Stormstrike Cooldown](<Screenshots/Example Windfury ICD with Stormstrike currently on CD.png>)
![WF ICD On Cooldown](<Screenshots/Example Windfury ICD on cooldown.png>)
![Shamanistic Focus On](<Screenshots/Example Shamanistic Focus On and no SS on CD.png>)
![Shamanistic Focus Shock Cooldown](<Screenshots/Example Shamanistic Focus with ES currently on CD.png>)

### Stagger Bar

Dual MH/OH swing bars with color feedback and resync cues.
Use it to keep cleaner stagger timing and squeeze more consistent DPS from your swing rhythm.

Quick way to use it:

- Gold bars = stagger is good, do nothing.
- White bars = stagger needs help.
- Red OH zones = do not click there.
- Dynamic marker = best click point for this pass (green normally, yellow in hold mode).
- `Click!` = press your resync macro once now.
- `Click Multiple Times!` = OH is too far ahead, tap the macro repeatedly to hold OH back.
- If OH is below 50%, clicking does not move OH yet.
- Timing is dynamic from your live weapon speeds/haste and aims for MH first with OH within ~0.5s (with ping buffer).

![Stagger Yellow](<Screenshots/Example Stagger Bar Yellow color.png>)
![Stagger Gray](<Screenshots/Example Stagger Bar Gray Color.png>)
![Stagger White](<Screenshots/Example Stagger bar White color.png>)

## Installation

### CurseForge App

1. Open CurseForge.
2. Search for **ShammyTime**.
3. Install and launch the game.

### Manual

1. Download or clone this addon.
2. Put the `ShammyTime` folder in:
   - `World of Warcraft\_anniversary_\Interface\AddOns\`
3. Restart game client or reload UI.
4. Enable **ShammyTime** in the AddOns list.

## Notes

- Saved settings are stored per character profile (`ShammyTimeDB`).
- Windfury Totem bonus damage tracking is an **estimate** based on combat log event correlation.
- Some no-buff totem range checks rely on position logic and work best outdoors.

## Settings, Commands & Dev (At The End)

### Settings

![Options](<Screenshots/Example Options Menu.png>)
![Smart Fade Preset](<Screenshots/Example Presets Smart Fade.png>)
![Command Line](<Screenshots/Example Command Line.png>)

### Quick Setup

1. Type **`/st options`**.
2. Pick a preset:
   - **Smart Fade** for context-aware visibility
   - **Always Visible** for always-on UI
3. Type **`/st unlock`**, move frames, then **`/st lock`**.
4. Type **`/st test`** to preview visuals.

Settings apply in real time.

### Main Commands

| Command | What it does |
|---|---|
| `/st` | Show command help |
| `/st options` | Open settings panel |
| `/st unlock` / `/st lock` | Move and lock frames |
| `/st test` | Start/stop demo mode |
| `/st reset` | Reset addon settings |
| `/st show <element> on\|off` | Toggle elements |
| `/st fade all on\|off` | Toggle global fade behavior |
| `/st resync` | Resync helper for stagger macro |

Alias: **`/shammytime`** also works.

### Optional Dev Commands

- `/st dev on|off`
- `/st dev performance`
- `/st print`

## License

MIT License. See `LICENSE`.
