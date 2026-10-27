---
type: Friction Entry
title: "Checkout tests require a newer schema than the local submodule"
description: "Checkout acceptance fixtures import a mutable local schema checkout and fail before exercising the command."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-10-27T02:20:55Z"
frictionId: FRIC-1
status: "resolved"
impact: detour
kind: tooling
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/seihou"
affectedVersion: "unreleased"
plan: "docs/plans/100-record-seed-receipts-in-manifest-schema-8.md"
workaround: "Make checkout fixtures import the published schema pinned by the executable, preserving the pre-existing schema submodule checkout."
resolution: "Checkout fixtures read the executable-pinned published schema from Git objects instead of the mutable submodule checkout; checkout acceptance passes without changing the checkout."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-10-27T02:23:15Z"
    change: "Use the pinned fixture schema and verify the full CLI suite"
---
# Checkout tests require a newer schema than the local submodule

## Attempted

nix develop --no-write-lock-file -c cabal test seihou-core-test seihou-cli-test --test-show-details=failures

## Encountered

Checkout end-to-end fixtures failed at Dhall evaluation because the existing local schema lacks Command.Action.

```text
Missing record field: Action at S.Command.Action.Apply
```

## Workaround

Make checkout fixtures import the published schema pinned by the executable, preserving the pre-existing schema submodule checkout.
