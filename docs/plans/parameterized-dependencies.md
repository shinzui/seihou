---
slug: parameterized-dependencies
title: "Parameterized Dependencies"
kind: exec-plan
created_at: 2026-03-11T23:44:25Z
---


# Parameterized Dependencies

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Today, when module A depends on module B, A cannot pass variable values to B. Dependencies are declared as bare module names (`dependencies = [ "claude-skill-link" ]`), so there is no mechanism for the parent module to supply values that the dependency needs. This forces the dependency to either hard-code defaults or prompt the user interactively, even when the parent already knows the answer.

After this change, a module author can write:

    , dependencies =
      [ { module = "claude-skill-link"
        , vars = [ { name = "skill.name", value = "exec-plan" } ]
        }
      ]

The dependent module receives `skill.name = "exec-plan"` as a pre-supplied value, skipping the interactive prompt. This value sits between "module default" and "CLI override" in the resolution precedence chain, so users can still override it from the command line or config files if they want to.

To verify: running `seihou run exec-plan --dry-run` with the updated module no longer prompts for `skill.name` in the `claude-skill-link` dependency.


## Progress

- [x] Milestone 1: Dhall schema and Haskell types (2026-03-11)
  - [x] Add `Dependency` type to `seihou-core/src/Seihou/Core/Types.hs`
  - [x] Add `VarSource` constructor `FromParent ModuleName`
  - [x] Update `Module.dependencies` from `[ModuleName]` to `[Dependency]`
  - [x] Dhall schema `schema/Module.dhall` — kept as `List Text` (backward compat handled in decoder)
  - [x] Add `dependencyDecoder` to `seihou-core/src/Seihou/Dhall/Eval.hs` with backward compatibility for bare strings
  - [x] Update `moduleDecoder` to use `dependencyDecoder`
  - [x] Update `formatExplain` in `seihou-core/src/Seihou/Core/Variable.hs` to show `FromParent`
  - [x] Update Graph.hs, Resolve.hs, Module.hs, test helpers for `[Dependency]`
  - [x] Verify: `cabal build all` succeeds
- [x] Milestone 2: Resolution engine (2026-03-11)
  - [x] Add `collectParentVars` to Resolve.hs
  - [x] Add `parentVars` parameter to `resolveVariables` with `lookupParent` in precedence chain
  - [x] Update `resolveComposedVariables` to compute and thread parent vars
  - [x] Update `resolveWithPrompts` to compute and thread parent vars
  - [x] Update all test call sites for new `resolveVariables` signature
  - [x] Verify: `cabal build all` succeeds
- [x] Milestone 3: Validation (2026-03-11)
  - [x] Update `checkDependencyNames` in `seihou-core/src/Seihou/Core/Module.hs` (done in M1)
  - [x] Add `checkDependencyVarBindings` validation rule
  - [x] Add `checkDependencyVarBindings` to `validateModule` function
  - [x] Add `Data.Map.Strict qualified as Map` import to Module.hs
  - [x] Verify: `cabal build all` succeeds
- [x] Milestone 4: Tests (2026-03-11)
  - [x] Add unit tests for `dependencyDecoder` (bare string and record forms) via `evalModuleFromFile`
  - [x] Add unit tests for parameterized resolution in `ResolveSpec.hs`
  - [x] Add unit tests for `FromParent` provenance display in `VariableSpec.hs`
  - [x] Add parent var resolution tests in `VariableSpec.hs`
  - [x] Fix `PromptSpec.hs` and `CompositionSpec.hs` for `[Dependency]` type change
  - [x] Fix `evalModuleFromFile` to bypass Dhall type-annotation check (required for mixed dependency forms)
  - [x] Verify: `cabal test all` passes (568 + 28 = 596 tests)
- [x] Milestone 5: Test fixture and end-to-end verification (2026-03-11)
  - [x] Create test fixture pair: `param-dep-parent` and `param-dep-child`
  - [x] Update the `exec-plan` module in `agent-seihou` to use the new syntax
  - [x] Verify: both fixtures load correctly via `evalModuleFromFile`
  - [x] Verify: `seihou run exec-plan --dry-run` no longer prompts for `skill.name` (2026-03-11)


## Surprises & Discoveries

- Dhall's `inputFile` and `input` functions type-check the expression against the decoder's `expected` type BEFORE extraction. Since `dependencyDecoder` has `expected = expected strictText` (returns `Text`), any Dhall expression with record-form dependencies (`List { module : Text, vars : ... }`) fails type-checking before the custom decoder can even run. The fix: changed `evalModuleFromFile` to use `inputExprWithSettings` (parse + resolve + normalize, no decoder type-check) followed by manual `extract moduleDecoder`. This required adding the `either` package dependency (for `Data.Either.Validation`) and `Data.Text.IO` for file reading. (2026-03-11)

- Two additional test files (`PromptSpec.hs`, `CompositionSpec.hs`) needed updating for the `[ModuleName] -> [Dependency]` type change. These were not caught in the initial M1/M2 work because the test suite wasn't run until M4. (2026-03-11)


## Decision Log

- Decision: Parent-supplied vars sit at a new precedence level between "module default" (level 7) and "config layers" (level 6, global config). Specifically the chain becomes: CLI -> env -> local config -> namespace config -> context config -> global config -> **parent-supplied** -> module default -> prompt.
  Rationale: Parent-supplied values are more authoritative than the dependency's own defaults (the parent knows why it invoked the dependency), but less authoritative than user-provided config or CLI overrides (the user always wins). This matches the existing pattern where exports override defaults.
  Date: 2026-03-11

- Decision: Use a Dhall union type for backward compatibility. The `dependencies` field accepts both bare `Text` values and `{ module : Text, vars : ... }` records. The Haskell decoder handles both forms.
  Rationale: Every existing module uses `dependencies = [ "mod-name" ] : List Text`. Requiring a schema migration for all existing modules would be disruptive. A union type lets old modules work unchanged.
  Date: 2026-03-11

- Decision: Parent-supplied vars are injected as overrides during resolution, not as defaults on `VarDecl`. They use a dedicated `FromParent` source tag for provenance.
  Rationale: Using `injectExportDefault` (which mutates `VarDecl.default_`) would conflate two different concepts. A parent binding should have higher priority than a module's own default and should be clearly visible in `--explain` output. A separate override map with its own `VarSource` achieves both goals.
  Date: 2026-03-11

- Decision: Refactored `evalModuleFromFile` to use `inputExprWithSettings` + manual `extract` instead of `inputFile`, bypassing Dhall's decoder type-annotation check.
  Rationale: Dhall's `inputFile` annotates the expression with the decoder's `expected` type and type-checks against it. The `dependencyDecoder` must accept both `Text` (bare strings) and `{ module : Text, vars : ... }` (records), but no single Dhall type represents both. Splitting evaluation from extraction lets the custom decoder handle the union at the AST level. Added `either` package dependency for `Data.Either.Validation`.
  Date: 2026-03-11


## Outcomes & Retrospective

Implementation complete across all 5 milestones. The feature adds parameterized dependencies
to seihou, allowing parent modules to supply variable values to their dependencies.

Key outcomes:
- New `Dependency` type replaces bare `ModuleName` in the `dependencies` field, with full
  backward compatibility for existing modules using `List Text`.
- Custom `dependencyDecoder` handles both bare string (`"base"`) and record form
  (`{ module = "base", vars = [...] }`) via Dhall AST pattern matching.
- Parent-supplied vars sit at precedence level 7 (between global config and module default),
  with `FromParent ModuleName` provenance tracking visible in `--explain` output.
- `evalModuleFromFile` refactored to bypass Dhall's decoder type-annotation check, enabling
  mixed dependency forms without type errors.
- 596 tests pass (568 core + 28 CLI), including 8 new tests covering decoder, resolution,
  provenance, and precedence.

Lesson: Dhall's `inputFile` couples parsing with type-checking against the decoder's expected
type. When the decoder needs to accept multiple Dhall types (Text vs Record), the expected
type cannot represent both, requiring a split between expression evaluation and extraction.


## Context and Orientation

Seihou is a composable project scaffolding system. Modules are defined in Dhall files (`module.dhall`) and contain variable declarations, generation steps, commands, and dependencies on other modules. When `seihou run` is invoked, the system loads all modules in the composition, resolves variables through a multi-layer precedence chain, generates files, and executes commands.

The key files involved in this change are:

`seihou-core/src/Seihou/Core/Types.hs` defines all core data types. The `Module` type has a `dependencies :: [ModuleName]` field, which is currently a flat list of module name strings. `VarSource` is an ADT that tracks where each resolved variable value came from (CLI, env, config, default, prompt, etc.).

`schema/Module.dhall` is the Dhall schema that defines the shape of `module.dhall` files. Currently `dependencies` is `List Text`.

`seihou-core/src/Seihou/Dhall/Eval.hs` contains Dhall decoders that parse `module.dhall` files into Haskell types. The `moduleDecoder` currently decodes dependencies as `list moduleNameDecoder` where `moduleNameDecoder` is simply `ModuleName <$> strictText`.

`seihou-core/src/Seihou/Composition/Graph.hs` builds a directed acyclic graph from modules using their dependency lists and performs topological sorting to determine execution order. It reads `m.dependencies` directly to build edges.

`seihou-core/src/Seihou/Composition/Resolve.hs` is the variable resolution engine. It has two main entry points: `resolveComposedVariables` (pure, no prompting) and `resolveWithPrompts` (effectful, with interactive prompting). Both iterate over modules in topological order, collecting exports from dependencies and injecting them as defaults via `injectExportDefault`. The key change will be to also inject parent-supplied variable bindings before resolution.

`seihou-core/src/Seihou/Core/Variable.hs` contains `resolveVariables`, which resolves a single module's variables through the precedence chain: CLI -> env -> local config -> namespace config -> context config -> global config -> module default. It also contains `formatExplain` which renders provenance for `--explain` output.

`seihou-core/src/Seihou/Core/Module.hs` contains validation logic including `checkDependencyNames` which validates that dependency names are well-formed.

`seihou-core/test/Seihou/Composition/ResolveSpec.hs` contains extensive tests for variable resolution across composed modules.


## Plan of Work

The work proceeds in five milestones. Each milestone produces a compiling codebase (milestones 1-3) or a passing test suite (milestones 4-5).


### Milestone 1: Dhall schema and Haskell types

This milestone introduces the new `Dependency` type and updates the Dhall schema and decoders. At the end, `cabal build all` compiles with no errors. No behavioral changes yet.

Start by adding a new type `Dependency` to `seihou-core/src/Seihou/Core/Types.hs`:

    data Dependency = Dependency
      { depModule :: ModuleName,
        depVars :: Map VarName Text
      }
      deriving stock (Eq, Show, Generic)

Change the `Module` type's `dependencies` field from `[ModuleName]` to `[Dependency]`. This is the most impactful change because every site that reads `m.dependencies` will need updating.

Add a new `VarSource` constructor:

    | FromParent ModuleName

This goes after `FromGlobalConfig` and before `FromDefault` in the definition (ordering does not matter for behavior but keeps the precedence order readable).

Update `schema/Module.dhall`. The `dependencies` field type does not change at the Dhall level; it remains `List Text` in the schema file. The backward compatibility is handled entirely in the Haskell decoder. However, we should document in comments that the decoder also accepts `List { module : Text, vars : ... }` and mixed lists via a union decoder.

In `seihou-core/src/Seihou/Dhall/Eval.hs`, add a `dependencyDecoder` that tries two forms:

1. A bare `Text` value, decoded as `Dependency (ModuleName t) Map.empty`.
2. A record `{ module : Text, vars : List { name : Text, value : Text } }`, decoded as `Dependency (ModuleName m) (Map.fromList [(VarName n, v) | ...])`.

The Dhall `list` combinator expects all elements to have the same type. Since Dhall does not have sum types that mix `Text` and records, the practical approach is: the decoder first tries to decode the `dependencies` field as `List Text` (bare strings). If that fails (which it will if the user uses the record form), it tries `List { module : Text, vars : List { name : Text, value : Text } }`. To support mixed lists, we can use Dhall's union type:

    let Dependency = < Simple : Text | Parameterized : { module : Text, vars : List { name : Text, value : Text } } >

But this is awkward for module authors. A cleaner approach: change the Dhall schema to accept `List { module : Text, vars : List { name : Text, value : Text } }` as the canonical form, and provide a helper function `dep : Text -> { module : Text, vars : ... }` that creates a bare dependency. However, this breaks all existing modules.

The most pragmatic approach is to keep the Dhall schema as `List Text` for documentation purposes, and implement the Haskell decoder using Dhall's `union` decoder or a custom decoder that tries both forms. Looking at the dhall-haskell library, the `Decoder` type only has a `Functor` instance, not `Alternative`. So the decoder cannot try one form and fall back to another within a single field.

The solution: define `dependencies` in the Dhall schema as a union type. Module authors write either:

    , dependencies = [ "base" ]

or:

    , dependencies = [ { module = "base", vars = [ { name = "x", value = "y" } ] } ]

For the Haskell decoder, we use a custom approach: decode the raw Dhall expression and pattern-match on the structure. Looking at how the existing codebase handles similar situations (e.g., `varTypeDecoder` uses `parseVarType <$> strictText`), the cleanest approach given Dhall's constraints is:

Use Dhall's `auto` decoder or write a custom decoder that handles the `dependencies` field as `list dependencyDecoder` where `dependencyDecoder` tries to interpret each element as either a plain text or a record. The dhall-haskell library provides `Dhall.Marshal.Decode.union` for union types. We define:

    dependencyDecoder :: Decoder Dependency
    dependencyDecoder = simpleDep <|> paramDep

But `Decoder` does not have an `Alternative` instance. We need a different approach.

The actual solution that works with dhall-haskell: use `Dhall.Core.Expr` pattern matching. The `Decoder` in dhall-haskell is `Decoder { extract :: Expr Src Void -> Extractor Src Void a, expected :: Expector (Expr Src Void) }`. The `Extractor` type *is* an `Alternative`, so we can write a custom decoder that tries the text form and falls back to the record form.

Alternatively, since the existing code uses `record` and `field` combinators from `Dhall.Marshal.Decode`, and the `Decoder`'s `extract` function returns an `Extractor` which has `Alternative`, we can construct a decoder like:

    import Dhall.Marshal.Decode (Decoder(..))

    dependencyDecoder :: Decoder Dependency
    dependencyDecoder = Decoder extractDep expectedDep
      where
        extractDep expr =
          (extractSimple expr) <|> (extractRecord expr)
        extractSimple expr = do
          name <- extract strictText expr
          pure (Dependency (ModuleName name) Map.empty)
        extractRecord expr = do
          dep <- extract depRecordDecoder expr
          pure dep
        expectedDep = expected strictText -- or a union expected type

This needs careful implementation. The `expected` field is used for type-checking and error messages; for a union we should use a union expected type, but for practical purposes we can use `expected strictText` since it is only used for error reporting.

Update `formatExplain` in `seihou-core/src/Seihou/Core/Variable.hs` to add:

    showSource (FromParent mn) = "[parent: " <> mn.unModuleName <> "]"

Then fix all compilation errors throughout the codebase where `m.dependencies` was used as `[ModuleName]` and now needs to account for `[Dependency]`. The main sites are:

- `seihou-core/src/Seihou/Composition/Graph.hs`: `buildGraph` reads `m.dependencies` to build edges. Change to map `depModule` over the list.
- `seihou-core/src/Seihou/Composition/Resolve.hs`: `loadComposition` reads `primaryMod.dependencies` and `m.dependencies`; `resolveComposedVariables` and `resolveWithPrompts` read `m.dependencies` to find direct dependency names for export collection.
- `seihou-core/src/Seihou/Core/Module.hs`: `checkDependencyNames` validates dependency names.
- Various test files that construct `Module` values with `dependencies = [...]`.

For convenience, add a helper function to `Types.hs`:

    -- | Extract module names from dependencies.
    depModuleNames :: [Dependency] -> [ModuleName]
    depModuleNames = map depModule

    -- | Create a bare dependency (no variable bindings).
    simpleDep :: ModuleName -> Dependency
    simpleDep name = Dependency { depModule = name, depVars = Map.empty }

Acceptance criteria for Milestone 1: `cabal build all` compiles with no errors.


### Milestone 2: Resolution engine

This milestone wires up the parent-supplied variable bindings during resolution. At the end, parent-supplied values are injected during resolution and variables with parent-supplied values are no longer prompted.

In `seihou-core/src/Seihou/Composition/Resolve.hs`, the `resolveComposedVariables` function iterates over modules in topological order. For each module, it currently:

1. Collects exported variables from direct dependencies (`visibleExports`).
2. Adjusts declarations by injecting exports as defaults (`injectExportDefault`).
3. Calls `resolveVariables` with the adjusted declarations.

The change adds a step between 2 and 3: collect parent-supplied variable bindings. When module A depends on module B with `vars = [{ name = "x", value = "y" }]`, we need to know, while resolving B, that A has supplied `x = "y"`. This means we need to build a reverse map: for each module, what vars have been supplied to it by its dependents?

However, the resolution order is topological (dependencies first), so when we resolve module B, module A has not been processed yet. We need to pre-compute the parent-supplied vars before entering the resolution loop.

Add a function:

    -- | Collect all parent-supplied variable bindings across the composition.
    -- Returns a map from module name to the vars supplied to it by its dependents.
    collectParentVars :: [(Module, FilePath)] -> Map ModuleName (Map VarName Text)
    collectParentVars modules =
      Map.fromListWith Map.union
        [ (dep.depModule, dep.depVars)
        | (m, _) <- modules
        , dep <- m.dependencies
        , not (Map.null dep.depVars)
        ]

Then in the resolution loop, look up `parentVars = Map.findWithDefault Map.empty m.name allParentVars` and pass them into `resolveVariables` as an additional override layer.

In `seihou-core/src/Seihou/Core/Variable.hs`, update `resolveVariables` to accept an additional parameter for parent-supplied vars. Insert it in the precedence chain between global config and module default:

    Nothing -> case lookupConfig name ty globalConfig FromGlobalConfig of
      Just result -> fmap Just (result >>= validateAndWrap decl)
      Nothing -> case lookupParent name ty parentVars of   -- NEW
        Just result -> fmap Just (result >>= validateAndWrap decl)
        Nothing -> case decl.default_ of
          ...

Where `lookupParent` is similar to `lookupConfig` but uses `FromParent parentModuleName` as the source. Since multiple parents could supply the same var (unlikely but possible), we need to decide which parent wins. The simplest rule: last writer wins based on the order modules appear in the dependency list. The `collectParentVars` function using `Map.union` (left-biased) will naturally pick the first parent that supplies the var.

Actually, looking at this more carefully, `resolveVariables` does not know which parent supplied the var. The `collectParentVars` map loses the parent identity. We need to carry the parent module name alongside the value. Change `collectParentVars` to:

    collectParentVars :: [(Module, FilePath)] -> Map ModuleName (Map VarName (Text, ModuleName))

Where the tuple is `(value, parentModuleName)`. Then `lookupParent` can create `FromParent parentModuleName`.

Update `resolveVariables` signature to add the new parameter:

    resolveVariables ::
      [VarDecl] ->
      Map VarName Text ->        -- CLI overrides
      Map Text Text ->           -- Environment variables
      Text ->                    -- Namespace
      Text ->                    -- Context
      Map VarName Text ->        -- Local config
      Map VarName Text ->        -- Namespace config
      Map VarName Text ->        -- Context config
      Map VarName Text ->        -- Global config
      Map VarName (Text, ModuleName) ->  -- Parent-supplied vars (NEW)
      Either [VarError] (Map VarName ResolvedVar)

Update all call sites of `resolveVariables` (in `Resolve.hs` and possibly tests) to pass the new parameter.

Similarly update `resolveWithPrompts` and `resolveComposedVariables` to compute and thread `parentVars`.

The `resolveWithPrompts` function also needs updating: when a variable has a parent-supplied value, it should not be prompted. This is already handled by the resolution precedence chain, since parent-supplied vars resolve before the "prompt" fallback. But we should verify that prompted vars (in the missing-required-var error path) correctly skip vars that have parent-supplied values.

Acceptance criteria for Milestone 2: `cabal build all` compiles. Running mentally through the resolution for the `exec-plan` / `claude-skill-link` scenario: `exec-plan` depends on `claude-skill-link` with `vars = [{ name = "skill.name", value = "exec-plan" }]`. When resolving `claude-skill-link`, `parentVars` contains `skill.name -> ("exec-plan", "exec-plan")`. `resolveVariables` finds the parent-supplied value before reaching the module default (which is `None Text`), so `skill.name` resolves as `VText "exec-plan"` with source `FromParent "exec-plan"`. No prompt is triggered.


### Milestone 3: Validation

This milestone adds validation rules to catch common mistakes in parameterized dependencies.

In `seihou-core/src/Seihou/Core/Module.hs`, update `checkDependencyNames` to extract module names from `Dependency` values instead of raw `ModuleName` values:

    checkDependencyNames m =
      concatMap
        ( \dep ->
            let n = dep.depModule.unModuleName
             in ...
        )
        m.dependencies

Add a new validation function `checkDependencyVarBindings` that warns when a dependency supplies a var name that does not exist in the dependency's declared variables. This is a cross-module validation that requires loading the dependency first, so it cannot be done in the single-module `validateModule` function. Instead, add it as a warning during composition loading in `loadComposition`. For now, skip this cross-module validation and only validate that var binding names are well-formed (non-empty, valid characters).

Acceptance criteria: `cabal build all` compiles.


### Milestone 4: Tests

Add tests to validate the new functionality.

In `seihou-core/test/Seihou/Dhall/EvalSpec.hs`, add tests for `dependencyDecoder`:
- A module with `dependencies = [ "base" ]` (bare string) still decodes correctly.
- A module with `dependencies = [ { module = "base", vars = [ { name = "x", value = "y" } ] } ]` decodes as `Dependency "base" (Map.fromList [("x", "y")])`.
- A module with `dependencies = [ { module = "base", vars = [] : List { name : Text, value : Text } } ]` decodes as `Dependency "base" Map.empty`.

In `seihou-core/test/Seihou/Composition/ResolveSpec.hs`, add tests:
- "parent-supplied var resolves in dependency": Module A depends on B with `vars = [("x", "hello")]`. B declares `x` as required with no default. Resolution succeeds with `x = "hello"` and source `FromParent "a"`.
- "parent-supplied var overrides dependency's default": B has default `"old"` for `x`, A supplies `"new"`. Resolution gives `x = "new"`.
- "CLI override beats parent-supplied var": A supplies `x = "from-parent"`, CLI provides `x = "from-cli"`. Resolution gives `x = "from-cli"` with source `FromCLI`.
- "parent-supplied var beats module default but not config": B declares `x` with default `"default"`, global config has `x = "global"`, A supplies `x = "parent"`. Resolution gives `x = "global"` (config wins over parent).

Update existing tests in `ResolveSpec.hs` and `GraphSpec.hs` that construct `Module` values to use the new `Dependency` type (via the `simpleDep` helper).

Acceptance criteria: `cabal test all` passes.


### Milestone 5: Test fixture and end-to-end verification

Create a test fixture pair in `seihou-core/test/fixtures/` that demonstrates parameterized dependencies. Create two module directories:

- `seihou-core/test/fixtures/param-dep-parent/module.dhall`: declares `skill.name` with default `"my-skill"`, exports it, depends on `param-dep-child` with `vars = [{ name = "skill.name", value = "my-skill" }]`.
- `seihou-core/test/fixtures/param-dep-child/module.dhall`: declares `skill.name` as required with no default.

Then update the real `exec-plan` module in `/Users/shinzui/Keikaku/bokuno/agent-seihou/modules/exec-plan/module.dhall` to use the new parameterized dependency syntax:

    , dependencies = [ { module = "claude-skill-link", vars = [ { name = "skill.name", value = "exec-plan" } ] } ]

Acceptance criteria: `seihou run exec-plan --dry-run` from a project directory no longer prompts for `skill.name` in the `claude-skill-link` dependency.


## Concrete Steps

All commands are run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

After each milestone's code changes:

    cabal build all

Expected output includes `Building` lines for `seihou-core` and `seihou-cli` with no errors.

After Milestone 4:

    cabal test all

Expected output includes test results for `seihou-core-test` and `seihou-cli-test` with all tests passing.

After Milestone 5, from a project directory that has the `exec-plan` module installed:

    seihou run exec-plan --dry-run

Expected: no interactive prompt for `skill.name`. The dry-run output shows `skill.name = "exec-plan"` resolved from `[parent: exec-plan]`.


## Validation and Acceptance

The feature is validated at three levels:

Unit tests (Milestone 4) verify that the decoder handles both bare string and record dependency forms, that parent-supplied vars resolve at the correct precedence level, and that provenance is correctly tagged as `FromParent`.

Build verification (all milestones) ensures that every existing call site has been updated and the compiler is satisfied.

End-to-end verification (Milestone 5) uses the real `exec-plan` / `claude-skill-link` module pair to confirm that the motivating use case works: no more unwanted prompts when the parent module supplies the dependency's required variable.

To verify provenance, run:

    seihou vars exec-plan --explain --var project.name=test

Expected output should show `skill.name` with source `[parent: exec-plan]` for the `claude-skill-link` module.


## Idempotence and Recovery

All changes are additive. The new `Dependency` type extends the existing `Module` type, and the decoder is backward-compatible with existing modules that use bare string dependencies. If a milestone fails partway through, the changes can be reverted with `git checkout .` and retried. No database migrations or destructive operations are involved.

The Dhall decoder change is the most sensitive piece: if it breaks, no modules can be loaded. To mitigate this, Milestone 1 includes verifying that existing test fixtures still decode correctly before proceeding.


## Interfaces and Dependencies

No new external library dependencies are required. The change uses existing dhall-haskell decoder combinators and Haskell standard library types.

In `seihou-core/src/Seihou/Core/Types.hs`, define:

    data Dependency = Dependency
      { depModule :: ModuleName,
        depVars :: Map VarName Text
      }
      deriving stock (Eq, Show, Generic)

    simpleDep :: ModuleName -> Dependency

    depModuleNames :: [Dependency] -> [ModuleName]

In `seihou-core/src/Seihou/Dhall/Eval.hs`, define:

    dependencyDecoder :: Decoder Dependency

In `seihou-core/src/Seihou/Composition/Resolve.hs`, define:

    collectParentVars :: [(Module, FilePath)] -> Map ModuleName (Map VarName (Text, ModuleName))

In `seihou-core/src/Seihou/Core/Variable.hs`, update:

    resolveVariables ::
      [VarDecl] ->
      Map VarName Text ->
      Map Text Text ->
      Text ->
      Text ->
      Map VarName Text ->
      Map VarName Text ->
      Map VarName Text ->
      Map VarName Text ->
      Map VarName (Text, ModuleName) ->   -- parent-supplied vars
      Either [VarError] (Map VarName ResolvedVar)
