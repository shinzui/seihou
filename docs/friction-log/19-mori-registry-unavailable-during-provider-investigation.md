---
type: Friction Entry
title: "Mori registry unavailable during provider investigation"
description: "The local Mori registry PostgreSQL socket refused connections, preventing dependency source discovery."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-15T19:02:25Z"
frictionId: FRIC-19
status: "accepted"
impact: detour
kind: environment
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/mori"
plan: "docs/plans/126-start-interactive-blueprint-runs-with-an-initial-message.md"
workaround: "Reuse existing resolver and request interfaces; observe provider argv with isolated terminal fixtures."
resolution: "Registry availability remains external to this launch fix; existing interfaces and terminal argv fixtures suffice without a dependency change."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-15T19:07:22Z"
    change: "Accept local registry outage for this implementation; dependency source discovery must be retried before future dependency changes."
---
# Mori registry unavailable during provider investigation

## Attempted

mori registry list

## Encountered

NotifierConnectError: local PostgreSQL connection refused

## Workaround

Reuse existing resolver and request interfaces; observe provider argv with isolated terminal fixtures.
