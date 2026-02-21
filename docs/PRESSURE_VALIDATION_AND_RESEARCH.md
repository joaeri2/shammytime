# Pressure Math Validation & Tier Thresholds (BUI-7)

How to validate that pressure ratio, score, and tier thresholds match in-game feel (“slightly challenging but reachable”), plus notes on how other games handle similar systems.

---

## 1. What to validate

- **pressureRatio** and **tierScore** (or equivalent) distributions during typical play: sustained rotation, burst windows, after target switch, at fight start.
- Whether **tier thresholds** (from tierBase, tierStepPct, resistance, rubberband) put most of the distribution in the intended bands (see `PRESSURE_TUNING_GUIDE.md` §0.5):
  - ~1.0 → T0/T1
  - ~1.2–1.4 → T2–T3
  - ~1.5–2.0+ → T4/T5
- Whether **resistance** and **slip** make tiers feel “slightly challenging” (not trivial, not impossible).

---

## 2. Instrumentation / logging approach

- **Option A — Dev-only dump:** Under `/st dev` (or a flag), periodically sample `pressureRatio`, `tierScore`, `tierEvalScore`, current tier, and optionally `fastCharge`/`slowCharge`. Write to a ring buffer or print every N seconds. Export to chat or file for analysis.
- **Option B — Combat log style:** On each pressure tick (or every K ticks), append one line: `time, ratio, score, tier, resistance, slip`. Post-fight, analyze distributions (histograms, percentiles) and compare to target bands in the tuning guide.
- **Concrete targets:** Log at least 2–3 minutes of sustained combat and 1–2 minutes including burst. Check:
  - Ratio in “sustained” segments: mostly 1.0–1.4?
  - Ratio in “burst” segments: peaks 1.5–2.5+?
  - Tier distribution: T2–T3 common during rotation, T4 during cooldowns?

If ratios are systematically low or high relative to tiers, adjust **tierBase**, **tierStepPct**, **displayGain**, or **resistance** per the tuning guide.

---

## 3. How other games do it (research notes)

- **Dynamic Difficulty Adjustment (DDA):** Games often use performance metrics (e.g. DPS, success rate) to adapt challenge in real time. The pressure gauge is similar: it compares *current* performance to a *recent* baseline (our slowCharge / time window).
- **Player-adaptive baselines:** Research uses temporal and data-driven models to tailor difficulty to the player. Our time-based decay (tauFast/tauSlow) is a simple form of that; event-based (e.g. last N events) is another (see `PRESSURE_BASELINE_TIME_VS_EVENTS.md`).
- **Takeaway:** We’re not reinventing the wheel—ratio vs. baseline and tier bands are a standard pattern. The main levers are (1) baseline definition (time vs. events), (2) threshold placement (tierBase, stepPct), and (3) feedback speed (tauFast/tauSlow, display smoothing). Validation should confirm that our current formula and defaults put the distribution where we want it; if not, adjust thresholds or formula per the tuning guide and re-measure.

---

## 4. Proposed threshold/formula changes (only if misaligned)

- If the bar sits **too high** (often T4 in normal rotation): increase **tierBase** or **tierStepPct**, or **resistance**.
- If the bar **never reaches T4** in burst: decrease those, or increase **displayGain**, or check **tauFast** (faster rise).
- If **tiers feel too sticky**: reduce **tierHelp** / **tierHoldSec**.
- If **tiers drop too fast**: increase **tierHelp** / **tierHoldSec** or **tauSlow**.

All knobs are documented in `PRESSURE_TUNING_GUIDE.md` §3 and §5.
