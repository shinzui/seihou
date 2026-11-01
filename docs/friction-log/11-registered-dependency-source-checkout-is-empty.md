---
type: Friction Entry
title: "Registered dependency source checkout is empty"
description: "Mori resolves the directory dependency to an empty temporary checkout, so source inspection requires recovering the exact released package separately."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-01T21:27:48Z"
frictionId: FRIC-11
status: "accepted"
impact: detour
kind: environment
origin: "mori://shinzui/seihou"
affects: "mori://haskell/directory"
plan: "docs/plans/118-extend-recipes-through-a-single-origin-aware-base.md"
workaround: "Read directory 1.3.10.1 from the current Cabal plan and fetch its authoritative Hackage source into a scoped temporary directory."
resolution: "Accept the local corpus lifecycle limitation for this plan: inspect the exact dependency version recovered from authoritative Hackage sources. Restoring or retiring persistent Mori source registrations is separate environment maintenance."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-01T21:30:48Z"
    change: "Triage the stale temporary-source registration with an exact-version source recovery workaround."
---
# Registered dependency source checkout is empty

## Attempted

Inspect permission APIs through mori registry search directory and mori registry show haskell/directory --full.

## Encountered

The registered path /private/tmp/seihou-105-directory-source exists but contains no source files.

## Workaround

Read directory 1.3.10.1 from the current Cabal plan and fetch its authoritative Hackage source into a scoped temporary directory.
