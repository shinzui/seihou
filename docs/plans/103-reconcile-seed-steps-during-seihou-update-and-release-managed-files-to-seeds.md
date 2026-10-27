---
id: 103
slug: reconcile-seed-steps-during-seihou-update-and-release-managed-files-to-seeds
title: "Reconcile seed steps during seihou update and release managed files to seeds"
kind: exec-plan
created_at: 2026-09-19T13:59:13Z
intention: "intention_01m2wz5ww3ezmvpf0aenfbgcjx"
master_plan: "docs/masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md"
provenance:
  created_by:
    model: "claude-opus-5[1m]"
    harness: "claude-code"
    at: 2026-09-19T13:59:13Z
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-27T00:43:50Z
      mode: "update"
      note: "Specify content-free release, transactional creation and early ordinary consumer acceptance"
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-27T00:43:50Z
      verdict: "approved"
      note: "Reviewed revised plan against current source and cross-plan contracts; approval is for implementation design, not runtime delivery"
---

# Reconcile seed steps during seihou update and release managed files to seeds

This ExecPlan is a living document. Maintain Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective as work proceeds.

This is EP-5 of [MasterPlan 12](../masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md).
Hard prerequisites are [plan 99](99-declare-seed-steps-in-the-module-schema-and-validate-them.md),
[plan 100](100-record-seed-receipts-in-manifest-schema-8.md), including Milestone 4, and
[plan 101](101-create-seed-files-once-during-seihou-run.md). Reporting from
[plan 102](102-keep-seed-files-out-of-status-diff-and-remove.md) is an integration dependency:
the combined status assertion must pass before delivery, but reconciliation work can begin first.

## Purpose / Big Picture

An existing remote-backed project with edited changelogs and Cabal files runs:

```bash
seihou update haskell-cli-app
```

Update fetches candidates and dependencies from recorded origins, reuses saved inputs, and
includes `release to project` in its ordinary preview. Accepting the overall update removes
managed content records for newly declared seeds, preserves current bytes or absence, and
records settlement. There is no separate per-file release prompt, prerequisite install/upgrade,
manual manifest edit, or special force flag. Existing edited seeds remain untouched; a new seed
is created only if its path is absent and has no settlement receipt. A second unchanged update
is a no-op. Missing legacy origin information still uses the existing manifest migration workflow.

## Progress

- [ ] Milestone 1: seed reconciliation and exclusive transactional creation preserve bytes, claims, and rollback; interim refusal is removed safely.
- [ ] Milestone 2: a representative existing Haskell consumer adopts seed declarations through ordinary update before expanding variant coverage.
- [ ] Milestone 3: shared-owner transitions, retirement, adoption, migration protection, automation, and human output meet the complete contract.
- [ ] Milestone 4: combined command acceptance, docs, and recovery checks pass; release readiness handed to EP-6.

## Surprises & Discoveries

Review (2026-10-26): `buildFinalManifest` already carries `filesManifest.seeds`. Current
schema is 10, not 8. `ObservedFile` represents presence plus a text hash, so it is unsuitable
for content-free seed settlement and cannot distinguish a dangling symlink from absence.
Update transaction already handles literal-link snapshots and Git-index adoption; preserve
that recovery behavior. An ordinary `WriteMutation` still replaces a concurrently appearing
file even if an earlier snapshot check passed.

## Decision Log

Decision (2026-10-26): seeds use the existing transaction and recovery journal, with an explicit
exclusive-create mutation. Metadata-only settlement/release never snapshots or hashes seed
content and never restores it on rollback. This prevents both accidental reads of arbitrary
project data and restoration over edits the transaction never owned.

Decision (2026-10-26): retained owners are checked before granting a lifecycle transition.
`--include-shared-owners` can expand an actual managed ownership closure, but cannot resolve
candidates that still disagree on lifecycle. Candidate claims replace only selected claims;
unchanged application owners are never inferred from the first content supplier.

Decision (2026-10-26): seed-to-managed adoption requires an explicit keep/accept choice,
including when generated and current bytes happen to agree. A deleted seed offers accept
(recreate and manage) or abort; it cannot become a tracked nonexistent file. `--force` and
JSON mode do not imply consent. Adoption of directories/symlinks refuses with a repair action.

## Outcomes & Retrospective

Planning correction only; no runtime delivery claimed.

## Context and Orientation

Read `CLAUDE.md` for record conventions and module placement. The CLI service is
`seihou-cli/src/Seihou/CLI/Update.hs`; its executable adapter is in `src-exe/Seihou/CLI/Update.hs`.
`Update/Selection.hs` selects recorded applications and enforces managed ownership closure;
`Update/Types.hs` defines `UpdatePlan` and `ManifestPreparation`. Candidate composition comes
from `Seihou.Composition.Plan`. EP-3 changes its tuple result to `ComposedPlan`, including
seed claims and explicit content supplier.

`seihou-core/src/Seihou/Engine/Reconcile.hs` plans managed file changes and orphan cleanup.
`UpdateTransaction.hs` applies changes, publishes baselines/manifest, and recovers failure.
`Seihou.Engine.Seed` from EP-3 owns classification against `PathEntry` and exclusive creation;
`Seihou.Core.Seed` from EP-2 owns receipts, exact claims, and invariant checks. Checkout
reconciliation already protects declarative links and commands. Extend those boundaries instead
of inventing another transaction or duplicating seed classification in the CLI.

Relevant decisions are [ADR 0017](../adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md)
(seed settlement), [ADR 0018](../adr/0018-checkout-outputs-are-observable-portable-declarations.md)
(checkout compatibility), [ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md)
(shared ownership), [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md)
(capability staging), [ADR 0007](../adr/0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md)
(no-op), and [ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md)
(human diagnostics).

## Plan of Work

### Milestone 1 — plan and apply one release safely

Partition compiled operations once before managed validation/grouping. Define `SeedAction`
in `Reconcile.hs` with candidate content for creation only, explicit supplier, exact
`Map ApplicationId (Set ModuleName)` claims, and EP-3's `SeedDecision`. Preserve manifest
application order followed by composition order when several applications propose a new seed.
For already-settled paths, keep the original supplier, outcome, and time regardless of order.

Add `FileSeedCreate`, `FileSeedSettle`, `FileSeedRelease`, and `FileSeedAbandon` to
`FileReconciliation`, carrying the path and required receipt/action data. Create carries an
observed missing `PathEntry`; metadata-only actions carry no text-hash precondition. Refactor
`reconciliationObservation` to express that distinction explicitly rather than manufacturing
an `ObservedFile`. The release constructor retains the prior managed record for manifest effects,
not to authorize disk mutation. Call `classifySeed`; do not duplicate its decision tree.

Exclude all released paths from managed orphan classification and baseline generation.
Create uses the exclusive primitive from EP-3 through a new `CreateSeedMutation`, not
`WriteMutation`. Update differs from run when a path appears after preview: abort as stale
before replacing it, leave the new object intact, and let a fresh preview settle it. Journal
only mutations actually owned by this transaction. Rollback removes a created seed only if it
still matches the transaction's creation evidence; a subsequently changed object is preserved
and recovery reports the unresolved state. This temporary recovery evidence is not a permanent
seed baseline or receipt hash. Preserve prior journal readers; advance journal format if needed.

Settle/abandon/release are metadata-only: merge or subtract precise claims; release drops the
managed record and creates `SeedReleasedFromManaged`, preserving bytes and deliberate absence.
Prune a released baseline only when no remaining managed record references its blob. Do not
assume one baseline blob belongs to one path. Validate the final manifest before publication.
Stage the minimum capability for exact seed ownership from EP-2, never downgrade schema 9/10
fields, and publish with the existing transaction. Schema 8 remains the historical receipt
capability. Remove EP-3's interim refusal only after these paths are integrated; never add a
managed-write fallback. Certification explicitly excludes seed operations.

Acceptance: focused `ReconcileSpec` and `UpdateTransactionSpec` prove edited, unedited, and
deleted managed releases; creation; appearing objects; failed apply and restart recovery;
unchanged seed bytes during rollback; and shared baseline retention. Existing checkout
rollback and index-adoption tests remain passing.

### Milestone 2 — prove the ordinary consumer path early

Before broad variants, take a disposable copy/worktree of a representative project that
already uses `mori://shinzui/seihou-modules/templates/haskell-cli-app` at its real pre-seed
release. Preserve its application records, origins, saved inputs, and edited Cabal/changelog
bytes. EP-6 supplies a minimal candidate registry revision from its classification milestone;
local candidate staging is acceptable for this early source proof and must be disclosed.
Do not repair the consumer's manifest, untrack files, enumerate transitive dependencies, or
pre-install a missing dependency to make the scenario pass.

Use the built executable's absolute path and a fresh isolated configuration/cache. Capture
bytes of edited paths before update in files outside the project, then run ordinary
`seihou update haskell-cli-app` and accept its normal confirmation. Compare with those snapshots
using `cmp`; `git diff --exit-code` against HEAD is not a valid edit-preservation assertion.
Assert release, new seed creation, current manifest invariants, a second no-op, and (once EP-4
is accepted) bounded status with no seed drift. Also run dry-run/cancel first and prove no
project/manifest/index mutation. Record binary revision, producer revision, old schema, every
setup step, and command count. A source proof does not satisfy EP-6's published release gate.

### Milestone 3 — transitions and all mutation surfaces

Aggregate candidate seed claims from every selected application. In each receipt, replace the
selected applications' claims with their candidate claims and retain unselected claims.
A false condition, destination rename, removed step, or removed dependency retires just that
claim. Last-claim retirement removes the receipt and keeps the file. The deletion memory ends
with the receipt; reintroduction may create an absent file. Test a seeder disappearing while
another module in the same application still seeds that path, and two different applications.

Reject `SeedReleaseBlockedByOwners` if any managed owner is unselected, regardless of old
additive certification. Refuse `SeedPathAlsoManaged` when any retained or candidate claim
still manages or overlaps a seeded path. Name the path and recorded application labels. Suggest
`--include-shared-owners` only if selection expansion can resolve the missing-owner case;
for contradictory declarations, require a compatible producer release. Seed claims alone do
not impose managed ownership closure. Resolve explicit legacy seed ownership from exact
recorded artifacts inside the normal command when precise subtraction is needed; retain unknown
claims and give an actionable error if evidence is unavailable.

For seed-to-managed adoption, use `AdoptingSeedFile` with explicit choices. Keep current writes
no file but records its hash and the *generated candidate* as the future merge baseline; accept
uses candidate bytes and baseline. Never use project-edited bytes as the generated ancestor.
Clear the seed receipt only after all owner claims transition; retained seed claims block adoption.
A missing file offers accept or abort. Interactive, JSON, and force paths must agree; unresolved
adoption in noninteractive mode explains that an interactive ordinary update is needed.

Protect seed paths before declarative migrations, staged generation, and removal-like mutations:
no move/delete/rewrite/patch may mutate a seed, or a path being released to one, as a side effect.
Report incompatible producer migrations before applying anything. Staged projects copy current
seed bytes when present, preserve deliberate absence, and materialize only newly created seed
candidates. They must not replace existing seeds with rendered template bytes. Shell commands
remain unsandboxed; audit adopting producers and document that they must not mutate seeds.
Do not claim that lifecycle protection can police arbitrary shell.

Extend no-op detection to receipt/claim/schema changes, excluding fresh timestamps or supplier
reordering as artificial work. Extend text and versioned JSON renderers in `Update/Render.hs`
with create, settle, release, and abandon actions; seed adoption stays in the conflict list.
Review every exhaustive reconciliation consumer, including summaries, automation commit path
selection, interaction, and `UpgradeDiagnosis.hs`. `--commit` must include newly created seeds
and the manifest but never auto-stage existing project edits merely because a file was released.
A dry-run brief explains releases as intentional ownership changes.

### Milestone 4 — combined acceptance and documentation

Extend `seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs` (or a registered `SeedUpdateE2ESpec`) with
old-schema release, unchanged/edited/deleted paths, co-owners, condition retirement, adoption,
empty cache, force refusal, no-op, and failed recovery scenarios. Reuse `UpdateFixture.hs`.
Retain tests of `ManifestCapabilityUpgradeSpec`, `UpdateRenderSpec`, `UpdateInteractionSpec`,
and `UpgradeDiagnosisSpec`. Finish the EP-4 status integration check before delivery.

Update `docs/cli/update.md`, root `CHANGELOG.md`, and ADR 0017 with actual evidence. Give one
normal adoption command and accurate repair messages. Leave release/installation status to EP-6.

## Concrete Steps

From the repository root in the Nix development shell:

```bash
cabal build all
cabal test seihou-core-test --test-options='-p Reconcile'
cabal test seihou-core-test --test-options='-p UpdateTransaction'
cabal test seihou-cli-test --test-options='-p Update'
cabal test all
nix flake check
```

In the preserved consumer, use the tested binary for:

```bash
seihou update haskell-cli-app --dry-run
seihou update haskell-cli-app
seihou status
seihou update haskell-cli-app
```

Dry-run/status/repetition are acceptance observations; normal adoption itself is one update.

## Validation and Acceptance

The existing consumer's edits and deliberate deletions survive one ordinary update with saved
inputs and an empty optional cache. No seed is orphan-deleted or managed-hashed. Failed and
cancelled work preserves old applied state and unrelated edits. No extra preparation is hidden
in fixtures. Tests establish native no-replace behavior as well as pure reconciliation.

## Idempotence and Recovery

Repeat update is a no-op when declarations and receipts are unchanged. Run failures may leave
new seed bytes as EP-3 documents; update failures use the existing transaction/recovery route,
including `seihou update --dry-run` recovery where already supported. Recovery must never
restore a metadata-only seed path or remove an object that appeared before creation succeeded.

## Interfaces and Dependencies

EP-5 owns seed reconciliation constructors, transaction mutations/journal extensions, update
rendering and adoption policy. EP-3 owns classification and exclusive creation; EP-2 owns
receipt schema and claim helpers. Shared artifacts have one owner even where update extends
exhaustive consumers. EP-6 depends on this plan's completion; no library dependency is selected.

Revision note (2026-10-26): add an early ordinary consumer proof, exact claim replacement,
content-free settlement, exclusive transactional creation, complete lifecycle/migration
protection, and explicit adoption semantics; preserve current checkout integration.
