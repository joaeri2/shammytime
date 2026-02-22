# Media Removal Plan

Date: 2026-02-22
Scope: `Media/`

## Findings

Audit method:
- Listed all files under `Media/`.
- Cross-checked texture usage in `ShammyTime_Media.lua`, `ShammyTime_SatelliteRings.lua`, `ShammyTime_CenterRing.lua`, `ShammyTime_Pressure.lua`, and `ShammyTime.toc`.
- Treated `SATELLITE_*` texture keys as used because they are resolved dynamically in `GetSatelliteTextureSet`.

Confirmed in use (keep):
- `Media/logo_64x64.tga` (`ShammyTime.toc` icon)
- `Media/wf_center_energy.tga` (`TEX.CENTER_ENERGY` in `ShammyTime_CenterRing.lua`)
- `Media/wf_center_shadow.tga` (`TEX.CENTER_SHADOW` in `ShammyTime_CenterRing.lua`)
- All top-level `Media/v2_*.tga` files
- All `Media/Pressure/v2_*.tga` files

Confirmed unused in current code path (remove candidates):
- `Media/wf_air_full_256.tga`
- `Media/wf_asset_test.tga`
- `Media/wf_center_bg.tga`
- `Media/wf_crit_bg_aligned.tga`
- `Media/wf_crit_border_aligned.tga`
- `Media/wf_crit_glow_aligned.tga`
- `Media/wf_crit_shadow_aligned.tga`
- `Media/wf_fire_bg.tga`
- `Media/wf_fire_border.tga`
- `Media/wf_fire_glow.tga`
- `Media/wf_fire_shadow.tga`
- `Media/wf_grass_upper_right.tga`
- `Media/wf_magic_gras_256.tga`
- `Media/wf_next_bg.tga`
- `Media/wf_next_border.tga`
- `Media/wf_next_glow.tga`
- `Media/wf_next_shadow.tga`
- `Media/wf_sat_bg.tga`
- `Media/wf_sat_border.tga`
- `Media/wf_sat_glow.tga`
- `Media/wf_sat_shadow.tga`
- `Media/wf_wind_bg.tga`
- `Media/wf_wind_border.tga`
- `Media/wf_wind_glow.tga`
- `Media/wf_wind_shadow.tga`

## Code Cleanup Plan

1. Remove dead texture keys from `ShammyTime_Media.lua` that map to the files above:
- `CRIT_*`, `PROCS_*`, `MIN_*`, `AVG_*`, `PROCPCT_*`
- `AIR_FULL`, `GRASS_FULL`, `GRASS_UPPER_RIGHT`, `ASSET_TEST`

2. Optional cleanup in `ShammyTime_Media.lua`:
- Remove placeholder keys that point to files not present in `Media/`: `MAX_*`, `ORB_BG`, `ORB_BORDER`, `GLOW`, `RING_RUNES`.

3. Optional comment cleanup:
- Update the comment in `ShammyTime_CenterRing.lua` that mentions `wf_center_bg.tga` to match the current v2 center texture.

## Execution Steps

1. Create a cleanup branch.
2. Delete the 25 candidate files listed above.
3. Apply key cleanup in `ShammyTime_Media.lua`.
4. Run an in-game smoke test:
- Addon loads with no missing texture errors.
- Center ring still renders and procs.
- Satellite bubbles and diffuse overlays still render.
- Totem bar, imbue bar, stagger bar, shamanistic focus, and Windfury ICD visuals still render.
- Pressure bar visuals still render.
5. Commit as one focused cleanup change.

## Deferred (if you want 100% v2-only naming)

- `wf_center_energy.tga` and `wf_center_shadow.tga` are still active.
- If you want fully v2-only assets, first replace those two with v2 equivalents, then remove the legacy files.
