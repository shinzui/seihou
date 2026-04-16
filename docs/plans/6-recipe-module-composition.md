# Add Recipe: Named Module Compositions

Intention: intention_01kpa7sf5ve7rasvfnkw4c8wy3

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Today, a user who wants to scaffold a Haskell library must either run `seihou run` for each module separately (`seihou run nix-flake`, then `seihou run cabal-ghc`), chain them with `-m` flags every time (`seihou run nix-flake -m cabal-ghc`), or create a "fake" module whose only purpose is to declare dependencies on the real modules. None of these are good: the first is tedious, the second is unmemorizable and not shareable, and the third pollutes the module namespace with glue modules that have no templates of their own.

After this change, a user can create a **recipe** — a named, reusable composition of modules with optional pre-configured variable bindings. Running `seihou run haskell-library` will automatically detect that `haskell-library` is a recipe, expand it into its constituent modules, and execute the entire composition in one pass through the existing pipeline.

Recipes are declared in Dhall as `recipe.dhall` files and live alongside modules in the same directories, sharing a unified namespace. They are first-class citizens: installable from Git repos, visible in `seihou list`, selectable via fzf, and tracked in the manifest.

The name "recipe" is thematically aligned with seihou (製法, "method of production / recipe") — modules are ingredients, recipes describe how to combine them.


## Progress

- [x] Milestone 1: Recipe schema in seihou-schema (Recipe.dhall, update package.dhall) (2026-04-15)
- [x] Milestone 1: Haskell types for Recipe in seihou-core (Types.hs) (2026-04-15)
- [x] Milestone 1: Dhall decoder for recipe files (Dhall/Eval.hs) (2026-04-15)
- [x] Milestone 1: Unit tests for recipe decoding (2026-04-15)
- [ ] Milestone 2: Runnable union type (Module or Recipe discovery)
- [ ] Milestone 2: Update discoverModule to discoverRunnable with recipe.dhall fallback
- [ ] Milestone 2: Recipe expansion into composition inputs
- [ ] Milestone 2: Unit tests for discovery and expansion
- [ ] Milestone 3: Wire recipe path through handleRun in CLI
- [ ] Milestone 3: Update fzf selector to show recipes with [recipe] tag
- [ ] Milestone 3: Update seihou list to show recipes
- [ ] Milestone 3: Integration test: recipe-based run end-to-end
- [ ] Milestone 4: Add `recipes` field to Registry type and Dhall decoder (with backwards-compatible default)
- [ ] Milestone 4: Extend registry validation to validate recipe entries and detect name collisions
- [ ] Milestone 4: Add SingleRecipe constructor to RepoContents discovery
- [ ] Milestone 4: Update seihou install to present and install recipe entries
- [ ] Milestone 4: Update seihou browse to show recipe entries from registries
- [ ] Milestone 4: Add seihou new-recipe scaffolding command
- [ ] Milestone 4: Recipe validation rules (validate-module extended or new validate-recipe)
- [ ] Milestone 5: Manifest records recipe provenance
- [ ] Milestone 5: seihou status shows recipe info
- [ ] Milestone 5: Recipe test fixtures and comprehensive test coverage


## Surprises & Discoveries

- Adding Recipe type with shared field names (prompts, modules, name, version, description) caused GHC ambiguous record update errors in existing tests (ModuleSpec.hs, ManifestTypesSpec.hs). With DuplicateRecordFields enabled, `someModule { prompts = ... }` becomes ambiguous when another type also has `prompts`. Fixed by adding explicit helper functions (withModulePrompts, withManifestModules) that construct the value positionally. Future milestones must be aware of this when touching record updates on types with shared field names.


## Decision Log

- Decision: Name the concept "Recipe"
  Rationale: Seihou (製法) literally means "recipe/method of production." The metaphor is precise: modules are ingredients, recipes describe how to combine them. The name is universally understood across skill levels, and has precedent in infrastructure tools (Chef recipes, Homebrew formulae).
  Date: 2026-04-15

- Decision: Co-locate recipes with modules, distinguished by filename
  Rationale: Recipes and modules share a unified namespace — `seihou run foo` auto-detects whether `foo` is a module or recipe. This eliminates the need for separate search paths, `--recipe` flags, or mental overhead about which kind of thing you are running. The filesystem distinguishes via `recipe.dhall` vs `module.dhall` in the same directory.
  Date: 2026-04-15

- Decision: Reuse the existing Dependency type for recipe module entries
  Rationale: A recipe's module list is structurally identical to a module's dependency list: a module name plus optional variable bindings. Reusing the type avoids duplication and means all existing variable binding, export, and composition infrastructure works without modification.
  Date: 2026-04-15

- Decision: Recipes reference modules only in v1 (no recipe-extends-recipe)
  Rationale: Allowing recipes to reference other recipes introduces flattening logic, variable shadowing rules, and potential cycles. For v1, recipes are flat lists of modules. If a user wants an "haskell-app" recipe that includes everything from "haskell-library," they list all modules explicitly. Recipe inheritance can be added later.
  Date: 2026-04-15

- Decision: The first module in a recipe becomes the "primary" module for namespace derivation
  Rationale: The existing `handleRun` uses the primary module name to derive a config namespace. In a recipe, the first listed module takes this role, consistent with how the user thinks about the primary ingredient in a composition.
  Date: 2026-04-15


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Seihou is a composable, type-safe project scaffolding system. Modules are the atomic units: each module is a directory containing a `module.dhall` file that declares variables, generation steps (Copy, Template, DhallText, Structured), dependencies on other modules, exports, prompts, and shell commands. The Dhall schemas that define module structure live in a separate repository at `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema` and are vendored into the seihou repo at `schema/`.

The codebase is a multi-package Cabal workspace with two packages: `seihou-core` (library with domain types, effects, and engine) and `seihou-cli` (executable with CLI commands). Key source locations:

- `seihou-core/src/Seihou/Core/Types.hs` — Core domain types: `Module`, `ModuleName`, `Dependency`, `VarDecl`, `Step`, `Operation`, `Manifest`, `AppliedModule`, `FileRecord`
- `seihou-core/src/Seihou/Core/Module.hs` — Module discovery (`discoverModule`) and validation (`validateModule`), search path logic
- `seihou-core/src/Seihou/Dhall/Eval.hs` — Dhall-to-Haskell decoders: `evalModuleFromFile`, dependency decoder, schema evolution via `withDefaults`
- `seihou-core/src/Seihou/Composition/Resolve.hs` — `loadComposition` (load primary + additional + transitive deps, topo-sort), `resolveWithPrompts` (variable resolution with interactive prompts)
- `seihou-core/src/Seihou/Composition/Graph.hs` — `buildGraph`, `topoSort` (Kahn's algorithm)
- `seihou-core/src/Seihou/Composition/Plan.hs` — `compileComposedPlan` (merge operations from all modules)
- `seihou-core/src/Seihou/Core/Registry.hs` — `Registry`, `RegistryEntry`, `discoverRepoContents`, `validateRegistry`
- `seihou-cli/src/Seihou/CLI/Commands.hs` — CLI command ADT, `RunOpts`, optparse-applicative parsers
- `seihou-cli/src/Seihou/CLI/Run.hs` — `handleRun` (full run pipeline: load → resolve → compile → diff → execute → manifest)
- `seihou-cli/src/Seihou/CLI/Install.hs` — Module installation from Git repos
- `seihou-cli/src/Seihou/CLI/List.hs` — Module listing
- `seihou-cli/src/Main.hs` — Command dispatch
- `seihou-cli/src/Seihou/Fzf/Selector.hs` — fzf-based interactive module selection

Module discovery searches three directories in priority order: `.seihou/modules/` (project-local), `~/.config/seihou/modules/` (user-global), and `~/.config/seihou/installed/` (installed from repos). Each module is a subdirectory named after the module, containing `module.dhall` and optionally a `files/` directory with templates.

The composition system already handles multi-module runs. The `loadComposition` function in `Resolve.hs` takes a primary module name and a list of additional module names, loads them all, resolves transitive dependencies, topologically sorts them, and returns them in execution order. The `handleRun` function in `Run.hs` already supports `-m` flags for additional modules. A recipe is a declarative encoding of what these CLI flags do: naming a specific combination of modules with optional variable pre-bindings.

The Dhall schema repository (`seihou-schema/`) contains: `Module.dhall`, `Step.dhall`, `VarDecl.dhall`, `VarExport.dhall`, `Prompt.dhall`, `Command.dhall`, `Dependency.dhall`, `Removal.dhall`, `RemovalStep.dhall`, and `package.dhall`. Schemas use Dhall record completion (`Type`/`default`) so that module authors can write `S.Module::{ name = "foo", ... }` and get defaults for all optional fields. The vendored copy in `schema/` mirrors seihou-schema exactly.


## Plan of Work

The implementation proceeds in five milestones. Each milestone produces working, testable code. The design principle is to make the recipe a thin declarative layer that feeds into the existing composition pipeline — there is no separate "recipe execution engine." A recipe is expanded into a primary module, additional modules, and variable overrides, then the existing `loadComposition` / `resolveWithPrompts` / `compileComposedPlan` pipeline handles everything.


### Milestone 1: Schema, Types, and Dhall Decoder

This milestone establishes the recipe as a first-class Dhall schema type and adds the Haskell data types and decoder to parse it. At the end of this milestone, recipe Dhall files can be evaluated into typed Haskell values.

#### 1a. Add Recipe.dhall to seihou-schema

Create a new file `Recipe.dhall` in the seihou-schema repository at `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/Recipe.dhall`. The recipe schema reuses the existing `Dependency.dhall` type for its module list, and reuses `VarDecl.dhall` and `Prompt.dhall` for recipe-level variable declarations and prompts.

The schema definition:

    -- Recipe.dhall
    let Dependency = ./Dependency.dhall
    let VarDecl = ./VarDecl.dhall
    let Prompt = ./Prompt.dhall

    in  { Type =
            { name : Text
            , version : Optional Text
            , description : Optional Text
            , modules : List Dependency.Type
            , vars : List VarDecl.Type
            , prompts : List Prompt.Type
            }
        , default =
            { version = None Text
            , description = None Text
            , vars = [] : List VarDecl.Type
            , prompts = [] : List Prompt.Type
            }
        }

The `name` and `modules` fields have no defaults — they are required. A recipe must have a name and at least one module.

Update `package.dhall` in seihou-schema to export the new type:

    { VarDecl = ./VarDecl.dhall
    , VarExport = ./VarExport.dhall
    , Prompt = ./Prompt.dhall
    , Step = ./Step.dhall
    , Command = ./Command.dhall
    , Dependency = ./Dependency.dhall
    , RemovalStep = ./RemovalStep.dhall
    , Removal = ./Removal.dhall
    , Module = ./Module.dhall
    , Recipe = ./Recipe.dhall
    }

Then vendor the updated schema into the seihou repo: copy `Recipe.dhall` to `schema/Recipe.dhall` and update `schema/package.dhall` to include the `Recipe` entry.

#### 1b. Add Haskell types for Recipe

In `seihou-core/src/Seihou/Core/Types.hs`, add:

    newtype RecipeName = RecipeName {unRecipeName :: Text}
      deriving stock (Eq, Ord, Show, Generic)
      deriving newtype (IsString, Hashable)

    data Recipe = Recipe
      { name :: RecipeName,
        version :: Maybe Text,
        description :: Maybe Text,
        modules :: [Dependency],
        vars :: [VarDecl],
        prompts :: [Prompt]
      }
      deriving stock (Eq, Show, Generic)

Add `RecipeName` and `Recipe` to the module exports.

Since recipes share the same namespace as modules, `RecipeName` follows the same `[a-z][a-z0-9-]*` format as `ModuleName`. We could even reuse `ModuleName` for recipe names (since they share a namespace), but a distinct newtype makes the code self-documenting. A helper `recipeNameToModuleName` converts between them:

    recipeNameToModuleName :: RecipeName -> ModuleName
    recipeNameToModuleName (RecipeName t) = ModuleName t

Also add a `Runnable` type that represents the result of name-based discovery:

    data Runnable
      = RunnableModule Module FilePath
      | RunnableRecipe Recipe FilePath
      deriving stock (Show)

This type is used by the discovery system to communicate what was found at a given name.

#### 1c. Add Dhall decoder for recipes

In `seihou-core/src/Seihou/Dhall/Eval.hs`, add `evalRecipeFromFile` alongside the existing `evalModuleFromFile`. The recipe decoder is simpler than the module decoder because recipes have fewer fields.

    evalRecipeFromFile :: FilePath -> IO (Either ModuleLoadError Recipe)

The decoder needs to handle the same fields as the schema: `name` (Text), `version` (Optional Text), `description` (Optional Text), `modules` (List Dependency), `vars` (List VarDecl), `prompts` (List Prompt). The `modules` field reuses `dependencyDecoder` which already supports both bare-string and parameterized dependency forms. The `vars` field reuses `varDeclDecoder`. The `prompts` field reuses `promptDecoder`. Apply the same `withDefaults` mechanism for schema evolution.

#### 1d. Add test fixture and unit test

Create a test fixture recipe at `seihou-core/test/fixtures/haskell-with-nix-recipe/recipe.dhall`:

    { name = "haskell-with-nix"
    , version = Some "1.0.0"
    , description = Some "Haskell project with Nix integration"
    , modules =
      [ { module = "haskell-base", vars = [] : List { name : Text, value : Text } }
      , { module = "nix-flake", vars = [] : List { name : Text, value : Text } }
      ]
    , vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }
    , prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
    }

Also create a fixture with variable bindings at `seihou-core/test/fixtures/haskell-pinned-recipe/recipe.dhall`:

    { name = "haskell-pinned"
    , version = Some "1.0.0"
    , description = Some "Haskell with pinned nix system"
    , modules =
      [ { module = "haskell-base", vars = [] : List { name : Text, value : Text } }
      , { module = "nix-flake", vars = [ { name = "nix.system", value = "aarch64-darwin" } ] }
      ]
    , vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }
    , prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
    }

Add a unit test in the existing test suite that calls `evalRecipeFromFile` on both fixtures and verifies the parsed Recipe values match expected fields.

**Verification:** Build with `cabal build all` from the repo root. Run `cabal test seihou-core-test` and confirm the new recipe decoding tests pass. Expected output: all tests pass, including the new recipe decoder tests.


### Milestone 2: Discovery and Recipe Expansion

This milestone makes the system able to find recipes in the module search paths and expand them into the inputs that the existing composition pipeline expects. At the end, the core library can discover a recipe by name and produce the primary module name, additional module names, and variable overrides that `loadComposition` needs.

#### 2a. Extend discovery to find recipes

In `seihou-core/src/Seihou/Core/Module.hs`, the existing `discoverModule` function searches the three standard paths for `<name>/module.dhall`. Add a new function `discoverRunnable` that checks both `module.dhall` and `recipe.dhall`:

    discoverRunnable ::
      [FilePath] ->
      ModuleName ->
      IO (Either ModuleLoadError Runnable)

For each search path, check in order:
1. `<path>/<name>/module.dhall` exists → load as module → `RunnableModule`
2. `<path>/<name>/recipe.dhall` exists → load as recipe → `RunnableRecipe`
3. Neither → continue to next search path

If no search path yields a result, return `ModuleNotFound` (reusing the existing error type).

Keep the existing `discoverModule` function unchanged — it is still used internally by `loadComposition` when loading dependency modules (dependencies are always modules, not recipes).

#### 2b. Recipe expansion function

In a new file `seihou-core/src/Seihou/Composition/Recipe.hs`, create:

    module Seihou.Composition.Recipe
      ( expandRecipe,
      )
    where

    expandRecipe :: Recipe -> (ModuleName, [ModuleName], Map VarName Text, [VarDecl], [Prompt])

This function takes a `Recipe` and produces five values:
1. The primary module name — the first module in the recipe's `modules` list
2. The additional module names — all remaining modules in the list
3. Variable overrides — collected from all module entries' `vars` bindings, suitable for merging into CLI overrides
4. Recipe-level variable declarations — the recipe's own `vars` field
5. Recipe-level prompts — the recipe's own `prompts` field

The variable overrides are assembled by iterating over each module entry's `depVars` map. Since these are pre-configured bindings (the recipe author's choices), they sit at the same precedence level as CLI `--var` overrides.

#### 2c. Validate recipe

Add recipe-specific validation in `seihou-core/src/Seihou/Core/Module.hs` (or a new `seihou-core/src/Seihou/Core/Recipe.hs`):

    validateRecipe :: Recipe -> Either [Text] Recipe

Validation rules:
1. Name matches `[a-z][a-z0-9-]*`
2. At least one module listed
3. No duplicate module names in the list
4. All variable binding names in module entries match `[a-z][a-z0-9.-]*` (the var name format)

Rules that require loading modules (like "referenced modules exist") are deferred to runtime when `loadComposition` runs — it already produces clear errors for missing modules.

#### 2d. Tests

Unit tests for `expandRecipe`:
- Simple recipe with two modules → correct primary and additional names
- Recipe with variable bindings → overrides map populated correctly
- Recipe with recipe-level vars and prompts → passed through

Unit tests for `validateRecipe`:
- Valid recipe passes
- Empty modules list fails
- Invalid name fails
- Duplicate module names fail

**Verification:** `cabal build all && cabal test seihou-core-test`. All tests pass including new recipe expansion and validation tests.


### Milestone 3: CLI Integration

This milestone wires recipes into the `seihou run` command, the fzf selector, and `seihou list`. At the end, a user can run `seihou run haskell-library` and have it transparently expand a recipe into a multi-module composition, or pick a recipe from the fzf menu.

#### 3a. Modify handleRun to support recipes

In `seihou-cli/src/Seihou/CLI/Run.hs`, the `handleRun` function currently resolves a module name and calls `loadComposition`. The change is to insert a recipe detection step between name resolution and composition loading.

After the module name is resolved (line 57-75 currently), add a step that calls `discoverRunnable`. If the result is `RunnableModule`, proceed exactly as before. If the result is `RunnableRecipe`, call `expandRecipe` to produce the primary module name, additional modules, and variable overrides, then merge those into the existing run options before calling `loadComposition`.

The merge rules:
- Recipe additional modules are appended to any `-m` flags from the CLI
- Recipe variable overrides are merged with CLI `--var` overrides (CLI wins on conflict)
- Recipe-level VarDecls need to be injected into variable resolution — the simplest approach is to create a synthetic module wrapper or to pass them through to the prompt system

For recipe-level vars and prompts, the cleanest approach is: after `loadComposition` returns the module list, prepend the recipe's VarDecls and Prompts to the first module's declarations. This way the existing variable resolution and prompt system handles them without modification. This is a pragmatic v1 approach — a future version could make recipe-level vars first-class in the resolution pipeline.

#### 3b. Update fzf selector

In `seihou-cli/src/Seihou/Fzf/Selector.hs`, the `selectModule` function scans module directories. Extend it to also scan for `recipe.dhall` files and include them in the fzf list. Recipes should be displayed with a `[recipe]` tag to distinguish them from modules. The output of fzf selection should indicate whether a module or recipe was selected.

#### 3c. Update seihou list

In `seihou-cli/src/Seihou/CLI/List.hs`, extend the listing to include recipes. Show them with a "recipe" type indicator. Add `--recipes` and `--modules` filter flags to let users narrow the list.

#### 3d. Integration test

Create an integration test that:
1. Sets up a temp directory with two modules (`mod-a` with `module.dhall` and `mod-b` with `module.dhall`) and a recipe (`combo` with `recipe.dhall` that lists both)
2. Runs the composition loading path with the recipe name
3. Verifies all modules are loaded in correct order
4. Verifies recipe variable overrides are applied

**Verification:** `cabal build all && cabal test all`. Run `seihou list` from the repo root and confirm recipes appear. Run `seihou run --dry-run <recipe-name>` with a test recipe and confirm the plan view shows all constituent modules.


### Milestone 4: Registry, Install, and Authoring

This milestone extends the module ecosystem infrastructure to handle recipes: installation from Git repos, registry support, and the `new-recipe` scaffolding command.

#### 4a. Extend Registry type and schema to include recipes

The `Registry` type in `seihou-core/src/Seihou/Core/Registry.hs` currently has only a `modules` field:

    data Registry = Registry
      { repoName :: Text,
        repoDescription :: Maybe Text,
        modules :: [RegistryEntry]
      }

Add a `recipes` field so the registry manifest can explicitly declare both modules and recipes:

    data Registry = Registry
      { repoName :: Text,
        repoDescription :: Maybe Text,
        modules :: [RegistryEntry],
        recipes :: [RegistryEntry]
      }

The same `RegistryEntry` type works for both — it carries a name, version, path, description, and tags. The difference is which Dhall file lives at the path (`module.dhall` vs `recipe.dhall`).

Update the Dhall decoder `registryDecoder` in `seihou-core/src/Seihou/Dhall/Eval.hs` (line 400) to read the new field. Use the `withDefaults` pattern so that existing `seihou-registry.dhall` files without a `recipes` field decode successfully (defaulting to an empty list):

    registryDecoder :: Decoder Registry
    registryDecoder =
      record
        ( Registry
            <$> field "repoName" strictText
            <*> field "repoDescription" (maybe strictText)
            <*> field "modules" (list registryEntryDecoder)
            <*> field "recipes" (list registryEntryDecoder)
        )

The `withDefaults` mechanism already used by `evalModuleFromFile` should inject `recipes = [] : List { ... }` when the field is absent in the source Dhall. Add a `registryDefaults` map alongside the existing `moduleDefaults` that injects this empty-list default for the `recipes` key.

Update the `seihou-registry.dhall` documentation and examples to show the new field. A multi-module repo that also offers recipes would declare:

    { repoName = "haskell-modules"
    , repoDescription = Some "Haskell scaffolding modules"
    , modules =
      [ { name = "haskell-base", version = Some "1.0.0", path = "modules/haskell-base"
        , description = Some "Base Haskell project", tags = ["haskell"] }
      , { name = "nix-flake", version = Some "1.0.0", path = "modules/nix-flake"
        , description = Some "Nix flake", tags = ["nix"] }
      ]
    , recipes =
      [ { name = "haskell-library", version = Some "1.0.0", path = "recipes/haskell-library"
        , description = Some "Haskell library with Nix + Cabal", tags = ["haskell", "nix"] }
      ]
    }

#### 4b. Registry validation for recipes

In `seihou-core/src/Seihou/Core/Registry.hs`, the `validateRegistry` function currently only validates `reg.modules`. Extend it to also validate `reg.recipes`:

    validateRegistry :: FilePath -> Registry -> IO [Text]
    validateRegistry repoRoot reg = do
      modErrs <- concat <$> mapM (validateModuleEntry repoRoot) reg.modules
      recErrs <- concat <$> mapM (validateRecipeEntry repoRoot) reg.recipes
      pure (modErrs <> recErrs)

The `validateModuleEntry` function (renamed from `validateEntry`) checks for `module.dhall` at the entry path, as before. The new `validateRecipeEntry` checks for `recipe.dhall` at the entry path. Both share the name-format and path-safety checks.

Also validate that no name appears in both `modules` and `recipes` — since they share a namespace, a collision would be ambiguous.

#### 4c. Install support for recipes

In `seihou-cli/src/Seihou/CLI/Install.hs`, the install handler calls `discoverRepoContents` and then iterates over registry modules. Extend this to also handle registry recipes. When a `MultiModule` registry is found, present both modules and recipes to the user for selection (with type labels in the interactive picker). The `--all` flag installs both modules and recipes.

When installing a recipe, copy the entire directory (with `recipe.dhall`) to `~/.config/seihou/installed/<name>/`, the same destination as modules. The recipe references modules by name — those modules must be separately installed or available in the search paths. After installing a recipe, check if all referenced modules are available and warn if any are missing:

    Warning: recipe 'haskell-library' references module 'cabal-ghc' which is not installed.
    Run 'seihou install <source> --module cabal-ghc' to install it.

For single-recipe repos (a repo root containing `recipe.dhall` instead of `module.dhall`), extend `discoverRepoContents` with a new constructor:

    data RepoContents
      = SingleModule FilePath
      | SingleRecipe FilePath
      | MultiModule Registry
      | EmptyRepo

The discovery order becomes: check for `seihou-registry.dhall` first (MultiModule), then `module.dhall` (SingleModule), then `recipe.dhall` (SingleRecipe), then EmptyRepo.

Update `seihou browse` to show recipe entries from registries with a `[recipe]` indicator.

#### 4c. Add seihou new-recipe command

Add a new CLI command `new-recipe` (parallel to the existing `new-module`). This command scaffolds a `recipe.dhall` file in the current directory. The command takes a name argument and optional module names:

    seihou new-recipe haskell-library --module nix-flake --module cabal-ghc

This creates `<name>/recipe.dhall` with the listed modules pre-populated.

In `seihou-cli/src/Seihou/CLI/Commands.hs`, add `NewRecipe NewRecipeOpts` to the `Command` type. Add the parser. In `Main.hs`, wire the new command to a handler in a new `seihou-cli/src/Seihou/CLI/NewRecipe.hs`.

#### 4d. Recipe validation command

Extend `seihou validate-module` to also detect and validate recipe files. When pointed at a directory containing `recipe.dhall`, apply the recipe validation rules from Milestone 2c. Alternatively, accept `seihou validate-module <name>` for both modules and recipes, since they share a namespace.

**Verification:** `cabal build all && cabal test all`. Install a recipe from a test repo with `seihou install`. Run `seihou new-recipe test-recipe --module mod-a --module mod-b` and verify the scaffolded file is valid Dhall. Run `seihou validate-module` on the scaffolded recipe.


### Milestone 5: Manifest Provenance and Polish

This milestone adds recipe tracking to the manifest, improves status output, and ensures comprehensive test coverage.

#### 5a. Manifest recipe tracking

In `seihou-core/src/Seihou/Core/Types.hs` (or `seihou-core/src/Seihou/Manifest/Types.hs`), extend the `Manifest` type with an optional `recipe` field:

    data Manifest = Manifest
      { version :: Int,
        genAt :: UTCTime,
        modules :: [AppliedModule],
        vars :: Map VarName Text,
        files :: Map FilePath FileRecord,
        recipe :: Maybe AppliedRecipe
      }

    data AppliedRecipe = AppliedRecipe
      { name :: RecipeName,
        recipeVersion :: Maybe Text,
        appliedAt :: UTCTime
      }

When a recipe is run, `handleRun` records the recipe info in the manifest. When a bare module is run, this field is `Nothing`. The JSON serialization must handle the new field with backwards compatibility (missing field defaults to `Nothing`).

#### 5b. Status output

In `seihou-cli/src/Seihou/CLI/Status.hs`, when a manifest has a `recipe` field, show it in the status output:

    Recipe: haskell-library v1.0.0
    Modules (3):
      nix-base v1.0.0 (dependency)
      nix-flake v1.0.0
      cabal-ghc v1.0.0

#### 5c. Comprehensive tests

Add test fixtures and tests covering:
- Recipe with variables passed to specific modules
- Recipe where modules have diamond dependencies (recipe lists A and B, both depend on C)
- Recipe where one module's exports feed another module's required variables
- Recipe with recipe-level prompts
- Manifest round-trip with recipe provenance
- Edge case: recipe with a single module (effectively an alias)
- Edge case: recipe references a nonexistent module (clear error message)

**Verification:** `cabal build all && cabal test all`. All tests pass. Run a real recipe end-to-end and verify the manifest contains recipe provenance.


## Concrete Steps

All commands should be run from the repository root `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` unless otherwise noted.

Building the project:

    cabal build all

Expected: compilation succeeds with no errors.

Running the core test suite:

    cabal test seihou-core-test

Expected: all tests pass.

Running all tests:

    cabal test all

Expected: all test suites pass.

Checking that a recipe fixture evaluates correctly (after Milestone 1):

    cabal repl seihou-core-test

Then in the REPL:

    > import Seihou.Dhall.Eval
    > evalRecipeFromFile "test/fixtures/haskell-with-nix-recipe/recipe.dhall"
    Right (Recipe {name = RecipeName "haskell-with-nix", ...})

Running a recipe in dry-run mode (after Milestone 3):

    seihou run --dry-run haskell-with-nix-recipe

Expected: plan view shows modules from the recipe, no files written.

These commands will be updated as implementation proceeds.


## Validation and Acceptance

**Milestone 1** is accepted when `evalRecipeFromFile` successfully parses both test fixtures and the unit tests pass. Verify by running `cabal test seihou-core-test` and checking for the recipe decoder test names in the output.

**Milestone 2** is accepted when `discoverRunnable` finds a recipe by name from a search path and `expandRecipe` produces the correct primary, additional, and override values. Verify by running the new unit tests.

**Milestone 3** is accepted when `seihou run --dry-run <recipe>` shows the composed plan from all recipe modules, and `seihou list` shows recipes with a type indicator. This is the most important acceptance point — a user must be able to type `seihou run haskell-library` and get a multi-module composition without any `-m` flags.

**Milestone 4** is accepted when `seihou install <repo-url>` can install recipes alongside modules, `seihou new-recipe` scaffolds a valid recipe file, and validation catches invalid recipes.

**Milestone 5** is accepted when running a recipe and then checking `seihou status` shows the recipe name and version alongside the applied modules, and all comprehensive tests pass.

The overall feature is accepted when a user can:
1. Author a `recipe.dhall` that composes multiple modules with pre-configured variables
2. Install that recipe from a Git repository
3. Run the recipe with `seihou run <recipe-name>`
4. See all modules applied in the correct order with variables resolved
5. See recipe provenance in `seihou status`


## Idempotence and Recovery

All milestones produce additive changes — no existing behavior is modified, only extended. The `discoverRunnable` function falls back to the existing `discoverModule` behavior when no recipe is found, so existing module-only workflows are unaffected.

The recipe schema is backwards-compatible: existing `module.dhall` files are untouched. The manifest format change (adding `recipe` field) is backwards-compatible: the JSON decoder treats a missing `recipe` field as `Nothing`. The registry format change (adding `recipes` field) is backwards-compatible: the Dhall decoder's `withDefaults` mechanism injects an empty list when the field is absent, so existing `seihou-registry.dhall` files continue to work without modification.

If a milestone is partially completed, the codebase remains in a working state because each milestone is independently testable. Recipe support can be reverted by removing the new files and reverting the small changes to existing files (discovery, CLI, registry).

Cabal builds are inherently repeatable. `cabal clean` followed by `cabal build all` rebuilds from scratch if needed.


## Interfaces and Dependencies

This feature uses only existing dependencies — no new libraries are required. The Dhall decoder machinery, effectful effects, optparse-applicative parsers, and aeson serialization are all in place.

### New Files

    seihou-schema/Recipe.dhall              — Recipe Dhall schema
    schema/Recipe.dhall                     — Vendored copy
    seihou-core/src/Seihou/Core/Recipe.hs   — Recipe validation
    seihou-core/src/Seihou/Composition/Recipe.hs — Recipe expansion
    seihou-cli/src/Seihou/CLI/NewRecipe.hs  — new-recipe command handler
    seihou-core/test/fixtures/haskell-with-nix-recipe/recipe.dhall    — Test fixture
    seihou-core/test/fixtures/haskell-pinned-recipe/recipe.dhall      — Test fixture

### Modified Files

    seihou-schema/package.dhall             — Add Recipe export
    schema/package.dhall                    — Add Recipe export (vendored)
    seihou-core/src/Seihou/Core/Types.hs    — Add RecipeName, Recipe, Runnable, AppliedRecipe types
    seihou-core/src/Seihou/Core/Module.hs   — Add discoverRunnable function
    seihou-core/src/Seihou/Dhall/Eval.hs    — Add evalRecipeFromFile decoder, add recipes field to registryDecoder with defaults
    seihou-core/src/Seihou/Core/Registry.hs — Add recipes field to Registry, split validation, name collision check
    seihou-core/src/Seihou/Manifest/Types.hs — Add recipe field to Manifest, AppliedRecipe JSON
    seihou-core/seihou-core.cabal           — Add new modules
    seihou-cli/src/Seihou/CLI/Commands.hs   — Add NewRecipe command, parser
    seihou-cli/src/Seihou/CLI/Run.hs        — Recipe detection in handleRun
    seihou-cli/src/Seihou/CLI/Install.hs    — Recipe entry handling, SingleRecipe discovery
    seihou-cli/src/Seihou/CLI/Browse.hs     — Show recipe entries from registries
    seihou-cli/src/Seihou/CLI/List.hs       — Recipe listing
    seihou-cli/src/Seihou/CLI/Status.hs     — Recipe provenance display
    seihou-cli/src/Seihou/Fzf/Selector.hs   — Recipe entries in fzf
    seihou-cli/src/Main.hs                  — Wire NewRecipe command
    seihou-cli/seihou-cli.cabal             — Add NewRecipe module

### Key Type Signatures

In `seihou-core/src/Seihou/Core/Types.hs`:

    newtype RecipeName = RecipeName {unRecipeName :: Text}
    data Recipe = Recipe
      { name :: RecipeName, version :: Maybe Text, description :: Maybe Text,
        modules :: [Dependency], vars :: [VarDecl], prompts :: [Prompt] }
    data Runnable = RunnableModule Module FilePath | RunnableRecipe Recipe FilePath
    data AppliedRecipe = AppliedRecipe
      { name :: RecipeName, recipeVersion :: Maybe Text, appliedAt :: UTCTime }

In `seihou-core/src/Seihou/Dhall/Eval.hs`:

    evalRecipeFromFile :: FilePath -> IO (Either ModuleLoadError Recipe)

In `seihou-core/src/Seihou/Core/Module.hs`:

    discoverRunnable :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError Runnable)

In `seihou-core/src/Seihou/Composition/Recipe.hs`:

    expandRecipe :: Recipe -> (ModuleName, [ModuleName], Map VarName Text, [VarDecl], [Prompt])

In `seihou-core/src/Seihou/Core/Recipe.hs`:

    validateRecipe :: Recipe -> Either [Text] Recipe


## Revision Notes

- **2026-04-15**: Expanded Milestone 4 registry coverage. The original plan only mentioned relaxing `validateEntry` to accept `recipe.dhall`. This was insufficient — the `Registry` type itself (and its Dhall decoder) needs a new `recipes :: [RegistryEntry]` field so that `seihou-registry.dhall` files can explicitly declare recipe entries alongside module entries. Added: Registry type change, decoder update with backwards-compatible defaults, split validation for module vs recipe entries, name collision detection, `SingleRecipe` constructor for `RepoContents`, browse integration, and install flow for recipe entries. Updated Progress checklist, Modified Files, and Idempotence sections accordingly.
