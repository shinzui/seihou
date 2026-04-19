# Run parameterized dependencies once per distinct parent binding

Intention: intention_01kpk82xjve7er8t8f3avfazjp

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Today, when a Seihou composition reaches the same helper module through two
different dependency edges that each supply different variable bindings, Seihou
silently drops one of them. The helper module runs exactly once, with one of
the parent bindings winning arbitrarily, and the user is left with a broken,
partially-applied project.

The concrete reproduction a reviewer can run today, from a fresh scratch
directory and using the existing agent-seihou module registry at
`/Users/shinzui/Keikaku/bokuno/agent-seihou`:

    cd $(mktemp -d)
    seihou run master-plan

The composition resolves to four modules — `claude-gitignore`,
`claude-skill-link`, `exec-plan`, `master-plan`. The `master-plan` module
depends on `exec-plan` (which transitively depends on `claude-skill-link` with
`skill.name = "exec-plan"`) and also directly on `claude-skill-link` with
`skill.name = "master-plan"`. Two distinct `claude-skill-link` invocations are
expected, producing two symlinks:

    .claude/skills/master-plan -> ../../claude/skills/master-plan
    .claude/skills/exec-plan   -> ../../claude/skills/exec-plan

Today only the `master-plan` symlink appears. The generation plan shows a
single `ln -sfn` command, and the `exec-plan` skill — although its `SKILL.md`
and `PLANS.md` files are generated under `claude/skills/exec-plan/` — is not
symlinked into `.claude/skills/` and is therefore invisible to Claude Code.

After this plan lands the same command will produce **both** symlinks, and any
future module that reuses a parameterized helper along multiple edges will do
the right thing automatically. The observable outcomes a reviewer can run:

    cabal test all

must pass (adding new cases for the multi-binding scenario), and

    cd $(mktemp -d) && seihou run master-plan && ls -la .claude/skills/

must show two symlinks, one for `master-plan` and one for `exec-plan`, each
pointing into `claude/skills/<skill>/`.


## Progress

- [x] M1: Introduce a composition-instance type keyed on
      `(ModuleName, ParentVars)` and refactor `loadComposition` to materialise
      one instance per distinct edge decoration.  **Done 2026-04-19** — added
      `ParentVars` (Core.Types) and `ModuleInstance` /
      `qualifiedName` / `stableHash` (Composition.Instance) and
      refactored `loadTransitive` to dedupe by
      `(ModuleName, ParentVars)`.
- [x] M2: Update `collectParentVars` to preserve per-instance bindings (drop
      the `Map.fromListWith Map.union` collapse at
      `seihou-core/src/Seihou/Composition/Resolve.hs:348`) and adjust
      `resolveComposedVariables` / `resolveWithPrompts` to return results keyed
      by instance.  **Done 2026-04-19** — replaced `fromListWith Map.union`
      with `fromList`, changed both resolvers to return
      `Map ModuleInstance (Map VarName ResolvedVar)`, and rewrote
      the visible-exports fold to resolve each dependency edge to
      its exact child instance.
- [x] M3: Update `buildGraph` / `topoSort` in
      `seihou-core/src/Seihou/Composition/Graph.hs` to operate on
      instance keys, so the topo sort produces one entry per instance.
      **Done 2026-04-19** — `CompositionGraph` rekeyed on
      `ModuleInstance`, `buildGraph` dedupes repeated edges so
      identical parent entries count once for in-degree, and
      `topoSort` returns `[ModuleInstance]`.
- [x] M4: Update `compileComposedPlan` in
      `seihou-core/src/Seihou/Composition/Plan.hs` and the call-sites in
      `seihou-cli/src/Seihou/CLI/Run.hs` and `seihou-cli/src/Seihou/CLI/Vars.hs`
      to carry instance identity from resolution through execution.
      **Done 2026-04-19** — `compileComposedPlan` accepts
      `[(ModuleInstance, Module, FilePath, Map VarName VarValue)]`
      and passes `qualifiedName` to `compilePlan` for the
      `ModuleName` slot. CLI `Run.hs` threads instances through
      resolution, planning, and manifest update, and the new
      `executePlan` ownership-map parameter means `FileRecord`s
      attribute correctly per instance. `Vars.hs` merges resolved
      maps for all instances of the target module (a followup can
      add per-instance explain output).
- [x] M5: Extend the manifest schema in
      `seihou-core/src/Seihou/Core/Types.hs` (`AppliedModule`, `Manifest`) to
      record instance identity, and add a migration path so existing
      single-instance manifests still load.  **Done 2026-04-19** — added
      `parentVars :: ParentVars` to `AppliedModule`, bumped
      `currentManifestVersion` 1→2, taught the decoder to default missing
      `parentVars` to `ParentVars mempty`, and added round-trip + v1
      back-compat specs in `Seihou.Manifest.TypesSpec`.
- [x] M6: Expand the `param-dep-parent` / `param-dep-child` fixtures under
      `seihou-core/test/fixtures/` into a diamond that exercises two distinct
      bindings of the same child, and add specs in
      `seihou-core/test/Seihou/Composition/{Graph,Resolve,Plan}Spec.hs` that
      assert two instances appear in the plan.  **Done 2026-04-19** — added
      `multi-instance-helper`, `multi-instance-leaf`, and
      `multi-instance-diamond` fixtures; added instance-aware
      assertions in `GraphSpec`, `ResolveSpec`, `InstanceSpec`, and
      an end-to-end diamond case in
      `Integration.CompositionSpec`. 851 tests total, all green.
- [x] M7: Regression-verify against the agent-seihou master-plan composition
      (the real-world reproduction) and update any plan-view / status
      formatting that needs to disambiguate instances of the same module.
      **Done 2026-04-19** — dry-run and live run both produce
      two `ln -sfn` commands and both symlinks under
      `.claude/skills/`. Manifest records two
      `claude-skill-link` entries with distinct `parentVars`;
      `seihou status` appends bindings inline so the two
      invocations are distinguishable. `executePlan` gained an
      ownership-map parameter so `FileRecord.moduleName` is
      attributed to the producing instance instead of collapsing
      under the primary module.
- [x] M8: Documentation: describe multi-instantiation semantics in
      `docs/user/module-authoring.md` and add a CHANGELOG entry.
      **Done 2026-04-19** — added a "Multi-instantiation"
      subsection to `module-authoring.md` with the
      `claude-skill-link` worked example; added a CHANGELOG entry
      noting the manifest schema bump and the disambiguated
      status output; added a design note at
      `docs/dev/design/proposed/module-instance-identity.md`
      covering the model, pipeline flow, business rules, and
      edge cases.


## Surprises & Discoveries

- 2026-04-19 — Pre-implementation validation against the live codebase
  confirmed the bug via the Purpose reproduction. Dry-run output from
  `seihou run master-plan` in a fresh scratch directory produced exactly
  one `ln -sfn ../../claude/skills/master-plan
  .claude/skills/master-plan` command and no `exec-plan` symlink — the
  `exec-plan` skill files are generated under
  `claude/skills/exec-plan/` but never linked into `.claude/skills/`.
  Saved before-transcript for M7 comparison.

- 2026-04-19 — The plan originally described `Manifest.modules` as
  `Map ModuleName AppliedModule`. The actual declaration at
  `seihou-core/src/Seihou/Core/Types.hs:340` is `modules ::
  [AppliedModule]`, serialised as a JSON array by the `ToJSON Manifest`
  instance at `seihou-core/src/Seihou/Manifest/Types.hs:50`. M5 has been
  rewritten to target the list shape.

- 2026-04-19 — `Manifest/Types.hs` defines `currentManifestVersion = 1`
  and the `FromJSON Manifest` parser refuses any version greater than
  `currentManifestVersion`. A schema-extending change like this plan's
  must bump the constant to 2, extend the parser's back-compat path, and
  add a round-trip fixture for a version-1 manifest. M5 now calls this
  out explicitly.

- 2026-04-19 — `Seihou.Composition.Recipe.expandRecipe` at
  `seihou-core/src/Seihou/Composition/Recipe.hs:18` returns
  `(ModuleName, [ModuleName], Map VarName Text, [VarDecl], [Prompt])`.
  It is the other source of module names feeding `loadComposition`
  besides the CLI's primary/additional list. M1 has been amended to
  explicitly account for recipe-declared modules getting `ParentVars
  mempty`.

- 2026-04-19 — `VarSource.FromParent` (at
  `seihou-core/src/Seihou/Core/Types.hs:300`) carries a `ModuleName`.
  If `qualifiedName` bakes a hash into the stored name, `--explain`
  output for a parent-sourced variable will read `FromParent
  claude-skill-link#a1b2c3d4` which is useless to a human reader. M4
  now splits display from storage: keep the bare `ModuleName` in
  `FromParent`, and only use qualified names where uniqueness is
  actually required (`FileRecord.moduleName`, `PatchFileOp.moduleName`,
  manifest keys).

- 2026-04-19 — The mergeOperations logic at
  `seihou-core/src/Seihou/Composition/Plan.hs:52` deduplicates
  `CreateDirOp` but *not* `RunCommandOp`. After the fix, each
  `claude-skill-link` instance will emit its own `mkdir -p
  .claude/skills` command. This is acceptable (mkdir -p is idempotent)
  and matches what Validation and Acceptance step 2 already allows.


## Decision Log

- Decision: Key composition instances on the exact `Map VarName Text` of
  parent-supplied bindings (the "edge decoration"), not on the fully-resolved
  variable map.
  Rationale: The parent-supplied bindings are what the authoring surface
  already treats as the "instance identity" — the `vars` field of a
  `Dependency` record in `module.dhall`. Using the resolved map would force
  instances to diverge based on downstream choices (CLI overrides, env vars,
  config files) that have nothing to do with "which helper invocation this
  is", producing a different set of instances each run. Edge decoration is
  stable, user-authored, and aligns with the intuition that a parent
  declaring `{ module = "claude-skill-link", vars = [ skill.name = "x" ] }`
  is declaring one specific instance.
  Date: 2026-04-19

- Decision: Deduplicate instances by exact equality of the normalised
  parent-var map, not by module name alone.
  Rationale: Two parents that legitimately want the same child invocation
  (same helper, same bindings) should share one instance to avoid redundant
  file writes, duplicate symlink commands, and spurious manifest churn. A
  normalised `Map VarName Text` (using `Data.Map.Strict`'s `Ord` instance)
  makes this deterministic. Modules with no `depVars` (e.g. the common
  `simpleDep` case) dedupe cleanly under an empty key.
  Date: 2026-04-19

- Decision: Change the composition model rather than adding an explicit
  `instances` keyword to `module.dhall`.
  Rationale: An explicit per-module `instances` syntax would put the burden
  on every author of a reusable helper (claude-skill-link, any future
  symlink/template helper) to anticipate and enumerate their call-sites. The
  natural reading of the existing `dependencies = [ … ]` list is already
  "these invocations". Making the edge carry identity preserves that
  reading, requires no schema change to `module.dhall`, and keeps existing
  single-binding modules working unchanged.
  Date: 2026-04-19

- Decision: When two parents supply overlapping var-sets with different
  values, emit a distinct instance for each rather than erroring.
  Rationale: The user's concrete case is exactly this: `master-plan` supplies
  `skill.name = "master-plan"` and `exec-plan` supplies `skill.name =
  "exec-plan"` to the same helper. Both invocations are legitimate and both
  are needed. Erroring would force authors to hand-write N copies of
  `claude-skill-link-foo` / `claude-skill-link-bar`, which defeats the
  purpose of reusable helpers. The manifest and plan view gain disambiguation
  (see M5, M7) so the user can still see what happened.
  Date: 2026-04-19

- Decision: Extend the manifest schema to record instance identity rather
  than keeping the current `[AppliedModule]` shape as-is.
  Rationale: The current list allows duplicates in principle but the
  rest of the pipeline keys off `AppliedModule.name` alone and
  effectively treats the list as a name-indexed set. That is what
  silently drops a second instance of the same module. Fix: keep the
  list shape (no structural container change), but add a `parentVars
  :: ParentVars` field to each `AppliedModule` so two entries with the
  same `name` and different `parentVars` are both valid and
  distinguishable. Migration: the `FromJSON AppliedModule` parser
  treats a missing `parentVars` key as `ParentVars mempty`, preserving
  existing single-instance manifests. Bump `currentManifestVersion`
  from 1 → 2 so a future reader can reason about the change; the
  version-1 path stays readable via the default-field back-compat in
  the decoder.
  Date: 2026-04-19

- Decision: `qualifiedName` is only used where module names must be
  unique within a composition — `FileRecord.moduleName`,
  `PatchFileOp.moduleName`, and any manifest-level grouping keys.
  User-facing provenance (`VarSource.FromParent ModuleName`, status
  output, `--explain`) keeps the bare `ModuleName` and optionally
  shows the `ParentVars` binding next to it.
  Rationale: A hash suffix like `claude-skill-link#a1b2c3d4` is fine
  as an internal disambiguator but terrible as a displayed identity.
  Readers need to see *which bindings* the invocation has, not an
  opaque hash. Keeping provenance bare-named also avoids cascading
  changes to every log line, status row, and explain-output in the
  CLI.
  Date: 2026-04-19

- Decision: The `stableHash` in `qualifiedName` is computed as the
  first 8 hex characters of SHA-256 over the canonical-serialised
  binding list — `[(VarName, Text)]` sorted ascending by `VarName`,
  concatenated as `name=value` lines joined with `\n`. It is not a
  public identifier and collisions within a single composition are
  the only correctness concern (and are vanishingly unlikely at
  2^32 for the sizes of compositions we expect).
  Rationale: Locking this down avoids subtle drift between the
  planner, the manifest writer, and the remove/diff code paths if
  each re-derives the hash independently.
  Date: 2026-04-19


## Outcomes & Retrospective

**Bug reproduction (before): 2026-04-19** — `seihou run master-plan
--dry-run` in a fresh scratch directory emitted one `ln -sfn
../../claude/skills/master-plan .claude/skills/master-plan` and no
`exec-plan` symlink. Only a single `claude-skill-link` invocation
reached the plan.

**Regression verification (after): 2026-04-19** — the same command,
run against a freshly-built `seihou` binary, produces both
`ln -sfn ../../claude/skills/master-plan .claude/skills/master-plan`
**and** `ln -sfn ../../claude/skills/exec-plan
.claude/skills/exec-plan`. `ls -la .claude/skills/` after a live run
lists both symlinks and each resolves into `claude/skills/<skill>/`
containing the expected `SKILL.md`. A re-run reports `5 unchanged`,
confirming idempotence.

**Acceptance criteria** (from Validation and Acceptance):
1. `cabal test all` passes. **851 tests** total (up from 846
   pre-implementation), including the new `InstanceSpec`,
   multi-instantiation cases in `GraphSpec` / `ResolveSpec`, the
   two-instance round-trip + version-1 back-compat in
   `Manifest.TypesSpec`, and the fixture-driven diamond in
   `Integration.CompositionSpec`.
2. Dry-run shows two `ln -sfn` commands with distinct destinations.
   Verified.
3. Live run leaves both symlinks in `.claude/skills/`. Verified.
4. `seihou status` renders cleanly and disambiguates the two
   `claude-skill-link` invocations via inline
   `[skill.name=…]` annotations. Verified.
5. A regression `haskell-base`-style composition runs unchanged
   because `emptyParentVars` is the only instance of each module
   and `qualifiedName` returns the bare name. The
   `Integration.CompositionSpec` suite covers this path.
6. Manifest back-compat: the `Seihou.Manifest.TypesSpec "decodes a
   version-1 manifest with parentVars defaulting to empty"` case
   exercises a v1 JSON document and asserts it decodes into an
   in-memory `Manifest` whose `AppliedModule.parentVars` is
   empty.

**Notable refinements discovered during implementation:**

- `executePlan` originally attributed every `FileRecord` to a single
  `ModuleName` passed at call time. With two invocations of the same
  helper producing files under different prefixes, that was wrong. M7
  added an ownership-map parameter (defaulting to `Map.empty` so
  single-module callers are unaffected) that `CompileComposedPlan`
  already builds as its merge result. This was not explicit in the
  original M4 scope but falls out naturally once the pipeline carries
  per-instance identity.
- `seihou status` tracked-file rendering would have leaked the
  internal `#<hash>` qualified-name suffix into user-visible output.
  Added a small `displayModuleName` helper that strips it, consistent
  with the Decision Log's "`qualifiedName` is internal" principle.
- `buildGraph` needed to dedupe its edge list: a parent that lists
  `(depModule, depVars)` twice (semantically the same edge) would
  otherwise inflate the in-degree count and mask the child as
  circularly dependent. A `GraphSpec` regression test now covers this.

**Schema change surfaced in the filesystem:** new manifests are
version 2. Old projects continue to load at version 1 and rewrite to
2 on the next run.


## Pre-implementation Validation (2026-04-19)

Before starting implementation, the plan was validated against the
live codebase at the current HEAD:

- Bug reproduction succeeded. `seihou run master-plan --dry-run` in a
  fresh scratch directory, using the agent-seihou registry, produced a
  single `ln -sfn ../../claude/skills/master-plan
  .claude/skills/master-plan` with no corresponding `exec-plan`
  symlink. This matches Purpose.

- All file path, line number, and function signature references in
  Context and Orientation and in the milestone bodies were checked
  against `seihou-core/src/Seihou/Composition/Resolve.hs`,
  `…/Composition/Plan.hs`, `…/Composition/Graph.hs`, `…/Core/Types.hs`,
  and `…/Manifest/Types.hs` and corrected where they were wrong. Four
  substantive corrections were folded into the plan and logged in
  Surprises & Discoveries:
    1. `Manifest.modules` is `[AppliedModule]`, not
       `Map ModuleName AppliedModule`. M5 now preserves the list
       shape and moves disambiguation into each `AppliedModule` via
       `parentVars`.
    2. `currentManifestVersion` must bump from 1 → 2, and the decoder
       must gain a `parentVars` default for version-1 manifests. M5
       now calls this out.
    3. Recipe expansion happens outside `loadComposition` (in
       `Composition/Recipe.hs`) and returns names, not modules. M1
       was amended to state that no changes to `Recipe.hs` are
       required.
    4. `qualifiedName` should not leak into
       `VarSource.FromParent` / `seihou vars --explain`, only into
       manifest-internal keys. M4 was amended and a Decision Log
       entry was added.


---

### Revision notes

- 2026-04-19 — Pre-implementation validation pass against the live
  codebase. Corrected four factual items (manifest shape, schema
  version bump, recipe-expansion scope, provenance surface) and
  added three Decision Log entries covering the manifest container,
  the scope of `qualifiedName`, and the exact construction of
  `stableHash`. Reproduction of the bug was captured before any
  code changes.


## Context and Orientation

Seihou is a scaffolding system that generates project files from a graph of
composable modules. The source tree lives at
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/`. The code is organised
into two Cabal packages:

- `seihou-core/` — pure library: module loading, composition resolution,
  plan compilation, manifest management.
- `seihou-cli/` — the `seihou` executable that wires the library together
  and performs filesystem I/O.

The build entry points are `cabal build all` (also `just build`) and
`cabal test all` (also `just test`). The test suite lives under
`seihou-core/test/` and its fixtures under `seihou-core/test/fixtures/`.
Individual spec modules live under `seihou-core/test/Seihou/<Topic>Spec.hs`.

A **module** is a directory containing a `module.dhall` file and a `files/`
subdirectory. A module declares named variables, generation steps, shell
commands, and zero-or-more dependencies on other modules. A dependency can
optionally supply variable bindings that flow into the child — this is the
"parameterized dependency" feature that this plan fixes.

A **composition** is the transitive closure of a user-requested primary
module plus any additional modules added on the CLI. Loading a composition
today produces a `[(Module, FilePath)]` in topo-sorted order (dependencies
first). The function that does this is `loadComposition` in
`seihou-core/src/Seihou/Composition/Resolve.hs:26`.

The current flow for `seihou run <module>`:

1. `Seihou.Composition.Resolve.loadComposition` walks dependencies and
   returns `[(Module, FilePath)]` in topo-sorted order. Inside it,
   `loadTransitive` (line 291) dedupes by module name via the `Map.member
   name loaded` check at line 298. This is the first place where "one
   instance per name" is baked in.

2. `Seihou.Composition.Resolve.collectParentVars` (line 346) folds the
   dependency edges into a `Map ModuleName (Map VarName (Text, ModuleName))`
   using `Map.fromListWith Map.union` at line 348. `Map.union` is
   left-biased, so when two different parents contribute bindings for the
   same variable in the same child, only one survives. Which one survives
   depends on list order. This is the second place where the
   single-instance assumption is baked in.

3. `Seihou.Composition.Resolve.resolveWithPrompts` (line 104) iterates the
   module list in order, resolving each module's variables exactly once
   using the single parent-var map produced in step 2. The result is a
   `Map ModuleName (Map VarName ResolvedVar)` — one entry per module name.

4. `Seihou.Composition.Plan.compileComposedPlan` (at
   `seihou-core/src/Seihou/Composition/Plan.hs:28`) takes
   `[(Module, FilePath, Map VarName VarValue)]` — one entry per module
   name — and merges operations.

5. `Seihou.CLI.Run` calls `Seihou.Engine.Execute.executePlan` with the
   merged operation list.

6. The manifest, defined by `Manifest` in
   `seihou-core/src/Seihou/Core/Types.hs` and the `AppliedModule` record at
   line 356, records one `AppliedModule` per module name.

The reproduction case lives outside the Seihou repo, in the sibling
registry at `/Users/shinzui/Keikaku/bokuno/agent-seihou/modules/`:

- `master-plan/module.dhall` declares dependencies on `exec-plan` (with
  `skill.name = "exec-plan"`) and `claude-skill-link` (with
  `skill.name = "master-plan"`).
- `exec-plan/module.dhall` declares a dependency on `claude-skill-link`
  with `skill.name = "exec-plan"`.
- `claude-skill-link/module.dhall` has two commands:
  `mkdir -p .claude/skills` and
  `ln -sfn ../../claude/skills/{{skill.name}} .claude/skills/{{skill.name}}`.

Today, running `seihou run master-plan` yields this plan:

    run    mkdir -p .claude/skills
    run    ln -sfn ../../claude/skills/master-plan .claude/skills/master-plan

The `exec-plan` symlink is missing. The cause is step 2 above: both
`master-plan` and `exec-plan` contribute a binding for `skill.name` to
`claude-skill-link`, and `Map.union` keeps whichever is inserted last, here
the `master-plan` binding.

Existing fixtures at `seihou-core/test/fixtures/param-dep-parent/` and
`param-dep-child/` already exercise single-parent parameterisation but not
the multi-parent diamond that triggers this bug. M6 extends them.


## Plan of Work

The work is organised as eight milestones. Each produces a tree that builds
and that leaves the overall test suite at green, by keeping the current
single-instance behaviour intact until the very last steps where it is
replaced wholesale. Intermediate milestones introduce the new types alongside
the old names, letting callers migrate incrementally.


### Milestone 1: Composition-instance type and loader

Introduce a new type that captures the identity of a module invocation
within a composition:

    -- In Seihou.Composition.Graph (or a new Seihou.Composition.Instance module)

    -- | Variables supplied by a dependent module to a specific invocation
    -- of another module. Normalised so that structurally equal sets compare
    -- equal regardless of construction order.
    newtype ParentVars = ParentVars { unParentVars :: Map VarName Text }
      deriving stock (Eq, Ord, Show)

    -- | Identity of a module invocation within a composition.
    data ModuleInstance = ModuleInstance
      { instanceModule :: ModuleName
      , instanceParentVars :: ParentVars
      } deriving stock (Eq, Ord, Show)

Refactor `loadTransitive` in
`seihou-core/src/Seihou/Composition/Resolve.hs` to produce a `Map
ModuleInstance (Module, FilePath)` and to recurse based on a work list of
`(child ModuleInstance, ParentVars derived from parent's depVars)`. Keep
`loadModuleWithDir` unchanged — module-on-disk discovery is still keyed by
name.

At the end of M1, `loadComposition` returns
`[(ModuleInstance, Module, FilePath)]` in topo-sorted order. The primary
module always receives `ParentVars mempty`. Recipe expansion from
`Seihou.Composition.Recipe.expandRecipe` (at
`seihou-core/src/Seihou/Composition/Recipe.hs:18`) continues to return
`(ModuleName, [ModuleName], Map VarName Text, [VarDecl], [Prompt])` —
its outputs are names, not instances. `loadComposition` is what turns
those names into `ModuleInstance` values, giving each recipe-declared
module `ParentVars mempty`. No changes to `Recipe.hs` are needed in M1.

At this milestone, downstream callers are adapted mechanically: they ignore
the new `ModuleInstance` field and continue to use module name as identity.
The test suite still passes.


### Milestone 2: Preserve per-instance parent bindings

Replace `collectParentVars` at line 346 of
`seihou-core/src/Seihou/Composition/Resolve.hs` with a version that keys on
the new `ModuleInstance`:

    collectParentVars
      :: [(ModuleInstance, Module, FilePath)]
      -> Map ModuleInstance (Map VarName (Text, ModuleName))

The `Map.fromListWith Map.union` becomes a plain `Map.fromList` because each
`(ModuleInstance, edgeVars)` pair is already distinct by construction (M1
guarantees one entry per distinct `ParentVars` under the same module name).

Update `resolveComposedVariables` and `resolveWithPrompts` in the same file
to accept `[(ModuleInstance, Module, FilePath)]` and return `Map
ModuleInstance (Map VarName ResolvedVar)`. The per-iteration logic is
unchanged except that lookups use the instance as key. Visible exports still
flow across edges, not across unrelated instances: the `visibleExports`
fold at lines 76–77 and 131–132 changes from

    Map.unions [Map.findWithDefault Map.empty dep allExports | dep <- deps]

to fold over the dependencies of the current module *instance*, resolving
each edge to the exact child instance (same `(depModule, depVars)`) and
looking up its exports.

Add a spec under `seihou-core/test/Seihou/Composition/ResolveSpec.hs` that
asserts two distinct instances of the same module produce two independent
resolved variable maps.


### Milestone 3: Graph and topo sort on instances

Update `seihou-core/src/Seihou/Composition/Graph.hs`:

    data CompositionGraph = CompositionGraph
      { cgModules :: Map ModuleInstance Module
      , cgEdges   :: Map ModuleInstance [ModuleInstance]
      }

`buildGraph` now receives `[(ModuleInstance, Module)]` and computes edges
by mapping each dependency's `(depModule, depVars)` to the corresponding
`ModuleInstance` already present in the instance set.

`topoSort` is unchanged in algorithm but operates on `ModuleInstance`s. Add
a spec under `seihou-core/test/Seihou/Composition/GraphSpec.hs` that
exercises a diamond with two distinct child instances and asserts the topo
order contains both.


### Milestone 4: Carry instance identity through planning

Update `Seihou.Composition.Plan.compileComposedPlan` at
`seihou-core/src/Seihou/Composition/Plan.hs:28` to accept
`[(ModuleInstance, Module, FilePath, Map VarName VarValue)]` and to pass
the instance's qualified name into `compilePlan`'s `ModuleName` slot so that
the `FileRecord.moduleName` and `PatchFileOp.moduleName` fields
disambiguate. Concretely: define

    qualifiedName :: ModuleInstance -> ModuleName
    qualifiedName (ModuleInstance name (ParentVars vs))
      | Map.null vs = name
      | otherwise   = ModuleName (unModuleName name <> "#" <> stableHash vs)

The `stableHash` is an 8-character truncated SHA-256 of the canonical
serialisation of the binding list (see Decision Log entry dated
2026-04-19 for the exact construction). Its purpose is disambiguation
within a single composition, not cross-project stability. Use
`qualifiedName` only where a module name *must* be unique — for
`FileRecord.moduleName`, `PatchFileOp.moduleName`, and any
manifest-level keys where two invocations of the same module must not
collide.

User-facing provenance keeps the bare `ModuleName`. In particular,
`VarSource.FromParent` (at `seihou-core/src/Seihou/Core/Types.hs:300`)
continues to hold the parent module's plain name, not a qualified
one, so `seihou vars --explain` stays readable. Status and preview
surfaces that need to distinguish instances render the `ParentVars`
bindings alongside the plain name (see M7).

`seihou-cli/src/Seihou/CLI/Run.hs` and
`seihou-cli/src/Seihou/CLI/Vars.hs` receive matching signature changes:
each place that previously iterated module names now iterates instances
and threads the `ModuleInstance` through to the planner. The resolved
map produced by `resolveWithPrompts` is now keyed by `ModuleInstance`,
so the triple-building comprehension at `Run.hs:163` changes from

    [ (m, dir, Map.map (.value) (resolved Map.! m.name))
    | (m, dir) <- modulesInOrder
    ]

to

    [ (inst, m, dir, Map.map (.value) (resolved Map.! inst))
    | (inst, m, dir) <- modulesInOrder
    ]

Add a spec under `seihou-core/test/Seihou/Composition/PlanSpec.hs` that
compiles the diamond fixture introduced in M6 and asserts the merged
operation list contains two `ln -sfn` commands with different destinations.


### Milestone 5: Manifest schema with instance identity

Extend `AppliedModule` at
`seihou-core/src/Seihou/Core/Types.hs:356`:

    data AppliedModule = AppliedModule
      { name          :: ModuleName
      , parentVars    :: ParentVars            -- NEW, default = ParentVars mempty
      , source        :: FilePath
      , moduleVersion :: Maybe Text
      , appliedAt     :: UTCTime
      , removal       :: Maybe Removal
      }

The containing `Manifest.modules` stays `[AppliedModule]` (at
`seihou-core/src/Seihou/Core/Types.hs:340`). The list already tolerates
duplicate names structurally — the current bug is that the rest of the
pipeline treated it as name-indexed. Now that each entry carries
`parentVars`, two entries with the same `name` and different
`parentVars` are legitimate and distinguishable. Code that currently
looks up by `name` alone (e.g. `Seihou.Core.Status`,
`Seihou.Engine.Remove`, `Seihou.Engine.Diff`) must change to match on
the `(name, parentVars)` pair.

JSON schema changes, all in
`seihou-core/src/Seihou/Manifest/Types.hs`:

1. Bump `currentManifestVersion` from `1` to `2`.
2. Add `"parentVars"` to the `ToJSON AppliedModule` instance — encode
   `ParentVars (Map VarName Text)` as an object of string→string,
   omitted when empty.
3. In `FromJSON AppliedModule`, parse `parentVars` as
   `Aeson..:? "parentVars" Aeson..!= ParentVars mempty` so version-1
   manifests continue to load with `ParentVars mempty`.
4. The `FromJSON Manifest` parser at `Manifest/Types.hs:57` already
   accepts any version `<= currentManifestVersion`; bumping to 2 is
   the whole change there.
5. Add a `ToJSON`/`FromJSON ParentVars` helper pair (or inline the
   map-of-text encoding) — writing this helper is a prerequisite for
   step 2.

`FileRecord.moduleName` continues to be a `ModuleName` — but is now the
qualified name from M4, so the manifest's `files` map unambiguously
attributes each file to its instance. Remove/diff logic in
`Seihou.Engine.Remove` and `Seihou.Engine.Diff` is updated to carry the
qualified name through when matching files to the `AppliedModule` that
produced them.

Emit a `CompositionWarning` the first time a version-1 manifest is
rewritten as version-2 by a composition that introduces multiple
instances (tells the user their manifest just gained new fields).

Tests:
- Under `seihou-core/test/Seihou/Manifest/TypesSpec.hs`, add a
  round-trip assertion that a manifest with two instances of the same
  module encodes and decodes without loss.
- Add a back-compat fixture: a minimal version-1 manifest JSON that
  decodes to an in-memory `Manifest` whose single `AppliedModule` has
  `parentVars = ParentVars mempty`.


### Milestone 6: Fixtures exercising the diamond

Author three new fixtures under `seihou-core/test/fixtures/`:

- `multi-instance-helper/` — a minimal module with one `skill.name` var
  and one command (`echo {{skill.name}}` to a dest file) so the test can
  assert what ran.
- `multi-instance-leaf/` — depends on `multi-instance-helper` with
  `skill.name = "leaf"`.
- `multi-instance-diamond/` — depends on both `multi-instance-leaf` and
  directly on `multi-instance-helper` with `skill.name = "diamond"`. This
  is the Seihou-side analogue of the agent-seihou master-plan
  reproduction.

Wire these into the existing spec modules (`GraphSpec`, `ResolveSpec`,
`PlanSpec`) so each milestone's new assertion has a real fixture to drive.


### Milestone 7: Regression verification against agent-seihou

With M1–M6 merged and the test suite green, install the freshly-built
`seihou` binary and run the reproduction from Purpose:

    cd $(mktemp -d)
    seihou run master-plan
    ls -la .claude/skills/

Both `master-plan` and `exec-plan` symlinks must be present. The dry-run
output must show two `ln -sfn` commands. Check that
`seihou status` and `seihou diff` both render cleanly with the
new instance-aware manifest (no crashes on repeated module names).

Update any plan-view formatting in `seihou-cli/src/Seihou/CLI/Style.hs`
and `Seihou.Engine.Preview` (`buildPreview`) that currently renders
"(<strategy>, <module>)" suffixes — these need to show the qualified name
or the `ParentVars` when a module appears more than once in the plan, so
the user can tell which invocation is which.

Record any changes to existing behavior that surface during this milestone
in Surprises & Discoveries.


### Milestone 8: Documentation and changelog

Update `docs/user/module-authoring.md` with a new subsection, "Parameterized
dependencies and multi-instantiation," that states: two dependency edges
pointing to the same module with different `vars` produce two distinct
invocations; identical edges dedupe. Show the agent-seihou master-plan
pattern as the worked example.

Add a design note under `docs/dev/design/` explaining the
`ModuleInstance` model and why the identity key is the parent-var binding,
referencing this plan by path.

Add a CHANGELOG entry under `docs/user/CHANGELOG.md` in the
"Unreleased"/next-version section, framing the change as a correctness fix
and noting the manifest schema bump with its back-compat behaviour.


## Concrete Steps

Preliminary — reproduce the bug from a clean tree, so the before/after
contrast is captured in evidence:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal build all
    SCRATCH=$(mktemp -d) && cd "$SCRATCH"
    seihou run master-plan --dry-run 2>&1 | tee /tmp/before.txt
    grep 'ln -sfn' /tmp/before.txt

Expected before the fix: exactly one `ln -sfn` line pointing at
`master-plan`. Save `/tmp/before.txt` for comparison at M7.

Per-milestone, the canonical build/test cycle is:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    just build       # or: cabal build all
    just test        # or: cabal test all

Each milestone lands as its own commit on a branch with an `ExecPlan:`
trailer pointing at `docs/plans/10-parameterized-dep-multi-instantiation.md`.
Commit messages follow Conventional Commits (`feat(composition): …`,
`refactor(manifest): …`, `test(composition): …`).

At M7, re-run the reproduction and capture the diff:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal install exe:seihou --installdir=/tmp/seihou-bin --overwrite-policy=always
    SCRATCH=$(mktemp -d) && cd "$SCRATCH"
    /tmp/seihou-bin/seihou run master-plan --dry-run 2>&1 | tee /tmp/after.txt
    diff /tmp/before.txt /tmp/after.txt

Expected after the fix: the `after.txt` file contains two `ln -sfn` lines —
one for `master-plan` and one for `exec-plan` — and two `run mkdir -p
.claude/skills` lines (or one shared line; both are acceptable so long as
the directory exists before either symlink is created).

Then run the non-dry-run command and verify the filesystem state:

    /tmp/seihou-bin/seihou run master-plan
    ls -la .claude/skills/

Expected output (order may vary):

    lrwxr-xr-x  …  exec-plan   -> ../../claude/skills/exec-plan
    lrwxr-xr-x  …  master-plan -> ../../claude/skills/master-plan


## Validation and Acceptance

The change is accepted when **all** of the following are true:

1. `cabal test all` in
   `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/` passes, with the
   new specs from M2, M3, M4, M5, and M6 included. Report the total test
   count before and after in the Outcomes & Retrospective section.

2. In a fresh scratch directory,
   `seihou run master-plan --dry-run` against the agent-seihou registry
   shows two `ln -sfn` commands with distinct destinations
   (`.claude/skills/master-plan` and `.claude/skills/exec-plan`).

3. In the same scratch directory after `seihou run master-plan` (no
   `--dry-run`), `ls -la .claude/skills/` lists both `master-plan` and
   `exec-plan` as symlinks into `../../claude/skills/<skill>/`, and
   following each symlink reaches a directory containing `SKILL.md`.

4. `seihou status` in the same directory renders without errors and
   shows the `claude-skill-link` module in a form that distinguishes the
   two invocations (either two entries or one entry that lists both
   `ParentVars` bindings).

5. A regression check: running `seihou run haskell-base` (or any
   existing single-instance composition in the fixtures) produces a
   byte-identical result to pre-change, validating that single-binding
   modules are unaffected.

6. Manifest back-compat: loading a manifest generated by the pre-change
   `seihou` against a simple composition succeeds and yields the same
   in-memory structure modulo the default `ParentVars mempty`.


## Idempotence and Recovery

Each milestone leaves the repository buildable and the test suite green.
Milestones M1–M4 introduce the new instance-aware plumbing while preserving
current behaviour for compositions where every module appears once —
existing fixtures and specs continue to pass unchanged, because in those
compositions `ParentVars mempty` is the only instance of each module and
`qualifiedName` returns the plain `ModuleName`.

M5's manifest schema change is the one non-additive step. Its back-compat
path (treating legacy entries as `ParentVars mempty`) is exercised by a
round-trip spec that reads a pre-change manifest fixture and re-serialises
it. If M5 is reverted mid-implementation, the on-disk `.seihou/manifest.json`
for any existing project written by the pre-change code remains readable
because M5 only adds an optional field.

M7's regression against agent-seihou is reproducible: the scratch directory
is disposable and the agent-seihou registry is read-only. If the
post-change output is wrong, roll back M4 or M5 by reverting the specific
commit and re-running `cabal test all` to restore green; the prior milestones
remain intact.


## Interfaces and Dependencies

By the end of M1, `seihou-core/src/Seihou/Composition/Graph.hs` (or a new
`seihou-core/src/Seihou/Composition/Instance.hs`) exposes:

    data ParentVars      = ParentVars { unParentVars :: Map VarName Text }
      deriving stock (Eq, Ord, Show)
    data ModuleInstance  = ModuleInstance
      { instanceModule     :: ModuleName
      , instanceParentVars :: ParentVars
      } deriving stock (Eq, Ord, Show)

    qualifiedName :: ModuleInstance -> ModuleName

By the end of M2, `seihou-core/src/Seihou/Composition/Resolve.hs` exposes:

    loadComposition
      :: [FilePath]
      -> ModuleName
      -> [ModuleName]
      -> IO (Either ModuleLoadError [(ModuleInstance, Module, FilePath)])

    collectParentVars
      :: [(ModuleInstance, Module, FilePath)]
      -> Map ModuleInstance (Map VarName (Text, ModuleName))

    resolveWithPrompts
      :: (Console :> es)
      => [(ModuleInstance, Module, FilePath)]
      -> Map VarName Text
      -> Map Text Text
      -> Text -> Text
      -> Map VarName Text -> Map VarName Text -> Map VarName Text -> Map VarName Text
      -> Eff es (Either [VarError] (Map ModuleInstance (Map VarName ResolvedVar)))

By the end of M4, `seihou-core/src/Seihou/Composition/Plan.hs` exposes:

    compileComposedPlan
      :: [(ModuleInstance, Module, FilePath, Map VarName VarValue)]
      -> IO (Either [Text] ([Operation], [CompositionWarning], Map FilePath ModuleName))

and `seihou-cli/src/Seihou/CLI/Run.hs` passes `ModuleInstance` values
through from resolution into planning and into `executePlan`, using
`qualifiedName` where a `ModuleName` is still expected downstream (e.g.
for `FileRecord.moduleName` and `PatchFileOp` module fields).

By the end of M5, `seihou-core/src/Seihou/Core/Types.hs` exposes:

    data AppliedModule = AppliedModule
      { name          :: ModuleName
      , parentVars    :: ParentVars
      , source        :: FilePath
      , moduleVersion :: Maybe Text
      , appliedAt     :: UTCTime
      , removal       :: Maybe Removal
      }

    data Manifest = Manifest
      { … existing fields …
      , modules :: [AppliedModule]   -- unchanged container shape;
                                     -- disambiguation is now inside
                                     -- each AppliedModule via parentVars
      }

And `seihou-core/src/Seihou/Manifest/Types.hs` exposes:

    currentManifestVersion :: Int  -- bumped from 1 to 2

The existing `Dependency`, `Module`, and `module.dhall` schema are
unchanged — authors continue to write `{ module = …, vars = [ … ] }`
entries exactly as today. The multi-instantiation behaviour falls out of
how Seihou interprets those entries, not from any new authoring syntax.
