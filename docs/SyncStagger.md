# Sync and Stagger (Simple Guide)

This page explains what the ShammyTime stagger bar means and exactly when to press your resync macro.

- Guide reference: [Enhancement Shaman Guide](https://www.enhanceshaman.com/pages/guide/sync_stagger)

## Goal

You want two things:

- Main hand (MH) should hit first.
- Off hand (OH) should hit shortly after (within 0.5s).

That gives good sync and good stagger.

## How to Read the Bar

- Top bar = MH swing progress.
- Bottom bar = OH swing progress.
- Red vertical mark = OH 50% arm point.
- Dynamic marker = next valid click spot from MH+OH timing.
- Marker color:
  - green = normal click timing
  - yellow = hold mode timing
- Red OH areas = do not click (early 50%-55% buffer and late no-click zone).

Visuals:

- Swing bars:
  - Gold = ideal stagger (MH first, OH follows in the good window).
  - White = not ideal (same-time, drifting, or OH-first).
- Delta text (middle number like `0.23s`) is always yellow.

## Resync Macro (What Actually Happens)

Use this macro:

```bash
/cleartarget
/targetlasttarget
/startattack
/st resync
```

Important behavior:

- If OH is below 50% when you press, nothing changes.
- If OH is at or above 50%, OH is pulled back to about 50%.

So pressing too early is expected to do nothing.

## Exactly When to Press

ShammyTime uses a dynamic rule:

- OH must be at least 50%, with a +5% click buffer (about 55% in practice).
- MH must be inside the dynamic time window (computed from weapon speeds and the 0.5s rule).
- Timing is latency-compensated (current ping + tiny safety buffer).
- Haste changes are re-timed immediately (mid-swing) in the visual.

If OH is ready but MH is outside that band, wait.  
The dynamic marker shows where OH should be at the next valid click.

Special case:

- If MH is very low while OH is very high (for example `MH 10% / OH 90%`), click to hold OH back first.

Example:

- MH 10% / OH 40% -> wait until OH reaches about 80%, then click.

## Helper Text Behavior

The helper uses these messages:

- `Click!` = click now (window open right now).
- `Click Multiple Times!` = hold mode (OH is already far ahead; keep pressing to hold OH back).
- `Synced: wait for marker` = MH/OH are stacked; wait for dynamic window.
- `Wait: OH < 50%` = macro cannot affect OH yet.
- `Wait: OH < 55%` = still inside the early safety buffer.
- `Wait for marker` = OH is armed but MH is not in-window yet.

## Quick Troubleshooting

- "I pressed and nothing happened": OH was likely below 50% (working as intended).
- "I see no helper text": either resync is not needed, or MH/OH are not at a valid click timing yet.
- "Drifting keeps coming back": click on the dynamic marker timing instead of forcing a fixed OH percent pass.
