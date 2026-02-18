# ShammyTime Pressure System — In-Game Feel & Tuning Guide

This guide explains **how damage drives the pressure model** and **how tuning the main knobs changes how it feels in-game** (speed, weight, stickiness, and feedback). It is written so you can predict: *"If I change X, Y, and Z, the bar and tiers will feel more like this."*

**Related docs:** `docs/PRESSURE_PLAN.md` (design, reasoning, findings). Detail: `docs/PRESSURE_VALIDATION_AND_RESEARCH.md`, `docs/PRESSURE_CRIT_SPELL_WEIGHTING.md`, `docs/PRESSURE_BASELINE_TIME_VS_EVENTS.md`, `docs/PRESSURE_STARTUP_OVERDRIVE_WARMUP.md`.

---

## 0. Target Feel & Tuning Targets (Design Spec)

This section defines **what we want the gauge to feel like** and gives **concrete tuning targets** to aim for. Use it to judge whether the current tuning is "right" and to decide which knobs to change.

### 0.1 Purpose of the gauge

- The bar represents **how well you're doing damage right now** compared to *your own* recent baseline.
- It should feel **rewarding** when you perform above that baseline and **slightly challenging** when you push for higher tiers.
- It is driven by **your recent performance**, not fixed global numbers.

### 0.2 Tier meanings (T0–T5)

| Tier | Target feel |
|------|-------------|
| **T0** | Baseline. White hits and normal activity **move the bar** (you see response), but the **meaningful climb** comes from sustained or burst damage above your average. |
| **T1–T2** | "Sustained average" to "a bit above average." The bar should sit here during **steady rotation** without big cooldowns. **Target:** casual sustained DPS lands around T2. |
| **T3** | Clearly above average. Reached when you're **pushing** (good uptime, some burst). **Target:** engaged play without cooldowns can reach and hold T3. |
| **T4–T5** | "Burst" and "peak." Reached when **damage spikes** (cooldowns, crits, big hits). **Target:** bar should reach T4 during real burst windows; T5 is rare and earned. |

**Design rule:** **Bursts should have a larger effect than average damage.** So a short burst (e.g. cooldown window) should move the bar up more per second than the same DPS spread evenly. The ratio (fastCharge vs slow baseline) and overdrive are there to make that true.

### 0.3 When the bar should sit where

- **At fight start:** After the short startup seed (~2.4 s), the bar should reflect current damage. It can sit in T0–T2 until you build pressure.
- **During sustained rotation:** Bar **around T2** (maybe dipping to T1, touching T3 when you're doing well). Not stuck at T0; not constantly at T4.
- **After a burst:** Bar **rises toward T4 (or T5)** during the burst, then **drops back** over a few seconds toward T2–T3. It should not snap to T0 unless you actually stop DPS.
- **After you stop DPS:** Bar **drops** over a few seconds (not instant). Tier may demote after a short hold (tier help). Target: noticeable drop within ~3–5 s, full "cooldown" over ~10–15 s depending on tauSlow and tier hold.

### 0.4 Target speeds (concrete tuning goals)

Use these as **targets** when tuning; measure in-game and adjust knobs until you're in range.

| What | Target | Main levers |
|------|--------|-------------|
| **Rise after burst** | Bar and tier react within **~0.5–1.5 s** of damage spike; tier-up feels **snappy** but not twitchy. | tauFast, displayTauRise, resistance |
| **Drop after stopping** | Bar fill starts dropping within **~1–2 s**; tier demotion after **~3–6 s** (with tier help). | tauFast, tierHelp, tierHoldSec, edge slip |
| **Sustained "rest" tier** | Steady rotation (no cooldowns) → bar **around T2** (ratio roughly in **1.0–1.3** range after smoothing). | tierBase, tierStepPct, displayGain, resistance |
| **Burst tier** | Real burst window → bar reaches **T4** (or T5 for big spikes). Ratio in **1.5–2.5+** during burst. | Same + overdrive for single big hits |
| **Tier hold** | Once in a tier, **hold 4–8 s** before demoting on damage dip (so brief gaps don't punish). | tierHelp, tierHoldSec |
| **T0 shows activity** | White hits and small damage **move the bar** (visible fill change); real **climb** needs sustained or burst damage. | tierBase (T0 low), displayGain, resistance not so high that T0 is stuck) |

### 0.5 Ratio and score ranges (design intent)

- **pressureRatio ~1.0:** At baseline (fast and slow in balance). Bar in lower part of T0 / T1.
- **pressureRatio ~1.2–1.4:** Above baseline. Bar in T2–T3 range (sustained above average).
- **pressureRatio ~1.5–2.0+:** Burst. Bar in T4; with overdrive or very high ratio, T5.

Tuning **tierBase**, **tierStepPct**, **displayGain**, and **resistance** should be chosen so that these ratio bands line up with the tier meanings in 0.2. If the bar sits at T4 during normal rotation, thresholds are too low; if it never leaves T0–T1 during burst, they're too high or rise is too slow.

---

## 1. How Damage Flows Through the System (The Pipeline)

### 1.1 From combat log to “pressure”

1. **Every damage event** (your outgoing hits from the combat log) is read as a **raw amount** (no scaling by spell type).
2. That amount is added to three things at once:
   - **fastCharge** — short-term damage memory (decays quickly).
   - **slowCharge** — long-term damage memory (decays slowly).
   - **recentHitImpulse** — used for “impulse” feedback (e.g. shake, overdrive logic).
3. **Decay (each tick, ~0.05 s):**
   - `fastCharge` decays with time constant **tauFast** (default **1.55 s**).
   - `slowCharge` decays with time constant **tauSlow** (default **20 s**).
   - So after you stop hitting, the “fast” number drops quickly and the “slow” number drifts down slowly.

### 1.2 Pressure ratio (the core “speed” number)

- A **denominator** is built from `slowCharge` (scaled by tauFast/tauSlow) and mixed with `fastCharge` and **burstDamping** so that sudden bursts don’t blow the ratio to infinity:
  - `dampedDen = (steadyDen + fastCharge * burstDamping) / (1 + burstDamping)`, with a floor.
- **Pressure ratio** is:
  - `pressureRatio = fastCharge / dampedDen`
- So:
  - **Sustained, steady damage** → fast and slow track each other → ratio stays in a moderate range (e.g. ~1.0–1.5).
  - **Burst of damage** → fastCharge jumps, slowCharge lags → ratio **spikes up** (you’re “above” your recent average).
  - **Stop DPS** → fastCharge falls fast, slowCharge falls slowly → ratio **drops** over a few seconds.

So **damage directly sets the height of the ratio**; **tauFast/tauSlow and burstDamping** set **how quickly** that height moves and how spikey it is.

### 1.3 From ratio to the number that drives the bar and tiers

- **Display path:**
  - `targetDisplay = pressureRatio * displayGain` (default **displayGain = 1.20**).
  - This is smoothed with different rise/fall times (**displayTauRise** very fast ~0.07 s, **displayTau** slower ~0.42 s) → **pressureDisplaySmoothed**.
- That smoothed value becomes:
  - **instantScore** = **tierScore** (in simple mode).
- So the **bar fill and tier logic** are driven by this smoothed “score”, which is just **rescaled, smoothed pressure ratio**. More damage → higher ratio → higher score → bar fills more and you can reach higher tiers.

### 1.4 From score to tier (T0–T5)

- **Tier thresholds** are five numbers (e.g. T1 at ~1.05, T2 at ~1.17, …). They come from:
  - **tierBase** (default 2.10) and **tierStepPct** (default 11%), combined with **resistance** and **rubberband** into a single “difficulty” that scales the thresholds.
- **Before** comparing to thresholds, the score is adjusted:
  - **Edge resistance** — as you get closer to the *next* tier (within a segment), a resistance term increases (curve based on segment progress). So pushing from 80% to 100% of a segment feels “heavier”.
  - **Edge slip** — if you’ve been **idle** (no damage) for longer than **idleGrace** (0.9 s) and you’re past 65% of the segment, a small “slip” subtracts from the score so the bar can drift down when you stop DPS.
- **Effective score for tier** = **tierEvalScore** = `tierScore - edgeResistance - edgeSlip`.
- **Tier** = which threshold **tierEvalScore** crosses (T0–T5).
- **Tier momentum (tier help)** — when you’re already in a tier, a small bonus is added to “hold” score so you don’t instantly demote when damage dips; it decays when you’re idle. **tierHelp** and **holdSec** control how strong and how long that stickiness lasts.

### 1.5 Overdrive (big hits = instant tier jump)

- Every damage amount is recorded in a rolling history (cap 100 samples).
- After enough samples (**simpleOverdriveMinSamples**, 40), a **threshold** is computed from that history:
  - A high **percentile** (e.g. 98th) of hit sizes × **overdriveMultiplier**, and also compared to median×factor.
  - So only **big** hits (relative to your recent hits) can trigger overdrive.
- When a single hit **exceeds** that threshold, the model can **grant a +1 tier boost** (consumed on the next tick), so you can **jump a tier** from one large crit/hit instead of only from sustained pressure.
- **overdrivePercentile** and **overdriveMultiplier** tune how often and how “big” a hit must be to trigger this.

### 1.6 Visuals (bar fill, color, shake)

- **Bar fill** targets a 0–1 value from **tierEvalScore** and current tier (segment progress). That target is then passed through **pull resistance** (so the bar is “sticky” near full and doesn’t snap to 100% too easily).
- **Fill transfer** — when you tier up, the bar does a “transfer” animation: it moves from full toward the new segment’s fill. **Rubberband** tuning sets:
  - **fillTransferDropSec** — how long that motion takes.
  - **fillTransferRubberDamping** and **fillTransferRubberOscillations** — whether it overshoots and bounces (more rubberband → more bounce, longer settle).
- **Shake** — when fill is high (e.g. > 90%) and/or you take a big hit (relative to overload threshold), the gauge texture shakes. **shakeAmount** and **shakeFromDamage** scale that effect.

So: **damage** → **ratio** (speed of change from tauFast/tauSlow) → **smoothed score** → **tier + resistance/slip** → **bar position and tier**; **big hits** can also **overdrive** a tier; **tuning** changes thresholds, resistance, slip, stickiness, and visuals.

---

## 2. Speed and Responsiveness (What Actually Moves the Bar)

- **Faster reaction to damage:**
  - **tauFast** smaller (e.g. 0.8–1.0) → fastCharge decays quicker, so ratio reacts more to *recent* damage; bar can spike up and drop faster.
  - **displayTauRise** already very low (0.07) → bar rise is already snappy; most of “slowness” is from tauFast/tauSlow and resistance.
- **Slower, heavier feel:**
  - **tauFast** larger (e.g. 2.5) → fastCharge lingers, ratio changes more slowly.
  - **tauSlow** larger → denominator drifts up more slowly, so ratio stays elevated longer after you stop (slower “cooldown” drop).
- **Smoother, less spikey:**
  - **burstDamping** higher → denominator pulls up more when fastCharge spikes, so ratio spikes less for the same burst.
- **Bar “weight” (how hard it is to push the fill up):**
  - **Resistance** and **rubberband** (in Tier model) scale **edge resistance** and **thresholds** → higher values mean you need more sustained damage to reach the same tier and the bar feels heavier near the top of a segment.
  - **fillMass** and **fillPullResistStart** (from resistance/tierHelp) make the **visual** fill lag more and resist reaching 100% → bar feels heavier and slower to fill even when score is high.

So in-game: **damage** directly raises **fastCharge**; **tauFast/tauSlow** and **burstDamping** decide how quickly the **ratio** (and thus score) moves; **resistance/rubberband** and **fill** tuning decide how that score translates to **bar position and tier** and how “heavy” or “snappy” it feels.

---

## 3. Tuning Parameters You Can Change (DB/options)

These are the main knobs that affect **in-game feel** (all have defaults below; names are the DB keys used in Tier/options):

| Parameter | Default | Typical range | What it mainly affects |
|-----------|---------|----------------|------------------------|
| **pressureSimpleResistance** | 1.25 | 0.20–4.00 | Difficulty scale: thresholds, edge resistance, fill “mass”. Higher = harder to climb, heavier bar. |
| **pressureSimpleRubberband** | 1.10 | 0.20–3.00 | Difficulty + transfer animation: more bounce, longer drop, more slip when idle. |
| **pressureSimpleTierBase** | 2.10 | 0.20–10.00 | Base for tier thresholds. Higher = need higher score for T1 (and all tiers). |
| **pressureSimpleTierStepPct** | 11.00 | 1–30 | Step between tiers (%). Higher = bigger gap between tiers. |
| **pressureSimpleTierHelp** | 0.85 | 0–3 | Tier stickiness and fill landing floor. Higher = tiers hold longer, bar doesn’t drop as fast. |
| **pressureSimpleTierHoldSec** | 6.00 | 0.10–15 | Min time before demoting a tier. Longer = tiers stick longer. |
| **pressureSimpleOverdrivePercentile** | 98 | 85–99.5 | Which percentile of hit size sets overdrive threshold. Higher = only bigger hits overdrive. |
| **pressureSimpleOverdriveMultiplier** | 1.16 | 1–3 | Multiplier on that percentile. Higher = need even bigger hit to overdrive. |
| **pressureSimpleShakeAmount** | 1.00 | 0–2.5 | Gauge shake intensity. |
| **pressureSimpleShakeFromDamage** | 0.85 | 0–3 | How much big hits contribute to shake. |

Core pressure math (in ShammyTime_Pressure.lua, not always in options UI):

- **tauFast** (default 1.55), **tauSlow** (default 20), **displayGain** (1.20), **burstDamping** (1.20), **displayTau** / **displayTauRise** — see “Speed and responsiveness” above.

---

## 4. Five Tuning Examples: “If I tune X, Y, Z it feels like this”

### Example 1: “Snappy and easy” vs “Heavy and earned”

- **If you tune:** **resistance** down (e.g. **0.7**), **rubberband** down (e.g. **0.8**), keep **tierBase** and **tierStepPct** at default:
  - **In-game:** Tier thresholds are lower and edge resistance is lighter. The bar and tiers move up quickly with less sustained damage; the bar feels light and responsive. Good for a “fast feedback” feel.
- **If you tune:** **resistance** up (e.g. **1.8**), **rubberband** up (e.g. **1.5**):
  - **In-game:** Same damage produces a lower effective score (higher resistance, higher thresholds). Reaching T3/T4 feels like you had to maintain pressure longer; the bar feels heavier and more “earned”. Transfer animation is also longer and bouncier (rubberband).

---

### Example 2: “Reach high tiers fast” vs “Slow climb”

- **If you tune:** **tierBase** down (e.g. **1.5**), **tierStepPct** down (e.g. **7%**):
  - **In-game:** T1–T3 thresholds are lower and closer together. You’ll hit T1 and T2 with less total damage and in less time; the **speed** of tier climb increases. Good for seeing high tiers often in short fights.
- **If you tune:** **tierBase** up (e.g. **3.0**), **tierStepPct** up (e.g. **18%**):
  - **In-game:** You need a higher score for T1 and each step is bigger. Tier climb is slower; the same damage might keep you at T1–T2 instead of T3–T4. Feels like a longer grind to the top.

---

### Example 3: “Tiers stick / forgiving” vs “Tiers drop fast / live”

- **If you tune:** **tierHelp** up (e.g. **1.5**), **pressureSimpleTierHoldSec** up (e.g. **10**):
  - **In-game:** Once you reach a tier, momentum bonus is stronger and you can’t demote for 10 seconds. So when you stop DPS or dip, the tier and bar don’t drop immediately — **speed** of “cooldown” (drop) is reduced. Feels forgiving and stable.
- **If you tune:** **tierHelp** down (e.g. **0.3**), **holdSec** down (e.g. **3**):
  - **In-game:** Little tier help and short hold time. As soon as your damage and score dip, the tier can demote and the bar drops faster. Feels very “live” and reactive — you have to keep pumping to stay up.

---

### Example 4: “Rare, impactful overdrive” vs “Frequent tier jumps from big hits”

- **If you tune:** **overdrivePercentile** high (e.g. **99%**), **overdriveMultiplier** low (e.g. **1.05**):
  - **In-game:** Only hits in the top ~1% of your recent history (and barely above that) can overdrive. So **damage** still drives normal tier climb; overdrive is rare but feels like a real “big hit” moment when it happens.
- **If you tune:** **overdrivePercentile** lower (e.g. **90%**), **overdriveMultiplier** higher (e.g. **1.4**):
  - **In-game:** The overdrive threshold is lower (90th percentile) but the hit must be 1.4× that. So more hits qualify as “big enough,” and you’ll see **speed** of tier changes from single hits more often — more spikey, crit-driven tier jumps.

---

### Example 5: “Calm, minimal motion” vs “High impact, lots of feedback”

- **If you tune:** **shakeAmount** down (e.g. **0.4**), **shakeFromDamage** down (e.g. **0.3**), **rubberband** down (e.g. **0.8**):
  - **In-game:** Gauge barely shakes; transfer animation is shorter and less bouncy. **Damage** still drives the bar and tiers the same way, but **visually** it feels calm and minimal. Speed of *feedback* (shake) is reduced.
- **If you tune:** **shakeAmount** up (e.g. **1.5**), **shakeFromDamage** up (e.g. **1.2**), **rubberband** up (e.g. **1.5**):
  - **In-game:** Big hits and high fill produce strong shake; tier-up has a longer, bouncier transfer. Same underlying damage→score→tier, but **in-game feel** is more “impact” and motion — you really see and feel when damage is high and when you tier up.

---

## 5. Quick Reference: Damage → Feel

| You want… | Main levers |
|------------|-------------|
| Bar and tiers to **react faster** to damage | Lower **tauFast**; lower **resistance** / **rubberband**; lower **tierBase** / **tierStepPct**. |
| Bar to **drop slower** when you stop DPS | Higher **tauSlow**; higher **tierHelp** and **holdSec**. |
| **Easier** to reach high tiers | Lower **resistance**, **tierBase**, **tierStepPct**. |
| **Heavier**, more “earned” climb | Higher **resistance**, **rubberband**, **tierBase**, **tierStepPct**. |
| Tiers to **stick** after you reach them | Higher **tierHelp**, **holdSec**. |
| **More** tier jumps from single big hits | Lower **overdrivePercentile** and/or higher **overdriveMultiplier**. |
| **Less** visual motion | Lower **shakeAmount**, **shakeFromDamage**, **rubberband**. |
| **More** visual punch on big hits / tier-up | Higher **shakeAmount**, **shakeFromDamage**, **rubberband**. |

---

## 6. Summary

- **Damage** is added to **fastCharge** and **slowCharge** every hit; they decay with **tauFast** and **tauSlow**. **pressureRatio = fastCharge / dampedDen** is the core “speed” signal.
- That ratio (scaled and smoothed) becomes **tierScore**; **edge resistance** and **slip** turn it into **tierEvalScore**, which drives **tier** and **bar fill**. **Overdrive** lets single big hits jump a tier.
- **Tuning** changes how high the bar goes for the same damage (thresholds, resistance), how quickly it moves (tauFast/tauSlow, rubberband, hold/tierHelp), and how much you see and feel (shake, transfer animation). The five examples above show concrete “if you tune X, Y, Z then it feels like this” tradeoffs for speed, weight, stickiness, overdrive frequency, and visual feedback.
