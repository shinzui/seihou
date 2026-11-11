---
type: Friction Entry
title: "Non-interactive seihou update cancels without naming --json"
description: "seihou update run without a terminal declines its own confirmation and prints only 'Update cancelled; no managed state was changed.', without saying that --json is the noninteractive way to apply it."
generated:
  by: "claude-code/claude-opus-5-5"
  at: "2026-11-11T21:31:54Z"
frictionId: FRIC-15
status: logged
impact: slowdown
kind: interface
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/seihou"
plan: "docs/plans/110-add-first-class-user-defined-judgements-backed-by-shikumi.md"
workaround: "Run seihou update ... --json, which skips confirmation"
---
# Non-interactive seihou update cancels without naming --json

## Attempted

Applying seihou update demo --commit from a script to verify the commit gate live

## Encountered

Exit 0 with 'Update cancelled'; piping 'y' on stdin also cancelled, because confirmApply returns False for a non-terminal

```text
Update cancelled; no managed state was changed.
```

## Workaround

Run seihou update ... --json, which skips confirmation
