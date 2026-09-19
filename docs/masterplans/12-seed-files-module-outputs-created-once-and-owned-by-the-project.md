---
id: 12
slug: seed-files-module-outputs-created-once-and-owned-by-the-project
title: "Seed files: module outputs created once and owned by the project"
kind: master-plan
created_at: 2026-09-19T13:59:13Z
intention: "intention_01m2wz5ww3ezmvpf0aenfbgcjx"
provenance:
  created_by:
    model: "claude-opus-5[1m]"
    harness: "claude-code"
    at: 2026-09-19T13:59:13Z
---

# Seed files: module outputs created once and owned by the project

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Vision & Scope

Today every file a Seihou module generates is *managed*: `seihou run` records its content
hash and generated baseline in `.seihou/manifest.json`, `seihou status` reports it as
`modified by user` the moment anyone edits it, `seihou update` three-way-merges new module
releases into it, and `seihou run` treats an unmanaged copy already on disk as a conflict.
That model is right for files the module keeps owning, such as a Nix flake, a formatter
configuration, or a `.gitignore` block. It is wrong for a large class of files a module only
*starts*. The `haskell-cli-app` module in the `seihou-modules` registry
(`mori://shinzui/seihou-modules`, directory `modules/haskell/haskell-cli-app/`) generates
`CHANGELOG.md`, `README.md`, both `.cabal` files, `app/Main.hs`, `Cli.hs`, and `Prelude.hs`.
A developer must edit every one of these on day one — a changelog entry, a new dependency, a
new module in `other-modules`. From then on `seihou status` shows them all as
`modified by user`, forever, and the signal the command exists to give ("which generated
files have drifted?") drowns in files that were always meant to drift.

After this initiative a module author can mark a generation step as a **seed**. A *seed file*
is a file a module creates once, when the path does not exist yet, and then hands to the
project. Seihou never overwrites it, never content-tracks it, never merges into it, never
reports it as modified, and never deletes it. The step is declared in `module.dhall` by one
new optional field on the existing `Step` record:

```dhall
S.Step::{
, strategy = "template"
, src = "CHANGELOG.md.tpl"
, dest = "CHANGELOG.md"
, lifecycle = Some "seed"
}
```

Omitting the field, or writing `lifecycle = Some "managed"`, keeps today's behavior exactly.

The user-visible behaviors enabled are:

1. `seihou validate-module` accepts `lifecycle = Some "seed"` on `copy`, `template`, and
   `dhall-text` steps and rejects nonsensical combinations (a seed step with a `patch`, a
   `structured` seed, two steps of different lifecycles writing the same destination, a
   removal step deleting a seed destination).
2. `seihou run` creates a seed file only when its path is absent, never reports an existing
   file at a seed path as a conflict, and records a lightweight *seed receipt* in the manifest
   (path, owning module, owning applications, how the path was settled) with no content hash
   and no baseline. A seed the developer later deletes is not resurrected by a re-run.
3. `seihou status` and `seihou diff` no longer list seed files among tracked files; status
   prints one bounded line saying how many seed files the project has. `seihou remove`
   leaves seed files on disk and says so.
4. `seihou update` never touches an existing seed file, creates a seed newly added by a module
   release when its path is absent, and — the migration path for every project that already
   exists — when a module release turns a previously managed file into a seed, *releases*
   the file: it drops the content record and baseline, keeps the bytes on disk exactly as
   they are (edited or not, with no prompt), and records a seed receipt instead.
5. The `seihou-modules` registry marks the files that projects are expected to own as seeds
   (starting with `haskell-cli-app`, `haskell-library`, and `haskell-keiro-project`), and the
   module-authoring guide explains when to choose a seed.

Explicitly out of scope: a project-side command that lets a developer detach an arbitrary
managed file on their own (the existing edited-orphan `DetachAndKeepOrphan` choice already
covers the orphan case; a general `seihou untrack` is recorded as a future enhancement);
re-creating a deleted seed on request (`--reseed`); a `lifecycle` value other than `managed`
and `seed` (for example "regenerate on every run"); seed semantics for `structured` steps and
for patch steps; and any per-module minimum-Seihou-version gate (an older Seihou binary
ignores the unknown `lifecycle` field and treats the step as managed, which is exactly
today's behavior — see the Decision Log).


## Decomposition Strategy

The initiative is decomposed along the life of a seed file, one functional concern per plan,
so that each plan leaves the repository in a working, testable state:

EP-1 (the *declaration*) is the author-facing contract: the Dhall schema field, the Haskell
`Step` type, the decoder, and `validate-module` rules. It also writes the ADR that defines
what a seed file is, because every later plan implements a clause of that definition.

EP-2 (the *record*) is the manifest-facing contract: a new `seeds` map of seed receipts in
`.seihou/manifest.json`, which is a semantic manifest change and therefore, under
[ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md),
advances the schema from 7 to 8 with one lossless upgrade step. EP-2 does not depend on EP-1:
it defines a record type, not how steps produce it.

EP-3 (the *first write*) makes `seihou run` compile seed steps into a new `SeedFileOp`
operation, classify them against disk and the receipts, create absent files, and record
receipts. This is where the concept first becomes observable end to end.

EP-4 (the *reporting and removal* surface) makes `status`, `diff`, and `remove` treat seed
files as the project's. It needs only EP-2's record, so it can proceed in parallel with EP-3.

EP-5 (the *evolution*) teaches `seihou update` about seeds, including the managed-to-seed
release that existing projects need. It is split from EP-3 because the update engine
(`Seihou.Engine.Reconcile`, `Seihou.Engine.UpdateTransaction`, three-way merge, baselines,
the ownership closure, shared-write certification) is a separate, much larger subsystem from
`seihou run`'s three-state diff; folding both into one plan would give one plan most of the
initiative's risk.

EP-6 (the *adoption*) changes the modules users actually install and writes the authoring
guide. It lives mostly in another repository (`mori://shinzui/seihou-modules`) and is only
meaningful once a Seihou build can execute seeds.

Alternatives considered and rejected. *A boolean field* (`track = False` or `seed = True`)
was rejected in favor of `lifecycle : Optional Text` because the value space is likely to
grow (see Future Enhancements in EP-1) and because the existing `strategy` and `patch` fields
already use short text enumerations, so authors meet one convention. *Not recording seeds in
the manifest at all* was rejected: [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md)
says every fact about applied state belongs in the manifest, and without a receipt Seihou
cannot tell "the developer deleted the seed on purpose" from "this path was never seeded",
cannot let `seihou remove` explain what it leaves behind, and cannot release a managed file
to a seed idempotently. What the receipt deliberately omits is the *content* hash, which is
what makes a file "tracked". *A project-side ignore list* (a `.seihouignore` that hides paths
from status) was rejected because it hides the symptom per project instead of letting the
module author state intent once for every project, and because hidden files would still be
merged into and conflict on update. *One plan per command* (run, status, diff, remove,
update) was rejected as decomposition by file rather than by concern.

Relevant ADRs consulted. One cross-repository record applies: `seihou-modules` ADR 2,
"Separate Keiro project seeds from domain implementation" (`mori://shinzui/seihou-modules`,
project-relative path `docs/adr/2-separate-keiro-project-seeds-from-domain-implementation.md`;
its artifact-level Mori URI is pending because `mori registry concepts` does not index that
bundle yet). It already calls `haskell-keiro-project`'s generated libraries "seeds" that
"become hand-owned during implementation" and asks users to respect Seihou's conflict
protection on reapplication; this initiative makes that intent mechanical, and EP-6 amends
that ADR. `mori registry concepts` searches for "seed" and "unmanaged file" on 2026-09-19
found no other relevant decision. Local ADRs:

- [ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md): the
  manifest is committed and machine-independent. Seed receipts record project-relative
  paths only, and EP-2 must extend the machine-independence test that walks every serialized
  string.
- [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md): the reason
  seed receipts exist and live in the manifest rather than in a side file.
- [ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md): shared-path
  ownership closure and shared-write evidence apply to managed paths. Seed paths are not in
  the `files` map and must not participate; EP-5 must ensure certification recompiles ignore
  seed operations.
- [ADR 0013](../adr/0013-status-is-a-bounded-summary-the-manifest-is-the-record.md): status
  is a bounded summary. EP-4 prints one count line for seeds rather than a list.
- [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md): the
  `seeds` map advances the schema to 8 with a lossless adjacent step, a capability entry, and
  tests; EP-2 owns this.
- [ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md):
  new diagnostics (validation findings, update refusals) name modules and paths as users
  write them.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Declare seed steps in the module schema and validate them | docs/plans/99-declare-seed-steps-in-the-module-schema-and-validate-them.md | None | None | Not Started |
| 2 | Record seed receipts in manifest schema 8 | docs/plans/100-record-seed-receipts-in-manifest-schema-8.md | None | EP-1 | Not Started |
| 3 | Create seed files once during seihou run | docs/plans/101-create-seed-files-once-during-seihou-run.md | EP-1, EP-2 | None | Not Started |
| 4 | Keep seed files out of status, diff, and remove | docs/plans/102-keep-seed-files-out-of-status-diff-and-remove.md | EP-2 | EP-3 | Not Started |
| 5 | Reconcile seed steps during seihou update and release managed files to seeds | docs/plans/103-reconcile-seed-steps-during-seihou-update-and-release-managed-files-to-seeds.md | EP-1, EP-2, EP-3 | EP-4 | Not Started |
| 6 | Adopt seed steps in seihou-modules and document seed authoring | docs/plans/104-adopt-seed-steps-in-seihou-modules-and-document-seed-authoring.md | EP-3, EP-4, EP-5 | None | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3).


## Dependency Graph

EP-1 and EP-2 have no hard dependencies and can be implemented in parallel. EP-2 lists EP-1
as a soft dependency only because the ADR EP-1 writes defines the vocabulary EP-2's
`SeedOutcome` values use; EP-2 embeds that vocabulary itself, so it does not wait.

EP-3 hard-depends on EP-1 because it compiles `Step.lifecycle` (EP-1's field) into a
`SeedFileOp`, and on EP-2 because it writes `SeedRecord`s into `Manifest.seeds` (EP-2's
types and codec). Without both, the code does not compile.

EP-4 hard-depends only on EP-2: it reads `Manifest.seeds` and builds its test manifests
directly, so it does not need `seihou run` to produce seeds. It lists EP-3 as soft because
its end-to-end acceptance scenario is most convincing when a real `seihou run` produced the
seeds; if EP-3 is not complete, EP-4 validates with hand-written schema-8 manifests.

EP-5 hard-depends on EP-1, EP-2, and EP-3: it reuses EP-3's `SeedFileOp`, EP-3's shared seed
classification function, and EP-2's receipt merge helpers. It lists EP-4 as soft because the
update acceptance scenario checks `seihou status` afterwards.

EP-6 hard-depends on EP-3, EP-4, and EP-5: marking real registry modules as seeds is only
safe once every command a consumer runs (`run`, `status`, `update`, `remove`) understands
seeds, and in particular once `seihou update` releases the files existing projects already
track. It also requires the schema commit EP-1 pushes.

The critical path is EP-1 → EP-3 → EP-5 → EP-6, with EP-2 needed before EP-3 and EP-4
filling in alongside EP-3 or EP-5.


## Integration Points

**The `lifecycle` Dhall field and `StepLifecycle` Haskell type.** Owned by EP-1. The Dhall
field is `lifecycle : Optional Text` on `schema/Step.dhall` with default `None Text`; the
accepted values are exactly `"managed"` and `"seed"`. The Haskell type is
`data StepLifecycle = Managed | Seed` in `seihou-core/src/Seihou/Core/Types.hs`, and `Step`
gains the strict field `lifecycle :: !StepLifecycle` (absent or `None` decodes to `Managed`).
EP-3 and EP-5 read it through `step ^. #lifecycle`; EP-6 writes it in `module.dhall` files.
The schema commit EP-1 pushes to `shinzui/seihou-schema` is the pin EP-6's modules import.

**The `SeedFileOp` operation.** Owned by EP-3, defined in
`seihou-core/src/Seihou/Core/Types.hs` as a new `Operation` constructor:
`SeedFileOp { dest :: !FilePath, content :: !Text, strategy :: !Strategy, moduleName :: !ModuleName }`.
It is produced by `Seihou.Engine.Plan.compileStep` for a `Seed` step and passed through
`Seihou.Composition.Plan.mergeOperations`, which keeps the first seed for a path, records every
seeding module in a new *seed owners* result (`Map FilePath (Set ModuleName)`) returned by
`compileComposedPlan`, and fails composition when one module seeds a path another manages.
EP-5 consumes it when splitting candidate operations into managed and seed sets. Because
`seihou update` and shared-write certification would otherwise drop the new constructor
through wildcard matches (and could then treat the file as an orphan and delete it), EP-3 adds
an interim `Seihou.Engine.Seed.seedAsManagedWrite` applied in
`seihou-cli/src/Seihou/CLI/Update.hs` and `seihou-cli/src/Seihou/CLI/ManifestCapabilityUpgrade.hs`,
which makes those paths treat a seed as today's managed write; EP-5 deletes it. Every function that pattern-matches `Operation` with a
wildcard must be reviewed by EP-3 (for run paths) and EP-5 (for update paths); notably
`Seihou.Engine.Reconcile.operationDestination` returns `Nothing` for unknown constructors,
which would silently drop seeds from update if EP-5 forgot them.

**Seed receipts in the manifest.** Owned by EP-2. `Manifest` gains
`seeds :: !(Map FilePath SeedRecord)`, serialized under the top-level key `seeds` from schema
8 on. `SeedRecord` has `moduleName :: !ModuleName`, `applicationIds :: !(Set ApplicationId)`,
`outcome :: !SeedOutcome`, and `settledAt :: !UTCTime`; `SeedOutcome` is
`SeedCreated | SeedFoundExisting | SeedReleasedFromManaged`, serialized as `created`,
`found-existing`, `released-from-managed`. EP-2 also owns the manifest invariant that a path
appears in at most one of `files` and `seeds` (checked when decoding and by a pure
`validateManifestInvariants`), the helpers `mergeSeedRecord` and `dropSeedOwner` (in
`seihou-core/src/Seihou/Core/Seed.hs`), and the capability `SeedReceipts` with
`minimumManifestVersion SeedReceipts = 8`. EP-3 and EP-5 write receipts only through those
helpers; EP-4 reads and removes them only through them.

**The seed classification function.** Owned by EP-3, in
`seihou-core/src/Seihou/Engine/Seed.hs`:
`classifySeed :: Maybe SeedRecord -> Maybe FileRecord -> Bool -> SeedDecision`, where the
`Bool` says whether the path exists on disk and `SeedDecision` is
`SeedWrite | SeedKeepExisting | SeedRespectDeletion | SeedAlreadySettled | SeedReleaseManaged`.
EP-5 must call the same function so `run` and `update` agree on what a seed step does; EP-5
may add a decision only by extending this type in EP-3's module.

**Update reconciliation of seeds.** Owned by EP-5, in
`seihou-core/src/Seihou/Engine/Reconcile.hs`: new `FileReconciliation` constructors
`FileSeedCreate`, `FileSeedSettle`, `FileSeedRelease`, `FileSeedAbandon`, the
`ReconciliationReason` `AdoptingSeedFile`, and the errors `SeedReleaseBlockedByOwners` and
`SeedPathAlsoManaged`. Seeds ride the existing update transaction (snapshot verification,
journal, rollback). EP-5 must also exclude seed paths from `classifyOrphans`, since a managed
path whose step became a seed would otherwise be an orphan and, if unedited, deleted.

**`seihou status` rendering.** EP-4 owns the new seed summary line in
`seihou-cli/src/Seihou/CLI/StatusRender.hs`. EP-5 and EP-6 only observe it.

**Documentation.** Each plan updates the user documentation for the command it changes:
EP-1 `docs/user/module-authoring.md` (the field reference only) and `schema/README.md`; EP-2
`docs/cli/manifest.md` and `docs/user/manifest-upgrade.md`; EP-3 `docs/cli/run.md`; EP-4
`docs/cli/status.md`, `docs/cli/diff.md`, `docs/cli/remove.md`; EP-5 `docs/cli/update.md`;
EP-6 the "choosing a lifecycle" guidance in `docs/user/module-authoring.md` and the
`docs/user/CHANGELOG.md` entry for the release. Each plan adds its own entry under
`## [Unreleased]` in the repository-root `CHANGELOG.md`.

**ADRs.** EP-1 creates `docs/adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md`,
which records the definition, the lifecycle field, and the exclusions. EP-2 amends it with the
receipt rationale (why a receipt without a hash), EP-5 amends it with the release rule (a
managed-to-seed transition never prompts and never deletes). ADR 0014's version history list
is extended by EP-2.


## Progress

- [ ] EP-1: Schema field authored, pushed, and re-pinned
- [ ] EP-1: `Step.lifecycle` decoded; `validate-module` rules and tests
- [ ] EP-1: ADR 0017 and field reference docs
- [ ] EP-2: `SeedRecord` types, codec, and invariant
- [ ] EP-2: Schema 8, upgrade step 7 → 8, capability, docs
- [ ] EP-3: `SeedFileOp` compiled and merged across a composition
- [ ] EP-3: `seihou run` creates, keeps, and records seeds; dry-run output
- [ ] EP-4: status and diff ignore seeds; status summary line
- [ ] EP-4: remove leaves seeds and drops receipts
- [ ] EP-5: reconcile seed steps (create, keep, respect deletion)
- [ ] EP-5: managed → seed release and seed → managed adoption
- [ ] EP-5: certification and agent upgrade diagnosis ignore seeds
- [ ] EP-6: schema re-pinned and seeds adopted in seihou-modules
- [ ] EP-6: end-to-end verification against a real project; authoring guide


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Name the concept "seed file" and declare it with `lifecycle = Some "seed"` on
  `Step`, not with a boolean or a new strategy.
  Rationale: Seeding is orthogonal to how bytes are produced (copy, template, dhall-text), so
  it cannot be a strategy. A text enumeration matches `strategy` and `patch`, leaves room for
  future lifecycles, and reads as intent in `module.dhall`.
  Date: 2026-09-19

- Decision: Record a content-free seed receipt in the manifest (`seeds` map), advancing the
  manifest schema to 8.
  Rationale: ADR 0004 puts every applied-state fact in the manifest. The receipt is what lets
  a re-run respect a deliberate deletion, lets `remove` report what it leaves, and makes the
  managed-to-seed release idempotent. It omits the hash, which is what "not tracked" means.
  ADR 0014 requires the version advance.
  Date: 2026-09-19

- Decision: A path is in at most one of `files` and `seeds`; a composition in which one
  module seeds a path another module manages is refused at compile time.
  Rationale: Mixed ownership has no coherent answer to "does status report edits here?".
  Refusing is cheap and explicit; no real module needs it.
  Date: 2026-09-19

- Decision: Releasing a managed file to a seed on update never prompts, never deletes, and
  keeps the disk bytes exactly as they are.
  Rationale: The module author has declared that the project owns the file. A prompt would
  ask the developer to confirm what they already do (own their changelog); deleting or
  resetting would destroy their work.
  Date: 2026-09-19

- Decision: A deleted seed file is not re-created by `run` or `update` while its receipt
  exists.
  Rationale: The project owns the file, and deleting it is a legitimate project decision
  (for example, a project that keeps no changelog). Re-creating on request is a future
  `--reseed` flag.
  Date: 2026-09-19

- Decision: No minimum-Seihou-version gate for modules that use `lifecycle`.
  Rationale: Dhall record extraction in `Seihou.Dhall.Eval.stepDecoder` ignores fields it does
  not ask for, so an older binary reads a seed step as managed — today's behavior, which is
  safe (it merely keeps the status noise). A gate would be a larger, separate feature.
  Date: 2026-09-19

- Decision: Between EP-3 and EP-5, `seihou update` treats a seed operation as the managed
  write it used to be (`seedAsManagedWrite`).
  Rationale: EP-3 introduces `SeedFileOp` into compiled plans that update also consumes;
  wildcard matches there would drop it and classify the file as an orphan. Managed behavior
  is today's behavior and is safe; no published module uses seeds until EP-6.
  Date: 2026-09-19

- Decision: Six child plans, split by life-cycle concern (declare, record, first write,
  report/remove, evolve, adopt) with `seihou update` isolated in its own plan.
  Rationale: Keeps each plan independently verifiable and keeps the update engine's risk
  from dominating the plan that first makes seeds observable.
  Date: 2026-09-19


## Outcomes & Retrospective

(To be filled during and after implementation.)
