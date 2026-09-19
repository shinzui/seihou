---
id: 100
slug: record-seed-receipts-in-manifest-schema-8
title: "Record seed receipts in manifest schema 8"
kind: exec-plan
created_at: 2026-09-19T13:59:13Z
intention: "intention_01m2wz5ww3ezmvpf0aenfbgcjx"
master_plan: "docs/masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md"
provenance:
  created_by:
    model: "claude-opus-5[1m]"
    harness: "claude-code"
    at: 2026-09-19T13:59:13Z
---

# Record seed receipts in manifest schema 8

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

This plan is EP-2 of the MasterPlan
`docs/masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md`.
It has no hard dependencies. It lists
`docs/plans/99-declare-seed-steps-in-the-module-schema-and-validate-them.md` (EP-1) as a soft
dependency only because EP-1 writes the ADR that names the concept; everything this plan
needs from it is restated below.


## Purpose / Big Picture

Seihou is gaining *seed files*: files a module creates once, when the path is absent, and
then hands to the project. Seihou never overwrites, content-tracks, merges into, reports, or
deletes a seed file. Even so, the project's record of what Seihou did —
`.seihou/manifest.json`, the committed *manifest* — must say that a path was seeded, by which
module, and how. Without that record Seihou cannot tell a seed the developer deliberately
deleted from a path that was never seeded, `seihou remove` cannot say which files it is leaving
behind, and `seihou update` cannot convert a previously managed file into a seed exactly once.

This plan adds that record, the *seed receipt*, as a new top-level `seeds` map in the manifest.
Because this changes what the manifest can say, the manifest schema advances from version 7
to version 8, with one lossless upgrade step. A seed receipt deliberately has **no content
hash and no baseline**: those are what make a file "tracked".

After this plan, a developer can run `seihou manifest upgrade` on any project and see a new
step `7 -> 8  seed receipts  (lossless)`, after which the manifest's `version` is 8 and it
contains `"seeds": {}`. Every existing command keeps working on schema 7 and 8 manifests.
Nothing yet writes a non-empty `seeds` map; `docs/plans/101-create-seed-files-once-during-seihou-run.md`
(EP-3) is the first producer.


## Progress

- [ ] Milestone 1: `SeedOutcome`, `SeedRecord`, and `Manifest.seeds` in `Seihou.Core.Types`;
      every `Manifest` construction updated.
- [ ] Milestone 1: `Seihou.Core.Seed` helpers `mergeSeedRecord`, `dropSeedOwner`,
      `validateManifestInvariants`; unit tests.
- [ ] Milestone 2: JSON codec for `seeds`, version-selected; `currentManifestVersion = 8`;
      decoder invariant; round-trip and rejection tests.
- [ ] Milestone 2: upgrade step 7 → 8 (`AddEmptySeedReceipts`, lossless); capability
      `SeedReceipts`; upgrade-registry tests.
- [ ] Milestone 3: machine-independence test extended; `docs/cli/manifest.md`,
      `docs/user/manifest-upgrade.md`, design-doc version history; ADR 0014 implementation
      note; ADR 0017 amendment; root `CHANGELOG.md`.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Store seed receipts in a separate top-level `seeds` map keyed by project-relative
  path, not as a variant of `FileRecord` inside `files`.
  Rationale: Dozens of call sites iterate `Manifest.files` assuming every entry has a hash and
  can be compared with disk (status, diff, update reconciliation, baselines, shared-write
  certification). A separate map keeps every one of them correct without edits, and makes
  "not tracked" structural rather than a flag each consumer must remember to check.
  Date: 2026-09-19

- Decision: `seeds` is required at schema 8 and the 7 → 8 step inserts an empty object; it
  is not an optional key.
  Rationale: ADR 0014 forbids an absent field meaning both a domain value and "this manifest
  predates the question". At schema 7 no writer could seed, so absence genuinely means "no
  seeds"; at schema 8 the key is always written.
  Date: 2026-09-19

- Decision: `SeedOutcome` has three values: `created`, `found-existing`,
  `released-from-managed`.
  Rationale: They are the three ways a path becomes a seed (Seihou wrote it; a file was
  already there; a module release converted a managed file). `seihou status` and
  `seihou remove` can report them, and they cost nothing to record.
  Date: 2026-09-19

- Decision: A path may appear in `files` or in `seeds`, never both; decoding a manifest that
  violates this fails.
  Rationale: Mixed state has no coherent meaning (is the path tracked or not?). Checking it at
  the decoding boundary means no command ever runs on such a manifest.
  Date: 2026-09-19


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The repository is a Haskell (GHC 9.12, `GHC2024`) Cabal workspace: `seihou-core/` holds the
domain library and `seihou-cli/` the command-line tool. Read the repository `CLAUDE.md`
first: records use strict fields and an explicit `deriving stock (…, Generic)`, fields are
read and written only through `generic-lens` labels (`m ^. #files`, `m & #seeds .~ x`,
`m & #seeds . at path ?~ r`), never with record dot or record update syntax, and each module
using labels imports `Data.Generics.Labels ()` itself.

**The manifest.** `.seihou/manifest.json` is committed to the user's repository and records
everything Seihou applied. Its Haskell type is `Seihou.Core.Types.Manifest`
(`seihou-core/src/Seihou/Core/Types.hs`, around line 529), with fields `version`, `genAt`,
`modules`, `vars`, `files :: Map FilePath FileRecord`, `applications`, `recipe`, `blueprint`,
`blueprintMigrations`. A `FileRecord` (around line 826) describes one *managed* file:
`hash` (SHA-256 of the applied content), `moduleName`, `strategy`, `generatedAt`,
`baseline` (a reference to the generated bytes stored under `.seihou/baselines/`),
`applicationIds :: Set ApplicationId`, and `sharedWriteMode`. An *application*
(`ApplicationId`, a newtype over `Text`, around line 614) identifies one recorded invocation
of `seihou run` for a module or recipe; `Manifest.applications` lists them.

**The codec.** `seihou-core/src/Seihou/Manifest/Types.hs` holds the JSON instances.
`currentManifestVersion` (around line 73) is `ManifestSchemaVersion 7`;
`oldestDecodableManifestVersion` is 6. `minimumManifestVersion :: ManifestCapability -> ManifestSchemaVersion`
(around line 85) is the single place a feature states which schema it needs, and
`manifestSupports` asks it. `ManifestCapability` (in `Core/Types.hs`, around line 558) today
has one constructor, `TargetedAdditiveSharedPathUpdate`. `instance ToJSON Manifest` (around
line 196) writes `files` through `filesToJSON (m ^. #version)`, i.e. the representation
depends on the document's version; `instance FromJSON Manifest` (around line 212) reads the
version first, calls `checkManifestVersion`, then decodes version-selected fields. A decoded
manifest keeps the version it was read at, and encoding writes that version's
representation — so a schema-7 manifest re-encoded stays schema 7. A producer that asserts
schema-8 facts must set `version` to 8 (for example `seihou run` sets `currentManifestVersion`
on the manifest it writes).

**Upgrade steps.** `seihou-core/src/Seihou/Manifest/Upgrade.hs` defines
`UpgradeStepAction` (`StampVersion | ConvertMachineLocalPaths | MakeSharedWriteEvidenceExplicit`),
`upgradeStepKind` (lossless or inference-bearing), the ordered table `manifestUpgradeSteps`
(one entry per adjacent version, currently 1→2 … 6→7), `applyLosslessUpgradeStep`, which
transforms a raw `Aeson.Value` document and then stamps the new version, and
`upgradeDocumentLosslessly`, which commands use to stage a minimum schema in memory.
`makeSharedWriteEvidenceExplicit` is the 6→7 transform and the model for a new transform.
`seihou manifest upgrade` (`seihou-cli/src/Seihou/CLI/ManifestUpgrade.hs`,
`runManifestUpgrade` around line 661) walks the table and prints each step with its summary
and kind; it needs no change beyond what the table drives, but check its rendering for any
exhaustive match on `UpgradeStepAction`.

**Tests.** `seihou-core/test/Seihou/Manifest/TypesSpec.hs` (round trips, version rejection,
and `describe "machine independence"`, which encodes a manifest populated in every string
position and fails if any string looks machine-specific — see
`manifestWithEveryStringPosition`), `seihou-core/test/Seihou/Manifest/UpgradeSpec.hs` (plans a
path from every supported version to current, so a missing step fails; `describe "the 6 -> 7 step"`
is the model for a new step's tests). Run with `cabal test seihou-core-test`.
`seihou-cli/test/Seihou/CLI/ManifestUpgradeSpec.hs` covers the command's report.

**ADRs.** [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md)
is the contract this plan follows: a semantic manifest change advances the version and ships,
in the same change, a version-selected decoder, exactly one adjacent upgrade step classified
lossless or inference-bearing, tests for the old representation, the transformed one, and
rejection of malformed input, and a version-history and user-documentation entry; features
declare their minimum schema only through `minimumManifestVersion`.
[ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md) requires every
location in the manifest to be project-relative (seed paths are); its machine-independence
test must cover the new field. [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md)
is why receipts live in the manifest. ADR 0017
(`docs/adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md`, created by EP-1)
defines seed files; if EP-1 has not landed yet, create no ADR here and instead add the
amendment text below to EP-1's plan so it is included when the ADR is written.


## Plan of Work

### Milestone 1 — types and pure helpers

Scope: the in-memory manifest can hold seed receipts, and there is one tested place that
adds, removes, and checks them. At the end, the code compiles with an always-empty `seeds`
map everywhere a `Manifest` is built, and helper tests pass.

In `seihou-core/src/Seihou/Core/Types.hs`, after `FileRecord`, add:

```haskell
-- | How a seed path was settled. A seed is a file a module creates once and
-- hands to the project; see
-- docs/adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md.
data SeedOutcome
  = -- | Seihou wrote the file because the path was absent.
    SeedCreated
  | -- | A file already existed at the path; Seihou left it untouched.
    SeedFoundExisting
  | -- | A module release turned a managed file into a seed; Seihou dropped
    -- its content record and baseline and left the bytes as they were.
    SeedReleasedFromManaged
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)

-- | The manifest's receipt for a seed path. It deliberately carries no
-- content hash or baseline: a seed file is not tracked.
data SeedRecord = SeedRecord
  { moduleName :: !ModuleName,
    applicationIds :: !(Set ApplicationId),
    outcome :: !SeedOutcome,
    settledAt :: !UTCTime
  }
  deriving stock (Eq, Show, Generic)
```

Add `seeds :: !(Map FilePath SeedRecord)` to `Manifest` immediately after `files`, and add
`SeedReceipts` to `ManifestCapability` with a haddock ("Seed receipts under the top-level
`seeds` key; required by every command that writes one"). Export the new types. Fix every
`Manifest { … }` construction the compiler reports (`emptyManifest`, test fixtures,
`seihou-cli` builders) by adding `seeds = Map.empty`.

Create `seihou-core/src/Seihou/Core/Seed.hs` (add it to `exposed-modules` in
`seihou-core/seihou-core.cabal`) with:

```haskell
-- | Record that an application's module seeds a path. When a receipt
-- already exists the application joins its owners and the original
-- outcome and time are kept, because the first settlement is the fact.
mergeSeedRecord :: FilePath -> SeedRecord -> Manifest -> Manifest

-- | Remove applications from a path's receipt; delete the receipt when no
-- owner remains. Never touches disk.
dropSeedOwner :: Set ApplicationId -> FilePath -> Manifest -> Manifest

-- | Receipts owned by a module name (for `seihou remove`, which works by
-- module rather than application).
seedsOwnedByModule :: ModuleName -> Manifest -> Map FilePath SeedRecord

data ManifestInvariantError
  = PathBothManagedAndSeeded FilePath
  deriving stock (Eq, Show, Generic)

-- | A path is either tracked (`files`) or seeded (`seeds`), never both.
validateManifestInvariants :: Manifest -> Either ManifestInvariantError ()
```

`mergeSeedRecord` must refuse nothing itself (callers decide); it only merges. Document in
its haddock that callers must not create a receipt for a path present in `files` and should
check `validateManifestInvariants` on the final manifest before writing. Add
`seihou-core/test/Seihou/Core/SeedSpec.hs` (register it in the cabal file's test
`other-modules` and in `seihou-core/test/Main.hs`) covering: merging into an empty map,
merging a second application keeps the first outcome and time, dropping the last owner
deletes the receipt, dropping one of two owners keeps it, and the invariant rejects a path in
both maps.

Acceptance: `cabal build all` and `cabal test seihou-core-test` pass.

### Milestone 2 — codec, schema 8, and the upgrade step

Scope: the manifest file carries `seeds` at schema 8; older schemas upgrade losslessly. At the
end, a schema-8 manifest round-trips, a schema-7 manifest still decodes with an empty
`seeds`, and `seihou manifest upgrade` offers the 7 → 8 step.

In `seihou-core/src/Seihou/Manifest/Types.hs`: set `currentManifestVersion = ManifestSchemaVersion 8`;
add `minimumManifestVersion SeedReceipts = ManifestSchemaVersion 8`. Add
`seedOutcomeToText`/`seedOutcomeFromText` (`created`, `found-existing`,
`released-from-managed`), `seedsToJSON`, and `seedsFromJSON`. A receipt serializes as:

```json
"seeds": {
  "CHANGELOG.md": {
    "module": "haskell-cli-app",
    "applications": ["<application id>"],
    "outcome": "created",
    "settledAt": "2026-09-19T14:00:00Z"
  }
}
```

(use the same key names and `ApplicationId` encoding that `fileRecordToJSON` uses for
`module` and `applications`; sort `applications` as `fileRecordToJSON` does so the encoding
is stable). In `ToJSON Manifest`, emit `"seeds"` only when `version >= 8` — at version 7 the
field cannot be expressed; if a caller tries to encode a version-7 manifest with a non-empty
`seeds`, that is a programming error, so make the encoder total but add a test-visible pure
function `manifestEncodingLoss :: Manifest -> [Text]` that reports it, and use it in the
tests (do not throw from `toJSON`). In `FromJSON Manifest`, read `seeds` with `.:` (required)
when `v >= 8` and default to `Map.empty` when `v == 7` or `v == 6`; after constructing the
value, run `validateManifestInvariants` and `fail` with
`"path <p> is recorded both as a tracked file and as a seed"` on violation. Reject an unknown
`outcome` text with a message listing the three accepted values.

In `seihou-core/src/Seihou/Manifest/Upgrade.hs`: add the action `AddEmptySeedReceipts`
(haddock: "Schema 7 to 8: add an empty top-level `seeds` object; no schema-7 writer could
seed a path, so absence meant none"), classify it `LosslessUpgrade`, implement
`addEmptySeedReceipts :: Aeson.Value -> Either Text Aeson.Value` (insert `"seeds": {}` when
absent, fail if a `seeds` key exists and is not an object, keep every other member), wire it
into `applyLosslessUpgradeStep`, and append `step 7 AddEmptySeedReceipts "seed receipts"` to
`manifestUpgradeSteps`. Fix any exhaustive matches the compiler reports (for example in
`seihou-cli/src/Seihou/CLI/ManifestUpgrade.hs`).

Tests: in `UpgradeSpec.hs`, extend the registry-kind test to assert 7 → 8 is lossless and add
`describe "the 7 -> 8 step"` mirroring the 6 → 7 block: adds `seeds: {}`, keeps unrelated
members, stamps version 8, produces a document the typed decoder reads and round-trips,
rejects a non-object `seeds`, refuses a document at another version. In `TypesSpec.hs`: a
schema-8 manifest with two receipts (one with two applications) round-trips; a schema-7
document without `seeds` decodes to an empty map; a schema-8 document without `seeds` is
rejected; an unknown outcome is rejected; a path in both `files` and `seeds` is rejected with
the message above; `manifestEncodingLoss` reports a version-7 manifest with receipts.
Existing tests that assert `currentManifestVersion` is 7 or that the path ends at 7 must be
updated to 8 — search for `ManifestSchemaVersion 7` in both test suites and judge each one
(some deliberately test schema 7 and must stay).

Also search `seihou-cli` for places that compare against the current version or render
"schema 7" in user text (`grep -rn 'schema 7\|ManifestSchemaVersion 7' seihou-cli`) and
update wording that means "current".

Acceptance: `cabal test all` passes; the upgrade-registry test proves a contiguous path from
every supported version to 8.

### Milestone 3 — machine independence, documentation, ADRs

Scope: the new field is covered by the project's standing invariants and documented.

Extend `manifestWithEveryStringPosition` in `TypesSpec.hs` with a seed receipt so the
machine-independence walk covers `seeds` (the path key, module, application, outcome).

Documentation: in `docs/cli/manifest.md`, add the row
`| 7 -> 8 | Adds an empty top-level seeds object for seed receipts. | lossless |` to the
step table and change "(7)" in the `--to VERSION` option description to "(8)". In
`docs/user/manifest-upgrade.md`, update the sample report's final line to schema version 8
and add one short paragraph explaining that schema 8 records seed receipts (define a seed file
in one sentence). In `docs/dev/design/proposed/manifest-and-incrementality.md`, add schema 8 to
the version history next to the schema 7 text (around its line 130). In ADR 0014's
"Implementation" section, add a short dated bullet naming this plan and the 7 → 8 step as a
lossless example of the rule. Amend ADR 0017 (created by EP-1) with a dated paragraph: seed
receipts live in the manifest's `seeds` map from schema 8; they record module, applications,
outcome, and time but no hash or baseline, which is exactly what "not tracked" means; a path
is in `files` or `seeds`, never both. Add an entry under `## [Unreleased]` in the root
`CHANGELOG.md`.

Acceptance: `nix flake check` passes; the documents describe schema 8.


## Concrete Steps

From the repository root, `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`, in the Nix
dev shell:

```bash
cabal build all
cabal test seihou-core-test
cabal test seihou-cli-test
nix flake check
```

Manual demonstration on a scratch project that has a schema-7 manifest (any project where
`seihou run` was used with the previous build; or copy one):

```bash
cd "$TMPDIR" && rm -rf seed-manifest-demo && mkdir seed-manifest-demo && cd seed-manifest-demo
git init -q
# create any small module run with the *previous* seihou build, or copy a schema-7
# .seihou/manifest.json from an existing project into .seihou/
cabal run -v0 --project-dir /Users/shinzui/Keikaku/bokuno/seihou-project/seihou seihou -- manifest upgrade --dry-run
```

Expected transcript excerpt:

```text
Reading .seihou/manifest.json (schema version 7)

  7 -> 8  seed receipts
```

and after running without `--dry-run`, `jq '.version, .seeds' .seihou/manifest.json` prints
`8` and `{}`.


## Validation and Acceptance

The new `SeedSpec`, `TypesSpec`, and `UpgradeSpec` cases fail before this plan and pass after.
All existing tests pass once their expectations about the *current* version are moved to 8.
`seihou manifest upgrade` on a schema-7 project reports the 7 → 8 step as lossless and writes
`"seeds": {}` with `"version": 8`; `seihou status` and `seihou update --dry-run` still work on
both a schema-7 and a schema-8 manifest.


## Idempotence and Recovery

All changes are code and documentation. `seihou manifest upgrade` on a schema-8 manifest is a
no-op. A developer who upgraded a project's manifest to 8 and then runs an older Seihou build
gets that build's standard "manifest was created by a newer version of seihou" error; the fix
is to use the newer build (there is no downgrade step, consistent with ADR 0014).


## Interfaces and Dependencies

At the end of this plan these exist, and later plans must use them rather than re-deriving
them:

- `Seihou.Core.Types.SeedOutcome` (`SeedCreated | SeedFoundExisting | SeedReleasedFromManaged`),
  `Seihou.Core.Types.SeedRecord` (`moduleName`, `applicationIds`, `outcome`, `settledAt`),
  `Manifest.seeds :: Map FilePath SeedRecord`, and the capability constructor `SeedReceipts`.
- `Seihou.Core.Seed.mergeSeedRecord`, `dropSeedOwner`, `seedsOwnedByModule`,
  `validateManifestInvariants`, `ManifestInvariantError`.
- `Seihou.Manifest.Types.currentManifestVersion == ManifestSchemaVersion 8`,
  `minimumManifestVersion SeedReceipts == ManifestSchemaVersion 8`, `seedOutcomeToText`,
  `seedOutcomeFromText`, `manifestEncodingLoss`.
- `Seihou.Manifest.Upgrade.AddEmptySeedReceipts` and the 7 → 8 entry in
  `manifestUpgradeSteps`.

Consumers: `docs/plans/101-create-seed-files-once-during-seihou-run.md` (EP-3) writes
receipts; `docs/plans/102-keep-seed-files-out-of-status-diff-and-remove.md` (EP-4) reads and
drops them; `docs/plans/103-reconcile-seed-steps-during-seihou-update-and-release-managed-files-to-seeds.md`
(EP-5) writes, drops, and stages schema 8 through `SeedReceipts`. No new library dependency.
