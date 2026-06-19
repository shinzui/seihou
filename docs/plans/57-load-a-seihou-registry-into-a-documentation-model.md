---
id: 57
slug: load-a-seihou-registry-into-a-documentation-model
title: "Load a seihou registry into a documentation model"
kind: exec-plan
created_at: 2026-06-19T17:55:29Z
intention: "intention_01kvgg9k54efytmmeqty43t6y5"
master_plan: "docs/masterplans/7-generate-okf-documentation-bundles-for-seihou-registries.md"
---

# Load a seihou registry into a documentation model

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This plan is part of the MasterPlan at
`docs/masterplans/7-generate-okf-documentation-bundles-for-seihou-registries.md`. Read that
file for the overall initiative; this plan stands alone for implementation.

The `seihou-okf-extension docs` feature must turn a seihou registry into documentation. A
"registry" is a directory whose `seihou-registry.dhall` file lists the artifacts a repo
publishes, in four groups: **modules** (deterministic scaffolding templates), **recipes**
(named module compositions), **blueprints** (agent-driven scaffolds), and **prompts**
(reusable agent-session templates). Each list entry is a thin record — `name`, `version`,
`path`, `description`, `tags` — that points (via `path`) at a directory containing the full
artifact definition (`module.dhall`, `recipe.dhall`, `blueprint.dhall`, or `prompt.dhall`).

This plan builds the **documentation model**: an in-memory value that, for every registry
entry, pairs its catalog metadata with the *fully loaded* artifact and records the
cross-references between entities (a module's dependencies, a recipe's composed modules, a
blueprint's base modules). It lives in the `seihou-okf-extension` package created by EP-60.
It deliberately imports only seihou's own types — not okf-core — so the loading logic is
independently verifiable before any rendering exists.

The observable outcome: a function `loadDocModel :: FilePath -> IO (Either DocLoadError
DocModel)` that, given a registry directory, returns a structured model; and unit tests that
run it against a fixture registry and assert the right entities, versions, descriptions, and
resolved cross-references are present. EP-58 then renders this model to an OKF bundle.


## Progress

- [ ] Define `DocModel`, `DocEntry`, `DocKind`, `ModuleRef`, and `DocLoadError` in `seihou-okf-extension`
- [ ] Implement `loadDocModel :: FilePath -> IO (Either DocLoadError DocModel)` reusing `Seihou.Dhall.Eval` loaders
- [ ] Resolve cross-references (module dependencies, recipe modules, blueprint base modules) into the model
- [ ] Add a fixture registry under the test tree and unit tests asserting entities + cross-references
- [ ] Add the new module(s) to `seihou-okf-extension-internal` `exposed-modules` and the spec to the extension test `Main.hs`
- [ ] `cabal build all` and `cabal test seihou-okf-extension-test` green


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Define the documentation model in `seihou-okf-extension`
  (`seihou-okf-extension/src/Seihou/OKF/Docs/Model.hs`), not in `seihou-core` or
  `seihou-cli-internal`.
  Rationale: It is feature-specific to the OKF extension. The extension can freely call the
  `seihou-core` `Seihou.Dhall.Eval` loaders, while the main CLI stays independent of OKF
  documentation internals.
  Date: 2026-06-19

- Decision: Resolve cross-references as *names plus a resolved/unresolved flag*, not as
  embedded sub-models.
  Rationale: A module dependency references another module by bare name. Storing the name
  (and whether it resolves to an entry in this registry) keeps the model a flat list and lets
  EP-58 render a link to `modules/<name>` and lets validation later flag unresolved
  references. Embedding full sub-artifacts would duplicate data and complicate cycles.
  Date: 2026-06-19


## Context and Orientation

All paths are relative to the seihou repository root
(`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`).

The registry type — `seihou-core/src/Seihou/Core/Registry.hs`:

```haskell
data RegistryEntry = RegistryEntry
  { name :: ModuleName       -- newtype over Text; unModuleName :: Text
  , version :: Maybe Text
  , path :: FilePath         -- relative to the registry repo root
  , description :: Maybe Text
  , tags :: [Text]
  }

data Registry = Registry
  { repoName :: Text
  , repoDescription :: Maybe Text
  , modules :: [RegistryEntry]
  , recipes :: [RegistryEntry]
  , blueprints :: [RegistryEntry]
  , prompts :: [RegistryEntry]
  }
```

The full artifact types — `seihou-core/src/Seihou/Core/Types.hs` (all derive
`(Eq, Show, Generic)`):

```haskell
data Module = Module
  { name :: ModuleName, version :: Maybe Text, description :: Maybe Text
  , vars :: [VarDecl], exports :: [VarExport], prompts :: [Prompt]
  , steps :: [Step], commands :: [Command], dependencies :: [Dependency]
  , removal :: Maybe Removal, migrations :: [Migration] }

data Recipe = Recipe
  { name :: RecipeName, version :: Maybe Text, description :: Maybe Text
  , modules :: [Dependency], vars :: [VarDecl], prompts :: [Prompt] }

data Blueprint = Blueprint
  { name :: ModuleName, version :: Maybe Text, description :: Maybe Text
  , prompt :: Text, vars :: [VarDecl], prompts :: [Prompt]
  , baseModules :: [Dependency], files :: [BlueprintFile]
  , allowedTools :: Maybe [Text], tags :: [Text] }

data AgentPrompt = AgentPrompt
  { name :: ModuleName, version :: Maybe Text, description :: Maybe Text
  , prompt :: Text, vars :: [VarDecl], prompts :: [Prompt]
  , commandVars :: [CommandVar], files :: [BlueprintFile]
  , allowedTools :: Maybe [Text], tags :: [Text], launch :: Maybe AgentPromptLaunch }
```

The shared reference type used by `Module.dependencies`, `Recipe.modules`, and
`Blueprint.baseModules`:

```haskell
data Dependency = Dependency { module_ :: Text, vars :: [...] }   -- references a module by name
```

(Check the exact field name for the referenced module in `Seihou.Core.Types` — research
reported the Dhall field is `module`; the Haskell field is likely `module_` or accessed via a
record selector. Confirm by reading the `Dependency` definition before using it.)

CRITICAL distinction (do not conflate): the schema has two "prompt" notions. `Prompt` (the
sub-field in `vars`/`prompts` lists) is an *interactive variable prompt* (`var`, `text`,
`when`, `choices`) used inside every artifact. A registry **"prompt" entry**, by contrast, is
a standalone **`AgentPrompt`** stored in a `prompt.dhall` file. So when this plan loads a
registry `prompts` entry, it loads an `AgentPrompt` via `evalAgentPromptFromFile`, *not* a
`Prompt`.

The Dhall loaders — `seihou-core/src/Seihou/Dhall/Eval.hs` (ordinary IO, return
`Either ModuleLoadError a`):

```haskell
evalRegistryFromFile    :: FilePath -> IO (Either ModuleLoadError Registry)
evalModuleFromFile      :: FilePath -> IO (Either ModuleLoadError Module)
evalRecipeFromFile      :: FilePath -> IO (Either ModuleLoadError Recipe)
evalBlueprintFromFile   :: FilePath -> IO (Either ModuleLoadError Blueprint)
evalAgentPromptFromFile :: FilePath -> IO (Either ModuleLoadError AgentPrompt)
```

`evalRegistryFromFile` decodes `<dir>/seihou-registry.dhall` (its `recipes`/`blueprints`/
`prompts` fields default to empty lists if omitted). For each entry, the full artifact file
lives at `<registryDir> </> entry.path </> "<kind>.dhall"` — i.e. a module entry's file is
`<registryDir>/<entry.path>/module.dhall`, a recipe's is `.../recipe.dhall`, a blueprint's
`.../blueprint.dhall`, a prompt's `.../prompt.dhall`. Confirm the exact filename convention
by reading how `Seihou.Core.Module.discoverRepoContents` probes a repo root (research found it
probes `module.dhall` → `recipe.dhall` → `blueprint.dhall` → `prompt.dhall`).

`ModuleName`/`RecipeName` are newtypes; use `unModuleName`/`unRecipeName` to get `Text`.

A concrete registry to model and to base the fixture on:
`/Users/shinzui/Keikaku/bokuno/seihou-modules/seihou-registry.dhall` — `repoName =
"seihou-modules"`, 5 modules (e.g. `nix-haskell-flake`, `haskell-library` which depends on
`nix-haskell-flake`), 2 recipes (`haskell-library-repo`, `haskell-cli-app-repo`), 1 blueprint
(`upgrade-haskell-flake-parts`), no `prompts`.

Seihou extension test conventions: tasty + tasty-hspec + hspec. Each spec module exports
`tests :: IO TestTree` built with `testSpec "Name" spec`; `spec :: Spec` uses
`describe`/`it`. Specs are aggregated in `seihou-okf-extension/test/Main.hs` (import the
spec, run its `tests`, add to the `testGroup`). New spec modules must be added to the test
stanza's `other-modules` in `seihou-okf-extension/seihou-okf-extension.cabal` AND to
`seihou-okf-extension/test/Main.hs`. Fixtures live under the extension test tree; use
`System.IO.Temp.withSystemTempDirectory` for generated ones or a checked-in fixture
directory. Read `seihou-core/test/Seihou/Core/RegistrySpec.hs` for the exact pattern of
writing a Dhall registry to a temp dir and asserting on the loader.

Build/test: `nix develop`, then `cabal build all`, `cabal test seihou-okf-extension-test` (or
`just build` / `just test`).


## Plan of Work

Single milestone delivering the model type and loader, plus tests.

Step 1 — model types. Create `seihou-okf-extension/src/Seihou/OKF/Docs/Model.hs`:

```haskell
module Seihou.OKF.Docs.Model
  ( DocKind (..)
  , DocArtifact (..)
  , DocEntry (..)
  , ModuleRef (..)
  , DocModel (..)
  , DocLoadError (..)
  , loadDocModel
  ) where
```

Define:

```haskell
data DocKind = DocModuleKind | DocRecipeKind | DocBlueprintKind | DocPromptKind
  deriving stock (Eq, Show)

-- The fully loaded artifact for an entry.
data DocArtifact
  = DocModuleArtifact Module
  | DocRecipeArtifact Recipe
  | DocBlueprintArtifact Blueprint
  | DocPromptArtifact AgentPrompt
  deriving stock (Eq, Show)

-- One registry entry: catalog metadata + the loaded artifact + resolved references.
data DocEntry = DocEntry
  { entryName :: Text            -- from RegistryEntry.name
  , entryKind :: DocKind
  , entryVersion :: Maybe Text
  , entryDescription :: Maybe Text
  , entryTags :: [Text]
  , entryPath :: FilePath        -- relative path from the registry root (becomes the resource link)
  , entryArtifact :: DocArtifact
  , entryModuleRefs :: [ModuleRef]   -- dependencies / recipe modules / base modules, by name
  }
  deriving stock (Eq, Show)

-- A reference to a module by name, with whether it resolves to an entry in this registry.
data ModuleRef = ModuleRef
  { refName :: Text
  , refResolved :: Bool          -- True iff a module entry with this name exists in the model
  }
  deriving stock (Eq, Show)

data DocModel = DocModel
  { docRepoName :: Text
  , docRepoDescription :: Maybe Text
  , docEntries :: [DocEntry]
  }
  deriving stock (Eq, Show)

data DocLoadError
  = RegistryNotFound FilePath
  | RegistryLoadFailed Text         -- rendered ModuleLoadError
  | ArtifactLoadFailed Text Text    -- entry name, rendered ModuleLoadError
  deriving stock (Eq, Show)
```

Step 2 — loader. Implement `loadDocModel :: FilePath -> IO (Either DocLoadError DocModel)`:

1. Compute `registryFile = registryDir </> "seihou-registry.dhall"`; if it does not exist
   (`System.Directory.doesFileExist`), return `Left (RegistryNotFound registryFile)`.
2. `evalRegistryFromFile registryFile`; on `Left e` return
   `Left (RegistryLoadFailed (render e))` where `render` shows the `ModuleLoadError` (reuse
   any existing renderer in `Seihou.Core` or `Text.pack . show`).
3. For each entry in `modules`/`recipes`/`blueprints`/`prompts`, in that order, load the full
   artifact from `registryDir </> path </> "<kind>.dhall"` with the matching `eval*FromFile`.
   On failure return `Left (ArtifactLoadFailed name (render e))`. Build a `DocEntry` with the
   catalog fields from the `RegistryEntry` and the loaded `DocArtifact`. (Use
   `unModuleName`/`unRecipeName` for `entryName`.)
4. Extract `entryModuleRefs` per kind: for a module, the names in `dependencies`; for a
   recipe, the names in `modules`; for a blueprint, the names in `baseModules`; for a prompt,
   none. Each ref's `module_`/referenced-module field is the name.
5. After all entries are built, set each `ModuleRef`'s `refResolved` by checking membership in
   the set of `entryName`s whose `entryKind == DocModuleKind`. Return
   `Right (DocModel repoName repoDescription entries)`.

Keep `loadDocModel` in plain `IO` (the seihou loaders are plain IO; do not introduce an
effectful stack here — EP-58/EP-59 stay in IO too).

Step 3 — exports + cabal. Add `Seihou.OKF.Docs.Model` to the `exposed-modules` of the
`seihou-okf-extension-internal` stanza in
`seihou-okf-extension/seihou-okf-extension.cabal`.

Step 4 — fixture + tests. Create a small fixture registry under the test tree, e.g.
`seihou-okf-extension/test/fixtures/docs-registry/`, containing `seihou-registry.dhall` and the
referenced artifact directories (at minimum: two modules where one depends on the other, one
recipe composing both, one blueprint with a base module, and one prompt). Pin the
seihou-schema import in the fixture `.dhall` files the same way the real registry does (a
`https://raw.githubusercontent.com/shinzui/seihou-schema/<sha>/package.dhall sha256:<hash>`
import) — copy a working import line from
`/Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/haskell-library/module.dhall`
so the hash matches a real schema commit. Alternatively, write the fixture into a temp dir at
test time (mirroring `RegistrySpec`), which avoids checking in network-fetched schema hashes;
prefer the temp-dir approach if the test environment lacks network access, and note the choice
in Surprises & Discoveries.

Create `seihou-okf-extension/test/Seihou/OKF/Docs/ModelSpec.hs` exporting `tests :: IO TestTree`, with
cases asserting: the model has the expected counts per kind; a known module entry has the
expected version/description/tags; the dependent module's `entryModuleRefs` contains its
dependency with `refResolved == True`; and an intentionally-broken reference (a module naming
a non-existent dependency) yields `refResolved == False`. Add the spec to
`seihou-okf-extension/test/Main.hs` and to the test stanza `other-modules`.

Step 5 — build and test (see Concrete Steps).


## Concrete Steps

From the seihou repository root, inside the dev shell:

```bash
nix develop
cabal build all
cabal test seihou-okf-extension-test
```

Expected: the new `ModelSpec` cases pass, e.g.:

```text
Seihou.OKF.Docs.Model
  loadDocModel
    loads all four entry kinds from the fixture registry [✔]
    resolves haskell-library's dependency on nix-haskell-flake [✔]
    marks an unknown dependency as unresolved [✔]
```

REPL spot-check against the real registry:

```bash
cabal repl seihou-okf-extension-internal
```

```haskell
ghci> import Seihou.OKF.Docs.Model
ghci> Right m <- loadDocModel "/Users/shinzui/Keikaku/bokuno/seihou-modules"
ghci> length (docEntries m)        -- 8 (5 modules + 2 recipes + 1 blueprint)
ghci> docRepoName m                 -- "seihou-modules"
```


## Validation and Acceptance

Acceptance is behavioral:

1. `cabal test seihou-okf-extension-test` passes the new `ModelSpec`, demonstrating that a registry
   directory loads into a `DocModel` with the correct entities and metadata.
2. Cross-reference resolution works: a real dependency is marked `refResolved == True` and a
   dangling one `refResolved == False` (the test proves both).
3. The REPL spot-check against `/Users/shinzui/Keikaku/bokuno/seihou-modules` returns the
   real entry count and repo name, proving the loader works on production data, not only the
   fixture.
4. No okf-core import appears in `Seihou.OKF.Docs.Model`; confirm with
   `grep -n "Okf" seihou-okf-extension/src/Seihou/OKF/Docs/Model.hs` returning nothing.


## Idempotence and Recovery

`loadDocModel` is read-only IO and deterministic for a fixed registry, so tests and REPL
checks are repeatable. If a fixture artifact fails to load because of a stale seihou-schema
hash, switch the fixture to the temp-dir approach (write `.dhall` text at test time using a
known-good schema import copied from a real `seihou-modules` artifact) and re-run. There is no
state to clean up; reverting the new module and spec removes the feature cleanly.


## Interfaces and Dependencies

Uses existing seihou-core modules only: `Seihou.Core.Registry` (`Registry`, `RegistryEntry`),
`Seihou.Core.Types` (`Module`, `Recipe`, `Blueprint`, `AgentPrompt`, `Dependency`,
`ModuleName`, `RecipeName`), `Seihou.Dhall.Eval` (the `eval*FromFile` loaders), plus
`System.Directory`/`System.FilePath`/`Data.Text`. No new package dependencies; no okf-core.

Types/functions that must exist at the end of this plan, in
`seihou-okf-extension/src/Seihou/OKF/Docs/Model.hs`:

```haskell
data DocKind = DocModuleKind | DocRecipeKind | DocBlueprintKind | DocPromptKind
data DocArtifact = DocModuleArtifact Module | DocRecipeArtifact Recipe
                 | DocBlueprintArtifact Blueprint | DocPromptArtifact AgentPrompt
data DocEntry = DocEntry { entryName :: Text, entryKind :: DocKind, entryVersion :: Maybe Text
                         , entryDescription :: Maybe Text, entryTags :: [Text], entryPath :: FilePath
                         , entryArtifact :: DocArtifact, entryModuleRefs :: [ModuleRef] }
data ModuleRef = ModuleRef { refName :: Text, refResolved :: Bool }
data DocModel = DocModel { docRepoName :: Text, docRepoDescription :: Maybe Text, docEntries :: [DocEntry] }
data DocLoadError = RegistryNotFound FilePath | RegistryLoadFailed Text | ArtifactLoadFailed Text Text
loadDocModel :: FilePath -> IO (Either DocLoadError DocModel)
```

Relationship to other plans (see the MasterPlan's Integration Points):

- This plan owns integration point 2 (the documentation model type). EP-58
  (`docs/plans/58-render-the-seihou-documentation-model-to-an-okf-bundle.md`) consumes
  `DocModel`/`DocEntry` read-only.
- It depends on EP-60 because the `seihou-okf-extension` package must exist first.
- It intentionally has no okf-core import; EP-58 introduces OKF rendering in the same package.
- It shares `seihou-okf-extension/test/Main.hs` and the extension test stanza
  `other-modules` with EP-58 and EP-59: append the new spec; do not reorder existing ones.


## Revision Notes

- 2026-06-19: Validated the model contract against downstream plans and added
  `ModuleRef (..)` to the required export list. EP-58 and EP-59 need to inspect `refName`
  and `refResolved`; omitting it from the export list would make the child plans inconsistent
  even though the type is part of `DocEntry`.
- 2026-06-19: Retargeted the plan from `seihou-cli-internal` to the new
  `seihou-okf-extension` package introduced by EP-60. The model remains okf-free but is now
  extension-owned so the private main CLI library is not part of the OKF feature boundary.
