---
id: 123
slug: keep-saved-inputs-when-a-release-changes-a-dependency-s-bindings
title: "Keep saved inputs when a release changes a dependency's bindings"
kind: exec-plan
created_at: 2026-11-11T13:53:55Z
intention: "intention_01m75e5s06e88a4vzm3r5qwyd6"
provenance:
  created_by:
    model: "claude-opus-5-5"
    harness: "claude-code"
    at: 2026-11-11T13:53:55Z
  revisions:
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-11-12T03:33:24Z
      mode: "implement"
      note: "Implement instance alignment and validate the public update workflow"
---

# Keep saved inputs when a release changes a dependency's bindings

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

This plan implements [IR-15](../improvement-requests/keep-saved-inputs-when-a-release-changes-dependency-bindings.md),
which was raised from `mori://shinzui/seihou-modules/okf/friction-log/concepts/FRIC-10`.


## Purpose / Big Picture

A module author sometimes releases a new version of a module that changes the variable
bindings on one of its dependency edges. For example, a parent module's release 1.1.0 adds
`child.extra=x` to its existing `child` dependency. Today `seihou update parent` treats
the `child` instance as new. It finds none of the inputs the project saved for `child`, so
it either fails on a required variable the project already answered, or, once that value is
supplied with `--var`, quietly puts every optional input back to its default. The second
case changes the project's generated files with no warning. The JSON output also reports
the child as `"from": null`, as if it had never been applied.

After this change, `seihou update parent` recognises that the recorded `child` instance and
the candidate `child` instance are the same invocation with new bindings. This plan calls
that a *rebinding*. The update carries the saved inputs across, lets the new edge's
bindings win only for the variables they set, reports the rebinding in the human preview
and in `--json` output, and reports the child's real prior version. When seihou cannot tell
which recorded instance became which candidate instance, it refuses with a diagnostic that
names the module and both sets of bindings, and changes nothing.

To see it working, apply a parent at 1.0.0 with `child.opt=custom`, release a parent 1.1.0
that adds a binding to the `child` edge, and run `seihou update parent --json`. The command
succeeds without `--var`, the manifest still records `child.opt=custom`, and the output
contains a `rebindings` entry for `child`. The unchanged child version is omitted
from version changes; if the child also advances, its real prior version is shown.


## Progress

- [x] Milestone 1 (2026-11-11; seven alignment tests passed): the alignment of recorded and candidate instances exists as a pure,
  unit-tested library function (`Seihou.CLI.Update.Rebinding`). Its unit tests cover an
  exact match, a 1:1 rebinding, deliberate multi-instantiation, an ambiguous pair, and
  the carried-value precedence rules.
- [x] Milestone 2 (2026-11-11; E2E and migration staging coverage passed): `seihou update` uses the alignment for saved values, origins, version
  evidence, migrations, and input counting. It refuses an ambiguous match with
  `ambiguous_instance_rebinding`, and its variable errors name a changed edge. The
  reproduction end-to-end test passes, `update` no longer exits 1 and no longer loses
  `child.opt`.
- [x] Milestone 3 (2026-11-11; 1,009 CLI tests, flake checks, docs audit passed): the rebinding is shown in the human preview, in plan and applied
  `--json` output, and in renderer coverage tests. User documentation, the user
  changelog, and a new ADR are written, and the full `seihou-cli-test` suite passes.


## Surprises & Discoveries

- The public-command reproduction failed against the unchanged source with
  `variable_errors` naming the already-saved `project.name`. The same workflow
  passes after alignment, including add/change/remove and CLI override cases.
- Migration staging also occurs while certifying selection ownership, before the
  final planning call. Both call sites now consume the same aligned priors.


## Decision Log

- Decision: Pair a recorded instance with a candidate instance only when, within one
  application and for one module name, exactly one candidate instance has no exact
  recorded match and exactly one recorded instance has no exact candidate match. Any
  other non-empty imbalance of unmatched instances for the module (2 and 2, 1 and 2, 2
  and 1) is ambiguous and refuses.
  Rationale: IR-15 asks for this rule and asks never to guess. A heuristic that compares
  binding subsets could pair several instances, but a wrong pairing silently moves one
  invocation's inputs onto another, which is the failure this plan exists to remove.
  One unmatched candidate with no unmatched recorded instance is a new invocation, and
  one unmatched recorded instance with no candidate is a removed invocation, as today.
  Date: 2026-11-11

- Decision: When carrying a rebound instance's saved values, drop every variable that the
  new edge binds. Also drop a variable that the old edge bound when its saved value
  still equals the old binding's value. Carry everything else unchanged.
  Rationale: Saved values outrank parent bindings in
  `Seihou.Core.Variable.resolveVariablesWithSources` (CLI, then saved, then environment
  and configuration, then parent bindings, then defaults). Without the first rule, an old
  saved value would beat the new binding. The manifest's `resolvedVars` stores every
  resolved value, including values that came from the old edge. Without the second rule,
  a release that removes a binding would freeze the old bound value as if the project
  had chosen it. A saved value that differs from the old binding came from a higher
  source, such as `--var` or configuration, so it is a project choice and is kept.
  Date: 2026-11-11

- Decision: `--reconfigure` is the escape hatch for an ambiguous match. Under
  `--reconfigure` an ambiguous module's unmatched candidates are treated as new
  instances (no saved values, no prior version), and the preview names them as
  rebindings that could not be paired. Without `--reconfigure` the update refuses.
  Rationale: `--reconfigure` already discards saved values, so pairing changes nothing
  about inputs, and a project must not be left unable to update. The refusal message
  leads with this remedy, as
  [ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md)
  requires.
  Date: 2026-11-11

- Decision: Rebinding is computed at plan time from the manifest and the candidate. It
  is not recorded in the manifest, and the manifest schema does not change.
  Rationale: After the update the manifest simply records the instance under its new
  parent vars, which is the existing representation. Nothing new about applied state
  needs to be stored, so
  [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md)
  does not require a schema step.
  Date: 2026-11-11

- Decision: A release-time `seihou validate-module` warning is out of scope.
  Rationale: IR-15 leaves it open, and the validator cannot see the prior release on its
  own. Fixing update makes the warning unnecessary for safety.
  Date: 2026-11-11


## Outcomes & Retrospective

Implemented all three milestones. A source-built `seihou` 0.15.0.0 based on
commit `dcd776c` was driven from isolated projects with empty HOME/XDG caches.
The ordinary workflow is `seihou run demo --var project.name=demo --var
child.opt=custom`, followed, after changing the producer's edge, by `seihou update
demo` and confirming its preview on a terminal (`--json` applies in the
noninteractive E2E harness). No adoption command, cache repair, manifest edit or repeated required input
is needed. Human and JSON previews are immutable; applied JSON carries the same
rebinding evidence. Added/changed/removed bindings preserve project choices,
CLI overrides still win, and a repeated update preserves manifest bytes.
Ambiguous multi-instantiation refuses before effects and succeeds with the
advertised `--reconfigure --var project.name=demo` recovery.

Validation: the reproduction failed on the unchanged implementation with the
saved-required-input error. Seven alignment tests and three E2E scenarios then
passed. The complete `seihou-cli-test` suite passed all 1,009 tests, including
renderer coverage and parameterized migration staging with a rebound invocation.
`nix flake check --no-write-lock-file` passed all four native checks. The docs
audit passed 19 topics, 37 command help pages plus agent run, six example modules,
and eight prompt renders. A separate real-terminal session ran `seihou run
parent --var project.name=demo --var child.opt=custom`, accepted its initial
preview, changed the parent edge, then ran `seihou update parent` and accepted
`Apply? [Y/n]`. The preview showed the rebinding and two reused inputs, and the
resulting file was `name=demo opt=custom extra=x`. Final focused checks passed
all 11 rebinding/alignment/renderer tests, including exact plan/applied JSON
agreement and reused-input counts. No material external-surface friction occurred; querying
logged entries for this plan returned none.

[ADR 0025](../adr/0025-a-rebound-instance-keeps-its-saved-inputs.md) distills the
pairing, precedence, ambiguity and manifest decisions. No manifest schema change
or dependency change was required. This completes source implementation and
verification; publication and installation of a new release remain outside this
plan and have not been performed.


## Context and Orientation

### Terms

A *module* is a Dhall-defined generator (`module.dhall`). A module can declare
`dependencies`, each an *edge* to another module with optional `vars`, a list of
`{ name, value }` bindings that the parent supplies to the child. These are *parent vars*
or *bindings*.

An *instance* is one invocation of a module inside a composition. Its identity is the
module name plus its parent vars, represented by `ModuleInstance` (fields `module_` and
`parentVars`) in `seihou-core/src/Seihou/Core/Types.hs`. `ParentVars` is a newtype over
`Map VarName Text` in the same file. Two edges with different bindings to the same child
produce two instances. This is *multi-instantiation*, documented under "Multi-instantiation"
in `docs/user/module-authoring.md` (around line 409). This plan does not change that rule.

An *application* is one recorded top-level composition, an `AppliedComposition` in
`seihou-core/src/Seihou/Core/Types.hs`, stored under `applications` in
`.seihou/manifest.json`. Each application lists its instances as `AppliedInstanceState`
records (`name`, `parentVars`, `origin`, `moduleVersion`, `resolvedVars`,
`removalPolicy`). `resolvedVars` is a `Map VarName Text` of every value the instance
resolved, whatever its source (CLI, saved, configuration, parent binding, or default).
These are the project's *saved inputs*. The manifest also keeps a flat `modules` list of
`AppliedModule` records keyed by name and parent vars.

A *candidate* is what `seihou update` proposes to apply: the newly staged artifacts
loaded as `modulesInOrder :: [(ModuleInstance, Module, FilePath)]`.

A *rebinding* is this plan's term for a recorded instance and a candidate instance of the
same module, in the same application, that are paired even though their parent vars differ.

### Where the defect lives

All paths are relative to the repository root.

`seihou-cli/src/Seihou/CLI/Update.hs` is the update service.

- `planApplication` (around line 580) loads the candidate composition and computes
  `savedValues`. It uses `Map.empty` under `--reconfigure` and `savedInstanceValues
  previous` otherwise. It then calls `resolveApplicationValues`, which resolves variables
  per instance through `Seihou.Composition.Resolve.resolveRecipeWithSources` and
  `resolveWithSources` in `seihou-core/src/Seihou/Composition/Resolve.hs`.
  `resolveWithSources` looks up each candidate instance's saved values with
  `Map.findWithDefault Map.empty inst savedValues`, an exact `ModuleInstance` key. This is
  where a rebound child gets no saved values. Later in the same function, the
  `originedModules` binding (around line 625) finds the prior instance's origin with an
  exact `(name, parentVars)` match.
- `savedInstanceValues` (around line 916) builds `Map ModuleInstance (Map VarName Text)`
  from `previous ^. #instances`, keyed by `ModuleInstance name parentVars`.
- `versionEvidence` (around line 965) has `instanceVersionEvidence`, which finds `prior`
  with an exact `(name, parentVars)` match. When it finds none, it emits
  `VersionChange name Nothing toVersion False`, which is the `"from": null` in the IR.
- `summarizeInputChanges` (around line 1085) counts reused, overridden, newly resolved,
  and removed inputs against `savedInstanceValues` of the previous application. A
  rebound instance's inputs would all count as newly resolved.
- `updateAppliedModules` (around line 1288) rebuilds the manifest's flat `modules` list.
  A recorded key that is in the previous selected application but not in the candidate
  is dropped unless another unselected application protects it, and candidate keys are
  added. This already does the right thing for a rebinding: the old `(child, {})` entry
  goes and `(child, {child.extra=x})` arrives. No change is needed.
- The update plan is assembled around lines 150 to 240 (`versionEvidence`,
  `summarizeInputChanges`, and the `UpdatePlan` record), and `stageSelection`
  (around line 395) calls `planApplication` for each selected application.

`seihou-cli/src/Seihou/CLI/Update/Migrations.hs` has `transitionFor` with a local
`matches` (around lines 139 to 157), which also pairs prior and candidate instances by an
exact `(name, parentVars)` match. It receives `applicationInputs`, built in `Update.hs` as
`[(Just previous, planned ^. #modulesInOrder)]`. A rebound child that moved from 1.0.0 to
2.0.0 would get no migration transition.

`seihou-cli/src/Seihou/CLI/Update/Types.hs` defines `PlannedApplication`, `UpdatePlan`,
`UpdateResult`, `VersionChange`, `InputChangeSummary`, `UpdateWarning`, and `UpdateError`.
It also defines `isUpdateNoOp`, which compares instances including `parentVars`, so a
rebinding is never a no-op. That is correct.

`seihou-cli/src/Seihou/CLI/Update/Render.hs` renders plans, results, and errors in human
and JSON form: `renderUpdateHuman`, `outputValue`, `versionValue`, `warningText`,
`errorCode`, and `errorMessage`. The `Removal policies changed:` line compares
`instancePolicies` lists, which include `parentVars`, so a rebinding would print it
spuriously. `seihou-cli/src/Seihou/CLI/ApplicationDisplay.hs` provides `parentVarsText`
(sorted `[key=value, ...]`, or `Nothing` for no bindings) and `applicationLabel` for an
`ApplicationRef`. `seihou-cli/src/Seihou/CLI/Update/Selection.hs` has `applicationRef ::
Manifest -> ApplicationId -> ApplicationRef`.

Variable precedence is in `resolveVariablesWithSources` in
`seihou-core/src/Seihou/Core/Variable.hs` (around line 234): explicit (CLI or recipe
binding), then saved (`FromApplication`), then environment, then local, namespace,
context, and global configuration, then parent binding (`FromParent`), then default. Saved
values outrank parent bindings. For an exact match this is harmless because the parent
vars are identical, but it is why carried values must be filtered for a rebinding.

### The reproduction

These are the IR's two minimal local modules. `child` declares `project.name` (text,
required), `child.opt` (text, default `"default"`), and `child.extra` (text, default
`"none"`), and writes a template that prints them. `parent` 1.0.0 depends on `child` with
no vars. The project runs `seihou run parent --var project.name=demo --var
child.opt=custom`. Then `parent` 1.1.0 adds `vars = [{ name = "child.extra", value = "x" }]`
to the `child` edge. On Seihou 0.15.0.0, `seihou update parent --json
--include-shared-owners` exits 1:

```text
{"error":{"code":"variable_errors","message":"Variables could not be resolved: missing required variable: project.name"},"outcome":"error","schemaVersion":1}
```

With `--var project.name=demo` added, it applies with 0 conflicts and `child.opt` returns
to `default`.

### Tests

The CLI suite is `seihou-cli-test` (tasty with hspec, entry point
`seihou-cli/test/Main.hs`; modules are listed in the `test-suite seihou-cli-test` stanza of
`seihou-cli/seihou-cli.cabal`). End-to-end specs drive the built `seihou` binary. The
helpers `prepare`, `invoke`, `success`, and `readManifest` in
`seihou-cli/test/Seihou/CLI/SeedRunE2ESpec.hs` show the pattern: modules are written under
`<root>/.seihou/modules/<name>` with a pinned schema copied in by `copyPinnedSchema`, then
`seihou run` and `seihou update` run with `HOME` and `XDG_*` redirected into the temp root.
`seihou-cli/test/Seihou/CLI/UpdateSpec.hs` holds service-level tests, including "preserves
parameterized instances while planning their shared transition once" (around line 623),
which builds `AppliedInstanceState` values by hand. `seihou-cli/test/Seihou/CLI/UpdateFixture.hs`
builds `UpdatePlan` values for render tests, and
`seihou-cli/test/Seihou/CLI/UpdateRenderSpec.hs` holds one value of every `UpdateWarning`
constructor and asserts that no output falls back to `show`.

Build and test inside the Nix development shell. The ambient Cabal build lacks zlib
(`docs/friction-log/3-ambient-cabal-build-lacks-zlib.md`, FRIC-3).

### Relevant ADRs

- [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md): the
  manifest is the only record of applied state. Rebinding is derived from it, and nothing
  else is consulted.
- [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md):
  a semantic manifest change advances the schema. This plan adds no manifest field, so
  no schema step is needed (see the Decision Log).
- [ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md):
  name applications and instances with `ApplicationDisplay` (`[key=value, ...]`), keep
  safety logic renderer-neutral by passing structured values, render every new warning
  and error constructor exhaustively with no `show` fallback, and lead each error with
  its remedy under a stable machine code. The new error and the rebinding display follow
  this.
- [ADR 0017](../adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md):
  legacy adoption already turns dependency-edge bindings into saved inputs. That is the
  precedent for treating an edge's bindings and a project's saved inputs as separable.
- [ADR 0021](../adr/0021-recipe-inputs-resolve-before-module-defaults.md): recipe inputs
  resolve before module saved values, ordinary update keeps omitted optional answers
  omitted, and `--reconfigure` discards both recipe and instance history. Carried values
  enter the same `saved` channel, so recipe precedence is unchanged.

The ADRs in `docs/adr/` follow a plain filesystem convention (`NNNN-slug.md`, a heading
`# ADR NNNN — Title`, and `- Status:` and `- Date:` lines). They are not a profiled OKF
bundle. The next free number is 0025.


## Plan of Work

### Milestone 1: a pure alignment of recorded and candidate instances

Create `seihou-cli/src/Seihou/CLI/Update/Rebinding.hs` in the `seihou-cli-internal`
library (list it in the library stanza of `seihou-cli/seihou-cli.cabal` next to
`Seihou.CLI.Update.Types`). It needs none of the executable-only imports, so it belongs
in `src/`. Define the types in `seihou-cli/src/Seihou/CLI/Update/Types.hs` so that
renderers can use them without importing the algorithm:

```haskell
-- | A recorded instance paired with a candidate instance of the same module in
-- the same application whose dependency-edge bindings changed.
data InstanceRebinding = InstanceRebinding
  { applicationId :: !ApplicationId,
    moduleName :: !ModuleName,
    fromParentVars :: !ParentVars,
    toParentVars :: !ParentVars
  }
  deriving stock (Eq, Show, Generic)

-- | Unmatched recorded and candidate instances of one module that cannot be
-- paired one to one.
data UnpairedInstances = UnpairedInstances
  { applicationId :: !ApplicationId,
    moduleName :: !ModuleName,
    recorded :: ![ParentVars],
    candidates :: ![ParentVars]
  }
  deriving stock (Eq, Show, Generic)

-- | Each candidate instance's prior state, whether matched exactly or rebound.
data PriorAlignment = PriorAlignment
  { priors :: !(Map ModuleInstance AppliedInstanceState),
    rebindings :: ![InstanceRebinding],
    unpaired :: ![UnpairedInstances]
  }
  deriving stock (Eq, Show, Generic)
```

In `Seihou.CLI.Update.Rebinding`, implement:

```haskell
alignPriorInstances :: AppliedComposition -> [ModuleInstance] -> PriorAlignment
carriedSavedValues :: PriorAlignment -> SavedInstanceValues
```

`alignPriorInstances previous candidates` first pairs every candidate whose
`(module_, parentVars)` equals a recorded instance's `(name, parentVars)`. For each module
name, it then collects the leftover candidates and leftover recorded instances. If there is
exactly one of each, they form an `InstanceRebinding` and the recorded state is entered in
`priors` under the candidate key. If both sides are non-empty but not one to one, it
records an `UnpairedInstances` and pairs nothing for that module. In every other case
(only new or only removed instances) it does nothing. The function never fails. Deciding
whether `unpaired` is fatal belongs to the caller, because `--reconfigure` changes the
answer. Sort the `ParentVars` lists so the output is deterministic.

`carriedSavedValues` returns, for each entry in `priors`, the recorded `resolvedVars`.
For a rebound entry it applies the two precedence rules from the Decision Log: drop every
key in `toParentVars`, and drop a key in `fromParentVars` whose saved value equals the old
bound value. For an exact match, return `resolvedVars` unchanged, which is today's
behaviour.

Add `seihou-cli/test/Seihou/CLI/RebindingSpec.hs`, register it in the test-suite stanza
and in `seihou-cli/test/Main.hs`, and cover:

1. Exact match only: `priors` holds every candidate, and `rebindings` and `unpaired` are
   empty.
2. Added binding: recorded `child {}` and candidate `child {child.extra=x}` give one
   rebinding. The carried values keep `project.name` and `child.opt` and drop
   `child.extra`.
3. Changed binding value (`x` to `y`) and removed binding (`{child.extra=x}` to `{}`):
   both rebind. In the removed case, a saved `child.extra=x` is dropped, while a saved
   `child.extra=z` (a project override) is kept.
4. Multi-instantiation unchanged: recorded `link {skill=a}` and `link {skill=b}`, with
   identical candidates, give two exact matches with separate values and no rebinding.
5. One of two invocations rebound: recorded `link {skill=a}` and `link {skill=b}`, with
   candidates `link {skill=a}` and `link {skill=b, extra=1}`, give one exact match and one
   rebinding.
6. Ambiguous: two recorded and two candidate instances that are all unmatched give one
   `UnpairedInstances` and no priors for that module.
7. New and removed only: one extra candidate with no leftover recorded instance is not
   paired, and the reverse is also not paired.

Acceptance: `cabal test seihou-cli-test --test-options='-p "/rebinding alignment/"'`
passes inside the Nix shell, and the cases fail if the pairing or the precedence rules
are removed.

### Milestone 2: use the alignment throughout update

Extend `PlannedApplication` in `Seihou.CLI.Update.Types` with
`priorAlignment :: !PriorAlignment`. In `planApplication`, compute it right after
`loadCandidateComposition` succeeds, from `previous` and the instance ids of
`modulesInOrder`. Then:

- If `unpaired` is non-empty and `--reconfigure` was not passed, return a new error
  `UpdateInstanceRebindingAmbiguous ApplicationRef [UnpairedInstances]` before resolving
  any values. Build the `ApplicationRef` in the same shape as
  `Seihou.CLI.Update.Selection.applicationRef`. Because planning fails, nothing is
  written, which already holds for every `planApplication` error: dry runs and failed
  updates preserve the manifest.
- Otherwise, set `savedValues` to `Map.empty` under `--reconfigure` and to
  `carriedSavedValues alignment` otherwise. Delete `savedInstanceValues` once nothing
  uses it.
- Resolve the `originedModules` origin through `priors` instead of the exact `find`.
- When `resolveApplicationValues` returns `UpdateVariableErrors errors` and
  `rebindings` is non-empty, map it to a new constructor
  `UpdateRebindingVariableErrors [InstanceRebinding] [VarError]`, keeping only the
  rebindings whose module declares, or whose new edge binds, a variable named in
  `errors`. If none qualify, keep `UpdateVariableErrors`. Both render with the code
  `variable_errors` so JSON consumers keep a stable code. The new one appends a clause
  naming each edge, for example `child's dependency edge changed from (no bindings) to
  [child.extra=x] in this release`.

In `versionEvidence`, take the prior from `planned ^. #priorAlignment . #priors`
instead of the exact `find`, so a rebound child reports `from` its recorded version. Under
`--reconfigure`, an unpaired candidate keeps `from: null`, which is honest because it was
not paired.

In `summarizeInputChanges`, replace `savedInstanceValues` with the aligned prior values,
keyed by candidate instance, so that carried inputs count as reused. Recorded instances
that are neither matched nor rebound still count as removed.

In `seihou-cli/src/Seihou/CLI/Update/Migrations.hs`, make `transitionFor` look up the
prior through the alignment. The smallest change is to make each `applicationInputs`
element carry the `priors` map in place of `Maybe AppliedComposition` and drop the local
`matches`. Update the caller in `Update.hs`, the `planAndStageMigrations` wrapper, and the
existing migration-staging test in `UpdateSpec.hs` that passes `[(Just previous,
candidates)]`. Confirm that the staged manifest's `modules` versions still advance for
both the old and the new key, as that test asserts for parameterized instances.

Add the reproduction as `seihou-cli/test/Seihou/CLI/RebindingUpdateE2ESpec.hs`, registered
like the other E2E specs. Reuse the `SeedRunE2ESpec` helpers or copy their small bodies.
Write `parent` and `child` under `<root>/.seihou/modules/`. The child writes `values.txt`
from the template `name={{project.name}} opt={{child.opt}} extra={{child.extra}}`. Run
`seihou run parent --var project.name=demo --var child.opt=custom`, then rewrite the parent
to 1.1.0 with the added binding, and assert:

1. `seihou update parent --json --dry-run` succeeds, its JSON has a `rebindings` entry for
   `child`, and the manifest bytes are unchanged.
2. `seihou update parent --json` succeeds with no `--var`. `values.txt` reads
   `name=demo opt=custom extra=x`. The manifest's `child` instance records
   `parentVars {child.extra=x}` and `resolvedVars` containing `child.opt=custom`. The JSON
   has a `child` version change whose `from` is not null (or no `child` version change at
   all when the version is unchanged; see the note in Validation).
3. Changed value: a further parent 1.2.0 with `child.extra=y` updates to
   `extra=y` and keeps `opt=custom`.
4. Removed binding: a parent 1.3.0 with no vars on the edge updates to `extra=none`
   (the child default) and keeps `opt=custom`.
5. A `--var child.opt=other` given at update time still wins over the carried value.
6. Multi-instantiation: a second parent that depends on `child` twice with
   `child.extra=a` and `child.extra=b`, applied and then re-released with no edge change,
   keeps both instances and their separate saved inputs.
7. Ambiguous: re-release that two-edge parent with a new binding added to both edges.
   `seihou update` exits non-zero with code `ambiguous_instance_rebinding`, the message
   names `child` and all four binding sets, and the manifest and project files are
   byte-identical. The same update with `--reconfigure --var project.name=demo` succeeds.
8. Variable error naming the edge: from case 2's starting state,
   `seihou update parent --json --reconfigure` with no `--var` fails with
   `variable_errors`, and the message contains `child` and `[child.extra=x]`.

Acceptance: the new E2E spec and the whole existing update suite pass.

### Milestone 3: show the rebinding, document it, record the decision

Add `rebindings :: ![InstanceRebinding]` to `UpdatePlan` (collected from the planned
applications) and to `UpdateResult` (copied from the plan where the result is built,
around line 1506 of `Update.hs`). Set it to `[]` in `minimalPlan` in
`seihou-cli/test/Seihou/CLI/UpdateFixture.hs`.

In `seihou-cli/src/Seihou/CLI/Update/Render.hs`:

- In the human plan, after the version lines, print one line per rebinding:
  `Rebinding:   child (no bindings) -> [child.extra=x]; saved inputs kept`, using
  `parentVarsText`. Under `--reconfigure`, an unpaired module prints
  `Rebinding:   child could not be paired; inputs resolved again (--reconfigure)`.
- In the plan and applied JSON, add `"rebindings": [{"application": <id>, "module":
  "child", "from": {}, "to": {"child.extra": "x"}}]`. Always emit the key, with `[]` when
  there are none, so consumers need not test for presence.
- Render `UpdateInstanceRebindingAmbiguous` with the code `ambiguous_instance_rebinding`
  and a message that leads with the remedy, for example: `Run 'seihou update parent
  --reconfigure' to supply child's inputs again: this release changed the bindings of
  more than one child dependency edge in parent, so seihou cannot tell which saved
  inputs belong to which. Recorded: child [child.extra=a], child [child.extra=b].
  Candidate: child [child.extra=a, child.mode=m], child [child.extra=b, child.mode=m].`
  Render `UpdateRebindingVariableErrors` as described in Milestone 2. Both matches must
  be exhaustive, per ADR 0015.
- Compute the `Removal policies changed:` comparison against the aligned prior, so that
  a rebinding alone does not print it.

Extend `seihou-cli/test/Seihou/CLI/UpdateRenderSpec.hs` with a plan carrying one
rebinding and with both new errors, asserting the exact human lines, the JSON shape, and
the absence of constructor syntax.

Documentation:

- `docs/user/module-authoring.md`, under "Multi-instantiation": add a short subsection,
  "Changing an edge's bindings in a release". Explain that update pairs a changed edge
  with the recorded instance when the pairing is one to one, keeps the project's saved
  inputs, lets the new bindings win for the variables they set, and refuses when several
  edges to the same module change at once (remedy: `--reconfigure`). Note that changing a
  binding's value is intended to change output, and the preview shows it.
- `docs/user/config-and-variables.md`, near the paragraph on saved inputs and
  `--reconfigure` (around line 510): one sentence on rebinding.
- `docs/user/CHANGELOG.md` under `## [Unreleased]`, `### Fixed`: one user-facing entry.
- If the CLI has a generated docs audit (`just audit-cli-docs`), run it.

ADR: write `docs/adr/0025-a-rebound-instance-keeps-its-saved-inputs.md` in the existing
format. It records the 1:1 pairing rule, the two carried-value precedence rules,
refusal on ambiguity with `--reconfigure` as the escape hatch, and the decision to keep
rebinding out of the manifest. Link it from this plan's Outcomes.

Acceptance: the whole `seihou-cli-test` suite passes, `nix flake check` passes
(module-placement and record-convention checks included), and the IR's acceptance
criteria all hold (see Validation and Acceptance).


## Concrete Steps

Run everything from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`, inside the development shell.

```bash
nix develop --no-write-lock-file -c cabal build seihou-cli:seihou seihou-cli:seihou-cli-test
```

Milestone 1 focused tests:

```bash
nix develop --no-write-lock-file -c cabal test seihou-cli-test --test-options='-p "/rebinding alignment/"'
```

Expected tail:

```text
All 7 tests passed
```

Milestone 2 focused tests (the E2E spec builds and drives the binary):

```bash
nix develop --no-write-lock-file -c cabal test seihou-cli-test --test-options='-p "/rebinding update end-to-end/"'
nix develop --no-write-lock-file -c cabal test seihou-cli-test --test-options='-p "/update/"'
```

Before writing the fix, run the new E2E spec once against the unchanged code. Case 1 should
fail with the IR's error, which proves that the test reproduces the defect:

```text
{"error":{"code":"variable_errors","message":"Variables could not be resolved: missing required variable: project.name"},"outcome":"error","schemaVersion":1}
```

Full validation at the end of Milestone 3:

```bash
nix develop --no-write-lock-file -c cabal test seihou-cli-test
nix flake check --no-write-lock-file
```

Commit at each milestone boundary with Conventional Commit messages and both trailers, for
example:

```text
fix(update): carry saved inputs across a released dependency rebinding

Pair a recorded instance with its rebound candidate one to one, carry its
saved inputs with the new edge's bindings taking precedence, and refuse an
ambiguous pairing.

ExecPlan: docs/plans/123-keep-saved-inputs-when-a-release-changes-a-dependency-s-bindings.md
Intention: intention_01m75e5s06e88a4vzm3r5qwyd6
```


## Validation and Acceptance

Required acceptance, mapped to IR-15's criteria:

1. With the parent and child above, `seihou update parent` succeeds with no `--var`,
   keeps `child.opt=custom`, and reports the rebinding in the human preview
   (`Rebinding:   child (no bindings) -> [child.extra=x]; saved inputs kept`) and in
   `--json` (`rebindings`). This is E2E cases 1 and 2.
2. A value that the new binding sets replaces the saved value for that variable only.
   `extra=x` takes effect, and `project.name` and `child.opt` are unchanged. This is E2E
   case 2 and unit case 2.
3. A module deliberately invoked twice with different bindings keeps both instances and
   their separate inputs. This is E2E case 6 and unit cases 4 and 5.
4. A release that removes or changes a binding value behaves the same way as one that
   adds one. This is E2E cases 3 and 4 and unit case 3.
5. An ambiguous match exits non-zero, leaves project state unchanged, and names the
   instances involved. This is E2E case 7 and unit case 6.
6. A variable error caused by a changed edge names that edge. This is E2E case 8.
7. The real prior version is reported: the rebound child's version evidence uses its
   recorded `moduleVersion`. In the reproduction the child's own version does not
   change, so `versions` contains no `child` entry instead of `{"name":"child","from":null,...}`.
   Assert exactly that, and also cover a variant where the child moves from 1.0.0 to
   1.1.0 in the same release, which must report `"from":"1.0.0","to":"1.1.0"`.

Regression: the full `seihou-cli-test` suite passes, including the existing
parameterized-instance migration test and every `UpdateRenderSpec` exhaustiveness check.
The project's own pre-commit and `nix flake check` gates pass.

Out of scope (proposals, not acceptance): a `validate-module` release-time warning, and
heuristic pairing of several changed edges.


## Idempotence and Recovery

Every step is a source edit or a test run and can be repeated. `seihou update` remains
transactional: an ambiguous refusal or a variable error happens during planning, before
the update transaction opens, so no manifest, baseline, or project file is written. The
E2E tests assert this byte for byte. Re-running a successful rebinding update is a no-op,
because the manifest now records the instance under its new parent vars and the next
alignment is an exact match. If a milestone has to be abandoned, revert its commit. No
manifest format or schema changes, so no project needs a migration in either direction.


## Interfaces and Dependencies

New and changed interfaces. All are in the `seihou-cli-internal` library, with no new
package dependencies.

- `Seihou.CLI.Update.Types`: new records `InstanceRebinding`, `UnpairedInstances`, and
  `PriorAlignment` (shown above); new fields `PlannedApplication.priorAlignment`,
  `UpdatePlan.rebindings`, and `UpdateResult.rebindings`; new `UpdateError`
  constructors `UpdateInstanceRebindingAmbiguous ApplicationRef [UnpairedInstances]` and
  `UpdateRebindingVariableErrors [InstanceRebinding] [VarError]`. All records follow the
  project record conventions: strict fields, no prefixes, `deriving stock`, `Generic`,
  and access through `generic-lens` labels only.
- `Seihou.CLI.Update.Rebinding` (new): `alignPriorInstances :: AppliedComposition ->
  [ModuleInstance] -> PriorAlignment` and `carriedSavedValues :: PriorAlignment ->
  SavedInstanceValues` (`SavedInstanceValues` is
  `Map ModuleInstance (Map VarName Text)` from `Seihou.Composition.Resolve`).
- `Seihou.CLI.Update.Migrations`: `applicationInputs` elements carry the aligned priors
  instead of `Maybe AppliedComposition`.
- `Seihou.CLI.Update.Render`: JSON plan and applied outputs gain a `rebindings` array, and
  the error code `ambiguous_instance_rebinding` is new. `schemaVersion` stays `1` because
  the change is additive.

No changes are needed in `seihou-core`. Resolution precedence in
`Seihou.Core.Variable` and the per-instance lookup in `Seihou.Composition.Resolve` stay
as they are, and the fix works by giving them the right saved values under the right key.
