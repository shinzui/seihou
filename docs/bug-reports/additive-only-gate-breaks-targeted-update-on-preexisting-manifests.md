---
type: Bug Report
title: Targeted `seihou update` is broken on any manifest that predates `additiveOnly`, and the remedies it prints make it worse
description: >-
  A single-module `seihou update <target>` fails closed on a co-owned `.gitignore` whenever the
  manifest predates the `FileRecord.additiveOnly` field, and the two remedies the error surfaces
  first broaden the write set and print opaque applicationId hashes instead of recording the additive
  fact.
bugId: BUG-1
affects: mori://shinzui/seihou
affectedVersion: 0.9.0.0
origin: mori://tan/mls-service-v2
severity: degraded
status: fixed
fixedVersion: unreleased
resolution: >-
  Fixed by mori://shinzui/seihou/masterplans/11-make-manifest-evolution-explicit-and-targeted-updates-upgrade-safe
  (unreleased after 0.9.0.0). Manifest schema 7 records `sharedWriteMode` (`unknown`, `additive-only`,
  `requires-ownership-closure`) on every file; a targeted `seihou update` certifies `unknown` shared
  paths by compiling co-owners at their recorded versions, without updating them, and publishes the
  6 -> 7 step with its own manifest. Missing evidence is `shared_write_evidence_unavailable` and never
  offers `--include-shared-owners`; owners are named like `seihou status` names them; every warning,
  including `CrossApplicationLastWriter`, renders as prose. Regression:
  `seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs` ("updates one target on a schema-6 manifest without
  touching the co-owner's files (BUG-1)" and "explains a schema-6 targeted plan and a whole-file
  refusal in prose, by application name").
generated:
  by: process:claude-code
  at: "2026-09-17T13:39:06Z"
observed: >-
  `seihou update --commit nix-haskell-flake` aborts with
  `Update failed [shared_path_requires_applications]` because `.gitignore` is co-owned by three
  applications, none recorded as `additiveOnly` (the field is newer than the manifest); the error
  offers `--include-shared-owners` and "select every owner" ahead of the only remedy that records the
  fact, `--include-shared-owners` then wants to rewrite seven unrelated files, and both paths emit
  `CrossApplicationLastWriter` warnings as raw derived `Show`.
expected: >-
  A single-module update of a module that writes `.gitignore` with an additive, idempotent patch
  should succeed against a pre-`additiveOnly` manifest — the outcome IR-8 and plan 90 set out to
  deliver — with a cheap, manifest-only way to record the additive fact, guidance that leads with the
  remedy that actually records it, application names rather than SHAs, and warnings rendered as prose.
workaround: >-
  Run `seihou update` with no targets once (preview with `--dry-run`: it reports 1 file updated —
  the nix-haskell-flake 0.24.0 `.gitignore` — plus the 0.23.2 → 0.24.0 migration; the
  `CrossApplicationLastWriter` lines are attribution warnings, not content changes). That backfills
  `additiveOnly` into the manifest, after which `seihou update --commit nix-haskell-flake` works
  targeted and stays working. Do not use `--include-shared-owners`: it does not record the fact and
  broadens the update to the co-owners' entire applications.
reproduction:
  - Have a project whose `.seihou/manifest.json` was written before seihou v0.9.0.0 (before `FileRecord.additiveOnly`), with a `.gitignore` co-owned by a whole-file/template module (e.g. `nix-haskell-flake`) and one or more additive-patch owners (e.g. the `exec-plan` / `master-plan` skill-link applications via `append-line-if-absent`).
  - Run `seihou update --commit nix-haskell-flake` (or `seihou update nix-haskell-flake --dry-run`).
  - Observe it fail with `Update failed [shared_path_requires_applications]`, naming the co-owners by their `applicationId` SHA and listing `--include-shared-owners` before "run seihou update with no targets".
  - Follow the error's second suggestion, `seihou update nix-haskell-flake --include-shared-owners --dry-run`, and observe it expand to both skill-link applications and plan to rewrite seven unrelated `agents/skills/exec-plan/*` files, emitting eight `CrossApplicationLastWriter` warnings printed as raw Haskell (`CrossApplicationLastWriter "…" (ModuleName {unModuleName = "exec-plan"}) (ModuleName {unModuleName = "exec-plan#bfa0a336"})`).
  - Re-run the bare `seihou update nix-haskell-flake` and observe it fail identically — the flag recorded nothing.
---

# Bug Report: Targeted `seihou update` is broken on manifests that predate `additiveOnly`

## What is wrong

[IR-8](../improvement-requests/exempt-additive-patch-paths-from-shared-ownership-closure.md) and its
plan (`docs/plans/90-exempt-additive-patch-paths-from-the-shared-ownership-closure.md`) added
`FileRecord.additiveOnly` so a targeted `seihou update` can skip the ownership-closure requirement on
a path that every owner writes with an additive, non-overlapping patch. The field is emitted only when
true and decodes as `False` when absent (`Seihou.Engine.Execute`, comment at
`seihou-core/src/Seihou/Engine/Execute.hs:27`) — a deliberate fail-closed reading.

That fail-closed default has no forward path for the manifests that already exist. **The gate meant to
make single-module updates painless instead makes them fail for every consumer who adopted it by
upgrading rather than by starting fresh** — because their manifest was written before the field, so
every owner of every co-owned path reads `additiveOnly = False`.

## Where it was observed

`mori://tan/mls-service-v2` on seihou v0.9.0.0 (`9979f8d`). `.gitignore` is co-owned by three
applications, per `.seihou/manifest.json`:

- `ab01bd76…` — `nix-haskell-flake` (the module being upgraded, 0.23.2 → 0.24.0)
- `808a1fc3…` — the `exec-plan` skill-link application (contributes its lines with `append-line-if-absent`)
- `a4e0ec04…` — the `master-plan` skill-link application (same)

## What happens

`seihou update --commit nix-haskell-flake` aborts:

```
Update failed [shared_path_requires_applications]: Path .gitignore is also owned by application(s)
808a1fc3258b2289be8d629e7275f3faedc130093bbf6b0fe93b2483bb8e1d1e,
a4e0ec0458e0a5aac4aa3d104efe6eef6a66137b8b69d3b2983517d69bf477b3, and it is not recorded as written
only by additive patches -- either an owner writes the whole file, or the manifest predates that
record, in which case one seihou update with no targets will record it. Select every owner, pass
--include-shared-owners, or run seihou update with no targets. Selected:
ab01bd7698a19555769ed09d135014eefdb65bf057a16f3c4289892c9559ea5f
```

Four distinct defects compound here, all reproduced with `--dry-run`:

1. **No targeted backfill.** The only way to record `additiveOnly` is a whole-project `seihou update`.
   A user who asked to upgrade one module is forced to reconcile every application to record a fact
   about one path.

2. **`--include-shared-owners`, offered second, makes it worse.** It does not record `additiveOnly`.
   It expands the selection to the ownership closure and reconciles the co-owners' *entire*
   applications, so a one-module upgrade balloons into an eight-file cross-application rewrite of
   unrelated files:

   ```
   Warning: also updating a4e0ec04… because it co-owns .gitignore
   Warning: also updating 808a1fc3… because it co-owns .gitignore
   Warning: CrossApplicationLastWriter "agents/skills/exec-plan/ADR.md" …
   Warning: CrossApplicationLastWriter "agents/skills/exec-plan/PLANS.md" …
   Warning: CrossApplicationLastWriter "agents/skills/exec-plan/PROVENANCE.md" …
   Warning: CrossApplicationLastWriter "agents/skills/exec-plan/SKILL.md" …
   Warning: CrossApplicationLastWriter "agents/skills/exec-plan/init-plan.ts" …
   Warning: CrossApplicationLastWriter "agents/skills/exec-plan/provenance-model.ts" …
   Warning: CrossApplicationLastWriter "agents/skills/exec-plan/record-provenance.ts" …
   Warning: CrossApplicationLastWriter ".gitignore" …
   ```

   And it records nothing, so the next bare `seihou update nix-haskell-flake` fails identically. The
   remedy the user reaches for first both widens the blast radius and fails to fix the underlying
   record.

3. **The guidance leads with the wrong remedy, in hashes.** `errorMessage` at
   `seihou-cli/src/Seihou/CLI/Update/Render.hs:373-383` lists "Select every owner, pass
   `--include-shared-owners`, or run seihou update with no targets" — the only remedy that records the
   fact (the no-target update) is last, right after the message itself diagnosed the predates-record
   case. Co-owners are named by `applicationId` SHA (Render.hs:377, 383), though `seihou status` prints
   the same applications by name (`link-skill [skill.name=exec-plan]`, `master-plan`), so "select every
   owner" is not actionable without hand-decoding hashes.

4. **`CrossApplicationLastWriter` renders as raw `Show`.** `warningText` (Render.hs:325-331) has a
   dedicated case only for `SelectionExpandedForSharedPath` and falls through with
   `warningText other = T.pack (show other)` (line 331). `CrossApplicationLastWriter` (defined at
   `seihou-cli/src/Seihou/CLI/Update/Types.hs:157`, built at
   `seihou-cli/src/Seihou/CLI/Update.hs:351-352,538`) therefore prints constructor and record syntax:
   `CrossApplicationLastWriter "agents/skills/exec-plan/ADR.md" (ModuleName {unModuleName = "exec-plan"}) (ModuleName {unModuleName = "exec-plan#bfa0a336"})`.
   This appears on the no-target "safe" path too, so even the remedy that works greets the user with a
   wall of internal representation.

## Why this is a bug, not an improvement request

Targeted `seihou update <target>` is behavior seihou already provides and documents. IR-8/plan-90
shipped `additiveOnly` specifically to make it work on co-owned additive paths; it does work on a
freshly-written manifest and does not on an upgraded one. A provided capability that holds in the fresh
case and fails in the ordinary upgrade case is a defect in that capability, which is why this is filed
as a bug rather than a fresh improvement request. The remaining design asks — a targeted backfill,
reordered/de-hashed guidance, a narrowed `--include-shared-owners`, and a rendered warning — are
tracked separately as improvement requests against the same gate; this report records the wrong
behavior and its reproduction.

## Related

- IR-8 (`../improvement-requests/exempt-additive-patch-paths-from-shared-ownership-closure.md`) and
  `docs/plans/90-exempt-additive-patch-paths-from-the-shared-ownership-closure.md` — introduced the
  gate, the flag, and the fail-closed-when-absent decode this report is the fallout of.
- Masterplan 8 (`docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md`) and plans
  66/68/69 — establish the ownership closure and the "never silently broaden a bare selection" rule.

## Resolution

Fixed after 0.9.0.0 by
`mori://shinzui/seihou/masterplans/11-make-manifest-evolution-explicit-and-targeted-updates-upgrade-safe`
(plans 92 to 95). Each of the four defects above was addressed:

1. **Targeted backfill.** Manifest schema 7 makes the answer explicit per file as
   `sharedWriteMode`. A schema-6 manifest's paths start `unknown`. `seihou update
   nix-haskell-flake` certifies an unknown shared path inside its own plan by compiling each
   co-owner from its recorded version and reading how it writes the path. It then publishes
   the 6 -> 7 step and the certified mode with the update's manifest. The co-owners are
   inspected, not updated. The dry run shows `Manifest: schema 6 -> 7` and
   `.gitignore evidence unknown -> additive-only` and writes nothing.
2. **`--include-shared-owners`** is offered only for a path proven
   `requires-ownership-closure`. If evidence is missing (the co-owner's recorded version is
   not installed), the update fails with `shared_write_evidence_unavailable`, names the owner
   and the reason, and does not offer expansion.
3. **Guidance** leads with the repair, and owners are named the way `seihou status` names
   them (`exec-plan [skill.name=exec-plan]`), never by application id.
4. **`CrossApplicationLastWriter`** now reads as ownership-attribution prose. Every warning
   and error renderer is exhaustive, with no `show` fallback.

The regression fixture in `seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs` runs the built
binary against a schema-6 manifest whose `.gitignore` is co-owned by an appending
application with a newer release. The targeted dry run writes nothing. The apply updates only
the target and leaves the co-owner's files and installed module byte-identical. It records
schema 7 and `additive-only`, and the retry is already up to date.
