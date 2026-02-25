# Stagger Guidance Matrix Script

Script:
- `Helpers/stagger_guidance_matrix.py`

Wrapper:
- `tests/stagger_guidance_matrix_test.py`

## What this script validates

It validates render gating logic for stagger guidance by exhaustively testing all combinations of these flags:

- `show_zones`
- `in_combat`
- `has_swing_timing`
- `has_dynamic_target`
- `needs_resync`
- `cue_resync_active`

That is `2^6 = 64` combinations.

It compares:
- older pre-fix logic
- intermediate logic
- current logic
- expected UX logic

## What this script does not validate

- Real WoW combat log timing/event ordering at runtime
- Ping jitter side effects over time
- Pixel-perfect rendering/anchoring artifacts
- Game-client-only behavior that cannot be reproduced with boolean-state modeling

## How to run

```bash
python3 Helpers/stagger_guidance_matrix.py
```

or

```bash
python3 tests/stagger_guidance_matrix_test.py
```

Both run the same canonical logic (the `tests/` file is only a wrapper).

## Pass/fail rule

- Exit code `0`: current logic matches expected behavior for all 64 combinations.
- Exit code non-zero: at least one mismatch exists, and the script prints failing input combinations.
