---
id: 105
slug: rebuild-checkout-local-symlinks-from-the-manifest-without-upgrading-artifacts
title: "Rebuild checkout-local symlinks from the manifest without upgrading artifacts"
kind: exec-plan
created_at: 2026-10-15T14:48:51Z
intention: "intention_01m500ey4xe2fsk010jcbs3mmt"
provenance:
  created_by:
    model: "gpt-6.1-sol"
    harness: "codex-cli"
    at: 2026-10-15T14:48:51Z
  revisions:
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-15T14:54:05Z
      mode: "other"
      note: "Create six-milestone IR-10 implementation plan after PR validation and merge"
---

# Rebuild checkout-local symlinks from the manifest without upgrading artifacts

This ExecPlan is a living document. Keep Progress, Surprises & Discoveries, Decision Log,
and Outcomes & Retrospective current. Distill durable decisions into docs/adr/ before
marking implementation complete.


## Purpose / Big Picture


A fresh clone should be able to restore its ignored skill directory links with
`seihou sync`, even with no modules installed. The command reads the committed manifest,
creates missing links, repairs incorrect links when safe, and reports its work. It never
upgrades modules, runs migrations or recorded shell commands, changes tracked files, or
rewrites the manifest. `seihou status` explains when a link needs this repair.

This implements [IR-10](../improvement-requests/rebuild-checkout-local-outputs-in-a-fresh-clone.md),
validated and merged through PR #1. The existing IR-9 concerns command receipt ordering
and remains separate. This document plans implementation; no checkout feature has shipped.


## Progress


- [ ] Verify prerequisite plans 99 and 100 are implemented; record their commits and actual schema version.
- [ ] Milestone 1: accept and validate checkout symlink declarations, including old-module compatibility.
- [ ] Milestone 2: persist portable link declarations with ownership and an adjacent manifest upgrade.
- [ ] Milestone 3: observe and safely rebuild links through shared library functions and filesystem effects.
- [ ] Milestone 4: expose manifest-only sync and read-only status diagnostics.
- [ ] Milestone 5: integrate declaration ownership and link operations with run, update, diff, and remove.
- [ ] Milestone 6: prove clean fresh-clone setup, finish documentation, and distill ADRs.


## Surprises & Discoveries


(None during implementation yet.)


## Decision Log


Decision (2026-10-15): use `strategy = "symlink"` with `lifecycle = Some "checkout"`,
initially for directory links only. Omitted lifecycle remains managed. A checkout output
is desired wiring recreated in each working copy; a seed is created once and then belongs
to the project. Require both symlink and checkout together, so an old Seihou fails on the
unknown strategy rather than silently treating the declaration as a managed copy.

Decision (2026-10-15): depend on the declaration and manifest foundations in plans 99 and
100, not the entire seed initiative. They introduce the shared lifecycle field and reserve
schema 8 for seed receipts. Extend them with Checkout and the next schema, expected 9,
instead of implementing an incompatible second lifecycle field or taking their version.
If another semantic version lands first, append one adjacent step after that version and
update this document before coding. Do not renumber existing released schemas.

Decision (2026-10-15): store desired links and ownership in the committed manifest, with
no local receipt file, observed timestamp, content hash, or baseline. Disk inspection is
the source of truth for whether each link is currently correct. Keep command receipts and
IR-9's receipt timing unchanged. Sync never executes recorded commands and has no shell
replay option in this change; this satisfies AC-5 without expanding automatic execution.

Decision (2026-10-15): sync requires a Git working tree and ignored, untracked destinations.
It refuses regular-file and directory collisions, reserved metadata paths, missing sources,
and symlinked ancestors. Incorrect symlinks can be replaced after those checks. Run may
warn for a nonignored destination as IR-10 requests, but sync refuses it. Initial
run before git-init is also supported under an explicit declaration-application policy;
it warns when Git evidence is unavailable and keeps path and collision checks. This makes the
promise to leave tracked files untouched an enforced rule.

Decision (2026-10-15): keep registry adoption outside this repository change. Document the
replacement of link-skill shell with declarative steps and a versioned release procedure;
do not automatically infer links from old shell strings or delete old receipts. Consumers
must apply a declaring module release once before future clones can use sync.


## Outcomes & Retrospective


(To be filled during implementation. Planning and PR validation are complete; the feature
and all six implementation milestones remain unimplemented.)


## Context and Orientation


Seihou is a Haskell scaffolding CLI. A module's `module.dhall` lists file-generation steps
and shell commands; a composition applies a target and its dependencies together. An
application is a recorded composition with an ApplicationId and its resolved module
instances. `.seihou/manifest.json` is the committed record of these applications and their
generated files. A symbolic link is a filesystem entry containing another path; read its
own target rather than reading through it. A dangling link exists even if its target does
not, so ordinary `doesFileExist` is insufficient for detecting collisions.

At planning time, packages are 0.9.0.0, the manifest schema is 7, and `Step` has no lifecycle.
`schema/Step.dhall` describes steps and `schema/Command.dhall` describes commands.
`schema` is a Git submodule belonging to `mori://shinzui/seihou-schema`; upstream master
and the recorded submodule revision were 49ff1e5b353b171b1b52946f478623ee4423ea93.
The upstream tags list was empty and no latest GitHub release existed on 2026-10-15;
there is no version tag to invent. Mori's separate registered schema checkout had an
uncommitted Step.dhall comment edit during planning; preserve it and all unrelated work.
Use the repository submodule for implementation and verify upstream again before pinning.

[Plan 99](99-declare-seed-steps-in-the-module-schema-and-validate-them.md) defines optional
`Step.lifecycle`, `StepLifecycle = Managed | Seed`, missing-field compatibility, validation,
and the schema pin workflow. [Plan 100](100-record-seed-receipts-in-manifest-schema-8.md)
defines `Manifest.seeds`, a schema-8 codec, the adjacent 7-to-8 lossless upgrade, and
seed invariants. Both were entirely unchecked when this plan was written. They are hard
prerequisites, not evidence of existing APIs. A novice must complete those checked-in
plans first if their interfaces are absent. This plan is standalone rather than a child
of MasterPlan 12 and retains its own intention. Plans 101–104 can coexist with this work;
review every added Operation constructor when either series lands. Do not enable seed
behavior or discard seed records as a side effect of checkout implementation.

`seihou-core/src/Seihou/Core/Types.hs` owns Step, Strategy, Operation, Manifest, application
ownership, and capability types. `seihou-core/src/Seihou/Dhall/Eval.hs` decodes steps;
`seihou-core/src/Seihou/Engine/Validate.hs` validates module sources.
`seihou-core/src/Seihou/Engine/Plan.hs` compiles module sources from the installed module's
`files/` directory today. A checkout symlink instead refers to the consuming project's
source path, and must never read a similarly named file from the install cache.
`seihou-core/src/Seihou/Composition/Plan.hs` combines operations and owners.
`seihou-core/src/Seihou/Engine/Execute.hs` produces managed FileRecords.
`seihou-core/src/Seihou/Engine/Reconcile.hs` and
`seihou-core/src/Seihou/Engine/UpdateTransaction.hs` plan and apply updates.
In particular, Reconcile.operationDestination currently returns Nothing for unrecognized
operations; adding a constructor without auditing such matches silently loses outputs.

`seihou-core/src/Seihou/Manifest/Types.hs` owns JSON encoding, version-selected decoding,
and the central minimum-capability mapping. `seihou-core/src/Seihou/Manifest/Upgrade.hs`
owns contiguous adjacent raw-JSON upgrade steps. Lossless means deterministic without
information loss; an upgrade that infers facts from local installations needs explicit
user review. An empty link declaration map is lossless; reconstructing intent from shell
receipts is inference and is excluded.

`seihou-core/src/Seihou/Effect/Filesystem.hs` abstracts disk operations. Its real interpreter
is `seihou-core/src/Seihou/Effect/FilesystemInterp.hs`; its in-memory interpreter is
`seihou-core/src/Seihou/Effect/FilesystemPure.hs`. Neither currently models links.
`seihou-core/src/Seihou/Core/Status.hs` hashes managed files only.
`seihou-cli/src/Seihou/CLI/CommandExecution.hs` skips commands with matching receipts under
RunChangedCommands. It does not inspect command outputs; this is the confirmed fresh-clone
gap. Do not change receipt policy to implement this feature.

The executable adapters are `seihou-cli/src-exe/Seihou/CLI/Commands.hs`,
`seihou-cli/src-exe/Seihou/CLI/Run.hs`,
`seihou-cli/src-exe/Seihou/CLI/Status.hs`,
`seihou-cli/src-exe/Seihou/CLI/Remove.hs`, and `seihou-cli/src-exe/Main.hs`.
Reusable CLI logic belongs under `seihou-cli/src/Seihou/CLI/`, including Update.hs and
StatusRender.hs, rather than inside Main. Cabal exposes new modules and registers tests
in `seihou-core/seihou-core.cabal`, `seihou-cli/seihou-cli.cabal`, and each package's
`test/Main.hs`. `Justfile` runs `cabal build all`, `cabal test all`, and `nix fmt`.

ADR discovery scanned the local docs/adr filenames and headings and inspected `mori show
--full`; docs/adr is not a profiled OKF bundle. Preserve its ordinary Markdown convention.
[ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md) requires
portable project-relative paths, with forward slashes and no machine-local state.
[ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md) forbids a second
applied-state record. [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md)
requires a version advance, capability mapping, adjacent upgrade, malformed-input tests,
and a version-history entry for the new map. [ADR 0013](../adr/0013-status-is-a-bounded-summary-the-manifest-is-the-record.md)
requires bounded human summaries; [ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md)
requires named paths/applications, specific remedies, stable machine codes, and exhaustive
rendering. Read the seed ADR created by plan 99 before extending the lifecycle rationale.
No cross-repository ADR is needed for this design.

The motivating consumer is `mori://shinzui/agent-seihou`, project-relative file
`modules/link-skill/module.dhall` (artifact-level URI pending), whose 0.2.0 source makes
`.claude/skills/<name>` and `.agents/skills/<name>` using shell. Its dependency is
claude-gitignore. The historical keiro transcript in IR-10 describes Seihou 0.6.0.0;
do not present it as a reproduction on the current binary.


## Plan of Work


### Milestone 1: declare directory links and validate their meaning


After prerequisites 99 and 100, extend StepLifecycle with Checkout and Strategy with
Symlink in `seihou-core/src/Seihou/Core/Types.hs`. Extend `schema/Step.dhall` documentation
and defaults, `schema/README.md`, and `Seihou.Dhall.Eval.stepDecoder` and strategyDecoder.
Accept exactly the pair symlink/checkout with no patch. Reject checkout plus byte-writing
strategies, seed/managed plus symlink, unknown lifecycle values, and symlink patches.
Retain when-condition evaluation and substitute placeholders in both src and dest.

Add shared path syntax validation in new
`seihou-core/src/Seihou/Core/Checkout.hs`. Accept nonempty canonical forward-slash relative
paths with no empty, dot, or dot-dot components, absolute/drive/UNC spelling, backslash,
or NUL. Reject source/destination equality or ancestor overlap and either path entering
`.git` or `.seihou`. Validate concrete rendered paths again after variable substitution.
Module validation can validate literal syntax and placeholder structure; only the consuming
project can prove source existence, ignored state, and real filesystem containment.
Skip installed `files/` source-existence checks for symlink steps. A true when condition
produces a CheckoutLinkOp carrying project-relative paths and module instance identity;
false produces no declaration. Do not read or hash the target directory.

Run `cabal test seihou-core-test --test-show-details=direct` with new decoder, validation,
and plan-compilation cases. Acceptance: a module declaring a directory link validates
without a matching installed files/ source; traversal injected through a variable fails
compilation; old modules without lifecycle decode unchanged. Update all Step/Strategy
construction and exhaustive matches, including seed rules from plan 99.


### Milestone 2: version and persist desired links with ownership


Add `CheckoutLinkRecord` and `Manifest.checkoutLinks`, keyed by destination, to
`seihou-core/src/Seihou/Core/Types.hs`. The record holds source plus owners as a map from
ApplicationId to a nonempty set of module instance ModuleNames. Destination is the map
key, not duplicated data. Module instance identity includes the existing qualification
for parameterized dependencies. No generated timestamp, receipt, content hash, baseline,
or absolute path belongs in this record. Extend the helpers in
`seihou-core/src/Seihou/Core/Checkout.hs` to merge agreeing owners, reject different targets
at one destination, and remove only the selected owner's claims.

Extend plan 100's manifest invariants: destination paths cannot overlap managed files,
seeds, or other checkout destinations by equality or ancestry, including byte-writing
operations not yet recorded. Sources may be managed or seeded project directories, but
cannot overlap any checkout destination, which prevents cycles through multiple links.
Reject missing/unknown application owners, duplicate JSON keys, malformed source paths,
and empty owner sets at the new schema. Composition must reject incompatible claims
rather than apply last-writer-wins to a link. Preserve unaffected owners on partial runs.

Add a required `checkoutLinks` object at schema 9, assuming prerequisites have established
8. Add CheckoutLocalOutputs to ManifestCapability and its minimum in
`seihou-core/src/Seihou/Manifest/Types.hs`. Add the lossless 8-to-9 action
AddEmptyCheckoutLinks in `seihou-core/src/Seihou/Manifest/Upgrade.hs`, preserving unrelated
raw JSON. Older schema decoding yields no checkout declarations, retains its original
version, and must not serialize the new field into an old document. Writers producing
links stage all required lossless upgrades and publish only their successful final
manifest. A newer unsupported schema is refused before any filesystem work.

Run `cabal test seihou-core-test --test-show-details=direct`. Acceptance: schema 8 upgrades
to 9 with an empty map; valid declarations round-trip; every malformed/overlapping fixture
fails with a named error; upgrade paths remain contiguous from every supported version.
Extend machine-independence tests and the manifest version history. Do not infer link
records from commands in an older manifest.


### Milestone 3: observe and safely apply checkout link actions


Extend Filesystem and both interpreters to distinguish missing entries, real files,
real directories, and links (including dangling links), read a link's literal target,
and create/remove links without traversing the destination. Extend PureFS with link
state and update all fixtures that construct it positionally. Use the existing directory
and process dependencies after consulting their actual source/documentation through Mori;
if a dependency is not registered, locate its authoritative upstream documentation and
register/acquire its source instead of guessing an API. Do not search the Nix store.

Implement the pure classifier and planner in `Seihou.Core.Checkout`, with observation and
apply orchestration in new `seihou-core/src/Seihou/Engine/Checkout.hs`. Make the caller
select an explicit policy: SyncIgnoredOnly requires Git and ignored destinations;
ApplyDeclaration permits an initial run without Git or with nonignored destinations
after warning, while retaining containment and collision checks. Sync resolves the
project root from Git; run uses its existing generation root. Normalize the root once,
and use fixed argument arrays for read-only Git checks when Git is available.
Use literal Git pathspec handling and NUL-delimited results, so spaces, glob characters,
and leading dashes are data. Inspect indexed tracked paths even if missing on disk; ignore
rules alone do not protect a tracked ignored path. Require the root to be the working-tree
root for SyncIgnoredOnly and refuse sync outside a working tree. Do not read `.envrc`, hooks, or module config to
assemble a sync plan.

All destinations and all ancestors must remain inside the root. Reject symlink ancestors
of source and destination, even when they currently resolve inside it; allow only the
final destination entry to be a link. Sources must be existing real directories. Refuse
reserved metadata, indexed destinations/descendants whenever Git is available, regular
files, real directories, invalid declarations, and inaccessible paths. In SyncIgnoredOnly,
also refuse unavailable Git evidence and nonignored destinations. ApplyDeclaration
returns a warning for absent Git evidence or a nonignored destination; a normal run
already has authority to generate project files, while sync promises no tracked writes. Validate all
records before any mutation. Missing parents may be created only under checked real
ancestors. Parent creation must not change a tracked object. Link text is the relative
path from destination parent to the recorded source (for example
`../../agents/skills/exec-plan`), never an absolute path. A link is correct only when its
literal target is that canonical relative spelling; do not traverse a wrong target.

Classify each entry as create, replace-link, unchanged, or refused. Revalidate each action
immediately before mutation. On a detected changed precondition, stop with a specific
error; never delete a newly appeared regular object or follow a substituted parent. Use
exclusive creation for a missing destination; replacing a link requires a guarded link
operation rather than rename-over-anything. Document the supported single-process working
tree assumption: portable path rechecks do not promise protection against a hostile
concurrent filesystem writer. Do not describe this as a general filesystem sandbox.

Snapshot previous link text and parents created by this attempt in memory. On an apply
failure, restore only entries still matching this attempt's own writes and remove only
its now-empty parents; report any interference instead of overwriting it. Do not persist
a local receipt or sync journal. This rollback covers links, never link targets.

Run core tests with both pure and real temporary filesystems. Acceptance: dangling links
are visible; correct links are unchanged; wrong links are repaired without reading their
target; traversal, symlink-parent, tracked-path, missing-source, metadata, and regular-object
cases preserve sentinel bytes. Inject an ordinary mid-apply failure and verify rollback
and a successful retry. This milestone exposes a working library API before CLI wiring.


### Milestone 4: provide sync and show repairable status


Add reusable `seihou-cli/src/Seihou/CLI/Sync.hs` with planning, execution, and rendering,
and thin `seihou-cli/src-exe/Seihou/CLI/Sync.hs`. Add SyncOpts and the command parser in
`seihou-cli/src-exe/Seihou/CLI/Commands.hs`, dispatch in `seihou-cli/src-exe/Main.hs`, and
Cabal registrations. The initial surface is exactly `seihou sync [--dry-run] [--json]`;
there is no force, upgrade, module-selection, or shell-replay option. Reuse the shared
observer and planner from milestone 3. Do not call discovery, artifact origin resolution,
update planning, migration code, executeCommandPlan, or any manifest writer.

Read the manifest once with its ordinary decoder. On supported older schemas with no
checkout declarations, report zero declarations and explain that a declaring module
release must be applied once; never mine command receipts. A missing, malformed, too old,
or newer unsupported manifest fails before mutation and gives the appropriate run or
explicit manifest-upgrade remedy. Dry-run observes and reports the same ordered actions
without creating even a parent directory. JSON prints one document on stdout with sorted
outputs, stable action/error codes, and created/replaced/unchanged/refused counts; human
progress goes to stderr when needed. Refusals have a nonzero exit code and validate all
records before applying any. Successful empty and already-correct plans exit zero.

Extend `seihou-cli/src-exe/Seihou/CLI/Status.hs` and
`seihou-cli/src/Seihou/CLI/StatusRender.hs` to show a checkout summary from the same
observation data. Show bounded counts and at most ten sorted affected paths, with an
elision count for more. Missing and wrong links name `seihou sync`; unsafe collisions
explain the concrete cause and manual remedy instead of promising sync can fix them.
Status writes nothing and retains its existing reporting exit semantics. Keep existing
artifact checks independent so a missing install cache cannot hide link diagnostics.
`seihou diff` continues to compare managed content and never follows a checkout link.

Run `cabal test seihou-cli-test --test-show-details=direct` and
`cabal run seihou -- sync --help`. Acceptance: parser and renderer tests cover every action
and error, status distinguishes missing/wrong/blocked links, dry-run leaves a complete
filesystem snapshot unchanged, and a manifest with command receipts never produces a
shell invocation through sync. Process tests permit only the fixed read-only Git calls.


### Milestone 5: integrate initial application, evolution, and removal


Update `Seihou.Composition.Plan` to merge CheckoutLinkOp claims and reject ownership and
path conflicts. In `seihou-cli/src-exe/Seihou/CLI/Run.hs`, separate link declarations from
managed generation and command plans. Generate ordinary files first, then observe source
directories and ignored state, build and apply the checked link plan, and publish its
portable declarations with the application ownership. This allows a composition to first
generate `agents/skills/example/SKILL.md` and then link its containing directory. A link
source that is absent from disk and will not be generated is refused before writes; a
planned source must exist as a real directory before its link is created. Do not publish
success declarations for failed link work. Preserve Run's existing command policy and
receipt timing. Warn about nonignored links on run while refusing tracked-object clashes;
sync remains stricter and refuses nonignored destinations.

Audit `Seihou.Engine.Diff`, `Seihou.Engine.Execute`, `Seihou.Engine.Reconcile`,
`Seihou.Engine.UpdateTransaction`, `seihou-cli/src/Seihou/CLI/Update.hs`,
`seihou-cli/src/Seihou/CLI/ManifestCapabilityUpgrade.hs`, and
`seihou-cli/src/Seihou/CLI/UpgradeDiagnosis.hs`. Checkout links never become managed files,
generated baselines, additive-write certificates, or ordinary managed-file orphans.
Update compiles declarations from its selected candidate modules, preserves unselected
owners, refuses changed targets while an unselected owner still claims the old source,
and creates/removes/replaces links through the checked planner. Orphan links lose only
the departing owners. A last-owner link is removed only when it still has the expected
literal target; modified links and real objects survive with an explicit warning. A
transition between managed/seed and checkout at the same path requires explicit manual
resolution in this version, rather than deleting content or silently releasing ownership.

Extend update snapshots, precondition verification, rollback, and recovery journal decoding
for link entries. A failure restores the original link text and manifest bytes, never target
directory bytes. Interrupted recovery must distinguish link and regular-file snapshots and
refuse unsafe parents. Keep compatibility with existing transaction journals; version that
format if needed. This transaction journal is existing update recovery machinery, not a
new record of checkout setup state. Test an update containing only link changes so it is
not incorrectly classified as a no-op.

Extend `seihou-core/src/Seihou/Engine/Remove.hs` and
`seihou-cli/src-exe/Seihou/CLI/Remove.hs` with the same owner-removal rule, independently
of custom shell removal declarations. Last-owner removal unlinks only a matching recorded
link and never traverses or deletes its source. Other owners retain both declaration and
link. Modified entries are left behind and explained while their removed owner's claim
is dropped. Dry-run performs no mutation. Run and update must retain links belonging to
other applications when rewriting the manifest.

Run both core and CLI test suites. Acceptance: a real declaring module run creates both
skill links and a portable manifest; two applications can share an agreeing declaration;
removing one keeps the link, removing the last removes only the link; changing a target
with a surviving disagreeing owner refuses; update failure and recovery preserve previous
links and manifest. Byte-writing and seed regressions remain green.


### Milestone 6: prove a fresh clone and document the workflow


Add `seihou-cli/test/Seihou/CLI/CheckoutSyncE2ESpec.hs`, using the real-binary fixture
pattern in `seihou-cli/test/Seihou/CLI/SharedManifestE2ESpec.hs` and
`seihou-cli/test/Seihou/CLI/TwoDeveloperFixture.hs`. In a temporary repository, generate
and commit a fixture skill, ignore rules, and declarations through a real run. Clone it
into a second directory with a distinct empty HOME/XDG install cache and prove its links
are absent. Put an executable sentinel command receipt in the fixture and prove it is
never executed by sync. Run once with an empty cache and once with a newer declaring
module installed; neither cache affects the outcome. Snapshot every tracked blob, index
entry, and manifest byte before sync, not just git status.

First run dry-run and show would-create without any mutation. Then sync creates both
links, status stops reporting missing links, and `git status --porcelain` stays empty.
A second sync reports zero changes. Delete one link and replace the other with a wrong
link; status diagnoses both and sync repairs them. Test blocked regular files, tracked
ignored paths, malicious manifest paths, sources absent in the clone, symlinked ancestors,
and linked worktrees. No refusal may execute the sentinel or modify tracked bytes. A
non-Git directory fails with an actionable message. Disable symlink creation in one
controlled fixture and prove an actionable unsupported/permission error rather than
silently copying directories. Test on supported macOS and Linux environments.

Write `docs/cli/sync.md`; update `docs/cli/status.md`, `docs/cli/run.md`,
`docs/cli/update.md`, `docs/cli/remove.md`, `docs/cli/manifest.md`,
`docs/user/module-authoring.md`, `docs/user/manifest-upgrade.md`,
`seihou-cli/help/modules.md`, the CLI command reference/navigation that lists status,
and root `CHANGELOG.md`. Explain old shell-only projects need one declaring module
update before cloning, sync's ignored-destination requirement, source availability,
relative links, ownership, and why no receipt marks setup complete. Include a migration
example for the producer at `mori://shinzui/agent-seihou`, project-relative file
`modules/link-skill/module.dhall` (artifact-level URI pending), but do not change or
publish that repository or allocate its release number as part of this plan.

Create a local ADR for the checkout contract using the next unused filesystem ADR number
at implementation time, preserving this repository's naming convention. Summarize how
it extends the lifecycle ADR from plan 99 and ADRs 0001, 0004, and 0014. Document desired
state versus observed state, directory-only links, no shell replay, Git safety checks,
manual transitions, and removal rules. Update ADR 0014's implementation history for the
new schema. Run all acceptance checks below; only then mark IR-10 completed and log the
verified behavior. Until then its status is accepted and planned.


## Concrete Steps


Run commands from the Seihou repository root unless a different working directory is
shown. Start by inspecting local changes and prerequisite progress; never overwrite
unrelated work or create a feature branch by default.

```bash
git status --short
git submodule status
rg -n 'StepLifecycle|checkoutLinks|currentManifestVersion' seihou-core/src
rg -n '^(- \[|##)' docs/plans/99-declare-seed-steps-in-the-module-schema-and-validate-them.md docs/plans/100-record-seed-receipts-in-manifest-schema-8.md
mori registry search seihou-schema
mori registry show shinzui/seihou-schema --full
mori registry docs shinzui/seihou-schema
gh api repos/shinzui/seihou-schema/tags
gh api repos/shinzui/seihou-schema/commits/master --jq .sha
```

Complete missing prerequisite interfaces using their checked-in plans. Before using a
new dependency API, run Mori search/show/docs for its owning project, then read its local
source and check its authoritative release registry and upstream tags before choosing
bounds. No new library dependency is selected by this plan.

Use the schema workflow in plan 99: change the schema submodule, type-check it there,
commit and publish the schema change first, then update its gitlink and
`seihou-cli/src/Seihou/CLI/SchemaVersion.hs` URL/hash and the existing flake input. Never
point the parent repository at an unpublished local-only revision. In the schema submodule:

```bash
cd schema
dhall type --file package.dhall
git diff --check
```

After implementation milestones, return to the Seihou root and run:

```bash
cabal build all
cabal test seihou-core-test --test-show-details=direct
cabal test seihou-cli-test --test-show-details=direct
cabal run seihou -- sync --help
cabal test all --test-show-details=direct
nix fmt
git diff --check
okf validate docs/improvement-requests --profile docs/improvement-requests/profile.dhall --profile-enforce --log-enforce
```

Every build/test command must exit zero. The help lists only dry-run and JSON options
beside standard help. Existing strict OKF validation has missing reviews diagnostics on
nine older requests; do not invent historical reviews to hide them. Run strict validation
too and ensure IR-10 introduces no diagnostic. Run nix formatting when the implementation
is ready and inspect its diff; avoid committing unrelated formatter churn.

Record implementation authorship once at the first plan edit in each session, using the
skill's runtime identity discovery rather than copying this plan's author identity:

```bash
bun agents/skills/exec-plan/record-provenance.ts revision --plan docs/plans/105-rebuild-checkout-local-symlinks-from-the-manifest-without-upgrading-artifacts.md --codex-session-file <current-agent-session-file> --mode implement --note 'Implement checkout link milestone and record validation'
```

Every implementation commit uses a Conventional Commit subject and these trailers; a
schema-submodule commit uses the canonical cross-repository plan reference instead:

```text
ExecPlan: docs/plans/105-rebuild-checkout-local-symlinks-from-the-manifest-without-upgrading-artifacts.md
Intention: intention_01m500ey4xe2fsk010jcbs3mmt
```

```text
ExecPlan: mori://shinzui/seihou/plans/105-rebuild-checkout-local-symlinks-from-the-manifest-without-upgrading-artifacts
Intention: intention_01m500ey4xe2fsk010jcbs3mmt
```


## Validation and Acceptance


IR-10 AC-1 is satisfied by module validation plus the real run fixture: a directory
source under the project creates the declared directory link, and the manifest contains
only portable source/destination paths plus ownership metadata, not machine-local paths
or observed-state receipts. Old declarations remain compatible, invalid pairs and
rendered traversal fail, and a generated source directory can be linked in the same run.

AC-2 and AC-3 are satisfied by CheckoutSyncE2ESpec's second clone. It starts with missing
ignored links, an unchanged committed manifest, and an empty cache. Dry-run leaves it
identical; sync creates the links; a second sync changes nothing. The test compares tracked
bytes, index state, manifest bytes, and empty porcelain output. Repeat with a newer module
installed to prove sync does not resolve upgrades. Assertions on Git status alone are
insufficient because a command could write a file then restore it.

AC-4 is satisfied by status rendering and real observation: missing and wrong-target
links are reported with `seihou sync`; blocked objects get their own named refusal.
Over ten affected paths produce a bounded summary. Status does not rewrite any file.

AC-5 is satisfied by sentinel and process-effect tests: no recorded command executes in
dry-run, sync, status, or failure paths. There is no shell replay flag in this version.
Only explicit fixed-argument read-only Git checks are allowed in sync's process trace.

A manual fixture can be created in a temporary Git working tree after installing the
modified binary. Commit `agents/skills/example/SKILL.md` and ignore `.claude/skills/`.
Apply a local module with this declaration and commit the resulting manifest:

```dhall
S.Step::{
, strategy = "symlink"
, src = "agents/skills/example"
, dest = ".claude/skills/example"
, lifecycle = Some "checkout"
}
```

Use an absolute path to the built binary (obtained by `cabal list-bin exe:seihou` from the
Seihou repository) when invoking it in a different project. In a fresh clone of the
fixture, run the binary with `status`, `sync --dry-run`, `sync --json`, `sync`, and
`status`. JSON must report one created output on the first apply; the second apply must
report zero created and replaced outputs and one unchanged output. `readlink
.claude/skills/example` prints `../../agents/skills/example`, and `git status --porcelain`
prints nothing. The committed source directory remains untouched after remove.

Update and removal acceptance includes agreeing co-owners, parameterized instances,
last-owner cleanup, modified-link preservation, source-directory preservation, refusal
of incompatible managed/seed transitions, a link-only update, and failed/interrupted
update recovery. Run full tests once after integration; repeat only when later edits or
failures justify it. Preserve evidence in Progress and Outcomes when implementation runs.


## Idempotence and Recovery


Sync's correctness comes from inspecting current entries every time, not from recording
completion. Repeated runs do not touch a correct link or the manifest. A deleted link is
recreated next time. A blocked object must be manually moved aside or the declaration
corrected through an ordinary module application; no force mode deletes it. When source
files are absent, restore the committed source first. Do not fetch a module to manufacture
missing source bytes during sync.

Plan all outputs before applying and keep the in-memory rollback described in milestone
3. A process killed during sync may leave a subset of correct ignored links and empty
parents; it cannot need a manifest repair because sync writes no manifest. Re-run sync
to converge. For run/update/remove, retain their existing failure semantics while adding
checked link actions; update's persistent recovery machinery must also snapshot links.
Never claim that general shell commands in a normal run can be rolled back by this feature.

Schema changes are additive, versioned, and lossless for prior schemas. Sync cannot write
an automatic schema upgrade. A legacy path-based manifest requires the existing explicit
`seihou manifest upgrade` first; no inference is permitted during checkout setup. Keep
older-version fixtures and rejection tests. Do not reset another contributor's schema
changes or alter the unrelated IR-9 while retrying this plan.


## Interfaces and Dependencies


The new domain types belong in `seihou-core/src/Seihou/Core/Types.hs`. In addition to
Checkout, Symlink, CheckoutLinkOp, and Manifest.checkoutLinks, use the following contract
(the concrete record field spelling may follow surrounding conventions):

```haskell
data CheckoutLinkRecord = CheckoutLinkRecord
  { source :: !FilePath
  , owners :: !(Map ApplicationId (Set ModuleName))
  }
```

`seihou-core/src/Seihou/Core/Checkout.hs` exports validation, ownership merge/drop, and a
pure plan from declarations and observations. An observation records an entry's own
kind/target, source-directory existence, ancestor safety, tracked state, and ignored
state. Actions carry preconditions and the expected relative link text. Errors carry
paths and structured causes rather than rendered strings. Use an interface equivalent to:

```haskell
validateCheckoutPaths :: FilePath -> FilePath -> Either CheckoutError ()
planCheckoutLinks :: CheckoutPolicy
                  -> Map FilePath CheckoutLinkRecord
                  -> Map FilePath CheckoutObservation
                  -> Either [CheckoutError] [CheckoutAction]
```

`seihou-core/src/Seihou/Engine/Checkout.hs` observes and applies those plans through
Filesystem and fixed read-only Git checks through Process. Revalidate preconditions on
apply under the same explicit policy and return structured action results. Sync always
chooses SyncIgnoredOnly; it cannot inherit the normal run policy from configuration.
Neither operation accepts a command receipt,
module search path, migration plan, artifact resolver, or ManifestStore writer.
`seihou-cli/src/Seihou/CLI/Sync.hs` renders results exhaustively with stable JSON action
codes `created`, `replaced`, `unchanged`, and `refused`. Name each concrete refusal such
as `checkout_path_tracked`, `checkout_parent_symlink`, or `checkout_source_missing` and
provide a cause-specific remedy. Status consumes observations, not sync's rendered text.

Use existing Haskell directory, filepath, process, Effectful, Aeson, and test dependencies;
verify the APIs from source before implementation. No bounds/pins other than the schema
publication workflow are chosen here. Repository integration includes cabal modules,
all Operation matches, manifest construction sites, schema upgrades, and the shared
real-binary test harness. Producer adoption in `mori://shinzui/agent-seihou` remains a
separate release after this contract is implemented and verified.

Revision note (2026-10-15): Created after validating and merging PR #1 as IR-10. The plan
preserves the existing IR-9, sequences seed declaration/schema foundations first, and
makes checkout rebuilding a manifest-only operation with observable fresh-clone proof.
