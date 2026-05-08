---
id: 3
slug: agent-driven-blueprints
title: "Introduce Blueprints, an Agent-Driven Runnable Type for Highly Dynamic Modules"
kind: master-plan
created_at: 2026-05-07T00:00:00Z
intention: "intention_01kr2q5p3ye30t4vk9fj4q69t1"
---


# Introduce Blueprints, an Agent-Driven Runnable Type for Highly Dynamic Modules

Intention: intention_01kr2q5p3ye30t4vk9fj4q69t1

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/master-plan/MASTERPLAN.md`.


## Vision & Scope

Today, Seihou recognises two runnable artifacts: **modules** (`module.dhall`,
deterministic generators that emit files via the Copy / Template / DhallText /
Structured strategies) and **recipes** (`recipe.dhall`, named compositions of
modules with pre-bound variables). Both are designed to be executed by `seihou
run` against a fully-resolved configuration: every input is captured by a
`VarDecl`, every output is a deterministic function of those inputs, and the
manifest at `.seihou/manifest.json` records the result so subsequent runs
diff against it.

This deterministic shape works beautifully for project shapes that vary along
small, well-understood axes (project name, license, list of GHC extensions,
Nix system tuple, etc.). It fits poorly for project shapes whose variation is
inherently open-ended: "scaffold a microservice for $domain", "set up a CI
pipeline that mirrors $existingProject's conventions", "wire in observability
that matches our team's $existingPattern". Encoding all the relevant axes as
typed `VarDecl`s produces modules with dozens of optional variables, brittle
template matrices, and far too many `{{#if}}` branches; a human author
rapidly hits the limit of what is reasonable to enumerate ahead of time.

After this initiative, Seihou ships a third runnable type — **the
Blueprint** (`blueprint.dhall`) — purpose-built for these high-dynamism
cases. A Blueprint is a *non-deterministic* artifact authored by a human and
consumed by an AI coding agent (Claude Code, via the existing `seihou agent
…` infrastructure). It bundles three things:

1. **A base prompt** (Markdown, supporting `{{var}}` placeholders) that
   describes what the agent is trying to accomplish, what conventions to
   follow, and how to use the supplied scaffolding.
2. **An optional baseline** — zero or more existing seihou modules listed as
   "base modules" — that the agent applies as a starting point before
   customising. The baseline gives the agent a concrete, validated scaffold
   to begin from rather than starting from an empty directory.
3. **An optional set of reference files** in a `files/` subdirectory
   (snippets, partial templates, example configurations) that the agent has
   read access to and can copy, adapt, or learn from while working with the
   user.

What a contributor sees after this initiative:

- The user runs `seihou agent run my-blueprint "set this up for a payments
  microservice"`. The CLI resolves the blueprint, prompts for any required
  up-front variables (such as the service name, the team owning it, and the
  language), optionally applies the baseline modules, then launches an
  interactive Claude Code session pre-loaded with the rendered prompt, the
  blueprint's `files/` directory mounted as a read-only reference, and the
  full seihou and git toolset available. The agent and the user iterate on
  the actual project files until the user is satisfied.
- The user attempts `seihou run my-blueprint` — the deterministic command —
  and the CLI refuses with a clear, actionable message: "`my-blueprint` is a
  blueprint, not a module or recipe. Blueprints must be run interactively
  via: `seihou agent run my-blueprint`." Blueprints are not directly
  runnable; that refusal is a hard, never-bypassed invariant.
- The user runs `seihou status` after the agent session and sees a new line:
  "Scaffolded from blueprint: `my-blueprint` v0.3.1 on 2026-05-12 (baseline:
  `nix-flake`, `haskell-base`)." The manifest records the blueprint's
  identity and version so future `seihou outdated` runs can flag a newer
  blueprint version, and so a later `seihou agent run my-blueprint
  --resume` can re-launch the agent with the prior context (the latter is
  out of scope for v1; see Decision Log).
- A blueprint author runs `seihou new-blueprint payments-service` and gets a
  scaffolded `blueprint.dhall` plus an example `prompt.md`. They iterate on
  the prompt and reference files locally, validate with `seihou
  validate-blueprint`, and publish via `seihou install`-friendly git repos
  the same way modules and recipes are shared today.
- Multi-module repositories (those with `seihou-registry.dhall`) can list
  blueprints alongside modules and recipes. `seihou install`, `seihou
  browse`, `seihou registry sync-versions`, and `seihou registry validate`
  all understand the new entry kind. `seihou list` displays blueprints with
  a dedicated label/icon and `seihou list --tag` filters across all three
  kinds.

In scope:

- A new `Blueprint` domain type in `seihou-core`, with a Dhall schema
  published in the `seihou-schema` repository and pinned via the standard
  `mori.dhall` flow.
- Discovery integration: `discoverRunnable` and `discoverAllRunnables`
  recognise `blueprint.dhall` alongside `module.dhall` and `recipe.dhall`.
- Validation: a `validateBlueprint` function with rules for name format,
  required prompt non-empty, base-module references resolving, var/prompt
  consistency, and safe `files/` references.
- A `seihou run` refusal branch that produces an actionable message when
  the discovered runnable is a blueprint.
- New CLI commands: `seihou new-blueprint NAME [--path DIR]`, `seihou
  validate-blueprint [PATH]`, `seihou agent run BLUEPRINT [PROMPT]`. The
  existing `seihou list` and `seihou vars` commands learn to display
  blueprints.
- A `seihou agent run` runner that:
  - resolves blueprint variables through the same precedence chain as
    `seihou run` (CLI → env → local → namespace → context → global → defaults
    → interactive prompts);
  - optionally applies declared base modules into the project (default on;
    `--no-baseline` skips);
  - renders the blueprint's prompt template, embeds it in a system-prompt
    scaffold mirroring the `assist`/`bootstrap`/`setup` patterns, and
    launches Claude Code with the blueprint's `files/` mounted via
    `--add-dir`;
  - records an `AppliedBlueprint` manifest entry so `seihou status` can
    surface scaffolding provenance.
- Manifest schema bump: `Manifest` gains an `AppliedBlueprint` field; a
  one-shot decoder upgrade keeps older manifests readable.
- Multi-module-repository support: `Registry` gains a `blueprints`
  field, `seihou install`, `seihou browse`, and the `seihou registry`
  subcommands all handle blueprints, and `discoverRepoContents` learns a
  `SingleBlueprint` variant.
- Documentation: a new design doc at
  `docs/dev/design/proposed/blueprints.md`, an updated architecture
  overview, updated agent-prompt files (`assist-prompt.md`,
  `bootstrap-prompt.md`, `setup-prompt.md`) so neighbouring agents
  understand blueprints, and a CHANGELOG entry per child plan.

Out of scope (deferred):

- **Resuming a prior blueprint session.** A future plan can persist
  conversation transcripts under `.seihou/blueprints/<name>/sessions/` and
  add `seihou agent run --resume <session-id>`. The v1 manifest entry
  records *that* a blueprint was applied (with version and timestamp), but
  not the conversation contents. Mentioned in the Decision Log so a future
  contributor knows the manifest schema was designed with this extension
  in mind.
- **Blueprints that depend on other blueprints.** A blueprint's
  `baseModules` list is restricted to *modules* (and, by extension,
  recipes — recipes expand to modules at composition time). A blueprint
  cannot list another blueprint as a base, because doing so would require
  recursively launching agent sessions, which is a meaningfully different
  feature with its own UX and safety considerations.
- **Migrations declared on a blueprint.** Modules use `migrations` to
  rewrite tracked files when the module's version advances. Blueprints
  produce non-deterministic output (the agent decides what gets written),
  so the manifest's `files` map cannot be authoritatively rewritten by a
  blueprint-author-supplied chain. Updating a project that was scaffolded
  from `my-blueprint v0.1.0` to use `my-blueprint v0.2.0` is the agent's
  job, run interactively. This is recorded in the Decision Log as a
  deliberate non-goal.
- **A non-Claude agent backend.** The runner uses the existing
  `launchAgentWith` helper, which shells out to the `claude` CLI. A
  pluggable agent backend (LangGraph, Aider, Cline, etc.) is a future
  initiative; this masterplan does not generalise the launcher.
- **Templates inside the prompt that pull from base modules' resolved
  values.** Blueprint prompts may reference top-level `vars`, but cannot
  pull values resolved by a base module's prompt chain. If a blueprint
  needs `project.name`, the blueprint must declare its own
  `project.name` `VarDecl` (which then becomes the override that any base
  module's `project.name` resolves to). Recorded in the Decision Log.


## Decomposition Strategy

The work decomposes naturally along the lifecycle of a new runnable type
in this codebase: define the type, make tools recognise it, expose
authoring and inspection, then build the consumer-facing runner. The
underlying ordering principle is "each child plan produces a behaviour a
contributor can validate end-to-end without the later plans being merged."

The principles applied:

- **Type before tooling.** EP-1 owns the `Blueprint` type, the Dhall
  schema, the decoder, the discovery extension, and the `seihou run`
  refusal branch. Every later plan consumes one or more of these without
  defining its own; if EP-1 is not in place, no later plan compiles.
- **Static surface before dynamic.** EP-2 (authoring + inspection)
  depends only on EP-1's type — it does not need the runner to land. A
  blueprint author can scaffold, edit, validate, and inspect a blueprint
  with EP-2 alone, even though running the blueprint requires EP-3.
  This shape makes EP-2 the natural place to land the schema-bump
  fixture and validation tests.
- **Runner is a single coherent unit.** EP-3 owns the agent runner
  end-to-end: variable resolution, optional baseline application, prompt
  rendering, and Claude launch. Splitting "resolve" from "launch" would
  introduce a stub that does not exercise the integration path; a single
  plan ensures the first time the runner runs, it produces a real Claude
  session. Manifest writing — the persistent side effect — is the only
  piece deliberately deferred to EP-4 because it touches a separate,
  well-isolated subsystem.
- **Manifest tracking is its own plan.** EP-4 bumps the manifest schema
  version, adds the `AppliedBlueprint` field, wires writing into EP-3's
  runner, and surfaces the entry in `seihou status`. Manifest-schema
  migrations are notoriously easy to break in subtle ways; isolating the
  change in its own plan with its own test fixtures keeps the diff
  reviewable.
- **Registry is a parallel ecosystem concern.** EP-5 extends the
  multi-module-repository surface (`seihou-registry.dhall`, `seihou
  install`, `seihou browse`, `seihou registry sync-versions / validate`).
  None of these are required for a blueprint to *work* — a blueprint in
  a single-module git repo is fully functional after EP-3 — but the
  ecosystem is incomplete without registry support. EP-5 is independent
  enough that an agent can work it in parallel with EP-3 and EP-4 once
  EP-1 lands, with light integration testing at the end.
- **Documentation closes the loop.** EP-6 is the customary final plan:
  the design doc, the architecture-overview update, the agent-prompt
  edits that make the existing `assist`/`bootstrap`/`setup` agents aware
  of blueprints, and the user-facing CHANGELOG entry.

Alternatives considered:

- **Fold EP-3 (runner) and EP-4 (manifest) into one plan.** Rejected:
  the manifest schema bump is the riskiest persistent-state change in
  the initiative. Keeping it separate gives reviewers a single,
  well-bounded diff to scrutinise — the same rationale used in
  masterplan 1 (`docs/masterplans/1-migrations-dx.md`) for keeping
  migration-engine work separate from migration-CLI work.
- **Move EP-2 (authoring) ahead of EP-1 by defining the schema first
  in the seihou-schema repo.** Rejected: the seihou-schema bump is part
  of EP-1's milestones precisely because the Haskell decoder, the
  validator, and the schema must land in lockstep. Doing the schema in
  isolation means writing decoder tests against fixtures that don't yet
  type-check.
- **Replace `seihou agent run` with a top-level `seihou blueprint run`
  command.** Rejected: the `seihou agent` namespace already groups
  AI-assisted commands (`assist`, `bootstrap`, `setup`), and blueprints
  *are* agent-assisted by definition. Co-locating the runner there
  follows the existing UX. EP-3 records this in its Decision Log so a
  later plan that adds a non-agent backend has a clear extension path.
- **Skip EP-5 (registry) and ship single-repo blueprints only.**
  Rejected: blueprints share enough with modules and recipes that
  registry parity is a small mechanical effort, and skipping it would
  produce two install workflows for users (one for module/recipe-only
  repos, another for blueprint-only repos). The cost of doing it
  upfront is much lower than the cost of explaining the gap.
- **Skip EP-6 (documentation) and rely on inline comments.**
  Rejected for the same reason every other masterplan in this
  repository keeps a doc plan: agents and contributors discover
  features through `docs/dev/design/proposed/` and the architecture
  overview. A feature with no doc page is a feature whose design
  decisions are not durable.


## Exec-Plan Registry

| #   | Title                                                                       | Path                                                              | Hard Deps  | Soft Deps  | Status      |
|-----|-----------------------------------------------------------------------------|-------------------------------------------------------------------|------------|------------|-------------|
| 29  | Define the Blueprint domain model, schema, discovery, and run-time refusal  | docs/plans/29-blueprint-domain-model-and-discovery.md             | None       | None       | Complete    |
| 30  | Authoring and inspection commands for blueprints                            | docs/plans/30-blueprint-authoring-and-inspection.md               | EP-29      | None       | Complete    |
| 31  | Agent runner for blueprints (`seihou agent run BLUEPRINT`)                  | docs/plans/31-blueprint-agent-runner.md                           | EP-29      | EP-30      | Complete    |
| 32  | Manifest tracking and `seihou status` integration for applied blueprints    | docs/plans/32-blueprint-manifest-and-status.md                    | EP-31      | None       | Complete    |
| 33  | Registry and multi-module-repository support for blueprints                 | docs/plans/33-blueprint-registry-and-install.md                   | EP-29      | EP-30      | In Progress |
| 34  | Documentation, agent-prompt updates, and ecosystem polish                   | docs/plans/34-blueprint-docs-and-ecosystem.md                     | EP-31      | EP-30, EP-32, EP-33 | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled. Hard Deps and Soft
Deps reference other rows by their `EP-N` prefix.


## Dependency Graph

EP-29 (foundation) is the root of the graph. It defines the `Blueprint`
Haskell type, the `RunnableBlueprint` constructor on the existing
`Runnable` ADT (in `seihou-core/src/Seihou/Core/Types.hs`), the
`Blueprint.dhall` schema (committed in this repo's `schema/` directory and
mirrored into `seihou-schema`), the decoder and validator
(`Seihou.Dhall.Eval.evalBlueprintFromFile`, `Seihou.Core.Blueprint.validateBlueprint`),
the discovery extension (`Seihou.Core.Module.discoverRunnable` learns a
new branch), and the `seihou run` refusal (in
`seihou-cli/src-exe/Seihou/CLI/Run.hs`'s recipe-detection block, which
already discriminates on `Runnable`). Without these, the type does not
exist and no later plan can compile against it.

EP-30 (authoring + inspection) hard-depends on EP-29 because every
command it adds reads or writes a `Blueprint` value: `seihou
new-blueprint` writes one to disk, `seihou validate-blueprint` reads and
validates one, and the existing `seihou list` and `seihou vars` flows
need to handle the new `RunnableBlueprint` constructor. EP-30 has no soft
dependencies.

EP-31 (agent runner) hard-depends on EP-29 for the `Blueprint` type and
the discovery extension, and has a soft dependency on EP-30 because
EP-30 lands the `seihou validate-blueprint` command that an EP-31
contributor uses to vet the test fixtures used by the runner's
integration tests. EP-31 also reuses pure helpers in
`seihou-cli/src/Seihou/CLI/AgentLaunch.hs` (formatters,
`gatherAgentContext`, `substitute`) and the `launchAgentWith` shell-out
in `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs`; both are in place
today.

EP-32 (manifest tracking) hard-depends on EP-31 because the manifest
write is wired into the runner. The plan extends
`Seihou.Core.Types.Manifest` with an `AppliedBlueprint` field, bumps
the manifest schema version (currently `currentManifestVersion` in
`seihou-core/src/Seihou/Manifest/Types.hs`), updates the JSON
serialization, hooks `seihou status` to display the entry, and adds a
single-shot upgrade path for older manifests. The plan is intentionally
small and surgical.

EP-33 (registry) hard-depends on EP-29 (it needs the `Blueprint` type to
classify discovered repo contents) and has a soft dependency on EP-30
(the `seihou registry validate` extension benefits from EP-30's
validation rules). EP-33 does *not* depend on EP-31 or EP-32 — a
blueprint can be installed via a registry before it can be run, just as a
module can be installed before it can be applied.

EP-34 (documentation) hard-depends on EP-31 because the design doc and
architecture overview describe the runner's behaviour; soft-depends on
EP-30, EP-32, EP-33 so the doc covers the full surface. EP-34 also lands
the agent-prompt edits to `seihou-cli/data/assist-prompt.md`,
`bootstrap-prompt.md`, and `setup-prompt.md` so the existing AI-assisted
commands learn that blueprints exist.

Critical path: EP-29 → EP-31 → EP-32 → EP-34. EP-30 and EP-33 can land in
parallel with EP-31 once EP-29 ships. EP-34 must wait until at least
EP-31 is merged so the doc describes shipped behaviour, not aspirational
behaviour.

Parallelism opportunities:

- After EP-29 lands, EP-30 and EP-31 can be worked simultaneously by
  different contributors. EP-30's surface (authoring) and EP-31's surface
  (running) touch disjoint CLI handlers; the only shared file is
  `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, which is a small and
  well-understood merge.
- EP-33 (registry) can also be worked in parallel with EP-30 and EP-31
  once EP-29 lands. The registry handlers live under
  `seihou-cli/src-exe/Seihou/CLI/Install.hs`, `Browse.hs`, and
  `seihou-cli/src/Seihou/CLI/Registry/`; these are disjoint from EP-30's
  and EP-31's surfaces.
- EP-32 cannot start until EP-31 lands because it must hook into the
  runner to write its entry.
- EP-34 must come last. It documents the ecosystem as a whole.


## Integration Points

This section enumerates every shared artifact that two or more child
plans touch. Each child plan must consult this list before defining its
own contracts.

**1. The `Blueprint` Haskell type and the `RunnableBlueprint` constructor.**

- Involved plans: EP-29 (definer), EP-30, EP-31, EP-32, EP-33 (consumers).
- Artifact: A record type `Blueprint` defined in
  `seihou-core/src/Seihou/Core/Types.hs` adjacent to `Module` and
  `Recipe`. The exact field set is EP-29's responsibility but at minimum
  contains:
  - `name :: ModuleName` (re-uses the `[a-z][a-z0-9-]*` namespace shared
    with modules and recipes, so a single search path can resolve all
    three by a single name and they cannot collide; the duplicate
    naming is checked at validation time and at registry time)
  - `version :: Maybe Text`
  - `description :: Maybe Text`
  - `prompt :: Text` — the rendered Markdown body the agent receives
  - `vars :: [VarDecl]` — variables the runner resolves before launch
  - `prompts :: [Prompt]` — interactive prompts at run time (same shape
    as `Module.prompts`)
  - `baseModules :: [Dependency]` — modules to apply as a baseline
    before launching the agent (re-uses `Dependency` for the parent-vars
    binding shape)
  - `files :: [BlueprintFile]` — references to files in the
    `files/` subdirectory the runner exposes via `--add-dir` (typed so
    validation can verify each file exists at validation time)
  - `allowedTools :: Maybe [Text]` — optional override of Claude
    Code's `--allowedTools`; default is a documented blueprint-runner
    toolset
  - `tags :: [Text]` — for `seihou list --tag` and registry filtering
- Owning plan: EP-29. EP-30, EP-31, EP-32, and EP-33 must use this
  representation verbatim; if any of them needs to extend it, EP-29
  must be revised first and the change cascaded.

**2. The `Runnable` ADT extension.**

- Involved plans: EP-29 (definer), EP-30, EP-31, EP-33 (consumers).
- Artifact: The `Runnable` ADT in
  `seihou-core/src/Seihou/Core/Types.hs` currently has constructors
  `RunnableModule Module FilePath` and `RunnableRecipe Recipe FilePath`.
  EP-29 adds `RunnableBlueprint Blueprint FilePath`. The
  `RunnableKind` enum gains `KindBlueprint` for the
  `discoverAllRunnables` enumeration path.
- Owning plan: EP-29. Every consumer must handle the new constructor
  exhaustively; EP-29's milestones include making any non-exhaustive
  `case` over `Runnable` either fail to compile (preferred — the
  `-Wincomplete-patterns` flag in this codebase will surface the issue)
  or be updated explicitly.
- Note for EP-30 and EP-33: the `seihou list` formatter
  (`seihou-cli/src/Seihou/CLI/List.hs`) and the registry classifier
  (`seihou-core/src/Seihou/Core/Registry.hs`) both case-split on
  `RunnableKind`. EP-30 owns the list-formatter update; EP-33 owns the
  registry-classifier update.

**3. The Dhall schema for `Blueprint.dhall` and the seihou-schema bump.**

- Involved plans: EP-29 (definer + schema bump), EP-30 (consumer for
  `new-blueprint` boilerplate), EP-31 (consumer for the runner's loader),
  EP-33 (consumer for registry-entry sync-versions), EP-34 (consumer for
  doc snippets).
- Artifact: A Dhall record type in `schema/Blueprint.dhall` and an
  export in `schema/package.dhall`. The same files must land in the
  `seihou-schema` repository at
  `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/`, and
  `seihou-cli/src/Seihou/CLI/SchemaVersion.hs` is updated to the new
  commit hash and integrity hash. **Note: `mori.dhall` is NOT the
  seihou-schema pin** — `mori.dhall` pins `mori-schema`, a separate
  schema. The seihou-schema URL/hash live solely in
  `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`. EP-29's milestones
  include the `seihou-schema` PR and the SchemaVersion.hs bump.
- Owning plan: EP-29. Other plans must not edit the Dhall schema; if
  a field is needed, the request is folded back into EP-29 (revising
  the masterplan if necessary).

**4. The `seihou run` refusal branch.**

- Involved plans: EP-29 (definer), EP-31 (consumer of the same
  discovery code path), EP-34 (documenter — the user-facing CLI help
  and design doc must quote this exact text).
- Artifact: In
  `seihou-cli/src-exe/Seihou/CLI/Run.hs`, the existing block at the top
  of `handleRun` that calls `discoverRunnable` and pattern-matches on
  the result currently has two branches: `RunnableRecipe` (expand) and
  `RunnableModule` (proceed). EP-29 adds a third: `RunnableBlueprint`
  must `exitFailure` after printing the actionable message below.
  EP-31's agent runner uses the same `discoverRunnable` to load the
  blueprint; the two consumers must agree on the discovery shape.
- **Canonical refusal text (verbatim — every consumer doc must
  match):**

      Error: 'NAME' is a blueprint, not a module or recipe.
      Blueprints must be run interactively via:
        seihou agent run NAME

  where `NAME` is the blueprint's name. Implementation note: a single
  multi-line `logError` call is required because
  `Seihou.Effect.Logger.logError` prepends `Error:` to every line —
  three separate `logError` calls would produce three `Error:`
  prefixes.
- Owning plan: EP-29. EP-31 must reuse `discoverRunnable` rather than
  rolling its own loader. EP-34 must quote this text verbatim in the
  design doc and any user-facing help.

**5. The `Manifest` schema and `AppliedBlueprint` entry.**

- Involved plans: EP-32 (definer), EP-31 (writer), and any future
  status-rendering plan (consumer).
- Artifact: An `AppliedBlueprint` record (mirroring the
  existing `AppliedRecipe` shape) added to `Manifest.recipe`'s
  neighbour position — see `seihou-core/src/Seihou/Core/Types.hs`
  lines 363-380 for the existing pattern. The `Manifest` record gains a
  `blueprint :: Maybe AppliedBlueprint` field. The manifest schema
  version constant in
  `seihou-core/src/Seihou/Manifest/Types.hs` (`currentManifestVersion`)
  is bumped, and the JSON decoder gains a backwards-compatibility branch
  that decodes pre-bump manifests with `blueprint = Nothing`.
- Owning plan: EP-32. EP-31 must call into a writer helper exposed by
  EP-32 rather than synthesising the entry inline; the masterplan
  records this as a small contract between the two plans.

**6. The shared `seihou agent run` CLI surface.**

- Involved plans: EP-31 (definer), EP-34 (documentation consumer).
- Artifact: A new `AgentRun BlueprintRunOpts` constructor on the
  existing `AgentCommand` ADT in
  `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, with a parser that
  follows the shape of the existing `assist`, `bootstrap`, `setup`
  parsers (positional `BLUEPRINT` argument, optional positional `PROMPT`
  argument, repeated `--var KEY=VALUE`, `--no-baseline`, `--debug`,
  `--verbose`). The handler lives in
  `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` (new file). EP-34's
  documentation plan describes this surface in user-facing terms.
- Owning plan: EP-31. EP-34 must reflect EP-31's shipped surface, not
  an aspirational one.

**7. The `Registry` data type's new `blueprints` field.**

- Involved plans: EP-33 (definer), EP-34 (documentation consumer),
  and a future-noted "discoverRepoContents" consumer (already in EP-33).
- Artifact: The `Registry` record in
  `seihou-core/src/Seihou/Core/Registry.hs` gains
  `blueprints :: [RegistryEntry]`. The Dhall registry schema (the
  `seihou-registry.dhall` shape that `evalRegistryFromFile` decodes)
  gains a parallel `blueprints` list. The `seihou registry sync-versions`
  and `seihou registry validate` commands gain blueprint-aware branches.
  `discoverRepoContents` gains a `SingleBlueprint FilePath` constructor
  that is returned when a cloned repo's root contains `blueprint.dhall`
  but no `module.dhall`/`recipe.dhall`/`seihou-registry.dhall`.
- Owning plan: EP-33.

**8. Agent-prompt files: `assist-prompt.md`, `bootstrap-prompt.md`,
`setup-prompt.md`.**

- Involved plans: EP-34 (definer), with a soft consumer relationship
  to EP-30 (whose `seihou validate-blueprint` is referenced) and EP-31
  (whose `seihou agent run` is referenced).
- Artifact: The three prompt files at
  `seihou-cli/data/{assist,bootstrap,setup}-prompt.md` are extended to
  describe blueprints — the existing prompts list available
  `seihou` commands and discuss authoring/consumption flows; each
  needs a brief blueprint-aware section so an agent reasoning over a
  user request can choose between scaffolding a module, a recipe, or a
  blueprint, and can correctly direct the user to `seihou agent run`
  rather than `seihou run` for blueprints.
- Owning plan: EP-34.

**9. Documentation: design doc, architecture overview, CHANGELOG.**

- Involved plans: EP-34 (definer); every other plan adds its own
  CHANGELOG entry as part of its milestones.
- Artifact: A new file at
  `docs/dev/design/proposed/blueprints.md` (rei-style format matching
  the other proposed-design docs). Updates to
  `docs/dev/architecture/overview.md` adding "Blueprint" to the
  runnable-types narrative and updating the project-structure tree
  with the new `Blueprint.hs` files. A `docs/user/CHANGELOG.md` entry
  per child plan describing what landed.
- Owning plan: EP-34 owns the design doc and the architecture-overview
  edits. Each child plan owns its own CHANGELOG entry.


## Progress

Track milestone-level progress across all child plans. Each entry names
the child plan and the milestone. This section provides an at-a-glance
view of the entire initiative.

- [x] EP-29: Add the `Blueprint` data type, the `BlueprintFile` helper, the `RunnableBlueprint` constructor on the `Runnable` ADT, and the `KindBlueprint` constructor on `RunnableKind`.
- [x] EP-29: Add `schema/Blueprint.dhall`, update `schema/package.dhall`, and add `evalBlueprintFromFile` plus `blueprintDecoder` in `Seihou.Dhall.Eval`.
- [x] EP-29: Add `Seihou.Core.Blueprint.validateBlueprint` with the documented validation rules; add `discoverBlueprint` and extend `discoverRunnable` and `discoverAllRunnables` to recognise `blueprint.dhall`.
- [x] EP-29: Mirror the schema into the `seihou-schema` repository, publish a release commit, and bump the schema URL/hash in `mori.dhall` and `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`. *(`mori.dhall` left untouched — it pins `mori-schema`, not `seihou-schema`.)*
- [x] EP-29: Add the `seihou run` refusal branch in `seihou-cli/src-exe/Seihou/CLI/Run.hs` for `RunnableBlueprint`; verify via integration test that `seihou run my-blueprint` fails with the documented message. *(Refusal arm in place; integration test arrives with EP-29 M7.)*
- [x] EP-30: Add `seihou new-blueprint NAME [--path DIR]` CLI handler scaffolding `blueprint.dhall`, `prompt.md`, and `files/`.
- [x] EP-30: Add `seihou validate-blueprint [PATH]` CLI handler exercising the EP-29 validator.
- [x] EP-30: Update `seihou list` and `seihou vars` to display blueprints with the new `RunnableKind`. *(List arm landed with EP-29's exhaustiveness fix-ups; EP-30 added the Vars dispatch and the blueprint declaration-mode formatter.)*
- [x] EP-31: Add the `AgentRun BlueprintRunOpts` constructor to `Seihou.CLI.Commands.AgentCommand` and the matching parser.
- [x] EP-31: Implement `Seihou.CLI.AgentRun.handleAgentRun`: discover the blueprint, validate, resolve variables (with prompts), render the prompt template, and invoke `launchAgentWith` with the right `--add-dir` and `--allowedTools`.
- [x] EP-31: Implement optional baseline application — programmatically apply each declared base module before launching the agent; respect `--no-baseline`.
- [x] EP-31: Add the embedded blueprint-agent system-prompt scaffold at `seihou-cli/data/blueprint-prompt.md` (mirrors `assist-prompt.md` shape) and embed via `Data.FileEmbed`.
- [x] EP-32: Add `AppliedBlueprint` to `Seihou.Core.Types`, extend `Manifest`, bump `currentManifestVersion`, and update the JSON encoder/decoder with backwards-compatible decoding for older manifests.
- [x] EP-32: Wire EP-31's runner to write the `AppliedBlueprint` entry on successful agent launch.
- [x] EP-32: Update `seihou status` to display the applied-blueprint line; verify via integration test.
- [x] EP-33: Extend `Registry` with `blueprints :: [RegistryEntry]`; update the Dhall registry schema and `evalRegistryFromFile`/`registryDecoder`.
- [ ] EP-33: Update `discoverRepoContents` with a `SingleBlueprint FilePath` constructor; update `seihou install` to handle the new constructor and registry-listed blueprints; update `seihou browse`.
- [ ] EP-33: Update `seihou registry sync-versions` and `seihou registry validate` to walk the new `blueprints` list.
- [ ] EP-34: Write `docs/dev/design/proposed/blueprints.md` describing the design, motivation, validation rules, runner flow, manifest behaviour, and registry integration.
- [ ] EP-34: Update `docs/dev/architecture/overview.md` with the third runnable type and the updated project-structure tree.
- [ ] EP-34: Update `seihou-cli/data/assist-prompt.md`, `bootstrap-prompt.md`, and `setup-prompt.md` so neighbouring agents understand blueprints; add a CHANGELOG entry summarising the whole initiative.


## Surprises & Discoveries

- 2026-05-07 (EP-29) — `Seihou.Effect.Logger.logError` prefixes each
  call with `[error] `, not `Error:` as the masterplan's "canonical
  refusal text" suggested. The body lines are unchanged; only the
  prefix differs. EP-34's documentation plan must reflect the
  literal observable output (e.g., `[error] 'NAME' is a blueprint, …`),
  not the placeholder `Error:` form. The single multi-line `logError`
  shape was retained so the prefix appears once.

- 2026-05-07 (EP-29) — Initial implementation passed the blueprint's
  declared `name` field into `formatBlueprintRefusal`. An end-to-end
  demo with directory `demo-blueprint/blueprint.dhall` whose
  `name = "sample-blueprint"` produced a misleading suggestion
  `seihou agent run sample-blueprint`. Discovery resolves by
  *directory name*, not by the declared `name`, so the suggestion
  must echo the user-typed name. Fixed by passing `modName` (the CLI
  positional argument) rather than `b.name`. **Cross-plan invariant:**
  EP-31's runner accepts the same positional `BLUEPRINT` argument
  and should preserve it through error messages; EP-34's doc must
  describe the suggestion as "the same name you typed".

- 2026-05-07 (EP-29) — `DuplicateRecordFields` plus
  `OverloadedRecordDot` reads cleanly but produces ambiguous
  *record-update* sites once `Blueprint` enters the type system —
  fields like `version`, `vars`, `prompts`, and `files` collide with
  `Module`/`Recipe`/`Manifest`. GHC warns that the type-directed
  disambiguation is being deprecated. EP-29 followed the codebase's
  existing convention (positional `withModuleName`-style helpers) in
  `BlueprintSpec`. EP-30, EP-31, and EP-32 should all use the
  positional pattern from the start; do not introduce new
  record-update sites on `Blueprint` values.

- 2026-05-07 (EP-29) — The `validateBlueprint :: FilePath -> Blueprint
  -> IO …` signature documented in the masterplan calls
  `defaultSearchPaths` internally, which is unworkable for tests that
  need to pin lookup roots. EP-29 added a sibling
  `validateBlueprintWith :: [FilePath] -> FilePath -> Blueprint -> IO …`
  for testability; production callers continue to use the original.
  EP-31 (which calls the validator before launching the agent) and
  EP-30 (which calls it from `seihou validate-blueprint`) should both
  use the original `validateBlueprint`. The `…With` form is internal
  to the test suite.

- 2026-05-07 (EP-30) — Integration Point #1 of this masterplan named
  three EP-29 adapters that EP-29 *did not* ship:
  `buildBlueprintReport :: Bool -> FilePath -> Blueprint -> IO
  ValidateReport`, `blueprintAsModule :: Blueprint -> Module`, and
  `emptyBlueprint :: Text -> Blueprint`. EP-29 ships the individual
  `checkBlueprint*` rule predicates and the top-level
  `validateBlueprint :: FilePath -> Blueprint -> IO (Either
  ModuleLoadError Blueprint)` aggregator only. EP-30 recovered by
  building its validation report locally in
  `seihou-cli/src-exe/Seihou/CLI/ValidateBlueprint.hs`
  (a `BlueprintReport` record + parallel renderer reusing
  `DiagCheck`/`DiagSeverity` from `Seihou.Engine.Validate`). EP-31
  and EP-34 should not look for those adapters. EP-31's runner that
  wants to validate-then-launch can either call `validateBlueprint`
  directly (`Either ModuleLoadError Blueprint`) and format errors
  itself, or re-export `BlueprintReport` from EP-30's module.

- 2026-05-07 (EP-30) — `seihou-cli`'s test suite cannot import any
  module from the `executable seihou` target because Cabal's test
  suites in the same package are limited to `lib:` modules.
  `Seihou.CLI.Commands`, `Seihou.CLI.NewBlueprint`, and
  `Seihou.CLI.ValidateBlueprint` all live under
  `executable seihou`'s `other-modules` (transitively trapped by
  `Options.Applicative`). EP-30 originally planned handler-level
  unit specs (`NewBlueprintSpec`, `ValidateBlueprintSpec`) that
  would not compile. The recovery — pure-helper coverage in
  `seihou-core/test/Seihou/Core/ScaffoldSpec.hs` for
  `blueprintDhall`/`examplePromptMarkdown` (six cases driving the
  full scaffold → eval → validate pipeline) plus a list-formatter
  case in `seihou-cli/test/Seihou/CLI/ListSpec.hs` — is the same
  pattern existing siblings `NewModule.hs`/`Validate.hs` use (no
  direct handler unit tests, smoke-tested manually). EP-31 and
  EP-32 will hit the same constraint. They should plan around it
  from the start: shared helpers go in `seihou-cli-internal` (the
  library) so they are testable; handlers in `src-exe` are
  smoke-tested.

- 2026-05-08 (EP-31) — `OverloadedRecordDot` against
  `ModuleInstance.instanceModule` and `instanceParentVars` requires
  importing the *constructor* (`ModuleInstance (..)`), not just the
  type alias. Type-only imports compile but every `inst.instanceModule`
  use site fails with "No instance for HasField …". `Seihou.CLI.Run`
  imports `(..)` already; EP-31 hit the error briefly and fixed it.
  EP-32 (manifest writer that consumes the runner's output) and
  EP-33 (registry classifier that case-splits on `RunnableKind` and
  may also touch `ModuleInstance`) should both import
  `ModuleInstance (..)` from `Seihou.Composition.Instance` from the
  start.

- 2026-05-08 (EP-31) — Cabal's `seihou-cli-test` test suite cannot
  import `Seihou.CLI.AgentRun`, `Seihou.CLI.Commands.BlueprintRunOpts`,
  or `Seihou.CLI.AgentLaunchExec.launchAgentWith`: each lives in the
  `executable seihou` target (trapped by `Options.Applicative` /
  `Data.FileEmbed` / `Paths_seihou_cli`), and tests can only import
  from the `seihou-cli-internal` library. EP-30 hit the same wall and
  recovered by covering pure helpers in the library and smoke-testing
  the handler manually; EP-31 followed the same pattern (10 new
  formatter unit tests + manual smoke tests). **Cross-plan signal for
  EP-32:** when wiring the manifest writer into the runner, design
  the writer to live in `seihou-cli-internal` (or in `seihou-core`)
  and consume `BlueprintRunOutcome` from the library side — the call
  site in `Seihou.CLI.AgentRun` is a one-liner, and the test suite
  covers the writer directly. Do not put the writer next to
  `handleAgentRun` in `src-exe/`.

- 2026-05-08 (EP-31) — `BlueprintFile` exposes its filesystem path as
  `src :: FilePath`, not `path :: FilePath` as Integration Point #1
  of this masterplan implies. The runner uses `bf.src` to render the
  reference-files block. EP-33's registry classifier and EP-34's doc
  snippets must also use `src`. Integration Point #1 is left
  unchanged because EP-29 is the owner of the type and the field name
  there is correct; this note records the discrepancy with the
  masterplan's prose.

- 2026-05-08 (EP-32) — `Seihou.CLI.AgentLaunchExec.launchAgentWith`
  used to call `exitWith exitCode` itself, which made it impossible
  to do post-launch bookkeeping (the manifest write that EP-32
  needed). EP-32 refactored it to return `IO ExitCode`; the four
  callers (Assist, Bootstrap, Setup, AgentRun) propagate the code
  themselves. The non-runner callers gained a one-liner `exitWith`.
  **Cross-plan signal for EP-34:** the design doc's runner-flow
  diagram should describe `launchAgentWith` as returning the exit
  code, not as terminating the process directly. The agent-prompt
  edits (`assist`/`bootstrap`/`setup`-prompt.md) describe user-facing
  behaviour and need no change.

- 2026-05-08 (EP-32) — EP-31 exported a placeholder
  `BlueprintRunOutcome` record from `Seihou.CLI.AgentRun` reserved
  for EP-32. EP-32 did not need it — the helper
  `appliedBlueprintFromOutcome` consumes the runner's local state
  directly and `recordAppliedBlueprint` consumes an
  `AppliedBlueprint` (the persistent form). The unused export was
  removed. **Cross-plan signal for EP-34:** the documentation must
  not describe `BlueprintRunOutcome` — it does not exist in the
  shipped surface.

- 2026-05-08 (EP-32) — The IO writer for `AppliedBlueprint` lives in
  `seihou-cli/src/Seihou/CLI/AppliedBlueprint.hs` (the
  `seihou-cli-internal` library), exposing
  `recordAppliedBlueprint :: FilePath -> AppliedBlueprint -> IO
  (Either Text ())`. The location is forced by the same Cabal
  trapping constraint EP-30 and EP-31 documented (`seihou-cli-test`
  cannot import from `executable seihou`). EP-33's registry work
  does not touch the manifest writer; EP-34's doc page should
  reference the helper by full module path so future contributors
  can find it.

- 2026-05-07 (EP-30) — `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`
  exports `schemaImportLine` (a precomputed `let S = … sha256:…`
  string), used by EP-30's `blueprintDhall` indirectly via the
  `schemaUrl` and `schemaHash` fields. The masterplan's Integration
  Point #3 says "the seihou-schema URL/hash live solely in
  `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`" and that note
  remains accurate. No changes to `SchemaVersion.hs` were needed in
  EP-30; the existing pin from EP-29 already exposes
  `S.Blueprint::` and the `S.Blueprint.BlueprintFile` nested
  export. *Note for future EPs:* `BlueprintFile` is exported as a
  nested record under `S.Blueprint.BlueprintFile`, **not** as a
  top-level `S.BlueprintFile` (despite the masterplan's wording in
  Integration Point #3 implying otherwise). `blueprintDhall`'s
  generated `[] : List S.Blueprint.BlueprintFile.Type` reflects
  this. EP-31's prompt-rendering machinery and EP-33's registry
  classifier should match.


## Decision Log

- Decision: Name the new runnable type "Blueprint" (file:
  `blueprint.dhall`, type: `Blueprint`, constructor:
  `RunnableBlueprint`, CLI: `seihou new-blueprint`, `seihou
  validate-blueprint`, `seihou agent run BLUEPRINT`).
  Rationale: The user picked Blueprint from a four-way preview
  comparison (Blueprint vs Brief vs AgentModule vs Sketch) at
  masterplan creation time. Blueprint connotes "a base plan an agent
  customises" without overloading existing terminology in the
  codebase ("module", "recipe", "scaffold", "template" are all
  taken). The metaphor scales: a building blueprint specifies enough
  for construction to begin but leaves details to the builder, which
  matches the agent-driven workflow.
  Date: 2026-05-07.

- Decision: Blueprint names share the `[a-z][a-z0-9-]*` namespace with
  modules and recipes; a `discoverRunnable` lookup resolves all three
  kinds against the same search paths.
  Rationale: The existing `discoverRunnable` already handles two kinds
  with the same name format. Adding a third kind in the same namespace
  keeps the user-facing UX simple ("`my-thing` resolves to one
  artifact, regardless of kind"). Cross-kind name collisions are
  validated at registry-validation time and surfaced as a clear error,
  mirroring how module/recipe collisions are handled today
  (`Seihou.Core.Registry.checkNameCollisions`).
  Date: 2026-05-07.

- Decision: Place the agent runner under `seihou agent run` rather
  than introducing a top-level `seihou blueprint` command.
  Rationale: The `seihou agent` namespace already groups AI-assisted
  commands (`assist`, `bootstrap`, `setup`); blueprints are
  agent-assisted by definition. The naming preserves the verb
  hierarchy (`agent` is the noun-namespace, `run` is the verb) and
  keeps a single Claude-Code launch path through `launchAgentWith`. A
  future plan that introduces a non-Claude backend can extend the
  `agent` namespace rather than fragmenting the CLI.
  Date: 2026-05-07.

- Decision: Defer "blueprint resume" (re-launching an agent session
  with the prior conversation transcript) to a future plan.
  Rationale: Resuming requires persisting conversation transcripts,
  managing session identifiers, and (likely) an explicit "checkpoint"
  command to capture work in progress. The v1 manifest entry records
  *that* a blueprint was applied but not the conversation contents;
  the schema is designed to be extended (an optional `sessionId`
  field is the obvious extension point). EP-32 should design the
  manifest entry with this extension in mind.
  Date: 2026-05-07.

- Decision: Blueprints cannot list other blueprints as base modules.
  Rationale: A blueprint listing another blueprint as a base would
  require recursively launching agent sessions, which is a
  meaningfully different feature with its own UX (when does the
  parent agent take over from the child?), safety concerns, and
  integration testing burden. EP-29's validator rejects this case
  with a clear message.
  Date: 2026-05-07.

- Decision: Blueprints do not declare `migrations`.
  Rationale: Modules use `migrations` to rewrite tracked files when
  the module's version advances — this is sound because the
  manifest's `files` map is authoritative for what the module
  produced. Blueprints produce non-deterministic output (the agent
  decides what gets written), so the manifest's `files` map cannot
  be authoritatively rewritten by a blueprint-author-supplied
  chain. Updating a project that was scaffolded from `my-blueprint
  v0.1.0` to use `my-blueprint v0.2.0` is the agent's job, run
  interactively. Recorded as a deliberate non-goal so a future
  contributor does not try to add it.
  Date: 2026-05-07.

- Decision: Within a single directory, when more than one of
  `module.dhall` / `recipe.dhall` / `blueprint.dhall` is present,
  discovery resolves in the priority order **module > recipe >
  blueprint**.
  Rationale: This matches the existing recipe-after-module fall-through
  in `discoverRunnable` (`seihou-core/src/Seihou/Core/Module.hs` lines
  60-84). Blueprint slots in last because (a) author error of the form
  "I left a stray module.dhall next to my blueprint.dhall" should
  silently surface the module — the more specific, deterministic
  artifact — rather than the looser blueprint, and (b) the registry
  validator (EP-33) will additionally flag duplicate-marker directories
  at install time. EP-29's M4 owns the test that locks this priority;
  EP-33's `discoverRepoContents` extends the same precedence as
  registry > module > recipe > blueprint.
  Date: 2026-05-07.

- Decision: EP-29's M1 (the ADT extension adding `RunnableBlueprint`
  and `KindBlueprint`) cannot land as an isolated commit. The
  codebase compiles with `-Wincomplete-patterns`; the moment the
  constructor is added, every existing `case` over `Runnable` and
  `RunnableKind` becomes a compile error. EP-29's deliverable for M1
  therefore spans M1 plus the run-refusal arm and the two formatter
  sites (`seihou-cli/src/Seihou/CLI/List.hs` and
  `seihou-cli/src/Seihou/Fzf/Selector/Module.hs`) in a single commit.
  Rationale: Compile-error-driven exhaustiveness is the project's
  intended safety net; splitting M1 from the consumer fix-ups would
  require either suppressing the warning (which weakens the safety
  net for everyone else) or landing a broken intermediate commit.
  Date: 2026-05-07.

- Decision: Apply the baseline by default; allow `--no-baseline` to
  skip.
  Rationale: A blueprint's `baseModules` are declared by the
  blueprint author specifically because they expect the agent to
  start from that baseline. Applying them by default produces a
  predictable, validated scaffold for the agent and the user to
  iterate on; skipping the baseline is a power-user override for
  cases where the agent should drive every decision from scratch
  (the prompt is a "starting point" rather than a "build on this").
  EP-31's milestones include both paths.
  Date: 2026-05-07.


## Outcomes & Retrospective

(To be filled during and after implementation.)
