# ShammyTime - Enhancment Shaman Addon for WoW TBC Anniversary
Author: Joachim Eriksson (05.02.2026)

An **Enhancement Shaman** addon for WoW TBC Anniversary that gives you a **Windfury** circle (center ring + stat bubbles), a totem bar with timers, a red overlay when you’re too far from a totem, Lightning/Water Shield, weapon imbue, and Shamanistic Focus.

**Built for The Burning Crusade Anniversary 2026** (Interface 20505). Works with TBC Anniversary clients (Interface 20501–20505).

When the addon loads you’ll see: **ShammyTime loaded.** Type **/st** for information or **/st options** to enter the options panel.

---

## Screenshots

### Windfury Circle

Animated; plays an electric strike on crit. Center shows "Windfury!" and total; satellites show MIN, MAX, AVG, PROCS, PROC%, CRIT%. Numbers on hover or always. Right-click to reset.

![Windfury Bubbles no numbers](Screenshots/Windfury%20Bubbles%20no%20numbers.png) ![Windfury Bubbles with numbers](Screenshots/Windfury%20Bubbles%20with%20numbers.png) ![Windfury Bubbles Critical Strike](Screenshots/Windfury%20Bubbles%20Critical%20Strike.png)

---

### Totem Bar

Fire, Earth, Water, Air with timers. Red overlay when out of range; "Gone" when a totem dies or expires.

![Totem Bar with totems](Screenshots/Totem%20Bar%20with%20totems.png) ![Totem Bar without totems](Screenshots/Totem%20Bar%20without%20totems.png)

---

### WF Totem Damage

Tracks the bonus damage your Windfury Totem gives to party members. Scrolling combat text floats each hit above your character, and a running total is shown below. Hover over the Air totem slot to see a per-player breakdown with damage and hit counts. Right-click the tooltip to reset stats.

![Windfury Totem Party Damage](Screenshots/Windfury%20Totem%20Party%20Damage.png) ![Windfury Totem Party Damage Total](Screenshots/Windfury%20Totem%20Party%20Damage%20Total.png) ![Windfury Totem Tooltip](Screenshots/Windfury%20Totem%20Tooltip.png)

---

### Weapon Imbue Bar

Current imbue and time left (Flametongue, Frostbrand, Rockbiter, Windfury Weapon).

![Weapon Imbue Bar](Screenshots/Weapon%20Imbue%20Bar%20with%20Imbue.png)

---

### Shamanistic Focus

Lights up with a timer after a melee crit; next Shock costs 60% less for 15s.

![Shamanistic Focus ON](Screenshots/Shamanistic%20Focus%20ON.png) ![Shamanistic Focus OFF](Screenshots/Shamanistic%20Focus%20OFF.png)

---

### Lightning/Water Shield

Shield charges (and time left where applicable).

![Shield ON](Screenshots/Shield%20ON.png) ![Shield OFF](Screenshots/Shield%20OFF.png)

---

### Presets

Quickly set the fade behaviour for every module at once. **Always Visible** keeps everything on screen, while **Smart Fade** hides elements when they're not needed (out of combat, no target, etc.). Only fade settings are changed — scale, position, and other options stay the same.

![Presets Smart Fade](Screenshots/Presets%20Smart%20Fade.png)

---

### Settings & Quick Commands

**/st options** opens the panel; **/st** lists slash commands. All elements can be shown/hidden, scaled, and faded in settings.

![Settings](Screenshots/Settings.png) ![CMD](Screenshots/CMD.png)

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

## Development Tools

### WoW Auto-Screenshot System (In Development)

We're building an automated screenshot capture system for World of Warcraft on macOS. This will enable Cursor agents to "see" the game state by reading screenshots from a designated folder.

**Status**: Research complete, ready for implementation

**Documentation**: See [`docs/BUI-11-INDEX.md`](docs/BUI-11-INDEX.md) for complete details

**Key Features** (when complete):
- Automatic periodic screenshot capture of WoW window
- Works across virtual desktops (Spaces)
- Background daemon for hands-free operation
- Cursor agent integration for AI-assisted gameplay analysis

**Quick Links**:
- [Project Summary](docs/BUI-11-SUMMARY.md) - Executive overview
- [Quick Reference](docs/BUI-11-quick-reference.md) - Implementation guide
- [Sub-Tasks](docs/BUI-11-subtasks.md) - Detailed specifications

---

## License

MIT License. Use and modify as you like; no warranty. If you publish a fork, credit the original. See **LICENSE** in this folder for the full text.
