# Sync and Stagger — Reference and ShammyTime Behavior

This document summarizes the **Sync and Stagger** mechanics for Enhancement Shaman in TBC and describes how **ShammyTime**’s Stagger Bar and Resync Action Cue implement them.

- **Guide:** [Enhance Shaman Guide: Sync and Stagger](https://www.enhanceshaman.com/pages/guide/sync_stagger)
- **Visual swing timer / trainer:** [Enhance Shaman Suite WeakAura](https://wago.io/fDDNP0SM7) — shows live timing and mirrors the resync timing the guide describes.

---

## 1. Why Sync and Stagger Matter

In TBC they matter for two things only:

- **Sync (0.5 s window)** — How close your MH and OH swings land. Flurry has a 0.5 s internal window: when two swings land within that window, both can benefit from one charge. Keeping swings **synced** (within 0.5 s) makes Flurry efficient.
- **Stagger (which hand leads)** — Which hand hits first after the Windfury ICD ends. Windfury has a 3 s shared ICD; the first swing to land after it has the best chance to proc. You want **main hand first**, off hand shortly after (still within the 0.5 s sync window).

---

## 2. Sync (0.5 second window)

**Sync** = how close together your main hand (MH) and off hand (OH) swings land.

- **Sync window:** **0.5 seconds.**  
  The two swings are “synced” when they land within **0.5 s** of each other. It does **not** require the same instant; the second hand just has to follow within that window.
- **Flurry:** When Flurry is active, the next three swings get a large attack speed bonus. If two swings land within that **0.5 s** window, both can benefit from one charge. If they land too far apart, each swing uses its own charge.
- **Goal:** Keep both weapons inside the **0.5 s** window. Perfect 0.0 s gap is not required; staying **under 0.5 s** is what matters.

---

## 3. Stagger (which hand leads)

**Stagger** = which hand hits first when a Windfury proc can occur.

- **Windfury:** Procs on a melee hit; then a 3 s internal cooldown (shared MH/OH). The first swing to land after the ICD has the best chance to claim the next proc.
- **Stagger goal:** **Main hand first**, off hand follows **shortly after**, still **inside the 0.5 s sync window**.
- **Stagger ≠ big gap:** You still want both swings within 0.5 s. The goal is a **small, consistent MH lead**, not a large delay between hands.

---

## 4. Target State: Sync + Stagger

- **Main hand** lands first.
- **Off hand** follows within **&lt; 0.5 s** (sync window).
- So: **delta &lt; 0.5 s** and **MH timestamp before OH** (positive delta in our convention).

---

## 5. Resync Macro

**Full macro (bind to a key):** use this exact macro so the game resyncs and ShammyTime’s stagger bar stays in sync.

```
/cleartarget
/targetlasttarget
/startattack
/st resync
```

- **First three lines:** Each press briefly stops and restarts auto attack. **Off hand** is forced back toward the **midpoint** of its swing if it has already passed that point.
- **/st resync:** Tells ShammyTime you pressed the macro so the OH bar indicator resets to 50%, matching in-game. Real OH swing events from the combat log remain the master and overwrite this on the next swing.
- If OH has **not** passed midpoint yet, one press does nothing useful in-game.
- **Do not spam.** One clean tap is better than repeated presses; every extra press delays the next OH swing and can cost a full swing.

---

## 6. When to Tap (per guide)

In **all** cases the [guide](https://www.enhanceshaman.com/pages/guide/sync_stagger) says to wait until the relevant bar **passes** the halfway point — the macro only has the intended effect after that. ShammyTime’s action cue uses a **60%–85%** window (so players don’t tap too early), not right at 50%.

| Situation | What to do |
|-----------|------------|
| **OH hitting first** (wrong order) | Wait until **MH** passes the **halfway point** of its swing. Press the macro **once**. Usually enough to flip priority. |
| **Both hands hit at same time** (synced but not staggered) | Watch **MH**. When **MH** just passes the **halfway point**, press **once**. Creates a small MH lead. Do not press again. |
| **MH first but OH not in window** (drifting) | Wait until **OH** passes the **halfway** point of its swing. Press the macro **repeatedly**; each press holds OH back. Stop as soon as OH lines up behind MH. |

So (in **all** cases the guide says to wait until the bar **passes** the halfway point — not before):

- **OH-first or same-time:** Safe moment = **MH bar past 50%** (ShammyTime shows the cue in **60%–85%** to reduce early taps) → press **once**.
- **Drifting (MH first, OH not in window):** Safe moment = **OH bar past 50%** (ShammyTime: **60%–85%**) → press **repeatedly** until aligned.

---

## 7. How ShammyTime Implements This

### 7.1 Stagger Bar (colors and delta)

- **Delta** = time between the last MH and OH swings (we use absolute value for display; sign indicates which hand was first).
- **Sync threshold:** We use **0.5 s** as the “good” boundary, matching the guide’s sync window. Gold requires a **small MH lead** (delta &gt; 0); a small lead like **0.05 s** is within the target range (gold).

| State  | Condition              | Bar/text color | Meaning |
|--------|------------------------|----------------|--------|
| **Gold**    | MH first, small lead (e.g. 0.01–0.5 s) | Gold           | Good: synced and staggered (MH lead, OH within window). |
| **Same time** | MH first, delta ≈ 0.00 s   | Yellow         | Synced but not staggered; one tap at MH 50% creates a small MH lead (per guide: do not press again). |
| **Yellow**  | MH first, delta &gt; 0.5 s   | Yellow         | Drifting: MH leads but gap too large; Flurry efficiency drops. |
| **Red**     | OH first                     | Red            | Wrong order: resync recommended so MH can lead. |

So:

- **Gold** = target state (sync + stagger, small MH lead).
- **Same time** (0.00) = bar is not gold; tap once at MH 50% to create a small MH lead.
- **Yellow** = still MH first but outside 0.5 s window (drifting); resync can help.
- **Red** = OH first; resync to get MH lead.

### 7.2 Resync Action Cue (when to press the macro)

- **Goal:** Show the **correct instruction** at the **correct moment** — different zone and message for red vs yellow, per the guide.
- **Zones (ShammyTime uses 60%–85% so players don’t tap too early):**
  - **Red** (OH first): zone = **MH bar 60%–85%**. When in zone: **"Click once!"** When waiting: **"Wait for MH 60% — click once"**.
  - **Same time** (0.00): zone = **MH bar 60%–85%**. When in zone: **"Click once to stagger!"** When waiting: **"Wait for MH 60% — click once to stagger"** (per guide: one tap, do not press again).
  - **Yellow** (MH first but drifting): zone = **OH bar 60%–85%**. When in zone: **"Spam to align!"** When waiting: **"Wait for OH 60% — spam to align"**.
- **Cooldown:** After the zone passes, we show **"Observe…"** for a short duration (or until a couple of swing events) so the user doesn't press again too soon.

| Scenario   | Zone           | Waiting message                         | In-zone message        |
|-----------|----------------|-----------------------------------------|------------------------|
| Red       | MH 60%–85%     | Wait for MH 60% — click once            | Click once!            |
| Same time | MH 60%–85%     | Wait for MH 60% — click once to stagger | Click once to stagger! |
| Yellow    | OH 60%–85%     | Wait for OH 60% — spam to align         | Spam to align!         |
| Cooldown  | —              | —                                       | Observe…               |

- **Click zone:** The cue fires when the bar is in **60%–85%** (minimum 60% to avoid tapping too early). Zone width is configurable (default 0.25 = 60%–85%).

### 7.3 Constants and options (reference)

- **Sync window (good threshold):** **0.5 s** — same as guide. Stored as `GOOD_THRESHOLD` in code; options/descriptions use "0.5 s".
- **Same-time threshold:** **0.01 s** — when delta &lt; 0.01 we treat as "same time" (0.00); 0.05 s is gold. Stored as `SAME_TIME_THRESHOLD` in code.
- **Action cue:** Red and same-time use **MH bar 60%–85%** (one tap); yellow uses **OH bar 60%–85%** (spam). The 60% minimum reduces early taps. Messages are scenario-specific (see table above).
- **Optional:** "Also show for Yellow" lets the action cue appear when drifting (yellow) as well as when reversed (red) or same-time, so the addon can prompt resync when delta &gt; 0.5 s even if MH is still first.

## 8. Quick reference

| Term        | Meaning |
|------------|---------|
| **Sync**   | MH and OH swings within **0.5 s** of each other. |
| **Stagger**| MH lands first; OH follows within that 0.5 s window. |
| **Delta**  | Time between last MH and OH swing (we show absolute value; sign = which was first). |
| **Gold**   | MH first, small lead (e.g. 0.05–0.5 s) → target state. |
| **Same time** | Delta ≈ 0.00 s, MH first → bar yellow; one tap at MH 50% to create stagger. |
| **Yellow** | Delta &gt; 0.5 s, MH first → drifting. |
| **Red**    | OH first → resync to get MH lead. |
| **60%–85% MH** | Main hand bar in 60%–85% = safe moment for **one** resync tap (OH-first or same-time). |
| **60%–85% OH** | Off hand bar in 60%–85% = safe moment to **spam** resync until OH aligns (drifting case). |

---

*Reference: [Swing Sync and Stagger | Enhancement Shaman Guide](https://www.enhanceshaman.com/pages/guide/sync_stagger)*
