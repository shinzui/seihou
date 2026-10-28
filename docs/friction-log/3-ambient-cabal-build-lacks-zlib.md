---
type: Friction Entry
title: "Ambient Cabal build lacks zlib"
description: "The ambient GHC 9.10.3 build fails configuring zlib; the Nix development shell supplies the supported toolchain and native libraries."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-10-28T02:54:37Z"
frictionId: FRIC-3
status: "resolved"
impact: detour
kind: environment
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/seihou"
plan: "docs/plans/111-run-blueprint-migrations-without-an-interactive-terminal.md"
workaround: "Run build, tests, and documentation audit through nix develop --no-write-lock-file -c."
resolution: "The repository Nix development shell supplies zlib and GHC 9.12.4; build, CLI tests, and documentation audit pass there."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-10-28T02:58:29Z"
    change: "Verified the supported development-shell workflow after the ambient native-library failure."
---
# Ambient Cabal build lacks zlib

## Attempted

cabal build exe:seihou and just audit-cli-docs

## Encountered

Cabal-7125: Missing (or bad) C library: z

## Workaround

Run build, tests, and documentation audit through nix develop --no-write-lock-file -c.
