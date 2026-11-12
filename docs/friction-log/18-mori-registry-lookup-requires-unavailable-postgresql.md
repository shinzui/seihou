---
type: Friction Entry
title: "Mori registry lookup requires unavailable PostgreSQL"
description: "Mori discovery could not locate dependency or producer sources because its notifier failed to connect to the local PostgreSQL socket."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-12T03:04:57Z"
frictionId: FRIC-18
status: "accepted"
impact: detour
kind: environment
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/mori"
plan: "docs/plans/124-bring-generated-okf-bundles-up-to-date-with-seihou-features-and-latest-okf.md"
workaround: "Inspect the verified upstream OKF release tag and a disposable producer checkout."
resolution: "Verified upstream release sources and a disposable producer checkout satisfied this plan; recovery of the local Mori database remains an environment concern."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-12T03:22:17Z"
    change: "Accept the documented upstream-source fallback for this implementation."
---
# Mori registry lookup requires unavailable PostgreSQL

## Attempted

mori registry list; mori registry search okf; mori registry show shinzui/okf --full; mori registry docs shinzui/okf; mori registry show shinzui/seihou-modules --full

## Encountered

NotifierConnectError: local PostgreSQL socket refused connection

## Workaround

Inspect the verified upstream OKF release tag and a disposable producer checkout.
