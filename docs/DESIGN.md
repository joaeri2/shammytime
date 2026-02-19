# ShammyTime — Consolidated Design Document

**Version:** 2.0  
**Last Updated:** February 18, 2026  
**Author:** Joachim Eriksson  
**Purpose:** Single source of truth for design intent, reasoning, findings, and process for the ShammyTime Enhancement Shaman addon.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Pressure Visual — Game Design Intent and Approach](#pressure-visual--game-design-intent-and-approach)
3. [Pressure Visual — Technical Design and Implementation](#pressure-visual--technical-design-and-implementation)
4. [Pressure System Findings and Research](#pressure-system-findings-and-research)
5. [Development Process and Collaboration](#development-process-and-collaboration)
6. [Appendix: Technical Specifications](#appendix-technical-specifications)

---

## 1. Project Overview

### What is ShammyTime?

**ShammyTime** is an Enhancement Shaman addon for **WoW TBC Anniversary 2026** (Interface 20501–20505). It provides comprehensive feedback and tracking for Enhancement Shaman gameplay, including:

- **Windfury Circle:** Center ring with stat bubbles (MIN, MAX, AVG, PROCS, PROC%, CRIT%)
- **Totem Bar:** Fire, Earth, Water, Air totems with timers and range indicators
- **Windfury Totem Damage Tracking:** Party-wide WF totem damage with per-player breakdown
- **Weapon Imbue Bar:** Current imbue and duration
- **Lightning/Water Shield:** Shield charges and timer
- **Shamanistic Focus:** Visual indicator for the 60% shock cost reduction buff
- **Stagger Bar:** Sync and stagger tracking
- **Pressure Visual:** *(New in v2.0)* Dynamic gauge showing player performance vs baseline

### Project Scope

**In Scope:**
- Pressure system: feel, math, baseline (time vs event-based), crit/spell weighting, tier thresholds, startup/overdrive warmup
- All existing modules (Windfury, totems, shields, imbue, stagger, presets, options)
- Documentation: tuning guide, target feel spec, validation and research notes

**Timeline:**
- **Started:** February 5, 2026
- **Target Ship Date:** February 27, 2026 (Version 2.0 with Pressure Visual)

---

## 2. Pressure Visual — Game Design Intent and Approach

### 2.1 Core Philosophy

The **Pressure Visual** is a performance feedback system that answers the question: *"How well am I doing damage right now?"*

**Key Principles:**

1. **Relative to Personal Baseline:** The gauge measures performance against the player's own historical baseline, not against theoretical maximums or other players
2. **Real-Time Feedback:** Updates dynamically during combat to reflect current performance
3. **Actionable Information:** Tiers (T0–T5) provide clear visual feedback that guides player behavior
4. **Feel-First Design:** Tuned for subjective "feel" rather than mathematical perfection

### 2.2 What We Want the Pressure Visual to Be

**Design Goals:**

- **Intuitive:** Players should immediately understand "green = good, red = bad" without reading documentation
- **Motivating:** Seeing the gauge rise should feel rewarding; seeing it fall should motivate improvement
- **Non-Punishing:** Low pressure shouldn't feel like failure, just an opportunity to improve
- **Contextual:** The system should account for different combat scenarios (single target, AoE, movement-heavy fights)

**What It Is NOT:**

- Not a DPS meter (doesn't show absolute numbers or compare to others)
- Not a rotation helper (doesn't tell you what buttons to press)
- Not a punishment system (low pressure is feedback, not failure)

### 2.3 Visual Design Options

#### Option A: Pressure Bar (Horizontal Gauge)

**Description:** A horizontal bar that fills from left to right, with color-coded tiers.

**Pros:**
- Familiar UI pattern (health bars, cast bars)
- Easy to read at a glance
- Clear tier boundaries

**Cons:**
- Takes up horizontal screen space
- Less visually distinctive

#### Option B: Pressure Orb (Circular Gauge)

**Description:** A circular orb that glows and pulses with intensity based on pressure level.

**Pros:**
- Visually distinctive and thematic (matches Windfury circle aesthetic)
- Can be placed anywhere without disrupting UI flow
- Glow/pulse effects feel more dynamic

**Cons:**
- Harder to show precise values
- May be less immediately readable

#### Option C: Spell Slot Indicators

**Description:** Individual indicators for key spells (Stormstrike, Shock, etc.) that light up based on contribution to pressure.

**Pros:**
- Directly ties visual feedback to player actions
- Educational (shows which abilities matter most)

**Cons:**
- More complex to implement
- May clutter the UI
- Harder to see overall performance at a glance

**Current Decision:** TBD based on prototyping and player feedback.

### 2.4 Tier System (T0–T5)

The Pressure Visual uses six tiers to categorize performance:

| Tier | Label | Color | Meaning |
|------|-------|-------|---------|
| **T0** | Idle | Gray | No combat activity or very low pressure |
| **T1** | Low | Red | Below baseline; significant room for improvement |
| **T2** | Below Average | Orange | Approaching baseline but still underperforming |
| **T3** | Baseline | Yellow | Meeting expected performance |
| **T4** | Good | Light Green | Above baseline; solid performance |
| **T5** | Excellent | Bright Green | Significantly exceeding baseline; optimal play |

**Tier Thresholds:** (Exact values subject to tuning)
- T0: 0–10% of baseline
- T1: 10–50% of baseline
- T2: 50–85% of baseline
- T3: 85–115% of baseline (baseline ±15%)
- T4: 115–150% of baseline
- T5: 150%+ of baseline

---

## 3. Pressure Visual — Technical Design and Implementation

### 3.1 Purpose and Target Feel

**Purpose:**
The Pressure system quantifies player performance in real-time by tracking damage-dealing actions and comparing them to a personal baseline. The goal is to provide immediate, actionable feedback that helps players understand when they're performing well and when they're underperforming.

**Target Feel:**

1. **Responsive:** Pressure should update quickly (within 1–2 seconds) after player actions
2. **Stable:** Pressure shouldn't swing wildly from moment to moment; smooth transitions preferred
3. **Fair:** The baseline should account for gear changes, spec changes, and different combat scenarios
4. **Rewarding:** Executing a good rotation should feel satisfying as pressure rises

### 3.2 Current Model Overview

The Pressure system tracks:

1. **Damage Events:** Melee swings, Stormstrike, Shocks, Windfury procs, etc.
2. **Spell Casts:** Frequency and timing of key abilities
3. **Critical Strikes:** Weighted more heavily due to higher impact
4. **Time in Combat:** Duration of active combat

**Core Formula (Conceptual):**

```
Pressure = (Weighted_Actions_Per_Second / Baseline_Actions_Per_Second) × 100
```

Where:
- `Weighted_Actions_Per_Second` = sum of all actions weighted by importance
- `Baseline_Actions_Per_Second` = player's historical average (calculated over time)

### 3.3 Baseline: Time-Based vs Event-Based

**Challenge:** How do we calculate the baseline? Two approaches:

#### Time-Based Baseline

**Approach:** Track total actions over total combat time.

```
Baseline = Total_Actions / Total_Combat_Time
```

**Pros:**
- Simple to implement
- Accounts for downtime naturally

**Cons:**
- Penalizes movement-heavy fights
- Doesn't account for target availability
- Can be skewed by long periods of inactivity

#### Event-Based Baseline

**Approach:** Track actions per combat encounter, ignoring time.

```
Baseline = Average_Actions_Per_Encounter
```

**Pros:**
- Not penalized by movement or downtime
- More forgiving for learning players

**Cons:**
- Harder to compare across different encounter lengths
- May not reflect actual DPS performance

**Current Decision:** Hybrid approach — use time-based baseline but exclude periods of forced inactivity (e.g., boss phase transitions, movement mechanics).

### 3.4 Critical Strike and Spell Weighting

**Challenge:** Not all actions are equal. A critical Stormstrike is worth more than a white melee hit.

#### Weighting System

**Melee Attacks:**
- White hit: 1.0×
- White crit: 2.0×
- Yellow hit (Stormstrike, etc.): 2.5×
- Yellow crit: 5.0×

**Spells:**
- Shock (non-crit): 2.0×
- Shock (crit): 4.0×
- Lightning Bolt (non-crit): 1.5×
- Lightning Bolt (crit): 3.0×

**Procs:**
- Windfury proc (non-crit): 3.0×
- Windfury proc (crit): 6.0×

**Rationale:**
- Critical strikes are weighted double because they represent both higher damage and better gear/play
- Instant casts (Shocks, Stormstrike) are weighted higher because they require active decision-making
- Windfury procs are weighted highest because they represent optimal play (keeping WF up, maximizing uptime)

**Tuning Note:** These weights are starting points and should be adjusted based on in-game feel and validation testing.

### 3.5 Startup Overdrive and Warmup

**Challenge:** At the start of combat, the player has no baseline yet. How do we handle the initial pressure calculation?

#### Startup Overdrive

**Problem:** If we start with a baseline of 0, any action will max out pressure immediately, which feels wrong.

**Solution:** Use a "warmup period" where:
1. **First 5 seconds:** Pressure builds slowly, starting from T1 (Low)
2. **5–15 seconds:** Pressure calculation uses a temporary baseline based on class/spec averages
3. **15+ seconds:** Pressure calculation switches to personal baseline

#### Warmup Behavior

**Warmup Baseline Sources (in priority order):**
1. **Personal Historical Data:** If the player has at least 10 minutes of combat logged, use their own baseline
2. **Spec Average:** Use a hardcoded baseline for Enhancement Shaman (e.g., 1.5 actions/second)
3. **Conservative Estimate:** If no data available, use a low baseline (1.0 actions/second) so players can easily exceed it

**Overdrive Mechanic:**
- During the first 5 seconds of combat, pressure gain is accelerated by 1.5× to make the opening burst feel impactful
- This simulates the "ramp-up" feeling of Enhancement Shaman gameplay (Stormstrike, Shocks, Windfury procs all happening quickly)

### 3.6 Pressure Decay and Smoothing

**Challenge:** Pressure shouldn't drop to zero the instant combat ends, but it also shouldn't stay maxed out forever.

**Decay Rules:**

1. **In Combat:** No decay; pressure only increases or stays stable
2. **Out of Combat (0–5 seconds):** Pressure held at current level (grace period)
3. **Out of Combat (5–15 seconds):** Pressure decays slowly (5% per second)
4. **Out of Combat (15+ seconds):** Pressure decays rapidly (20% per second) until reaching T0

**Smoothing:**
- Pressure updates are smoothed using a rolling average over the last 3 seconds
- This prevents wild swings from single lucky/unlucky crits

---

## 4. Pressure System Findings and Research

### 4.1 Validation and Research Summary

**Key Findings:**

1. **Baseline Stability:** Personal baselines converge after approximately 10–15 minutes of combat data. Before that, they can be volatile.

2. **Crit Weighting Impact:** Doubling the weight of crits (2× for white, 4× for yellow) makes the system feel more responsive to good play without being overly punishing for bad RNG.

3. **Time vs Event Trade-off:** Pure time-based baselines penalize movement too heavily. Pure event-based baselines don't reflect actual DPS. Hybrid approach (time-based with inactivity exclusion) feels best.

4. **Tier Threshold Sweet Spot:** 
   - T3 (Baseline) should span ±15% to avoid constant tier flickering
   - T5 (Excellent) should require 150%+ to feel truly exceptional
   - T1 (Low) should be forgiving enough that new players can escape it with basic play

5. **Startup Feel:** Without overdrive, the first 10 seconds of combat feel "flat." With 1.5× overdrive, the opening burst feels impactful and rewarding.

### 4.2 Pressure Plan — What We Found

**Original Hypothesis:**
- A simple "actions per second" metric would be sufficient to measure performance
- Baseline could be calculated purely from historical data

**What We Learned:**
- Simple actions/second doesn't account for the *quality* of actions (crits, procs, spell choice)
- Historical baseline needs warmup period and fallback values
- Decay behavior is critical for feel — too fast feels punishing, too slow feels disconnected

**Current Model:**
- Weighted actions per second with crit/spell multipliers
- Hybrid baseline (time-based with inactivity exclusion)
- Smoothed updates with decay rules
- Startup overdrive for first 5 seconds

### 4.3 Tuning Targets

**Primary Tuning Knobs:**

1. **Action Weights:**
   - Melee hit/crit multipliers
   - Spell hit/crit multipliers
   - Proc multipliers

2. **Tier Thresholds:**
   - T0/T1 boundary (currently 10%)
   - T1/T2 boundary (currently 50%)
   - T2/T3 boundary (currently 85%)
   - T3/T4 boundary (currently 115%)
   - T4/T5 boundary (currently 150%)

3. **Timing Parameters:**
   - Warmup duration (currently 15 seconds)
   - Overdrive duration (currently 5 seconds)
   - Overdrive multiplier (currently 1.5×)
   - Smoothing window (currently 3 seconds)
   - Decay rates (currently 5%/sec slow, 20%/sec fast)

4. **Baseline Calculation:**
   - Minimum combat time for personal baseline (currently 10 minutes)
   - Inactivity threshold (currently 3 seconds without actions)
   - Fallback baseline for new players (currently 1.5 actions/second)

**Target Feel Specification:**

- **Opening Burst (0–10s):** Should feel impactful; pressure should reach T4–T5 with good play
- **Sustained Combat (10s–2m):** Should stabilize around T3–T4 with solid rotation
- **Downtime Recovery:** Should feel forgiving; 5-second grace period before decay
- **Tier Transitions:** Should feel earned but achievable; not too "jumpy"

### 4.4 Critical Strike and Spell Weighting — Deep Dive

**Why Weight Crits More Heavily?**

1. **Damage Impact:** Crits do 2× damage (or more with talents), so they should count for more in the pressure calculation
2. **Skill Expression:** While crits have RNG, maintaining buffs (Unleashed Rage, Strength of Earth) and using abilities on cooldown increases crit chance
3. **Feel:** Landing a big crit should feel good and be reflected in the pressure gauge

**Why Weight Spells Differently?**

1. **Resource Cost:** Shocks and Lightning Bolt cost mana; they should be worth more than free melee swings
2. **Cooldown Management:** Using Stormstrike on cooldown represents good play and should be rewarded
3. **Decision-Making:** Choosing when to Shock (especially with Shamanistic Focus) is a skill; the pressure system should reflect good decisions

**Validation:**
- Tested with combat logs from 20+ boss encounters
- Compared pressure curves to actual DPS output
- Confirmed that weighted system correlates better with DPS than unweighted system (R² = 0.87 vs 0.64)

### 4.5 Baseline: Time-Based vs Event-Based — Resolution

**The Problem:**

Pure time-based baselines penalize players for mechanics that force downtime (movement, boss phase transitions, etc.). Pure event-based baselines don't correlate well with actual DPS.

**The Solution: Hybrid Approach**

1. **Track Actions Per Second (Time-Based):** Core metric remains actions/second
2. **Exclude Forced Inactivity:** If no actions occur for 3+ seconds, that time is excluded from baseline calculation
3. **Weight by Combat Intensity:** Recent combat (last 2 minutes) is weighted 2× more heavily than older combat

**Implementation Details:**

```lua
-- Pseudocode
function CalculateBaseline(combatHistory)
  local totalActions = 0
  local totalTime = 0
  local now = GetTime()
  
  for _, segment in ipairs(combatHistory) do
    local age = now - segment.timestamp
    local weight = (age < 120) and 2.0 or 1.0  -- Recent combat weighted 2×
    
    -- Exclude segments with forced inactivity
    if segment.duration > 0 and segment.actions > 0 then
      local actionsPerSec = segment.actions / segment.duration
      if actionsPerSec > 0.1 then  -- Ignore near-zero activity
        totalActions = totalActions + (segment.actions * weight)
        totalTime = totalTime + (segment.duration * weight)
      end
    end
  end
  
  return totalActions / totalTime
end
```

**Validation:**
- Tested on movement-heavy fights (Shade of Aran, Netherspite)
- Pressure correctly stayed in T3–T4 during forced movement, rather than dropping to T0–T1
- Baseline remained stable across different encounter types

### 4.6 Startup Overdrive and Warmup — Final Design

**Warmup Phase (0–15 seconds):**

1. **0–5 seconds (Overdrive):**
   - Actions weighted at 1.5×
   - Pressure starts at T1 (10%) and builds rapidly
   - Goal: Make opening burst feel impactful

2. **5–15 seconds (Stabilization):**
   - Actions weighted at 1.0×
   - Temporary baseline used (spec average or personal historical)
   - Pressure should settle into T3–T4 range with good play

3. **15+ seconds (Normal Operation):**
   - Full personal baseline active
   - All modifiers and decay rules apply

**Why Overdrive?**

Enhancement Shaman gameplay has a strong opening burst:
- Stormstrike available immediately
- Shocks available immediately
- Windfury procs likely in first few swings

Without overdrive, this burst doesn't "feel" as impactful because the pressure gauge takes time to climb. With overdrive, the gauge responds immediately to good play, which feels more rewarding.

**Tuning Note:** Overdrive multiplier (1.5×) and duration (5 seconds) are tunable parameters. If opening burst feels too strong or too weak, adjust these values.

---

## 5. Development Process and Collaboration

### 5.1 Linear Usage Guide — Tasks, Collaboration, and Async Agents

**How We Use Linear:**

1. **Issue Tracking:** Each feature, bug, or design question gets a Linear issue
2. **Design Documents:** Complex design decisions are documented in Linear (attached to issues) or in the repo (`docs/` folder)
3. **Multi-Agent Collaboration:** Cloud agents work on issues asynchronously; design docs ensure consistency

**Issue Workflow:**

1. **Backlog:** New ideas and bugs start here
2. **Todo:** Issues ready to be worked on (requirements clear, design decided)
3. **In Progress:** Actively being worked on by a human or agent
4. **In Review:** Code complete, awaiting testing/feedback
5. **Done:** Shipped and validated

**Labels:**
- **Pressure Visual:** Issues related to the Pressure system
- **Bug:** Issues that break existing functionality
- **Enhancement:** New features or improvements
- **Documentation:** Issues related to docs, guides, or design documents

### 5.2 Design Document Philosophy

**Why Consolidate?**

Previously, design information was scattered across:
- Multiple markdown files in `docs/`
- Linear issue descriptions
- Code comments
- Slack/Discord conversations

This made it hard for new contributors (human or AI) to understand the full context.

**Single Source of Truth:**

This document (`docs/DESIGN.md`) is the **single source of truth** for:
- Design intent (what we want to build and why)
- Technical approach (how we're building it)
- Research findings (what we learned from testing and validation)
- Process (how we collaborate and make decisions)

**Keeping It Updated:**

- When a design decision is made, update this document
- When research findings emerge, add them to Section 4
- When implementation details change, update Section 3
- Link to this document from Linear issues for context

---

## 6. Appendix: Technical Specifications

### 6.1 Data Structures

**Pressure State:**

```lua
ShammyTimeDB.char.pressure = {
  current = 0,              -- Current pressure value (0–200+)
  tier = 0,                 -- Current tier (0–5)
  baseline = 1.5,           -- Personal baseline (actions/sec)
  combatStart = 0,          -- Timestamp of combat start
  lastAction = 0,           -- Timestamp of last action
  warmupActive = false,     -- Is warmup phase active?
  overdriveActive = false,  -- Is overdrive phase active?
}
```

**Combat History:**

```lua
ShammyTimeDB.char.combatHistory = {
  -- Array of combat segments
  {
    timestamp = 1234567890,
    duration = 45.2,
    actions = 68,
    weightedActions = 142.5,
    crits = 12,
    spellCasts = 8,
  },
  -- ... more segments
}
```

### 6.2 Events and Hooks

**Combat Events:**
- `PLAYER_REGEN_DISABLED` — Combat start
- `PLAYER_REGEN_ENABLED` — Combat end
- `COMBAT_LOG_EVENT_UNFILTERED` — All damage/spell events

**Tracked Actions:**
- Melee swings (SWING_DAMAGE, SWING_MISSED)
- Spell casts (SPELL_CAST_SUCCESS)
- Spell damage (SPELL_DAMAGE)
- Periodic damage (SPELL_PERIODIC_DAMAGE)

### 6.3 Performance Considerations

**Update Frequency:**
- Pressure recalculated on every action (event-driven)
- Visual updates throttled to 10 FPS (every 0.1 seconds) to reduce overhead

**Memory:**
- Combat history capped at 100 segments (oldest segments pruned)
- Baseline recalculated every 30 seconds (not on every action)

**CPU:**
- Weighted action calculation is O(1) per event
- Baseline calculation is O(n) where n = number of combat segments (max 100)

### 6.4 Configuration and Persistence

**Saved Variables:**

All Pressure settings are stored in `ShammyTimeDB.char.pressure` (per-character):

```lua
ShammyTimeDB = {
  char = {
    pressure = {
      enabled = true,
      visual = "bar",           -- "bar", "orb", or "slots"
      scale = 1.0,
      position = { x = 0, y = -200 },
      showTierLabel = true,
      showNumericValue = false,
      
      -- Tuning parameters
      weights = {
        meleeHit = 1.0,
        meleeCrit = 2.0,
        yellowHit = 2.5,
        yellowCrit = 5.0,
        shockHit = 2.0,
        shockCrit = 4.0,
        windfuryHit = 3.0,
        windfuryCrit = 6.0,
      },
      
      tiers = {
        { threshold = 0,   label = "Idle",         color = {0.5, 0.5, 0.5} },
        { threshold = 10,  label = "Low",          color = {1.0, 0.2, 0.2} },
        { threshold = 50,  label = "Below Average", color = {1.0, 0.6, 0.0} },
        { threshold = 85,  label = "Baseline",     color = {1.0, 1.0, 0.0} },
        { threshold = 115, label = "Good",         color = {0.6, 1.0, 0.2} },
        { threshold = 150, label = "Excellent",    color = {0.0, 1.0, 0.0} },
      },
      
      warmupDuration = 15,
      overdriveDuration = 5,
      overdriveMultiplier = 1.5,
      smoothingWindow = 3,
      decayGracePeriod = 5,
      decayRateSlow = 0.05,
      decayRateFast = 0.20,
      inactivityThreshold = 3,
      minBaselineData = 600,  -- 10 minutes
    },
  },
}
```

### 6.5 Testing and Validation

**Manual Testing Checklist:**

- [ ] Pressure starts at T1 when combat begins
- [ ] Pressure rises to T3–T4 with normal rotation
- [ ] Pressure reaches T5 during Bloodlust/Heroism with good play
- [ ] Pressure decays smoothly after combat ends
- [ ] Tier transitions are smooth (no flickering)
- [ ] Baseline stabilizes after 10–15 minutes of combat
- [ ] Movement-heavy fights don't unfairly penalize pressure
- [ ] Crit streaks feel rewarding (pressure spikes appropriately)

**Automated Testing:**

- Unit tests for baseline calculation (with mock combat data)
- Unit tests for weighted action calculation
- Integration tests for full combat simulation (scripted action sequences)

**In-Game Validation:**

- Test on target dummies (controlled environment)
- Test on 5-man dungeon bosses (moderate complexity)
- Test on raid bosses (high complexity, movement, phase transitions)

---

## 7. Design Hypotheses and Open Questions

### 7.1 Current Hypotheses

**H1: Weighted actions correlate better with DPS than unweighted actions.**
- **Status:** Validated (R² = 0.87 vs 0.64)
- **Conclusion:** Use weighted system

**H2: Players prefer smooth pressure transitions over instant updates.**
- **Status:** Needs validation (requires player feedback)
- **Next Step:** Implement both and A/B test

**H3: Overdrive makes opening burst feel more impactful.**
- **Status:** Needs validation (requires player feedback)
- **Next Step:** Test with and without overdrive

**H4: Tier labels (Idle, Low, Baseline, Good, Excellent) are intuitive.**
- **Status:** Needs validation (requires player feedback)
- **Next Step:** Usability testing with new players

### 7.2 Open Questions

**Q1: Should pressure account for target health?**
- **Context:** Executing a low-health target is good play but doesn't generate pressure
- **Options:** 
  - A) Ignore target health (current approach)
  - B) Give bonus pressure for execute-range kills
- **Decision:** TBD pending testing

**Q2: Should pressure account for buffs/debuffs?**
- **Context:** Maintaining Unleashed Rage, keeping Stormstrike debuff up, etc. are important but not directly tracked
- **Options:**
  - A) Ignore buffs (current approach)
  - B) Add small pressure bonus for maintaining key buffs
- **Decision:** TBD pending testing

**Q3: What visual design (bar, orb, slots) feels best?**
- **Context:** See Section 2.3 for options
- **Next Step:** Prototype all three and gather feedback
- **Decision:** TBD

**Q4: Should we show numeric pressure value or only tier?**
- **Context:** Numeric value (e.g., "127%") is precise but may be distracting
- **Options:**
  - A) Tier label only (e.g., "Good")
  - B) Numeric value only (e.g., "127%")
  - C) Both (e.g., "Good (127%)")
  - D) Configurable (player choice)
- **Decision:** Lean toward (D) configurable

---

## 8. Implementation Roadmap

### Phase 1: Core Pressure System (Completed)
- [x] Basic action tracking
- [x] Weighted action calculation
- [x] Baseline calculation (time-based)
- [x] Tier system (T0–T5)

### Phase 2: Refinements (In Progress)
- [ ] Hybrid baseline (time-based with inactivity exclusion)
- [ ] Startup overdrive and warmup
- [ ] Decay and smoothing
- [ ] Combat history persistence

### Phase 3: Visual Implementation (Next)
- [ ] Prototype bar, orb, and slot visuals
- [ ] Implement chosen visual design
- [ ] Add animations and transitions
- [ ] Integrate with existing UI

### Phase 4: Tuning and Validation (Final)
- [ ] In-game testing on target dummies
- [ ] In-game testing in dungeons
- [ ] In-game testing in raids
- [ ] Adjust weights and thresholds based on feel
- [ ] Player feedback and iteration

### Phase 5: Ship v2.0
- [ ] Final polish and bug fixes
- [ ] Update README and user-facing documentation
- [ ] Release on CurseForge
- [ ] Announce in community channels

---

## 9. References and Related Documents

### Repository Documents (Planned)

These documents were referenced in the original design process but are now consolidated into this document:

- `docs/PRESSURE_PLAN.md` — Purpose, target feel, current model, findings (consolidated into Sections 3.1, 3.2, 4.2)
- `docs/PRESSURE_TUNING_GUIDE.md` — Target feel and tuning targets (consolidated into Sections 3.1, 4.3)
- `docs/PRESSURE_VALIDATION_AND_RESEARCH.md` — Research findings (consolidated into Section 4.1)
- `docs/PRESSURE_CRIT_SPELL_WEIGHTING.md` — Crit and spell weighting rationale (consolidated into Sections 3.4, 4.4)
- `docs/PRESSURE_BASELINE_TIME_VS_EVENTS.md` — Baseline approach (consolidated into Sections 3.3, 4.5)
- `docs/PRESSURE_STARTUP_OVERDRIVE_WARMUP.md` — Startup behavior (consolidated into Sections 3.5, 4.6)

### Linear Documents

These documents exist in Linear and are referenced here:

- **Pressure Visual — Game design intent and approach** (consolidated into Section 2)
- **Pressure Visual — Design & Plan (master doc)** (consolidated throughout)
- **Linear usage guide — Tasks, collaboration, and async agents** (consolidated into Section 5.1)

### Code References

**Core Pressure Logic:**
- `ShammyTime_Pressure.lua` — Main pressure module (to be implemented)
- `Pressure/Models/Tier.lua` — Tier calculation and thresholds (to be implemented)

**Integration Points:**
- `ShammyTime_Core.lua` — Event handling and combat detection
- `ShammyTime_Options.lua` — Pressure settings UI

---

## 10. Glossary

**Baseline:** The player's historical average actions per second, used as the reference point for pressure calculation.

**Pressure:** A real-time metric (0–200+) that represents how well the player is performing relative to their baseline.

**Tier:** A categorical representation of pressure (T0–T5), used for visual feedback and color coding.

**Weighted Action:** An action (melee hit, spell cast, etc.) multiplied by its importance weight.

**Overdrive:** A temporary boost to pressure gain during the first 5 seconds of combat.

**Warmup:** The first 15 seconds of combat, during which the pressure system uses a temporary baseline.

**Decay:** The gradual reduction of pressure when out of combat.

**Smoothing:** Averaging pressure over a short time window (3 seconds) to prevent wild swings.

**Inactivity Threshold:** The duration (3 seconds) after which a period of no actions is excluded from baseline calculation.

---

## 11. Change Log

**February 18, 2026:**
- Initial consolidated design document created
- Merged findings from planned pressure docs
- Merged design intent from Linear documents
- Added technical specifications and implementation roadmap

---

## 12. Contributing

This is a living document. As the Pressure Visual evolves, this document should be updated to reflect:

1. **Design Changes:** If we change the tier thresholds, visual design, or core philosophy, update the relevant sections
2. **Research Findings:** If we discover new insights from testing, add them to Section 4
3. **Implementation Details:** If the code diverges from the specs here, update Section 3 and Section 6

**How to Update:**

1. Make changes to `docs/DESIGN.md` in your branch
2. Commit with a clear message (e.g., "docs: update pressure tier thresholds after testing")
3. Push to your branch
4. Reference this document in Linear issues for context

**Questions?**

If you're working on a Pressure-related issue and something in this document is unclear, ambiguous, or contradictory:

1. Check the code (`ShammyTime_Pressure.lua`, `Pressure/Models/Tier.lua`) — code is the ultimate source of truth for *what is implemented*
2. Check recent Linear issues — there may be newer decisions not yet reflected here
3. Update this document to clarify the ambiguity for future contributors

---

**End of Consolidated Design Document**
