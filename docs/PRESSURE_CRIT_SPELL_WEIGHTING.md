# Crit and Spell Weighting for Pressure (BUI-8)

Design and tradeoffs for feeding **crits** and/or **certain spells** (and optionally **number of targets hit**) into the pressure model so the gauge better matches “good play” and improves feel.

---

## 1. Current state

- **Production** (`ShammyTime_Pressure.lua`): Every damage event adds its **raw amount** to fastCharge, slowCharge, and recentHitImpulse. No crit or spell weighting.
- **POC** (`ShammyTime_POC_CombatCapture.lua`): Crits feed **extra** into fastCharge (and impulse) via `critBonusMult` (e.g. 2.0): crit amount × 2 into fastCharge, normal amount into slowCharge. So crits raise the **ratio** (fast/slow) more than white hits.

---

## 2. Design options

### 2.1 Crit weighting

- **Option A — Crit bonus on fastCharge only (POC-style):** Crit hit of amount X → fastCharge += X × critMult (e.g. 1.5–2.0), slowCharge += X. Effect: ratio spikes more on crits; burst windows with many crits feel more impactful.
- **Option B — Crit bonus on both, more on fast:** e.g. fastCharge += X × 1.5, slowCharge += X × 1.1. Tracks crits in baseline but still favors recent crits.
- **Option C — No crit weighting (current production):** Simplest; gauge reflects raw DPS. Crits only matter via overdrive (big hit = possible tier jump).

### 2.2 Spell weighting

- **Option A — Weight specific spells:** e.g. Stormstrike, Earth Shock, Lavaburst count 1.2×; white swings 1.0×. Rewards “good” rotation; requires spell ID maintenance and can feel opaque.
- **Option B — Category weights:** e.g. “Shocks” 1.1×, “melee” 1.0×. Coarser, easier to tune.
- **Option C — No spell weighting (current):** All damage equal; easiest to explain and maintain.

### 2.3 Number of targets hit

- **Option A — Multi-target bonus:** If event hits N targets, feed amount × f(N) (e.g. 1 + 0.1×(N-1)) into fastCharge so AoE/cleave is rewarded. Requires multi-target info from combat log where available.
- **Option B — Ignore (current):** Single target only for pressure; multi-target is implicit in total damage.

---

## 3. Tradeoffs

| Approach | Pros | Cons |
|----------|------|------|
| **Crit bonus (POC-style)** | Burst and crit streaks feel better; aligns with “big hit” feedback. | Slightly more code; need to tune critMult; baseline (slowCharge) still raw so ratio is “crit-aware”. |
| **Spell weights** | Can reward rotation and key abilities. | Maintenance (spell IDs), balance patches; can feel arbitrary if not documented. |
| **Multi-target** | Cleave/AoE builds see pressure reflect multi-target. | Combat log support; tuning f(N); may dilute single-target “skill” signal. |
| **Raw only (current)** | Simple, predictable, no hidden weights. | Gauge may under-react to “good” crit/rotation play. |

---

## 4. Recommendation (short term)

- **Crit:** Introduce an optional **crit bonus on fastCharge only** (as in POC), with a tunable multiplier (e.g. 1.0 = off, 1.5–2.0 = on). Keep slowCharge raw so the baseline stays comparable across gear/crit%. Document in options so players understand “pressure favors burst and crits.”
- **Spell:** Defer spell weighting until we see how crit-only feels; if we add it, start with a small set (e.g. Stormstrike, shocks) and document in the tuning guide.
- **Multi-target:** Defer until we have a clear use case and combat log support.

---

## 5. Implementation notes

- POC: `ShammyTime_POC_CombatCapture.lua` — parse crit from combat log, `feedAmount = amount * PS.critBonusMult` for crits into fastCharge; normal amount into slowCharge.
- Production: `ShammyTime_Pressure.lua` — combat log handler adds same amount to fast and slow; no crit flag. Adding crit would require (1) reading crit from the log, (2) applying multiplier to the amount fed to fastCharge only (or to both with different factors), (3) exposing multiplier in options/DB.
