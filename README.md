# ShammyTime

A World of Warcraft addon for **Shaman** that shows your totems, Lightning Shield, and weapon imbue in a compact, movable bar with timers and clear feedback.

**Built for The Burning Crusade Anniversary 2026** (Interface 20505). Compatible with TBC Anniversary clients using Interface 20501–20505.

---

## What It Does

- **Totem bar** — Four slots (Fire, Earth, Water, Air) showing active totems with countdown timers.
- **“Gone” feedback** — When a totem is killed or expires, that slot briefly flashes with a red “GONE” overlay and a cooldown-style sweep so you notice immediately.
- **Out-of-range indicator** — If you’re too far from a totem to receive its buff (e.g. Mana Spring, Strength of Earth), a red **“OUT OF RANGE”** overlay appears on that slot so you know to move back in range.
- **Lightning Shield** — Slot showing charges and time remaining (e.g. `3 (30)`).
- **Weapon imbue** — Slot showing your current imbue (Flametongue, Frostbrand, Rockbiter, Windfury Weapon) and time until it expires; tooltip shows the imbue name.
- **Movable & lockable** — Drag the bar where you want it, then lock it with a slash command so it stays put.

---

## Commands

| Command | Description |
|--------|-------------|
| `/st lock`   | Lock the frame so it can’t be dragged. |
| `/st unlock` | Unlock the frame so you can drag it. |
| `/st move`   | Same as `unlock`. |
| `/st scale [0.5–2]` | Set bar scale (e.g. `/st scale 1.2`). |

You can also use `/shammytime` instead of `/st`.

---

## Installation

### Via CurseForge

1. Install the [CurseForge app](https://www.curseforge.com/download/app) and add your WoW TBC Anniversary installation.
2. Search for **ShammyTime** and install it. The app will place the addon in the correct folder for your game flavor.

### Manual

1. Download the latest release (e.g. from CurseForge) or clone this repository.
2. Place the **ShammyTime** folder in:
   - **TBC Anniversary:**  
     `World of Warcraft\_anniversary_\Interface\AddOns\`
3. Restart WoW or run `/reload` and enable **ShammyTime** in the AddOns list at the character selection screen.

---

## Technical Notes

- **Saved data:** Position, scale, and lock state are stored in `ShammyTimeDB` (per character).
- **Out-of-range detection:** The addon infers “out of range” when a totem is down but you don’t have its buff (e.g. Mana Spring, Grace of Air). Totems that don’t grant a trackable buff (e.g. Windfury Totem, Searing Totem) don’t show the overlay.
- **UI styling:** Uses Blizzard’s tooltip/dialog textures so the bar fits the default WoW look. See `WOW_UI_STYLING.md` in the addon folder for details.

---

## Publishing on CurseForge

If you want to publish this addon (or a fork) on CurseForge, see **CURSEFORGE.md** in this folder for submission requirements, project page guidelines, and a checklist.

---

## License

Use and modify as you like. No warranty. If you publish a fork, please credit the original and comply with the license you choose on CurseForge (e.g. MIT).
