---
id: 11
slug: make-manifest-evolution-explicit-and-targeted-updates-upgrade-safe
title: "Make manifest evolution explicit and targeted updates upgrade-safe"
kind: master-plan
created_at: 2026-09-17T14:16:50Z
intention: "intention_01m2qvd83ae0yt8e3h7ay430bg"
provenance:
  created_by:
    model: "gpt-5.6-sol"
    harness: "codex-cli"
    at: 2026-09-17T14:16:50Z
  revisions:
    - model: "gpt-5.6-sol"
      harness: "codex-cli"
      at: 2026-09-17T15:41:41Z
      mode: "update"
      note: "Made ADR 0014 the initiative-wide manifest-evolution contract"
---

# Make manifest evolution explicit and targeted updates upgrade-safe

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Vision & Scope

After this initiative, a manifest schema version says which facts the file can express,
not merely which fields a permissive decoder happens to accept. Schema version 7 makes
shared-write evidence explicit for every managed path: the manifest can say that the
path is certified additive-only, that it requires the complete ownership closure, or
that an older manifest has not yet established either answer. A feature declares the
minimum manifest schema it needs, and a command upgrades only as far as that feature
requires. [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md)
makes that versioning and upgrade discipline the permanent manifest-evolution contract.

The failure reported in
[BUG-1](../bug-reports/additive-only-gate-breaks-targeted-update-on-preexisting-manifests.md)
then has a direct path forward. Running a targeted command such as
`seihou update nix-haskell-flake` against a schema-6 manifest may inspect the unknown
shared paths relevant to that target, stage the recorded co-owners only to establish
their write modes, and include the schema/evidence change in the update transaction.
It does not reconcile or rewrite the unrelated files owned by those applications. A
genuinely non-additive shared path still requires all owners, preserving the safety rule
from [ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md).

`seihou manifest upgrade` becomes an ordered schema-upgrade command rather than one
special-case rewrite from “anything old” to “current.” It can stop at a requested
schema version, chain every intervening step, preserve unknown JSON fields, and report
what each step changed. Manifests at schema 5 and earlier still receive the existing
explicit, reviewable conversion of machine-local `source` and `targetSource` paths to
portable `ArtifactOrigin` values. When local install metadata identifies the upstream,
the conversion records the appropriate remote URL; when it cannot, it refuses by default
instead of inventing provenance. Lossless upgrades such as 6 to 7 can be prepared in
memory by a feature command and committed atomically with that feature's result.

Errors and warnings use application labels such as
`link-skill [skill.name=exec-plan]`, not raw application-id hashes. Guidance leads with
the operation that repairs the missing evidence, `--include-shared-owners` is reserved
for paths proven to require the closure, and `CrossApplicationLastWriter` is rendered as
plain explanatory prose rather than a Haskell constructor.

This initiative does not add a second lockfile, change artifact or module versioning,
silently infer a remote for a schema-5-or-earlier manifest, or weaken ownership closure
for a path certified non-additive. It also does not make a targeted update reconcile an
unselected application's other files. Those exclusions preserve
[ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md),
[ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md),
and [ADR 0005](../adr/0005-legacy-manifests-convert-through-an-explicit-command.md).


## Decomposition Strategy

The initiative is split into four functional work streams, following the path from durable
representation to user-visible behavior.

EP-92 owns the manifest contract. It replaces the ambiguous `FileRecord.additiveOnly ::
Bool` interpretation with explicit shared-write evidence, advances the schema to version
7, defines the mapping from a feature to its minimum schema version, and introduces a
pure ordered-step model that cannot skip a schema version accidentally. This is isolated
in `seihou-core` so every producer and consumer shares one definition. It also owns the
implementation of ADR 0014. ADR 0012 now marks its schema-6 non-bump as superseded, and
ADR 0005 distinguishes inference-based explicit conversion from deterministic, lossless
adjacent upgrades. EP-92 must keep the code and those prospective records aligned.

EP-93 owns evidence acquisition and the explicit upgrade command. It generalizes
`Seihou.CLI.ManifestUpgrade` into a stepwise, lossless driver, keeps the current
machine-local-path-to-remote inference as the 5-to-6 step, and adds a reusable service
that can certify the write mode of all paths or only paths relevant to named targets.
This is separate from `seihou update` because `seihou manifest upgrade --dry-run` must be
independently testable and useful even when no module update is desired.

EP-94 owns update orchestration. Selection currently enforces the ownership closure
before any candidate source is fetched, which makes an unknown schema-6 fact impossible
to repair from inside the targeted workflow. EP-94 changes that into a two-phase
selection: identify the requested applications, resolve unknown evidence through EP-93,
then enforce the closure. It folds any lossless schema change into the same transaction
as the targeted update and proves that unrelated application files stay untouched.

EP-95 owns presentation and whole-workflow acceptance. It introduces one application
display vocabulary, gives every warning an explicit prose renderer, repairs remedy
ordering, updates user and CLI documentation, and adds regression fixtures matching the
reported project. Keeping this last prevents terminal and JSON contracts from being
written against intermediate error types.

Putting everything in one plan was rejected because the schema contract, inference and
certification service, update transaction, and presentation layer have different safety
properties and independent acceptance tests. A command-specific patch that treats
missing `additiveOnly` as true was rejected because it would silently weaken the gate.
Blindly bumping `currentManifestVersion` while leaving the one-off upgrader unchanged was
rejected because schema 6 would be sent through a path-conversion step it does not need
and could be stamped current without the new fact. Automatically converting schema 5
and earlier during `seihou update` was rejected because choosing a remote from the current
machine is inference that must remain explicit and reviewable under ADR 0005.

The relevant local decisions consulted were ADR 0001, ADR 0004, ADR 0005,
[ADR 0007](../adr/0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md),
ADR 0012, and
[ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md).
Mori searches for `manifest schema upgrade` and
`additive shared ownership` returned no cross-repository ADRs, so this initiative cites
no cross-repository decision record. The reproducing consumer is canonically identified
as `mori://tan/mls-service-v2`; no path into that other repository is used as a durable
reference.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 92 | Define manifest schema capabilities and ordered upgrade steps | docs/plans/92-define-manifest-schema-capabilities-and-ordered-upgrade-steps.md | None | None | Not Started |
| 93 | Upgrade legacy path manifests and backfill additive facts | docs/plans/93-upgrade-legacy-path-manifests-and-backfill-additive-facts.md | EP-92 | None | Not Started |
| 94 | Gate targeted updates on the minimum manifest schema | docs/plans/94-gate-targeted-updates-on-the-minimum-manifest-schema.md | EP-92, EP-93 | None | Not Started |
| 95 | Make shared-owner diagnostics actionable and verify upgrades | docs/plans/95-make-shared-owner-diagnostics-actionable-and-verify-upgrades.md | EP-94 | EP-93 | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3).


## Dependency Graph

EP-92 is the root because every later plan needs the version-7 wire format,
`SharedWriteMode`, the feature-to-minimum-version mapping, and the ordered upgrade-step
vocabulary.

EP-93 depends on EP-92 because the upgrade driver must produce and validate the exact
schema EP-92 defines. EP-94 depends on both: it consumes EP-92's capability query and
EP-93's target-scoped certification service. EP-95 depends on EP-94's final errors,
warnings, and transactional behavior; its soft dependency on EP-93 means its documentation
and end-to-end tests must describe the final upgrade command, but its presentation helpers
do not compile against EP-93 directly.

The dependency shape is intentionally narrow:

```text
EP-92 -> EP-93 -> EP-94 -> EP-95
   \----------------^       ^
            hard            |
                  EP-93 ----/ soft
```

After EP-92, exploratory work for EP-95's application-label renderer can proceed in
parallel with EP-93, but EP-95 cannot be completed until EP-94 fixes the error taxonomy.


## Integration Points

The manifest wire format is shared by every plan. EP-92 exclusively owns
`ManifestSchemaVersion`, `ManifestCapability`, `SharedWriteMode`, the version-aware JSON
decoder and encoder in `seihou-core/src/Seihou/Manifest/Types.hs`, and the corresponding
domain fields in `seihou-core/src/Seihou/Core/Types.hs`. Later plans may populate or
render those values but must not add another schema discriminator or reinterpret
`UnknownSharedWriteMode`.

The upgrade pipeline is shared by EP-93 and EP-94. EP-93 owns the step planner, raw-JSON
preservation, `seihou manifest upgrade` behavior, and the reusable target-scoped shared
write certification service under `seihou-cli/src/`. EP-94 calls that service from update
planning; it must not copy path-inference or composition logic into
`Seihou.CLI.Update.Selection`.

Application selection and identity are shared by EP-94 and EP-95. EP-94 owns the two-phase
selection protocol and a renderer-neutral `ApplicationRef` carrying stable id, target,
and saved parent-variable context. EP-95 owns how that reference becomes terminal prose.
This keeps UI labels out of the safety algorithm while ensuring the renderer never has
only an opaque hash.

The update transaction is shared by EP-94 and the existing reconciliation engine. EP-94
owns the rule that a lossless schema/evidence upgrade is planned in memory and published
with the target update's manifest, while `Engine.UpdateTransaction` continues to own
atomic file and manifest publication. No child plan may write the manifest as a separate
preflight side effect of `seihou update --dry-run`.

ADR 0014 owns the cross-plan manifest-evolution rule. EP-92 implements its schema,
capability, and contiguous-step contracts. EP-93 implements its distinction between
lossless steps and inference-bearing conversions. EP-94 consumes its feature-to-minimum
mapping. ADR 0012 and ADR 0005 link to ADR 0014 so later implementation must update those
records only if the delivered behavior differs from their prospective wording.


## Progress

Track milestone-level progress across all child plans. Each entry names the child plan
and the milestone. This section provides an at-a-glance view of the entire initiative.

- [ ] EP-92 M1: Define schema versions, feature requirements, and explicit shared-write evidence.
- [ ] EP-92 M2: Make version-aware JSON round trips and ordered pure schema steps pass.
- [ ] EP-92 M3: Update every manifest producer and verify ADR 0014 without silently stamping incomplete state current.
- [ ] EP-93 M1: Generalize the raw-document upgrader into an ordered, targetable step chain.
- [ ] EP-93 M2: Preserve and strengthen machine-local-path-to-remote conversion for schema 5 and earlier.
- [ ] EP-93 M3: Certify shared-write modes for all applications or a named target without touching project files.
- [ ] EP-94 M1: Split application matching from ownership-closure enforcement.
- [ ] EP-94 M2: Stage the minimum required manifest upgrade inside targeted update planning and apply.
- [ ] EP-94 M3: Prove targeted, dry-run, retry, and genuinely non-additive cases transactionally.
- [ ] EP-95 M1: Render application labels and every update warning as intentional prose.
- [ ] EP-95 M2: Correct remedies and lock the human and JSON contracts with regression tests.
- [ ] EP-95 M3: Update all documentation and run the full repository acceptance matrix.


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments, or unexpected
interactions between child plans. Provide concise evidence.

- Observation: Manifests are already versioned; `currentManifestVersion` is 6. The
  `additiveOnly` field was deliberately excluded from versioning and omitted when false,
  so schema 6 cannot distinguish “known to require closure” from “predates the field.”
  Evidence: `seihou-core/src/Seihou/Manifest/Types.hs` documents the non-bump and its
  `FromJSON FileRecord` defaults an absent key to `False`.

- Observation: The existing upgrade command is not a general migration chain.
  `readLegacyManifest` treats every version below `currentManifestVersion` as an
  absolute-path manifest, `applyUpgrade` always sets the document directly to current,
  and `setSchemaVersion` has no intervening-step validation. A version bump without this
  initiative would therefore make schema 6 enter the wrong conversion path.

- Observation: The useful machine-local path conversion already exists and should be
  retained, not reinvented. `Seihou.CLI.ManifestUpgrade` inspects local install metadata,
  emits `RemoteOrigin` when it can establish a URL, keeps project paths relative, reports
  unverifiable local origins, validates the converted document, and writes atomically.

- Observation: The ownership gate runs before source staging. `selectAndSeedLegacy` calls
  `selectApplications`, and `selectApplications` calls `ensureOwnershipClosure` before
  `stageCandidateSources`. Targeted repair therefore requires a two-phase selection
  protocol rather than a local change to the error renderer.


## Decision Log

Record every decomposition or coordination decision made while working on the master
plan.

- Decision: Schema 7 will represent shared-write evidence as an explicit three-state
  value rather than continuing to overload a Boolean default.
  Rationale: A Boolean cannot preserve fail-closed safety while also distinguishing a
  genuinely non-additive path from an older manifest that can be certified on demand.
  Date: 2026-09-17

- Decision: Every feature that depends on manifest semantics will name its minimum schema
  version through one core mapping.
  Rationale: Scattered numeric checks would recreate the same reliability problem at
  command boundaries and make later schema changes depend on convention.
  Date: 2026-09-17

- Decision: Inference-bearing upgrades remain explicit; lossless upgrades may be staged
  automatically and committed with the feature transaction that needs them.
  Rationale: Turning somebody else's absolute path into a remote URL is a judgement that
  must be reviewed, while making previously implicit uncertainty explicit is deterministic.
  Date: 2026-09-17

- Decision: Unknown shared-write evidence is resolved only for paths relevant to the
  requested target unless the user explicitly runs an all-manifest upgrade.
  Rationale: The reported bug is costly because a one-target request expands into unrelated
  application work. Evidence gathering may inspect co-owners, but it must not reconcile
  their unrelated files.
  Date: 2026-09-17

- Decision: `--include-shared-owners` remains available for paths proven to require the
  closure but is not a remedy for unknown evidence.
  Rationale: Expanding the selection is legitimate for a real whole-file co-write. It is
  harmful when the only missing input is a schema fact that can be established without
  updating those applications.
  Date: 2026-09-17

- Decision: Adopt ADR 0014 as the governing cross-plan manifest-evolution contract.
  Rationale: Requiring a schema bump, one adjacent classified upgrade step, a capability
  minimum, and a mechanical gap check for every semantic change prevents a future
  optional-field exception from recreating the schema-6 ambiguity.
  Date: 2026-09-17


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original vision. Before marking the MasterPlan complete,
distill durable project context from this MasterPlan and its child ExecPlans into
docs/adr/. Keep task-local execution and coordination details here.

(To be filled during and after implementation.)


## Revision Notes

- 2026-09-17: Recorded accepted ADR 0014 as the initiative-wide manifest-evolution
  contract, replaced prospective ADR-creation language, and assigned its implementation
  responsibilities across EP-92, EP-93, and EP-94.
