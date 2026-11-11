---
type: Friction Entry
title: "Mori registry unavailable through database tunnel"
description: "Required registry discovery fails because the sungkyung PostgreSQL tunnel cannot connect."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-11T21:37:33Z"
frictionId: FRIC-16
status: logged
impact: blocked
kind: environment
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/mori"
plan: "docs/plans/112-make-gitignore-line-removal-migrations-predictable-during-managed-updates.md"
---
# Mori registry unavailable through database tunnel

## Attempted

mori registry list; mori registry search dhall

## Encountered

NotifierConnectError: PostgreSQL socket connection refused; tunnel logs show SSH timeouts to 100.66.155.64:22
