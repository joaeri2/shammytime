# Scaling jump analysis – why elements move diagonally

## Reference: Shamanistic Focus (works correctly)

**File:** `ShammyTime_ShamanisticFocus.lua`  
**Function:** `ShammyTime.ApplyShamanisticFocusScale()` (lines 376–388)

**Pattern that keeps the frame in place:**
1. `f:SetScale(s)` – apply new scale
2. **Then** re-apply saved position: `f:ClearAllPoints()` and `f:SetPoint(db.point, relTo, db.relativePoint, db.x, db.y)`

So the frame always uses the **saved** anchor (point, relativeTo, relativePoint, x, y) from DB **after** changing scale. That keeps the anchor point fixed in parent space, so the element only gets bigger/smaller and does not drift.

---

## Elements that jump (and why)

In WoW, changing a frame’s scale can cause layout to recompute in a way that shifts the frame. If we only set scale and do not re-apply position afterward, the frame can move diagonally. The fix is the same for all: **after** `SetScale(...)`, re-apply the **saved** position (ClearAllPoints + SetPoint with stored values).

---

### 1. Center ring (Windfury radial)

**Frame:** `ShammyTimeWindfuryRadial` (wrapper; position is saved in `pos.center`).  
**Where scale is applied:**  
- `ShammyTime_Modules.lua` – `windfuryBubbles:ApplyConfig()`: `ApplyCenterRingPosition()` then `wrapper:SetScale(effScale)`  
- `ShammyTime_CenterRing.lua` – `CreateRadialWrapper()` and `PlayCenterRingProc()` set scale on wrapper/center

**Current behavior:** Position is applied **before** scale, but position is **not** re-applied **after** scale. So when scale changes, the engine can shift the wrapper.

**Fix:** After `wrapper:SetScale(effScale)` in `windfuryBubbles:ApplyConfig()`, call `ApplyCenterRingPosition()` again so the wrapper’s anchor is re-applied from saved `pos.center`.

---

### 2. Totem bar

**Frame:** `ShammyTimeWindfuryTotemBarFrame`.  
**Where scale is applied:**  
- `ShammyTime_Modules.lua` – `totemBar:ApplyConfig()`: `ApplyTotemBarPosition()` then `bar:SetScale(effScale)`  
- `ShammyTime_CenterRing.lua` – `CreateWindfuryTotemBarFrame()` sets scale at creation

**Current behavior:** Same as center ring: position before scale, no re-apply after scale.

**Fix:** After `bar:SetScale(effScale)` in `totemBar:ApplyConfig()`, call `ApplyTotemBarPosition()` again (re-apply saved `pos.totemBar`).

---

### 3. Imbue bar

**Frame:** `ShammyTimeImbueBarFrame`.  
**Where scale is applied:**  
- `ShammyTime_Modules.lua` – `weaponImbueBar:ApplyConfig()`: position → scale → position (already re-applies)  
- `ShammyTime_ImbueBar.lua` – `ApplyImbueBarScale()` (e.g. `/st imbue scale X`): only `SetScale(scale)`, **no** position re-apply

**Current behavior:** Options path re-applies position; **command path** (`ApplyImbueBarScale`) does not. So changing scale via `/st imbue scale` can make the bar jump.

**Fix:** In `ApplyImbueBarScale()`, after `SetScale(scale)` call `ApplyImbueBarPosition()` so the bar’s position is re-applied from saved (and normalized to CENTER as already done there).

---

### 4. Shield indicator

**Frame:** Shield frame in `ShammyTime_ImbueBar.lua`.  
**Where scale is applied:**  
- `ShammyTime_Modules.lua` – `shieldIndicator:ApplyConfig()`: position → scale → position (re-applies)  
- `ShammyTime_ImbueBar.lua` – `ApplyShieldScale()`: `SetScale(scale)` then re-anchor using **current** `GetCenter()` (normalize to CENTER)

**Current behavior:** After scale, the code re-anchors using the frame’s **current** center. If the frame has already shifted due to scale, we lock it at the **new** (wrong) position instead of the saved one.

**Fix:** In `ApplyShieldScale()`, after `SetScale(scale)` call `ApplyShieldPosition(shieldFrame)` so we re-apply the **saved** position from `pos.shieldFrame` (and keep the existing CENTER normalization inside `ApplyShieldPosition`).

---

### 5. Satellite bubbles

**Scale:** Applied in `ShammyTime_SatelliteRings.lua`; bubbles are children of the center ring. Their positions are offset in parent space. If the **center ring** no longer jumps (fix #1), satellite movement from scaling should be resolved by that. If they still move, we can add a dedicated “re-apply satellite layout after scale” step later.

---

## Summary (all fixes applied)

| Element           | Re-apply position after scale? | Fix applied |
|------------------|---------------------------------|-------------|
| Shamanistic Focus| Yes (reference)                 | —           |
| Center ring      | Yes                             | ApplyConfig + `/st scale` + `/st circle scale`: wrapper scale then `ApplyCenterRingPosition()`. |
| Totem bar        | Yes                             | ApplyConfig + `/st totem scale`: bar scale then `ApplyTotemBarPosition()`. |
| Imbue bar        | Yes                             | `ApplyImbueBarScale()` now calls `ApplyImbueBarPosition()` after `SetScale()`. |
| Shield           | Yes                             | `ApplyShieldScale()` now calls `ApplyShieldPosition()` after `SetScale()` (saved position). |
| Satellites       | N/A (children of center)        | Covered by center ring fix. |
