---
type: Friction Entry
title: "Home Manager also provides the installed Seihou executable"
description: "The default-priority release installation collided with the Home Manager profile after removal of the old standalone package."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-10-28T14:49:10Z"
frictionId: FRIC-6
status: "resolved"
impact: detour
kind: environment
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/seihou"
affectedVersion: "0.12.0.1"
plan: "docs/plans/115-validate-recipes-without-running-their-composition.md"
workaround: "Preserve the Home Manager profile and add the released Seihou profile entry at priority 4."
resolution: "Installed github:shinzui/seihou/v0.12.0.1 at priority 4 while preserving the Home Manager profile; the effective executable reports 0.12.0.1 at f529a7a and passes installed acceptance."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-10-28T14:50:01Z"
    change: "Record the successful priority-aware installation without removing Home Manager."
---
# Home Manager also provides the installed Seihou executable

## Attempted

Replace the old standalone Nix profile entry with github:shinzui/seihou/v0.12.0.1

## Encountered

The Home Manager profile also provides bin/seihou at priority 5, so adding the release at default priority failed and was rolled back.

```text
An existing package already provides bin/seihou; conflicting packages have a priority of 5.
```

## Workaround

Preserve the Home Manager profile and add the released Seihou profile entry at priority 4.
