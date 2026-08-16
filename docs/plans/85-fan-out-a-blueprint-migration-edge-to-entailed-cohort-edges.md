---
id: 85
slug: fan-out-a-blueprint-migration-edge-to-entailed-cohort-edges
title: "Fan out a blueprint migration edge to entailed cohort edges"
kind: exec-plan
created_at: 2026-08-16T14:16:41Z
intention: "intention_01m05ew4qbef6tn9bnphy4nv2n"
master_plan: "docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md"
---

# Fan out a blueprint migration edge to entailed cohort edges

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

A *blueprint migration* is an agent-guided upgrade step a library author ships with a
blueprint: one Markdown prompt per version edge, run by
`seihou agent migrate <blueprint> --from X --to Y`. Today every edge in a run belongs to the
one blueprint named on the command line, and the version window is that blueprint's own
version space.

That works when the library whose breaking change you are absorbing is the library you
depend on. It stops working when the change travels through an intermediary. A concrete
chain: `mori://shinzui/kiroku` ships a breaking change. `mori://shinzui/keiro` depends on
kiroku and absorbs the change in one of its own releases. Most consuming projects depend on
keiro and never name kiroku; a few depend on kiroku directly and never touch keiro. A keiro
consumer knows their keiro version and has no reason to know which kiroku version keiro
pulls in. So kiroku's upgrade knowledge has to reach them through keiro's version space,
without being copied into keiro's repository and without running twice for a project that
depends on both.

After this plan, an edge in one blueprint can declare that crossing it *entails* crossing a
named edge in another blueprint. keiro's `2.4.0 -> 3.0.0` edge declares that it entails
kiroku's `1.9.0 -> 2.0.0` edge. A consumer runs one command:

```bash
seihou agent migrate keiro-upgrade --from 2.4.0 --to 3.0.0
```

and gets two agent sessions in order — kiroku's edge first, with kiroku's reference files and
allowed tools and variables, then keiro's own. A project depending only on kiroku runs
`seihou agent migrate kiroku-upgrade` and is unaffected. A project depending on both crosses
the shared kiroku edge exactly once from either entry point, because the receipt for an
entailed edge is written under the identity of the blueprint that *declares* it.

You can see all of this without contacting a provider:

```bash
seihou agent --debug migrate keiro-upgrade --from 2.4.0 --to 3.0.0
```

which prints every pending session in order, labelled with its owning blueprint.

This is the plan the initiative in
`docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md` exists for. The
other plans make it safe; this one makes it work.


## Progress

- [ ] Verify both prerequisite plans have landed (orientation, no edits).
- [ ] Publish `EntailedEdge.dhall` and the `entails` field in the `seihou-schema` submodule; push and re-pin.
- [ ] Decode `entails` in `seihou-core/src/Seihou/Dhall/Eval.hs`, tolerating blueprints that predate it.
- [ ] Validate entailment in `seihou-core/src/Seihou/Core/Blueprint.hs`.
- [ ] Add a step type carrying its owning blueprint, and pure recursive expansion with cycle detection, in `seihou-core/src/Seihou/Core/Migration.hs`.
- [ ] Resolve the cohort's blueprints in `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs` by transitive-closure discovery.
- [ ] Prepare one execution context per owning blueprint so each step gets its own files, tools, and variables.
- [ ] Filter each step against receipts using its owning blueprint's identity.
- [ ] Label the owning blueprint in launch output and `--debug` output.
- [ ] Add tests: expansion, cycles, missing blueprint, missing edge, cross-entry-point deduplication.
- [ ] Update `docs/user/blueprint-migrations.md`, `docs/user/blueprints.md`, `docs/cli/agent.md`, `schema/README.md`, and `docs/user/CHANGELOG.md`.
- [ ] Write the ADR recording that an entailed edge is owned by the blueprint that declares it.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: ...
  Rationale: ...
  Date: ...


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

### Dependencies on other plans

This plan **cannot be implemented before** two others:

- `docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md` gives every receipt
  an `origin`, and makes the receipt completion key include it. Without that, an entailed
  edge recorded under the name `kiroku-upgrade` cannot be distinguished from a same-named
  blueprint published by a different repository, and this plan's whole
  cross-entry-point-deduplication property rests on that distinction.
- `docs/plans/84-add-a-not-applicable-outcome-for-blueprint-migration-edges.md` gives an
  edge a way to report that its precondition is unmet. An entailed edge is, by construction,
  frequently inapplicable: a keiro consumer who never imports kiroku directly should have
  kiroku's edge report "nothing to do here". Without that outcome, every such run writes an
  *applied* receipt for kiroku's edge, which then suppresses that edge for the same project
  if it later starts using kiroku directly — converting the feature into a silent-work-loss
  machine.

Verify both:

```bash
rg -n "origin :: !ArtifactOrigin" seihou-core/src/Seihou/Core/Types.hs
rg -n "MigrationNotApplicable" seihou-core/src/Seihou/Core/Types.hs
```

Both must appear. If either does not, implement that plan first.

`docs/plans/82-refuse-to-overwrite-an-installation-from-a-different-source.md` and
`docs/plans/83-guard-the-agent-path-against-stale-and-substituted-artifacts.md` are soft
dependencies: this plan resolves several blueprints by bare name out of a name-keyed install
cache, which is exactly the surface those two harden. Neither blocks implementation.

### What this repository is

Seihou is a project scaffolding system written in Haskell: a two-package Cabal workspace,
`seihou-core` (library, at `seihou-core/`) and `seihou-cli` (at `seihou-cli/`). The CLI
package is split into a library at `seihou-cli/src/` (package `seihou-cli-internal`) and an
executable at `seihou-cli/src-exe/`. New code goes in a library by default; the executable
holds `Main.hs`, command dispatchers, and modules needing `Options.Applicative`,
`Data.FileEmbed`, `GitHash`, or `Paths_seihou_cli`, plus anything transitively importing
one. `nix/check-cli-module-placement.sh` enforces this and will fail the build if a new
module lands on the wrong side.

That matters a lot in this plan, because the natural place to put "expand entailed edges" is
wherever it is convenient, and the right place is `seihou-core`. Keep the expansion pure and
in the core library; keep the filesystem discovery that feeds it in the CLI.

Records use strict fields, `Generic`, explicit deriving strategies, and are read and written
through `generic-lens` overloaded labels (`step ^. #owner`), never record dot syntax and
never record update syntax. Modules using `#label` import `Data.Generics.Labels ()`.
`nix/check-record-conventions.sh` enforces this.

### Terms used in this plan

**Blueprint** — an agent-driven runnable described by a `blueprint.dhall`. It declares a
name, a version, a shared prompt, optional variables, optional base modules, optional
reference files under `files/`, optional `allowedTools`, and a list of `migrations`.

**Edge** — one entry in a blueprint's `migrations` list: a `from` version, a `to` version,
and a prompt describing the source changes that transition requires.

**Cohort** — the set of libraries whose upgrades are coupled, here kiroku and keiro. Note
that seihou has no cohort *artifact*; a cohort exists only as the transitive closure of
entailment declarations. That is a deliberate decision recorded in the parent MasterPlan.

**Owning blueprint** — for an edge reached through entailment, the blueprint whose
`migrations` list actually declares it. kiroku's `1.9.0 -> 2.0.0` edge is owned by
`kiroku-upgrade` even when it is reached by running `keiro-upgrade`.

**Receipt** — one `AppliedBlueprintMigration` in `.seihou/manifest.json`, identifying an
edge by the origin and name of its owning blueprint plus its `from` and `to` versions.

### The schema as it stands

`schema/` is a git submodule — a working copy of the GitHub repository
`shinzui/seihou-schema`, branch `master`. It is the only checkout that matters here;
`flake.nix` sources the schema from it, `nix/haskell-overlay.nix` copies it for
Dhall-importing tests, and `seihou-core/test/Seihou/Core/ScaffoldSpec.hs` resolves the local
schema path from it. There is a second, standalone clone at
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema` that Mori's registry points at;
**do not author schema changes there** — it creates a second unpushed lineage.

`schema/BlueprintMigration.dhall` today:

```dhall
{ Type = { from : Text, to : Text, prompt : Text }
, default = {=}
}
```

`schema/package.dhall` re-exports every top-level record; a new file must be added to it.
`schema/README.md` carries a type list that must stay accurate.

The pin lives in `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`:

```haskell
schemaUrl :: Text
schemaUrl = "https://raw.githubusercontent.com/shinzui/seihou-schema/<commit>/package.dhall"

schemaHash :: Text
schemaHash = "sha256:<hash>"
```

The full re-pin procedure — submodule bump, `SchemaVersion.hs`, `flake.lock` — is the
`update-seihou-schema` skill at `.claude/skills/update-seihou-schema/SKILL.md`. Follow it
rather than improvising; it lists every pin that must move together.

### The planner as it stands

`seihou-core/src/Seihou/Core/Migration.hs` is pure — no IO, no filesystem, no manifest, and
its module comment says so explicitly. It exposes:

```haskell
data BlueprintMigration = BlueprintMigration
  { from :: !Text, to :: !Text, prompt :: !Text }

data BlueprintMigrationPlan = BlueprintMigrationPlan
  { name :: !Text, from :: !Version, to :: !Version, steps :: ![BlueprintMigration] }

planBlueprintMigrationChain ::
  Text -> [BlueprintMigration] -> Version -> Version ->
  Either MigrationPlanError (Maybe BlueprintMigrationPlan)
```

`planBlueprintMigrationChain` delegates to `planMigrationWindow`, a gap-tolerant cursor walk
shared with module migrations. **`planMigrationWindow` must keep behaving identically for
module migrations**; it is called by `planMigrationChain` for `seihou migrate`, which this
initiative does not touch. Add entailment expansion *after* the window walk rather than
inside it.

The window rules, which entailment must not change: an edge is selected when its `from` is
at or after the cursor and its `to` is at or before the target; selecting it advances the
cursor to its `to`; gaps are legal; two edges with the same `from` are an authoring error.

### The command as it stands

`seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`, `handleAgentMigrate`, in order:

1. `discoverMigrationBlueprint` resolves the name to a `(Blueprint, FilePath)` using
   `Seihou.Core.Module.defaultSearchPaths` and `discoverRunnable`. It errors distinctly when
   the name resolves to a module, recipe, or prompt.
2. `validateBlueprint blueprintDir blueprint`.
3. Agent provider/model/effort resolution, honouring the blueprint's `launch` declaration.
4. Parse `--from` and `--to`.
5. `planBlueprintMigrationChain`.
6. Read receipts from the manifest; `pendingBlueprintMigrations` drops recorded edges.
7. `prepare` builds one `PreparedBlueprintExecution` for the whole command.
8. Either print debug output for every pending edge, or run them one at a time through
   `runBlueprintMigrationsWith`, writing a receipt after each.

Step 7 is the one that has to become per-blueprint:

```haskell
data PreparedBlueprintExecution = PreparedBlueprintExecution
  { blueprint :: !Blueprint,
    blueprintDir :: !FilePath,
    resolvedVariables :: !(Map VarName ResolvedVar),
    mountedFilesDir :: !(Maybe FilePath),
    referenceFiles :: !Text,
    referenceFilesAccess :: !Text,
    sharedPrompt :: !Text,
    allowedTools :: ![String]
  }
```

Every field in it is blueprint-specific: the mounted `files/` directory, the rendered
reference-file list, the shared prompt, the allowed tools, and the resolved variables. Today
`docs/user/blueprint-migrations.md` states plainly that "Reference files under `files/` are
shared by every edge… There is no per-edge `files` or `allowedTools`." Entailment makes that
statement wrong, because a step can now be owned by a different blueprint entirely, and that
documentation must change with the code.

### Relevant ADRs

- `docs/adr/0002-artifact-identity-is-origin-url-plus-name.md` — identity is origin plus
  name. This is what makes an entailed edge's receipt recognisable from either entry point.
- `docs/adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md` — a command about to
  generate from an artifact refuses when the local copy is stale or substituted, scoped to
  the artifacts it is about to use. Under entailment "the artifacts it is about to use"
  grows to the whole resolved cohort; see milestone 4.
- `docs/adr/0004-the-manifest-is-the-only-record-of-applied-state.md` — no lockfile. A
  cohort is not recorded anywhere; it is recomputed from declarations on every run.

`docs/adr/` is a plain filesystem corpus, not a profile-governed OKF bundle — `mori.dhall`
registers only `docs/improvement-requests`. Keep the `NNNN-slug.md` convention, the
`# ADR NNNN — Title` heading, and `Status` / `Date` lines. Do not add OKF frontmatter.

No cross-repository ADR governs this work. `mori registry concepts --search 'migration'`
returns database-migration decisions from `mori://shinzui/rei` and `mori://shinzui/pgmq-hs`,
which are a different subject.


## Plan of Work

### Design decisions to make before coding, and how to resolve them

**Order of an entailed edge relative to its entailing edge.** Entailed edges run *first*, in
declaration order, then the declaring edge. Rationale: the entailed edge is the deeper
change (kiroku's API), and the declaring edge's own guidance may assume it has been applied
(keiro's wrapper on top of the new kiroku surface). Authors control ordering among several
entailed edges by their order in the list. Record this and state it in the authoring
documentation, because an author cannot discover it from the schema.

**Transitivity.** Expansion is recursive: an entailed edge may itself entail others. Bound it
with a visited set keyed by `(owning blueprint name, from, to)`, and treat a cycle as a hard
authoring error naming the cycle. Recursion is what makes a three-deep cohort work without
every blueprint knowing the whole graph.

**A missing entailed blueprint.** Hard error, naming the blueprint and printing an install
hint. Do not skip it silently — the whole point is that the consumer does not know the
cohort, so silently omitting a member produces a half-migrated project with no signal. Do
not auto-fetch it either: ADR 0003 rejects auto-fetching because it would mutate the
machine-global install cache as a side effect of an unrelated command.

**A missing entailed edge.** If the named blueprint resolves but declares no edge with that
exact `from`/`to`, that is an authoring error in the *declaring* blueprint. Hard error
naming both blueprints and the edge. Do not fall back to window-planning inside the entailed
blueprint: entailment names one exact edge, and guessing would make a keiro release silently
change which kiroku work it implies.

**Duplicate edges within one expanded plan.** Two selected keiro edges might both entail the
same kiroku edge. Deduplicate during expansion using the visited set, keeping the first
occurrence. This is distinct from receipt-based skipping, which happens afterwards.

Record each of these in the Decision Log as you make them.

### Milestone 1 — publish the schema change

At the end of this milestone the `entails` field is authorable in a `blueprint.dhall` and
this repository is pinned to a schema that contains it. Nothing in Haskell reads it yet.

Work in the `schema/` submodule, following `.claude/skills/update-seihou-schema/SKILL.md`.
First verify the submodule is clean and current:

```bash
git -C schema fetch origin
git -C schema status --branch --porcelain
```

Create `schema/EntailedEdge.dhall`:

```dhall
-- | One migration edge in another blueprint that this edge entails.
--
-- Declaring an entailed edge means: a project crossing the declaring edge
-- must also cross this exact edge of the named blueprint. Seihou resolves
-- the named blueprint the same way `seihou agent migrate` resolves the
-- blueprint you name on the command line, finds the edge whose `from` and
-- `to` match exactly, and runs it before the declaring edge.
--
-- The receipt for an entailed edge is recorded under the *entailed*
-- blueprint's identity, so a project that also runs that blueprint directly
-- crosses the edge only once.
--
-- All fields are required.
--
-- Usage:
--   let S = ./package.dhall
--   in  S.EntailedEdge::{
--         blueprint = "kiroku-upgrade",
--         from = "1.9.0",
--         to = "2.0.0"
--       }

{ Type = { blueprint : Text, from : Text, to : Text }
, default = {=}
}
```

Extend `schema/BlueprintMigration.dhall` with an `entails` field defaulting to the empty
list, and expand its comment to explain what entailment means and that entailed edges run
first. Add `EntailedEdge` to `schema/package.dhall` and to the type list in
`schema/README.md`.

Type-check, and prove the new field is authorable with a scratch file using record
completion:

```bash
dhall type --file schema/package.dhall > /dev/null && echo "package.dhall type-checks"
```

Commit and **push inside the submodule** — the pin resolves over HTTPS from
`raw.githubusercontent.com`, so an unpushed commit cannot be fetched by anyone:

```bash
git -C schema add EntailedEdge.dhall BlueprintMigration.dhall package.dhall README.md
git -C schema commit -m "feat(schema): add entails to BlueprintMigration"
git -C schema push origin master
```

Then re-pin in this repository per the skill: bump the submodule pointer, update `schemaUrl`
and `schemaHash` in `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`, and update `flake.lock`.

Coordination note: `docs/plans/86-infer-the-blueprint-migration-version-window.md` also adds
a schema field. This plan lands its schema change first; plan 86 rebases onto the resulting
pin rather than publishing a competing one.

### Milestone 2 — decode and validate

At the end of this milestone a blueprint declaring `entails` loads, and
`seihou validate-blueprint` rejects a malformed declaration.

In `seihou-core/src/Seihou/Dhall/Eval.hs`, add an `EntailedEdge` decoder and extend
`blueprintMigrationDecoder`. Blueprints published before this schema version have no
`entails` key, so use the existing `withDefaults` mechanism the same way `blueprintDecoder`
already handles `migrations` and `launch`:

```haskell
emptyEntailsList :: Dhall.Expr Src Void
emptyEntailsList = Dhall.ListLit (Just entailedEdgeType) mempty
```

Note that `withDefaults` is currently applied at the `blueprintDecoder` level, not to the
per-migration decoder, so this needs a `withDefaults` wrapper on
`blueprintMigrationDecoder` itself. Read how `emptyMigrationList` is constructed at
`seihou-core/src/Seihou/Dhall/Eval.hs:200` and follow the same shape; a list of records
needs its element type spelled out where the empty migration list only needed `Text`.

Add the corresponding Haskell type in `seihou-core/src/Seihou/Core/Migration.hs`:

```haskell
-- | A reference from one blueprint's migration edge to an exact edge of
-- another blueprint. Resolution is by name through the same search paths
-- @seihou agent migrate@ uses; the referenced edge must exist verbatim.
data EntailedEdge = EntailedEdge
  { blueprint :: !Text,
    from :: !Text,
    to :: !Text
  }
  deriving stock (Eq, Show, Generic)
```

and add `entails :: ![EntailedEdge]` to `BlueprintMigration`.

In `seihou-core/src/Seihou/Core/Blueprint.hs`, extend `checkBlueprintMigrations` (rule 10 in
the documented list at the top of that file, which must be updated too). Validate that each
entailed edge's `blueprint` matches the module-name format `[a-z][a-z0-9-]*` — reuse
`isValidModuleName`, already imported there — that `from` and `to` parse as dotted numeric
versions, that `from` is strictly less than `to`, and that no edge entails an edge of its own
blueprint. Cross-blueprint existence cannot be checked here, because
`checkBlueprintMigrations` is pure and existence is a filesystem question; it is checked at
resolution time in milestone 4, and the validation rule list should say so.

### Milestone 3 — pure expansion

At the end of this milestone the core library can turn a selected window of edges plus a map
of loaded blueprints into a flat ordered list of steps, each labelled with its owner, and
every failure mode is a typed error. This is fully unit-testable with no filesystem.

In `seihou-core/src/Seihou/Core/Migration.hs`:

```haskell
-- | One edge to run, together with the blueprint that declares it.
--
-- @owner@ is the name of the blueprint whose @migrations@ list contains
-- @edge@ — not the blueprint the user named on the command line. Receipts
-- are written under the owner, which is what makes a shared cohort edge the
-- same edge from either entry point.
data BlueprintMigrationStep = BlueprintMigrationStep
  { owner :: !Text,
    edge :: !BlueprintMigration
  }
  deriving stock (Eq, Show, Generic)
```

Change `BlueprintMigrationPlan`'s `steps` from `![BlueprintMigration]` to
`![BlueprintMigrationStep]`, and have `planBlueprintMigrationChain` label every window-selected
edge with the blueprint name it was already given.

Add the expander:

```haskell
-- | Expand each selected edge into its entailed edges followed by itself,
-- recursively, in declaration order.
--
-- @lookupMigrations@ answers "what edges does this blueprint declare?" and
-- returns 'Nothing' for a blueprint that could not be resolved. Keeping it a
-- parameter is what lets this function stay pure: discovery is the CLI's job.
expandEntailedEdges ::
  (Text -> Maybe [BlueprintMigration]) ->
  [BlueprintMigrationStep] ->
  Either EntailmentError [BlueprintMigrationStep]

data EntailmentError
  = -- | An entailed blueprint could not be resolved. Carries the name.
    EntailedBlueprintNotFound !Text
  | -- | The named blueprint resolved but declares no such edge.
    -- Carries: declaring blueprint, entailed blueprint, from, to.
    EntailedEdgeNotDeclared !Text !Text !Text !Text
  | -- | Entailment forms a cycle. Carries the chain, in order.
    EntailmentCycle ![Text]
  deriving stock (Eq, Show, Generic)
```

Implement as a depth-first walk with two sets: a `visited` set of
`(owner, from, to)` triples for deduplication across the whole expansion, and an
`inProgress` set for the current path, for cycle detection. For each step, recurse into its
entailed edges first, then emit the step itself. Skip a step already in `visited`.

Write this function to be obviously correct rather than clever. It is the heart of the
feature, it is pure, and it is where a subtle bug would produce a plausible-looking plan that
runs the wrong work.

### Milestone 4 — resolve the cohort

At the end of this milestone `seihou agent migrate` loads every blueprint the run needs and
produces an expanded plan.

In `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`, between planning (step 5) and receipt
filtering (step 6), add transitive-closure discovery. The named blueprint is already loaded;
walk the entailed references of its selected edges, discover each named blueprint through
the same `defaultSearchPaths` + `discoverRunnable` path `discoverMigrationBlueprint` uses,
validate each with `validateBlueprint`, and repeat until no new names appear. Bound the loop
by the set of names already loaded, so a cycle in declarations cannot spin here — cycle
*reporting* is `expandEntailedEdges`'s job, but discovery must terminate regardless.

Build, for each loaded blueprint: its `Blueprint`, its directory, and its `ArtifactOrigin`
(via `detectArtifactOrigin projectRoot blueprintDir`, as plan 81 established for the invoked
blueprint). Keep them in a `Map Text` keyed by blueprint name.

Reuse `discoverMigrationBlueprint`'s existing error messages for a name that resolves to a
module, recipe, or prompt — an author who writes `blueprint = "kiroku"` when they meant
`"kiroku-upgrade"` should get the same clear message a user would.

Then call `expandEntailedEdges` with a lookup backed by that map, and render each
`EntailmentError` as a user-facing message. Write these messages carefully; they are the
only feedback a blueprint author gets:

```text
✗ 'keiro-upgrade' edge 2.4.0 -> 3.0.0 entails blueprint 'kiroku-upgrade',
  which is not installed on this machine.

  Install it, then re-run:
    seihou install <url> --module kiroku-upgrade
```

```text
✗ 'keiro-upgrade' edge 2.4.0 -> 3.0.0 entails edge 1.9.0 -> 2.0.0 of
  'kiroku-upgrade', which declares no such edge.

  This is an authoring error in 'keiro-upgrade'. Report it upstream.
  Declared edges of 'kiroku-upgrade': 1.0.0 -> 1.5.0, 1.5.0 -> 2.0.0
```

Listing the declared edges in the second message is worth the extra work: the most likely
cause is an off-by-one in a version string, and showing the real list makes it obvious.

If `docs/plans/83-guard-the-agent-path-against-stale-and-substituted-artifacts.md` has
landed, extend its guard here: every blueprint in the resolved cohort is an artifact this
command is about to use, so ADR 0003's scoping rule implies each should be checked. Do this
after discovery and before any launch. If plan 83 has not landed, leave a note in this
plan's Outcomes section so it is picked up when that plan does.

### Milestone 5 — per-blueprint execution context

At the end of this milestone each step runs with its owning blueprint's reference files,
allowed tools, and resolved variables.

`prepare` currently builds one `PreparedBlueprintExecution`. Build one per loaded blueprint,
keyed by name, each with its own `blueprintDir` so `files/` mounts from the right place. The
`--var` overrides, `--namespace`, and `--context` from the command line apply to every
blueprint in the cohort: a variable the entailed blueprint declares is resolved through the
same precedence chain, and will be prompted for if required and unset. Say so in the
documentation, because it is a user-visible consequence — running a keiro migration may
prompt for a variable declared by kiroku's blueprint.

Resolve variables for every cohort blueprint *before* the first session launches, not lazily
per step. A user should answer all prompts up front rather than being interrupted between
agent sessions.

`launchConfiguredAgentAddingDirs` receives `maybeToList (prepared ^. #mountedFilesDir)` and
the allowed-tools list. Pass the owning blueprint's values per step. Consider whether to
mount *every* cohort blueprint's `files/` directory for every session instead: reject that —
it hands kiroku's reference material to keiro's edge and invites the agent to pre-apply work
from another step, which the framing prompt explicitly tells it not to do.

Provider, model, and effort resolution stays a property of the *command*, not of each step.
The invoked blueprint's `launch` declaration wins, as it does today. An entailed blueprint's
`launch` declaration is ignored, because a single command cannot switch providers between
edges. Document this in `docs/user/blueprints.md` under launch settings, and record the
decision — an author might reasonably expect otherwise.

`renderBlueprintMigrationSystemPrompt` renders `blueprint_name`, `blueprint_version`, and
`blueprint_description` from the prepared execution; with per-step contexts these now name
the owning blueprint, which is correct — the agent should be told it is doing kiroku's
migration. Check the template at `seihou-cli/data/blueprint-migration-prompt.md` for any
wording that assumes a single blueprint across the chain and adjust it, including the
"Step N of M" framing, which should now make the owner visible.

### Milestone 6 — receipts per owner

At the end of this milestone a shared edge is crossed once regardless of entry point.

`pendingBlueprintMigrations` takes one blueprint identity and filters a plan's steps against
it. Change it to take the per-step owner identity instead: for each step, look up its owner's
`(name, origin)` in the cohort map and filter with that. The simplest shape is to have the
caller resolve owner identities and pass a lookup:

```haskell
pendingBlueprintMigrations ::
  Bool ->
  (Text -> Maybe (ModuleName, ArtifactOrigin)) ->
  [AppliedBlueprintMigration] ->
  BlueprintMigrationPlan ->
  [BlueprintMigrationStep]
```

A step whose owner is not in the lookup cannot happen — discovery is complete before this
point — but handle it as "not previously applied" rather than crashing, and add a comment
saying why it is unreachable.

Then `recordMigration` in `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs` writes the
receipt using the *owner's* name, origin, and blueprint version, not the invoked
blueprint's. This single change is what produces the cross-entry-point property, and it
deserves a comment saying so explicitly, because it looks like a mistake to a reader who
does not know the design.

Update the launch announcement and the debug output to name the owner:

```text
Running blueprint migration 1/2: kiroku-upgrade 1.9.0 -> 2.0.0 (entailed by keiro-upgrade 2.4.0 -> 3.0.0)
Running blueprint migration 2/2: keiro-upgrade 2.4.0 -> 3.0.0
```

For that "entailed by" clause the step needs to know what pulled it in. Add an optional
`entailedBy :: !(Maybe (Text, Text, Text))` to `BlueprintMigrationStep` — declaring
blueprint, from, to — populated during expansion. It is display-only and must not enter any
identity comparison; say so in its Haddock.

`formatBlueprintMigrationDebugOutput` builds the `===== [1/2] 1.0.0 -> 2.0.0 =====` headers;
extend them the same way.

### Milestone 7 — tests

Core tests are at `seihou-core/test/`, run with `cabal test seihou-core-test`; CLI tests at
`seihou-cli/test/`, run with `cabal test seihou-cli-test`. Both use `tasty` with `hspec` via
`Test.Tasty.Hspec.testSpec`; each spec module exports `tests :: IO TestTree` and is
registered in the suite's `Main.hs`.

Create `seihou-core/test/Seihou/Core/EntailmentSpec.hs` for `expandEntailedEdges`, which is
pure and where most of the risk lives:

- a step with no entailed edges expands to itself;
- a step with one entailed edge expands to `[entailed, self]` in that order;
- two entailed edges expand in declaration order, both before the declaring edge;
- transitive entailment expands depth-first;
- the same entailed edge referenced by two selected edges appears once;
- a cycle returns `EntailmentCycle` with the chain, and does not hang — give this test a
  timeout;
- an unresolvable blueprint returns `EntailedBlueprintNotFound`;
- a resolvable blueprint missing the exact edge returns `EntailedEdgeNotDeclared`;
- an edge entailing an edge of a blueprint that itself declares entailments back into the
  first blueprint but at a *different* edge is not a cycle and expands correctly. This one
  catches an over-eager cycle check that keys on blueprint name rather than on the edge
  triple.

Add to `seihou-cli/test/Seihou/CLI/BlueprintMigrationSpec.hs`: given a plan whose steps are
owned by two different blueprints and a receipt recorded under the *entailed* blueprint's
identity, only the entailed step is dropped. Then the mirror: a receipt under the invoking
blueprint's identity for the same `from`/`to` does **not** drop the entailed step. That pair
is the regression fence around the design's core claim.

Add an end-to-end case. `seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs` is the existing
model; read it first to see how it drives the command without launching a real provider.
Build two blueprint fixtures on disk — an entailed one and a declaring one — and assert with
`--debug` that the rendered chain contains both steps, in order, each carrying its own
blueprint's reference-file section. `--debug` is the ideal test surface here: it exercises
discovery, expansion, and per-blueprint preparation while contacting no provider and writing
nothing.

### Milestone 8 — documentation and the ADR

`docs/user/blueprint-migrations.md` needs the most work:

- A new section under "For library authors" explaining entailment: what it declares, the
  ordering rule, that the receipt goes to the entailed blueprint, and worked Dhall showing
  keiro entailing kiroku. Use the cohort story from this plan's Purpose — it is the clearest
  motivation available and a reader arriving cold needs it.
- Correct the existing statement that reference files and `allowedTools` are shared by every
  edge. They are shared by every edge *of one blueprint*; a step owned by another blueprint
  gets that blueprint's.
- A note under "For consumers" that one command may run edges from several blueprints, may
  prompt for variables declared by a blueprint they did not name, and that `seihou status`
  will list receipts under those blueprints' names.
- Troubleshooting rows for the two new hard errors.

`docs/user/blueprints.md` — entailment in the `migrations` field reference, and the note
that an entailed blueprint's `launch` declaration is ignored.

`docs/cli/agent.md` — under `agent migrate`, that a chain may span blueprints and that
`--debug` labels each step with its owner.

`schema/README.md` — already updated in milestone 1; verify it still matches.

`docs/user/CHANGELOG.md` — a feature entry.

Finally write the ADR. This is the durable decision:
`docs/adr/0006-an-entailed-migration-edge-is-owned-by-the-blueprint-that-declares-it.md`
(check `ls docs/adr/` for the next free number — do not reuse or fill gaps). It should record
the decision, the alternative of a cohort artifact and why it was rejected, the ordering
rule, and the consequence that a cohort exists only as a transitive closure of declarations
and is never recorded anywhere. Follow the existing file convention exactly: `# ADR NNNN —
Title` heading, `Status` and `Date` lines, then Context / Decision / Consequences as the
existing records do. Read
`docs/adr/0002-artifact-identity-is-origin-url-plus-name.md` first to match the voice.


## Concrete Steps

Run everything from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Confirm both prerequisites:

```bash
rg -n "origin :: !ArtifactOrigin" seihou-core/src/Seihou/Core/Types.hs
rg -n "MigrationNotApplicable" seihou-core/src/Seihou/Core/Types.hs
```

Schema work (milestone 1), following `.claude/skills/update-seihou-schema/SKILL.md`:

```bash
git -C schema fetch origin
git -C schema status --branch --porcelain
dhall type --file schema/package.dhall > /dev/null && echo "package.dhall type-checks"
git -C schema push origin master
```

Build and test after each later milestone:

```bash
cabal build all
cabal test seihou-core-test
cabal test seihou-cli-test
```

Inspect an expanded chain without contacting a provider:

```bash
seihou agent --debug migrate keiro-upgrade --from 2.4.0 --to 3.0.0
```

Full checks before committing:

```bash
nix flake check
```

Commit with all three trailers. The schema submodule commit is separate and does not carry
them:

```text
feat(agent): fan out a migration edge to entailed cohort edges

A blueprint migration edge may declare that it entails an exact edge of
another blueprint. Entailed edges are expanded recursively, run first, use
their own blueprint's files and variables, and record receipts under their
owning blueprint's identity so a shared edge is crossed once from either
entry point.

MasterPlan: docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md
ExecPlan: docs/plans/85-fan-out-a-blueprint-migration-edge-to-entailed-cohort-edges.md
Intention: intention_01m05ew4qbef6tn9bnphy4nv2n
```


## Validation and Acceptance

**Automated.** Both suites pass, including `EntailmentSpec`. The cycle test must complete
rather than hang.

**By hand — the cohort story, end to end.** Build two throwaway git repositories to stand in
for kiroku and keiro. In each, `seihou new-blueprint <name>` scaffolds
`blueprint.dhall`, `prompt.md`, and `files/`; add a `migrations/` directory with one Markdown
file per edge, per `docs/user/blueprint-migrations.md`.

`kiroku-upgrade/blueprint.dhall` declares one edge:

```dhall
migrations =
  [ S.BlueprintMigration::{
    , from = "1.9.0"
    , to = "2.0.0"
    , prompt = ./migrations/1-9-to-2.md as Text
    }
  ]
```

`keiro-upgrade/blueprint.dhall` declares one edge that entails it:

```dhall
migrations =
  [ S.BlueprintMigration::{
    , from = "2.4.0"
    , to = "3.0.0"
    , prompt = ./migrations/2-4-to-3.md as Text
    , entails =
      [ S.EntailedEdge::{ blueprint = "kiroku-upgrade", from = "1.9.0", to = "2.0.0" } ]
    }
  ]
```

Put a distinctive marker file in each blueprint's `files/` directory so you can tell which
reference set each session received.

Install both and inspect the plan:

```bash
seihou install file:///tmp/kiroku --module kiroku-upgrade
seihou install file:///tmp/keiro --module keiro-upgrade
seihou agent --debug migrate keiro-upgrade --from 2.4.0 --to 3.0.0
```

Expected shape:

```text
Blueprint migrations for keiro-upgrade: 2.4.0 -> 3.0.0
===== [1/2] kiroku-upgrade 1.9.0 -> 2.0.0 (entailed by keiro-upgrade 2.4.0 -> 3.0.0) =====
...kiroku's shared prompt, kiroku's reference files, kiroku's edge prompt...

===== [2/2] keiro-upgrade 2.4.0 -> 3.0.0 =====
...keiro's shared prompt, keiro's reference files, keiro's edge prompt...
```

Two things to verify by eye: the kiroku step comes first, and each step's "Reference Files"
section lists that blueprint's marker file and not the other's.

**The deduplication property — the decisive test.** Run the chain for real once, then:

```bash
cat .seihou/manifest.json | jq '.blueprintMigrations'
```

The kiroku receipt must be recorded under `"name": "kiroku-upgrade"` with kiroku's repository
in its `origin`, not under `keiro-upgrade`. Then run the kiroku blueprint directly:

```bash
seihou agent --debug migrate kiroku-upgrade --from 1.9.0 --to 2.0.0
```

Expected:

```text
All blueprint migrations in the requested version window already have receipts.
```

That is the whole design working: a project that reaches a cohort edge through keiro does not
cross it again through kiroku. Then check the reverse order in a fresh scratch project — run
`kiroku-upgrade` first, then `keiro-upgrade` — and confirm the keiro chain shows only its own
step as pending.

**The kiroku-only consumer is unaffected.** In a project with only `kiroku-upgrade`
installed, `seihou agent --debug migrate kiroku-upgrade --from 1.9.0 --to 2.0.0` plans one
step and never mentions keiro.

**Error paths.** Uninstall `kiroku-upgrade` and re-run the keiro chain: it must fail with the
not-installed message and exit nonzero, not skip the step. Then edit keiro's `entails` to
name an edge kiroku does not declare and confirm the second error message, including the list
of kiroku's real edges.

**Module migrations are unaffected.** `seihou migrate <module>` must behave exactly as before
— `planMigrationWindow` is shared. Run the existing module-migration tests and one manual
`seihou migrate --dry-run` against any module with declared migrations.


## Idempotence and Recovery

Source edits and one schema publication. The schema push is the only step that is not
locally reversible: once a commit is pushed to `shinzui/seihou-schema`, other repositories
can pin it. That is safe here because the change is purely additive — a new optional field
with an empty default and a new exported type — so no existing `blueprint.dhall` stops
type-checking. If the field's shape turns out to be wrong, publish a corrected version and
re-pin rather than force-pushing.

Re-running the build, the tests, and `--debug` planning is safe and free of side effects.
`--debug` in particular writes nothing and contacts no provider, so it can be used freely
while iterating on expansion.

For users, the recovery paths are the existing ones. A chain interrupted partway leaves
receipts for completed steps and resumes at the first unrecorded one; that behaviour is
unchanged and now spans blueprints. `--rerun` re-runs the selected steps, which under
entailment means every step in the expanded chain — note that in the documentation, because
a user who wants to re-run only the keiro half has to invoke it differently.

If a cohort is misconfigured such that expansion always errors, the consumer's escape hatch
is to run the entailed blueprint directly by name; that path never expands anything it does
not need and is unaffected by the declaring blueprint's mistake. Say this in the
troubleshooting rows.

If work stops mid-plan, the safe stopping points are the end of milestone 1 (schema
published, nothing reads it), milestone 3 (expansion exists and is tested, nothing calls it),
and milestone 5 (per-blueprint contexts built, receipts still written under the invoked
blueprint). Do not stop between milestones 5 and 6 in a released state: running entailed
edges while recording their receipts under the invoking blueprint would write receipts that
are wrong in a way later runs cannot detect.


## Interfaces and Dependencies

No new library dependencies. The schema submodule gains one file.

At the end of the plan these must exist.

`schema/EntailedEdge.dhall`

```dhall
{ Type = { blueprint : Text, from : Text, to : Text }, default = {=} }
```

`schema/BlueprintMigration.dhall`

```dhall
{ Type = { from : Text, to : Text, prompt : Text, entails : List EntailedEdge.Type }
, default = { entails = [] : List EntailedEdge.Type }
}
```

`seihou-core/src/Seihou/Core/Migration.hs`

```haskell
data EntailedEdge = EntailedEdge
  { blueprint :: !Text, from :: !Text, to :: !Text }
  deriving stock (Eq, Show, Generic)

data BlueprintMigration = BlueprintMigration
  { from :: !Text, to :: !Text, prompt :: !Text, entails :: ![EntailedEdge] }
  deriving stock (Eq, Show, Generic)

data BlueprintMigrationStep = BlueprintMigrationStep
  { owner :: !Text,
    edge :: !BlueprintMigration,
    entailedBy :: !(Maybe (Text, Text, Text))
  }
  deriving stock (Eq, Show, Generic)

data BlueprintMigrationPlan = BlueprintMigrationPlan
  { name :: !Text, from :: !Version, to :: !Version, steps :: ![BlueprintMigrationStep] }
  deriving stock (Eq, Show, Generic)

data EntailmentError
  = EntailedBlueprintNotFound !Text
  | EntailedEdgeNotDeclared !Text !Text !Text !Text
  | EntailmentCycle ![Text]
  deriving stock (Eq, Show, Generic)

expandEntailedEdges ::
  (Text -> Maybe [BlueprintMigration]) ->
  [BlueprintMigrationStep] ->
  Either EntailmentError [BlueprintMigrationStep]
```

`seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`

```haskell
pendingBlueprintMigrations ::
  Bool ->
  (Text -> Maybe (ModuleName, ArtifactOrigin)) ->
  [AppliedBlueprintMigration] ->
  BlueprintMigrationPlan ->
  [BlueprintMigrationStep]
```

Hard dependencies: `docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md` and
`docs/plans/84-add-a-not-applicable-outcome-for-blueprint-migration-edges.md`.

Soft dependencies: `docs/plans/82-refuse-to-overwrite-an-installation-from-a-different-source.md`
and `docs/plans/83-guard-the-agent-path-against-stale-and-substituted-artifacts.md`.

`docs/plans/86-infer-the-blueprint-migration-version-window.md` soft-depends on this plan:
it consumes `BlueprintMigrationStep` and extends the `--debug` and `--verbose` output this
plan reshapes, and it publishes its own schema field on top of the pin this plan establishes.
