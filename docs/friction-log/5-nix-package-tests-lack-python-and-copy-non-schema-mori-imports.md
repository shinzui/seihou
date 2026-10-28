---
type: Friction Entry
title: "Nix package tests lack Python and copy non-schema Mori imports"
description: "The published native package build failed after source checks because the isolated test environment lacked Python and schema fixtures copied Mori metadata with a remote import."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-10-28T14:37:44Z"
frictionId: FRIC-5
status: logged
impact: detour
kind: tooling
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/seihou"
affectedVersion: "0.12.0.0"
plan: "docs/plans/113-declare-and-install-cross-registry-recipe-dependencies.md"
workaround: "Add Python to native test tools, exclude mori.dhall from copied schema fixtures, and issue a patch release with a complete native package build before publication."
---
# Nix package tests lack Python and copy non-schema Mori imports

## Attempted

nix build github:shinzui/seihou/v0.12.0.0

## Encountered

37 CLI tests failed: Python process fixtures could not start and checkout fixture installation attempted an unrelated remote Mori schema import.

```text
python3 is required for process fixture ownership; certificate has unknown CA
```

## Workaround

Add Python to native test tools, exclude mori.dhall from copied schema fixtures, and issue a patch release with a complete native package build before publication.
