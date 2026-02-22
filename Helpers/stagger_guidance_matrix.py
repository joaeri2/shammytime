#!/usr/bin/env python3
"""Stagger guidance behavior matrix checker.

Why this exists:
- We changed stagger guidance rendering a few times and regressions happened.
- This script lets us verify render gating logic via a complete boolean matrix.

What it checks:
- Marker visibility gate (predictive guide).
- Red risk overlay gate.
- Legacy (before fix) behavior vs intermediate behavior vs current behavior.

What it does NOT check:
- Live WoW event ordering, latency spikes, or timing drift over real combat time.
- Visual placement math details (pixel coordinates, sizing, anchors).
- Any rendering issues caused by Blizzard client quirks.

Usage:
- python3 Helpers/stagger_guidance_matrix.py
- python3 tests/stagger_guidance_matrix_test.py  (wrapper to same logic)
"""

from dataclasses import dataclass
from itertools import product
from typing import Dict, List


@dataclass(frozen=True)
class Inputs:
    show_zones: bool
    in_combat: bool
    has_swing_timing: bool
    has_dynamic_target: bool
    needs_resync: bool
    cue_resync_active: bool


def pre_fix_logic(i: Inputs) -> Dict[str, bool]:
    """Older behavior before decoupling predictive guide from dynamic target."""
    show_predictive_guide = (
        i.show_zones and i.in_combat and i.has_swing_timing and i.has_dynamic_target
    )
    show_risk_guidance = show_predictive_guide and i.needs_resync
    return {
        "show_dynamic_marker": show_predictive_guide,
        "show_risk_overlays": show_risk_guidance,
    }


def post_fix_logic(i: Inputs) -> Dict[str, bool]:
    """Intermediate behavior (still missing cue-active red risk overlays)."""
    show_predictive_guide = i.show_zones and i.in_combat and i.has_swing_timing
    show_risk_guidance = show_predictive_guide and i.needs_resync
    return {
        "show_dynamic_marker": show_predictive_guide,
        "show_risk_overlays": show_risk_guidance,
    }


def current_logic(i: Inputs) -> Dict[str, bool]:
    """Current Lua behavior in ShammyTime_StaggerBar.lua."""
    show_predictive_guide = i.show_zones and i.in_combat and i.has_swing_timing
    show_risk_guidance = show_predictive_guide and (i.needs_resync or i.cue_resync_active)
    return {
        "show_dynamic_marker": show_predictive_guide,
        "show_risk_overlays": show_risk_guidance,
    }


def expected_logic(i: Inputs) -> Dict[str, bool]:
    """UX expectation we validate against.

    - If swing timing is computable in combat and zones are enabled, show a guide marker.
    - Show red risk overlays whenever correction is active (needs_resync or cue active).
    """
    show_predictive_guide = i.show_zones and i.in_combat and i.has_swing_timing
    show_risk_guidance = show_predictive_guide and (i.needs_resync or i.cue_resync_active)
    return {
        "show_dynamic_marker": show_predictive_guide,
        "show_risk_overlays": show_risk_guidance,
    }


def scenario_checks() -> List[Dict[str, object]]:
    scenarios = [
        (
            "primary_repro_post_resync_before_new_delta",
            Inputs(
                show_zones=True,
                in_combat=True,
                has_swing_timing=True,
                has_dynamic_target=False,
                needs_resync=False,
                cue_resync_active=False,
            ),
        ),
        (
            "perfect_stagger_with_dynamic_target",
            Inputs(
                show_zones=True,
                in_combat=True,
                has_swing_timing=True,
                has_dynamic_target=True,
                needs_resync=False,
                cue_resync_active=False,
            ),
        ),
        (
            "oh_first_desync_with_dynamic_target",
            Inputs(
                show_zones=True,
                in_combat=True,
                has_swing_timing=True,
                has_dynamic_target=True,
                needs_resync=True,
                cue_resync_active=False,
            ),
        ),
        (
            "out_of_combat",
            Inputs(
                show_zones=True,
                in_combat=False,
                has_swing_timing=True,
                has_dynamic_target=True,
                needs_resync=True,
                cue_resync_active=False,
            ),
        ),
        (
            "no_swing_timing_yet",
            Inputs(
                show_zones=True,
                in_combat=True,
                has_swing_timing=False,
                has_dynamic_target=True,
                needs_resync=True,
                cue_resync_active=False,
            ),
        ),
        (
            "desync_without_dynamic_target",
            Inputs(
                show_zones=True,
                in_combat=True,
                has_swing_timing=True,
                has_dynamic_target=False,
                needs_resync=True,
                cue_resync_active=False,
            ),
        ),
        (
            "cue_active_without_delta",
            Inputs(
                show_zones=True,
                in_combat=True,
                has_swing_timing=True,
                has_dynamic_target=False,
                needs_resync=False,
                cue_resync_active=True,
            ),
        ),
    ]

    out = []
    for name, inputs in scenarios:
        before = pre_fix_logic(inputs)
        after = post_fix_logic(inputs)
        current = current_logic(inputs)
        expected = expected_logic(inputs)
        out.append(
            {
                "scenario": name,
                "inputs": inputs,
                "before": before,
                "after": after,
                "current": current,
                "expected": expected,
                "before_matches": before == expected,
                "after_matches": after == expected,
                "current_matches": current == expected,
            }
        )
    return out


def full_matrix_mismatches(logic_fn) -> List[Dict[str, object]]:
    mismatches: List[Dict[str, object]] = []
    for show_zones, in_combat, has_swing_timing, has_dynamic_target, needs_resync, cue_resync_active in product(
        [False, True], repeat=6
    ):
        i = Inputs(
            show_zones=show_zones,
            in_combat=in_combat,
            has_swing_timing=has_swing_timing,
            has_dynamic_target=has_dynamic_target,
            needs_resync=needs_resync,
            cue_resync_active=cue_resync_active,
        )
        got = logic_fn(i)
        expected = expected_logic(i)
        if got != expected:
            mismatches.append(
                {
                    "inputs": i,
                    "current": got,
                    "expected": expected,
                }
            )
    return mismatches


def run() -> int:
    scenarios = scenario_checks()
    mismatches_before = full_matrix_mismatches(pre_fix_logic)
    mismatches_after = full_matrix_mismatches(post_fix_logic)
    mismatches_current = full_matrix_mismatches(current_logic)

    print("=== Scenario Checks ===")
    for s in scenarios:
        status_before = "PASS" if s["before_matches"] else "FAIL"
        status_after = "PASS" if s["after_matches"] else "FAIL"
        status_current = "PASS" if s["current_matches"] else "FAIL"
        print(f"{s['scenario']}: BEFORE={status_before} AFTER={status_after} CURRENT={status_current}")
        if not s["before_matches"]:
            print(f"  inputs:   {s['inputs']}")
            print(f"  before:   {s['before']}")
            print(f"  after:    {s['after']}")
            print(f"  current:  {s['current']}")
            print(f"  expected: {s['expected']}")

    print("\n=== Full Matrix Summary (Before Fix) ===")
    print("Total combinations: 64")
    print(f"Mismatches: {len(mismatches_before)}")
    if mismatches_before:
        print("\n=== Mismatch Cases (Before Fix) ===")
        for idx, m in enumerate(mismatches_before, 1):
            print(f"{idx}. inputs={m['inputs']}")
            print(f"   got={m['current']}")
            print(f"   expected={m['expected']}")

    print("\n=== Full Matrix Summary (After Fix) ===")
    print("Total combinations: 64")
    print(f"Mismatches: {len(mismatches_after)}")
    if mismatches_after:
        print("\n=== Mismatch Cases (After Fix) ===")
        for idx, m in enumerate(mismatches_after, 1):
            print(f"{idx}. inputs={m['inputs']}")
            print(f"   got={m['current']}")
            print(f"   expected={m['expected']}")

    print("\n=== Full Matrix Summary (Current) ===")
    print("Total combinations: 64")
    print(f"Mismatches: {len(mismatches_current)}")
    if mismatches_current:
        print("\n=== Mismatch Cases (Current) ===")
        for idx, m in enumerate(mismatches_current, 1):
            print(f"{idx}. inputs={m['inputs']}")
            print(f"   got={m['current']}")
            print(f"   expected={m['expected']}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
