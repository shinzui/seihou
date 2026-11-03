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
workaround: "Verify the released tag through nix build or nix shell and add no standalone profile entry. This supersedes the earlier priority 4 entry, which kept overriding Home Manager after later releases."
resolution: "The release skill now verifies published tags with nix build and nix shell without changing the profile, so Home Manager remains the only installed seihou; the stale v0.13.0.0 priority 4 entry was removed from the profile."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-10-28T14:50:01Z"
    change: "Record the successful priority-aware installation without removing Home Manager."
  - by: "claude-code/claude-opus-5-5"
    at: "2026-11-03T16:04:50Z"
    change: "Supersede the priority 4 install: its standalone entry left seihou stuck at 0.13.0.0 after 0.15.0.0 reached Home Manager."
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

Verify the released tag through `nix build` or `nix shell` and add no standalone profile entry, as the "Published Nix verification" section of [the release skill](../../agents/skills/release/SKILL.md) describes.

The original workaround preserved the Home Manager profile and added the released Seihou profile entry at priority 4. That entry kept overriding Home Manager after later releases: `seihou --version` stayed at 0.13.0.0 after Home Manager had moved to 0.15.0.0, until `nix profile remove seihou` cleared it on 2026-11-03.
