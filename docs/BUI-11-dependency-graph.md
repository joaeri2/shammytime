# BUI-11 Sub-Task Dependency Graph

This document visualizes the dependencies between the 10 sub-tasks to help with project planning and parallel work assignment.

---

## Visual Dependency Graph

```
┌─────────────────────────────────────────────────────────────────┐
│                        START HERE                                │
│                  (3 tasks can run in parallel)                   │
└─────────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   BUI-11-1   │    │   BUI-11-4   │    │   BUI-11-6   │
│    Window    │    │Configuration │    │  Permission  │
│  Discovery   │    │    System    │    │   Checker    │
│              │    │              │    │              │
│  Priority: H │    │  Priority: M │    │  Priority: H │
│Complexity: L │    │Complexity: L │    │Complexity: M │
│   Time: 1h   │    │   Time: 1h   │    │  Time: 1.5h  │
└──────────────┘    └──────────────┘    └──────────────┘
        │                   │
        │                   │
        ▼                   │
┌──────────────┐            │
│   BUI-11-2   │            │
│  Screenshot  │            │
│   Capture    │            │
│              │            │
│  Priority: H │            │
│Complexity: L │            │
│   Time: 1h   │            │
└──────────────┘            │
        │                   │
        │                   │
        ▼                   │
┌──────────────┐            │
│   BUI-11-3   │            │
│   Storage    │            │
│  Management  │            │
│              │            │
│  Priority: M │            │
│Complexity: L │            │
│  Time: 0.5h  │            │
└──────────────┘            │
        │                   │
        └─────────┬─────────┘
                  │
                  ▼
        ┌──────────────────┐
        │    BUI-11-5      │
        │      Main        │
        │  Orchestration   │
        │                  │
        │   Priority: H    │
        │ Complexity: M    │
        │    Time: 1.5h    │
        └──────────────────┘
                  │
                  ▼
        ┌──────────────────┐
        │    BUI-11-7      │
        │   Automation     │
        │   (launchd)      │
        │                  │
        │   Priority: M    │
        │ Complexity: M    │
        │    Time: 1.5h    │
        └──────────────────┘
                  │
        ┌─────────┴─────────┐
        │                   │
        ▼                   ▼
┌──────────────┐    ┌──────────────┐
│   BUI-11-8   │    │   BUI-11-9   │
│Documentation │    │   Testing    │
│              │    │              │
│  Priority: H │    │  Priority: M │
│Complexity: L │    │Complexity: M │
│   Time: 1h   │    │   Time: 2h   │
└──────────────┘    └──────────────┘
        │                   │
        └─────────┬─────────┘
                  │
                  ▼
        ┌──────────────────┐
        │   BUI-11-10      │
        │     Agent        │
        │  Integration     │
        │    Examples      │
        │   Priority: L    │
        │ Complexity: L    │
        │    Time: 1h      │
        └──────────────────┘
                  │
                  ▼
        ┌──────────────────┐
        │      DONE!       │
        └──────────────────┘
```

---

## Critical Path (Longest Sequence)

The critical path determines the minimum time to complete the project:

```
BUI-11-1 (1h) → BUI-11-2 (1h) → BUI-11-5 (1.5h) → BUI-11-7 (1.5h) → BUI-11-9 (2h) → BUI-11-10 (1h)
```

**Total Critical Path Time**: 8 hours

**With Parallel Work**: 6-7 hours (tasks 1, 4, 6 run in parallel)

---

## Parallel Work Opportunities

### Wave 1 (Start Immediately)
```
Developer A: BUI-11-1 (Window Discovery)
Developer B: BUI-11-4 (Configuration)
Developer C: BUI-11-6 (Permission Checker)
```
**Time**: 1.5 hours (longest task in wave)

---

### Wave 2 (After Wave 1)
```
Developer A: BUI-11-2 (Screenshot Capture) [requires BUI-11-1]
Developer B: [idle or helping with docs]
Developer C: [idle or helping with docs]
```
**Time**: 1 hour

---

### Wave 3 (After Wave 2)
```
Developer A: BUI-11-3 (Storage Management) [requires BUI-11-2]
Developer B: [idle or code review]
Developer C: [idle or code review]
```
**Time**: 0.5 hours

---

### Wave 4 (After Wave 3)
```
Developer A: BUI-11-5 (Main Orchestration) [requires 1,2,3,4]
Developer B: [code review, testing]
Developer C: [code review, testing]
```
**Time**: 1.5 hours

---

### Wave 5 (After Wave 4)
```
Developer A: BUI-11-7 (Automation) [requires BUI-11-5]
Developer B: [helping with BUI-11-7]
Developer C: [preparing docs]
```
**Time**: 1.5 hours

---

### Wave 6 (After Wave 5)
```
Developer A: BUI-11-9 (Testing) [requires BUI-11-7]
Developer B: BUI-11-8 (Documentation) [requires BUI-11-7]
Developer C: [helping with BUI-11-8]
```
**Time**: 2 hours (longest task in wave)

---

### Wave 7 (After Wave 6)
```
Developer A: BUI-11-10 (Agent Examples) [requires 8,9]
Developer B: [final review]
Developer C: [final review]
```
**Time**: 1 hour

---

## Total Time Estimates

### Sequential (One Developer)
```
1 + 1 + 0.5 + 1 + 1.5 + 1.5 + 1.5 + 1 + 2 + 1 = 12 hours
```

### Parallel (Three Developers)
```
Wave 1: 1.5h
Wave 2: 1h
Wave 3: 0.5h
Wave 4: 1.5h
Wave 5: 1.5h
Wave 6: 2h
Wave 7: 1h
────────────
Total: 9 hours
```

### Optimized (Overlap & Efficiency)
```
With code review overlap and efficient handoffs: 6-7 hours
```

---

## Dependency Matrix

| Task | Depends On | Blocks | Can Start |
|------|-----------|--------|-----------|
| BUI-11-1 | None | 2 | ✅ Immediately |
| BUI-11-2 | 1 | 3, 5 | After 1 |
| BUI-11-3 | 2 | 5 | After 2 |
| BUI-11-4 | None | 5 | ✅ Immediately |
| BUI-11-5 | 1, 2, 3, 4 | 7, 8, 9 | After 1-4 |
| BUI-11-6 | None | None | ✅ Immediately |
| BUI-11-7 | 5 | 8, 9 | After 5 |
| BUI-11-8 | 5, 7 | 10 | After 5, 7 |
| BUI-11-9 | 5, 7 | 10 | After 5, 7 |
| BUI-11-10 | 8, 9 | None | After 8, 9 |

---

## Risk Analysis

### High-Risk Dependencies (Blockers)

**BUI-11-5 (Main Orchestration)**:
- Blocks: 7, 8, 9
- Risk: If delayed, entire project delayed
- Mitigation: Assign to most experienced developer

**BUI-11-7 (Automation)**:
- Blocks: 8, 9, 10
- Risk: launchd configuration can be tricky
- Mitigation: Start early, have backup (manual execution)

### Low-Risk Tasks (Can Be Delayed)

**BUI-11-10 (Agent Examples)**:
- Blocks: Nothing
- Risk: Low priority, can be done after MVP
- Mitigation: Can be skipped for initial release

**BUI-11-6 (Permission Checker)**:
- Blocks: Nothing
- Risk: Nice-to-have, not critical for MVP
- Mitigation: Can be added later if needed

---

## Recommended Assignment Strategy

### Strategy A: Speed (Minimize Total Time)
**Goal**: Complete as fast as possible

```
Developer A (Senior):
  - BUI-11-1 (1h)
  - BUI-11-2 (1h)
  - BUI-11-5 (1.5h)
  - BUI-11-7 (1.5h)
  Total: 5 hours

Developer B (Mid-level):
  - BUI-11-4 (1h)
  - BUI-11-3 (0.5h)
  - BUI-11-8 (1h)
  - BUI-11-10 (1h)
  Total: 3.5 hours

Developer C (Mid-level):
  - BUI-11-6 (1.5h)
  - BUI-11-9 (2h)
  Total: 3.5 hours
```

**Total Time**: ~5-6 hours (with handoffs)

---

### Strategy B: Balance (Even Workload)
**Goal**: Distribute work evenly

```
Developer A:
  - BUI-11-1 (1h)
  - BUI-11-2 (1h)
  - BUI-11-5 (1.5h)
  Total: 3.5 hours

Developer B:
  - BUI-11-4 (1h)
  - BUI-11-3 (0.5h)
  - BUI-11-7 (1.5h)
  Total: 3 hours

Developer C:
  - BUI-11-6 (1.5h)
  - BUI-11-8 (1h)
  - BUI-11-9 (2h)
  - BUI-11-10 (1h)
  Total: 5.5 hours
```

**Total Time**: ~6-7 hours

---

### Strategy C: MVP First (Minimum Viable Product)
**Goal**: Get basic functionality working ASAP

**Phase 1 (MVP)** - 3-4 hours:
```
Developer A:
  - BUI-11-1 (1h)
  - BUI-11-2 (1h)
  - BUI-11-5 (1.5h)

Developer B:
  - BUI-11-4 (1h)
  - BUI-11-3 (0.5h)

Developer C:
  - BUI-11-6 (1.5h)
```

**Phase 2 (Automation)** - 2-3 hours:
```
Developer A:
  - BUI-11-7 (1.5h)

Developer B:
  - BUI-11-8 (1h)

Developer C:
  - BUI-11-9 (2h)
```

**Phase 3 (Polish)** - 1 hour:
```
Developer A:
  - BUI-11-10 (1h)
```

**Total Time**: 6-8 hours (with breaks between phases)

---

## Bottleneck Analysis

### Primary Bottleneck: BUI-11-5 (Main Orchestration)
- **Why**: Depends on 4 tasks (1, 2, 3, 4)
- **Impact**: Blocks 3 downstream tasks (7, 8, 9)
- **Solution**: Prioritize tasks 1-4, assign best developer to task 5

### Secondary Bottleneck: BUI-11-7 (Automation)
- **Why**: Blocks documentation and testing
- **Impact**: Can't finalize docs until automation works
- **Solution**: Start early, have fallback (manual execution)

### No Bottleneck: BUI-11-6 (Permission Checker)
- **Why**: Doesn't block anything
- **Impact**: Can be done anytime
- **Solution**: Good task for junior developer or parallel work

---

## Quick Decision Guide

### "We need it working TODAY"
→ Use **Strategy A (Speed)** with 3 developers
→ Skip tasks 6, 9, 10 initially (add later)
→ Focus on: 1 → 2 → 4 → 5 → 7 → 8
→ **Time**: 3-4 hours

### "We want it done RIGHT"
→ Use **Strategy B (Balance)** with 3 developers
→ Complete all 10 tasks
→ **Time**: 6-7 hours

### "We have ONE developer"
→ Use **Strategy C (MVP First)** with phases
→ Complete MVP first, then enhance
→ **Time**: 8-10 hours (with breaks)

### "We want to TEST as we go"
→ Use **Strategy C (MVP First)** with phases
→ Test after each phase
→ **Time**: 8-10 hours (includes testing time)

---

## Gantt Chart (Parallel Execution)

```
Hour:   0    1    2    3    4    5    6    7    8    9
Dev A:  [1  ][2  ][3][  5  ][  7  ][  9        ][ 10]
Dev B:  [  4    ][idle][idle][idle][  8  ][idle][idle]
Dev C:  [    6      ][idle][idle][idle][idle][idle][idle]

Legend:
[1] = BUI-11-1 (Window Discovery)
[2] = BUI-11-2 (Screenshot Capture)
[3] = BUI-11-3 (Storage Management)
[4] = BUI-11-4 (Configuration)
[5] = BUI-11-5 (Main Orchestration)
[6] = BUI-11-6 (Permission Checker)
[7] = BUI-11-7 (Automation)
[8] = BUI-11-8 (Documentation)
[9] = BUI-11-9 (Testing)
[10] = BUI-11-10 (Agent Examples)
```

**Note**: Idle time can be used for code review, testing, or documentation

---

## Summary

- **Critical Path**: 8 hours (sequential)
- **Optimized Time**: 6-7 hours (parallel)
- **Minimum MVP**: 3-4 hours (skip 6, 9, 10)
- **Bottlenecks**: Tasks 5 and 7
- **Parallel Opportunities**: Tasks 1, 4, 6 can start immediately
- **Recommended Strategy**: Strategy A (Speed) or Strategy C (MVP First)

---

**Created**: 2026-02-18  
**Version**: 1.0  
**Status**: Ready for Project Planning
