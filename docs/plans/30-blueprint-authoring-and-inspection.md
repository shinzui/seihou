---
id: 30
slug: blueprint-authoring-and-inspection
title: "Authoring and Inspection Commands for Blueprints"
kind: exec-plan
created_at: 2026-05-07T00:00:00Z
intention: "intention_01kr2q5p3ye30t4vk9fj4q69t1"
---


# Authoring and Inspection Commands for Blueprints

MasterPlan: docs/masterplans/3-agent-driven-blueprints.md
Intention: intention_01kr2q5p3ye30t4vk9fj4q69t1

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Seihou today recognises two runnable artifacts: *modules* (`module.dhall`,
deterministic file generators) and *recipes* (`recipe.dhall`, named
compositions of modules). The masterplan
`docs/masterplans/3-agent-driven-blueprints.md` introduces a third runnable
type called a **Blueprint** (`blueprint.dhall`) — a non-deterministic,
agent-driven artifact whose body is a Markdown prompt that an AI coding
assistant consumes. EP-29 (`docs/plans/29-blueprint-domain-model-and-discovery.md`,
landing in parallel) lands the Haskell type, the Dhall schema, the
discovery extension, and the `seihou run` refusal branch. EP-30 lands
the *static surface* — authoring, validation, and inspection — that a
human author needs around that type, *before* the agent runner (EP-31)
exists.

After this plan ships, a contributor in a writable git checkout can do
four things they cannot do today.

First, run `seihou new-blueprint payments-service` and get a fresh
`./payments-service/` directory containing a syntactically valid
`blueprint.dhall` pinned to the current `seihou-schema`, an example
`prompt.md` referenced by the blueprint's `prompt` field via `./prompt.md
as Text`, and an empty `files/` subdirectory ready for reference
snippets.

Second, run `seihou validate-blueprint ./payments-service` and see a
structured report identical in shape to `seihou validate-module`'s — Dhall
parses, name matches `[a-z][a-z0-9-]*`, variable names unique, every
`prompts` entry references a declared variable, every entry in the
blueprint's `files` list points at a real file under `files/`, and no
`baseModules` reference is itself a blueprint.

Third, run `seihou list` and see blueprints displayed alongside modules
and recipes, each tagged with a `[blueprint]` suffix so the kind is
unambiguous at a glance.

Fourth, run `seihou vars payments-service` and see the blueprint's
`vars`/`prompts` declarations the same way the command renders a module
today. Passing `--explain` against a blueprint prints a clear, actionable
refusal because resolving a blueprint's variables requires the runner
from EP-31, which does not yet exist.

Out of scope for this plan: actually *running* a blueprint. EP-29 has
already wired `seihou run BLUEPRINT` to print a documented refusal
message; this plan leaves that wiring untouched and deliberately
introduces no runner-shaped command.


## Progress

- [x] M1: Scaffolding command. Added `NewBlueprintOpts` to
      `seihou-cli/src-exe/Seihou/CLI/Commands.hs`,
      `Seihou.CLI.NewBlueprint.handleNewBlueprint` in
      `seihou-cli/src-exe/Seihou/CLI/NewBlueprint.hs`, and the
      `blueprintDhall` + `examplePromptMarkdown` exports in
      `seihou-core/src/Seihou/Core/Scaffold.hs`. Parser wired into
      `commandParser`'s "Authoring:" group; `NewBlueprint`
      constructor on `Command`; dispatch arm in
      `seihou-cli/src-exe/Main.hs`.
- [x] M2: Validation command. Added `ValidateBlueprintOpts` to
      `Commands.hs`, `Seihou.CLI.ValidateBlueprint.handleValidateBlueprint`
      in `seihou-cli/src-exe/Seihou/CLI/ValidateBlueprint.hs`, the
      parser branch, the `ValidateBlueprint` `Command` constructor,
      and the `Main.hs` dispatch arm. Note: EP-29 did *not* ship the
      `buildBlueprintReport` / `blueprintAsModule` / `emptyBlueprint`
      adapters this plan assumed; instead the handler builds a
      blueprint-shaped `BlueprintReport` locally by calling EP-29's
      individual `checkBlueprint*` functions and renders via a small
      blueprint-shaped renderer in the same file. Recorded under
      Decision Log.
- [x] M3: List + Vars updates. List.hs `kindSuffix` already handled
      `KindBlueprint -> " [blueprint]"` (landed with EP-29's
      exhaustiveness fix-ups); no further change needed there.
      `seihou-cli/src-exe/Seihou/CLI/Vars.hs` was rewritten to
      dispatch through `discoverRunnable` with three arms
      (`declarationModeModule`, `declarationModeRecipe`,
      `declarationModeBlueprint`); `--explain` against a blueprint
      refuses with the documented four-line message.
- [x] M4: Tests. Pure-helper coverage lives in
      `seihou-core/test/Seihou/Core/ScaffoldSpec.hs` (six new cases
      for `blueprintDhall` and `examplePromptMarkdown`, including
      end-to-end scaffold → eval → validate). List handling is
      covered by a new `runnableToEntryWithOrigin` blueprint case in
      `seihou-cli/test/Seihou/CLI/ListSpec.hs`. The handler-level
      test specs that the plan originally described
      (`NewBlueprintSpec`, `ValidateBlueprintSpec`) were not added —
      see Decision Log: `seihou-cli`'s test suite cannot import the
      `executable seihou` modules where the handlers live, so these
      mirror the existing `NewModule`/`Validate` siblings (no
      direct unit tests; smoke-tested manually).
- [x] M5: Documentation. New pages at `docs/cli/new-blueprint.md`
      and `docs/cli/validate-blueprint.md` mirror the existing
      `new-module` / `validate-module` docs. `docs/user/CHANGELOG.md`
      gained a 2026-05-07 entry summarising EP-30's user-visible
      changes.


## Surprises & Discoveries

- 2026-05-07 (M2) — EP-29's `Seihou.Core.Blueprint` ships the
  individual `checkBlueprint*` rule-checking functions and the
  top-level `validateBlueprint :: FilePath -> Blueprint -> IO
  (Either ModuleLoadError Blueprint)` aggregator, but it does *not*
  ship a `buildBlueprintReport` adapter, a `blueprintAsModule`
  shim, or an `emptyBlueprint` placeholder constructor. The
  Integration Points section of this plan and of the masterplan
  both name those three adapters as EP-29 contracts. They are not
  there. EP-30's `ValidateBlueprint` handler therefore calls each
  EP-29 `checkBlueprint*` function directly and synthesises its own
  blueprint-shaped report (`BlueprintReport`) and renderer rather
  than feeding through `Seihou.CLI.Style.renderReportColor`. The
  divergence is contained: the new renderer reuses
  `DiagCheck`/`DiagSeverity` from `Seihou.Engine.Validate` so the
  visual style matches `validate-module`. Cross-plan note: the
  masterplan's Integration Point #1 description (mentions of
  `buildBlueprintReport`/`blueprintAsModule`/`emptyBlueprint`)
  should be updated when EP-31 lands so a future contributor does
  not look for adapters that never existed.

- 2026-05-07 (M3) — `List.hs`'s `kindSuffix` already had the
  `KindBlueprint -> " [blueprint]"` arm. EP-29's M1 commit was
  required to land all three constructor consumers in lockstep
  (`-Wincomplete-patterns` makes any `case` over `RunnableKind`
  fail to compile until every kind is handled), and the list
  formatter is one of those consumers. M3 of this plan therefore
  reduced to "extend Vars.hs" — the list change was already there.

- 2026-05-07 (M3) — Pre-EP-30 behaviour: `seihou vars <recipe>`
  always errored with `Module 'X' not found` because `handleVars`
  unconditionally called `loadModule` (which only knows about
  `module.dhall`). The rewrite to `discoverRunnable` made recipe
  declaration mode work as a side effect — `declarationModeRecipe`
  is a parallel arm to `declarationModeModule`. `--explain` for
  recipes still passes through to `explainMode`, which calls
  `loadComposition` and may or may not handle recipes; that's
  out-of-scope for EP-30.

- 2026-05-07 (M4) — The seihou-cli test suite's `other-modules`
  layout is library-only: tests cannot import
  `Seihou.CLI.Commands`, `Seihou.CLI.NewBlueprint`, or
  `Seihou.CLI.ValidateBlueprint` because all three live in the
  `executable seihou` target. This is the same trap that explains
  why `NewModule.hs` and `Validate.hs` do not have direct
  handler-level unit tests. The plan's M4 originally specified
  `NewBlueprintSpec` and `ValidateBlueprintSpec` against handler
  IO; those would not compile. EP-30 covers the equivalent pure
  surface (`blueprintDhall`/`examplePromptMarkdown` end-to-end
  scaffold → eval → validate) in `seihou-core/test`, plus a
  formatter test for the list `[blueprint]` suffix in
  `seihou-cli/test`. Smoke-test transcript verified manually.


## Decision Log

- Decision: `prompt.md` is a separate file imported by
  `blueprint.dhall` as `./prompt.md as Text`, not inlined into the
  Dhall record as a multi-line string literal.
  Rationale: Inlining a 30-line Markdown body into Dhall makes the
  author edit Markdown through Dhall's escaping rules (every
  backslash and every `${` becomes load-bearing), Dhall errors
  reference Dhall positions rather than Markdown line numbers, and
  downstream tools (lint, prose checkers, `git diff`, the EP-31
  runner's prompt preview) cannot operate on a "Markdown file" they
  recognise. An `./prompt.md as Text` import preserves the rendered
  string verbatim and matches how seihou modules already use external
  file imports. EP-29's schema declares `prompt :: Text`; whether
  that field is populated via an inline literal or an import is the
  validator's no-op.
  Date: 2026-05-07.

- Decision: `validate-blueprint` is a separate command (with its own
  `ValidateBlueprintOpts` and handler module
  `Seihou.CLI.ValidateBlueprint`) rather than an extension of
  `validate-module` that auto-detects the artifact at PATH.
  Rationale: `validate-module` ships with a documented contract
  ("PATH contains module.dhall"); silently accepting blueprints at
  the same command would swallow user typos. The existing
  `Validate.hs` builds a `Module`-shaped `ValidateReport` that does
  not naturally accept a `Blueprint`. The `Command` ADT already
  pairs `NewModule`/`NewRecipe` for the same reason; parity is the
  path of least surprise.
  Date: 2026-05-07.

- Decision: `seihou vars BLUEPRINT --explain` is *refused* in this
  plan rather than partially supported.
  Rationale: `--explain` resolves variables through the full
  precedence chain (CLI → env → local → namespace → context →
  global → defaults → interactive prompts). For a blueprint, that
  chain is the runner's job (EP-31). Implementing a second
  resolution path here either duplicates runner logic about to land
  in EP-31, or stubs out the parts that need interactive prompts and
  produces subtly wrong "explain" output. EP-31 will revise the
  refusal message to "supported" semantics in its own diff.
  Date: 2026-05-07.

- Decision: Reuse the same name-format rule
  (`[a-z][a-z0-9-]*`) and the same predicate shape as
  `Seihou.CLI.NewModule.isValidModuleName`.
  Rationale: The masterplan states blueprints share the
  module/recipe namespace so a single `discoverRunnable` lookup
  resolves all three kinds. Reusing the predicate keeps the rule a
  single source of truth.
  Date: 2026-05-07.

- Decision (M2 implementation-time): Build the validate-blueprint
  report locally in `Seihou.CLI.ValidateBlueprint` rather than
  depending on a `buildBlueprintReport`/`blueprintAsModule`
  adapter from `Seihou.Core.Blueprint`.
  Rationale: EP-29's `Seihou.Core.Blueprint` ships only the
  individual `checkBlueprint*` rule predicates and the top-level
  `validateBlueprint :: FilePath -> Blueprint -> IO (Either
  ModuleLoadError Blueprint)` aggregator. The
  `buildBlueprintReport`/`blueprintAsModule`/`emptyBlueprint`
  adapters this plan named under "What EP-29 ships" do not exist.
  EP-30 had two paths: (a) extend `Seihou.Core.Blueprint` with
  the missing adapters, or (b) build the report at the consumer
  site. Option (b) keeps EP-29 immutable, isolates the
  blueprint-vs-module rendering split inside
  `ValidateBlueprint.hs`, and matches the existing CLI pattern
  where module/recipe formatters live in the CLI layer. Chosen.
  Visual style matches `validate-module` because the new renderer
  reuses `DiagCheck`/`DiagSeverity` from
  `Seihou.Engine.Validate`. EP-31's runner, which also wants to
  validate a blueprint before launching the agent, can either
  reuse the same `BlueprintReport` shape (re-exporting it from
  `ValidateBlueprint`) or call `validateBlueprint` directly and
  format errors itself. Recorded so a future contributor does not
  refactor toward an adapter that was never designed.
  Date: 2026-05-07.

- Decision (M3 implementation-time): Switch `seihou vars` from
  `loadModule` to `discoverRunnable` for *all* runnable kinds, not
  only blueprints.
  Rationale: The plan says to use `discoverRunnable` for blueprints
  and leaves the recipe arm as optional. The simplest shape that
  ships blueprints correctly *also* fixes a pre-existing dead path
  for recipes (`vars <recipe>` previously errored "module not
  found"). Splitting the dispatch by kind in `handleVars` is a
  one-screen change and the new `declarationModeRecipe` is a
  trivial mirror of `declarationModeModule`. Cost: the small
  behaviour change that an *invalid* module (one that decodes but
  fails `validateModule`) now shows its declared variables in
  declaration mode rather than erroring out, because
  `discoverRunnable` decodes without validating. This is on the
  right side of useful for `seihou vars` whose job is to inspect
  declarations, and matches what most users expect when they ask
  "what variables does this thing declare?".
  Date: 2026-05-07.

- Decision (M4 implementation-time): Cover the new behaviour
  through pure-helper specs in `seihou-core/test` and a list
  formatter case in `seihou-cli/test`, rather than direct
  handler-level specs in `seihou-cli/test`.
  Rationale: `seihou-cli`'s `test-suite` `other-modules` layout
  cannot import any module from the `executable seihou` target
  (Cabal layout — test suites in the same package can only import
  library modules). `Seihou.CLI.NewBlueprint`,
  `Seihou.CLI.ValidateBlueprint`, and `Seihou.CLI.Commands` all
  live under `executable seihou` (transitively trapped by
  `Options.Applicative`). The originally-planned
  `NewBlueprintSpec` / `ValidateBlueprintSpec` modules failed to
  compile (`Could not find module 'Seihou.CLI.NewBlueprint'`).
  Existing siblings `NewModule.hs` and `Validate.hs` have the
  same constraint and ship without direct handler unit tests, so
  this plan follows the same pattern: pure-helper coverage in
  `Seihou.Core.ScaffoldSpec` (six new cases exercising
  `blueprintDhall`/`examplePromptMarkdown` through the full
  scaffold → eval → validate pipeline against the on-disk
  schema), plus a `runnableToEntryWithOrigin` blueprint case in
  `Seihou.CLI.ListSpec`, plus the smoke-test transcript that was
  manually verified during M1–M3. Future work that wants
  handler-level coverage should either move shared helpers into
  `seihou-cli-internal` (the library) or shell out to the
  `seihou` executable from a test (more friction, less precise).
  Date: 2026-05-07.


## Outcomes & Retrospective

EP-30 shipped the static surface around the new blueprint runnable
type. After this plan landed, a contributor in a writable git
checkout can:

- run `seihou new-blueprint NAME [--path DIR]` and get a fresh
  directory containing `blueprint.dhall` (importing the seihou-schema
  via URL and using `S.Blueprint::`), `prompt.md` (a 30-line Markdown
  body imported by the Dhall record as `./prompt.md as Text`), and
  an empty `files/` subdirectory;
- run `seihou validate-blueprint [PATH]` and see a structured
  report mirroring `validate-module`'s shape, with one row per
  rule (Dhall evaluation, name format, version, prompt non-empty,
  unique vars, prompt refs, base modules, reference files, tags,
  allowed tools);
- run `seihou list` and see blueprints displayed alongside modules
  and recipes with a `[blueprint]` source-tag suffix;
- run `seihou vars BLUEPRINT` and see the blueprint's declared
  variables under a `(blueprint)` heading. `--explain` is refused
  with a four-line message pointing at `seihou agent run` (EP-31).

Surface that lands but is intentionally limited:

- `--lint` on `validate-blueprint` is a no-op. The flag is wired
  through the parser for parity with `validate-module`; future
  work can add lint checks without changing the CLI surface.
- `seihou vars <recipe>` declaration mode now works as a side
  effect of routing through `discoverRunnable`; previously it
  errored. `vars --explain <recipe>` still goes through the
  pre-existing `loadComposition` path which may not handle
  recipes — out-of-scope for EP-30.

What was harder than expected:

- The plan named EP-29 adapters
  (`buildBlueprintReport`/`blueprintAsModule`/`emptyBlueprint`)
  that EP-29 never shipped. Recovery was straightforward:
  `ValidateBlueprint.hs` builds a parallel `BlueprintReport` /
  renderer locally, reusing `DiagCheck`/`DiagSeverity` for visual
  consistency. Recorded under Surprises and Decision Log.
- The seihou-cli test-suite layout cannot import src-exe modules.
  M4's plan-described handler specs would not compile. Recovery:
  shift M4 to pure-helper coverage in `seihou-core/test`
  (validating `blueprintDhall`/`examplePromptMarkdown` through the
  full scaffold pipeline) plus a list formatter case in
  `seihou-cli/test`.

Cross-plan implications recorded for the next plans in the
masterplan:

- EP-31 (agent runner): can choose to reuse `BlueprintReport` from
  `ValidateBlueprint` (re-export it from the module) or call
  `validateBlueprint` directly. Either is fine. The existing
  `discoverRunnable` is the right entry point — do not roll a
  blueprint-only loader.
- EP-31 must preserve the user-typed name when echoing it back to
  the user (e.g., in error messages), as discovered in EP-29's
  Surprises section. EP-30's `--explain` refusal already follows
  this rule.
- EP-34 (docs): update the masterplan's Integration Point #1
  description to drop mentions of
  `buildBlueprintReport`/`blueprintAsModule`/`emptyBlueprint`,
  which never existed. EP-30's Surprises section is the canonical
  reference for what actually shipped.
- EP-34: when documenting `validate-blueprint`, copy from
  `docs/cli/validate-blueprint.md` rather than re-stating from the
  master plan; the doc reflects shipped behaviour.

Tests: 831 (seihou-core) + 212 (seihou-cli) all pass. Six new
cases under `Seihou.Core.Scaffold` cover the new helpers
end-to-end. One new case under `Seihou.CLI.List` covers the
`[blueprint]` formatter arm. Smoke-test transcript with
`new-blueprint` → `validate-blueprint` → `list` → `vars` (with and
without `--explain`) verified manually at M1–M3 stopping points.
`nix/check-cli-module-placement.sh` accepts the two new src-exe
modules (both transitively import `Seihou.CLI.Commands`).


## Context and Orientation

All paths below are absolute or rooted at the repository root
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

### What EP-29 ships (consumed, not delivered here)

EP-29 lands in parallel and is a hard dependency of EP-30. Per the
masterplan's Integration Points section, before EP-30's first
compile attempt the following must already exist.

In `seihou-core/src/Seihou/Core/Types.hs`: a record type `Blueprint`
adjacent to the existing `Module` and `Recipe` records, with at
minimum the fields `name :: ModuleName`, `version :: Maybe Text`,
`description :: Maybe Text`, `prompt :: Text`, `vars :: [VarDecl]`,
`prompts :: [Prompt]`, `baseModules :: [Dependency]`,
`files :: [BlueprintFile]`, `tags :: [Text]`. The `Runnable` ADT has
gained `RunnableBlueprint Blueprint FilePath`; the `RunnableKind`
enum has gained `KindBlueprint`.

In `seihou-core/src/Seihou/Dhall/Eval.hs`: `evalBlueprintFromFile ::
FilePath -> IO (Either DhallEvalError Blueprint)`, mirroring
`evalModuleFromFile`.

In `seihou-core/src/Seihou/Core/Blueprint.hs` (a new module added by
EP-29): `validateBlueprint :: FilePath -> Blueprint -> IO
[BlueprintIssue]` plus a small adapter `buildBlueprintReport :: Bool
-> FilePath -> Blueprint -> IO ValidateReport` that folds the
issues into the existing `Seihou.Engine.Validate.ValidateReport`
shape. EP-30 calls only `buildBlueprintReport`; the issue type is
EP-29's contract. Because `ValidateReport` keys on `reportModule ::
Module`, EP-29 also exports `blueprintAsModule :: Blueprint ->
Module` (a no-semantics adapter that copies shared fields and
empties the rest) so the existing renderer is reused unchanged.

In `seihou-core/src/Seihou/Core/Module.hs`: `discoverRunnable`
returns `RunnableBlueprint b dir` when a blueprint named NAME is the
closest match; `discoverAllRunnables` enumerates blueprints with
`drKind = KindBlueprint`.

In `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`: `schemaUrl` and
`schemaHash` point at a `seihou-schema` revision that exports
`S.Blueprint`, `S.BlueprintFile`, and `S.Dependency`.

If any of these is missing at implementation time, stop and revise
the masterplan's Integration Points section before continuing — do
not work around the gap in this plan.

### What this repository already provides

`seihou-cli/src-exe/Seihou/CLI/NewModule.hs` is the structural
template for `NewBlueprint.hs`: name validation
(`isValidModuleName`), `doesDirectoryExist` guard,
`createDirectoryIfMissing` for `files/`, `writeFile` for
`module.dhall` plus the README template. Read it once before
writing the new handler.

`seihou-core/src/Seihou/Core/Scaffold.hs` exports `moduleDhall name
url hash` (the boilerplate Dhall text with the schema imported via
URL and `S.Module::{ ... }` record completion) and `readmeTemplate`.
This plan adds two parallel exports `blueprintDhall` and
`examplePromptMarkdown`.

`seihou-cli/src-exe/Seihou/CLI/Validate.hs` is the structural
template for `ValidateBlueprint.hs`. It determines `moduleDir` from
`validatePath`, exits 4 if `module.dhall` is missing, calls
`evalModuleFromFile`, and on `Right modul` calls
`Seihou.Engine.Validate.buildReport` and renders via
`Seihou.CLI.Style.renderReportColor`. The blueprint variant
substitutes `blueprint.dhall`, `evalBlueprintFromFile`, and EP-29's
`buildBlueprintReport`.

`seihou-cli/src/Seihou/CLI/List.hs`'s `runnableToEntryWithOrigin`
contains a `case dr.drKind of KindModule -> ""; KindRecipe -> "
[recipe]"` block. After EP-29 adds `KindBlueprint`, GHC's
`-Wincomplete-patterns` warning fails the build until M3 adds the
third arm.

`seihou-cli/src-exe/Seihou/CLI/Vars.hs` calls `loadModule
searchPaths modName` and prints the result via `declarationMode`.
M3 generalises this to a `discoverRunnable` lookup that handles all
three runnable kinds, with the `--explain` arm refusing blueprints.

`seihou-cli/src-exe/Seihou/CLI/Commands.hs` is where every option
record, parser, and `Command` constructor lives. Three new
constructors land here in this plan and are wired through
`commandParser`'s "Authoring:" group:

    command "new-blueprint" newBlueprintInfo
    command "validate-blueprint" validateBlueprintInfo

`seihou-cli/src-exe/Main.hs` dispatches the parsed `Command`. Two
new arms land here, mirroring `NewModule`/`ValidateModule`.

### Library-first module placement

Per the project `CLAUDE.md`, library code goes under
`seihou-cli/src/`; `seihou-cli/src-exe/` is reserved for modules
that import `Options.Applicative`, `Data.FileEmbed`, `GitHash`,
`Paths_seihou_cli`, or transitively another `src-exe`-only module
(typically `Seihou.CLI.Commands`). Both new modules
(`Seihou.CLI.NewBlueprint`, `Seihou.CLI.ValidateBlueprint`) import
`Seihou.CLI.Commands` for their option types, so both belong in
`src-exe/`, exactly like their `NewModule`/`Validate` siblings.
`nix/check-cli-module-placement.sh` mechanically rejects
misplacements; M4's `just check` confirms.

### How CLI tests are structured

`seihou-cli/test/Main.hs` imports each spec module and feeds
`tests :: IO TestTree` into `Test.Tasty.defaultMain`. New specs
follow either the pure-formatter shape of
`seihou-cli/test/Seihou/CLI/ListSpec.hs` or the temp-dir-handler
shape of `seihou-cli/test/Seihou/CLI/Registry/ValidateSpec.hs`.


## Plan of Work

The work is organised as five milestones M1–M5. Each is independently
buildable, testable, and reviewable. Build with `cabal build all`
from the repo root; test with `cabal test all
--test-show-details=direct`. `just check` (which wraps `nix flake
check` plus pre-commit hooks) catches placement violations and is
run as part of M4.


### M1 — `seihou new-blueprint`

After this milestone, a fresh blueprint directory can be created
with one command and the result type-checks against the Dhall
schema (semantic validation arrives in M2).

In `seihou-core/src/Seihou/Core/Scaffold.hs`, add `blueprintDhall`
and `examplePromptMarkdown` to the export list and implement them
at the bottom of the file. `blueprintDhall name url hash` returns
the Dhall text below (matching `moduleDhall`'s style):

    let S =
          <url>
            <hash>

    in  S.Blueprint::{
        , name = "<name>"
        , version = Some "0.1.0"
        , description = Some "A new seihou blueprint"
        , prompt = ./prompt.md as Text
        , vars =
          [ S.VarDecl::{
            , name = "project.name"
            , type = "text"
            , description = Some "The name of the project"
            , required = True
            }
          ]
        , prompts =
          [ S.Prompt::{
            , var = "project.name"
            , text = "What is your project name?"
            }
          ]
        , baseModules = [] : List S.Dependency.Type
        , files = [] : List S.BlueprintFile.Type
        , tags = [] : List Text
        }

The exact field names match EP-29's Integration Point #1. If EP-29's
schema renames any field (for example, `S.BlueprintFile.Type` is
spelled differently), `blueprintDhall` is adjusted at integration
time and the divergence is recorded in the Decision Log.

`examplePromptMarkdown` returns a novice-friendly Markdown body that
the agent runner (EP-31) will eventually consume. The body opens
with `# {{project.name}}` so the templating substitution is visible
to authors, then describes what the agent has access to (the
`./files/` reference dir mounted via `--add-dir`, the seihou and git
toolsets), what to do (confirm the goal, lay down the scaffolding,
iterate), and conventions (Conventional Commits, small testable
pieces, ask before destructive changes). The exact text is
implementation-time detail; the contract is "between 20 and 40
lines of plain Markdown that an author can edit without
reading source code".

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, add the option
record, the `Command` constructor, the parser, the `ParserInfo`,
and wire the parser into `commandParser`'s "Authoring:" group:

    data NewBlueprintOpts = NewBlueprintOpts
      { newBlueprintName :: Text,
        newBlueprintPath :: Maybe FilePath
      }
      deriving stock (Eq, Show, Generic)

    newBlueprintParser :: Parser Command
    newBlueprintParser =
      fmap NewBlueprint $
        NewBlueprintOpts
          <$> argument (T.pack <$> str) (metavar "NAME")
          <*> optional (option str (long "path" <> metavar "DIR" <> help "Output directory (default: ./<name>/)"))

The `ParserInfo` wraps `newBlueprintParser` with `progDesc
"Scaffold a new agent-driven blueprint"` and a footer naming the
three artifacts produced (blueprint.dhall, prompt.md, files/) and
the name-format rule.

Add `seihou-cli/src-exe/Seihou/CLI/NewBlueprint.hs` (mirroring
`NewModule.hs`): validate the name (same predicate body as
`isValidModuleName` but inlined as `isValidBlueprintName`); resolve
`outputDir` from `newBlueprintPath` defaulting to `T.unpack name`;
exit non-zero with "directory already exists" if the directory is
non-empty; `createDirectoryIfMissing True (outputDir </> "files")`;
`writeFile` `blueprint.dhall` from `blueprintDhall name schemaUrl
schemaHash` and `prompt.md` from `examplePromptMarkdown`; print a
"Created …" line per artifact and a final "Blueprint '<name>'
created at <dir>/" summary.

In `seihou-cli/src-exe/Main.hs`, add the dispatch arm next to
`NewModule`/`NewRecipe`:

    NewBlueprint blueprintOpts ->
      handleNewBlueprint blueprintOpts

…and the corresponding import.

In `seihou-cli/seihou-cli.cabal`, add `Seihou.CLI.NewBlueprint` to
the `executable seihou` stanza's `other-modules` list.

Acceptance for M1: from a throwaway directory,

    cabal run seihou-cli:seihou -- new-blueprint demo --path /tmp/demo

prints three "Created" lines and one summary, and `/tmp/demo`
contains exactly `blueprint.dhall`, `prompt.md`, and `files/`.
Re-running fails with the existing-directory error and exit
non-zero. Running `seihou new-blueprint Bad_Name` fails with the
invalid-name error and exit non-zero.


### M2 — `seihou validate-blueprint`

After this milestone, a blueprint directory can be checked for
syntactic and semantic problems with the same shape of report
`seihou validate-module` produces today.

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, add
`ValidateBlueprintOpts (..)` with `validateBlueprintPath :: Maybe
FilePath` and `validateBlueprintLint :: Bool`, the
`ValidateBlueprint` `Command` constructor, the parser, and the
`ParserInfo` (named `validateBlueprintInfo`). Wire `command
"validate-blueprint" validateBlueprintInfo` into `commandParser`'s
"Authoring:" group, immediately after `command "validate-module"
validateInfo`.

Add `seihou-cli/src-exe/Seihou/CLI/ValidateBlueprint.hs`. The handler
mirrors `Validate.hs`:

1. Resolve `blueprintDir` from `validateBlueprintPath` defaulting to
   `getCurrentDirectory`.
2. Check `<blueprintDir>/blueprint.dhall` exists; exit 4 if not.
3. Call `evalBlueprintFromFile <blueprintDir>/blueprint.dhall`.
4. On `Left err`, build a `ValidateReport` with `reportDhallOk =
   False` and `reportModule = blueprintAsModule (emptyBlueprint
   "<unknown>")` (the dummy adapter EP-29 ships); render via
   `renderReportColor` and `exitFailure`.
5. On `Right bp`, call `buildBlueprintReport
   vopts.validateBlueprintLint blueprintDir bp` (the EP-29 helper),
   render via `renderReportColor`, and `exitFailure` if
   `reportHasErrors` returns `True`.

In `seihou-cli/src-exe/Main.hs`, add the dispatch arm `ValidateBlueprint
opts -> handleValidateBlueprint opts` and the import. In
`seihou-cli/seihou-cli.cabal`, add `Seihou.CLI.ValidateBlueprint` to
the `executable seihou` stanza's `other-modules`.

Acceptance for M2: against the M1 fixture,

    cabal run seihou-cli:seihou -- validate-blueprint /tmp/demo

exits 0 and prints a green "OK" report listing the checks that
passed (Dhall evaluation, name format, variable uniqueness, prompts
consistency, files-list integrity, baseModules-not-blueprint).
Mutating the fixture (delete `prompt.md` so the import fails;
rename to `Bad_Name`; introduce a duplicate variable; reference an
undeclared variable in `prompts`; add a `files` entry pointing at a
missing file under `files/`) yields non-zero exit and a clear error
row per broken rule. The exact wording of each rule is EP-29's
contract; this handler is a thin adapter.


### M3 — `seihou list` and `seihou vars` learn about blueprints

After this milestone, the two existing inspection commands display
blueprints in their output, with a clear visual indicator and a
clean refusal for the unsupported `--explain` path.

In `seihou-cli/src/Seihou/CLI/List.hs`, the existing case at
`runnableToEntryWithOrigin` reads:

    kindSuffix = case dr.drKind of
      KindModule -> ""
      KindRecipe -> " [recipe]"

After EP-29 adds `KindBlueprint`, this case is non-exhaustive and
the GHC `-Wincomplete-patterns` warning fails the build. M3 adds:

    kindSuffix = case dr.drKind of
      KindModule -> ""
      KindRecipe -> " [recipe]"
      KindBlueprint -> " [blueprint]"

The header text — currently `"Available modules and recipes:\n"` —
becomes `"Available modules, recipes, and blueprints:\n"`. The
summary noun "modules" stays put; the per-row tag carries the
disambiguation.

In `seihou-cli/src-exe/Seihou/CLI/Vars.hs`, replace the top-level
`loadModule searchPaths modName` call with `discoverRunnable
searchPaths modName` and pattern-match on the resulting `Runnable`:

- `RunnableModule m _` → call the existing `declarationMode m`
  (renamed `declarationModeModule m`).
- `RunnableRecipe r _` → call a new `declarationModeRecipe r` that
  prints the recipe's declared `vars`/`prompts` the same way (a
  parallel arm; if the recipe arm is too entangled with
  `loadComposition` to land cleanly here, leave it as a follow-up
  and record in the Decision Log — the blueprint arm is the
  load-bearing one for *this* plan).
- `RunnableBlueprint b _` → if `vopts.varsExplain`, log the
  four-line refusal below and `exitFailure`; otherwise call a new
  `declarationModeBlueprint b`.

The refusal message reads:

    '<name>' is a blueprint; --explain is not supported in this release.
    Resolving a blueprint's variables requires the agent runner.
    Run `seihou agent run <blueprint>` instead (when EP-31 ships).
    For a read-only listing of declared variables, omit --explain.

`declarationModeBlueprint` opens with `Variables for <name>
(blueprint):` and uses `Seihou.Core.Variable.formatDeclarations` on
the blueprint's `vars`, the same formatter the module path uses.

Acceptance for M3:

    cabal run seihou-cli:seihou -- list

shows the M1 fixture's `demo` line tagged `[blueprint]`.

    cabal run seihou-cli:seihou -- vars demo

prints `Variables for demo (blueprint):` followed by the declared
`project.name` line; exit 0.

    cabal run seihou-cli:seihou -- vars demo --explain

prints the four-line refusal and exits non-zero.


### M4 — Tests

After this milestone, every behaviour M1–M3 introduces is covered.

`seihou-cli/test/Seihou/CLI/NewBlueprintSpec.hs` (new): one positive
test calls `handleNewBlueprint (NewBlueprintOpts "demo" (Just dir))`
under `withSystemTempDirectory` and asserts that `dir/blueprint.dhall`
exists, `dir/prompt.md` exists, and `dir/files/` is a directory. One
negative test passes name `Bad_Name` and asserts the call exits
non-zero (use the `try @SomeException`-around-`exitFailure` idiom
used elsewhere in the suite — search for `IOError` /
`SomeException` patterns in `seihou-cli/test/`).

`seihou-cli/test/Seihou/CLI/ValidateBlueprintSpec.hs` (new): one
positive test scaffolds via `handleNewBlueprint` then calls
`handleValidateBlueprint` and asserts exit 0. One negative test
deletes `prompt.md` from the fixture and asserts non-zero exit. One
"missing file" test points the handler at an empty temp dir and
asserts exit code 4.

`seihou-cli/test/Seihou/CLI/ListSpec.hs` (extended): one new `it`
case constructs a `DiscoveredRunnable` with `drKind = KindBlueprint`
(mirroring the existing module/recipe fixtures) and asserts the
formatted output contains `" [blueprint]"`.

Register the two new modules in `seihou-cli/seihou-cli.cabal`'s
`test-suite seihou-cli-test` `other-modules` list (alphabetical
position) and import + sequence them in `seihou-cli/test/Main.hs`:

    import Seihou.CLI.NewBlueprintSpec qualified as NewBlueprintSpec
    import Seihou.CLI.ValidateBlueprintSpec qualified as ValidateBlueprintSpec
    -- in the sequence list:
    , NewBlueprintSpec.tests
    , ValidateBlueprintSpec.tests

Acceptance for M4: `cabal test seihou-cli-test
--test-show-details=direct` runs every existing test plus the new
specs, all green. `just check` passes — `nix/check-cli-module-placement.sh`
accepts both new `executable seihou` modules because both
transitively import `Seihou.CLI.Commands`.


### M5 — Documentation

After this milestone, the new commands are findable through the
same docs structure that today documents `seihou new-module` and
`seihou validate-module`.

The exact docs page is determined at implementation time by
`grep -lr "new-module\|validate-module" /Users/shinzui/Keikaku/bokuno/seihou-project/seihou/docs/`.
Likely candidates: `docs/cli/authoring.md`, a per-command reference
under `docs/cli/`, and `docs/user/CHANGELOG.md`. Add short sections
for `seihou new-blueprint` and `seihou validate-blueprint` mirroring
the existing `seihou new-module` and `seihou validate-module`
sections (synopsis, options table, description, example).

Add a CHANGELOG entry under `docs/user/CHANGELOG.md`'s "Unreleased"
section:

    ### Added

    - `seihou new-blueprint NAME [--path DIR]`: scaffold a new
      agent-driven blueprint (blueprint.dhall + prompt.md + files/).
    - `seihou validate-blueprint [PATH]`: validate a blueprint
      directory the same way `validate-module` validates a module.
    - `seihou list` now shows blueprints with a `[blueprint]` suffix.
    - `seihou vars BLUEPRINT` lists a blueprint's declared variables.
      `--explain` is not yet supported for blueprints; run
      `seihou agent run` (EP-31) for full resolution.


## Concrete Steps

The commands below run from the repo root
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`. Every step is
idempotent.

### Build

    cabal build all

Expected: both `seihou-core` and `seihou-cli` build cleanly with no
new warnings after each milestone.

### Test

    cabal test all --test-show-details=direct

Expected: every existing spec passes plus the new cases in
`Seihou.CLI.NewBlueprint`, `Seihou.CLI.ValidateBlueprint`, and the
extended `Seihou.CLI.ListSpec`. The first run after adding a new
module may need a prior `cabal build` to refresh the build plan.

### Lint and placement check

    just fmt
    just check

Expected: `nix/check-cli-module-placement.sh` accepts the two new
`src-exe/` modules because both import `Seihou.CLI.Commands` (the
documented trapping import).

### Smoke-test transcript

    REPO=$(mktemp -d -t seihou-blueprint-XXXX)
    cd "$REPO"
    cabal run seihou-cli:seihou -- new-blueprint payments-service

Expected:

    Created payments-service/blueprint.dhall
    Created payments-service/prompt.md
    Created payments-service/files/
    Blueprint 'payments-service' created at payments-service/

Then:

    cabal run seihou-cli:seihou -- validate-blueprint payments-service

Expected: exit 0 and a green "OK" report.

    cabal run seihou-cli:seihou -- list

Expected: a row `payments-service` with the `[blueprint]` suffix in
the source-tag column.

    cabal run seihou-cli:seihou -- vars payments-service

Expected: `Variables for payments-service (blueprint):` followed by
a single declaration line for `project.name`.

    cabal run seihou-cli:seihou -- vars payments-service --explain

Expected: non-zero exit and the four-line refusal pointing at
`seihou agent run`.


## Validation and Acceptance

Acceptance is observable behaviour, not "the code compiles".

1. `seihou new-blueprint --help` prints the new help text mentioning
   `blueprint.dhall`, `prompt.md`, and `files/`.

2. `seihou new-blueprint NAME` produces exactly `<NAME>/blueprint.dhall`,
   `<NAME>/prompt.md`, and `<NAME>/files/`. Re-running fails with
   exit non-zero and the existing-directory message. Passing
   `Bad_Name` fails with the invalid-name message.

3. `seihou validate-blueprint <NAME>` exits 0 on a freshly
   scaffolded directory. Each individual mutation (delete prompt.md,
   rename to Bad_Name, duplicate variable, undeclared prompt
   reference, missing files entry) yields exit non-zero with a
   clear error row.

4. `seihou list` shows blueprints tagged `[blueprint]` in the
   source-tag column, on the same row format as modules and
   recipes.

5. `seihou vars BLUEPRINT` opens with `Variables for <NAME>
   (blueprint):` and lists every declared variable.

6. `seihou vars BLUEPRINT --explain` exits non-zero with the
   four-line message naming `seihou agent run` and EP-31.

7. `nix/check-cli-module-placement.sh` accepts the new modules;
   `just check` does not flag `Seihou.CLI.NewBlueprint` or
   `Seihou.CLI.ValidateBlueprint`.

8. `cabal test all` is green; no new warnings introduced.

A failure of any of (1)–(8) is a regression and must be fixed
before the plan is marked complete.


## Idempotence and Recovery

Every new command is either read-only (`validate-blueprint`,
`list`, `vars`) or refuses to overwrite existing state
(`new-blueprint` errors out on a non-empty target). Re-running any
of them is safe.

The implementation steps are additive: new option records, new
handler modules, new parser branches, new dispatch arms. There is
no schema migration, no on-disk format change in this plan (the
schema bump is EP-29's responsibility), and no manifest write.
Recovery from a partial implementation is to delete the new files
or to commit and continue.

If `cabal test` fails after adding the new specs, the most likely
cause is forgetting to register a spec in *both*
`seihou-cli/seihou-cli.cabal` (`other-modules`) *and*
`seihou-cli/test/Main.hs` (the import + sequence list). Re-check
both. If `nix/check-cli-module-placement.sh` flags a misplacement,
confirm the new module lives under
`seihou-cli/src-exe/Seihou/CLI/` and is listed in the `executable
seihou` `other-modules`, not in the library's `exposed-modules` —
`Seihou.CLI.Commands` is a `src-exe` module, so any importer is
trapped into `src-exe/`.

If EP-29's surface differs from this plan's assumptions (for
example, `validateBlueprint` returns a different structure than
`Seihou.Engine.Validate.ValidateReport`, or `RunnableKind`'s
constructor is named differently), adapt the wiring at the consumer
site and record the change in the Decision Log; do *not* edit
EP-29.


## Interfaces and Dependencies

This plan adds no new third-party Haskell dependencies. Every
required import (`Data.Text`, `Data.Text.IO`, `System.Directory`,
`System.FilePath`, `System.IO.Temp` for tests) is already available
through `seihou-core` and the existing `seihou-cli-internal`
library.

After the work is complete, the following symbols and signatures
must exist.

In `seihou-core/src/Seihou/Core/Scaffold.hs`:

    blueprintDhall :: Text -> Text -> Text -> Text
    examplePromptMarkdown :: Text

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`:

    data NewBlueprintOpts = NewBlueprintOpts
      { newBlueprintName :: Text,
        newBlueprintPath :: Maybe FilePath
      }
      deriving stock (Eq, Show, Generic)

    data ValidateBlueprintOpts = ValidateBlueprintOpts
      { validateBlueprintPath :: Maybe FilePath,
        validateBlueprintLint :: Bool
      }
      deriving stock (Eq, Show, Generic)

`Command` gains `NewBlueprint NewBlueprintOpts` and
`ValidateBlueprint ValidateBlueprintOpts`. Both opts types are
re-exported from `Seihou.CLI.Commands` so `Main.hs` can
pattern-match without an extra import (matching the existing
`NewModuleOpts`/`ValidateOpts` pattern).

In `seihou-cli/src-exe/Seihou/CLI/NewBlueprint.hs` (new):

    handleNewBlueprint :: NewBlueprintOpts -> IO ()

In `seihou-cli/src-exe/Seihou/CLI/ValidateBlueprint.hs` (new):

    handleValidateBlueprint :: ValidateBlueprintOpts -> IO ()

This plan *consumes* (must exist by the time M2 lands) the
following EP-29 contracts:

    -- in seihou-core/src/Seihou/Core/Types.hs
    data Blueprint = Blueprint { name :: ModuleName, version :: Maybe Text, ... }
    data Runnable = ... | RunnableBlueprint Blueprint FilePath
    data RunnableKind = KindModule | KindRecipe | KindBlueprint

    -- in seihou-core/src/Seihou/Dhall/Eval.hs
    evalBlueprintFromFile :: FilePath -> IO (Either DhallEvalError Blueprint)

    -- in seihou-core/src/Seihou/Core/Blueprint.hs (new module from EP-29)
    validateBlueprint :: FilePath -> Blueprint -> IO [BlueprintIssue]
    buildBlueprintReport :: Bool -> FilePath -> Blueprint -> IO ValidateReport
    blueprintAsModule :: Blueprint -> Module
    emptyBlueprint :: Text -> Blueprint

    -- in seihou-core/src/Seihou/Core/Module.hs (extended)
    discoverRunnable :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError Runnable)
    discoverAllRunnables :: [FilePath] -> IO [DiscoveredRunnable]

    -- in seihou-cli/src/Seihou/CLI/SchemaVersion.hs
    schemaUrl :: Text
    schemaHash :: Text
    -- pointing at a seihou-schema commit that exports S.Blueprint,
    -- S.BlueprintFile, and S.Dependency.

If EP-29 ships these symbols under different names, M2 and M3's
imports are adjusted accordingly and the Decision Log records the
divergence. The masterplan's Integration Points section is the
authoritative source of truth; revise it (not this plan) if a
contract changes mid-flight.
