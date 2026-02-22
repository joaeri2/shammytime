# Pressure Visual — Design, Reasoning & Findings

This document explains **what we want the Pressure Visual to be**, **how it currently works**, and **what we found** so we can use that reasoning to work on the system. Status and tasks live in Linear; this doc is for design and findings only.

---

## 1. Purpose & design intent

The Pressure Visual (gauge + tiers T0–T5) should:

- Represent **how well the player is doing damage right now** compared to a baseline.
- Feel **rewarding** when they perform above that baseline and **slightly challenging** when they push for higher tiers.
- Be driven by **each player’s own recent performance** (not fixed global numbers), so it adapts to the player.
- **Design rule:** Bursts should have a **larger effect** than average damage (cooldown windows / crits move the bar more than the same DPS spread evenly).

---

## 2. Target feel (summary)

| Tier | Target feel |
|------|-------------|
| **T0** | Baseline. White hits move the bar; meaningful climb comes from sustained or burst damage above average. |
| **T1–T2** | Sustained average → a bit above. Bar should sit here during steady rotation. **Target:** casual sustained DPS lands around T2. |
| **T3** | Clearly above average. Engaged play without cooldowns can reach and hold T3. |
| **T4–T5** | Burst and peak. Bar reaches T4 during real burst windows; T5 is rare and earned. |

**When the bar should sit where:**

- **Fight start:** After ~2.4 s seed, bar reflects current damage; can sit T0–T2 until pressure builds.
- **Sustained rotation:** Bar **around T2** (dip to T1, touch T3 when doing well). Not stuck at T0; not constantly at T4.
- **After a burst:** Bar rises toward T4/T5, then **drops back** over a few seconds toward T2–T3.
- **After you stop DPS:** Bar drops over a few seconds; tier may demote after a short hold. Target: noticeable drop within ~3–5 s.

**Ratio bands (design intent):**

- **pressureRatio ~1.0** → T0/T1 (baseline).
- **~1.2–1.4** → T2–T3 (sustained above average).
- **~1.5–2.0+** → T4/T5 (burst).

Full target speeds and tuning goals: **`docs/PRESSURE_TUNING_GUIDE.md`** §0.

---

## 3. Current model (what’s in the code)

- **Damage:** Every outgoing damage event adds its **raw amount** to fastCharge, slowCharge, and recentHitImpulse. **No crit or spell weighting in production.**
- **Baseline:** **Time-based** — slowCharge decays with tauSlow (~20 s). pressureRatio = fastCharge / dampedDen(slowCharge). “Above baseline” = above a ~20 s exponential moving average.
- **Tiers:** Score = smoothed ratio × displayGain; tier thresholds from tierBase (2.03), tierStepPct (11%), resistance, rubberband. Edge resistance and slip make the bar heavier near segment top; tier help adds stickiness.
- **Overdrive:** **Event-based** — last **100 hit amounts** define a percentile (e.g. 98th) × multiplier; a single hit above that can grant +1 tier. **40 samples minimum** before overdrive is active.
- **Startup:** First **~2.4 s** we seed slowCharge from fastCharge to avoid spike-then-collapse.

**Code refs:** `ShammyTime_Pressure.lua` (OnPressureTick, combat log, startup seed), `Pressure/Models/Tier.lua` (thresholds, overdrive 40/100, resistance, slip). Full pipeline: **`docs/PRESSURE_TUNING_GUIDE.md`** §1–6.

---

## 4. What we found (reasoning & recommendations)

### 4.1 Validation

- **What to check:** Log pressureRatio and tierScore distributions; compare tier placement to the ratio bands above. Confirm tiers feel “slightly challenging but reachable.”
- **Research:** Our approach (ratio vs. baseline, tier bands) aligns with common DDA / player-adaptive patterns; we’re not reinventing the wheel.
- **If misaligned:** Adjust tierBase, tierStepPct, displayGain, or resistance per the tuning guide; re-measure.

**Detail:** **`docs/PRESSURE_VALIDATION_AND_RESEARCH.md`** (instrumentation options, when to change thresholds).

### 4.2 Crit and spell weighting

- **Current:** Production = raw damage only. POC = crit bonus on fastCharge (critBonusMult 2.0) so crits raise the ratio more.
- **Recommendation:** Add an **optional crit bonus on fastCharge only** (tunable multiplier, e.g. 1.5–2.0). Defer spell weighting and multi-target until crit is in and feels good.

**Detail:** **`docs/PRESSURE_CRIT_SPELL_WEIGHTING.md`** (design options, tradeoffs, implementation refs).

### 4.3 Baseline: time vs event-based

- **Current:** Main baseline = **time-based** (slowCharge, tauSlow). “Last 100” = **overdrive only** (100 hit amounts for percentile threshold), not the main baseline.
- **Recommendation:** Keep overdrive as-is. **Prototype** an event-based main baseline (e.g. last 50/100 events) in a branch and compare feel; then document the choice.

**Detail:** **`docs/PRESSURE_BASELINE_TIME_VS_EVENTS.md`** (pros/cons, where “last 100” applies).

### 4.4 Startup and overdrive warmup

- **2.4 s seed:** Avoids spike-then-collapse. **Proposal:** Optionally expose `startupSeedWindowSec` in options; consider default ~1.5 s if tests feel better.
- **40–100 overdrive samples:** Keep 40 minimum; 100 cap is fine. Optional softer warmup (blend before 40 samples) only if overdrive at fight start feels wrong.

**Detail:** **`docs/PRESSURE_STARTUP_OVERDRIVE_WARMUP.md`** (current behavior, minimal change proposals).

---

## 5. Related docs (where to find more)

| Doc | Contents |
|-----|----------|
| **`docs/PRESSURE_TUNING_GUIDE.md`** | Full pipeline (§1), target feel & tuning targets (§0), knobs (§3), examples (§4), quick reference (§5). |
| **`docs/PRESSURE_VALIDATION_AND_RESEARCH.md`** | What to validate, instrumentation, research notes, threshold changes. |
| **`docs/PRESSURE_CRIT_SPELL_WEIGHTING.md`** | Crit/spell/multi-target design, tradeoffs, recommendation. |
| **`docs/PRESSURE_BASELINE_TIME_VS_EVENTS.md`** | Time vs event baseline, where “last 100” applies. |
| **`docs/PRESSURE_STARTUP_OVERDRIVE_WARMUP.md`** | 2.4 s seed and 40/100 overdrive warmup review. |

Design docs live in the repo (`docs/`) and are versioned with the code; Linear is used for status and tasks.
