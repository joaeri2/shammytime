# ShammyTime

A World of Warcraft addon for **Shaman** that shows your totems and Lightning Shield in a compact, movable bar with timers and clear feedback.

**Built for The Burning Crusade Anniversary 2026** (Interface 20505). Compatible with TBC Anniversary clients using Interface 20501–20505.

---

## What It Does

- **Totem bar** — Four slots (Fire, Earth, Water, Air) showing active totems with countdown timers.
- **“Gone” feedback** — When a totem is killed or expires, that slot briefly flashes with a red “GONE” overlay and a cooldown-style sweep so you notice immediately.
- **Out-of-range indicator** — If you’re too far from a totem to receive its buff (e.g. Mana Spring, Strength of Earth), a red **“OUT OF RANGE”** overlay appears on that slot so you know to move back in range.
- **Lightning Shield** — Optional slot showing Lightning Shield charges or time remaining when active.
- **Movable & lockable** — Drag the bar where you want it, then lock it with a slash command so it stays put.

---

## Commands

| Command | Description |
|--------|-------------|
| `/st lock`   | Lock the frame so it can’t be dragged. |
| `/st unlock` | Unlock the frame so you can drag it. |
| `/st move`   | Same as `unlock`. |

You can also use `/shammytime` instead of `/st`.

---

## Installation

1. Download or clone this addon into your WoW addons folder.
2. Place the **ShammyTime** folder in:
   - **TBC Anniversary:**  
     `World of Warcraft\_anniversary_\Interface\AddOns\`
3. Restart WoW or run `/reload` and enable **ShammyTime** in the AddOns list at the character selection screen.

---

## Technical Notes

- **Saved data:** Position, scale, and lock state are stored in `ShammyTimeDB` (per character).
- **Out-of-range detection:** The addon infers “out of range” when a totem is down but you don’t have its buff (e.g. Mana Spring, Grace of Air). Totems that don’t grant a trackable buff (e.g. Windfury, Searing) don’t show the overlay.
- **UI styling:** Uses Blizzard’s tooltip/dialog textures so the bar fits the default WoW look. See `WOW_UI_STYLING.md` in the addon folder for details.

---

## License

Use and modify as you like. No warranty.
