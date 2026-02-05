# ShammyTime - Enhancment Shaman Addon for WoW TBC Anniversary
Author: Joachim Eriksson (05.02.2026)

An **Enhancement Shaman** addon for WoW TBC Anniversary that gives you a **Windfury** circle (center ring + stat bubbles), a totem bar with timers, a red overlay when you’re too far from a totem, Lightning/Water Shield, weapon imbue, and Shamanistic Focus.

**Built for The Burning Crusade Anniversary 2026** (Interface 20505). Works with TBC Anniversary clients (Interface 20501–20505).

When the addon loads you’ll see: **ShammyTime loaded.** Type **/st** for information or **/st options** to enter the options panel.

---

## What You Get

| Element | What to expect |
|--------|----------------|
| **Windfury circle** | A center ring plus satellite “bubbles” showing MIN, MAX, AVG, PROCS, PROC%, CRIT%. When Windfury procs, the center shows “Windfury!” and the total damage. Right-click the circle to reset all statistics. You can scale it, set text positions, and show/hide numbers. |
| **Totem bar** | Four totem slots (Fire, Earth, Water, Air) with countdown timers. “Gone” feedback when a totem dies; red overlay when you’re too far from a totem to benefit. |
| **Weapon imbue bar** | Shows your current imbue (Flametongue, Frostbrand, Rockbiter, Windfury Weapon) and time left. |
| **Shamanistic Focus** | TBC proc: after a melee crit you get “Focused” for 15s; next Shock costs 60% less. The element lights up with a timer while the buff is active. |
| **Lightning/Water Shield** | Shows shield charges and (where applicable) time left. |

All elements can be shown/hidden, scaled, and faded (e.g. out of combat, when no totems, when not procced). Use the **settings panel** (**/st options**) to configure everything.

---

## Windfury Circle

When you have **Windfury Weapon** on your weapon, the addon tracks Windfury Attack damage and shows:

- **Center ring** — “Windfury!” and TOTAL damage for the last proc (and optional always-visible numbers).
- **Satellite bubbles** — MIN, MAX, AVG, PROCS, PROC%, CRIT% (session stats).

Stats are session-based (since login or since you last reset). **Right-click the Windfury circle** to reset. Use the settings panel to show/hide, scale, and lock frames (when unlocked you can drag to reposition).

---

## Totem Bar

- **Slots** — Fire, Earth, Water, Air with countdown timers. Empty slots show a dimmed elemental icon.
- **“Gone” feedback** — When a totem dies or expires, that slot flashes red with a cooldown sweep.
- **Too far from totem** — If you’re too far to benefit, that slot gets a **red overlay**. For totems that give you a buff (e.g. Mana Spring, Strength of Earth), the overlay shows when the totem is down but you don’t have the buff. For totems that don’t give a buff (e.g. Searing Totem, Windfury Totem), the addon estimates distance from where you placed it; **that check only works outdoors**, not in instances.
Show/hide and options are in the settings panel.

---

## Quick Commands

| Command | Description |
|--------|-------------|
| **/st** | Show addon info and main slash commands. |
| **/st options** | Open the settings panel (recommended). |
| **/st lock** / **/st unlock** | Lock or unlock all frames (drag when unlocked). |
| **/st test** | Test mode (circle, Windfury, focus). Run again to stop. |
| **/st reset** | Reset all settings to defaults. |
| **/st print** | Export current settings to chat. |
| **/st dev on\|off** | Show or hide the Developer tab in options. |

You can use **/shammytime** instead of **/st**.

---

## Installation

### CurseForge

1. Install the [CurseForge app](https://www.curseforge.com/download/app) and add your WoW TBC Anniversary install.
2. Search for **ShammyTime** and install. The app puts it in the right folder.

### Manual

1. Download the latest release or clone this repo.
2. Put the **ShammyTime** folder in:
   - **TBC Anniversary:** `World of Warcraft\_anniversary_\Interface\AddOns\`
3. Restart WoW or `/reload`, and enable **ShammyTime** in the AddOns list at the character screen.

---

## Technical Notes

- **Saved data:** Positions, scales, lock state, and all settings are stored in **ShammyTimeDB** per character. Windfury session and pull stats are saved too.
- **Range overlay:** Totem slots get a red overlay when you’re too far to benefit. **Buff-based:** For totems that put a buff on you (Mana Spring, Strength of Earth, etc.), the overlay shows when the totem is down but you don’t have the buff. **Position-based:** For totems without a player buff (Searing Totem, Windfury Totem, etc.), the addon uses your position when you placed the totem; **position check only works outdoors**, not in instances.
- **Options:** After changing settings in the options panel, type **/reload** so that all options are applied correctly.

---

## License

MIT License. Use and modify as you like; no warranty. If you publish a fork, credit the original. See **LICENSE** in this folder for the full text.
