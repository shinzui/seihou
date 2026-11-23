---
type: Friction Entry
title: "Baikai provider source needs a core export absent from its declared release bound"
description: "Building Seihou with the Baikai OpenAI source package still selected a Hackage core release that lacks the provider's replay dependency."
generated:
  by: "codex-cli/gpt-6.2-sol"
  at: "2026-11-23T14:29:41Z"
frictionId: FRIC-22
status: "promoted"
impact: detour
kind: tooling
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/baikai/packages/baikai-openai"
plan: "docs/plans/127-let-callers-supply-tool-policy-for-batch-blueprint-runs-and-migrations.md"
workaround: "Build the disposable consumer with both the Baikai core and OpenAI checkout packages and keep the release dependency unresolved."
promotedTo: "mori://shinzui/baikai/okf/improvement-requests/concepts/IR-14"
amended:
  - by: "codex-cli/gpt-6.2-sol"
    at: "2026-11-23T14:42:54Z"
    change: "The Baikai release boundary now tracks publishing both core and OpenAI before Seihou adopts the API."
---
# Baikai provider source needs a core export absent from its declared release bound

## Attempted

Run cabal build exe:seihou with only the Baikai OpenAI source package added to cabal.project.local in an isolated consumer worktree.

## Encountered

The solver accepted baikai 0.10.1.1 from Hackage, but compiling Baikai.Provider.OpenAI.Responses.Request failed.

```text
GHC-76037: The module Baikai.Content does not export outputItemReplay.
```

## Workaround

Build the disposable consumer with both the Baikai core and OpenAI checkout packages and keep the release dependency unresolved.
