# Refactor Nested Conditionals to Idiomatic Haskell

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this refactoring, the seihou codebase will use idiomatic Haskell patterns — guards, `Data.Bifunctor.first`, helper extraction, and `<|>` / `asum` — in place of deeply nested `if/then/else` chains and manual `case result of Left/Right` error propagation. The code will be shorter, flatter, and easier to read without changing any observable behavior.

A developer reading the codebase will find consistent patterns: guards for multi-branch conditionals, `first` for mapping the left side of `Either`, extracted helpers for repeated logic, and `maybe`/`asum` for cascading lookups.


## Progress

- [x] M1: Validation helpers — `checkSafeDestinations`, `checkCommandSafety`, `checkDestVarRefs` in `seihou-core/src/Seihou/Core/Module.hs` (2026-03-21)
- [x] M1: Path validation in `validateEntry` in `seihou-core/src/Seihou/Core/Registry.hs` (2026-03-21)
- [x] M2: `evalConfigFileIfExists` in `seihou-core/src/Seihou/Dhall/Config.hs` — use `first` instead of case on Either (2026-03-21)
- [x] M2: `evalConfigFile` in `seihou-core/src/Seihou/Dhall/Config.hs` — extract `isEmptyConfig` predicate (2026-03-21)
- [x] M3: `popInput` helper extraction in `seihou-core/src/Seihou/Effect/ConsolePure.hs` (2026-03-21)
- [x] M4: `resolveContext` cascading lookup in `seihou-core/src/Seihou/Core/Context.hs` (2026-03-21)
- [x] M4: `readProjectContext` / `readGlobalDefaultContext` — flatten `if exists` nesting (2026-03-21)
- [x] M5: `loadComposition` in `seihou-core/src/Seihou/Composition/Resolve.hs` — flatten nested Either cascades (2026-03-21)
- [x] Build and test validation after each milestone (2026-03-21)


## Surprises & Discoveries

- `Dhall/Config.hs` already imports `Seihou.Prelude`, contrary to the plan's note that it doesn't. No explicit `Data.Bifunctor` import was needed.
- `hoistEither` is not exported by `Control.Monad.Trans.Except` in transformers 0.6.1.2. Used `ExceptT . pure` instead.
- `<|>` is not in scope with GHC2024 by default; required explicit `import Control.Applicative ((<|>))` in Context.hs.
- `transformers` needed to be added as an explicit build-depends in the cabal file despite being a transitive dependency — GHC/Cabal requires direct dependency declarations.


## Decision Log

- Decision: Scope this plan to clear, mechanical refactorings only — not architectural changes to `Resolve.hs`'s deeper `resolveWithPrompts` function.
  Rationale: The `resolveWithPrompts` function (lines 147-245) has complex interactive logic that goes beyond simple if/else flattening. Refactoring it meaningfully would require design decisions about error handling strategy (e.g., introducing `ExceptT`), which is a separate concern.
  Date: 2026-03-21

- Decision: Do not refactor `Main.hs` dispatch. The nested `case` for `Agent` subcommands is standard optparse-applicative style and only one level deep.
  Rationale: The nesting in `Main.hs` is shallow and idiomatic for CLI dispatch. Extracting a `handleAgent` helper adds a function with no real clarity gain.
  Date: 2026-03-21

- Decision: Do not refactor `Engine/Diff.hs` `classifyFile`. The 3-way tuple pattern match is already the idiomatic way to handle product-type case analysis in Haskell.
  Rationale: The cases in `classifyFile` are distinct behaviors keyed on `(Maybe, Maybe, Bool)` — this is a natural use of pattern matching, not a nested conditional.
  Date: 2026-03-21

- Decision: Re-export `first` from `Data.Bifunctor` via `Seihou.Prelude` so all modules get it for free.
  Rationale: `first` is used frequently across the refactoring (ConfigReaderInterp, Dhall/Config, and potentially others). Adding it to the prelude avoids repetitive per-module imports and establishes it as a standard tool in the codebase.
  Date: 2026-03-21


## Outcomes & Retrospective

All five milestones completed successfully. All 601 tests pass with no regressions. Both `seihou-core` and `seihou-cli` compile cleanly.

Summary of changes:
- **Module.hs**: 3 validation functions refactored from nested lambdas with `if/else` to guard-based named helpers and list comprehensions.
- **Registry.hs**: `validateEntry` extracted `checkName` and `checkPath` guard-based helpers.
- **Config.hs**: `evalConfigFileIfExists` uses `first formatError <$> try ...`; `evalConfigFile` extracts `isEmptyConfig` predicate.
- **ConsolePure.hs**: Duplicated input-queue pop logic extracted into `popInput` helper.
- **Context.hs**: `resolveContext` uses `<|>` for pure source combination; `readTextFileMaybe` shared helper replaces duplicated file-reading logic.
- **Resolve.hs**: `loadComposition` flattened from 3-level nested `case` to linear `ExceptT` pipeline.

One new dependency added: `transformers` (explicit, was already transitive).


## Context and Orientation

The seihou codebase is a Haskell project using GHC 9.12.2 with the GHC2024 language edition. It uses the `effectful` library for effects. The workspace has two packages: `seihou-core` (library) and `seihou-cli` (executable).

The recently refactored `seihou-core/src/Seihou/Effect/ConfigReaderInterp.hs` serves as the style reference. That refactoring replaced nested `if/else` with guards and a `loadNamespacedConfig` helper, and replaced `case result of Left err -> ...; Right m -> ...` with `first (ConfigParseError path) <$> evalConfigFileIfExists path`.

`Data.Bifunctor.first` is re-exported from `Seihou.Prelude` (added in `seihou-core/src/Seihou/Prelude.hs`), so modules that import `Seihou.Prelude` do not need an explicit `import Data.Bifunctor (first)`. Any module in this plan that already imports `Seihou.Prelude` gets `first` for free.

Key terms:

- **Guard**: Haskell syntax `| condition = expression` that replaces `if/then/else` chains with flat, readable clauses.
- **`Data.Bifunctor.first`**: `first f (Left x) = Left (f x)` and `first f (Right y) = Right y`. Used to map an error-wrapping function over `Either` without a manual case expression. Available via `Seihou.Prelude`.
- **`asum`**: From `Data.Foldable`, tries alternatives in order and returns the first `Just`. Useful for cascading lookups like "try CLI flag, then env var, then file."


## Plan of Work

The work is organized into five milestones, each touching one or two files with related patterns. Every milestone is independently verifiable by building the project and running the test suite.


### Milestone 1: Validation Guards in Module.hs and Registry.hs

This milestone replaces `if/then/else` chains in path and command validation functions with guards and extracted helpers.

**Module.hs changes (lines 181-230):**

`checkSafeDestinations` (line 183) currently uses a nested `if/else` inside a lambda passed to `concatMap`. Replace the lambda with a named local function using guards:

    checkSafeDestinations m = concatMap checkDest m.steps
      where
        checkDest s
          | T.isPrefixOf "/" s.dest = ["step destination must be relative: " <> s.dest]
          | ".." `T.isInfixOf` s.dest = ["step destination must not contain '..': " <> s.dest]
          | otherwise = []

`checkDestVarRefs` (line 198) uses a nested `concatMap` with an inner `if/else`. Replace with a guard-based helper:

    checkDestVarRefs m =
      let varNames = Set.fromList (map (\d -> d.name.unVarName) m.vars)
       in concatMap (checkStep varNames) m.steps
      where
        checkStep varNames s =
          [ "step destination references undeclared variable: " <> ref
          | ref <- extractPlaceholders s.dest
          , not (Set.member ref varNames)
          ]

This uses a list comprehension with a guard, which is the idiomatic Haskell way to filter-and-map.

`checkCommandSafety` (line 214) uses `if/then/else` for the empty-run check and a `case/guard` combo for `workDir`. Extract a helper:

    checkCommandSafety m = concatMap checkCmd m.commands
      where
        checkCmd c = checkEmptyRun c <> checkWorkDir c.workDir

        checkEmptyRun c
          | T.null (T.strip c.run) = ["command text must not be empty"]
          | otherwise = []

        checkWorkDir Nothing = []
        checkWorkDir (Just wd)
          | T.isPrefixOf "/" wd = ["command workDir must be relative: " <> wd]
          | ".." `T.isInfixOf` wd = ["command workDir must not contain '..': " <> wd]
          | otherwise = []

**Registry.hs changes (lines 82-98):**

`validateEntry` uses inline `if/then/else` for path validation. Extract helpers matching the Module.hs pattern:

    validateEntry repoRoot entry = do
      let nameText = entry.name.unModuleName
          nameErrors = checkName nameText
          pathText = T.pack entry.path
          pathErrors = checkPath pathText
      let moduleDhall = repoRoot </> entry.path </> "module.dhall"
      fileExists <- doesFileExist moduleDhall
      let fileErrors =
            if fileExists
              then []
              else ["registry entry '" <> nameText <> "' points to missing module.dhall at " <> pathText]
      pure (nameErrors <> pathErrors <> fileErrors)
      where
        checkName name
          | validModuleName name = []
          | otherwise = ["registry entry name must match [a-z][a-z0-9-]*, got: " <> name]

        checkPath path
          | T.isPrefixOf "/" path = ["registry entry path must be relative: " <> path]
          | ".." `T.isInfixOf` path = ["registry entry path must not contain '..': " <> path]
          | otherwise = []

Note: `fileExists` check stays as `if/then/else` since it depends on an IO result and is only one level deep.

After these edits, run:

    cabal build seihou-core
    cabal test seihou-core


### Milestone 2: Bifunctor.first in Dhall/Config.hs

This milestone applies two small refactorings to `seihou-core/src/Seihou/Dhall/Config.hs`.

**`evalConfigFileIfExists` (line 48):** Replace the `case result of Left/Right` with `first`:

    evalConfigFileIfExists path = do
      exists <- doesFileExist path
      if exists
        then first formatError <$> try (evalConfigFile path)
        else pure (Right Map.empty)
      where
        formatError :: SomeException -> Text
        formatError e = "Error reading config " <> T.pack path <> ": " <> T.pack (show e)

Since `Dhall/Config.hs` does not import `Seihou.Prelude`, it will need `import Data.Bifunctor (first)` added explicitly.

**`evalConfigFile` (line 27):** Extract `isEmptyConfig` predicate for clarity:

    evalConfigFile path = do
      content <- TIO.readFile path
      let stripped = stripDhallComments content
      if isEmptyConfig stripped
        then pure Map.empty
        else input configMapDecoder ("toMap (" <> content <> ")")

    isEmptyConfig :: Text -> Bool
    isEmptyConfig s = s `elem` ["{=}", "{ = }"] || T.null s

After these edits, run:

    cabal build seihou-core
    cabal test seihou-core


### Milestone 3: Extract popInput in ConsolePure.hs

This milestone removes the duplicated "pop from input queue" pattern in `seihou-core/src/Seihou/Effect/ConsolePure.hs`.

The `GetLine` and `Confirm` handlers both do `get`, pattern match on `consoleInputs`, and `modify` to pop the head. Extract a `popInput` helper:

    popInput :: (State ConsoleState :> es') => Eff es' Text
    popInput = do
      s <- get @ConsoleState
      case s.consoleInputs of
        [] -> pure ""
        (x : xs) -> do
          modify @ConsoleState (\st -> st {consoleInputs = xs})
          pure x

Then the handler becomes:

    GetLine -> popInput
    Confirm _prompt -> (`elem` ["y", "yes"]) <$> popInput

After this edit, run:

    cabal build seihou-core
    cabal test seihou-core


### Milestone 4: Flatten Context Resolution in Context.hs

This milestone refactors `seihou-core/src/Seihou/Core/Context.hs` in two ways.

**`resolveContext` (line 25):** The cascading `case/case/case` pattern tries CLI flag, then env var, then project file, then global default. Refactor using a helper that normalizes text sources to `Maybe Text`:

    resolveContext cliFlag envVars =
      case nonEmpty cliFlag <|> nonEmpty (Map.lookup "SEIHOU_CONTEXT" envVars) of
        Just ctx -> pure (Just ctx)
        Nothing -> do
          projectCtx <- readProjectContext
          case projectCtx of
            Just ctx -> pure (Just ctx)
            Nothing -> readGlobalDefaultContext
      where
        nonEmpty (Just t) | not (T.null (T.strip t)) = Just (T.strip t)
        nonEmpty _ = Nothing

The first two sources are pure so we can combine them with `<|>`. The last two are IO-based and stay in do-notation.

**`readProjectContext` and `readGlobalDefaultContext`:** Both follow the same pattern: check file exists, read it, strip whitespace, return `Nothing` if empty. Extract a shared helper:

    readTextFileMaybe :: FilePath -> IO (Maybe Text)
    readTextFileMaybe path = do
      exists <- doesFileExist path
      if exists
        then do
          content <- T.strip <$> TIO.readFile path
          pure $ if T.null content then Nothing else Just content
        else pure Nothing

Then:

    readProjectContext = do
      cwd <- getCurrentDirectory
      readTextFileMaybe (cwd </> ".seihou" </> "context")

    readGlobalDefaultContext = do
      base <- getXdgDirectory XdgConfig "seihou"
      readTextFileMaybe (base </> "default-context")

After these edits, run:

    cabal build seihou-core
    cabal test seihou-core


### Milestone 5: Flatten loadComposition in Resolve.hs

This milestone addresses the 3-level nested `case` on `Either` in `seihou-core/src/Seihou/Composition/Resolve.hs` (lines 30-50).

The function chains three fallible operations: `loadModuleWithDir`, `loadTransitive`, and `topoSort`. Each failure is `pure (Left err)`. This is the classic use case for `ExceptT` or monadic bind on `Either` inside `IO`.

Introduce `runExceptT` to flatten:

    loadComposition searchPaths primary additional = runExceptT $ do
      (primaryMod, primaryDir) <- ExceptT $ loadModuleWithDir searchPaths primary
      let effectiveDeps = primaryMod.dependencies ++ map simpleDep additional
          effectivePrimary = primaryMod {dependencies = nubOrdBy (.depModule) effectiveDeps}
          loaded = Map.singleton primary (effectivePrimary, primaryDir)
      allModules <- ExceptT $ loadTransitive searchPaths loaded (depModuleNames effectivePrimary.dependencies)
      let graph = buildGraph (map fst (Map.elems allModules))
      order <- hoistEither $ topoSort graph
      pure [(m, d) | name <- order, Just (m, d) <- [Map.lookup name allModules]]

This requires adding `import Control.Monad.Trans.Except (ExceptT (..), runExceptT, hoistEither)` — which is available from the `transformers` package (already a dependency via `effectful`).

After this edit, run:

    cabal build seihou-core
    cabal test seihou-core


## Concrete Steps

All commands should be run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Build the project after each milestone:

    cabal build seihou-core

Run the test suite after each milestone:

    cabal test seihou-core

Expected output: all tests pass, no warnings introduced. The `treefmt` pre-commit hook will format code on commit.


## Validation and Acceptance

After all milestones are complete:

1. Run `cabal build all` to ensure both `seihou-core` and `seihou-cli` compile.
2. Run `cabal test seihou-core` — all existing tests must pass with no regressions.
3. Visually inspect each changed file: no `if/then/else` chains deeper than one level remain in the refactored functions, and all `case result of Left/Right` patterns that merely wrap the error have been replaced with `first`.
4. Run `treefmt` to confirm formatting is clean.


## Idempotence and Recovery

Every edit in this plan is a pure refactoring — behavior is unchanged. If a milestone introduces a compilation error, revert with `git checkout -- <file>` and re-apply the edit. Each milestone can be applied and committed independently.


## Interfaces and Dependencies

No new library dependencies are introduced. `Data.Bifunctor` is in `base` and is now re-exported from `Seihou.Prelude`. `Control.Monad.Trans.Except` is in `transformers`, which is already a transitive dependency.

No public API signatures change. All refactored functions keep their existing type signatures. The only new definitions are internal helpers (`popInput`, `readTextFileMaybe`, `isEmptyConfig`, `checkDest`, `checkCmd`, etc.) that are not exported.


## Revision History

- 2026-03-21: Updated plan to reflect that `Data.Bifunctor.first` is now re-exported from `Seihou.Prelude`. Modules importing `Seihou.Prelude` no longer need an explicit `Data.Bifunctor` import. Updated M2 instructions for `Dhall/Config.hs` to note it needs an explicit import since it does not use `Seihou.Prelude`. Added decision to Decision Log.
