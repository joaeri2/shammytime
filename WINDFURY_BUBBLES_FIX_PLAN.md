# Plan: Windfury Bubbles – Move + Demo Scale

**Goals**
1. **Movable:** User can drag the Windfury radial (center + satellite bubbles) and the position persists.
2. **Demo scale:** Running demo does not leave bubble scale or position wrong; after proc/demo, bubbles return to normal.

---

## Root causes (from code comparison)

### 1. Why moving can feel broken
- **Wrapper vs center:** The draggable frame is the center ring; it moves the wrapper and saves the wrapper’s position. That’s correct.
- **ApplyConfig overwriting:** `windfuryBubbles:ApplyConfig()` runs on load and on option changes. It calls `ApplyCenterRingPosition()` which applies `pos.center` from DB. If `pos.center` is never set (e.g. first load or missing migration), `ApplyCenterPosition()` returns early and the wrapper keeps whatever it had (e.g. 0,0). So the radial can be stuck at default until first drag.
- **Locked:** If `db.locked` is true, drag is no-op. Options panel or profile might be setting locked.
- **Order of operations:** If `ApplyAllConfigs` (and thus `ApplyConfig`) runs *after* the user drags (e.g. after closing options), it should re-apply the same saved position. So moving should work as long as we save correctly and don’t clear `pos.center`. The main risk is `pos.center` being nil so position is never applied or is reset.

### 2. Why demo changes bubble scale
- **Center scale in proc:** In `PlayCenterRingProc` (CenterRing.lua ~726) the code does `f:SetScale(GetRadialScale())` on the **center frame**. Design is “scale only on wrapper, center at 1”. So:
  - Scale is applied twice: wrapper (in Modules) and center (in PlayCenterRingProc).
  - Satellite math uses `centerFrame:GetScale()` in `OnRingProcScaleUpdate` and `ResetSatellitePositions`. So when the center is forced to `GetRadialScale()` at proc start, satellite offsets and scale use that value. When proc ends, `ResetSatellitePositions` runs with that same (wrong) center scale, so layout is consistent during proc but wrong after, and the center frame keeps the radial scale instead of 1.
- **Fix:** Do **not** set the center frame’s scale in `PlayCenterRingProc`. Keep center at 1; only the wrapper should have the user’s radial scale. Then satellite math (which divides by `centerScale`) stays correct and proc animation only affects the ring subframe and satellites as intended.

---

## Implementation plan

### Phase 1: Demo / proc scale (single source of scale)

| Step | File | Action |
|------|------|--------|
| 1.1 | `ShammyTime_CenterRing.lua` | In `PlayCenterRingProc`, **remove** the line `f:SetScale(GetRadialScale())` (center frame `f`). Ensure the center frame is created with `f:SetScale(1)` only (already set in `CreateCenterRingFrame()`). |
| 1.2 | `ShammyTime_CenterRing.lua` | Confirm the **wrapper** is the only frame that gets the user radial scale: it’s set in `CreateRadialWrapper()` with `GetRadialScale()` and again in `windfuryBubbles:ApplyConfig()` with `effScale`. No other frame (center, ring subframe except during proc animation) should get the radial scale. |
| 1.3 | `ShammyTime_SatelliteRings.lua` | In `OnRingProcScaleUpdate` and `ResetSatellitePositions`, `GetCenterFrame()` is the center ring (scale 1). So `centerScale` will be 1. Offsets stay as `baseOffsetX / 1`, `baseOffsetY / 1`; no change needed if center is fixed to 1. |
| 1.4 | `ShammyTime_Modules.lua` | In `windfuryBubbles:DemoStart()`, after showing frames, do **not** call any layout/position/scale that would overwrite wrapper scale. Already only `ApplyCenterRingPosition()` is called (position only). No change needed if Phase 1.1 is done. |
| 1.5 | **Verify** | Run demo: start → procs → stop. After stop, bubbles and center should be same size and position as before demo. No permanent scale change. |

### Phase 2: Dragging and saved position

| Step | File | Action |
|------|------|--------|
| 2.1 | `ShammyTime_CenterRing.lua` | In `ApplyCenterPosition(f)`: when `pos.center` is nil (first load), apply a **default** position instead of returning: e.g. `CENTER`, UIParent, `CENTER`, 0, -180 (or match main frame default). So the radial always has a defined position and can be dragged from first load. |
| 2.2 | `ShammyTime_CenterRing.lua` | In `CreateRadialWrapper()`, after `ApplyCenterPosition(radialWrapper)`, if you added a default in 2.1, the first-time experience is correct. Optionally: after applying position, if `pos.center` was nil, call `SaveCenterPosition(radialWrapper)` so the default is persisted and future `ApplyConfig` re-applies the same place. |
| 2.3 | `ShammyTime_Core.lua` / options | Ensure “locked” is only used to block drag. When the user unlocks, they can drag; when they drag and release, `SaveCenterPosition` runs and we never clear `pos.center` in normal flow. No change needed unless you find a path that clears `wfRadialPos` or `pos.center`. |
| 2.4 | **Verify** | Unlock, drag radial, release. Reload UI or run `/reload`. Radial should be where you left it. Open/close options and run demo; position should not jump. |

### Phase 3: Stop demo and layout (sanity check)

| Step | File | Action |
|------|------|--------|
| 3.1 | `ShammyTime_Core.lua` | Confirm `StopDemo` only stops timers and updates fade state; it must **not** call `ApplyAllConfigs`, `ApplyCenterRingPosition`, or any SetPoint/SetScale. (Already correct per earlier spec.) |
| 3.2 | `ShammyTime_Modules.lua` | Confirm `windfuryBubbles:DemoStop()` only cancels the proc ticker and calls `UpdateAllElementsFadeState()`; no layout. (Already correct.) |

---

## Summary

- **Demo scale:** Remove center ring scale override in `PlayCenterRingProc` so only the wrapper has radial scale and satellite math stays correct; proc animation still scales only the ring subframe and satellite positions/scale temporarily, then `ResetSatellitePositions` restores them.
- **Move:** Ensure a default position when `pos.center` is nil and optionally persist it so the radial is always movable and position survives reload and options.

---

## Files to touch

1. **ShammyTime_CenterRing.lua** – Remove `f:SetScale(GetRadialScale())` in `PlayCenterRingProc`; add default position in `ApplyCenterPosition` when `pos.center` is nil; optionally save that default in `CreateRadialWrapper`.
2. **ShammyTime_SatelliteRings.lua** – No change if center scale is fixed to 1.
3. **ShammyTime_Modules.lua** – No change if Phase 1 and 3 checks pass.
4. **ShammyTime_Core.lua** – No change if StopDemo already does not touch layout.

After Phase 1 and 2, moving and demo should work: radial is draggable and persists; demo does not permanently change bubble scale.
