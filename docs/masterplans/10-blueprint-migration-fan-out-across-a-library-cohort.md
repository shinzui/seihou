---
id: 10
slug: blueprint-migration-fan-out-across-a-library-cohort
title: "Blueprint Migration Fan-Out Across a Library Cohort"
kind: master-plan
created_at: 2026-08-16T14:16:12Z
intention: "intention_01m05ew4qbef6tn9bnphy4nv2n"
---

# Blueprint Migration Fan-Out Across a Library Cohort

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Vision & Scope

A blueprint migration is an agent-guided upgrade step a library author ships with a
blueprint: one Markdown prompt per version edge, run by `seihou agent migrate <blueprint>
--from X --to Y`, with a receipt written into `.seihou/manifest.json` after each edge so an
interrupted chain resumes where it stopped. Today that machinery assumes the library whose
version edge is being crossed is the same library the consumer names on the command line.
That assumption breaks the moment a breaking change travels through an intermediary.

The motivating shape is a three-link chain. `mori://shinzui/kiroku` ships a breaking change.
`mori://shinzui/keiro` depends on kiroku and absorbs that change in one of its own releases.
Most consuming projects — `mori://shinzui/mori` among them — depend on keiro and never name
kiroku, while a small number of projects depend on kiroku directly and never touch keiro. A
consumer knows which keiro version they are on; they neither know nor should have to look up
which kiroku version keiro pulls in transitively. So the version window a consumer can
supply is always the window of the library they actually declare, and the upgrade knowledge
that has to reach them lives one repository away.

After this initiative, a library author publishes one blueprint per library a consumer
actually declares, versioned in that library's own version space, and an edge in one
blueprint may declare that crossing it *entails* crossing a named edge in another
blueprint. keiro's `2.4.0 -> 3.0.0` edge entails kiroku's `1.9.0 -> 2.0.0` edge. A mori
maintainer then runs one command:

```bash
seihou agent migrate keiro-upgrade --to 3.0.0
```

and gets both edges, in order, each with its own blueprint's reference files, allowed tools,
and resolved variables. A project that depends on kiroku alone runs `seihou agent migrate
kiroku-upgrade` and is unaffected by keiro's existence. A project that depends on both runs
either command and crosses the shared kiroku edge exactly once, because every receipt is
keyed by the origin and name of the blueprint that *owns* the edge rather than by whichever
blueprint the user happened to type. An edge whose precondition is not met in a particular
project — the common case once one blueprint serves both direct and indirect consumers —
reports itself not-applicable, records that outcome honestly, and does not suppress a later
run once the precondition is met. And the version window stops being two hand-typed
numbers: `--to` defaults to a version the blueprint knows how to read out of the project,
and `--from` defaults to how far the receipt ledger says this project has already been
migrated.

Four Improvement Requests already filed against seihou are prerequisites rather than
side quests, because fan-out multiplies exactly the failures they describe. Installing a
cohort means installing several blueprints from several repositories into one install cache
keyed by bare name (IR-4). Resolving an entailed edge means resolving a second blueprint by
name and trusting that it is the one the project's manifest means (IR-2, IR-3). Serving
direct and indirect consumers from one edge means most runs of that edge legitimately do
nothing (IR-1). All four are implemented here.

In scope:

- Origin on every agent-path manifest record, and origin as part of the blueprint migration
  completion key (`docs/improvement-requests/record-artifact-origin-for-agent-applied-artifacts.md`, IR-2).
- An install-time refusal when an artifact name is about to be overwritten by an artifact
  from a different repository (`docs/improvement-requests/refuse-to-overwrite-an-installation-from-a-different-source.md`, IR-4).
- `ManifestGuard` on `seihou agent run` and `seihou agent migrate`
  (`docs/improvement-requests/guard-the-agent-path-against-stale-and-substituted-artifacts.md`, IR-3).
- A not-applicable outcome an edge can report, distinct from success and failure
  (`docs/improvement-requests/add-a-not-applicable-outcome-for-blueprint-migration-edges.md`, IR-1).
- A new `entails` field on the blueprint migration schema, recursive expansion of entailed
  edges into one ordered plan, and per-owning-blueprint reference files, allowed tools, and
  variable resolution for each step.
- A declared version probe supplying the default `--to`, and a receipt-derived default
  `--from`.

Explicitly excluded:

- **Authoring the cohort blueprints themselves.** The `kiroku-upgrade` and `keiro-upgrade`
  blueprints, their shared prompt fragments, and their registry entries belong to
  `mori://shinzui/kiroku` and `mori://shinzui/keiro`. Any capability those repositories turn
  out to need is filed as an Improvement Request in that repository and referenced here by
  its `mori://` URI, not implemented as a child plan of this MasterPlan.
- **Deterministic module migrations** (`seihou migrate`, `schema/Migration.dhall`,
  `Seihou.Engine.Migrate`). They are declared file operations with no agent judgement, so
  none of the four IRs and none of the fan-out semantics apply to them. The one contact
  point is `planMigrationWindow` in `seihou-core/src/Seihou/Core/Migration.hs`, shared by
  both planners; changes there must keep module migration behaviour byte-identical.
- **Namespacing the install cache by repository** (`installed/<repo>/<name>`). IR-4
  considers and rejects this: it changes artifact resolution for every command and
  invalidates every existing installation. The refusal added by EP-82 stays correct if the
  cache is ever re-laid-out.
- **Verifying that a migration worked.** A receipt records that a provider interaction
  returned, not that the build passes. That contract, documented in
  `docs/user/blueprint-migrations.md`, is unchanged; EP-84 adds a third outcome to it
  without promoting the other two into proof.


## Decomposition Strategy

The work is decomposed by functional concern, and the concerns fall into three layers: what
a receipt *is* (identity and outcome), what the commands *refuse* (install-time and
use-time), and what the planner *does* (fan-out and window inference).

The spine is EP-81, receipt identity. Both EP-84 (a new outcome) and EP-85 (fan-out) change
`AppliedBlueprintMigration` and the `alreadyApplied` predicate in
`seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`. Landing origin first means each later
plan extends a settled record and a settled completion key rather than racing another plan
for the same three lines. EP-81 is also the plan that makes fan-out *correct* rather than
merely convenient: cross-entry-point deduplication depends on two projects' receipts for the
same kiroku edge being recognisably the same receipt, and a bare name cannot establish that
when the install cache is keyed by bare name too.

The two refusal plans are deliberately separate from each other and from the spine. EP-82
acts at install time, in `installModuleDir`
(`seihou-cli/src/Seihou/CLI/InstallShared.hs`), and touches no manifest type at all, so it
can proceed in parallel with everything. EP-83 acts at use time, in
`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` and
`seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`, and cannot start before EP-81 because
`ManifestGuard` has no origin to compare against until the agent-path records carry one.
Merging them was considered and rejected: they refuse different things (an incoming
artifact versus a recorded one), at different times, in different modules, and IR-4 argues
each is useful alone.

EP-84 and EP-85 are separated even though the motivating story needs both, because the
not-applicable outcome is independently verifiable and independently valuable — it is the
IR-1 defect exactly as filed, reproducible today with a single blueprint and no fan-out.
Folding it into EP-85 would bury a correctness fix inside a feature.

EP-85 is the largest plan and the one the initiative exists for. It absorbs per-edge
reference files rather than splitting them out, because entailment *requires* them: an
entailed kiroku edge's reference material lives in kiroku's blueprint directory, so
"which files does this step get" stops being a nice-to-have the moment a step can be owned
by a blueprint other than the one named on the command line.

EP-86 is last because it is pure ergonomics over a settled plan shape, and because the
receipt-derived `--from` default must respect the origin-aware completion key EP-81
establishes.

Six child plans, no phases. The natural parallel front is EP-81 and EP-82 together; after
EP-81 lands, EP-83 and EP-84 can proceed concurrently.

### ADR context

`docs/adr/` in this repository is a plain filesystem corpus, not a profile-governed OKF
bundle — `mori.dhall` registers exactly one bundle, `docs/improvement-requests`. New or
revised ADRs therefore keep the established convention: one file per decision named
`NNNN-slug.md`, a `# ADR NNNN — Title` heading, and `Status` / `Date` lines. Do not add OKF
frontmatter or allocate a Mori handle for an ADR as an incidental edit.

Four local ADRs govern this initiative:

- `docs/adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md` — the manifest is
  checked into version control and may not record a path meaningful only on the machine that
  wrote it. This is why every new record field added by EP-81 must be an `ArtifactOrigin`
  and never a directory.
- `docs/adr/0002-artifact-identity-is-origin-url-plus-name.md` — an artifact's identity in
  the manifest is its origin URL plus its name, and a bare name is explicitly rejected as an
  identity because two registries can publish the same name. EP-81 brings the three
  agent-path records into line with this; EP-85 depends on it for cross-blueprint receipt
  matching.
- `docs/adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md` — a command about to
  generate from an artifact refuses when the local copy is older than, or from a different
  source than, what the manifest records, and warn-and-continue is rejected by name. EP-83
  extends this decision to the agent path it does not currently reach; EP-82 applies the
  same reasoning one layer earlier, at install time.
- `docs/adr/0004-the-manifest-is-the-only-record-of-applied-state.md` — there is no
  lockfile; the manifest is the single record of what was applied. This is the reason EP-86
  derives the default `--from` from the receipt ledger rather than introducing any new
  state file, and the reason the version probe reads the *project's own* dependency
  declaration rather than anything seihou persists.

`docs/adr/0005-legacy-manifests-convert-through-an-explicit-command.md` is relevant only as
a constraint on EP-81: it decides that legacy manifests convert through
`seihou manifest upgrade` rather than silently, so EP-81 must choose between a decoder
default and a schema bump deliberately and record which.

Mori was searched for cross-repository decisions governing migration ledgers and artifact
identity (`mori registry concepts --search 'migration'`, `--search 'artifact identity'`).
The hits — `mori://shinzui/rei/okf/adrs/concepts/ADR-4` and
`mori://shinzui/pgmq-hs/okf/capabilities/concepts/CAP-8` — are about database migration
histories and are not relevant here. No cross-repository ADR governs blueprint migration
receipts.

Cross-plan decisions expected to deserve ADR records at completion are listed under
Integration Points.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| EP-81 | Record artifact origin for agent-applied artifacts | docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md | None | None | Complete |
| EP-82 | Refuse to overwrite an installation from a different source | docs/plans/82-refuse-to-overwrite-an-installation-from-a-different-source.md | None | None | In Progress |
| EP-83 | Guard the agent path against stale and substituted artifacts | docs/plans/83-guard-the-agent-path-against-stale-and-substituted-artifacts.md | EP-81 | EP-82 | Not Started |
| EP-84 | Add a not-applicable outcome for blueprint migration edges | docs/plans/84-add-a-not-applicable-outcome-for-blueprint-migration-edges.md | EP-81 | None | Not Started |
| EP-85 | Fan out a blueprint migration edge to entailed cohort edges | docs/plans/85-fan-out-a-blueprint-migration-edge-to-entailed-cohort-edges.md | EP-81, EP-84 | EP-82, EP-83 | Not Started |
| EP-86 | Infer the blueprint migration version window | docs/plans/86-infer-the-blueprint-migration-version-window.md | EP-81 | EP-85 | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3).


## Dependency Graph

EP-81 and EP-82 have no dependencies and may be implemented in either order or
simultaneously. They touch disjoint code: EP-81 changes
`seihou-core/src/Seihou/Core/Types.hs`, `seihou-core/src/Seihou/Manifest/Types.hs`, and the
completion key in `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`; EP-82 changes only
`installModuleDir` in `seihou-cli/src/Seihou/CLI/InstallShared.hs` and its callers' flag
plumbing.

EP-83 hard-depends on EP-81. `Seihou.CLI.ManifestGuard.judgeArtifact` takes a recorded
`ArtifactOrigin` as its first argument; until `AppliedBlueprint` and
`AppliedBlueprintMigration` carry one, the agent path has nothing to pass and can only
detect the staleness half of ADR 0003, not the substitution half. EP-83 soft-depends on
EP-82: a machine where install-time refusal is already in place is much harder to get into
the substituted state EP-83 detects, so implementing EP-82 first makes EP-83's manual
reproduction steps require deliberate setup rather than being reachable by accident. EP-83
does not block anything.

EP-84 hard-depends on EP-81 because both plans rewrite `AppliedBlueprintMigration`, its two
JSON instances, and the `alreadyApplied` predicate in `pendingBlueprintMigrations`. This is
a sequencing dependency to avoid two plans editing the same completion key; EP-84's outcome
field is meaningless to interleave with EP-81's origin field.

EP-85 hard-depends on EP-81 and EP-84. On EP-81 because an entailed edge is recorded under
the *entailed* blueprint's identity, and identity must include origin or a project that
consumes two same-named blueprints from different repositories will have real work silently
skipped — the precise failure IR-2 describes, made routine by fan-out. On EP-84 because an
entailed edge is, by construction, an edge that frequently does not apply to the project
running it: without a not-applicable outcome, every inapplicable entailed edge writes an
"applied" receipt that then suppresses the direct run of that same edge under the
origin-aware key EP-81 introduces. EP-85 soft-depends on EP-82 and EP-83: cohort resolution
loads a second blueprint by bare name from the install cache, which is exactly the surface
those two plans harden.

EP-86 hard-depends on EP-81 because the default `--from` is derived by selecting receipts
that match the blueprint's identity, and matching on bare name would pick a receipt written
by a different repository's blueprint of the same name. It soft-depends on EP-85: window
inference is useful for a single blueprint but is most valuable for a cohort chain, and the
`--debug` output it must extend is the output EP-85 reshapes.

Serialised critical path: EP-81 → EP-84 → EP-85 → EP-86. EP-82 runs alongside from the
start; EP-83 runs alongside once EP-81 lands.


## Integration Points

**`AppliedBlueprintMigration` and its JSON encoding**
(`seihou-core/src/Seihou/Core/Types.hs`, `seihou-core/src/Seihou/Manifest/Types.hs`).
Involved: EP-81, EP-84, EP-85, EP-86. **Settled by EP-81 (complete).** All three records carry
`origin :: !ArtifactOrigin` immediately after `name`, encoded under the JSON key `origin`,
matching `AppliedModule`. EP-84 extends `AppliedBlueprintMigration` with an outcome field and must
not alter that encoding. EP-85 and EP-86 read the record and must not add fields to it.

EP-81 chose the decoder default over a schema bump: `currentManifestVersion` stays at 6, and a
record with no `origin` key decodes as `LocalOrigin` of its recorded name via `legacyLocalOrigin`
in `seihou-core/src/Seihou/Manifest/Types.hs`. The rationale is in EP-81's Decision Log — the
origin of an already-recorded artifact is genuinely unrecoverable, so an explicit conversion
command per ADR 0005 could only write the same weak value, and ADR 0005's rule is for conversions
that lose or relocate information. **EP-84 must follow the same approach**: give the outcome field
a decoder default meaning "applied", so a receipt written before the field existed keeps its
current meaning, and do not bump the schema version.

**The migration completion key** — the `alreadyApplied` predicate inside
`pendingBlueprintMigrations` in `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`.
Involved: EP-81, EP-84, EP-85, EP-86. **Settled by EP-81 (complete).** The key is
`(origin, name, from, to)`, and `pendingBlueprintMigrations` now takes the invoked blueprint's
`ArtifactOrigin` as its second argument:

```haskell
pendingBlueprintMigrations ::
  Bool ->
  ArtifactOrigin ->
  ModuleName ->
  [AppliedBlueprintMigration] ->
  BlueprintMigrationPlan ->
  [BlueprintMigration]
```

Origins are compared with `Seihou.Core.ArtifactIdentity.sameArtifactIdentity`, never structural
`==`, so that two spellings of one git URL are one identity. The two ledger helpers in
`seihou-core/src/Seihou/Manifest/Types.hs` — `writeAppliedBlueprintMigration`'s `sameEdge` and
`hasAppliedBlueprintMigration`, whose signature gained an `ArtifactOrigin` first parameter — use
the same function, so a receipt cannot be written as a new entry while being read as a duplicate.

EP-84 makes the predicate consider only receipts whose outcome is "applied". EP-85 calls it once
per expanded step using that step's *owning* blueprint identity rather than the invoked
blueprint's, which is the mechanism by which one project crossing the same cohort edge from two
entry points crosses it once. EP-86 reads receipts through the same key to compute the default
`--from`. The predicate's doc comment must state, at every stage, which fields are part of the key
and which are deliberately excluded; EP-81 left it saying that artifact versions and timestamps
are intentionally excluded while origin is included, and that passage must stay true and grow.

**The blueprint migration plan type** — `BlueprintMigrationPlan` in
`seihou-core/src/Seihou/Core/Migration.hs`, whose `steps` field is `[BlueprintMigration]`
today. Involved: EP-85, EP-86. EP-85 owns the change: a step must carry the name of the
blueprint that declared it, so `steps` becomes a list of a new step record rather than of
bare edges. EP-86 consumes the new shape and must not widen it. `planMigrationWindow` in
the same module is shared with module migrations and must remain behaviourally unchanged
for them.

**The blueprint Dhall schema** — the `schema/` git submodule, a working copy of
`shinzui/seihou-schema`, plus the pinned URL and hash in `SchemaVersion.hs` and
`flake.lock`. Involved: EP-85 (adds `entails` to `schema/BlueprintMigration.dhall` and a new
`schema/EntailedEdge.dhall`), EP-86 (adds `versionProbe` to `schema/Blueprint.dhall`). Both
must follow the `update-seihou-schema` skill: author in the submodule, push to
`shinzui/seihou-schema` before re-pinning, then bump `SchemaVersion.hs` and `flake.lock`.
Because both plans touch `schema/package.dhall` and `schema/README.md`, EP-85 lands its
schema change first and EP-86 rebases onto the resulting pin rather than publishing a
competing one. Both must keep the corresponding decoder in
`seihou-core/src/Seihou/Dhall/Eval.hs` tolerant of blueprints that predate the new field,
using the existing `withDefaults` mechanism.

**The agent-path command entry points** — `handleAgentRun` in
`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` and `handleAgentMigrate` in
`seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`. Involved: EP-83, EP-85, EP-86. EP-83
inserts a guard check before any work and owns where in the sequence it sits — specifically,
before `applyBaseline` in `agent run` and before planning in `agent migrate`. EP-85 and
EP-86 add work after that point and must not move the guard earlier or later. All three
must preserve the rule that `--debug` performs no check, applies no baseline, contacts no
provider, and writes nothing.

**Documentation surfaces.** Involved: all six. Each plan updates `docs/cli/agent.md` and/or
`docs/cli/install.md` for flags and behaviour, `docs/user/blueprint-migrations.md` for the
migration workflow, `docs/user/blueprints.md` for authoring, and appends to
`docs/user/CHANGELOG.md`. There is no separate documentation plan; a child plan is not
complete until its own documentation is updated. `docs/user/blueprint-migrations.md` is the
one file every plan from EP-84 onward edits, so each should re-read it immediately before
editing rather than assuming the shape it had when this MasterPlan was written.

Cross-plan decisions expected to become ADRs at completion:

- **Receipt identity includes the origin of the blueprint that owns the edge.** *Recorded.*
  EP-81 amended `docs/adr/0002-artifact-identity-is-origin-url-plus-name.md` rather than adding
  a record, extending it from "what the manifest records about an artifact" to "what makes two
  records of the same work the same record", and noting that the comparison has one definition in
  `Seihou.Core.ArtifactIdentity` because three call sites must agree. See the Decision Log entry
  dated 2026-08-16 for why the anticipated new ADR was deferred to EP-85 instead.
- **An entailed edge is owned by the blueprint that declares it, not by the blueprint that
  names it.** This is the architectural boundary the whole fan-out design rests on and is
  the reason a cohort does not need a coordinating artifact. Record it during EP-85.
- **A deliberate no-op is a third outcome, not a success.** Record during EP-84; note the
  structurally identical decision in `mori://shinzui/keiro` that IR-1 cites.
- **Deliberate exclusion: no cohort artifact.** A `Recipe`-like artifact listing member
  blueprints and a version map per cohort release was considered and rejected in favour of
  per-edge entailment. Record the rationale so a future contributor does not re-open it
  without new information.


## Progress

- [x] EP-81: `ArtifactOrigin` added to `AppliedBlueprint`, `AppliedBlueprintMigration`, and `AppliedRecipe`, with JSON round-trip tests — 2026-08-16
- [x] EP-81: completion key extended to include origin, with a spec proving two same-named blueprints from different origins do not share receipts — 2026-08-16
- [x] EP-81: legacy manifests without `origin` decode as unverifiable provenance; documentation and CHANGELOG updated — 2026-08-16
- [ ] EP-82: `installModuleDir` reads `.seihou-origin.json` before removal and refuses on a different source, with `--force` override
- [ ] EP-82: same-source reinstall stays frictionless; `seihou migrate`'s install refresh verified to take the same-source path
- [ ] EP-83: `seihou agent run` consults `ManifestGuard` before `applyBaseline`, leaving the tree byte-identical on refusal
- [ ] EP-83: `seihou agent migrate` consults `ManifestGuard` before planning; `--debug` still checks nothing
- [ ] EP-84: an edge can report not-applicable; the outcome is recorded and does not suppress a later run
- [ ] EP-84: framing prompt template tells the agent how to signal it; `seihou status` renders the outcome
- [ ] EP-85: `entails` published in `seihou-schema` and re-pinned; decoder tolerates blueprints without it
- [ ] EP-85: recursive entailment expansion with cycle detection, in a pure planner
- [ ] EP-85: each step runs with its owning blueprint's reference files, allowed tools, and variables
- [ ] EP-85: a shared edge reached from two entry points is crossed once; end-to-end spec proves it
- [ ] EP-86: `versionProbe` published and re-pinned; `--to` defaults to the probe's output
- [ ] EP-86: `--from` defaults to the highest recorded receipt for this blueprint identity
- [ ] EP-86: both defaults reported in `--verbose` and `--debug` output with their source


## Surprises & Discoveries

- **The "same artifact?" comparison is a core concern, not a CLI one, and EP-81 has already
  placed it.** EP-81's plan proposed exporting `normalizeOriginUrl` from
  `seihou-cli/src/Seihou/CLI/ManifestGuard.hs` for a helper local to
  `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`. That could not work: two of the three
  places the Integration Points section requires to agree —
  `writeAppliedBlueprintMigration`'s `sameEdge` and `hasAppliedBlueprintMigration` — are in
  `seihou-core`, which cannot import from `seihou-cli`. The comparison now lives in a new
  module, `seihou-core/src/Seihou/Core/ArtifactIdentity.hs`, exporting `sameArtifactIdentity`,
  `normalizeOriginUrl`, and `normalizeProjectPath`; `ManifestGuard`'s private copies of the two
  normalisers were deleted in favour of it, and its three-way `judgeArtifact` verdict is
  untouched.

  **Consequence for EP-84, EP-85, and EP-86:** compare recorded origins with
  `Seihou.Core.ArtifactIdentity.sameArtifactIdentity`, never structural `==`. EP-85 in
  particular calls `pendingBlueprintMigrations` once per expanded step with that step's owning
  origin, and a `.git` spelling difference between the entailing blueprint's declaration and the
  entailed blueprint's install record would otherwise cross a shared edge twice — the exact
  failure the fan-out design exists to prevent.

- **Adding a strict field to a manifest record surfaces write sites a search does not.** EP-81's
  plan named three sites for `AppliedRecipe`/`AppliedBlueprint`/`AppliedBlueprintMigration`
  construction; there were four. `seihou-cli/src/Seihou/CLI/Update.hs` rebuilds the recipe record
  in `buildFinalManifest` when `seihou update` republishes the manifest. EP-84 adds a field to
  `AppliedBlueprintMigration` and should expect the same: add the field first, then treat the
  `[GHC-95909]` error list as the site inventory rather than planning the list up front.

- **Closing an Improvement Request has a required frontmatter shape.** The bundle profile at
  `docs/improvement-requests/profile.dhall` does not accept `status: implemented`; the terminal
  value is `completed`, which requires `completedAt` and recommends `resolution`. EP-82, EP-83,
  and EP-84 each close an IR and should set `status`, `completedAt`, `resolution`, and
  `targetPlan` in one edit. Separately, `okf validate --strict --profile-enforce` already exits 1
  for all four documents because none carries the recommended `reviews` field; that is
  pre-existing, and the check to apply is that closing a request adds no new line to the output.


## Decision Log

- Decision: Decompose into six child plans with EP-81 (receipt identity) as the spine,
  rather than implementing the four IRs as one plan and fan-out as another.
  Rationale: EP-81, EP-84, and EP-85 all rewrite `AppliedBlueprintMigration` and the
  `alreadyApplied` completion key. Sequencing them through a single owning plan for that
  record avoids three plans racing for the same predicate, and leaves each IR independently
  verifiable as filed.
  Date: 2026-08-16

- Decision: Treat IR-1 through IR-4 as prerequisites of the fan-out feature rather than as
  independent maintenance.
  Rationale: Fan-out makes each of their failure modes routine instead of rare. Entailment
  resolves a second blueprint by bare name from a name-keyed install cache (IR-4), records
  receipts under that second blueprint's identity (IR-2), acts on artifacts the manifest
  names without checking them (IR-3), and runs edges that frequently do not apply to the
  project at hand (IR-1). Shipping entailment without them would convert four latent silent
  failures into likely ones.
  Date: 2026-08-16

- Decision: Model cohort propagation as per-edge entailment between blueprints, not as a new
  cohort artifact listing member blueprints and their versions.
  Rationale: Entailment reuses machinery that already exists — receipts are already keyed
  per edge, so cross-entry-point deduplication falls out for free once identity includes
  origin. A cohort artifact would need its own version space, its own registry entry kind,
  its own receipts, and an answer for what happens when a member is absent. Revisit only if
  a cohort grows past the point where per-edge declaration is legible.
  Date: 2026-08-16

- Decision: An entailed edge's receipt is written under the identity of the blueprint that
  *declares* it, not the blueprint the user invoked.
  Rationale: This is what makes `seihou agent migrate keiro-upgrade` and `seihou agent
  migrate kiroku-upgrade` agree about a shared kiroku edge. Writing the receipt under the
  invoking blueprint would make the same work look like two different edges and cross it
  twice in a project that consumes both libraries directly.
  Date: 2026-08-16

- Decision: Scope every child plan to this repository and the `seihou-schema` submodule;
  file Improvement Requests in `mori://shinzui/kiroku`, `mori://shinzui/keiro`, and
  `mori://shinzui/mori` for anything those repositories need.
  Rationale: Confirmed with the initiative owner. The seihou capability and the cohort
  content that uses it have different owners and release cadences, and the IR channel
  already exists for exactly this direction of request — the four IRs implemented here were
  filed against seihou from `mori://shinzui/okf-profiles` the same way.
  Date: 2026-08-16

- Decision: Amend `docs/adr/0002-artifact-identity-is-origin-url-plus-name.md` during EP-81
  rather than write a new ADR; the new ADR the Integration Points section anticipates is
  deferred to EP-85.
  Rationale: The Integration Points section left this open, conditioned on whether EP-85 lands.
  What EP-81 established — that a receipt's identity is the origin and name of the owning
  blueprint plus the edge window, that origin is included while artifact version and timestamp
  are excluded, and that one shared definition of "same artifact" must serve all three key
  comparisons — is the *same* decision ADR 0002 already makes, extended from "what the manifest
  records about an artifact" to "what makes two records of the same work the same record". It is
  recorded there as an amendment with a dated note. The genuinely new decision is EP-85's: that
  an entailed edge is owned by the blueprint that declares it, which is what lets one project
  cross a shared cohort edge exactly once from two entry points. That has no home in ADR 0002 and
  gets its own record when EP-85 lands.
  Date: 2026-08-16

- Decision: `--to` defaults to a blueprint-declared version probe; `--from` defaults to the
  receipt ledger. Not the reverse.
  Rationale: The two ends of the window answer different questions. The probe reads how far
  the *dependency* has been bumped in this project, which is the target, because the normal
  workflow is to bump the dependency and then migrate the source to match. The receipt
  ledger records how far the *source* has already been migrated, which is the start. Using
  the probe for `--from` would report nothing to do for any project that bumped its
  lockfile first — that is, for the workflow the feature exists to serve.
  Date: 2026-08-16


## Outcomes & Retrospective

(To be filled during and after implementation.)
