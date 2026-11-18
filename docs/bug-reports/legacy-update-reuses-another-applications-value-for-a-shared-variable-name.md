---
type: Bug Report
title: "Updating a legacy manifest reuses another application's value for a shared variable name, so exec-plan targets the release skill"
description: >-
  On a manifest that predates recorded applications, `seihou update <target>` seeds the
  target's inputs from the flat legacy `variables` map and only treats a name as ambiguous when
  it is declared twice inside the target's own composition. A generic name such as `skill.name`,
  last written by a different application (`link-skill` with `skill.name=release`), is therefore
  reused silently, and the instance's own legacy `parentVars` (`skill.name=exec-plan`) are
  ignored, so `seihou update exec-plan` and `seihou update master-plan` aim at
  `agents/skills/release/SKILL.md` and stop on a conflict.
bugId: BUG-6
affects: mori://shinzui/seihou
affectedVersion: 0.16.0.1
origin: mori://shinzui/relay-pagination
severity: degraded
status: reported
generated:
  by: process:claude-code
  at: "2026-11-18T15:36:23Z"
observed: >-
  In mori://shinzui/relay-pagination (manifest schema 15, `applications: []`, applied by the
  `hackage-release` blueprint in July 2026), the flat legacy map held `"skill.name": "release"`,
  written by the root `link-skill` instance that links the project's own release skill. The
  legacy `exec-plan` module record carried `parentVars: {"skill.name": "exec-plan"}`.
  `seihou update exec-plan --dry-run` and `seihou update master-plan --dry-run` both failed with
  `Update failed [unresolved_conflicts]: Unresolved paths require an interactive terminal or an
  applicable --force choice: agents/skills/release/SKILL.md`, and printed no
  `AmbiguousLegacyValue` warning for `skill.name`. The same master-plan run did print that
  warning for `intentions.enabled`, which is declared twice inside its own composition. A fresh
  resolution (`seihou vars exec-plan --explain`) gives `skill.name = "exec-plan" [default]`, and
  `seihou update exec-plan --dry-run --var skill.name=exec-plan` planned cleanly with 0 conflicts.
  Updating the root `link-skill` afterwards needed `--var skill.name=release`, because by then the
  shared key had been rewritten to `exec-plan`.
expected: >-
  A legacy value should be reused only when no other recorded module could have written it. A
  name declared by modules outside the target's composition (here `link-skill`, `exec-plan` and
  `master-plan` all declare `skill.name`) should be treated as ambiguous, with the
  `AmbiguousLegacyValue` warning, and resolved afresh. When the legacy module record carries
  `parentVars` for that name, those are the instance's authoritative value and should win over
  the flat map.
workaround: >-
  Pass the intended value explicitly on each targeted update, for example
  `seihou update master-plan --var skill.name=exec-plan` and
  `seihou update link-skill --var skill.name=release`. Each update then records its own
  application with correct inputs, so later updates no longer read the flat map. Update the
  application that owns a dependency (master-plan), not the dependency (exec-plan) itself.
reproduction:
  - Start from a legacy manifest (no `applications`) in which `link-skill` was applied at the root with `skill.name=release` after `master-plan` (which depends on `exec-plan` and `link-skill` with `skill.name` bindings), so the flat `variables` map ends with `skill.name` set to `release`; keep a project-authored `agents/skills/release/SKILL.md`.
  - Run `seihou update exec-plan --dry-run` with exec-plan 0.14.0 installed and see `unresolved_conflicts` on `agents/skills/release/SKILL.md` with no ambiguity warning for `skill.name`.
  - Run `seihou update exec-plan --dry-run --var skill.name=exec-plan` and see a clean plan with 0 conflicts.
timestamp: "2026-11-18T15:36:23Z"
---

# Bug Report: legacy update reuses another application's value for a shared variable name

## What is wrong

`legacySavedValues` in `seihou-cli/src/Seihou/CLI/Update.hs` (line 901 at `6e1a7e0`) builds
the target's saved inputs from the manifest's flat `variables` map. It counts declarations only
across `modulesInOrder`, which is the target's own composition. A name declared once in that
composition counts as `reusable`, and its flat value is taken, whichever recorded module last
wrote it.

Before applications were recorded, the flat map is last-writer-wins across every module the
project ever ran. Generic names such as `skill.name` are declared by many unrelated modules
(`link-skill`, `exec-plan`, `master-plan`), so a single declaration inside the target's
composition says nothing about who wrote the value. The legacy module records already hold the
better answer: each instance's `parentVars`. In this case `exec-plan`'s record said
`skill.name=exec-plan`, and the update used the flat `release` instead.

The `AmbiguousLegacyValue` warning has the same blind spot. It fires only for names counted
twice inside the composition, so the user sees a warning for `intentions.enabled` but none for
the `skill.name` value that actually redirected the update.

## Where it was observed

While bringing mori://shinzui/relay-pagination from exec-plan and master-plan 0.6.0 to 0.14.0
and from nix-haskell-flake 0.13.0 to 0.40.0. The project's own release skill, linked through
`link-skill` with `skill.name=release`, had left `release` in the shared key.

## Consequence

* The update aims a module at another skill's files. Here the conflict stopped it. If
  `agents/skills/release/` had been absent, or had been accepted with `--force`, exec-plan's
  `SKILL.md` would have replaced the project's release skill, and the new application would
  have recorded `skill.name=release`.
* Nothing in the output points at the cause. The conflict names an unrelated path, and the only
  ambiguity warning shown concerns a different variable.
* Working around it on one target rewrites the shared key, which then misleads the next
  targeted update (`link-skill` here) in the opposite direction.
* Related: `seihou update exec-plan`, where exec-plan was only ever a dependency of master-plan,
  recorded exec-plan as a new root application rather than upgrading the dependency instance.
  The project now has two exec-plan applications at 0.14.0 that own the same files, and
  `seihou remove exec-plan --application …` refuses because exec-plan declares no removal
  specification.
