# Stagger Guidance Python Test Report

Date: 2026-02-22  
Addon: `ShammyTime`  
Target file: `ShammyTime_StaggerBar.lua`

## What I ran

```bash
python3 Helpers/stagger_guidance_matrix.py
```

Test runner:
- canonical: `Helpers/stagger_guidance_matrix.py`
- wrapper: `tests/stagger_guidance_matrix_test.py`

## Purpose

Validate marker/risk rendering for all state combinations and catch both regressions:

1. Guide line disappeared after `/st resync` in some valid timing states.
2. Red risk bar did not appear in cue-active states.

## Matrix dimensions

The matrix now tests 64 combinations:
- `show_zones`
- `in_combat`
- `has_swing_timing`
- `has_dynamic_target`
- `needs_resync`
- `cue_resync_active`

## Findings

### Pre-fix (older gate)

- `showPredictiveGuide = showZones and inCombat and hasSwingTiming and hasDynamicTarget`
- `showRiskGuidance = showPredictiveGuide and needsResync`

Failures:
- `5 / 64` mismatches
- Included both “no guide line” and “no red risk” cases when `hasDynamicTarget` was false or cue was active without `delta`.

### After first fix (predictive marker decoupled from dynamic target)

- `showPredictiveGuide = showZones and inCombat and hasSwingTiming`
- `showRiskGuidance = showPredictiveGuide and needsResync`

Failures:
- `2 / 64` mismatches
- Remaining issue: cue-active-without-delta states still hid red risk overlays.

### Current fix (implemented)

- `showPredictiveGuide = showZones and inCombat and hasSwingTiming`
- `showRiskGuidance = showPredictiveGuide and (needsResync or cueResyncActive)`
- plus manual `/st resync` now clears cue state to avoid stale cue bleed:
  - `actionCue.state = "idle"`
  - `actionCue.cooldownEnd = 0`
  - `actionCue.cooldownSwings = 0`
  - `actionCue.stateEnteredAt = now`

Result:
- `0 / 64` mismatches

### Follow-up fix (red risk during repeated correction clicks)

User-reported follow-up:
- During white/desynced correction, repeated `/st resync` taps could make red risk guidance disappear.

Adjustment made:
- In `SimulateResyncMacro()`, preserve correction guidance intent:
  - If prior state indicated active correction (`priorNeedsResync` or cue active), set `actionCue.state = "resync_needed"` after macro application.
  - Otherwise keep `actionCue.state = "idle"`.
- In rendering gate, treat cooldown as resync-active for red-risk visibility:
  - `cueResyncActive = resync_needed | click_now | cooldown`

Verification:
- Re-ran `python3 tests/stagger_guidance_matrix_test.py`
- Current logic remains `0 / 64` mismatches.

## Key failing scenarios now covered

1. `primary_repro_post_resync_before_new_delta`
- Expected: green guide visible, red hidden
- Current: pass

2. `desync_without_dynamic_target`
- Expected: guide visible, red visible
- Current: pass

3. `cue_active_without_delta`
- Expected: guide visible, red visible
- Current: pass

## Files changed

- `ShammyTime_StaggerBar.lua`
- `Helpers/stagger_guidance_matrix.py`
- `Helpers/stagger_guidance_matrix.md`
- `tests/stagger_guidance_matrix_test.py` (wrapper)
- `docs/stagger-guidance-python-test-report.md`
