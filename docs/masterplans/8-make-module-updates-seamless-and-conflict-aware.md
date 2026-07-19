---
id: 8
slug: make-module-updates-seamless-and-conflict-aware
title: "Make module updates seamless and conflict-aware"
kind: master-plan
created_at: 2026-07-19T16:26:57Z
intention: "intention_01kxxjwvf8e2e8r64feyk6r65b"
---

# Make module updates seamless and conflict-aware

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

After this initiative, updating an applied Seihou module is one project-aware operation.
A user runs `seihou update master-plan`, or runs `seihou update` to update every recorded
top-level composition in the current project. Seihou fetches candidate module sources
without first mutating the shared installed-module cache, reuses the exact per-instance
inputs from the previous application, plans and applies migrations, renders the new
templates, merges non-overlapping user edits, runs only new or changed module commands,
and publishes the new manifest and installed cache only after the managed update succeeds.

The intended user experience is concise and organized by outcome rather than by every
internal generation operation:

```text
$ seihou update master-plan
master-plan  0.5.0 -> 0.7.0
Inputs:      4 reused; 1 new default
Migrations:  0 operations
Files:       2 updated; 1 merged; 4 unchanged; 0 conflicts
Commands:    6 unchanged commands skipped

Apply? [Y/n]
✓ Updated master-plan to 0.7.0.
```

Three-way merge is a central requirement, not an optional follow-up. For each generated
text file, Seihou retains the previous generated content as the **baseline**. On update it
compares that baseline with the current disk content (the user's version) and the newly
generated content. Non-overlapping changes merge automatically. Overlapping edits become a
real conflict with labeled conflict markers and interactive or flag-driven resolution.
The manifest distinguishes the generated baseline hash from the hash of the content that
was actually written after merging, so user customizations remain visible on future
updates instead of being mistaken for generated content.

The initiative includes all of the following behavior:

- a backward-compatible manifest schema that records top-level applied compositions,
  ordered roots, module instances, per-instance resolved inputs, file ownership, generated
  baseline references, and successful command receipts;
- content-addressed baseline blobs under `.seihou/baselines/`, including validation and
  pruning of unreferenced blobs after successful updates;
- a three-way text merge engine backed by `git merge-file --stdout --diff3`, with pure
  short-circuit cases and a conservative conflict result if Git cannot run;
- one file-level reconciliation plan that collapses repeated patch operations targeting
  the same path, safely deletes unchanged obsolete generated files, and retains edited
  orphans as tracked unresolved state;
- a conservative targeted-update rule: if a selected application and an unselected
  application jointly own any path, planning stops and asks the user to select every owner
  (or run the all-applications form) rather than guessing how to reconstruct the unselected
  layer;
- stable command fingerprints and an update policy that skips unchanged commands by
  default while retaining `--run-all-commands` and `--no-commands` escape hatches;
- a testable staged update service in the `seihou-cli-internal` library that fetches remote
  candidates, resolves saved inputs, deduplicates module migrations, produces an honest
  post-migration dry-run for declarative file operations, applies a rollback journal for
  managed file/cache mutations, and exposes structured results to the CLI;
- a top-level `seihou update` command, status recommendations, JSON/human rendering,
  commit integration, completions, user documentation, and a local-git-remote end-to-end
  fixture covering upgrades with user edits;
- explicit no-op and same-version behavior: unchanged candidate content exits cleanly
  without confirmation or publication, while changed content under the same declared
  version remains updateable but carries an authoring/version warning;
- clearer separation of responsibilities: `seihou run` remains initial generation or
  explicit reconfiguration, `seihou update` reconciles an existing project, and `seihou
  upgrade` remains cache-only maintenance with wording that no longer implies the current
  project was updated.

The following are explicitly out of scope:

- binary-file merging. Binary or non-text content that differs on both sides remains a
  conflict and is never silently overwritten;
- semantic language-aware merges for arbitrary source formats. The existing Structured
  strategy continues to deep-merge JSON/YAML at composition time, while update-time merge
  is line-oriented text merge;
- undoing arbitrary side effects from module or migration shell commands. The managed
  file tree, baseline store, installed cache, and manifest receive rollback protection,
  but an external command may perform effects Seihou cannot reverse; failures must report
  this limitation explicitly;
- automatic project updates for blueprints or prompts. Blueprints are agent-authored and
  non-deterministic; prompts do not own project files. This initiative applies to
  deterministic modules and recipes;
- replacing Git-backed module sources or redesigning the shared XDG installed-module cache
  as a per-project package store;
- named multiple applications of the identical root composition. The stable application
  identity is the requested module-or-recipe target plus the ordered additional roots.
  Reapplying that identity updates its saved inputs. A future initiative may add explicit
  user-assigned application names if the same root needs several independent instances.


## Decomposition Strategy

The work is split into six functional work streams. The ordering follows the data flow of
an update: first persist enough information to reproduce an application; then make prior
generated content available and mergeable; then turn generated operations into safe
file-level actions; in parallel, make commands incremental; then compose those capabilities
behind a staged update service; finally expose and document the public CLI.

EP-64 owns persistent state. It bumps the manifest schema once and defines every shared
record later plans need: `ApplicationId`, `AppliedComposition`, `AppliedInstanceState`,
`BaselineRef`, per-file application ownership, and `CommandReceipt`. It also makes ordinary
successful `seihou run` invocations record reproducible compositions. Later plans populate
baseline and command fields rather than independently changing the manifest shape.

EP-65 owns baseline storage and the three-way merge primitive. It adds the
content-addressed baseline effect and verifies the real Git merge driver independently of
the update orchestrator. It also makes normal generation seed baseline references, so
projects can accumulate merge-ready state before `seihou update` is exposed.

EP-66 owns file reconciliation. It collapses multiple operations into one desired result
per path, calls EP-65's merge engine, classifies safe and edited orphans, and applies a
pre-resolved file plan with rollback. This is separate from remote fetching and variable
resolution so its safety rules can be tested entirely against temporary and pure
filesystems.

EP-67 owns command lifecycle. It annotates rendered commands with their module instance,
defines stable fingerprints, records only successful executions, and provides run-all,
changed-only, and disabled policies. It depends on EP-64's receipt fields but can proceed in
parallel with EP-65 and EP-66.

EP-68 owns project update orchestration. It is the only plan allowed to combine remote
candidate discovery, saved-input resolution, migration planning, staged rendering,
file reconciliation, command planning, cache publication, and manifest publication. It
produces a library service rather than executable-only glue, closing the testability gap
recorded in `docs/plans/16-make-run-migration-aware.md`.

EP-69 owns the public surface. It adds the parser and executable dispatcher, rendering,
interactive conflict choices, status advice, upgrade/run guidance, documentation, and
end-to-end acceptance tests. Keeping parser concerns last follows the repository's
library-first convention: behavior belongs in `seihou-cli/src/`; only
`Options.Applicative` parsing and dispatch remain under `seihou-cli/src-exe/`.

Several alternatives were considered and rejected. Extending `seihou upgrade` with a
`--run` flag would keep the shared cache mutation as the first step and would not provide a
single project transaction, so the new operation is named `update`. Storing only hashes
cannot support three-way merge because the original generated bytes are unavailable, so a
content-addressed baseline store is required. Depending on a new Haskell diff package was
rejected after `mori registry search` found no registered Haskell three-way merge package;
the already-required Git executable has a mature `merge-file --diff3` implementation.
Putting all behavior in one ExecPlan was rejected because the manifest schema, merge
engine, file safety policy, command policy, orchestration, and CLI each have independent
acceptance tests and distinct failure modes.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 64 | Record reproducible applied compositions and update state | docs/plans/64-record-reproducible-applied-compositions-and-update-state.md | None | None | Complete |
| 65 | Store generated baselines and perform three-way merges | docs/plans/65-store-generated-baselines-and-perform-three-way-merges.md | EP-64 | None | In Progress |
| 66 | Plan conflict-aware file reconciliation and safe orphan handling | docs/plans/66-plan-conflict-aware-file-reconciliation-and-safe-orphan-handling.md | EP-64, EP-65 | None | Not Started |
| 67 | Track generated commands and skip unchanged executions | docs/plans/67-track-generated-commands-and-skip-unchanged-executions.md | EP-64 | EP-66 | Not Started |
| 68 | Build a staged project update service | docs/plans/68-build-a-staged-project-update-service.md | EP-64, EP-65, EP-66, EP-67 | None | Not Started |
| 69 | Ship the `seihou update` workflow and ecosystem guidance | docs/plans/69-ship-the-seihou-update-workflow-and-ecosystem-guidance.md | EP-68 | EP-64, EP-65, EP-66, EP-67 | Not Started |


## Dependency Graph

EP-64 is the only root plan. EP-65 and EP-67 can begin in parallel once EP-64 completes:
EP-65 consumes `BaselineRef` and the extended `FileRecord`, while EP-67 consumes
`CommandFingerprint`, `CommandReceipt`, and the per-application receipt container.

EP-66 requires both EP-64 and EP-65 because a reconciliation plan needs application-scoped
file ownership, baseline lookup, and the three-way merge result type. EP-67 has only a soft
dependency on EP-66: command previews should use compatible outcome vocabulary, but command
fingerprinting and receipt recording do not require file reconciliation code.

EP-68 is the convergence point. It cannot truthfully plan or apply an update until saved
application inputs, baseline/merge support, file reconciliation, and command policies all
exist. It consumes those interfaces without redefining them.

EP-69 depends on EP-68's `UpdateRequest`, `UpdatePlan`, `UpdateResult`, and service entry
points. Its soft dependencies name the earlier plans because its help text and docs must
describe their final semantics, but their code reaches EP-69 transitively through EP-68.

The dependency shape is therefore:

```text
EP-64
  |-- EP-65 -- EP-66 --\
  |                    +-- EP-68 -- EP-69
  \-- EP-67 -----------/
```


## Integration Points

The manifest schema is shared by every plan. EP-64 owns the definitions and JSON contract
in `seihou-core/src/Seihou/Core/Types.hs` and
`seihou-core/src/Seihou/Manifest/Types.hs`. EP-65 may populate baseline references, EP-66
may update applied hashes and application ownership, EP-67 may populate command receipts,
and EP-68 may replace an application after success, but none may add another schema field
or bump the schema version without first revising this MasterPlan and EP-64.

Application identity is shared by EP-64, EP-66, EP-68, and EP-69. EP-64 defines a stable
`ApplicationId` from the requested runnable target plus the ordered additional roots. It is
not a module version, a resolved-variable hash, or `ModuleInstance.qualifiedName`. EP-66
uses it to scope file ownership, EP-68 uses it to select update targets, and EP-69 renders
it only when disambiguation is necessary.

Baseline storage is shared by EP-65, EP-66, and EP-68. EP-65 owns
`Seihou.Effect.BaselineStore`, its real and pure interpreters, the on-disk layout
`.seihou/baselines/<sha256>`, and `Seihou.Engine.ThreeWayMerge`. EP-66 consumes those APIs
to plan and apply files. EP-68 brackets the store with project update orchestration and
prunes only after the new manifest is durable.

File reconciliation is shared by EP-66, EP-68, and EP-69. EP-66 owns the complete
`FileReconciliation` and `ReconciliationPlan` sum types and their apply semantics. EP-68
embeds a `ReconciliationPlan` in `UpdatePlan`; EP-69 renders those variants and maps CLI
conflict choices to EP-66's resolution type rather than inventing a second conflict model.

Command lifecycle is shared by EP-64, EP-67, EP-68, and EP-69. EP-64 reserves the manifest
types. EP-67 owns fingerprint calculation and `CommandPlan`. EP-68 embeds the command plan
and persists successful receipts. EP-69 controls the user-selected policy through
`--run-all-commands` and `--no-commands`.

Remote source acquisition is shared by existing migration/upgrade code and EP-68. EP-68
must extract or reuse `cloneRepo`, origin metadata decoding, registry discovery, and
installed-cache publication from `Seihou.CLI.InstallShared` and
`Seihou.CLI.Migrate`; it must not add a third clone/discovery implementation.

The CLI boundary is shared by EP-68 and EP-69. EP-68 defines all behavior under
`seihou-cli/src/Seihou/CLI/Update.hs` so it is testable through `seihou-cli-test`. EP-69
adds only the trapped `UpdateOpts` parser under `seihou-cli/src-exe/Seihou/CLI/Commands.hs`,
the dispatcher in `seihou-cli/src-exe/Main.hs`, and thin terminal interaction/rendering.


## Progress

- [x] EP-64 M1: Define application/update state and bump the manifest schema with backward decoding.
- [x] EP-64 M2: Record successful module and recipe compositions with per-instance resolved values.
- [x] EP-64 M3: Prove stable identity, legacy fallback, and round-trip behavior with fixtures.
- [ ] EP-65 M1: Add the content-addressed baseline store and pure/real interpreters.
- [ ] EP-65 M2: Add and verify the Git-backed three-way merge engine and conservative fallback.
- [ ] EP-65 M3: Seed and maintain baseline references during ordinary generation.
- [ ] EP-66 M1: Fold generation operations into one desired file state per path.
- [ ] EP-66 M2: Classify automatic merges, true conflicts, and safe/edited orphans.
- [ ] EP-66 M3: Apply resolved file plans with rollback and manifest/baseline updates.
- [ ] EP-67 M1: Preserve command ownership and compute stable rendered-command fingerprints.
- [ ] EP-67 M2: Plan changed-only, run-all, and disabled command policies and persist successes.
- [ ] EP-67 M3: Integrate receipt recording without changing existing `seihou run` run-all behavior.
- [ ] EP-68 M1: Select recorded applications and stage remote candidate module repositories.
- [ ] EP-68 M2: Reuse saved inputs and produce a unified post-migration update plan.
- [ ] EP-68 M3: Apply managed migrations, files, commands, cache, baselines, and manifest with recovery.
- [ ] EP-68 M4: Verify the service against local remotes, duplicate module instances, and failure injection.
- [ ] EP-69 M1: Add `seihou update` parsing, dispatch, human/JSON rendering, and interaction.
- [ ] EP-69 M2: Point status, run, and upgrade guidance at the project-aware workflow.
- [ ] EP-69 M3: Publish CLI/user/design documentation and completion coverage.
- [ ] EP-69 M4: Run full automated gates and the conflict-aware end-to-end update demonstration.


## Surprises & Discoveries

- The current manifest writes a flat `variables` map but `handleRun` resolves variables
  before it reads the manifest and never supplies those values to the resolver. In the live
  project, the manifest records `intentions.enabled = true` while a dry-run against the
  upgraded module resolves the new default `false`. Persistent state therefore exists but
  does not make regeneration reproducible.

- Pending migration detection iterates every `AppliedModule`, while migration execution
  bumps every instance with the same bare module name. The live project contains two
  `exec-plan` instances and prints the same pending `0.5.0 -> 0.7.0` row twice. EP-68 must
  plan migrations per unique module source/version transition, while retaining instance
  identity for variables and files.

- The existing dry-run contract openly computes against pre-migration disk state:

  ```text
  Note: the run plan below is computed against the current (pre-migration)
  disk state. Re-run without --dry-run to apply migrations and regenerate.
  ```

  An honest update plan therefore needs a staged filesystem representation for declarative
  migration operations. Arbitrary migration commands remain non-simulatable and must be
  labeled as such.

- `mergeOperations` already combines patches when a prior in-memory `WriteFileOp` exists,
  but retains separate `PatchFileOp`s when the base is only on disk. The live preview shows
  `.gitignore` four times even though it is one file. EP-66 must execute the ordered patch
  sequence against the stored baseline (or the disk content for a legacy/new file) before
  classifying the path.

- `mori registry search Diff`, `diff3`, `patience`, and `merge` found no registered Haskell
  three-way merge dependency. The local Git 2.54.0 exposes `git merge-file --stdout
  --diff3`, so EP-65 can use a mature available implementation without adding an unverified
  package bound.

- EP-64 confirmed that `executePlan` cannot be the source of file application ownership
  because it returns only physically written records. Ordinary generation must attribute
  the complete composed-operation destination set after written, kept, and unchanged
  records are combined. EP-65 must use the same complete set when seeding baselines so an
  unchanged generated file does not remain baseline-free.

- Recipe-expanded modules are versioned contents of the recipe rather than stable
  application identity. EP-64 stores and hashes only ordered `--module` roots supplied by
  the user alongside the requested recipe target. EP-68 must preserve this distinction
  when it loads a newer recipe and expands its possibly changed module list.


## Decision Log

- Decision: Introduce `seihou update` as the project operation and leave `seihou upgrade`
  as cache-only maintenance.
  Rationale: Mutating the shared installed cache before reconciling the current project is
  the central split-brain problem. A project update needs candidate staging and one success
  boundary; another `upgrade` flag cannot provide that mental model.
  Date: 2026-07-19.

- Decision: Persist applications separately from bare applied modules and key them by the
  requested target plus ordered additional roots.
  Rationale: `AppliedModule` records dependency instances but loses which module or recipe
  the user invoked. Updating a composition and reusing its values requires preserving that
  root and layering order. Resolved values and versions are deliberately excluded from the
  identity so an update replaces the prior application rather than creating a new one.
  Date: 2026-07-19.

- Decision: Keep both a generated baseline reference and an applied disk hash per file.
  Rationale: The baseline is the common ancestor for future three-way merges; the applied
  hash answers whether the user edited the result after the last update. Replacing the
  baseline with merged output would absorb user customization into generated ownership and
  lose it on a later update.
  Date: 2026-07-19.

- Decision: Use `git merge-file --stdout --diff3` as the first merge backend and return a
  conservative conflict if the executable is absent or fails unexpectedly.
  Rationale: Git is already required for installed-module fetch/update flows and provides a
  mature diff3 implementation. Mori found no registered Haskell alternative. Falling back
  to overwrite would violate the safety goal; falling back to a conflict preserves data.
  Date: 2026-07-19.

- Decision: `seihou update` always plans applicable migrations and has no
  `--with-migrations` flag.
  Rationale: A project update that advances templates without advancing declared layout
  migrations is internally inconsistent. The update preview is the consent boundary; users
  who want cache-only behavior retain `seihou upgrade`.
  Date: 2026-07-19.

- Decision: Existing `seihou run` continues to execute every rendered command, while
  `seihou update` defaults to only new or changed fingerprints.
  Rationale: Changing `run` would be a compatibility break for modules that rely on repeated
  setup commands. The new command can adopt the lower-noise policy explicitly and expose
  `--run-all-commands` when repetition is desired.
  Date: 2026-07-19.

- Decision: Delete an orphan automatically only when its disk hash still equals the last
  applied hash; retain and continue tracking edited orphans.
  Rationale: An unchanged obsolete generated file is safe cleanup. Forgetting an edited
  orphan, as the current run path does, silently abandons user data and makes later recovery
  impossible.
  Date: 2026-07-19.

- Decision: Refuse a targeted update when any selected application jointly owns a path
  with an unselected application.
  Rationale: A single combined baseline proves the current generated file but does not
  preserve a separately replayable operation stream for every historical application.
  Overwriting from only the selected composition could erase the unselected contribution.
  Requiring all owners is conservative, explicit, and makes the no-argument whole-project
  update the safe escape hatch.
  Date: 2026-07-19.

- Decision: Keep behavior in the `seihou-cli-internal` library and delay parser/dispatcher
  work until the final ExecPlan.
  Rationale: The existing `handleRun` is executable-only and lacks an end-to-end testable
  core. This initiative should not reproduce that architecture for a more complex workflow.
  Date: 2026-07-19.

- Decision: Decompose the initiative into six child plans with EP-64 as the schema root,
  EP-65/EP-67 as parallel branches, EP-68 as the convergence point, and EP-69 as rollout.
  Rationale: Each plan produces independently verifiable behavior while shared persistent
  interfaces remain owned by one early plan.
  Date: 2026-07-19.

- Decision: Keep recipe-expanded module roots out of `ApplicationId` and
  `AppliedComposition.additionalModules`.
  Rationale: Recipe membership may change when the recipe version changes. Treating those
  expanded roots as identity would append a new application during update; only ordered
  user-supplied `--module` roots represent identity-level layering choices.
  Date: 2026-07-19.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original vision.

EP-64 completed the persistent-state foundation. Version-4 manifests now preserve stable
top-level applications, distinct per-instance values, baseline and command-receipt slots,
and application-scoped file ownership while retaining versions 1-3 and the flat legacy
variable map. Real module and recipe smoke runs demonstrated the recorded target and
provenance, replacement of a repeated application, and ownership of unchanged files. EP-65
and EP-67 can now proceed from the shared schema contract.

Revision note (2026-07-19): Marked EP-64 complete and recorded its operation-derived file
ownership and recipe identity discoveries for EP-65 and EP-68.
