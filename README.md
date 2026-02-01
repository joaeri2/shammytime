# ShammyTime

A World of Warcraft addon for **Shaman** that shows your totems, Lightning Shield, weapon imbue, and **Windfury stats** in a compact, movable bar with timers and clear feedback.

**Built for The Burning Crusade Anniversary 2026** (Interface 20505). Compatible with TBC Anniversary clients using Interface 20501–20505.

---

## What It Does

### Main bar (totems, shields, imbue)

- **Totem bar** — Four slots (Fire, Earth, Water, Air) showing active totems with countdown timers.
- **“Gone” feedback** — When a totem is killed or expires, that slot briefly flashes with a red “GONE” overlay and a cooldown-style sweep so you notice immediately.
- **Out-of-range indicator** — If you’re too far from a totem to receive its buff (e.g. Mana Spring, Strength of Earth), a red **“OUT OF RANGE”** overlay appears on that slot so you know to move back in range.
- **Lightning Shield** — Slot showing charges and time remaining (e.g. `3 (30)`).
- **Weapon imbue** — Slot showing your current imbue (Flametongue, Frostbrand, Rockbiter, Windfury Weapon) and time until it expires; tooltip shows the imbue name.
- **Focused** — Indicator for the Shamanistic Focus proc (TBC): when you get a melee critical strike, you gain “Focused” for 15 seconds; your next Shock costs 60% less mana. The slot lights up with a timer while the buff is active.
- **Movable & lockable** — Drag the bar where you want it, then lock it with a slash command so it stays put.

### Windfury stats bar (below the main bar)

When you have **Windfury Weapon** on your weapon, a second bar appears below the main bar. It tracks your Windfury Attack damage in two rows:

- **Top row (Pull)** — This fight only. Resets when you enter combat.
- **Bottom row (Session)** — Since you logged in (or since you last reset).

Each column means:

| Column   | What it shows |
|----------|----------------|
| **Procs**   | How many Windfury Attack hits landed (actual damage only; parry/dodge/miss are not counted). |
| **Proc %**  | Windfury hits ÷ your white (auto) swings. Only white swings can proc Windfury, so this is your real proc rate. |
| **Crits**   | How many of those Windfury hits were critical strikes. |
| **Min**     | Smallest single Windfury hit. |
| **Avg**     | Average damage per Windfury hit. |
| **Max**     | Largest single Windfury hit. |
| **Total**   | Sum of all Windfury damage. |

- **Right-click** the Windfury bar to reset session stats (and pull stats).
- The Windfury bar is **movable** when unlocked; use `/st wf unlock` to drag it, then `/st wf lock` to lock it.

---

## Commands

| Command | Description |
|--------|-------------|
| `/st lock`   | Lock the main bar so it can’t be dragged. |
| `/st unlock` | Unlock the main bar so you can drag it. |
| `/st move`   | Same as `unlock`. |
| `/st scale [0.5–2]` | Set bar scale (e.g. `/st scale 1.2`). Affects both bars. |
| `/st wf reset` | Reset Windfury stats (pull and session). Same as right-clicking the Windfury bar. |
| `/st wf lock`   | Lock the Windfury bar so it can't be dragged. |
| `/st wf unlock` | Unlock the Windfury bar so you can drag it. |

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

- **Saved data:** Position, scale, and lock state for both bars are stored in `ShammyTimeDB` (per character). Windfury stats (session and last pull) are also saved so they persist across relog and reload.
- **Out-of-range detection:** The addon infers “out of range” when a totem is down but you don’t have its buff (e.g. Mana Spring, Grace of Air). Totems that don't grant a trackable buff use distance via WoW's `UnitPosition` API.
- **Out-of-range in instances:** WoW's `UnitPosition` only returns valid coordinates in the open world. Inside instances (dungeons, raids, battlegrounds), position-based range cannot work, so the "OUT OF RANGE" overlay will not show for totems that rely on it: Windfury Totem, Searing Totem, Stoneclaw Totem, Earthbind Totem, etc. Buff-based range (totems that give you a trackable buff like Mana Spring or Strength of Earth) should still work in instances.
- **UI styling:** Uses Blizzard’s tooltip/dialog textures so the bar fits the default WoW look. See `WOW_UI_STYLING.md` in the addon folder for details.

---

## Publishing on CurseForge

If you want to publish this addon (or a fork) on CurseForge, see **CURSEFORGE.md** in this folder for submission requirements, project page guidelines, and a checklist.

---

## License

Use and modify as you like. No warranty. If you publish a fork, please credit the original and comply with the license you choose on CurseForge (e.g. MIT).
