---
id: 68
slug: build-a-staged-project-update-service
title: "Build a staged project update service"
kind: exec-plan
created_at: 2026-07-19T16:27:06Z
intention: "intention_01kxxjwvf8e2e8r64feyk6r65b"
master_plan: "docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md"
---

# Build a staged project update service

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, Seihou has a testable library service that performs the entire semantic
work of updating recorded module/recipe applications without exposing parser or terminal
concerns. It selects one or more recorded applications, fetches candidate repositories into
temporary storage, loads the candidate composition, reuses prior per-instance inputs,
deduplicates migrations, simulates declarative migration effects, renders the new
composition, asks EP-66 and EP-67 for file/command plans, and returns one structured
`UpdatePlan`.

Applying an accepted plan recovers any prior interrupted transaction, protects managed
project and installed-cache paths, executes real migrations, revalidates the reconciliation
against post-migration state, applies resolved files, runs the selected commands, publishes
candidate artifacts to the installed cache, writes baselines and the manifest, and completes
the transaction. The shared cache is not changed merely by planning or dry-run.

This plan deliberately stops before adding the public `seihou update` parser. Its behavior
is exercised through `seihou-cli-test` and local-git-remote fixtures. EP-69 adds terminal
interaction and documentation around this service.


## Progress

- [x] M1: Define update selection, request, plan, result, warning, and error types.
- [x] M1: Select recorded applications and provide a safe legacy-manifest seeding path.
- [x] M1: Group origins, clone each source once, and build a validated candidate artifact catalog.
- [x] M2: Resolve candidate compositions with saved per-instance inputs and explicit reconfiguration behavior.
- [x] M2: Deduplicate and stage migration plans, including honest command caveats.
- [x] M2: Produce one unified version/input/migration/file/command `UpdatePlan` without mutating cache or project.
- [x] M3: Apply accepted plans under recovery/rollback protection and revalidate after real migrations.
- [x] M3: Publish installed artifacts, applications, receipts, baselines, and manifest only on success.
- [x] M3: Report limits around arbitrary command side effects and prune unreferenced baselines after durability.
- [x] M4: Add local-remote, multi-instance, recipe, legacy, dry-run, conflict, and failure-injection tests.
- [x] M4: Run all repository gates and record the service-level end-to-end evidence.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- EP-66's journal initially records the files-only reconciliation candidate, but EP-68 adds
  applications, receipts, variables, and recipe state before publication. Recovery therefore
  needed a supported way to replace the expected manifest with the complete final value.

- Installed-cache artifacts and whole directories affected by migrations do not fit EP-66's
  text-file journal. A small service journal inside the same transaction directory can protect
  those byte trees while sharing the final-manifest commit marker and recovery lifecycle.

- Candidate search directories contain copied, name-keyed artifacts and may combine discovery
  concerns. Staleness checks and cache publication must use the original staged artifact
  directory, while independent content hashes must ignore `.git` and `.seihou-origin.json`.

- Recipe-expanded roots are deliberately absent from `AppliedComposition.additionalModules`;
  that field stores only explicit user additions. Planning must load candidate recipe roots
  alongside those explicit additions but keep only the explicit list in the replacement
  record. The candidate also retains the prior `ApplicationId` so an internal recipe change
  replaces the same recorded application.

- Deduplicating shared migrations through `Map.elems` reordered them by key and lost
  dependency order. Stable first-occurrence deduplication preserves the composition's
  dependency-first order while still executing one transition for parameterized instances.


## Decision Log

- Decision: Put update behavior in `seihou-cli-internal`, not in the executable handler or
  `seihou-core`.
  Rationale: Remote origin metadata, registry discovery, installed-cache publication, and
  config/prompt resolution are CLI concerns, while the workflow must remain directly
  testable. The private library is the repository's required home for non-parser CLI logic.
  Date: 2026-07-19.

- Decision: Plan against temporary candidate artifacts and publish the installed cache only
  after managed project work and commands succeed.
  Rationale: Current `upgrade` mutates global cache first and leaves the project behind if a
  later run fails. Candidate staging creates one project success boundary.
  Date: 2026-07-19.

- Decision: Group candidate fetches by origin URL and clone once per source repository.
  Rationale: A composition often contains several modules from one Seihou registry. Cloning
  once is faster and ensures all candidates come from one consistent repository revision.
  Date: 2026-07-19.

- Decision: With no explicit selection, update every recorded application in manifest order;
  legacy manifests with no applications require an explicit target once.
  Rationale: Old manifests do not preserve top-level roots, so guessing an all-applications
  graph is unsafe. An explicit target permits a conservative one-time reconstruction; all
  future no-argument updates then work from recorded applications.
  Date: 2026-07-19.

- Decision: For legacy seeding, reuse a flat manifest variable only when it maps
  unambiguously to one candidate instance; otherwise resolve it normally and surface a
  warning.
  Rationale: The live flat map has `skill.name` shared by several module instances. Copying
  it into every instance would silently choose the wrong destinations. Unique values are a
  useful migration aid; ambiguous values need prompts/defaults or `--var`.
  Date: 2026-07-19.

- Decision: Saved values have update precedence below explicit CLI `--var` and above
  environment/config/default sources; `reconfigure = True` disables saved values.
  Rationale: Updates should reproduce the accepted application despite changed defaults,
  shell environment, or config. Explicit command-line input is intentional. New variables
  absent from saved state continue through normal resolution and may prompt.
  Date: 2026-07-19.

- Decision: Deduplicate migrations by module name, origin, from-version, and to-version,
  while retaining per-instance state for rendering.
  Rationale: Migration execution updates a module's project layout once even when the module
  appears through several parameterized instances. Instance values are still distinct and
  must not be deduplicated.
  Date: 2026-07-19.

- Decision: Simulate declarative migration file operations for planning, but label migration
  shell commands as non-simulatable and re-plan file reconciliation after running them.
  Rationale: A dry-run can truthfully model moves/deletes and pure version bumps. It cannot
  predict arbitrary shell side effects. Re-planning after real commands prevents applying a
  stale file plan; newly introduced conflicts stop and roll back managed paths.
  Date: 2026-07-19.

- Decision: Treat all selected applications as one ordered batch and one managed success
  boundary.
  Rationale: Applications can share dependency instances and files. Updating independently
  could publish half of an interdependent batch. Manifest order preserves prior layering;
  each later application plans against the staged result of earlier ones.
  Date: 2026-07-19.

- Decision: Reject named selections when a selected application jointly owns any path with
  an unselected application.
  Rationale: The manifest has a combined generated baseline but no historical
  per-application operation log. EP-66 cannot safely subtract or replay an unselected
  contribution. The diagnostic lists the other owners and recommends selecting them or
  running the no-argument all-applications update.
  Date: 2026-07-19.

- Decision: Treat identical candidate artifacts/rendered plans as a successful no-op, and
  allow same-version content changes only with an explicit warning in the plan.
  Rationale: Registry repositories can advance because an unrelated artifact changed, so a
  new source revision alone does not imply project work. Conversely, unversioned modules
  and mistakenly unbumped versioned modules can have real content changes; hiding those
  changes would leave no recovery path. The warning preserves PVP/version discipline while
  letting the user reconcile deliberately.
  Date: 2026-07-19.

- Decision: Store service-level directory/cache backups beside EP-66's journal and give both
  journals the same complete expected manifest before publication.
  Rationale: A durable manifest is the single observable commit boundary. Sharing it lets
  recovery distinguish rollback from committed cleanup without inventing a second phase flag.
  Date: 2026-07-19.

- Decision: Use original staged artifact directories for staleness and publication, reserving
  the name-keyed search root only for composition loading.
  Rationale: The original directory is the independently validated/hashable unit and cannot
  be contaminated by another artifact with the same discovery name.
  Date: 2026-07-19.

- Decision: Preserve a recorded recipe application's identity while replacing its expanded
  recipe roots and retaining only explicit additional roots.
  Rationale: Recipe dependency changes are updates to one user-requested application, not new
  top-level applications, and removed dependencies must disappear from active instance state.
  Date: 2026-07-19.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

EP-68 now exposes a renderer-neutral staged update service from `seihou-cli-internal`.
`withProjectUpdate` owns candidate lifetimes; planning selects recorded applications, clones
each origin once, reloads module or recipe candidates, replays per-instance values, stages
migrations in `PureFS`, and combines reconciliation and command plans without publishing the
project or shared cache. Apply rejects stale snapshots and unresolved conflicts, protects
managed files/directories/cache entries, revalidates after real migration commands, and
publishes cache, manifest, receipts, and baselines behind one manifest commit boundary.

The end-to-end fixtures prove byte-identical dry-run behavior, coherent saved-input upgrade,
structured no-op, single-clone multi-artifact discovery, candidate recipe dependency
replacement, explicit legacy seeding, stale-manifest refusal, three-way conflict refusal,
shared parameterized-instance migration deduplication, command-failure rollback, and
cache-publication rollback. `cabal test all` passes 1,308 tests (1,007 core, 285 CLI, 16 OKF
extension); `nix fmt`, `git diff --check`, and `nix flake check` also pass.

Arbitrary migration/module command effects outside managed paths remain intentionally
non-reversible and are represented by structured warnings/errors. EP-69 can now add parsing,
interaction, rendering, commit integration, and user guidance without rebuilding service
semantics in the executable layer.


## Context and Orientation

This is the convergence plan for EP-64 through EP-67. Confirm all four are Complete in
`docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md` and read their
interfaces before editing. Do not substitute older hash-only `DiffResult` or per-file
`ConflictResolution` types for the new application, baseline, reconciliation, and command
contracts.

`seihou-cli/src/Seihou/CLI/InstallShared.hs` owns `OriginInfo`, `readOriginInfo`, `cloneRepo`,
`installModuleDir`, and recursive artifact copying. Despite its name, `installModuleDir`
copies modules, recipes, blueprints, and prompts; this plan updates only module and recipe
targets. Reuse these functions instead of shelling out through the independent clone code in
`seihou-cli/src-exe/Seihou/CLI/Upgrade.hs`.

`seihou-core/src/Seihou/Core/Registry.hs` and `Seihou.Dhall.Eval` discover a cloned source as
a single artifact or multi-artifact registry. A registry may contain new dependencies that
are not installed locally. Candidate discovery therefore needs to expose every module and
recipe in a cloned registry, not only artifacts already present in the manifest.

`seihou-core/src/Seihou/Composition/Resolve.hs` loads compositions from search paths and
returns values keyed by `ModuleInstance`. `resolveWithPrompts` currently accepts global CLI,
environment, and config maps but no per-instance saved layer. Add an explicit saved-value
map to the resolution pipeline at the precedence defined above. `VarSource` needs a
`FromApplication` constructor so diagnostics and input summaries can distinguish reuse from
defaults/config.

`seihou-cli/src/Seihou/CLI/Migrate.hs` has reusable planning concepts but combines fetch,
planning, execution, cache refresh, rendering, and command-line options. The pure planner is
`Seihou.Core.Migration.planMigrationChain`; classification/execution are in
`Seihou.Engine.Migrate`. Extract only shared source-location or migration helpers that make
sense. Do not call `runMigrate` during planning because it may fetch again, mutate the cache,
or execute against the real working tree.

`Seihou.Engine.Migrate.executeMigration` can run against pure Filesystem and Process
interpreters. For staging, snapshot every tracked/touched text path into `PureFS`, classify
the candidate plan, and simulate file operations with migration commands mocked as success
and recorded as warnings. Directory operations need all tracked descendants from the
manifest. Real apply uses the real engine inside EP-66's transaction protection.

The current executable `handleRun` is not a reusable core. Build new update modules under
`seihou-cli/src/Seihou/CLI/Update/` and expose them from the private library. Tests belong in
`seihou-cli/test/Seihou/CLI/UpdateSpec.hs` (and focused sub-specs if useful), registered in
`seihou-cli/seihou-cli.cabal` and `seihou-cli/test/Main.hs`.


## Plan of Work

### Milestone 1: select applications and stage candidate sources

Create `seihou-cli/src/Seihou/CLI/Update/Types.hs` with the service contract. The following
shape is required; fields may be split into focused records to avoid one oversized type:

```haskell
data UpdateSelection
  = AllRecordedApplications
  | NamedUpdateTargets [Text]

data PromptPolicy
  = AllowPrompts
  | ForbidPrompts

data UpdateRequest = UpdateRequest
  { selection :: UpdateSelection
  , varOverrides :: [(Text, Text)]
  , reconfigure :: Bool
  , promptPolicy :: PromptPolicy
  , commandPolicy :: CommandPolicy
  , dryRun :: Bool
  }

data VersionChange = VersionChange
  { name :: Text
  , fromVersion :: Maybe Text
  , toVersion :: Maybe Text
  , sameVersionContentChanged :: Bool
  }

data InputChangeSummary = InputChangeSummary
  { reused :: Int
  , overridden :: Int
  , newlyResolved :: Int
  , removed :: Int
  , ambiguousLegacy :: [VarName]
  }

data UpdatePlan = UpdatePlan
  { applications :: [AppliedComposition]
  , versionChanges :: [VersionChange]
  , inputChanges :: InputChangeSummary
  , migrations :: [PlannedUpdateMigration]
  , reconciliation :: ReconciliationPlan
  , commandPlan :: CommandPlan
  , candidateArtifacts :: [CandidateArtifact]
  , warnings :: [UpdateWarning]
  }

data UpdateResult = UpdateResult
  { updatedApplications :: [ApplicationId]
  , manifest :: Manifest
  , versions :: [VersionChange]
  , fileSummary :: ReconciliationSummary
  , commandSummary :: CommandSummary
  , touchedPaths :: Set FilePath
  }

planProjectUpdate :: UpdateRequest -> IO (Either UpdateError UpdatePlan)
applyProjectUpdate :: UpdatePlan -> IO (Either UpdateError UpdateResult)

withProjectUpdate
  :: UpdateRequest
  -> (Either UpdateError UpdatePlan -> IO a)
  -> IO a
```

`UpdatePlan` may contain temporary candidate paths and is valid only during the bracketed
service call/session that owns those directories. `withProjectUpdate` is the public
lifetime-safe entry point used by EP-69; `planProjectUpdate` is called inside that bracket
and may remain an internal/test-facing helper. Do not serialize a plan for reuse across
processes. Include observed project hashes and candidate source revisions so apply can
detect staleness. `UpdateResult.touchedPaths` is the exact project-relative set eligible for
optional commit integration; callers must not reconstruct it from a whole-worktree diff.

Create `Seihou.CLI.Update.Selection`. AllRecorded selects every recorded composition in
manifest order and errors actionably when `applications` is empty. Named selection first
matches target names; if no target matches a name, select every recorded composition whose
instances contain that bare module. Deduplicate selected application IDs. A missing name is
an error listing available recorded targets.

Before fetching, inspect file ownership for the selected set. If any path record names both
a selected and an unselected application, fail with
`SharedPathRequiresApplications`, listing the path, selected owners, missing owners, and
the safe `seihou update` alternative. Do not silently expand the selection because that
would update targets the user did not request. EP-66 repeats this check at reconciliation
as defense in depth.

For a legacy manifest with no applications, allow exactly one explicit name. Load that
module as a root from the current installed sources, recover only unambiguous flat variables,
and build a provisional `AppliedComposition`. Record warnings for ambiguous/missing values.
Do not write the provisional application during dry-run or a failed update.

Create `Seihou.CLI.Update.Source`. Read origin metadata from each selected target's
`targetSource` and every selected instance source, group by `sourceUrl`, clone once into a
session temp directory, discover/validate every module and recipe, and build a
`CandidateCatalog` keyed by artifact kind/name. Include registry tags and origin metadata
needed to publish later. Copy candidate artifacts into a temporary search root with the
same directory-by-name layout expected by `loadComposition`, or add one tested catalog-based
loader; do not create symlinks whose behavior differs across platforms. Candidate sources
take precedence over installed search paths, which remain a fallback for local/unversioned
artifacts with no origin.

Planning fails before project mutation if a clone cannot provide a previously installed
remote artifact, candidate Dhall evaluation/validation fails, a version is a downgrade, or
two source repositories ambiguously provide the same selected name. A local artifact with
no origin remains at its current source and is included with an explicit no-remote warning.
Hash each discovered candidate artifact independently of its repository revision. If the
artifact, rendered file plan, migration plan, and command fingerprints are all unchanged,
return a structured no-op even if the registry repository revision advanced. If content or
rendered behavior changed while a declared version stayed equal, include
`SameVersionContentChanged` in warnings and continue planning; unversioned sources use the
same content comparison without a version-authoring warning.

### Milestone 2: resolve saved inputs and build one staged plan

Extend the core resolver with a per-instance saved layer:

```haskell
type SavedInstanceValues = Map ModuleInstance (Map VarName Text)
```

Add it as a distinct input to the composed resolution functions. `--var` overrides remain
global and highest priority. For matching instances, saved values are parsed/coerced through
the candidate declaration and then win over environment, local, namespace, context, global,
parent/default/prompt sources. A candidate variable absent from saved state follows the
normal chain. Candidate instances absent from the previous composition have no saved state.
When `reconfigure` is true, pass an empty saved map. Add `FromApplication` provenance and
tests for changed defaults, changed type validation, new/removed variables, new dependency
instances, and explicit overrides.

Refactor `resolveWithPrompts` with an underlying entry point that accepts an explicit prompt
permission rather than consulting the terminal unconditionally; keep the existing wrapper
for current callers. `AllowPrompts` permits existing Console-effect prompts, while
`ForbidPrompts` returns structured missing-variable errors. This makes JSON and non-TTY
planning deterministic and testable even when the process happens to own a TTY.

Load each selected candidate application in manifest order. Recipe targets must rediscover
and expand the candidate recipe from `targetSource`/candidate catalog rather than treating
the prior expanded primary module as the root. Use its ordered additional roots from
EP-64. Build candidate `AppliedComposition` records but do not publish them.

Create `Seihou.CLI.Update.Migrations`. Compare prior instance versions with candidate
module versions and group equal transitions by `(module name, origin URL, from, to)`. Plan
each transition once with `planMigrationChain`. Reject downgrades and conflicting prior
versions for the same unique installed module with a diagnostic rather than picking one.
Apply each declarative migration plan to a staged `PureFS`/manifest in ascending dependency
and version order. Mock `RunCommandInst` as success in staging, retain it in
`PlannedUpdateMigration`, and add `MigrationCommandNotSimulated` to warnings. Pure version
bumps still advance the staged manifest.

Compile candidate compositions against the staged post-migration filesystem state and call
EP-66 materialization/reconciliation for each application in order, feeding the staged
output of one into the next. Merge their actions into one batch `ReconciliationPlan` and
surface any cross-application last-writer warning explicitly. Call EP-67 with the requested
policy and prior receipts. The update default is supplied later by EP-69; the service honors
the request exactly.

Planning and `dryRun = True` must not mutate the real project, `.seihou` manifest/baselines,
or installed cache. It may clone and use system temp storage. `UpdatePlan` summaries count
unique paths and commands, never raw duplicate patch operations.

### Milestone 3: apply with recovery and publish one accepted state

At entry, call EP-66's recovery function. Refuse to continue if a malformed or failed
recovery needs manual attention. Recheck candidate revisions and every observed project
hash; return `UpdatePlanStale` before mutation if they changed.

Begin one update transaction covering all migration source/destination paths, reconciliation
paths, and installed artifact destinations. EP-66's generated-file journal covers managed
text paths. Extend the transaction with byte-for-byte backup/restore of installed artifact
directories and any whole directory touched by a migration MoveDir/DeleteDir. Refuse an
unsafe path before backup. This does not make shell commands reversible.

Execute each real migration plan against the candidate module definition with the real
Filesystem/Process effects, never through `runMigrate`'s fetch/cache wrapper. After migration
commands finish, recompute file materialization and reconciliation against the actual
post-migration tree. If the plan introduces a new unresolved conflict or differs from a
user-resolved action, roll back managed paths and return `UpdateChangedAfterMigrationCommand`
with the new summary. The user can review/retry; do not continue with stale choices.

Apply the resolved reconciliation and execute EP-67's command plan. On command failure,
roll back managed project/cache paths and return the structured command error plus a warning
that earlier arbitrary command side effects may remain. Do not persist candidate receipts.

After all managed files and commands succeed, publish each updated module/recipe candidate
with the shared install primitive while its previous destination remains backed up by the
transaction. Update both legacy `Manifest.modules` and each selected
`AppliedComposition.instances` version/source/value state. Replace selected application
records, finalize successful command receipts, preserve unrelated applications/files, and
write the manifest atomically. Baseline blobs may have been added earlier because they are
immutable; the manifest makes them live.

Only after the new manifest is durable, mark/complete the transaction and prune unreferenced
baselines. A prune failure is a warning in `UpdateResult`. Commit integration is not in this
service plan unless an existing reusable helper can accept the structured touched-path list
without importing executable options; EP-69 may call existing Git helpers after success.

### Milestone 4: exercise the service end to end

Build fixtures entirely inside system temporary directories. Create a local bare or normal
Git repository containing a version-1 module, install it into an isolated XDG config home,
run/construct a version-4 project application, then commit a version-2 candidate with
changed defaults/templates, a non-overlapping user edit, a migration, an unchanged command,
and a new command. Plan and apply through the library service.

Add variants for two parameterized instances of one dependency, a candidate recipe, two
modules from one registry clone, legacy flat-variable recovery, no-argument selection,
conflicting merge, migration command warning/replan, clone failure, command failure, cache
publication failure, and stale plan. Assert source repos are cloned once, dry-run mutates
nothing, failures preserve prior manifest/cache/managed files, and success publishes the
coherent new state.


## Concrete Steps

Run from the repository root:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
cabal test seihou-cli-test
cabal test all
nix fmt
git diff --check
nix flake check
```

The service-level successful fixture should assert an equivalent structured outcome:

```text
version: demo 1.0.0 -> 2.0.0
inputs: 1 reused, 1 newly resolved
migrations: 1 declarative operation
files: 1 automatically merged, 1 updated, 0 conflicts
commands: 1 unchanged skipped, 1 executed
```

The dry-run variant must leave byte-for-byte identical project manifest, installed artifact
directory, and project files. The command-failure variant must restore managed state and
return the warning about non-reversible command side effects.

Every implementation commit must include:

```text
MasterPlan: docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md
ExecPlan: docs/plans/68-build-a-staged-project-update-service.md
Intention: intention_01kxxjwvf8e2e8r64feyk6r65b
```


## Validation and Acceptance

Acceptance requires all of the following:

- named and all-recorded selection use stable application records; legacy no-application
  state requires one explicit target and becomes recorded only on success;
- one remote repository is cloned once even when it supplies several selected modules and a
  recipe; planning never publishes the cache;
- changed candidate defaults do not change saved values; explicit overrides win; new values
  resolve normally; reconfigure ignores all saved values;
- prompt-forbidden requests never read terminal input and return structured missing-variable
  errors; prompt-allowed requests can resolve genuinely new or reconfigured values;
- candidate recipe expansion uses the candidate recipe and can add/remove dependencies;
- repeated parameterized instances preserve separate values while their shared migration
  transition executes once;
- declarative migration moves/deletes appear in the post-migration dry-run, and migration
  commands are explicitly labeled non-simulatable;
- update planning counts one path for repeated patches and invokes the merge/reconciliation
  and command planners from EP-66/EP-67;
- dry-run mutates neither project nor shared cache;
- an identical candidate produces a no-op with no cache/manifest rewrite, while changed
  same-version content is visible and warned rather than silently ignored;
- real migration commands trigger post-command revalidation; a changed/conflicted plan rolls
  back managed state rather than applying stale decisions;
- success publishes matching candidate cache, manifest module/application versions, files,
  baselines, and receipts; failure preserves the prior durable state as specified;
- unreferenced baseline pruning happens only after manifest durability;
- every new behavioral module lives in `seihou-cli/src/`, is directly exercised by
  `seihou-cli-test`, and passes the full gates.


## Idempotence and Recovery

Planning is read-only and repeatable but a returned plan is snapshot-bound; stale plans must
be discarded and recomputed. Temporary clones disappear when their bracket closes. Never
store a reusable plan containing temporary paths in the manifest.

Apply always starts with transaction recovery. If a previous process died before manifest
publication, restore managed project/cache paths and retain the old manifest. If it died
after manifest publication but before cleanup, journal metadata must include the intended
manifest digest so recovery can recognize the committed state and complete cleanup rather
than restoring old files under a new manifest. Define and test this commit marker before
writing apply code.

Baseline blobs are immutable and may safely remain after rollback. Arbitrary shell commands
can have non-reversible effects; return this fact in errors and never claim the whole world
was rolled back. Retry uses saved old manifest state unless the user independently changed
the project, in which case the next plan observes those changes.


## Interfaces and Dependencies

Hard dependencies: EP-64, EP-65, EP-66, and EP-67. This plan must import their checked-in
interfaces and must not introduce another application identity, merge result, file conflict,
or command policy.

Reuse `Seihou.CLI.InstallShared`, `Seihou.Core.Registry`, `Seihou.Dhall.Eval`, composition
loading/resolution/planning, `Seihou.Core.Migration`, `Seihou.Engine.Migrate`, the existing
config/console/process/filesystem effects, and standard temporary-directory support. Use
Mori before selecting or changing any dependency; no new dependency is currently expected.

EP-69 consumes `UpdateSelection`, `UpdateRequest`, `UpdatePlan`, `UpdateResult`, `UpdateError`,
`planProjectUpdate`, and `applyProjectUpdate`. Keep these types renderer-neutral: no ANSI
text, terminal prompts, `Options.Applicative`, or process exits in the service. Provide
structured warnings and summaries so human and JSON renderers do not parse prose.
