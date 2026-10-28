---
id: 112
slug: make-gitignore-line-removal-migrations-predictable-during-managed-updates
title: "Make gitignore line-removal migrations predictable during managed updates"
kind: exec-plan
created_at: 2026-10-27T20:51:42Z
intention: "intention_01m5zj1gk1ed39hwz0byrgqeff"
provenance:
  created_by:
    model: "gpt-6.1-sol"
    harness: "codex-cli"
    at: 2026-10-27T20:51:42Z
---

# Make gitignore line-removal migrations predictable during managed updates

This ExecPlan is a living document. Keep Progress, Surprises & Discoveries, Decision Log,
and Outcomes & Retrospective current. Delivery includes the module producer and the
reporting consumer's friction entry.


## Purpose / Big Picture


A project using an older `nix-haskell-flake` can run `seihou update nix-haskell-flake`
and let Seihou retire the obsolete exact `.envrc` ignore entry as part of the update.
The preview predicts that edit, apply succeeds without manually editing `.gitignore`,
and a repeated preview is stable. Unrelated ignore entries, user edits, saved inputs,
and shared owners survive. Unexpected effects from arbitrary shell migrations still
cause rollback.

The source report is `mori://tan/notification-hub/okf/friction-log/concepts/FRIC-1`.
Its command was `seihou update nix-haskell-flake --json --include-shared-owners`, which
failed with `changed_after_migration_command` despite reporting the same counts:

```text
planned 0 created, 2 updated, 0 deleted; found 0 created, 2 updated, 0 deleted
```

The consumer worked around this by removing the exact `.envrc` line before updating.
Its entry is currently `accepted` and explicitly claims no upstream fix. Finish this
plan by delivering and verifying the product fix, then marking that original entry
`resolved` with evidence that the cause is addressed.

The normal starting state is a recorded application at module 0.34.0, with the obsolete
line still present and ordinary remote-source access. After updating the Seihou executable
through the user's established installation path, run the same public update command.
There is no required pre-edit, manifest repair, transitive-module enumeration, new flag,
or separate migration command. A dry run is an optional review step; ordinary human apply
uses the existing preview and confirmation. JSON mode is the automation equivalent and
must retain the report's successful command shape. Existing shared-owner policy remains
in force; the supplied `--include-shared-owners` authorizes necessary expansion but is
not itself the fix for this defect.


## Progress


- [ ] Milestone 1: declarative exact-line removal is decoded and executes identically in pure staging and real migration, with an early representative update proof.
- [ ] Milestone 2: managed updates preview, apply, roll back, and retry the edit correctly; unexpected shell drift still refuses and names affected paths.
- [ ] Milestone 3: the published module uses the declarative migration, engine/schema/module compatibility and documentation pass, and the untouched consumer replay succeeds.
- [ ] Milestone 4: the delivered executable and public module pass the installed-consumer workflow, and the original FRIC-1 changes from accepted workaround to resolved product fix with versioned evidence.


## Surprises & Discoveries


(None yet.)


## Decision Log


Decision (2026-10-27): add a declarative `RemoveLine` migration operation for exact logical
line removal. Adopt it in the module's existing 0.34.0-to-0.35.0 migration declaration in
a new module release. Preview and apply can then use the same deterministic filesystem
operation. Do not execute arbitrary shell commands during preview, recognize special sed
strings, or weaken exact reconciliation comparison to summary-count equality.

Decision (2026-10-27): remove all exact matching logical lines, without trimming or regex
matching. Preserve every nonmatching line and its existing line terminator. Missing file
or absent match is a no-op and never creates a file. Keep `.envrc.local`, `/.envrc`,
comments, blank lines, whitespace variants, and unrelated co-owner contributions intact.
Reject an empty or multiline requested line rather than turning this into an unrestricted
text transformation language.

Decision (2026-10-27): the new operation preserves unrelated edits instead of requiring
`--force` merely because a file's whole-file hash differs. It may remove the explicitly
authorized matching line only. Protect seeds, validate project-relative paths, reject
unsafe file kinds/links, and include the target in snapshots and rollback. Keep existing
whole-file migration conflict rules for move/delete operations.

Decision (2026-10-27): include producer delivery in this plan. A source-only new constructor
leaves users running the original shell migration. Publish the supporting Seihou release
before the module that needs it and state the minimum CLI version in module guidance.
Do not rewrite immutable old releases or promise that unchanged historical shell commands
can be predicted. Test the historical module to reproduce the defect and a new public
module release to prove the ordinary path; this work does not require adding an update
`--to` flag.

Decision (2026-10-27): retain `changed_after_migration_command` for genuine drift and add
path-level explanation. Equal create/update/delete counts do not imply equal accepted
bytes or metadata. The refusal must identify the changed path and kind of difference
without printing file contents or prescribing the failed retry as a cure.


## Outcomes & Retrospective


(To be filled during implementation.)


## Context and Orientation


A module migration is an ordered set of operations applied when advancing the version
recorded in `.seihou/manifest.json`. Pure staging executes known filesystem operations
against an in-memory file map, so preview can describe their consequences without changing
the project. A reconciliation plan describes the precise generated and retained bytes,
file classifications, observed hashes, and ownership metadata that apply is allowed to
publish. A trusted baseline is the prior generated content stored under
`.seihou/baselines/`; it separates generated changes from user edits.

`seihou-cli/src/Seihou/CLI/Update/Migrations.hs`, in
`planAndStageMigrationsWithSeeds`, snapshots managed files into `PureFS` and executes
migrations using `runFilesystemPure`. `RunCommand` is deliberately mocked as successful
and reported as `MigrationCommandNotSimulated`; it has no simulated file effects.
`migrationTouchedPaths` presently knows move/delete targets, but no text-edit targets.

`seihou-cli/src/Seihou/CLI/Update.hs` stages candidates, materializes the simulated tree,
and plans reconciliation. `applyAcceptedPlan` starts the transaction, runs real migrations,
rebuilds reconciliation with `planActualReconciliation`, reapplies user choices, then
requires exact equality with the accepted plan. A shell edit to `.gitignore` changes that
comparison even when classifications have equal totals. Keep this safety condition.
`transactionTargetPaths`, `observePaths`, and transaction backups must include the new
operation even when reconciliation itself classifies that path as unchanged.

`seihou-core/src/Seihou/Core/Migration.hs` defines the five current `MigrationOp`
constructors. `seihou-core/src/Seihou/Dhall/Eval.hs` decodes them through
`migrationOpDecoder`. Its module evaluator normalizes Dhall and extracts directly rather
than requiring the whole input record to equal the decoder's expected annotation. However,
Dhall's `union` extractor itself compares every remaining alternative with its expected
union. Merely appending a constructor therefore rejects old five-variant declarations,
even through direct extraction. Preserve explicitly supported legacy and extended union
shapes when adding the operation; keep absent-migrations fixtures as well.
`seihou-core/src/Seihou/Engine/Migrate.hs` classifies concrete `MigrationOpInstance`
values, validates paths and protected seeds, executes filesystem effects, and advances
module versions. The real and pure filesystem interpreters provide the common execution
surface. `schema/MigrationOp.dhall` is the public Dhall authoring union in the schema
submodule, owned by `mori://shinzui/seihou-schema/packages/seihou-schema`.

`seihou-cli/src/Seihou/CLI/Migrate.hs` renders standalone `seihou migrate` operations
in human and JSON output and enumerates touched paths for `--commit`. Update it with the
new constructor. `seihou-cli/src/Seihou/CLI/Update/Types.hs` currently represents drift as
`UpdateChangedAfterMigrationCommand ReconciliationSummary ReconciliationSummary`.
`seihou-cli/src/Seihou/CLI/Update/Render.hs` only prints those summaries. Its migration
preview JSON contains module/from/to/step count/containsCommands but no operation detail;
make the exact removal inspectable in normal preview as well as standalone migration help.
`seihou-cli/src/Seihou/CLI/Update/Source.hs` stages fresh remote candidates based on
recorded origins, so tests must control candidate source state rather than assuming that
copying a different installed module pins what update will fetch.

The producer is `mori://shinzui/seihou-modules/templates/nix-haskell-flake`. Within
`mori://shinzui/seihou-modules`, its source is
`modules/haskell/nix-haskell-flake/module.dhall` (artifact URI above owns that path).
At planning time it declares version 0.37.0. It uses a locally declared five-variant
migration union because its main schema import predates migrations. Its 0.34.0-to-0.35.0
edge contains this command:

```sh
if [ -e .gitignore ]; then sed -i.seihoubak '/^\.envrc$/d' .gitignore && rm -f .gitignore.seihoubak; fi
```

The generated steps append ignore entries with `append-line-if-absent`, which never removes
an older contribution by itself. Replace this known cleanup with `RemoveLine` in a new
release; retain the edge window so projects at 0.34.0 still receive it. Use the newly
published canonical migration union as a separate immutable import if necessary, rather
than incidentally upgrading the producer's entire older Module schema. Preserve unrelated
generation behavior and update its registry version and maintained docs through its normal
workflow. No producer change has been made during planning.

The reporting consumer is `mori://tan/notification-hub`, with background in
`mori://tan/notification-hub/plans/109-upgrade-to-keiro-0-22-and-nix-haskell-flake-0-36-0`.
Commit `ef0f4f4c12821d58518b8e2958b5909b775f2895` is a verified pre-update checkpoint:
module 0.34.0, manifest schema 10, `.envrc` in `.gitignore`, and two recorded owners of
that file. The consumer is now migrated, so replay only in a disposable detached worktree.
Its original requested module 0.36.0 remains untouched in its current checkout. A replay
against the new fix-containing release verifies this plan, without pretending that new
release is identical to historical 0.36.0. Mori's indexed registration currently lacks the
friction bundle; use the intended canonical FRIC-1 URI above even if resolution fails.

Relevant ADRs were discovered by filename/heading scan and read for this plan.
[ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md) keeps all
applied-state facts in the manifest and excludes a second lockfile.
[ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md) preserves
co-owner contributions and limits additive exemptions to proven additive generation.
A removal is not a new additive exemption; the supplied shared-owner closure and existing
safety policy remain authoritative.
[ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md)
requires a versioned upgrade for any change in serialized manifest meaning. Adding an
operation need not change the manifest format; keep existing file-hash/baseline semantics
unless implementation proves a persisted semantic change necessary.
[ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md)
requires actionable human rendering and stable cause codes. There is no local ADR yet
covering declarative text migrations; record this policy during implementation.

Mori discovery located the producer and schema sources and the existing Dhall dependency
`mori://dhall-lang/dhall-haskell`. Within that project,
`dhall/src/Dhall/Marshal/Decode.hs` implements the union comparison described above
(artifact-level source URI pending). No new external Haskell dependency or changed bound is
proposed. Reinspect dependency sources through Mori before using unfamiliar APIs. Planning
baseline is installed `seihou v0.11.0.1 (4ade3fb)`; the Seihou tree already contains a
modified schema submodule pointer and the separate plan 111. Preserve both.


## Plan of Work


### Milestone 1: express the edit and prove matching execution


Reproduce the report in an isolated consumer snapshot and a controlled historical producer
candidate before expanding test coverage. The consumer plan identifies producer commit
`2eaba137a2b8c4f425be1a6e59cb0ff9b0d80b42` for module 0.36.0 in
`mori://shinzui/seihou-modules`; verify its contents from Git before use. The consumer
checkpoint and exact candidate must be recorded in the reproduction. Control source fetch
in a test-only local remote or a per-invocation Git URL mapping, preserving the original
manifest origin. Do not alter manifest identity, edit `.gitignore`, or write global Git
configuration to prepare the reproduction. The historical invocation must fail for the
recorded reason, with rollback inspected. An existing workaround-completed checkout is
not a valid negative fixture.

Add `RemoveLine {path, line}` to the schema union, core type, decoder, and migration engine.
Keep a decoder for the exact legacy five-variant shape and one for the extended shape.
At the module-loading extraction boundary, deliberately try the supported shapes instead
of blindly extending a single `union` decoder. Use the extended shape for new authoring;
refuse unsupported constructors rather than ignoring them. Test actual old and new module
expressions through `evalModuleFromFile`, including empty lists, all old constructors,
and a new removal; compiling Haskell alone cannot establish Dhall compatibility.
Represent the classified operation explicitly and run it through the existing Filesystem
effect so staging and real execution share the exact transform. Match logical line payloads
excluding their terminators; preserve all remaining LF/CRLF terminators and final-newline
state. Removing all matching lines from a file produces an empty existing file. Reject
empty or multiline line arguments and unsafe paths with clear errors; missing files and
nonmatching content are no-ops. A directory, symlink, or path escaping through a link
must not be treated as a regular editable file. Seed and managed-to-seed release paths
stay protected.

Use a pure helper for the transform, tested with `.envrc`, `.envrc.local`, duplicate exact
matches, whitespace variants, missing final newline, and LF/CRLF. Do not normalize the
whole file with a generic lines/unlines roundtrip. Update new error renderers exhaustively.
Then use one real-binary update fixture built from the consumer's old shape, with a
candidate that declares the new op. It must preview and apply the edit without shell
execution or preparatory user edits. This early proof checks decoder, staging, actual
execution, and reconciliation together; repair failures before adding the larger matrix.


### Milestone 2: integrate safety, rollback, and useful drift diagnostics


Teach migration path enumeration, stale observations, transaction target selection, result
touched paths, and standalone commit staging about exact line removal. Ensure the staging
snapshot includes declared edit targets that are not already in the managed manifest,
without inventing new ownership records for those files. Preserve absence: materializing
the staged project must not copy back a path the simulation intentionally removed. Keep
original observed hashes separate from the post-migration observations used for comparing
predicted and actual reconciliation.

Retain the current interpretation of generated baseline versus user edits. A real and a
staged removal must produce identical reconciliation decisions under the same trusted
baseline. Do not turn unrelated current-file content into generated baseline data or stamp
it as a fresh generated hash simply to satisfy equality. Where a file is not otherwise
regenerated, record the deterministic edit coherently without claiming ownership it did not
have. Verify that the removed line stays absent on subsequent updates and that baseline
storage, file records, and unrelated user bytes retain their existing semantics. If a
baseline overlay is needed, keep preview changes in the session and publish them only in
the same successful transaction; never rewrite a content-addressed baseline object in place.

Add targeted regressions for an already edited shared `.gitignore`, absent line/file,
untracked-but-declared target, idempotence, seed rejection, unsafe paths, and a later failure
that must restore the edited file, manifest, baselines, and installed candidate cache.
Exercise normal human preview/apply and JSON automation. A targeted removal must not silently
broaden shared-owner selection or reclassify a destructive migration as additive-safe.

Keep exact post-migration equality and planned conflict-choice validation. Extend the drift
error with a sorted set/list of differing paths and human-readable difference categories
(classification, observed content, planned output, or metadata), derived from the two plans.
Retain the machine code and summaries for compatibility. Do not print contents, whole
hashes as user labels, or constructor `show` output. Include a regression where a remaining
arbitrary RunCommand changes bytes but leaves counts equal: it must still fail, name the
path, and roll back. Also retain stale-plan and user-resolution invalidation checks.


### Milestone 3: adopt and publish the supported producer path


Update standalone migration rendering in `seihou-cli/src/Seihou/CLI/Migrate.hs` and managed
update rendering in `seihou-cli/src/Seihou/CLI/Update/Render.hs`. The human preview must
state that it will remove the exact `.envrc` line from `.gitignore`, and JSON migration
data must expose the declarative operation through an additive field without removing
existing fields. Pure edits must not be labelled non-simulatable shell commands. Genuine
shell commands retain that warning and the drift refusal.

Update `docs/user/migrations.md`, `docs/cli/migrate.md`, `docs/cli/update.md`,
`seihou-cli/help/migrations.md`, and `seihou-cli/help/update.md`, plus engineering and user
changelogs. Replace the five-operation enumeration where necessary, show the new Dhall
constructor, define exact matching and no-op behavior, and explain why deterministic edits
should use it. Document the unchanged shell escape hatch and failure recovery. Distill
preview/apply agreement and exact-removal safety into a local ADR; do not migrate the
whole ADR corpus to another convention.

Publish the schema change through `mori://shinzui/seihou-schema` using immutable imports
and computed hashes, update the Seihou submodule and Nix schema pin coherently, and release
the supporting CLI through `agents/skills/release/SKILL.md` when publication is authorized.
Inspect the existing schema pointer before editing so unrelated pending schema work is not
lost or silently bundled. Updating an exported Haskell sum type requires the release
workflow's API-compatibility review. Old migration unions and all five older constructors
must continue decoding; old CLIs are not claimed to support the new constructor.

In `mori://shinzui/seihou-modules/templates/nix-haskell-flake`, replace the sed migration
with the new declarative operation in a new module version, preserve the 0.34.0-to-0.35.0
edge, bump the catalog entry through `seihou registry sync-versions`, and validate it.
Include minimum CLI guidance and regenerate producer-owned docs by its documented command.
Publish the new module after the supporting CLI is usable. Prove a consumer at 0.34.0 can
reach that new release through ordinary update; do not create a new edge only after 0.37.0
that would run too late to fix the original failing transition.


### Milestone 4: deliver and close the report with evidence


Repeat the consumer replay using the executable installed through the user's normal
installation path and the public fix-containing module source. Verify the human command
and the report's JSON command on separate untouched replays. Record the executable path,
version/commit, schema commit/hash, module version/source revision, starting consumer
checkpoint, exit result, resulting diff, and stable follow-up preview. Preserve saved inputs
and both `.gitignore` owners. Required dependency locks and template-generated changes must
be reviewable in the ordinary update; neither `--force` nor manual pre-edits may stand in
for the fix.

The original consumer task requested module 0.36.0. This replay does not authorize advancing
its current main checkout to a later module: use disposable worktrees, and leave its real
application unchanged while amending its friction entry. Once delivery and acceptance pass,
use the bundled friction script against that repository's bundle to change FRIC-1 from
`accepted` to `resolved`, append authorship, and explain that the product fix addressed the
cause. Include exact versions and a canonical reference to this plan. Preserve the original
attempt, rollback evidence, and workaround as history. Validate the bundle and inspect its
index/log diff. Until executable/module publication or installed verification is done,
leave this milestone and the friction closure open.


## Concrete Steps


Work from the Seihou repository. The new intention is recorded in frontmatter; do not
prompt for it again. On first implementation edit, resolve the current runtime model and
append one revision with `agents/skills/exec-plan/record-provenance.ts --mode implement`.
Each implementation commit uses Conventional Commits and both trailers below; in other
repositories use the canonical plan URI instead of a Seihou-relative path.

```text
ExecPlan: docs/plans/112-make-gitignore-line-removal-migrations-predictable-during-managed-updates.md
Intention: intention_01m5zj1gk1ed39hwz0byrgqeff
```

Begin with discovery and source-build identification:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
git status --short
git -C schema status --short
mori registry search seihou-modules
mori registry show shinzui/seihou-modules --full
mori registry docs shinzui/seihou-modules
mori registry show shinzui/seihou-schema --full
cabal build exe:seihou
cabal list-bin exe:seihou
seihou --version
```

Use the paths returned by Mori to inspect producer code and local instructions before
editing other repositories. No new package dependency is proposed. If unfamiliar Dhall
APIs are needed, locate their sources with `mori registry search dhall` and
`mori registry show dhall-lang/dhall-haskell --full`. Verify current registry releases and
upstream tags before choosing any new bounds or pins. Never search the filesystem root
or `/nix/store`.

Prepare the untouched consumer checkpoint, retaining its tracked manifest and baselines:

```bash
seihou_source="$PWD"
fixed_seihou="$(cabal list-bin exe:seihou)"
consumer_root="$(mori path mori://tan/notification-hub)"
replay_parent="$(mktemp -d -t seihou-fric1-replay)"
replay_project="$replay_parent/notification-hub"
git -C "$consumer_root" worktree add --detach "$replay_project" ef0f4f4c12821d58518b8e2958b5909b775f2895
cd "$replay_project"
git status --short
"$fixed_seihou" --version
"$fixed_seihou" update nix-haskell-flake --dry-run --include-shared-owners
"$fixed_seihou" update nix-haskell-flake --json --include-shared-owners
"$fixed_seihou" update nix-haskell-flake --dry-run --json --include-shared-owners
git diff --stat
cd "$seihou_source"
```

Before the fix, use the controlled historical candidate described in Milestone 1; after
publication use the public candidate. Record that distinction and all preparation steps.
The negative run must reproduce `changed_after_migration_command`; the positive apply
must emit `outcome: applied` and exit zero. The subsequent same-candidate preview must
report `alreadyUpToDate: true`, with no migration and no new managed changes. Use a second
disposable checkpoint for human apply so JSON application does not pre-complete that test.
Do not invent `update --to` or use `--force`/manual edits to prepare acceptance.

Run focused tests during development and the full affected suites at the source boundary:

```bash
cabal test seihou-core-test --test-options='--pattern "Seihou.Dhall.MigrationDecoder"'
cabal test seihou-core-test --test-options='--pattern "Seihou.Engine.Migrate"'
cabal test seihou-cli-test --test-options='--pattern "Seihou.CLI.Update"'
cabal build all
cabal test seihou-core-test seihou-cli-test
just audit-cli-docs
nix fmt
nix flake check
git diff --check
```

Expected test-suite outcomes are PASS. Extend
`seihou-core/test/Seihou/Dhall/MigrationDecoderSpec.hs`,
`seihou-core/test/Seihou/Engine/MigrateSpec.hs`,
`seihou-cli/test/Seihou/CLI/UpdateSpec.hs`,
`seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs`, and
`seihou-cli/test/Seihou/CLI/UpdateRenderSpec.hs`; add a standalone migration rendering
regression in the existing `seihou-cli/test/Seihou/CLI/MigrateSpec.hs` where appropriate.
If toolchain commands are absent, use `nix develop --no-write-lock-file -c`.
Record unrelated baseline failures explicitly and keep their gates open rather than
claiming they passed. Do not repair unrelated pending schema/test-stack work by stealth.

From the producer root returned by `mori path mori://shinzui/seihou-modules`, after the
supporting executable/schema are ready, use its documented authoring workflow:

```bash
seihou validate-module modules/haskell/nix-haskell-flake
seihou registry sync-versions
seihou registry validate
seihou extension run okf -- docs --dir . --out okf-docs --force
```

Use the just-built executable explicitly for pre-release checks; repeat with the delivered
installed executable. Freeze actual new schema imports with `dhall freeze` and evaluate
them from the remote source before publication acceptance. Never invent integrity hashes
or hand-edit generated producer docs. Preserve its unrelated work and current branch.

Only after Milestone 4 verification, set `verified_release` to the recorded CLI/module
version pair and run the closure command from Seihou. Resolve the implementing session's
model again; replace the explicit model below if runtime metadata identifies another.

```bash
consumer_root="$(mori path mori://tan/notification-hub)"
bun agents/skills/exec-plan/record-friction.ts update \
  --bundle "$consumer_root/docs/friction-log" --id FRIC-1 --status resolved \
  --resolution "Addressed by $verified_release: the declared exact .envrc ignore-line removal is simulated and applied inside ordinary managed update; untouched consumer replay and stable repeat preview passed. See mori://shinzui/seihou/plans/112-make-gitignore-line-removal-migrations-predictable-during-managed-updates." \
  --change "Replaced the accepted manual pre-edit workaround with verified released-product and installed-consumer evidence." \
  --model gpt-6.1-sol --harness codex-cli
okf validate "$consumer_root/docs/friction-log" --strict \
  --profile "$consumer_root/docs/friction-log/profile.dhall" \
  --profile-enforce --log-enforce
git -C "$consumer_root" diff -- docs/friction-log
```

Do not execute closure during plan creation. Add concise actual acceptance evidence in
the entry body if needed, preserving generated/amended metadata written by the script.


## Validation and Acceptance


From the original consumer shape, with `.envrc` still ignored, the fixed ordinary update
must show and perform the exact removal without `changed_after_migration_command`, manual
preparation, or extra migration flags. The report's JSON command must also succeed without
prompts. A repeated preview against the same candidate must show no pending migrations
and no managed changes. Human preview must disclose the removal even if reconciliation's
file totals do not change. Prove source-build and delivered-install behavior separately;
no source-only or manually repaired consumer counts as final delivery.

The transform must remove all exact `.envrc` lines while preserving `.envrc.local`,
`/.envrc`, comments, all unrelated lines, LF/CRLF, and missing-final-newline behavior.
An absent file stays absent; an absent line causes no write. Stage/apply must agree for
tracked, locally edited, shared, and untracked declared targets. Existing owners and inputs
survive; migration does not promote user edits into generated baselines. Seed and unsafe
path/link cases refuse before file effects. Older Dhall migration union declarations and
modules without migrations still decode.

A failure after line removal must restore the transaction's declared file state, manifest,
baselines, and cache publication state; retry from that restored state must succeed once
the cause is fixed. A stale accepted plan still refuses before mutation. An arbitrary
shell migration that produces an unpredicted byte or classification change must still
roll back even when all summary counts match, and the diagnostic must name the differing
path and useful change category. Conflict choices must not silently authorize newly
different outputs.

The source gate is the affected test suites, complete build, CLI documentation audit,
formatter, flake checks, whitespace checks, schema remote-import evaluation, and producer
validation. The delivery gate is a usable installed CLI and published producer release
proved through the real consumer replay. The closure gate is FRIC-1's resolved product-fix
amendment and strict consumer friction-bundle validation. No persistent notification-hub
database migration or service deployment is required for this tool fix.


## Idempotence and Recovery


Exact line removal is idempotent. It does not recreate missing files, remove partial
matches, or erase unrelated edits. Tests and historical reproductions use temporary
projects and controlled candidate remotes; they do not mutate global Git configuration,
the real installed module cache, or the already upgraded consumer application. An isolated
config/cache used for a check is counted as test infrastructure, not presented as an
end-user adoption step.

Preview remains read-only for project/manifest/baselines and never runs shell migrations.
All declared edit targets must be inside the update transaction, even if no candidate step
would otherwise write them. A failed apply restores its backups and leaves earlier user
edits intact. Arbitrary shell effects outside declared managed targets retain the existing
non-transactional limitation; do not imply the new op makes shell commands reversible.
Retain replay worktrees until their evidence is recorded and remove them only when no
work needs preservation.

Publish schema and module corrections as new immutable commits/releases. Do not rewrite
old module 0.36.0 or its recorded artifact identity. If delivery pauses, keep its milestone
open and leave the original accepted workaround status unchanged. The friction script may
write before validation fails; repair/revalidate that entry rather than creating a second
entry or weakening its profile. Keep original observation and authorship history.


## Interfaces and Dependencies


Add a matching Dhall and Haskell operation in `schema/MigrationOp.dhall` and
`seihou-core/src/Seihou/Core/Migration.hs`:

```dhall
RemoveLine : { path : Text, line : Text }
```

```haskell
RemoveLine {path :: FilePath, line :: Text}
```

Extend `MigrationOpInstance` with a classified exact-removal representation and route it
through the same engine in staging and apply. Keep transformation logic pure, with its
line-ending preservation contract covered directly. Update every path/error/rendering
match that handles migration operations; compiler warnings alone may not find wildcard
matches, so search the constructor consumers explicitly. Maintain existing source-level
conventions for strict fields and record access.

Extend `UpdateChangedAfterMigrationCommand` in
`seihou-cli/src/Seihou/CLI/Update/Types.hs` to carry sorted path-level differences alongside
the two summaries; render them in `Update/Render.hs` while retaining its machine code and
existing JSON fields. Add operation detail to managed preview without removing current
migration summary fields. Do not replace the equality guard with a looser comparator.

The producer and schema are independent deliverables owned by
`mori://shinzui/seihou-modules/templates/nix-haskell-flake` and
`mori://shinzui/seihou-schema/packages/seihou-schema`. Delivery order is schema/engine
compatibility, usable CLI release, producer release, then installed-consumer proof and
FRIC-1 amendment. This is a standalone ExecPlan with no prerequisite MasterPlan or plan-111
dependency. Existing Haskell dependencies suffice; if serialized manifest meaning must
change, revise this plan and follow ADR 0014's versioned upgrade contract rather than
silently altering hashes or ownership semantics.
