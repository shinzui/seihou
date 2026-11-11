---
type: Friction Entry
title: "Running fourmolu directly fails to parse; only nix fmt formats Haskell sources"
description: "The contributor docs never name the formatter entry point, and invoking fourmolu on a source file fails on ImportQualifiedPost, so formatting before commit took a detour through nix fmt."
generated:
  by: "claude-code/claude-opus-5-5"
  at: "2026-11-11T14:17:55Z"
frictionId: FRIC-12
status: "resolved"
impact: slowdown
kind: documentation
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/seihou"
affectedVersion: "unreleased"
plan: "docs/plans/120-let-seihou-update-reconcile-module-owned-files-under-seihou.md"
workaround: "nix fmt -- <files>, which runs treefmt with the configured fourmolu and cabal-gild"
resolution: "docs/dev/contributing.md now has a Formatting section naming nix fmt -- <files> and explaining the direct-fourmolu parse failure."
amended:
  - by: "claude-code/claude-opus-5-5"
    at: "2026-11-11T14:18:18Z"
    change: "Resolved by documenting the formatter entry point in the contributing guide under ExecPlan 120."
---
# Running fourmolu directly fails to parse; only nix fmt formats Haskell sources

## Attempted

fourmolu -i seihou-core/src/Seihou/Core/Path.hs (from the repository root and from seihou-core/) to match the treefmt pre-commit hook before committing

## Encountered

fourmolu could not parse the file because it does not pick up the packages' default extensions; neither CLAUDE.md nor docs/dev/contributing.md mentions nix fmt or treefmt

```text
The GHC parser (in Haddock mode) failed: Found `qualified' in postpositive position.
```

## Workaround

nix fmt -- <files>, which runs treefmt with the configured fourmolu and cabal-gild
