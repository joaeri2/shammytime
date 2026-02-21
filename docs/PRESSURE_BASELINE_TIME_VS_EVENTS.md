# Baseline: Time-Based vs Event-Based (BUI-6)

Current baseline is **time-based** (slowCharge with tauSlow ~20 s). This doc summarizes pros/cons and where an **event-based baseline** (e.g. “last 100 combat log events”) could apply.

---

## 1. Current: time-based baseline

- **slowCharge** accumulates all damage and decays with **tauSlow** (~20 s).
- **pressureRatio = fastCharge / dampedDen(slowCharge)**.
- “Baseline” = effectively an exponential moving average of damage over ~20 s. Same number of events in 5 s vs 20 s can produce different baseline levels (time matters, not event count).

**Pros:** Simple; smooth; no buffer management; works with variable event rate (idle, then burst).  
**Cons:** After target switch or burst, “recent” may feel like “last 20 s” rather than “last N hits”; players may expect “last few actions” to define the baseline.

---

## 2. Event-based baseline (e.g. last N events)

- Define baseline from **last N damage events** (e.g. N = 50 or 100): e.g. sum of amounts (or EMA over events) for those events.
- Ratio = fastCharge / eventBaseline (with appropriate scaling and floor).

**Pros:** Intuitive (“my last 100 hits”); same “window” in event space across different attack speeds; aligns with “last 100” already used for **overdrive** (hit-size percentile).  
**Cons:** Need a ring buffer; variable *time* per N events (N hits in 5 s vs 30 s); edge cases when event count &lt; N (warmup).

---

## 3. Where “last 100” applies today

- **Overdrive only:** In `Pressure/Models/Tier.lua`, the **overdrive** path uses a **cap of 100 hit amounts** (and a minimum of 40 samples before overdrive is active). That is **event-based** (last 100 hits), not time-based.
- **Main baseline (ratio denominator):** Currently **time-based** only (slowCharge). So:
  - **Main baseline:** time-based (slowCharge, tauSlow).
  - **Overdrive threshold:** event-based (last 100 hit sizes → percentile).

---

## 4. Should “last 100 events” apply to main baseline, overdrive, or both?

| Option | Main baseline | Overdrive | Comment |
|--------|----------------|-----------|--------|
| **A — Current** | Time (slowCharge) | Events (100 hits) | No change. |
| **B — Main event-based** | Last N events (e.g. 100) | Events (100 hits) | Both aligned to “last N events”; ratio would be “fast vs last N events.” Requires prototype. |
| **C — Main event-based, overdrive same** | Last N events | Keep 100 hits | Consistent event window for ratio; overdrive unchanged. |

**Recommendation:** Keep **overdrive** as-is (event-based, 40–100 samples). **Main baseline:** document that time-based is current; **prototype** an event-based main baseline (e.g. last 100 events → sum or EMA) in a branch and compare feel (fight start, target switch, sustained vs burst). If event-based feels better for “above my recent performance,” consider Option B or C; otherwise stay time-based and document the choice.

---

## 5. Clarification summary

- **“Last 100 events”** today = **overdrive only** (100 hit amounts for percentile threshold).
- **Main baseline** = time-based (slowCharge, tauSlow). No event-based main baseline yet.
- Next step: implement an optional or parallel event-based main baseline (e.g. last 50/100 events), log or A/B compare in-game, then decide whether to switch or offer both behind an option.
