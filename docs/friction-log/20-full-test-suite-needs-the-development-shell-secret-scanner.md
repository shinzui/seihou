---
type: Friction Entry
title: "Full test suite needs the development shell secret scanner"
description: "Running Cabal directly omitted gitleaks from PATH and caused unrelated judgement checks to fail."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-15T19:08:31Z"
frictionId: FRIC-20
status: "resolved"
impact: detour
kind: environment
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/seihou"
plan: "docs/plans/126-start-interactive-blueprint-runs-with-an-initial-message.md"
workaround: "Run the full suite through nix develop, which supplies gitleaks."
resolution: "The repository development shell supplies gitleaks; final full-suite verification runs through nix develop."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-15T19:09:12Z"
    change: "Use the complete development environment for the full suite."
---
# Full test suite needs the development shell secret scanner

## Attempted

cabal test all --enable-tests --test-show-details=direct

## Encountered

Judgement tests failed because gitleaks was not on PATH.

## Workaround

Run the full suite through nix develop, which supplies gitleaks.
