---
type: Friction Entry
title: "Shikumi's published bounds exclude the first Baikai release with reviewed Codex hooks"
description: "The released Seihou dependency graph cannot select the Baikai API while Shikumi 0.5.1.0 caps both Baikai and its Effectful binding at the previous major series."
generated:
  by: "codex-cli/gpt-6.2-sol"
  at: "2026-11-23T16:01:48Z"
frictionId: FRIC-24
status: "resolved"
impact: detour
kind: tooling
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/shikumi/packages/shikumi"
affectedVersion: "0.5.1.0"
plan: "docs/plans/127-let-callers-supply-tool-policy-for-batch-blueprint-runs-and-migrations.md"
workaround: "Test the published archives in the isolated Seihou candidate with scoped allow-newer for those two Shikumi bounds."
resolution: "Shikumi 0.5.1.1 is published with compatible Baikai and Effectful bounds."
amended:
  - by: "codex-cli/gpt-6.2-sol"
    at: "2026-11-23T19:17:24Z"
    change: "Verified the release tag and a clean Seihou Cabal solve using Hackage archives without an override."
---
# Shikumi's published bounds exclude the first Baikai release with reviewed Codex hooks

## Attempted

Resolve Seihou's released Hackage dependencies for Baikai 0.11.0.0 and Baikai OpenAI 0.7.4.0.

## Encountered

Shikumi 0.5.1.0 requires baikai <0.11 and baikai-effectful <0.5.

## Workaround

Test the published archives in the isolated Seihou candidate with scoped allow-newer for those two Shikumi bounds.
