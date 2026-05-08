---
id: 29
slug: blueprint-domain-model-and-discovery
title: "Define the Blueprint Domain Model, Schema, Discovery, and Run-Time Refusal"
kind: exec-plan
created_at: 2026-05-07T00:00:00Z
intention: "intention_01kr2q5p3ye30t4vk9fj4q69t1"
---


# Define the Blueprint Domain Model, Schema, Discovery, and Run-Time Refusal

MasterPlan: docs/masterplans/3-agent-driven-blueprints.md
Intention: intention_01kr2q5p3ye30t4vk9fj4q69t1

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Today, Seihou recognises two runnable artifacts: a **module** (a directory
containing `module.dhall` plus a `files/` subdirectory of templates) and a
**recipe** (a directory containing `recipe.dhall`, a named composition of
modules with pre-bound variable values). Both are deterministic: given the
same inputs, `seihou run NAME` produces the same files. This shape is the
right tool for project shapes that vary along small, well-understood axes,
and it is the wrong tool for project shapes whose variation is open-ended
("scaffold a microservice for $domain"). The seihou masterplan
`docs/masterplans/3-agent-driven-blueprints.md` introduces a third runnable
type — the **blueprint** — to fill that gap. A blueprint is a directory
containing `blueprint.dhall`, a Markdown prompt, and reference files; it is
authored by a human and consumed by an AI coding agent, not directly executed.

This ExecPlan, EP-29, is the foundation of that initiative. After it lands,
the following observable behaviour exists:

- A `blueprint.dhall` file authored against the new `Blueprint.dhall` Dhall
  schema type-checks against the published seihou-schema.
- The Haskell library `seihou-core` exposes a `Blueprint` record type, an
  `evalBlueprintFromFile` decoder, and a `validateBlueprint` validator that
  enforces the rules listed below.
- `seihou`'s name-based discovery (`Seihou.Core.Module.discoverRunnable`)
  recognises a blueprint directory alongside modules and recipes, returning
  a new `RunnableBlueprint` constructor on the existing `Runnable` ADT.
- Running `seihou run my-blueprint` against a directory whose
  `blueprint.dhall` resolves prints

      Error: 'my-blueprint' is a blueprint, not a module or recipe.
      Blueprints must be run interactively via:
        seihou agent run my-blueprint

  on stderr and exits with a non-zero status. This refusal is a hard
  invariant; subsequent plans (EP-30 authoring, EP-31 runner, EP-32
  manifest, EP-33 registry, EP-34 docs) all rest on it.

No command authors a blueprint after this plan ships, and no command runs
one. The point of this plan is to make blueprints *first-class data* in the
codebase, so EP-30 can scaffold them, EP-31 can launch them, and so on. A
fixture blueprint placed in `~/.config/seihou/modules/my-blueprint/` is
enough to demonstrate the full surface end-to-end.


## Progress

- [x] M1: Add `Blueprint`, `BlueprintFile`, the `RunnableBlueprint` constructor, and the `KindBlueprint` constructor to `seihou-core/src/Seihou/Core/Types.hs` and `seihou-core/src/Seihou/Core/Module.hs`. Update every exhaustive `case`/`pattern-match` over `Runnable`/`RunnableKind` in the workspace so the build remains warning-clean under `-Wincomplete-patterns`. *Done 2026-05-07: types added; List.hs, Selector/Module.hs, Run.hs all updated. M6's refusal arm landed in the same edit (see Decision Log).*
- [x] M2: Add `schema/Blueprint.dhall`, update `schema/package.dhall`, and add `evalBlueprintFromFile`, `blueprintDecoder`, `blueprintFileDecoder` to `seihou-core/src/Seihou/Dhall/Eval.hs`. *Done 2026-05-07.*
- [x] M3: Add `seihou-core/src/Seihou/Core/Blueprint.hs` exposing `validateBlueprint` and the per-rule `check…` helpers, mirroring `Seihou.Core.Module`'s validator shape. *Done 2026-05-07; registered in `seihou-core.cabal`.*
- [x] M4: Extend `Seihou.Core.Module.discoverRunnable` with a `blueprint.dhall` branch and `discoverAllRunnables` with the matching enumeration; add a private `discoverBlueprint` helper for symmetry with `discoverModule` / `discoverRecipe`. *Done 2026-05-07; `discoverBlueprint` exported.*
- [ ] M5: Mirror `schema/Blueprint.dhall` and the updated `schema/package.dhall` into `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/`, commit and push, and bump the URL/hash in `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`. Bump `mori.dhall` if it pins the schema (it currently pins mori-schema; verify before editing).
- [x] M6: Add the `RunnableBlueprint` refusal branch to `seihou-cli/src-exe/Seihou/CLI/Run.hs` (lines 95-110, the recipe-detection block). *Done 2026-05-07 alongside M1; using a single multi-line `logError` call so the `[error]` prefix appears once. See Decision Log.*
- [ ] M7: Add a positive-and-negative-case `seihou-core` test fixture under `seihou-core/test/fixtures/sample-blueprint/` and a matching `seihou-core/test/Seihou/Core/BlueprintSpec.hs` covering each validation rule. Add a `seihou-cli` integration test under `seihou-cli/test/Seihou/CLI/` exercising the run-refusal branch.
- [ ] M8: Run `cabal build all`, `cabal test all --enable-tests`, `nix flake check`, and a manual end-to-end demo of the refusal message; record the demo transcript in Surprises & Discoveries if it diverges from the plan.


## Surprises & Discoveries

- 2026-05-07 — `Seihou.Effect.Logger.logError` prepends `[error] ` (not
  `Error:`) to every line. The masterplan and Plan-of-Work narrative
  refer to a hypothetical `Error:` prefix. The actual user-observable
  refusal output is therefore prefixed with `[error] `. The "canonical
  refusal text" requirement still holds — every consumer doc must use
  the same body lines — but the literal string visible on stderr begins
  with `[error] `, not `Error:`. Recorded so EP-34's documentation plan
  describes what users actually see.


## Decision Log

- Decision: Re-use the existing `ModuleName` newtype for `Blueprint.name`
  rather than introducing a `BlueprintName`. Recipes followed the opposite
  convention (`RecipeName` exists at
  `seihou-core/src/Seihou/Core/Types.hs:254` with
  `recipeNameToModuleName` to bridge into discovery), but recipes
  predate the unified `discoverRunnable` design. Today every consumer of
  `RecipeName` immediately converts to `ModuleName` for search-path
  resolution (see `Seihou.Core.Module.discoverRunnable`'s
  `nameStr = T.unpack name.unModuleName`). Blueprints share that
  same `[a-z][a-z0-9-]*` namespace per the masterplan's Decision Log
  (2026-05-07), so adding a parallel newtype would only force a third
  conversion helper without buying type safety. Cross-kind name
  collisions (a blueprint and a module sharing a name) are validated at
  registry-validation time in EP-33; within a single search path the
  first match in `discoverRunnable` wins, with `module.dhall`
  beating `recipe.dhall` beating `blueprint.dhall`.
  Date: 2026-05-07.

- Decision: Place the validator in a new `Seihou.Core.Blueprint` module
  rather than co-locating with `Seihou.Core.Module`. The `Seihou.Core.Recipe`
  module at `seihou-core/src/Seihou/Core/Recipe.hs` sets the precedent: each
  runnable type owns its own validator file. Co-locating would balloon
  `Seihou.Core.Module` (already 446 lines) and would mix domain concerns
  (modules are deterministic file generators; blueprints are agent-prompt
  bundles). The discovery code (`discoverRunnable`,
  `discoverAllRunnables`) stays in `Seihou.Core.Module` because the
  search-path traversal is shared across kinds.
  Date: 2026-05-07.

- Decision: Re-use the existing `Dependency` type for `Blueprint.baseModules`
  rather than introducing a `BlueprintBase`. The dependency record at
  `seihou-core/src/Seihou/Core/Types.hs:176` already carries a
  `depModule :: ModuleName` and a `depVars :: Map VarName Text`
  binding-set, which is exactly what a baseline declaration needs (apply
  module X with these pre-bound variables). The validator has to enforce
  the additional rule that `depModule` resolves to a module or a recipe
  but **not** another blueprint (recorded in the masterplan as a hard
  decision: "Blueprints cannot list other blueprints as base modules,"
  2026-05-07); that check lives in `validateBlueprint`'s rule 6.
  Date: 2026-05-07.

- Decision: Define `BlueprintFile` inline in `schema/Blueprint.dhall`
  rather than at `schema/BlueprintFile.dhall`. The record has only two
  fields (`src`, `description`), both trivially typed. Splitting it into a
  separate schema file would add a `let BlueprintFile = …` line to every
  blueprint authoring scaffold for no reuse benefit (no other schema type
  references it). If a future plan needs to share `BlueprintFile` between,
  for example, blueprints and recipes, splitting it out at that point is a
  mechanical refactor.
  Date: 2026-05-07.

- Decision: Reuse the existing `ModuleLoadError` ADT for blueprint load
  failures rather than introducing a `BlueprintLoadError`. The error
  constructors `ModuleNotFound`, `DhallEvalError`, `DhallDecodeError`, and
  `ValidationError` all carry a `ModuleName` payload that already
  uniquely identifies the offending artifact (recipes do the same via
  `recipeNameToModuleName`). Introducing a parallel `BlueprintLoadError`
  would force every consumer of `discoverRunnable` to widen its error
  type, breaking far more code than the eight call sites that read
  `ModuleLoadError` today. The existing `ValidationError ModuleName
  [Text]` constructor is sufficient to surface blueprint-validator
  failures with a clear identifier.
  Date: 2026-05-07.

- Decision: Land M1 and M6 together in the same commit rather than
  using an `error "EP-29 M6 will fill this in"` placeholder during M1.
  The plan already documented (in the masterplan's Decision Log,
  2026-05-07) that the M1 ADT extension cannot land as a standalone
  commit because every existing exhaustive `case` over `Runnable` /
  `RunnableKind` becomes a compile error. Substituting the placeholder
  arm with the real refusal body in the same edit removes a future
  intermediate commit that would otherwise crash on the new
  `RunnableBlueprint` constructor with a misleading message.
  Date: 2026-05-07.

- Decision: Render the refusal body as a single multi-line `logError`
  call joined by `T.intercalate "\n"` rather than three sequential
  `logError` calls. With the actual logger prefix `[error] ` (see
  Surprises & Discoveries), each separate `logError` would tag its
  line with the prefix; the multi-line form prints the prefix once and
  keeps the indentation of the `seihou agent run …` suggestion
  readable in terminals.
  Date: 2026-05-07.


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

This section names every file and function the rest of the plan references,
with full repository-relative paths so a novice can navigate confidently.
All paths are relative to the repository root
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` unless otherwise stated.

The Seihou codebase is a multi-package Cabal workspace declared in
`cabal.project`. The two packages are `seihou-core` (a library at
`seihou-core/`) and `seihou-cli` (a library at `seihou-cli/src/` plus an
executable at `seihou-cli/src-exe/`). The split between the two CLI sources
is described in the project `CLAUDE.md` and is enforced by
`nix/check-cli-module-placement.sh`: the executable target only contains
modules that genuinely import `Options.Applicative`, `Data.FileEmbed`,
`GitHash`, `Paths_seihou_cli`, or another already-trapped module. The
domain types and validators added by this plan live entirely in
`seihou-core` (no CLI dependencies), with one exception: the run-time
refusal branch in M6 lives in `seihou-cli/src-exe/Seihou/CLI/Run.hs`
because that file already imports `Options.Applicative` (transitively
through `Seihou.CLI.Commands`).

### Domain types: the existing two runnables

`seihou-core/src/Seihou/Core/Types.hs:236` defines the `Module` record:

    data Module = Module
      { name :: ModuleName,
        version :: Maybe Text,
        description :: Maybe Text,
        vars :: [VarDecl],
        exports :: [VarExport],
        prompts :: [Prompt],
        steps :: [Step],
        commands :: [Command],
        dependencies :: [Dependency],
        removal :: Maybe Removal,
        migrations :: [Migration]
      }

`seihou-core/src/Seihou/Core/Types.hs:260` defines `Recipe`:

    data Recipe = Recipe
      { name :: RecipeName,
        version :: Maybe Text,
        description :: Maybe Text,
        modules :: [Dependency],
        vars :: [VarDecl],
        prompts :: [Prompt]
      }

`seihou-core/src/Seihou/Core/Types.hs:271` defines the unified result of
discovery:

    data Runnable
      = RunnableModule Module FilePath
      | RunnableRecipe Recipe FilePath
      deriving stock (Show)

The `FilePath` is the directory containing the corresponding `*.dhall`.
This plan extends `Runnable` with a `RunnableBlueprint Blueprint FilePath`
constructor (M1).

`seihou-core/src/Seihou/Core/Module.hs:343` defines the enumeration tag:

    data RunnableKind = KindModule | KindRecipe
      deriving stock (Eq, Show, Generic)

This plan extends it with `KindBlueprint`. Two existing consumers
case-split on `RunnableKind` and will need to grow a third branch:
`seihou-cli/src/Seihou/CLI/List.hs:90` (the `seihou list` formatter) and
`seihou-cli/src/Seihou/Fzf/Selector/Module.hs:41` (the fzf module
picker). Both today produce `""` for `KindModule` and `" [recipe]"` for
`KindRecipe`; this plan adds `" [blueprint]"` for `KindBlueprint`.

### Discovery: how `seihou run` finds a runnable today

`seihou-core/src/Seihou/Core/Module.hs:60` defines `discoverRunnable`:

    discoverRunnable :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError Runnable)
    discoverRunnable searchPaths name = go searchPaths
      where
        nameStr = T.unpack name.unModuleName
        go [] = pure $ Left (ModuleNotFound name searchPaths)
        go (dir : rest) = do
          let candidate = dir </> nameStr
          let moduleDhall = candidate </> "module.dhall"
          let recipeDhall = candidate </> "recipe.dhall"
          isModule <- doesFileExist moduleDhall
          if isModule
            then ... evalModuleFromFile moduleDhall ...
            else do
              isRecipe <- doesFileExist recipeDhall
              if isRecipe
                then ... evalRecipeFromFile recipeDhall ...
                else go rest

This plan extends the inner `if/else` chain with a third case for
`blueprint.dhall`, lower priority than module/recipe within a single
candidate directory.

`seihou-core/src/Seihou/Core/Module.hs:360` defines `discoverAllRunnables`,
which enumerates every candidate sub-directory in every search path and
classifies each. The plan extends `loadRunnable`'s inner if-cascade
symmetrically.

### Decoders: the Dhall layer

`seihou-core/src/Seihou/Dhall/Eval.hs` exposes per-type decoders. The two
existing top-level entry points are `evalModuleFromFile` (line 78) and
`evalRecipeFromFile` (line 107). Both follow the same shape: read the
file, run `inputExprWithSettings` to parse and normalize, extract with
the type's `Decoder`, force lazy thunks (because the `Dhall.Decoder`
machinery is `Functor`-only and uses `error` for unknown enum strings),
and return `Either ModuleLoadError <T>`. The blueprint's decoder uses
the same pattern.

The existing `recipeDecoder` (line 232) is the closer model because the
`Recipe` record is the smaller of the two and shares more fields with
`Blueprint`:

    recipeDecoder :: Decoder Recipe
    recipeDecoder =
      record
        ( Recipe
            <$> field "name" recipeNameDecoder
            <*> field "version" (maybe strictText)
            <*> field "description" (maybe strictText)
            <*> field "modules" (list dependencyDecoder)
            <*> field "vars" (list varDeclDecoder)
            <*> field "prompts" (list promptDecoder)
        )

The blueprint decoder reuses `dependencyDecoder` (for `baseModules`),
`varDeclDecoder` (for `vars`), `promptDecoder` (for `prompts`), and
`strictText` / `maybe strictText` / `list strictText` for the
remaining fields. The only new helper is `blueprintFileDecoder`, a
two-field record decoder.

### Schema: the Dhall side

`schema/Module.dhall` is the canonical example of a top-level Type/default
schema record (read at lines 1-55 of that file). `schema/Recipe.dhall` is
the simpler companion. `schema/package.dhall` re-exports each per-type
file under a name a blueprint author would write as
`let S = ./package.dhall in S.Blueprint::{ ... }`.

The schema is also published as a separate git repository at
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/` (mirror of
`https://raw.githubusercontent.com/shinzui/seihou-schema/`). The pinned
URL/hash that `seihou`-generated modules import lives in
`seihou-cli/src/Seihou/CLI/SchemaVersion.hs`:

    schemaUrl :: Text
    schemaUrl = "https://raw.githubusercontent.com/shinzui/seihou-schema/b83079d377f22c77292ad5ccf88d1061a58f0c1c/package.dhall"

    schemaHash :: Text
    schemaHash = "sha256:1d46697ed3e7ca1b0d9922020e2da034ae6e33f7b482ee454c68d94b536e8c2a"

M5 of this plan bumps both constants to point at a new commit in the
`seihou-schema` repo that contains `Blueprint.dhall` and the updated
`package.dhall`.

### Validation: the existing model

`seihou-core/src/Seihou/Core/Module.hs:104` defines `validateModule`, which
runs nine rules and returns `Either ModuleLoadError Module`. Each rule
is its own pure function (`checkNameFormat`, `checkVersionPresent`,
`checkUniqueVars`, `checkPromptRefs`, `checkExportRefs`,
`checkDependencyNames`, `checkDependencyVarBindings`,
`checkSafeDestinations`, `checkDestVarRefs`, `checkCommandSafety`) plus
one IO rule (`checkFileExistence`) that walks the module's `files/`
subdirectory. The shared name-format predicate `isValidModuleName`
(line 132) is exported and re-used here.

`seihou-core/src/Seihou/Core/Recipe.hs` defines the smaller
`validateRecipe :: Recipe -> Either [Text] Recipe` (signature differs
because recipes have no on-disk `files/` to check). The blueprint
validator's signature matches `validateModule`'s (it does need IO for
the `files/` existence check):

    validateBlueprint :: FilePath -> Blueprint -> IO (Either ModuleLoadError Blueprint)

### The run-refusal site

`seihou-cli/src-exe/Seihou/CLI/Run.hs:95-110` is the recipe-detection block
at the top of `handleRun`. It already pattern-matches on the result of
`discoverRunnable`:

    runnableResult <- discoverRunnable searchPaths modName
    case runnableResult of
      Right (RunnableRecipe recipe _recipeDir) -> do
        ... expand to primary + additionals + overrides ...
      Right (RunnableModule _ _) ->
        pure (modName, additional, Map.empty, Nothing)
      Left _ ->
        -- Discovery failed — let loadComposition handle the error
        pure (modName, additional, Map.empty, Nothing)

After M1 lands, that `case` becomes non-exhaustive (the new
`RunnableBlueprint` constructor is unhandled). The build will fail under
`-Wincomplete-patterns`, which surfaces every other site that
pattern-matches on `Runnable` and forces M6's refusal branch to land
before the workspace builds. M6 supplies the `RunnableBlueprint` arm
that prints the documented message and exits non-zero.


## Plan of Work

The work decomposes into eight milestones M1-M8. Each is independently
buildable; after each milestone, `cabal build all` succeeds and the
existing test suite continues to pass. The order is "type → schema →
validator → discovery → schema bump → run refusal → tests → demo,"
which matches the dependency arrows: every later milestone consumes
something an earlier milestone defined.

### M1 — Domain types and the `Runnable` extension

After this milestone, `Blueprint`, `BlueprintFile`, `RunnableBlueprint`,
and `KindBlueprint` exist in `seihou-core` and the workspace builds with
no incomplete-pattern warnings. No behaviour visible to a user has
changed (no decoder, no validator, no discovery branch yet); the change
is purely structural.

In `seihou-core/src/Seihou/Core/Types.hs`, immediately after `Recipe`
(currently ending at line 268) add:

    -- | A reference to a file in a blueprint's @files/@ subdirectory.
    -- The runner mounts the blueprint's @files/@ directory into the
    -- agent's filesystem; @description@ is shown to the agent so it
    -- can pick the right reference for the user's request.
    data BlueprintFile = BlueprintFile
      { src :: FilePath,
        description :: Maybe Text
      }
      deriving stock (Eq, Show, Generic)

    -- | A blueprint: an agent-driven runnable artifact bundling a base
    -- prompt, optional baseline modules, and reference files.
    -- Blueprints are not directly executable — running @seihou run@ on
    -- a blueprint name refuses with an actionable message; the agent
    -- runner @seihou agent run@ (EP-31) consumes them instead.
    data Blueprint = Blueprint
      { name :: ModuleName,
        version :: Maybe Text,
        description :: Maybe Text,
        prompt :: Text,
        vars :: [VarDecl],
        prompts :: [Prompt],
        baseModules :: [Dependency],
        files :: [BlueprintFile],
        allowedTools :: Maybe [Text],
        tags :: [Text]
      }
      deriving stock (Eq, Show, Generic)

Extend the export list at the top of the module to include `Blueprint`
and `BlueprintFile`. Extend the `Runnable` ADT (line 271) with a third
constructor:

    data Runnable
      = RunnableModule Module FilePath
      | RunnableRecipe Recipe FilePath
      | RunnableBlueprint Blueprint FilePath
      deriving stock (Show)

In `seihou-core/src/Seihou/Core/Module.hs`, extend `RunnableKind`
(line 343):

    data RunnableKind = KindModule | KindRecipe | KindBlueprint
      deriving stock (Eq, Show, Generic)

Build with `cabal build all` from the repo root. Expect compiler errors
of the form "non-exhaustive patterns in case" at every site that
pattern-matches on `Runnable` or `RunnableKind`. The known sites are:

- `seihou-cli/src-exe/Seihou/CLI/Run.hs:95` — the recipe-detection
  block. Add a placeholder arm that calls `error "EP-29 M6 will fill
  this in"`; M6 replaces the placeholder with the real refusal logic.
  This stub is acceptable here because no test in the suite exercises
  the not-yet-extended branch and `cabal build` only requires
  exhaustiveness, not correct behaviour.
- `seihou-cli/src/Seihou/CLI/List.hs:90` — the `seihou list` row
  formatter. Add `KindBlueprint -> " [blueprint]"`.
- `seihou-cli/src/Seihou/Fzf/Selector/Module.hs:41` — the fzf module
  picker label. Add `KindBlueprint -> " [blueprint]"`.

After fixing the three sites, `cabal build all` succeeds again. Run
`cabal test all --enable-tests` to confirm no existing test regressed.

### M2 — Dhall schema and decoders

After this milestone, a `blueprint.dhall` file authored against the new
schema parses, evaluates, and decodes into a `Blueprint` value via
`Seihou.Dhall.Eval.evalBlueprintFromFile`. Validation does not exist
yet (M3); the value is structurally valid Dhall but may fail
`validateBlueprint`'s rules.

Create `schema/Blueprint.dhall`:

    -- | Seihou Blueprint Schema
    --
    -- A blueprint is a Dhall record describing an agent-driven runnable.
    -- Unlike a Module, a Blueprint produces non-deterministic output — its
    -- prompt and reference files guide an AI coding agent that ultimately
    -- decides what files are written. Blueprints cannot be directly run
    -- via `seihou run`; use `seihou agent run BLUEPRINT` instead (EP-31).
    --
    -- Required fields (no default): name, prompt
    -- Usage: let S = ./package.dhall in S.Blueprint::{ name = "payments-service", prompt = ./prompt.md as Text }

    let VarDecl = ./VarDecl.dhall

    let Prompt = ./Prompt.dhall

    let Dependency = ./Dependency.dhall

    let BlueprintFile =
          { Type = { src : Text, description : Optional Text }
          , default = { description = None Text }
          }

    in  { Type =
            { name : Text
            , version : Optional Text
            , description : Optional Text
            , prompt : Text
            , vars : List VarDecl.Type
            , prompts : List Prompt.Type
            , baseModules : List Dependency.Type
            , files : List BlueprintFile.Type
            , allowedTools : Optional (List Text)
            , tags : List Text
            }
        , default =
            { version = None Text
            , description = None Text
            , vars = [] : List VarDecl.Type
            , prompts = [] : List Prompt.Type
            , baseModules = [] : List Dependency.Type
            , files = [] : List BlueprintFile.Type
            , allowedTools = None (List Text)
            , tags = [] : List Text
            }
        , BlueprintFile = BlueprintFile
        }

Update `schema/package.dhall` to expose `Blueprint`:

    { VarDecl = ./VarDecl.dhall
    , VarExport = ./VarExport.dhall
    , Prompt = ./Prompt.dhall
    , Step = ./Step.dhall
    , Command = ./Command.dhall
    , Dependency = ./Dependency.dhall
    , RemovalStep = ./RemovalStep.dhall
    , Removal = ./Removal.dhall
    , MigrationOp = ./MigrationOp.dhall
    , Migration = ./Migration.dhall
    , Module = ./Module.dhall
    , Recipe = ./Recipe.dhall
    , Blueprint = ./Blueprint.dhall
    }

In `seihou-core/src/Seihou/Dhall/Eval.hs`, add the decoders. Place them
after `recipeDecoder` (currently line 232). Mirror the
`evalRecipeFromFile` shape, including the lazy-thunk forcing:

    -- | Decoder for a 'BlueprintFile' record.
    blueprintFileDecoder :: Decoder BlueprintFile
    blueprintFileDecoder =
      record
        ( BlueprintFile
            <$> field "src" string
            <*> field "description" (maybe strictText)
        )

    -- | Decoder for the top-level Blueprint type from Dhall.
    blueprintDecoder :: Decoder Blueprint
    blueprintDecoder =
      record
        ( Blueprint
            <$> field "name" moduleNameDecoder
            <*> field "version" (maybe strictText)
            <*> field "description" (maybe strictText)
            <*> field "prompt" strictText
            <*> field "vars" (list varDeclDecoder)
            <*> field "prompts" (list promptDecoder)
            <*> field "baseModules" (list dependencyDecoder)
            <*> field "files" (list blueprintFileDecoder)
            <*> field "allowedTools" (maybe (list strictText))
            <*> field "tags" (list strictText)
        )

    -- | Evaluate a @blueprint.dhall@ file and decode it into a 'Blueprint'.
    evalBlueprintFromFile :: FilePath -> IO (Either ModuleLoadError Blueprint)
    evalBlueprintFromFile path = do
      result <- try $ do
        text <- TIO.readFile path
        let settings =
              set rootDirectory (takeDirectory path) $
                set sourceName path defaultInputSettings
        expr <- inputExprWithSettings settings text
        case extract blueprintDecoder expr of
          Success b -> do
            mapM_ (\v -> evaluate v.type_) b.vars
            mapM_ (\p -> evaluate p.condition) b.prompts
            pure b
          Failure e -> throwIO e
      case result of
        Left (e :: SomeException) ->
          let nm = guessModuleName path
           in pure $ Left (DhallEvalError nm (T.pack (show e)))
        Right b -> pure (Right b)

Extend the module export list at the top of `Seihou.Dhall.Eval`:

    , evalBlueprintFromFile
    , blueprintDecoder
    , blueprintFileDecoder

Run `cabal build all` to confirm. No test changes yet; the validator
in M3 is what tests can exercise.

### M3 — `Seihou.Core.Blueprint.validateBlueprint`

After this milestone, a decoded `Blueprint` value can be validated
against nine rules and the result is `Right Blueprint` for valid input
or `Left (ValidationError name [Text])` for invalid input. The shape
mirrors `Seihou.Core.Module.validateModule`.

Create `seihou-core/src/Seihou/Core/Blueprint.hs`:

    module Seihou.Core.Blueprint
      ( validateBlueprint,
        checkBlueprintNameFormat,
        checkBlueprintVersionPresent,
        checkBlueprintPromptNonEmpty,
        checkBlueprintUniqueVars,
        checkBlueprintPromptRefs,
        checkBlueprintBaseModules,
        checkBlueprintFiles,
        checkBlueprintTags,
        checkBlueprintAllowedTools,
      )
    where

The validator runs each rule, accumulates errors, and returns `Right b`
or `Left (ValidationError b.name allErrors)`. The rules are:

1. **Name format** — `b.name.unModuleName` is non-empty and matches
   `[a-z][a-z0-9-]*`. Reuse `Seihou.Core.Module.isValidModuleName`.
   Error text: `"blueprint name must match [a-z][a-z0-9-]*, got: " <> n`.

2. **Version present** — if `b.version` is `Just v`, then `T.strip v`
   is non-empty. Mirrors `checkVersionPresent` in
   `Seihou.Core.Module`. Error text: `"blueprint version, if specified,
   must not be empty"`. (Unlike modules, blueprints may legitimately
   omit a version during early authoring; the rule only rejects
   `Just ""`.)

3. **Prompt non-empty** — `T.strip b.prompt` is non-empty. Error
   text: `"blueprint prompt must not be empty"`.

4. **Unique vars** — every `VarName` in `b.vars` is distinct. Mirror
   `checkUniqueVars`.

5. **Prompt refs declared** — every `Prompt` in `b.prompts` references
   a var declared in `b.vars`. Mirror `checkPromptRefs`.

6. **Base modules well-formed and resolvable** — implemented as an IO
   check because resolution requires reading the search paths. For each
   `dep` in `b.baseModules`:
   - `dep.depModule.unModuleName` matches `[a-z][a-z0-9-]*`.
   - `discoverRunnable defaultSearchPaths dep.depModule` returns
     `Right (RunnableModule _ _)` or `Right (RunnableRecipe _ _)`.
     A `Right (RunnableBlueprint _ _)` is rejected with
     `"baseModule '" <> n <> "' resolves to a blueprint; baseModules
     must be modules or recipes"`.
   - A `Left ModuleNotFound` is reported as
     `"baseModule '" <> n <> "' not found in any search path"`.
   - Var binding names match the same `[a-z][a-z0-9.-]*` pattern that
     `Seihou.Core.Recipe.checkVarBindingNames` enforces.

7. **Files exist** — for each `bf` in `b.files`, the file at
   `baseDir </> "files" </> bf.src` exists and is a regular file
   (use `System.Directory.doesFileExist`). Error text:
   `"blueprint file not found: " <> T.pack bf.src`. Mirror
   `Seihou.Core.Module.checkFileExistence`.

8. **Tags non-empty strings** — every `t` in `b.tags` satisfies
   `not (T.null (T.strip t))`. Error text: `"tag must not be empty"`.

9. **AllowedTools non-empty strings** — if `b.allowedTools` is `Just
   xs`, every entry in `xs` satisfies `not (T.null (T.strip t))`.
   Error text: `"allowedTools entry must not be empty"`.

Aggregate signature:

    validateBlueprint :: FilePath -> Blueprint -> IO (Either ModuleLoadError Blueprint)
    validateBlueprint baseDir b = do
      fileErrs <- checkBlueprintFiles baseDir b
      baseErrs <- checkBlueprintBaseModules b
      let pureErrs =
            checkBlueprintNameFormat b
              <> checkBlueprintVersionPresent b
              <> checkBlueprintPromptNonEmpty b
              <> checkBlueprintUniqueVars b
              <> checkBlueprintPromptRefs b
              <> checkBlueprintTags b
              <> checkBlueprintAllowedTools b
          allErrs = pureErrs <> fileErrs <> baseErrs
      pure $
        if null allErrs
          then Right b
          else Left (ValidationError b.name allErrs)

Run `cabal build all` to confirm. The validator is exercised by tests
in M7; M3 itself is just the implementation.

### M4 — Discovery extension

After this milestone, `discoverRunnable` and `discoverAllRunnables`
both recognise `blueprint.dhall`. A directory containing only
`blueprint.dhall` (no `module.dhall`, no `recipe.dhall`) returns
`Right (RunnableBlueprint b dir)` from `discoverRunnable`.

In `seihou-core/src/Seihou/Core/Module.hs`, edit `discoverRunnable`
(line 60) to extend its inner `if` cascade. The new structure:

    discoverRunnable searchPaths name = go searchPaths
      where
        nameStr = T.unpack name.unModuleName
        go [] = pure $ Left (ModuleNotFound name searchPaths)
        go (dir : rest) = do
          let candidate = dir </> nameStr
              moduleDhall = candidate </> "module.dhall"
              recipeDhall = candidate </> "recipe.dhall"
              blueprintDhall = candidate </> "blueprint.dhall"
          isModule <- doesFileExist moduleDhall
          if isModule
            then ... (unchanged) ...
            else do
              isRecipe <- doesFileExist recipeDhall
              if isRecipe
                then ... (unchanged) ...
                else do
                  isBlueprint <- doesFileExist blueprintDhall
                  if isBlueprint
                    then do
                      result <- evalBlueprintFromFile blueprintDhall
                      case result of
                        Left err -> pure (Left err)
                        Right b -> pure (Right (RunnableBlueprint b candidate))
                    else go rest

Add the import `import Seihou.Dhall.Eval (evalBlueprintFromFile, ...)`
to the top of `Seihou.Core.Module`.

Add a `discoverBlueprint` helper for symmetry with `discoverModule`:

    discoverBlueprint :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError FilePath)
    discoverBlueprint searchPaths name = go searchPaths
      where
        nameStr = T.unpack name.unModuleName
        go [] = pure $ Left (ModuleNotFound name searchPaths)
        go (dir : rest) = do
          let candidate = dir </> nameStr
          let dhallFile = candidate </> "blueprint.dhall"
          exists <- doesFileExist dhallFile
          if exists
            then pure (Right candidate)
            else go rest

Export it from the module.

Extend `discoverAllRunnables` (line 360). Inside its `loadRunnable`
helper, after the existing `isRecipe` branch, add a third branch:

              else do
                isBlueprint <- doesFileExist blueprintDhall
                if isBlueprint
                  then do
                    decoded <- evalBlueprintFromFile blueprintDhall
                    pure
                      [ case decoded of
                          Left err -> ... DiscoveredRunnable { drKind = KindBlueprint, drIsError = True, drError = Just (briefLoadError err), ... }
                          Right b -> ... DiscoveredRunnable { drName = b.name.unModuleName, drDescription = b.description, drKind = KindBlueprint, drIsError = False, drError = Nothing, ... }
                      ]
                  else pure []

Run `cabal build all`. The `case` on `Runnable` in
`seihou-cli/src-exe/Seihou/CLI/Run.hs:95` still has its M1 placeholder;
that gets replaced in M6.

### M5 — Schema repository bump

After this milestone, the `seihou-schema` git repository at
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/` contains a
new commit that includes `Blueprint.dhall` and an updated
`package.dhall`. The pinned URL/hash in
`seihou-cli/src/Seihou/CLI/SchemaVersion.hs` points at that commit, so
modules and blueprints generated by EP-30 (a future plan) import the
new schema by default.

This milestone assumes the implementer has push permission to
`github.com/shinzui/seihou-schema`. If push permission is unavailable,
the implementer should commit locally, ask the user to push, and only
proceed once the new commit is on `origin/main`.

Steps (run from the repo root unless noted):

    cp schema/Blueprint.dhall ../seihou-schema/Blueprint.dhall
    cp schema/package.dhall ../seihou-schema/package.dhall

    cd ../seihou-schema
    git add Blueprint.dhall package.dhall
    git commit -m "feat(blueprint): add Blueprint.dhall schema"
    git push origin main
    git rev-parse HEAD

Record the new commit SHA. From the schema repo root:

    nix-prefetch-url --type sha256 \
      "https://raw.githubusercontent.com/shinzui/seihou-schema/<NEW-SHA>/package.dhall"

If `nix-prefetch-url` is unavailable, run

    curl -sL "https://raw.githubusercontent.com/shinzui/seihou-schema/<NEW-SHA>/package.dhall" | sha256sum

and convert the hex digest to Dhall's `sha256:<hex>` form.

Back in the seihou repo, edit
`seihou-cli/src/Seihou/CLI/SchemaVersion.hs` to replace the two
constants:

    schemaUrl :: Text
    schemaUrl = "https://raw.githubusercontent.com/shinzui/seihou-schema/<NEW-SHA>/package.dhall"

    schemaHash :: Text
    schemaHash = "sha256:<NEW-HEX>"

`mori.dhall` at the seihou repo root pins `mori-schema`, not
`seihou-schema`; do not edit it. (Confirmed by reading the file at the
top of this plan.)

Run `cabal build all` to confirm; no Haskell-source changes are needed
beyond the constant bumps. The bump is required so EP-30's
`seihou new-blueprint` scaffold imports a schema that actually contains
`Blueprint.dhall`; without this milestone, every authored blueprint
would refer to a schema URL that 404s.

### M6 — `seihou run` refusal branch

After this milestone, running `seihou run NAME` against a blueprint
prints the documented error message and exits non-zero. The existing
recipe-detection block at
`seihou-cli/src-exe/Seihou/CLI/Run.hs:95-110` grows a third arm.

Replace the M1 placeholder with the real refusal:

      Right (RunnableBlueprint b _blueprintDir) -> do
        logIO level $ do
          logError $ "'" <> b.name.unModuleName <> "' is a blueprint, not a module or recipe."
          logError "Blueprints must be run interactively via:"
          logError $ "  seihou agent run " <> b.name.unModuleName
        exitFailure

The `logError` helper from `Seihou.Effect.Logger` prefixes each line
with a red `Error:` label when colour is enabled; the message body must
not duplicate the `Error:` prefix. Inspect the existing call sites in
`Run.hs` (e.g. `logError "Errors compiling plan:"` at line 188) to
confirm the pattern. The exact stderr surface a user observes is:

    Error: 'my-blueprint' is a blueprint, not a module or recipe.
    Error: Blueprints must be run interactively via:
    Error:   seihou agent run my-blueprint

If integration testing reveals the doubled `Error:` prefix is jarring,
the alternative is a single multi-line `logError` call. Choose whichever
matches the existing recipe-validation refusal style; if no precedent
exists, prefer the multi-line single call. Record the chosen form in
Decision Log.

Run `cabal build all` to confirm the placeholder is gone. M7 supplies
the integration test that exercises this branch.

### M7 — Tests and fixture

After this milestone, the test suite covers every validation rule
(positive and negative) and the run-refusal branch. The seihou-core
fixtures are deterministic Dhall+files trees; the seihou-cli
integration test uses `withSystemTempDirectory` to set up a search
path containing a sample blueprint, then invokes the run handler.

#### Fixture: `seihou-core/test/fixtures/sample-blueprint/`

Create the directory and three files:

`seihou-core/test/fixtures/sample-blueprint/blueprint.dhall`:

    { name = "sample-blueprint"
    , version = Some "0.1.0"
    , description = Some "Fixture blueprint for EP-29 tests"
    , prompt = "Scaffold a project for {{project.name}} using {{language}}."
    , vars =
      [ { name = "project.name"
        , type = "text"
        , default = None Text
        , description = Some "Project name"
        , required = True
        , validation = None Text
        }
      , { name = "language"
        , type = "text"
        , default = Some "haskell"
        , description = None Text
        , required = False
        , validation = None Text
        }
      ]
    , prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
    , baseModules = [] : List { module : Text, vars : List { name : Text, value : Text } }
    , files =
      [ { src = "example.md", description = Some "Example reference snippet" }
      ]
    , allowedTools = None (List Text)
    , tags = [ "demo" ]
    }

`seihou-core/test/fixtures/sample-blueprint/files/example.md`:

    # Example
    A reference snippet the agent can copy.

Optionally add a parallel
`seihou-core/test/fixtures/invalid-blueprint/blueprint.dhall` mirroring
the structure of `seihou-core/test/fixtures/invalid-module/module.dhall`:
declare a `Bad_Name`, an empty prompt, duplicate vars, an undeclared
prompt-ref, an empty tag, and a missing `files/` source. Each rule
should be triggered by exactly one defect so the spec can assert on
the precise error list.

#### Spec: `seihou-core/test/Seihou/Core/BlueprintSpec.hs`

Mirror the shape of `seihou-core/test/Seihou/Core/RecipeSpec.hs`
(present in the directory listing). The spec exercises:

1. `evalBlueprintFromFile` on the sample fixture returns
   `Right blueprint` and the decoded fields match the fixture.
2. `validateBlueprint baseDir blueprint` on the sample returns
   `Right blueprint`.
3. `validateBlueprint` on the invalid fixture returns
   `Left (ValidationError "Bad_Name" errs)` with `length errs >= 6`
   and at least one error per rule (1, 3, 4, 5, 7, 8).
4. A blueprint whose `baseModules` contain a name that does not
   resolve in the test search paths produces an error containing
   `"baseModule '...' not found"`.
5. A blueprint whose `baseModules` contain another blueprint
   (constructed by writing a second `blueprint.dhall` into the test
   search path) produces the documented refusal error
   `"baseModule '...' resolves to a blueprint"`.

Register the spec in `seihou-core/test/Main.hs` alongside
`ModuleSpec`/`RecipeSpec`:

    import Seihou.Core.BlueprintSpec qualified as BlueprintSpec
    ...
    blueprintTests <- BlueprintSpec.tests
    ...
    [ ..., moduleTests, recipeTests, blueprintTests, ... ]

Add the new module to `seihou-core/seihou-core.cabal`'s
`test-suite seihou-core-test` `other-modules`:

    Seihou.Core.BlueprintSpec

#### CLI integration test for the run refusal

Create `seihou-cli/test/Seihou/CLI/RunBlueprintRefusalSpec.hs`. The
existing CLI specs use `withSystemTempDirectory` to set up a working
directory and then invoke a handler directly (see, e.g.,
`seihou-cli/test/Seihou/CLI/InitSpec.hs` for the pattern). The spec:

1. Creates a temp directory, places a minimal valid `blueprint.dhall`
   under `<tmp>/.seihou/modules/refused-blueprint/blueprint.dhall`
   (with a one-byte prompt), and a matching `files/` directory.
2. `cd`s into the temp directory and invokes `handleRun` with
   `runOpts.runModule = Just "refused-blueprint"` inside a
   `try` that catches `ExitCode`.
3. Asserts the captured `ExitCode` is `ExitFailure 1` and that the
   stderr buffer (captured via `hCapture` from `Test.Hspec.Capture`,
   matching the `StatusSpec` style at
   `seihou-cli/test/Seihou/CLI/StatusSpec.hs:251`) contains the substring
   `"is a blueprint, not a module or recipe"` and the substring
   `"seihou agent run refused-blueprint"`.

Register the spec in `seihou-cli/test/Main.hs` and
`seihou-cli/seihou-cli.cabal`'s `test-suite seihou-cli-test`
`other-modules` list, mirroring how `MigrateSpec` and `StatusSpec`
are registered.

Run `cabal test all --enable-tests --test-show-details=direct` and
confirm the new specs pass alongside the existing ones.

### M8 — Build, lint, and demo

After this milestone, the contributor has personally observed the
refusal message and confirmed `nix flake check` is clean.

Commands, run from the repo root:

    cabal build all
    cabal test all --enable-tests --test-show-details=direct
    nix flake check

The `nix/check-cli-module-placement.sh` invocation inside `nix flake
check` will accept the new `Seihou.Core.Blueprint` module trivially
(it lives under `seihou-core/src/`, not `seihou-cli`), and it will
accept the unchanged module placement of `Run.hs` (already in
`src-exe/`).

Manual end-to-end demo:

    mkdir -p ~/.config/seihou/modules/demo-blueprint/files
    cp seihou-core/test/fixtures/sample-blueprint/blueprint.dhall ~/.config/seihou/modules/demo-blueprint/
    cp seihou-core/test/fixtures/sample-blueprint/files/example.md ~/.config/seihou/modules/demo-blueprint/files/
    cd /tmp
    mkdir demo-target && cd demo-target
    cabal run -v0 -- seihou run demo-blueprint
    echo "exit code was: $?"

Expected stderr text (subject to logger formatting):

    Error: 'demo-blueprint' is a blueprint, not a module or recipe.
    Error: Blueprints must be run interactively via:
    Error:   seihou agent run demo-blueprint

Expected exit code: 1.

If the observed output differs (for example, the logger collapses the
three lines into one), update Surprises & Discoveries with the actual
text and consider whether the message should be reformatted. The
acceptance criterion below is "the message identifies the artifact as
a blueprint, names the correct alternate command, and the exit code is
non-zero" — the exact line breaks are not load-bearing.


## Concrete Steps

The commands below are run from the repo root unless noted. Each step
is idempotent: re-running has no destructive effect.

### Build and test

    cabal build all
    cabal test all --enable-tests --test-show-details=direct

After M2, both invocations succeed with the new decoders compiling.
After M3, the validator compiles. After M4, discovery compiles. After
M6, the CLI executable links again (the M1 placeholder is gone). After
M7, the new specs pass.

### Format and lint

    just fmt
    just check

The `Justfile` at the repo root wraps formatting (ormolu) and
`nix flake check`. The latter runs
`nix/check-cli-module-placement.sh`, which only fails if a `seihou-cli`
module accidentally lands in the wrong target. None of this plan's
work touches the `seihou-cli` library/executable boundary except M1's
list-formatter and fzf-selector edits and M6's `Run.hs` edit, all of
which respect the existing placement.

### Schema bump (M5)

See M5 in Plan of Work for the full sequence. The two essential
commands are:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema
    git push origin main

and (back in the seihou repo)

    $EDITOR seihou-cli/src/Seihou/CLI/SchemaVersion.hs

### Demo (M8)

See M8 above for the full recipe.


## Validation and Acceptance

Acceptance is observable behaviour, not "the code compiles":

1. **`evalBlueprintFromFile` on the sample fixture round-trips.** The
   M7 spec's first case asserts the decoded `Blueprint` matches the
   fixture's fields verbatim.
2. **`validateBlueprint` on the sample fixture returns `Right`.** M7
   case 2.
3. **`validateBlueprint` on the invalid fixture surfaces every rule
   violation.** M7 case 3 asserts `length errs >= 6`.
4. **`discoverRunnable` finds a blueprint.** A unit-level test in M7
   (added to `BlueprintSpec`) constructs a temp search path
   containing only `<tmp>/<name>/blueprint.dhall` and asserts
   `discoverRunnable [tmp] (ModuleName "<name>")` returns
   `Right (RunnableBlueprint b _)`.
5. **`discoverRunnable` prefers `module.dhall` over `blueprint.dhall`
   in the same directory.** A second test case writes both files in
   the same directory and asserts the result is `RunnableModule`,
   confirming the search-order decision.
6. **`seihou run BLUEPRINT` refuses with the documented message and
   exit code 1.** The CLI integration spec from M7 plus the M8
   manual demo together demonstrate this.
7. **`nix flake check` is clean** including the
   `nix/check-cli-module-placement.sh` invocation.

A failure of any of (1)–(7) is a regression and must be addressed
before the plan is marked complete.


## Idempotence and Recovery

Every step in the plan is additive. New types are introduced; existing
types are extended (only the ADT-extension milestone M1 is potentially
disruptive, and only for code that pattern-matches on `Runnable` /
`RunnableKind`). No on-disk format change occurs in `seihou-core`'s
manifest (that is EP-32's surface).

The schema bump (M5) is the only step with side effects on a remote
system (a `git push` to the `seihou-schema` repo). If the push fails or
needs to be reverted, the recovery procedure is:

1. Revert the URL/hash bump in
   `seihou-cli/src/Seihou/CLI/SchemaVersion.hs` to the previous values.
2. Either `git revert` the bad commit in the schema repo and force-push
   the previous tip, or push a new commit that removes
   `Blueprint.dhall` from `package.dhall`. The previous URL remains
   valid (immutable raw-content URLs in GitHub), so reverting the
   constants suffices to restore the old behaviour without coordinating
   with the schema repo.

If `cabal build` fails after M1 with non-exhaustive-pattern errors
beyond the three documented sites (`Run.hs`, `List.hs`,
`Module.hs` selector), search for additional pattern matches with

    rg "RunnableModule|RunnableRecipe|KindModule|KindRecipe" seihou-core seihou-cli

and add the missing arm. The codebase enables `-Wincomplete-patterns`
as part of its standard GHC options (see `cabal.project` and the
shared `ghc-options` in each `.cabal` file), so the compiler is the
authoritative source of truth.

If `cabal test` fails because the spec module is not picked up, the
most likely cause is forgetting to register it in **both**
`seihou-{core,cli}.cabal`'s `other-modules` and the corresponding
`test/Main.hs` entry list.


## Interfaces and Dependencies

This plan adds no new third-party dependencies. Every required import
is already available transitively through `seihou-core`.

After the work is complete, the following symbols and signatures must
exist (these match Integration Point #1, #2, #3, and #4 of the
masterplan exactly):

In `seihou-core/src/Seihou/Core/Types.hs`:

    data BlueprintFile = BlueprintFile
      { src :: FilePath,
        description :: Maybe Text
      }
      deriving stock (Eq, Show, Generic)

    data Blueprint = Blueprint
      { name :: ModuleName,
        version :: Maybe Text,
        description :: Maybe Text,
        prompt :: Text,
        vars :: [VarDecl],
        prompts :: [Prompt],
        baseModules :: [Dependency],
        files :: [BlueprintFile],
        allowedTools :: Maybe [Text],
        tags :: [Text]
      }
      deriving stock (Eq, Show, Generic)

    data Runnable
      = RunnableModule Module FilePath
      | RunnableRecipe Recipe FilePath
      | RunnableBlueprint Blueprint FilePath
      deriving stock (Show)

In `seihou-core/src/Seihou/Core/Module.hs`:

    data RunnableKind = KindModule | KindRecipe | KindBlueprint
      deriving stock (Eq, Show, Generic)

    discoverBlueprint :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError FilePath)

In `seihou-core/src/Seihou/Dhall/Eval.hs`:

    evalBlueprintFromFile :: FilePath -> IO (Either ModuleLoadError Blueprint)
    blueprintDecoder :: Decoder Blueprint
    blueprintFileDecoder :: Decoder BlueprintFile

In `seihou-core/src/Seihou/Core/Blueprint.hs` (new file):

    validateBlueprint :: FilePath -> Blueprint -> IO (Either ModuleLoadError Blueprint)

The pure per-rule helpers `checkBlueprintNameFormat`,
`checkBlueprintVersionPresent`, `checkBlueprintPromptNonEmpty`,
`checkBlueprintUniqueVars`, `checkBlueprintPromptRefs`,
`checkBlueprintTags`, and `checkBlueprintAllowedTools` have signature
`Blueprint -> [Text]`. The IO helpers `checkBlueprintFiles` and
`checkBlueprintBaseModules` have signatures
`FilePath -> Blueprint -> IO [Text]` and `Blueprint -> IO [Text]`
respectively.

In `seihou-cli/src-exe/Seihou/CLI/Run.hs`, the `case runnableResult of`
block at lines 95-110 grows a `Right (RunnableBlueprint b _) -> ...`
arm that prints the documented refusal message and calls
`exitFailure` from `System.Exit` (already imported at line 65).

In `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`, the two `Text`
constants `schemaUrl` and `schemaHash` are bumped to point at the new
`seihou-schema` commit landed in M5. No new exports.

In `schema/`, the new file `Blueprint.dhall` and the updated
`package.dhall` are mirrored to
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/` and
committed there.
