---
type: Bug Report
title: "Updating a module that a legacy manifest records only as a dependency seeds it as a new root application"
description: >-
  On a manifest that predates recorded applications, `seihou update <module>` for a module
  recorded only as a dependency (a legacy record with non-empty `parentVars`) does not upgrade
  that instance. `seedLegacyApplication` finds no root record and falls through to
  `seedInstalledLegacyApplication`, which records a brand-new root application built from the
  installed copy, so `seihou update exec-plan` leaves the project with two exec-plan
  applications owning the same files, one of which `seihou remove` cannot remove.
bugId: BUG-7
affects: mori://shinzui/seihou
affectedVersion: 0.16.0.1
origin: mori://shinzui/relay-pagination
severity: degraded
status: reported
generated:
  by: process:claude-code
  at: "2026-11-18T18:34:29Z"
observed: >-
  In mori://shinzui/relay-pagination (legacy manifest, `applications: []`), `exec-plan` was
  recorded only as master-plan's dependency, with `parentVars: {"skill.name": "exec-plan"}`;
  there was no root `exec-plan` record. `seihou update exec-plan` (with
  `--var skill.name=exec-plan`, the BUG-6 workaround) succeeded and recorded application
  `808a1fc3…` targeting module `exec-plan`, with root instances `agent-gitignore` and
  `exec-plan` and no `parentVars`. A later `seihou update master-plan` recorded application
  `a4e0ec04…` whose `exec-plan` instance is bound to `skill.name=exec-plan`. Both applications
  now own `agents/skills/exec-plan/`, and `seihou remove exec-plan --application …` refuses
  because exec-plan declares no removal specification. A dry run against the pre-update tree
  (commit `25e0336~1`) shows the cue: `exec-plan  unversioned -> 0.14.0`, because the new root
  instance matches no legacy record and so carries no recorded version.
expected: >-
  A recorded manifest already handles this: `matchApplications` selects every application that
  contains a requested bare module, so `seihou update exec-plan` updates master-plan's
  application. A legacy manifest should not silently do something different. When the named
  module is recorded only with `parentVars`, `seihou update` should refuse before planning,
  name the recorded dependency instance, and point at updating the module that depends on it
  (here `seihou update master-plan`), or else seed that owning root. Seeding a root application
  from the installed copy should be reserved for a module the legacy records hold as a root.
workaround: >-
  On a legacy manifest, update the module that owns a dependency (`seihou update master-plan`),
  never the dependency itself. A project that already has the duplicate root application must
  drop it by hand from `.seihou/manifest.json`'s `applications`, after checking that the owning
  application records the same files.
reproduction:
  - Start from a legacy manifest (no `applications`) in which master-plan was applied, so `exec-plan` is recorded only with `parentVars` binding `skill.name=exec-plan` and has no root record; commit `25e0336~1` of mori://shinzui/relay-pagination is such a tree.
  - Run `seihou update exec-plan --dry-run --var skill.name=exec-plan` with exec-plan 0.14.0 installed and see the plan line `exec-plan  unversioned -> 0.14.0` for a root application, not an upgrade of master-plan's dependency instance.
  - Apply it, then `seihou update master-plan`, and see two applications that both own `agents/skills/exec-plan/`.
timestamp: "2026-11-18T18:34:29Z"
---

# Bug Report: legacy update of a dependency records it as a new root application

## What is wrong

`resolveSelection` in `seihou-cli/src/Seihou/CLI/Update.hs` hands a legacy target to
`seedLegacyApplication`. That function looks for a root record: a legacy module record with
the requested name and empty `parentVars`, or a recipe of that name. When none exists it falls
through to `seedInstalledLegacyApplication`, which discovers the installed module, builds a
fresh root composition from it, and records it as a new application.

`matchApplications` (`seihou-cli/src/Seihou/CLI/Update/Selection.hs`) also routes a name to the
legacy path in a mixed manifest, when no recorded application contains it but a legacy record
does. So a name recorded only as a dependency gets a new root application there as well.

Nothing in that path asks whether the name exists in the legacy records only as a dependency.
For a module recorded only through `parentVars`, the new application does not upgrade the
recorded instance. It adds a second, unbound owner of the same files.

## Where it was observed

While bringing mori://shinzui/relay-pagination from exec-plan and master-plan 0.6.0 to 0.14.0,
alongside BUG-6. Updating exec-plan directly looked like the narrowest change, and the plan
gave no sign that it would create a new application rather than upgrade the existing instance.

## Consequence

* Two applications own the same paths, so every later update of either one is co-owned and
  subject to the shared-path closure.
* The duplicate cannot be removed with `seihou remove`, because the module declares no removal
  specification; only a hand edit of the manifest clears it.
* The only cue in the plan is `unversioned -> 0.14.0` on the target row, which reads as a
  missing version, not as "this creates a new root".
* It also exposed BUG-6. With no bindings in the new root composition, the flat legacy value
  for `skill.name` was the only candidate.
