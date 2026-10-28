---
type: Friction Entry
title: "TAN consumer acceptance has no implemented producer artifact"
description: "The TAN registry is unregistered and contains no recipe, blocking final consumer acceptance."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-10-28T13:11:20Z"
frictionId: FRIC-4
status: logged
impact: blocked
kind: environment
origin: "mori://shinzui/seihou"
affects: "mori://tan/tan-seihou-modules"
plan: "docs/plans/113-declare-and-install-cross-registry-recipe-dependencies.md"
---
# TAN consumer acceptance has no implemented producer artifact

## Attempted

mori registry show tan/tan-seihou-modules --full, followed by inspection of the user-supplied checkout

## Encountered

Mori reports project not found; seihou-registry.dhall has empty artifact lists and the consumer MasterPlan gates implementation on upstream fixes.

```text
Project tan/tan-seihou-modules not found in local registry; no recipes/tan-keiro-project/recipe.dhall exists.
```
