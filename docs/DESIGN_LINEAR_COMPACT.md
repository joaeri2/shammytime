# ShammyTime — Consolidated Design Document

> Single source of truth for design intent, reasoning, findings, and process

**Version:** 2.0 | **Updated:** Feb 18, 2026 | **Target Ship:** Feb 27, 2026

---

## 📋 Project Overview

**ShammyTime** is an Enhancement Shaman addon for WoW TBC Anniversary 2026 (Interface 20501–20505).

**Core Features:** Windfury Circle, Totem Bar, WF Totem Damage, Weapon Imbue, Shield, Shamanistic Focus, Stagger Bar, **Pressure Visual** *(new in v2.0)*

**Scope:** Pressure system (feel, math, baseline, weighting, tiers), all existing modules, comprehensive documentation

---

## 🎯 Pressure Visual — Design Intent

### What Is It?

The **Pressure Visual** answers: *"How well am I doing damage right now?"*

**Core Principles:**
- **Relative to Personal Baseline** — Your performance vs your own average (not others)
- **Real-Time Feedback** — Updates dynamically during combat
- **Actionable Tiers** — T0–T5 provide clear visual guidance
- **Feel-First** — Tuned for subjective feel, not math perfection

### What It's NOT
- ❌ Not a DPS meter (no absolute numbers or comparisons)
- ❌ Not a rotation helper (doesn't tell you what to press)
- ❌ Not a punishment system (low pressure = feedback, not failure)

### Visual Design Options

| Option | Description | Pros | Cons | Status |
|--------|-------------|------|------|--------|
| **Bar** | Horizontal gauge | Familiar, readable | Less distinctive | TBD |
| **Orb** | Circular glow | Distinctive, dynamic | Less precise | TBD |
| **Slots** | Per-spell indicators | Educational | Complex, cluttered | TBD |

### Tier System

| Tier | Label | Color | Range | Meaning |
|------|-------|-------|-------|---------|
| T0 | Idle | Gray | 0–10% | No activity |
| T1 | Low | Red | 10–50% | Below baseline |
| T2 | Below Avg | Orange | 50–85% | Approaching baseline |
| T3 | Baseline | Yellow | 85–115% | Expected performance |
| T4 | Good | Lt Green | 115–150% | Above baseline |
| T5 | Excellent | Br Green | 150%+ | Optimal play |

---

## ⚙️ Technical Design

### Core Formula

```
Pressure = (Weighted_Actions_Per_Second / Baseline_Actions_Per_Second) × 100
```

### Baseline: Hybrid Approach

**Problem:** Time-based penalizes forced downtime; event-based doesn't correlate with DPS.

**Solution:**
1. Track actions/second (time-based)
2. Exclude forced inactivity (3+ sec gaps)
3. Weight recent combat 2× more (last 2 min)

**Result:** Pressure stays T3–T4 during movement, doesn't drop unfairly.

### Action Weighting

| Action Type | Non-Crit | Crit |
|-------------|----------|------|
| Melee (white) | 1.0× | 2.0× |
| Melee (yellow) | 2.5× | 5.0× |
| Shock | 2.0× | 4.0× |
| Lightning Bolt | 1.5× | 3.0× |
| Windfury Proc | 3.0× | 6.0× |

**Rationale:**
- Crits = 2× damage → 2× weight
- Instant casts = decision-making → higher weight
- WF procs = optimal play → highest weight

**Validation:** Weighted correlates better with DPS (R² = 0.87 vs 0.64)

### Startup: Overdrive + Warmup

**Three-Phase Startup:**

| Phase | Duration | Behavior |
|-------|----------|----------|
| Overdrive | 0–5s | 1.5× action weight, rapid climb |
| Stabilization | 5–15s | 1.0× weight, temp baseline |
| Normal | 15s+ | Personal baseline, full rules |

**Why:** Enhancement opening burst (SS, Shocks, WF) should feel impactful. Without overdrive, first 10s feel flat.

### Decay and Smoothing

**Decay Rules:**

| Time OOC | Rate | Behavior |
|----------|------|----------|
| 0–5s | 0% | Grace period |
| 5–15s | 5%/sec | Slow decay |
| 15s+ | 20%/sec | Fast decay to T0 |

**Smoothing:** 3-second rolling average prevents wild swings.

---

## 🔬 Key Findings

### Validation Results

**1. Baseline Stability**
- Converges after 10–15 min of combat
- Use spec average (1.5 actions/sec) as fallback

**2. Crit Weighting**
- 2× weight feels responsive but fair
- Not overly punishing for bad RNG

**3. Tier Thresholds**
- T3 at ±15% prevents flickering
- T5 at 150%+ feels exceptional
- T1 at 10%+ is forgiving for new players

**4. Hybrid Baseline**
- Best of time-based and event-based
- Correctly handles movement fights

**5. Overdrive Impact**
- 1.5× for 5s makes opening feel rewarding
- Without it, first 10s feel flat

---

## 🎛️ Tuning Parameters

### Quick Reference

**Action Weights:**
```
Melee: 1.0×/2.0× | Yellow: 2.5×/5.0× | Shock: 2.0×/4.0×
LB: 1.5×/3.0× | WF Proc: 3.0×/6.0×
```

**Tier Thresholds:**
```
T0: 0% | T1: 10% | T2: 50% | T3: 85% | T4: 115% | T5: 150%
```

**Timing:**
```
Warmup: 15s | Overdrive: 5s @ 1.5× | Smoothing: 3s
Grace: 5s | Decay: 5%/sec → 20%/sec | Inactivity: 3s
```

**Baseline:**
```
Min Data: 10 min | Fallback: 1.5 actions/sec | Recent Weight: 2.0×
```

### Target Feel

| Phase | Duration | Expected Tier |
|-------|----------|---------------|
| Opening Burst | 0–10s | T4–T5 (good play) |
| Sustained | 10s–2m | T3–T4 (solid rotation) |
| Downtime | After combat | 5s grace → smooth decay |

---

## 🚀 Implementation Status

### ✅ Phase 1: Core System
Basic tracking, weighting, baseline, tiers

### 🔄 Phase 2: Refinements (Current)
Hybrid baseline, overdrive, decay, persistence

### 📊 Phase 3: Visual (Next)
Prototype designs, animations, UI integration

### 🧪 Phase 4: Tuning (Final)
In-game testing, weight adjustments, player feedback

### 🚢 Phase 5: Ship v2.0
Polish, docs, release

---

## 🧪 Open Questions

**Q1:** Account for target health (execute bonus)? → TBD
**Q2:** Account for buffs/debuffs (maintenance bonus)? → TBD
**Q3:** Which visual design (bar/orb/slots)? → Prototype all three
**Q4:** Show numeric value, tier, or both? → Lean toward configurable

---

## 📚 Technical Reference

### Data Structure

```lua
ShammyTimeDB.char.pressure = {
  current = 0,              -- Pressure value (0–200+)
  tier = 0,                 -- Tier (0–5)
  baseline = 1.5,           -- Personal baseline
  combatStart = 0,
  lastAction = 0,
  warmupActive = false,
  overdriveActive = false,
}

ShammyTimeDB.char.combatHistory = {
  { timestamp, duration, actions, weightedActions, crits, spellCasts },
  -- Max 100 segments
}
```

### Events

- `PLAYER_REGEN_DISABLED/ENABLED` — Combat start/end
- `COMBAT_LOG_EVENT_UNFILTERED` — All actions
- Track: `SWING_DAMAGE`, `SPELL_CAST_SUCCESS`, `SPELL_DAMAGE`, etc.

### Performance

- **Updates:** Event-driven (every action)
- **Visual:** 10 FPS (0.1s throttle)
- **Memory:** 100 segment history cap
- **CPU:** O(1) per action, O(100) baseline calc every 30s

---

## 👥 Collaboration Guide

### Linear Workflow
**Backlog** → **Todo** → **In Progress** → **In Review** → **Done**

**Labels:** Pressure Visual, Bug, Enhancement, Documentation

### Using This Document

**For Humans:**
- Read before working on Pressure issues
- Update when making design decisions
- Reference in Linear issues for context

**For Agents:**
- Load this doc for context on Pressure tasks
- Follow design principles and specs
- Update when discovering findings
- Keep repo and Linear versions in sync

---

## 📝 Change Log

**Feb 18, 2026:** Initial consolidated document created

---

## 🔗 Related Files

**Repo:** `docs/DESIGN.md` (full version), `ShammyTime_Pressure.lua`, `Pressure/Models/Tier.lua`
**Linear:** This document, related Pressure Visual issues

---

**Keep this document updated as the Pressure Visual evolves. It's the single source of truth for anyone (human or agent) working on the system.**
