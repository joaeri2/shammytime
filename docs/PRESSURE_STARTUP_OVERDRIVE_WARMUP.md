# Startup and Overdrive Warmup Review (BUI-10)

Review of the **2.4 s slowCharge seed** and **overdrive 40–100 sample warmup**. Do they cause inconsistent feel at fight start or after target switches? Minimal change proposals if needed.

---

## 1. Current behavior

### 1.1 Startup seed (first ~2.4 s)

- **Where:** `ShammyTime_Pressure.lua` — after decay, if `firstPressureAt` is set and `fastCharge > 0`, we compute a **seed** for slowCharge over a **warm window** (`startupSeedWindowSec`, default **2.40** s).
- **Formula:** `age = now - firstPressureAt`. Over the window, a **fade** goes from 1 → 0. `seedSlow = (fastCharge * (tauSlow/tauFast)) * fade`. If `slowCharge < seedSlow`, we set `slowCharge = seedSlow`.
- **Effect:** For the first 2.4 s, the denominator is lifted toward a value derived from fastCharge, so the ratio doesn’t spike to infinity and then collapse when slowCharge is still near zero. After 2.4 s, seed is fully faded and slowCharge is purely time-based.

### 1.2 Overdrive warmup (40–100 samples)

- **Where:** `Pressure/Models/Tier.lua` — overdrive uses a rolling buffer of hit amounts (cap **100**). **simpleOverdriveMinSamples** = **40**: overdrive is inactive until we have at least 40 samples.
- **Effect:** For the first 40 hits, no single hit can grant a +1 tier overdrive boost. So at fight start (or after target switch with fresh state), overdrive “kicks in” only after 40 hits.

---

## 2. Possible inconsistency / feel issues

- **Startup seed (2.4 s):** If fights are very short (&lt; 2.4 s) or the player expects “instant” baseline, the bar might feel like it’s “catching up” for the first 2.4 s. If we **removed** the seed, the first hit would spike ratio very high then drop as slowCharge builds—likely worse.
- **Overdrive (40 samples):** After target switch or fight start, the first 40 hits never trigger overdrive. So tier jumps from “big hit” are delayed. On the other hand, with 0 samples a single early crit could overdrive too easily (threshold undefined).

---

## 3. Minimal change proposals

### 3.1 Startup seed

- **Keep 2.4 s** as default; it avoids spike-then-collapse.
- **Optional tunable:** Expose `startupSeedWindowSec` in options (already in PS state) so testers can try **1.0–1.5 s** for a quicker “settle.” If shorter window feels better without big spike, consider lowering default to ~1.5 s.
- **No change to formula:** Seed formula (fastCharge → scaled slowCharge with fade) is sound; only duration might be tuned.

### 3.2 Overdrive warmup

- **Keep 40 minimum samples** to avoid undefined threshold; 100 cap is fine.
- **Optional:** Add a **softer warmup** so the first 40–100 samples use a **blend** (e.g. threshold = percentile from available samples, but scaled down until we have 40). That would allow some overdrive effect earlier, with smaller boost. More invasive; only if we see strong feedback that “overdrive never fires at fight start.”
- **Target switch:** If we ever reset overdrive buffer on target switch, we’d get the same “no overdrive for 40 hits” again; document that as intentional so overdrive is “recent-history relative.”

---

## 4. Summary

- **2.4 s seed:** Reduces spike-then-collapse; consider exposing and optionally lowering to ~1.5 s if early fight feels slow.
- **40–100 overdrive:** Reasonable; no change unless we want a softer warmup (blend before 40 samples). Document that overdrive is inactive for the first 40 hits so expectations are clear.
