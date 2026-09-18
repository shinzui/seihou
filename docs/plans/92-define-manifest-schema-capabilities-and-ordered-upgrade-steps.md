---
id: 92
slug: define-manifest-schema-capabilities-and-ordered-upgrade-steps
title: "Define manifest schema capabilities and ordered upgrade steps"
kind: exec-plan
created_at: 2026-09-17T14:17:05Z
intention: "intention_01m2qvd83ae0yt8e3h7ay430bg"
master_plan: "docs/masterplans/11-make-manifest-evolution-explicit-and-targeted-updates-upgrade-safe.md"
provenance:
  created_by:
    model: "gpt-5.6-sol"
    harness: "codex-cli"
    at: 2026-09-17T14:17:05Z
  revisions:
    - model: "gpt-5.6-sol"
      harness: "codex-cli"
      at: 2026-09-17T15:39:42Z
      mode: "update"
      note: "Linked accepted ADR 0014 and made its schema-evolution rules authoritative"
    - model: "claude-opus-5[1m]"
      harness: "claude-code"
      at: 2026-09-18T03:48:18Z
      mode: "implement"
      note: "Implemented schema 7, capabilities, SharedWriteMode, and ordered upgrade steps"
---

# Define manifest schema capabilities and ordered upgrade steps

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Seihou already writes a numeric schema version into `.seihou/manifest.json`, but the
number did not advance when shared-path safety gained `FileRecord.additiveOnly`. An absent
Boolean therefore means both “this path is not additive-only” and “this manifest predates
the question.” After this plan, schema version 7 represents those states separately and
features ask one shared API for the minimum schema they require.

A developer can observe the result by decoding a schema-6 fixture without an
`additiveOnly` key and seeing an explicit unknown shared-write mode, upgrading that
document to schema 7 and seeing a `sharedWriteMode` key on every file record, and then
round-tripping it without losing the distinction. A schema-7 document that omits the new
key fails validation instead of silently acquiring a default. This plan supplies the
contract used by
`docs/plans/93-upgrade-legacy-path-manifests-and-backfill-additive-facts.md` and
`docs/plans/94-gate-targeted-updates-on-the-minimum-manifest-schema.md`; it does not yet
change the public upgrade or update commands.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1: Define typed manifest schema versions, feature requirements, and explicit shared-write evidence. (2026-09-18) `ManifestSchemaVersion`, `ManifestCapability`, `SharedWriteMode`, `knownSharedWriteMode`, and `mergeSharedWriteMode` in `Seihou.Core.Types`; `minimumManifestVersion` and `manifestSupports` in `Seihou.Manifest.Types`.
- [x] M2: Add version-aware decoding, schema-7 encoding, and ordered pure document upgrades with focused tests. (2026-09-18) `Seihou.Manifest.Upgrade` with the adjacent step table, gap-checked planner, and pure 6-to-7 transform; `Seihou.Manifest.UpgradeSpec` and new `TypesSpec` cases.
- [x] M3: Move every manifest producer to the new contract, verify it against the governing ADRs, and pass the core and repository checks. (2026-09-18) All producers and tests moved; ADR 0012 and ADR 0014 amended; design doc version history added. `cabal test all`: core 1134, okf-extension 51, cli 591, all passing; `nix fmt -- --fail-on-change` and `nix flake check` pass.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Observation: Bumping `currentManifestVersion` to 7 immediately made the existing
  `seihou manifest upgrade` converter treat every schema-6 manifest as a legacy
  absolute-path document, because `readLegacyManifest` compared against current.
  Evidence: `ManifestUpgradeSpec` would have converted schema-6 fixtures. The interim fix
  compares against `oldestDecodableManifestVersion` and, after the path conversion, stamps
  6 and runs the lossless steps to current. EP-93 replaces this interim with the stepwise
  driver.

- Observation: The two no-op checks (`isUpdateNoOp` in `Seihou.CLI.Update` and
  `planLooksUnchanged` in `Seihou.CLI.Update.Render`) compared the desired Boolean with the
  prior record directly, so a partial update of a path whose prior answer could not change
  would have been reported as pending work forever. Both now compare against
  `recordedSharedWriteMode`, the same function the manifest writer uses.

- Observation: With a three-state value a partial run whose own contribution is not
  additive can record a *known* closure requirement, which the Boolean could only express
  as the ambiguous `False`. This is strictly more information and still fails closed.


## Decision Log

Record every decision made while working on the plan.

- Decision: Replace `FileRecord.additiveOnly :: Bool` with a three-state
  `SharedWriteMode` in memory and a required `sharedWriteMode` key in schema 7.
  Rationale: The update gate must distinguish a certified additive path, a path proven to
  require closure, and an older record whose mode has not been established. A Boolean
  plus a missing-key default cannot express all three.
  Date: 2026-09-17

- Decision: Treat schema 6's `additiveOnly: true` as certified additive and every other
  schema-6 representation as unknown.
  Rationale: The version-6 encoder omitted false, so absence cannot prove non-additivity.
  Preserving true evidence is safe; inventing false evidence is not.
  Date: 2026-09-17

- Decision: Make ordered upgrade steps explicit and require contiguous paths.
  Rationale: The current converter sends every version below current through one path and
  stamps the final version. A registry of adjacent steps makes a missing 6-to-7 migration
  an error instead of a silent skip.
  Date: 2026-09-17

- Decision: Keep inference-bearing step implementation out of `seihou-core`.
  Rationale: Core owns schema shapes and pure JSON transforms. Looking at installed
  artifacts and selecting an upstream URL is CLI policy and remains in EP-93.
  Date: 2026-09-17

- Decision: Adopt
  [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md)
  as the governing manifest-evolution contract before implementation begins.
  Rationale: The schema-6 ambiguity came from treating fail-closed decoding as enough
  compatibility. A dedicated decision makes schema bumps, adjacent upgrade steps,
  capability minimums, and mechanical gap checks mandatory for future changes rather
  than leaving them as task-local choices in this plan.
  Date: 2026-09-17

- Decision: A decoded manifest keeps the version it was read at, and the encoder emits the
  representation of `Manifest.version` (schema 6: `additiveOnly: true` only; schema 7:
  required `sharedWriteMode`).
  Rationale: `manifestSupports` must be able to say that a decoded schema-6 file does not
  prove schema-7 facts, and a command that merely rewrites a schema-6 manifest (remove,
  migrate) must not silently claim schema 7. Producers that build a complete manifest
  (`seihou run`, whole update, `writeAppliedBlueprintMigration`) still set
  `currentManifestVersion`, which is lossless because every decoded record carries an
  explicit mode. Encoding a closure requirement at schema 6 omits the key and reads back as
  unknown, the fail-closed direction.
  Date: 2026-09-18

- Decision: Declare adjacent steps 1-to-2 through 4-to-5 as lossless version stamps, 5-to-6
  as the inference-bearing path conversion (declared in core, implemented only by the CLI),
  and 6-to-7 as the lossless shared-write transform. The kind is a total function of the
  step's action.
  Rationale: ADR 0014 requires one adjacent step per version and a gap test from every
  supported version. The fields schemas 2 through 5 added all decode from absence to the
  older reader's default, so stamping is honest; fixing the kind by action means no table
  entry can claim to be lossless while doing inference.
  Date: 2026-09-18

- Decision: Share the partial-write merge rule as `mergeSharedWriteMode` (core types) and
  `recordedSharedWriteMode` (reconcile), used by `attachApplication`,
  `prepareCandidateManifest`, and both no-op checks.
  Rationale: Four call sites previously re-derived the same conjunction; a single function
  keeps the writer and the no-op checks from disagreeing.
  Date: 2026-09-18

- Decision: Records created for a `KeepCurrent` conflict resolution in `seihou run` and
  `seihou agent run` get `SharedWriteUnknown`.
  Rationale: No plan produced those bytes, so neither known mode is proven.
  Date: 2026-09-18


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

Completed 2026-09-18. Schema 7 is current. A schema-6 manifest decodes with
`additiveOnly: true` as `SharedWriteAdditiveOnly` and everything else as
`SharedWriteUnknown`, keeps version 6 in memory, and reports
`manifestSupports TargetedAdditiveSharedPathUpdate == False`. A schema-7 record without
`sharedWriteMode`, or with an unknown value, fails with the record path and key named.
`Seihou.Manifest.Upgrade` plans contiguous paths from every supported version, refuses
gaps, classifies each step, and implements the lossless 6-to-7 transform on raw JSON while
keeping unmodelled keys. Every producer and consumer uses the three-state mode, and the
partial-write rule is shared by one function.

The public commands are unchanged in shape. The only behavioural changes a user can see
are that manifests written by `seihou run` and whole updates now say `"version": 7` with
`sharedWriteMode` on every file, and that `seihou manifest upgrade` on a schema-5 file now
lands on schema 7. The stepwise command, `--to`, and certification are EP-93's.

Durable context was promoted into ADR 0014 (a new Implementation section: where the
mapping and step table live, how steps are classified, and the version-preserving
encoder) and ADR 0012 (the schema-7 form of the partial-write rule). ADR 0005 needed no
change: its wording already matched.


## Context and Orientation

This repository is a Cabal workspace. `seihou-core` owns the manifest domain and JSON
contract; `seihou-cli` owns commands that read, upgrade, and apply it. Run all commands in
this plan from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

`seihou-core/src/Seihou/Core/Types.hs` defines `Manifest` and `FileRecord`. `Manifest`
stores an integer `version`, file records, recorded applications, and applied artifact
state. `FileRecord` currently stores `additiveOnly :: Bool`. The flag means every owner
of that path contributed only an idempotent, non-overlapping patch, so a targeted update
may avoid selecting every owner.

`seihou-core/src/Seihou/Manifest/Types.hs` owns `currentManifestVersion`, JSON instances,
and the version guard. The current version is 6. Its comment explicitly says the schema
was not bumped for `additiveOnly`; the encoder emits the key only when true and the
decoder maps an absent key to false. `checkManifestVersion` rejects versions below 6
because they carry machine-local paths and rejects versions above current. Versions 1
through 5 are converted by the explicit CLI command and must remain rejected by the
ordinary typed decoder.

The producers that can assign or preserve a manifest version are
`writeAppliedBlueprintMigration` in `seihou-core/src/Seihou/Manifest/Types.hs`,
`prepareCandidateManifest` in
`seihou-core/src/Seihou/Engine/UpdateTransaction.hs`, `buildFinalManifest` in
`seihou-cli/src/Seihou/CLI/Update.hs`, and the constructors in
`seihou-cli/src-exe/Seihou/CLI/Run.hs` and
`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`. Search all uses of
`currentManifestVersion` during implementation so no write path is missed. New code in
the CLI belongs under `seihou-cli/src/` unless it imports an executable-only dependency;
that rule is recorded in `CLAUDE.md` and mechanically checked by
`nix/check-cli-module-placement.sh`.

`seihou-core/test/Seihou/Manifest/TypesSpec.hs` has the current version checks and the
`additiveOnly` round-trip tests. `seihou-core/test/Seihou/Core/ApplicationSpec.hs` and
`seihou-core/test/Seihou/Engine/UpdateTransactionSpec.hs` assert how partial writes may
weaken but not strengthen the shared-path answer. Those tests must move to the three-state
vocabulary rather than being deleted.

The motivating behavior is recorded in
`docs/bug-reports/additive-only-gate-breaks-targeted-update-on-preexisting-manifests.md`.
The relevant durable decisions are:

- [ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md)
  requires the manifest to remain machine-independent.
- [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md)
  says schema growth belongs in this file and is handled through versioning and conversion.
- [ADR 0005](../adr/0005-legacy-manifests-convert-through-an-explicit-command.md)
  requires inference-based legacy conversion to remain explicit and lossless.
- [ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md)
  defines the two-layer safety check; its decision not to bump schema 6 is superseded by
  ADR 0014.
- [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md)
  requires every semantic manifest change to advance the version, provide a contiguous
  adjacent upgrade, classify whether that step needs review, and declare feature minimums.

ADR 0012 and ADR 0005 already link to the governing contract. During implementation,
EP-92 must keep their prospective schema-7 language aligned with the code that actually
lands. Mori searches found no cross-repository ADR for this concern.


## Plan of Work

Milestone 1 introduces the durable vocabulary. In
`seihou-core/src/Seihou/Core/Types.hs`, add `ManifestSchemaVersion`,
`ManifestCapability`, and `SharedWriteMode`. The three mode constructors mean unknown
legacy evidence, certified additive-only, and ownership closure required. Replace the
stored Boolean on `FileRecord`; the operation-planning types may keep their Boolean where
the plan has complete knowledge of the operations it just compiled. Provide a small total
conversion from a complete plan's Boolean to the corresponding known mode.

In `seihou-core/src/Seihou/Manifest/Types.hs`, make `currentManifestVersion` a
schema-version value whose JSON representation remains the integer 7. Add
`minimumManifestVersion :: ManifestCapability -> ManifestSchemaVersion` and
`manifestSupports :: ManifestCapability -> Manifest -> Bool`. The first capability is the
shared-path targeted-update exemption and maps to schema 7. Do not scatter a literal 7
through CLI modules. At the end of this milestone, pure unit tests can ask whether a
schema-6 or schema-7 manifest supports the capability.

Milestone 2 makes the wire contract version-aware. Change `Manifest.parseJSON` so it reads
and validates the top-level version before parsing `files`. Schema 6 accepts the old
`additiveOnly` representation: true becomes `SharedWriteAdditiveOnly`; false or absent
becomes `SharedWriteUnknown`. Schema 7 requires a `sharedWriteMode` value of `unknown`,
`additive-only`, or `requires-ownership-closure` on every file record. The schema-7
encoder always emits the key, including `unknown`, so another absent-field ambiguity
cannot recur. Versions 1 through 5 continue to fail with the explicit-upgrade message and
future versions continue to fail as newer than this binary.

Add `seihou-core/src/Seihou/Manifest/Upgrade.hs` and expose it from
`seihou-core/seihou-core.cabal`. It owns adjacent step metadata, validates that an upgrade
path is contiguous, and implements the pure 6-to-7 `Aeson.Value` transform. The transform
preserves every unrelated object member, changes `version` only after transforming all
file records, maps an old true flag to `additive-only`, and maps an absent or false flag to
`unknown`. It must be idempotent when asked to plan from 7 to 7 and must reject a target
above current or a path with a missing adjacent step. It does not implement the 5-to-6
path inference; EP-93 supplies that CLI step.

Milestone 3 updates producers and durable decisions. Replace every `FileRecord`
construction and every comparison in core and CLI tests with the new mode. The combination
rule in `Seihou.Core.Application.attachApplication` and
`Seihou.Engine.UpdateTransaction.prepareCandidateManifest` remains conservative: a
partial write with unknown retained owners remains unknown; a known closure requirement
cannot be strengthened; a complete plan may write either known answer. Any command that
rewrites a typed manifest may emit schema 7 because every decoded schema-6 file now carries
an explicit unknown value, but it must not turn unknown into additive-only without complete
evidence.

Update the version history comment and architecture sample in
`docs/dev/design/proposed/manifest-and-incrementality.md`. Verify that the implementation
fulfills ADR 0014 and update ADR 0005 or ADR 0012 only if the implemented behavior changes
their prospective wording. Do not change the public `seihou manifest upgrade` or `seihou
update` flow in this plan; focused tests should prove the new core contract before those
integrations begin.


## Concrete Steps

From the repository root, locate every version and file-record producer before editing:

```bash
rg -n 'currentManifestVersion|additiveOnly|FileRecord' \
  seihou-core/src seihou-core/test seihou-cli/src seihou-cli/src-exe seihou-cli/test
```

After Milestone 1, run the core suite:

```bash
cabal test seihou-core-test
```

The result must end in a successful test-suite status. After Milestone 2, add or extract a
schema-6 fixture and inspect the pure upgrade in a focused test. The expected JSON shape is:

```json
{
  "version": 7,
  "files": {
    ".gitignore": {
      "sharedWriteMode": "unknown"
    }
  }
}
```

The real fixture retains its other required keys; the excerpt only shows the changed
contract. Then run:

```bash
cabal test seihou-core-test
cabal build all
cabal test all
nix fmt -- --fail-on-change
nix flake check
```

Record the exact test counts and any deviations in Progress and Surprises & Discoveries.


## Validation and Acceptance

Acceptance is behavioral at the JSON boundary.

A schema-6 manifest with `"additiveOnly": true` decodes to
`SharedWriteAdditiveOnly`; one with the key absent or false decodes to
`SharedWriteUnknown`. Upgrading either to schema 7 produces a required
`sharedWriteMode` key and preserves unknown top-level and nested fields at the JSON-value
level. Encoding and decoding the resulting typed manifest returns the same value.

A schema-7 file record without `sharedWriteMode`, or with an unrecognized value, fails
with a message naming the file record and the missing or invalid key. A schema-8 manifest
continues to fail as newer than this binary. A schema-5 manifest continues to fail through
the ordinary decoder and names `seihou manifest upgrade`; the core 6-to-7 step must not
pretend to convert its machine-local paths.

`minimumManifestVersion TargetedAdditiveSharedPathUpdate` returns 7,
`manifestSupports` is false for a decoded schema-6 manifest and true for schema 7, and no
CLI module contains an independent numeric check for this capability.

Every manifest producer compiles with `SharedWriteMode`; unit tests prove that partial
updates preserve unknown or closure-required evidence and only complete evidence can
write additive-only. The full `cabal test all` and `nix flake check` runs pass.


## Idempotence and Recovery

The pure 6-to-7 transform must be safe to plan repeatedly. A request whose source and
target are both 7 returns an empty step list and unchanged document. A partially applied
in-memory transform is never written by this plan, so a failed test run needs no cleanup.

The schema bump touches many constructors. Make it in compilable slices: introduce the
new type, update core producers and tests, then update CLI producers and tests. If a slice
fails, retain the compiler errors as the exhaustive list of remaining call sites rather
than adding temporary wildcard conversions. All edits are ordinary tracked files and can
be recovered from git; do not delete user work in a dirty tree.


## Interfaces and Dependencies

`seihou-core/src/Seihou/Core/Types.hs` must export vocabulary equivalent to:

```haskell
newtype ManifestSchemaVersion = ManifestSchemaVersion { unManifestSchemaVersion :: Int }
  deriving stock (Eq, Ord, Show, Generic)

data ManifestCapability
  = TargetedAdditiveSharedPathUpdate
  deriving stock (Eq, Ord, Show, Generic)

data SharedWriteMode
  = SharedWriteUnknown
  | SharedWriteAdditiveOnly
  | SharedWriteRequiresOwnershipClosure
  deriving stock (Eq, Ord, Show, Generic)
```

`Manifest.version` becomes `ManifestSchemaVersion`, and `FileRecord` carries
`sharedWriteMode :: !SharedWriteMode`. Constructor names may change to match existing
repository vocabulary, but the three states and their meanings may not collapse.

`seihou-core/src/Seihou/Manifest/Types.hs` must export:

```haskell
currentManifestVersion :: ManifestSchemaVersion
minimumManifestVersion :: ManifestCapability -> ManifestSchemaVersion
manifestSupports :: ManifestCapability -> Manifest -> Bool
```

`seihou-core/src/Seihou/Manifest/Upgrade.hs` must expose a pure adjacent-step model and a
6-to-7 transform. The concrete record layout may follow repository conventions, but callers
must be able to ask for a source-to-target path, distinguish a lossless step from a step
requiring CLI inference, and receive an error for a gap. EP-93 consumes this API; it must
not parse `currentManifestVersion` comments or duplicate the step table.

No new package dependency is expected. Use the existing `aeson`, `containers`, `text`,
and `generic-lens` dependencies. New records follow `CLAUDE.md`: strict `data` fields,
explicit deriving strategies including `Generic`, and overloaded-label access rather than
record update syntax.


## Revision Notes

- 2026-09-17: Added the accepted ADR 0014 contract to make schema bumps, adjacent upgrade
  steps, capability minimums, and upgrade classifications permanent requirements rather
  than decisions local to this implementation plan. Updated the relevant ADR context and
  implementation guidance accordingly.

- 2026-09-18: Implemented all three milestones; recorded progress, discoveries, the
  version-preserving encoder and step-classification decisions, and the outcome.
