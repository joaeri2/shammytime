# Stagger Dynamic Click Logic Spec (Current Implementation)

This document describes the **actual runtime logic** currently implemented in `ShammyTime_StaggerBar.lua`.
It is intended as a verification spec.

## 0. Code Anchors (for verification)

- Constants and buffers: `ShammyTime_StaggerBar.lua:22`
- Lag compensation: `ShammyTime_StaggerBar.lua:208`
- Dynamic MH zone math: `ShammyTime_StaggerBar.lua:330`
- Click-window intersection solver: `ShammyTime_StaggerBar.lua:360`
- Mode selection (`normal` / `hold_now`): `ShammyTime_StaggerBar.lua:401`
- Red zones + dynamic marker render: `ShammyTime_StaggerBar.lua:1485`
- Text output and cue state machine: `ShammyTime_StaggerBar.lua:1620`
- Fight score metric and reset: `ShammyTime_StaggerBar.lua:113`, `ShammyTime_StaggerBar.lua:1992`
- Resync macro simulation (`OH -> 50%`): `ShammyTime_StaggerBar.lua:952`

## 1. Goal

For every frame, compute the best resync guidance using live MH/OH swing progress, current weapon speeds, and lag buffer.

The system should tell the player one of:
- `Click!`
- `Click Multiple Times!` (hold-type case)
- wait guidance (`Wait: OH < 50%`, `Wait: OH < 55%`, `Wait for marker`, `Synced: wait for marker`)

## 2. Core Constants

- `GOOD_THRESHOLD = 0.5` seconds (target stagger max)
- `SAME_TIME_THRESHOLD = 0.01` seconds
- `RESYNC_OH_ARM = 0.50` (macro can affect OH from here)
- `RESYNC_CLICK_BUFFER_PROGRESS = 0.05` (5% early safety buffer)
- `RESYNC_LOOKAHEAD_CYCLES = 3.0`
- `RESYNC_FIXED_BUFFER_SEC = 0.008` (8ms)
- `RESYNC_MAX_LAG_COMP_SEC = 0.200`
- `RESYNC_READY_EPSILON = UPDATE_INTERVAL * 1.5` (about 24ms)

Resulting fixed OH threshold:
- `ohClickMin = 0.50 + 0.05 = 0.55`

## 3. Inputs Used Every Frame

- Current MH progress (`mhProgress`), OH progress (`ohProgress`)
- Current hand cycle times (`mhCycleSpeed`, `ohCycleSpeed`)
- Current lag compensation from `GetNetStats`
- Current swing delta/sign for resync-needed detection

Lag compensation:

`lagCompSec = clamp(worldOrHomeLagSec + 0.008, 0.008, 0.200)`

## 4. Resync-Needed Gate

Action cue logic only matters when resync is needed (plus explicit hold mode).

`needsResync` is true when any of these apply:
- OH-first (`deltaSign < 0`)
- same-time (`delta < 0.01`)
- drifting (`delta > 0.5`) if drifting cue option is enabled

## 5. Dynamic MH Target Zone (Time-Based, Not Fixed 50-60)

The old fixed MH 50%-60% model is no longer used.

A dynamic MH zone is derived from the post-click timing rule:
- resync click resets OH to ~50%
- from that moment, OH next swing is roughly `0.5 * ohCycleSpeed` away
- MH should still land first and within the allowed lead window

Definitions:
- `minLead = 0.01`
- `maxLead = 0.5 - lagSafety`, where `lagSafety = clamp(lagCompSec, 0, 0.15)`

Then:
- `ohHalf = 0.5 * ohCycleSpeed`
- `mhRemainingLo = clamp(ohHalf - maxLead, 0, mhCycleSpeed)`
- `mhRemainingHi = clamp(ohHalf - minLead, 0, mhCycleSpeed)`

Convert remaining-time bounds into MH progress bounds:
- `mhZoneLo = 1 - (mhRemainingHi / mhCycleSpeed)`
- `mhZoneHi = 1 - (mhRemainingLo / mhCycleSpeed)`

This zone updates automatically with haste and speed differences.

## 6. Finding the Next Click Window

Build future intervals over lookahead horizon:
- MH intervals where `MH in [mhZoneLo, mhZoneHi]`
- OH intervals where `OH in [0.55, 1.0]`

Find first overlap `[tStart, tEnd]`.

Client action time is adjusted earlier for lag:
- `tActionStart = max(0, tStart - lagCompSec)`
- `tActionEnd = max(tActionStart, tEnd - lagCompSec)`

Marker outputs:
- `markerOh = OH progress at tActionStart`
- `markerMh = MH progress at tActionStart`
- `latestSafeOh = OH progress at tActionEnd`

Stability clamp:
- marker and late edge are never rendered below `ohClickMin` (55%).

## 7. Mode Selection

After computing dynamic zone and intersection, mode is selected as follows.

### 7.1 Hold Mode (`hold_now`)

Triggered when:
- `ohProgress >= 0.55`
- and state is **not** same-time (`delta >= 0.01` or OH-first/drifting state)
- and there is **no direct computed click** before OH's next swing:
  - `directClickBeforeSwing = (tActionStart exists) and (tActionStart <= holdLatestSec + epsilon)`
  - where `holdLatestSec = max(0, tToOhSwing - lagCompSec)`

Output:
- mode = `hold_now`
- helper text = `Click Multiple Times!`
- dynamic marker is shown in yellow at current hold-start point

### 7.2 Normal Mode (`normal`)

If neither special mode applies and an intersection exists:
- mode = `normal`
- `Click!` appears when `nextClickIn <= epsilon`

## 8. Action Cue State Machine

States:
- `idle`
- `resync_needed`
- `click_now`
- `cooldown`

Flow:
- `idle -> resync_needed` when `needsResync`
- `resync_needed -> click_now` when click timing is now
- `click_now -> cooldown` when leaving click window without resolving
- `cooldown -> resync_needed` after cooldown timeout or 2 swing events
- any state -> `idle` when resync no longer needed

Special override:
- `hold_now` guidance is shown immediately and persistently while condition holds.
- same-time states suppress hold and stay on normal wait/click guidance.

## 9. Text Output Rules

Priority order:
1. `hold_now` -> `Click Multiple Times!`
2. state machine `click_now` -> `Click!`
3. fallback wait messages while resync is needed:
   - `Wait: OH < 50%`
   - `Wait: OH < 55%`
   - `Wait for marker`
   - `Synced: wait for marker` (same-time state)

## 10. Visual Spec

## 10.1 Layering

Top to bottom:
1. Text (`delta`, helper, fight score)
2. Markers frame (fixed line, dynamic line, OH cursor)
3. Red no-click overlays
4. White MH/OH bars and frame art

## 10.2 Marker and Zone Meaning

- Fixed red line at 50%: OH arm boundary
- Early red zone 50%-55%: too early, do not click
- Dynamic marker:
  - primary/actionable position is read from the OH bar
  - green in normal mode
  - yellow in hold mode
- Late red zone (from `latestSafeOh` to 100%): too late for this pass
- Live OH cursor: green, tracks current OH progress

Out of combat:
- red no-click overlays are hidden

## 10.3 OH Bar Drawing (concept)

```text
OH progress -> 0%                                              100%
               |------------------|-----|------------------|------|
               white              red   white valid area    red late
                                  50-55%                    do not click
                                  (early no-click)

fixed red line at 50%
dynamic marker = ideal click x-position (green/yellow)
```

## 10.4 Marker Placement (concept)

The click timing marker is an **OH timing marker**.
It may be mirrored on MH at the same X only as alignment aid.

```text
MH: [==============================|==============================]  (optional mirror)
                                   ^ same X alignment line
OH: [==================|====|====================|==============]
                       ^50   ^55       ^dynamic(click)     ^latestSafe
```

## 11. Fight Score % (Right-Side Yellow Text)

Per-fight metric:
- `good`: samples where MH-first and `0.01 <= delta <= 0.5`
- `total`: all scored samples with known sign/delta
- displayed as rounded `good/total * 100`

Reset behavior:
- resets on `PLAYER_REGEN_DISABLED` (start of next fight)

Option:
- `Show Fight Score %` toggle controls visibility

## 12. Event Sources Affecting Timing

The logic uses/updates from:
- `SWING_DAMAGE` / `SWING_MISSED` (actual swing timing)
- `SPELL_EXTRA_ATTACKS` amount (skip next N MH extra swings)
- incoming parry detection (`SWING_MISSED` with player as dest, missType `PARRY`) -> parry haste adjustment
- `UNIT_ATTACK_SPEED` (retime cycles immediately for haste changes)
- `UNIT_SPELLCAST_START` + `UNIT_SPELLCAST_SUCCEEDED` (non-instant cast completion resets both timers)
- `PLAYER_REGEN_ENABLED` (clear visuals)
- `PLAYER_REGEN_DISABLED` (fight score reset + speed refresh)

## 13. Options That Affect Behavior

- `Show Fight Score %` controls right-side yellow score visibility (`ShammyTime_Options.lua:1765`).
- `Enable Action Cue` turns timing prompts on/off (`ShammyTime_Options.lua:1823`).
- `Also Show for Drifting` allows cueing for MH-first but too-wide gap (`ShammyTime_Options.lua:1832`).
- `Observe Duration` sets cooldown state duration (`ShammyTime_Options.lua:1842`).

## 14. Resync Macro Simulation Rule

`/st resync` simulation in addon behavior:
- if `OH < 50%`: no effect
- if `OH >= 50%`: OH timer is pulled back to 50%

Then real combat log swings overwrite simulated timing naturally.

## 15. Validation Cases (Expected)

1. `MH low`, `OH high` and OH will swing before MH reaches dynamic zone:
- expected mode: `hold_now`
- expected text: `Click Multiple Times!`

2. `MH high`, `OH high`:
- if state is same-time, hold is suppressed -> `Synced: wait for marker` until click window opens.
- if state is not same-time and no direct click exists before OH swings -> `hold_now`.

3. `OH < 50%` with resync needed:
- expected fallback text: `Wait: OH < 50%`

4. `OH between 50% and 55%` with resync needed:
- expected fallback text: `Wait: OH < 55%`

5. Inside computed dynamic click window now:
- expected text: `Click!`

## 16. Worked Examples (2.7/2.7 and 2.7/2.5)

Assumptions for all examples:
- `lagCompSec = 0.038` (example: 30ms ping + 8ms fixed buffer)
- `ohClickMin = 55%`
- `needsResync = true` (so helper text is allowed to show)

### 16.1 Dynamic MH Window by Weapon Speeds

Using the implemented formula:
- `minLead = 0.01`
- `maxLead = 0.5 - lagSafety = 0.5 - 0.038 = 0.462`
- `ohHalf = 0.5 * ohSpeed`
- convert to MH progress window `[mhZoneLo, mhZoneHi]`

Results:
- `MH 2.7 / OH 2.7` -> `mhZone = 50.37% .. 67.11%`
- `MH 2.7 / OH 2.5` -> `mhZone = 54.07% .. 70.81%`

So with faster OH (2.5), MH must be later in its cycle before click is valid.

### 16.2 Cases: MH 2.7 / OH 2.7

| Case | Start (MH/OH) | Solver mode | `tActionStart` | `markerOH` | `latestSafeOH` | Text now (with `needsResync=true`) |
|---|---:|---|---:|---:|---:|---|
| A. in-window now | 58% / 62% | `normal` | 0.000s | 62.0% | 69.7% | `Click!` |
| B. OH not armed | 55% / 40% | `nil` | - | - | - | `Wait: OH < 50%` |
| C. armed but in buffer | 56% / 52% | `normal` | 0.043s | 55.0% | 61.7% | `Wait: OH < 55%` |
| D. hold case | 10% / 90% | `hold_now` | 0.000s | 90.0% | 98.6% | `Click Multiple Times!` |
| E. high/high (same-time state) | 90% / 90% | `normal` (hold suppressed) | 1.717s | 55.0% | 65.7% | `Synced: wait for marker` |
| F. wait for marker | 45% / 70% | `normal` | 0.107s | 74.0% | 90.7% | `Wait for marker` |
| G. near-sync (OH ahead ~1.1ms) | 52.00% / 52.04% | `normal` | 0.042s | 55.0% | 65.7% | `Wait: OH < 55%` |

### 16.3 Cases: MH 2.7 / OH 2.5

| Case | Start (MH/OH) | Solver mode | `tActionStart` | `markerOH` | `latestSafeOH` | Text now (with `needsResync=true`) |
|---|---:|---|---:|---:|---:|---|
| A. in-window now | 58% / 62% | `normal` | 0.000s | 62.0% | 74.3% | `Click!` |
| B. OH not armed (future window exists) | 55% / 40% | `normal` | 0.337s | 55.0% | 55.6% | `Wait: OH < 50%` |
| C. armed but in buffer | 56% / 52% | `normal` | 0.037s | 55.0% | 66.5% | `Wait: OH < 55%` |
| D. hold case | 10% / 90% | `hold_now` | 0.000s | 90.0% | 98.5% | `Click Multiple Times!` |
| E. high/high (same-time state) | 90% / 90% | `normal` (hold suppressed) | 1.692s | 57.7% | 75.8% | `Synced: wait for marker` |
| F. wait for marker | 45% / 70% | `normal` | 0.207s | 78.3% | 96.4% | `Wait for marker` |
| G. near-sync (OH ahead ~1.1ms) | 52.00% / 52.04% | `normal` | 0.036s | 55.0% | 70.8% | `Wait: OH < 55%` |

### 16.4 Sanity Check: “MH 10 / OH 40” Example

This is the case you called out earlier.

- `MH 2.7 / OH 2.7`:
  - first valid marker appears at about `OH 79.0%`
  - this matches the intuition of waiting roughly to `OH ~80%`
- `MH 2.7 / OH 2.5`:
  - first valid marker is later, about `OH 86.1%`
  - because faster OH requires MH to be further progressed (higher dynamic MH zone)

---

If anything here does not match your intended rule set, we can treat this as the baseline and adjust one rule at a time.
