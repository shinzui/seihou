---
type: Improvement Request
title: Exempt additive-patch paths from the shared-ownership closure, and offer an opt-in to expand it
description: >-
  Stop a targeted `seihou update` from failing on a shared path that every owner writes with an
  additive, idempotent patch (append-line-if-absent, append-section), where reconciling one owner
  provably cannot corrupt another's contribution; and add an explicit opt-in flag that expands a
  named selection to the full ownership closure for the paths where the requirement still holds.
generated:
  by: process:claude-code
  at: "2026-09-16T00:00:00Z"
timestamp: 2026-09-16T00:00:00Z
requestId: IR-8
status: proposed
origin: mori://shinzui/okf-profiles
---

# Improvement Request: Exempt Additive-Patch Paths from the Shared-Ownership Closure

## Context

`seihou update <target>` selects a subset of the manifest's recorded applications and, before
fetching or mutating anything, requires that the selection be *ownership-closed*: for every managed
path, if any selected application owns it, every application that owns it must also be selected.
`ensureOwnershipClosure` in `seihou-cli/src/Seihou/CLI/Update/Selection.hs` enforces this:

```haskell
ensureOwnershipClosure manifest selected =
  case [ (path, selectedOwners, missingOwners)
       | (path, record) <- Map.toAscList (manifest ^. #files),
         let selectedOwners = Set.intersection selected (record ^. #applicationIds),
         let missingOwners  = (record ^. #applicationIds) Set.\\ selected,
         not (Set.null selectedOwners),
         not (Set.null missingOwners)
       ] of
    (path, selectedOwners, missingOwners) : _ ->
      Left (SharedPathRequiresApplications path selectedOwners missingOwners)
    [] -> Right ()
```

`Seihou.Engine.Reconcile` repeats the same check as defense in depth (`SharedPathRequiresApplications`
at `seihou-core/src/Seihou/Engine/Reconcile.hs`). The design intent, recorded in plans 66/68/69, is
sound: a targeted update must not *silently* regenerate a path that an unselected application also
owns, because that would touch a target the user did not request.

## Problem

**The check treats every co-owned path as a whole-file conflict, but the most common co-owned path
is `.gitignore`, which every owner writes with an additive, idempotent patch.** For those paths the
premise behind the requirement — "reconciling this path on behalf of the selected owner might clobber
the unselected owner's content" — is simply false, so the safety rail fires on a case that is not
unsafe.

Observed 2026-09-16 in `mori://shinzui/pgmq-hs` (a Haskell library project). `.gitignore` is co-owned
by two applications:

- `nix-haskell-flake` — contributes its line group via `patch = Some "append-line-if-absent"`
- `master-plan` — contributes its own distinct lines the same additive way

Running `seihou update nix-haskell-flake` fails with:

```
Update failed [shared_path_requires_applications]: Path .gitignore is also owned by
application(s) <master-plan>. Select every owner or run seihou update with no targets.
```

`append-line-if-absent` appends only lines not already present, and `append-section` writes a
distinct tagged region. Two owners using these strategies occupy disjoint, order-independent slices
of the file; reconciling one owner's slice cannot alter the other's. Yet the user is forced to either
name every unrelated co-owner or update the whole project, every time they touch one module that
happens to append to `.gitignore` — which in practice is nearly every module. The rail meant for
whole-file collisions is paid on the one file the ecosystem deliberately shares.

## Requested change

### 1. Exempt non-overlapping additive-patch paths from the closure requirement

Relax `ensureOwnershipClosure` (and the mirrored `Reconcile` check) so a co-owned path is *not* a
closure violation when **every** owner — selected and unselected alike — contributes to it through an
additive, non-overlapping patch strategy: `AppendLineIfAbsent`, and `AppendSection` (each owner's
section is delimited by its own markers). `AppendFile` / `PrependFile` are ordering-sensitive and
should stay under the requirement, as should any whole-file strategy (`Copy`, `Template`, `DhallText`,
`Structured`) and `replace-section`. The exemption is deliberately narrow: it covers only the write
modes whose composition is provably commutative and idempotent.

When the exemption applies, a targeted update reconciles **only the selected owners' contribution** to
the path and leaves every unselected owner's lines/section untouched on disk — which is exactly what
the additive strategies already guarantee at materialization time.

**Feasibility note — this is the real cost of option 1.** The manifest does *not* currently carry
enough information to make this decision from the `FileRecord` alone. `FileRecord`
(`seihou-core/src/Seihou/Core/Types.hs`) records a single `strategy :: Strategy` and a single
`moduleName :: ModuleName` per path, and no `PatchOp` at all — so the `.gitignore` record in the
observed project reads `strategy = template, module = nix-haskell-flake` even though both owners
reached it via `append-line-if-absent`. Implementing the exemption therefore requires one of:

- **(a)** persist per-application write mode for each managed path — extend `FileRecord` to record,
  per `ApplicationId`, the `PatchOp` (or its absence) that owner used for the path — so the closure
  check can read it directly and defense-in-depth in `Reconcile` stays a pure function of the
  manifest; or
- **(b)** resolve the owning modules' current step definitions at update time and inspect the `patch`
  field of the step whose `dest` is the path, for both selected and unselected owners. This avoids a
  manifest change but makes the check depend on re-resolving unselected owners' modules, and it reads
  the *current* definition rather than what was applied.

Option (a) is the cleaner and more honest basis and is preferred; it is a manifest schema addition,
so it should decode an older record (missing the per-owner mode) as "unknown," and a path with any
unknown-mode owner must fall back to requiring closure — fail closed, never open.

### 2. Add an explicit opt-in that expands a named selection to its ownership closure

For the paths where the closure requirement legitimately still holds (whole-file and ordering-
sensitive strategies), give the user a way to say "yes, also update the co-owners" without having to
hand-type every one and without falling back to a whole-project `seihou update`. Add a flag —
`seihou update <target> --include-shared-owners` (name is an author's call) — that expands the
selection to the ownership closure of the requested targets before running, updating exactly the
co-owners that the requirement names and nothing more.

This preserves the plan 66/68/69 principle that a *bare* named selection is never silently broadened:
the expansion happens only under an explicit flag. The error message for the un-flagged case should
name the flag alongside the existing "select every owner / run with no targets" guidance, so the
recovery path is discoverable at the moment it is needed.

## Scope

- `ensureOwnershipClosure` in `seihou-cli/src/Seihou/CLI/Update/Selection.hs` — the primary gate, and
  the site of the `--include-shared-owners` expansion.
- The mirrored `SharedPathRequiresApplications` check in `seihou-core/src/Seihou/Engine/Reconcile.hs`
  — must apply the same exemption, or defense-in-depth will reject what the CLI gate allowed.
- `FileRecord` in `seihou-core/src/Seihou/Core/Types.hs` and its manifest codec, if option (a) is
  taken; with a decode-old-as-unknown, fail-closed fallback.
- The error rendering in `seihou-cli/src/Seihou/CLI/Update/Render.hs` (`SharedPathRequiresApplications`)
  — mention the new flag.

This request does not touch how additive patches are materialized, the "never silently broaden a bare
selection" rule, or any provenance guarantee. Part 1 narrows a preflight to the cases where it is
actually protecting something; part 2 adds an explicit, opt-in convenience for the cases where it
still is.

## Related

Same preflight introduced by plans 66 (`docs/plans/66-plan-conflict-aware-file-reconciliation-and-safe-orphan-handling.md`),
68, and 69, and masterplan 8 (`docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md`).
Those documents establish the "do not silently broaden a named selection" principle that part 2 is
careful to keep; part 1 refines the conflict definition those plans encode so that an idempotent,
commutative co-write is no longer classified as a conflict.
