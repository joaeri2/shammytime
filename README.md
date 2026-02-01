# ShammyTime

A **Shaman** addon for WoW that gives you a compact totem bar with timers, a red overlay when you’re too far from a totem, Lightning Shield, weapon imbue, and **Windfury** tracking—plus a big gold damage popup when Windfury procs.

**Built for The Burning Crusade Anniversary 2026** (Interface 20505). Works with TBC Anniversary clients (Interface 20501–20505).

---

## What You Get

| Thing | What to expect |
|-------|----------------|
| **Main bar** | One row: your 4 totem slots (Fire, Earth, Water, Air) + Lightning Shield + weapon imbue + Shamanistic Focus. Each slot shows a timer. Drag it where you want, lock it with `/st lock`. |
| **Windfury stats bar** | When you have Windfury Weapon, a second bar appears below (or where you drag it). It shows Procs, Proc %, Crits, Min/Avg/Max/Total damage for the current pull and the whole session. Right-click to reset. |
| **Windfury damage popup** | When Windfury procs, a **large gold number** (e.g. *Windfury: 2.4k*) appears on screen: it pops in at full size, bounces to 140% and back to 100% over ~0.3s, stays readable for a few seconds (you choose how long), then floats up and fades. You can move it, resize it, and turn it on/off. |

You can hide the Windfury stats bar and still use the popup (or the other way around). Type **`/st`** or **`/st wf`** to see all options.

---

## Main Bar (Totems, Shield, Imbue, Focus)

- **Totem slots** — Fire, Earth, Water, Air with countdown timers. Empty slots show a dimmed elemental icon.
- **“Gone” feedback** — When a totem dies or expires, that slot flashes red (“GONE”) with a cooldown sweep so you notice right away.
- **Too far from totem** — If you’re too far from a totem to benefit from it, that slot gets a **red overlay** (no text). For totems that give you a buff (e.g. Mana Spring, Strength of Earth), the addon shows the overlay when the totem is down but you don’t have that buff. For totems that don’t give a buff (e.g. Searing Totem, Windfury Totem), it estimates distance from where you were when you placed it and shows the overlay if you’re beyond the totem’s radius—**that distance check only works outdoors**, not in instances.
- **Lightning Shield** — Shows charges and time left (e.g. `3 (30)`).
- **Weapon imbue** — Shows your current imbue (Flametongue, Frostbrand, Rockbiter, Windfury Weapon) and time until it expires.
- **Focused** — Shamanistic Focus proc (TBC): after a melee crit you get “Focused” for 15s; next Shock costs 60% less mana. The slot lights up with a timer while the buff is active.
- **Move & lock** — Drag the bar to position it. Use `/st lock` so it can’t be moved, `/st unlock` to move it again.

---

## Windfury Stats Bar

When you have **Windfury Weapon** on your weapon, a second bar appears. It tracks Windfury Attack damage in two rows:

- **Pull** — This fight only (resets when you enter combat).
- **Session** — Since login or since you last reset.

Columns: **Procs** (number of WF hits), **Proc %** (WF hits ÷ white swings), **Crits**, **Min**, **Avg**, **Max**, **Total**.

- **Right-click** the bar to reset session (and pull) stats.
- **Move it** — `/st wf unlock`, drag the bar, then `/st wf lock`.
- **Hide it** — `/st wf disable`. Stats stop updating and the bar is hidden. Use `/st wf enable` to turn it back on.
- **Scale** — `/st wf scale 1.2` (0.5–2). This is separate from the main bar scale.

---

## Windfury Damage Popup

When Windfury procs, you see a **big gold number** (e.g. *Windfury: 2.4k*) that:

1. **Appears at full size** — No slow fade-in; the number is there immediately.
2. **Bounces** — Scales up to 140% and back to 100% over about 0.3 seconds.
3. **Stays visible** — Holds at 100% for a few seconds (default 2s; you set it).
4. **Dissipates** — Floats up and fades out.

The popup works even if the Windfury stats bar is hidden. You can move it (unlock, drag when it appears, then lock), change its size, and how long it stays before fading.

| Command | What it does |
|--------|----------------|
| `/st wf popup on` | Show the damage popup when Windfury procs. |
| `/st wf popup off` | Hide the popup. |
| `/st wf popup unlock` | Let you drag the popup to move it (drag it the next time it appears). |
| `/st wf popup lock` | Lock the popup position. |
| `/st wf popup scale 1.3` | Popup text size (0.5–2). Default 1.3. |
| `/st wf popup hold 2` | Seconds the popup stays at full size before fading (0.5–4). Default 2. |

Type **`/st wf popup`** to see current popup settings and a short reminder of these commands.

---

## All Commands

| Command | Description |
|--------|----------------|
| `/st lock` | Lock the main bar. |
| `/st unlock` / `/st move` | Unlock so you can drag the main bar. |
| `/st scale [0.5–2]` | Main bar size (e.g. `/st scale 1.2`). |
| `/st wf` | Show Windfury options (tracker, popup, reset, lock, scale). |
| `/st wf reset` | Reset Windfury stats (same as right-click on the bar). |
| `/st wf lock` / `unlock` | Lock or unlock the Windfury bar. |
| `/st wf scale [0.5–2]` | Windfury bar size (separate from main bar). |
| `/st wf enable` / `disable` | Turn the Windfury tracker (stats bar) on or off. |
| `/st wf popup on` / `off` | Turn the Windfury damage popup on or off. |
| `/st wf popup lock` / `unlock` | Lock or unlock popup position. |
| `/st wf popup scale [0.5–2]` | Popup text size. |
| `/st wf popup hold [0.5–4]` | Seconds popup stays visible before fading. |
| `/st debug` | Technical info (for troubleshooting). |

You can use **`/shammytime`** instead of **`/st`**.

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

- **Saved data:** Bar positions, scales, and lock states (main bar, Windfury bar, and popup) are stored in `ShammyTimeDB` per character. Windfury stats (session and last pull) are saved too.
- **Range overlay:** When you’re too far from a totem, that slot gets a red overlay (no text). **Buff-based:** For totems that put a buff on you (Mana Spring, Strength of Earth, etc.), the overlay shows when the totem is down but you don’t have the buff. **Position-based:** For totems that don’t give a buff (Searing Totem, Windfury Totem, Earthbind, etc.), the addon uses your position when you placed the totem and your current position; if you’re beyond the totem’s effect radius, the overlay shows. Position-based check uses `UnitPosition` and **only works outdoors**; in instances it doesn’t work, so those totems won’t show the red overlay from distance.
- **UI:** Uses Blizzard tooltip/dialog textures so the bar matches the default WoW look. See `WOW_UI_STYLING.md` for details.

---

## Publishing on CurseForge

See **CURSEFORGE.md** in this folder for submission requirements and a checklist.

---

## License

Use and modify as you like. No warranty. If you publish a fork, credit the original and follow the license you set on CurseForge (e.g. MIT).
