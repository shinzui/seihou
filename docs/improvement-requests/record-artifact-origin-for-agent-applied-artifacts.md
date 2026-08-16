---
type: Improvement Request
title: Record artifact origin for agent-applied artifacts
description: >-
  Give AppliedBlueprint, AppliedBlueprintMigration, and AppliedRecipe the same ArtifactOrigin the
  module records already carry, so manifest provenance for agent-run artifacts is an identity ADR
  0002 accepts rather than the bare name it explicitly rejects.
generated:
  by: process:claude-code
  at: "2026-08-06T17:12:58Z"
timestamp: 2026-08-16T00:00:00Z
requestId: IR-2
status: completed
completedAt: "2026-08-16T00:00:00Z"
targetPlan: docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md
resolution: >-
  All three requested changes landed. AppliedBlueprint, AppliedBlueprintMigration, and
  AppliedRecipe carry origin :: !ArtifactOrigin under the JSON key origin; the blueprint migration
  completion key in pendingBlueprintMigrations, writeAppliedBlueprintMigration, and
  hasAppliedBlueprintMigration all include it; and a record with no origin decodes as LocalOrigin
  of its recorded name, so currentManifestVersion stays at 6 and no conversion command is needed.
  The shared "same artifact" comparison had to move into seihou-core as
  Seihou.Core.ArtifactIdentity, because two of the three key comparisons live there and cannot
  import from seihou-cli.
origin: mori://shinzui/okf-profiles
---

# Improvement Request: Record Artifact Origin for Agent-Applied Artifacts

## Status

Implemented in `docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md`, under
`docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md`. See Resolution
below.

## Context

[ADR 0002](../adr/0002-artifact-identity-is-origin-url-plus-name.md) settles what the manifest
records to identify an artifact, and rejects the bare name in terms that name this exact risk:

> Recording only `"haskell-base"` is not an identity. Two registries can both publish a module
> called `haskell-base`, and a manifest keyed on name alone cannot tell a developer that the copy
> they have installed is a different module from the one the project was generated with. Silently
> generating from the wrong module is exactly the class of failure this design exists to prevent.

The module-side records honour that decision. In `seihou-core/src/Seihou/Core/Types.hs`:

- `AppliedModule` carries `origin :: !ArtifactOrigin`
- `AppliedComposition` carries `targetOrigin :: !ArtifactOrigin`

## Problem

The three records written on the agent and recipe paths carry a bare `name` and no origin:

| Record | Fields |
|---|---|
| `AppliedBlueprint` | `name`, `blueprintVersion`, `appliedAt`, `baselineModules`, `noBaseline`, `userPrompt`, `agentSessionId` |
| `AppliedBlueprintMigration` | `name`, `blueprintVersion`, `fromVersion`, `toVersion`, `appliedAt`, `agentSessionId` |
| `AppliedRecipe` | `name`, `recipeVersion`, `appliedAt` |

Their JSON encodings match — `instance ToJSON AppliedBlueprint` emits `name`, `appliedAt`,
`baselineModules`, `noBaseline`, and optional `version`, `userPrompt`, `agentSessionId`. There is
no field in which an origin could be written.

The collision this permits is not hypothetical, because the install cache is keyed by bare name
too: `installModuleDir` writes to `~/.config/seihou/installed/<name>` and replaces whatever was
there (see [IR-4](refuse-to-overwrite-an-installation-from-a-different-source.md)). Two registries
publishing a blueprint called `adopt-architecture-decisions` therefore contend for one directory
and one manifest identity.

The sharp edge is the migration skip decision. `pendingBlueprintMigrations`
(`seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`) drops an edge when a receipt matches on three
fields and no more:

```haskell
receipt ^. #name == blueprintName
  && receipt ^. #fromVersion == migration ^. #from
  && receipt ^. #toVersion == migration ^. #to
```

Its comment states the exclusions deliberately — "Artifact versions and timestamps are
intentionally not part of the completion key" — which is right, because an edge is the same edge
across artifact versions. Origin is a different case and is absent rather than excluded by
argument: two blueprints from different repositories that share a name and an edge window are not
the same edge, but their receipts are indistinguishable.

So a project that ran `0.7.0 -> 0.8.0` under one repository's blueprint, and later resolves that
name to a different repository's blueprint, has that second blueprint's `0.7.0 -> 0.8.0` edge
dropped from the plan. Nothing prints, because suppressing recorded edges is the feature. The user
sees a normal `no pending migrations` outcome for work that never ran.

`AppliedBlueprint` degrades more gently — a substituted blueprint at least appears in
`seihou status` — but it is the same defect, and `AppliedRecipe` has it with none of the agent
path's human-in-the-loop mitigation.

## Why the existing mechanisms do not cover it

- **`ArtifactOrigin` already exists** and already models the three provenance strengths, so this is
  not a design question. The type is simply not reached from these three records.
- **`seihou status`** renders a `Blueprint:` provenance block (`StatusRender.hs`), but it can only
  show the name it was given.
- **`--rerun`** recovers a falsely-skipped migration, exactly as it does for
  [IR-1](add-a-not-applicable-outcome-for-blueprint-migration-edges.md) — and with the same
  objection: it is a remedy only for someone who already suspects the receipt is wrong. Here there
  is even less to go on, because a name collision leaves no trace in the manifest at all.
- **Version fields** do not disambiguate. Two unrelated blueprints can both be at `0.8.0`.

## Requested change

Give the three records an origin field of the same `ArtifactOrigin` type the module records use,
resolved the same way at write time, and make the migration completion key include it.

Specifically:

1. Add `origin :: !ArtifactOrigin` to `AppliedBlueprint`, `AppliedBlueprintMigration`, and
   `AppliedRecipe`, with the JSON key `origin` to match `AppliedModule`.
2. Extend `alreadyApplied` in `pendingBlueprintMigrations` to compare origin alongside name,
   `fromVersion`, and `toVersion`, and update the comment to say that origin *is* part of the
   completion key while versions and timestamps deliberately are not.
3. Decode a receipt with no `origin` as the weak case rather than failing. Existing manifests
   were written before the field existed and their artifacts cannot be identified retroactively;
   treating them as unverifiable provenance is the honest reading, and matches how ADR 0002 treats
   `LocalOrigin`.

Point 3 is what keeps this out of a manifest schema bump. If a bump is preferred anyway, the
migration is mechanical, since the origin of an already-recorded artifact is not recoverable and
every legacy entry takes the same value.

## Scope

Manifest records and the migration completion key. Acting on a detected mismatch is
[IR-3](guard-the-agent-path-against-stale-and-substituted-artifacts.md); this request only makes
the mismatch representable, which IR-3 depends on. Preventing the collision upstream is
[IR-4](refuse-to-overwrite-an-installation-from-a-different-source.md).

## Related

- [IR-1](add-a-not-applicable-outcome-for-blueprint-migration-edges.md) — the same subsystem, and
  the same underlying shape: a receipt that asserts more than seihou actually knows. IR-1 is about
  an outcome the receipt cannot express; this is about an identity it does not carry.
- [ADR 0002](../adr/0002-artifact-identity-is-origin-url-plus-name.md) — the decision this brings
  the agent path into line with.

## Resolution

All three requested changes landed as specified.

`AppliedBlueprint`, `AppliedBlueprintMigration`, and `AppliedRecipe` in
`seihou-core/src/Seihou/Core/Types.hs` each carry `origin :: !ArtifactOrigin`, encoded under the
JSON key `origin` to match `AppliedModule`. There were four write sites rather than the three the
request implies: `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`,
`seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`, `seihou-cli/src-exe/Seihou/CLI/Run.hs`, and
`seihou-cli/src/Seihou/CLI/Update.hs`, which rebuilds the recipe record when `seihou update`
republishes the manifest.

`pendingBlueprintMigrations` takes the invoked blueprint's origin and compares it, and its Haddock
now states the whole key and both exclusions. The two ledger helpers in
`seihou-core/src/Seihou/Manifest/Types.hs` — `writeAppliedBlueprintMigration`'s `sameEdge` and
`hasAppliedBlueprintMigration` — were extended to match, so a receipt cannot be written as a new
entry while being read as a duplicate.

Point 3 was taken as written: a record with no `origin` decodes as `LocalOrigin` of its recorded
name, and `currentManifestVersion` stays at 6. No schema bump, and
[ADR 0005](../adr/0005-legacy-manifests-convert-through-an-explicit-command.md) is not engaged,
because the conversion would lose nothing — the origin of an already-recorded artifact is not
recoverable, so an explicit command could only write the same weak value the decoder supplies.

One thing the request did not anticipate: the comparison could not live only in
`seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`, because two of the three places that need it
are in `seihou-core` and cannot import from `seihou-cli`. It is now
`Seihou.Core.ArtifactIdentity.sameArtifactIdentity`, which also absorbs the git-URL and
project-path normalisers that were private to `Seihou.CLI.ManifestGuard`. That module's three-way
`judgeArtifact` verdict is unchanged and stays where it was: "cannot be proved either way" is a
meaningful answer for the pre-generation guard and no answer at all for a receipt lookup.
