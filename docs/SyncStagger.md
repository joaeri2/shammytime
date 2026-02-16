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
- The 50% and 60% marks show the resync tap window.

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

ShammyTime uses one fixed window:

- Press only when OH is between 50% and 60%.

How many times to press depends on the situation:

- OH-first: press once.
- Same-time (0.00): press once.
- Drifting (MH first but gap too large): press repeatedly while OH stays in 50%–60%, then stop as soon as it lines up.

## Helper Text Behavior

The helper is intentionally minimal:

- It shows `Click!` only when both are true:
  - resync is needed, and
  - OH is in the 50%–60% window.
- Outside that window, helper text is blank.

There is no wait/observe text.

## Quick Troubleshooting

- "I pressed and nothing happened": OH was likely below 50% (working as intended).
- "I see no helper text": either OH is not in 50%–60%, or resync is not currently needed.
- "Drifting keeps coming back": keep presses inside 50%–60% only; stop as soon as alignment is good.
