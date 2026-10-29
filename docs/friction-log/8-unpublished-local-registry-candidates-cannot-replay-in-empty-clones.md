---
type: Friction Entry
title: "Unpublished local registry candidates cannot replay in empty clones"
description: "Local-path and file-URL installs intentionally record no upstream, so a fresh clone with empty caches cannot fetch an unpublished producer candidate."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-10-29T03:53:12Z"
frictionId: FRIC-8
status: "accepted"
impact: detour
kind: interface
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/seihou"
plan: "docs/plans/117-let-recipes-enforce-configured-variable-values.md"
workaround: "Use a scoped Git URL rewrite from the real TAN URL to the committed local candidate during prepublication tests, recording preparation and revision; rerun without the rewrite after publication."
resolution: "Local unpublished installs deliberately cannot promise a fetchable origin; prepublication acceptance records a scoped Git URL rewrite, and release acceptance must omit it."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-10-29T03:58:13Z"
    change: "Retain the origin safety boundary and document the reproducible candidate-test preparation."
---
# Unpublished local registry candidates cannot replay in empty clones

## Attempted

Install the committed TAN candidate through its local Git path or file URL and run update in a fresh clone with empty caches.

## Encountered

The installer records a local origin because HEAD is unpublished, and fresh-clone update reports candidate_artifact_unresolved.

## Workaround

Use a scoped Git URL rewrite from the real TAN URL to the committed local candidate during prepublication tests, recording preparation and revision; rerun without the rewrite after publication.
