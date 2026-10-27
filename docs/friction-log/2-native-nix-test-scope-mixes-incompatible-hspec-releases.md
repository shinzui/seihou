---
type: Friction Entry
title: "Native Nix test scope mixes incompatible Hspec releases"
description: "The Seihou Nix package cannot configure hspec-api 2.11.17 against its resolved hspec-core 2.11.18."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-10-27T04:12:29Z"
frictionId: FRIC-2
status: "resolved"
impact: blocked
kind: tooling
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/haskell-nix"
affectedVersion: "unreleased"
plan: "docs/plans/104-adopt-seed-steps-in-seihou-modules-and-document-seed-authoring.md"
resolution: "Align hspec-api with Hspec 2.11.18 and relax the current tasty-hspec QuickCheck bound only in the local Nix overlay; native package builds retain all tests and all 2080 pass."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-10-27T04:18:39Z"
    change: "Verified upstream releases/bounds and adapter source; native core, CLI and extension suites and bundle build pass."
---
# Native Nix test scope mixes incompatible Hspec releases

## Attempted

nix build .#default --no-link --no-write-lock-file --print-build-logs

## Encountered

hspec-api 2.11.17 declares hspec-core ==2.11.17; the composed scope resolves hspec-core 2.11.18.

```text
Error: [Cabal-8010] Encountered missing or private dependencies: hspec-core ==2.11.17
```
