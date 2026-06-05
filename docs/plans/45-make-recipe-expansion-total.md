---
id: 45
slug: make-recipe-expansion-total
title: "Make recipe expansion total"
kind: exec-plan
created_at: 2026-06-05T14:34:18Z
intention: "intention_01ktc3hwwneswaz13bvr1tb6f9"
master_plan: "docs/masterplans/5-first-public-release-readiness.md"
---

# Make recipe expansion total

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, an invalid recipe with an empty `modules` list cannot crash `seihou run`. It fails with a normal validation error that tells the author the recipe must list at least one module.

This matters for public release because users can install recipes from git. Invalid third-party input should produce diagnostics, not partial-function exceptions.


## Progress

- [x] Make `expandRecipe` total by removing `head` and `tail`. Completed 2026-06-05: `expandRecipe` now returns `Either [Text] ExpandedRecipe` and pattern matches on the validated module list.
- [x] Ensure discovered recipes are validated before `seihou run` expands them. Completed 2026-06-05: `Seihou.CLI.Run` handles `Left` from `expandRecipe` as a normal invalid-recipe error before loading the composition.
- [x] Add regression tests for empty recipes. Completed 2026-06-05: `Seihou.Composition.RecipeSpec` asserts that empty recipes return `Left ["recipe must list at least one module"]`.
- [x] Confirm the source distribution build no longer emits library partial warnings for `Seihou.Composition.Recipe`. Completed 2026-06-05: `cabal build all` passed without the prior `Seihou.Composition.Recipe` `head`/`tail` warnings.
- [x] Run focused recipe/composition tests and full core/CLI tests as needed. Completed 2026-06-05: focused recipe tests, full core tests, full CLI tests, and `cabal build all` passed.


## Surprises & Discoveries

During the audit, building from source distributions emitted GHC warnings for `head` and `tail` in `seihou-core/src/Seihou/Composition/Recipe.hs`.

As with the earlier plans, the focused test command needs `--pattern` rather than `--match` for this test runner.


## Decision Log

- Decision: Make the expansion function total even if validation should catch bad recipes.
  Rationale: Defensive total functions make command paths safer and remove the possibility that a future caller forgets validation.
  Date: 2026-06-05

- Decision: Validate at `expandRecipe` and handle the error in `seihou run`, rather than changing recipe discovery globally.
  Rationale: The release blocker is the expansion crash in the run path. Keeping validation at expansion makes the function total for every caller while avoiding broader discovery behavior changes for commands that inspect recipe metadata without expanding it.
  Date: 2026-06-05


## Outcomes & Retrospective

Implemented total recipe expansion. `expandRecipe` now returns `Either [Text] ExpandedRecipe`, reuses `validateRecipe`, and pattern matches on the module list instead of calling `head` and `tail`. `seihou run` now reports invalid recipes through the normal logger path before composition loading.

Validation evidence:

```bash
cabal test seihou-core-test --test-options '--pattern "Seihou.Composition.Recipe"'
```

```text
All 5 tests passed (0.00s)
```

```bash
cabal test seihou-core-test
```

```text
All 863 tests passed (0.50s)
```

```bash
cabal test seihou-cli-test
```

```text
All 226 tests passed (24.99s)
```

```bash
cabal build all
```

```text
Build completed successfully with no Seihou.Composition.Recipe partial head/tail warnings.
```


## Context and Orientation

`seihou-core/src/Seihou/Composition/Recipe.hs` defines:

```haskell
expandRecipe :: Recipe -> (ModuleName, [ModuleName], Map VarName Text, [VarDecl], [Prompt])
```

It currently calls `head deps` and `tail deps`. That is safe only if every caller has already checked that `recipe.modules` is non-empty.

`seihou-core/src/Seihou/Core/Recipe.hs` defines `validateRecipe`, which already checks that recipes list at least one module. The risk is that `seihou-core/src/Seihou/Core/Module.hs` discovers a recipe by evaluating `recipe.dhall` and returning `RunnableRecipe r candidate` without validating it, and `seihou-cli/src-exe/Seihou/CLI/Run.hs` expands it directly.


## Plan of Work

Milestone 1 changes the expansion interface. Replace the partial return type with an error-aware type. A suitable signature is:

```haskell
expandRecipe :: Recipe -> Either [Text] (ModuleName, [ModuleName], Map VarName Text, [VarDecl], [Prompt])
```

The `Left` case should reuse `validateRecipe` or at least return the same message for empty modules. Update all callers. The main caller is `seihou-cli/src-exe/Seihou/CLI/Run.hs`.

Milestone 2 validates recipe discovery/run. Decide whether validation belongs in `discoverRunnable` or immediately before expansion in `Run.hs`. Prefer validating at discovery so commands such as `seihou vars RECIPE` and future recipe-aware commands see consistent behavior. If adding validation at discovery changes many call sites, validate at run first and record the tradeoff in the Decision Log.

Milestone 3 adds tests. Add a unit test in `seihou-core/test/Seihou/Composition/RecipeSpec.hs` proving `expandRecipe` returns `Left` for an empty recipe. Add a CLI or module discovery test if practical so `seihou run` does not crash when a recipe has no modules.


## Concrete Steps

Inspect current recipe call sites:

```bash
rg -n "expandRecipe|validateRecipe|RunnableRecipe" seihou-core/src seihou-cli/src seihou-cli/src-exe seihou-core/test seihou-cli/test
```

Run focused tests:

```bash
cabal test seihou-core-test --test-options '--pattern "Seihou.Composition.Recipe"'
```

Run a broader suite if CLI call sites changed:

```bash
cabal test all
```


## Validation and Acceptance

Acceptance requires:

- No production module uses `head` or `tail` in `Seihou.Composition.Recipe`.
- `expandRecipe` handles `Recipe { modules = [] }` without throwing.
- Invalid empty recipes produce a message containing `recipe must list at least one module`.
- Existing recipe tests still pass.

Optional but valuable acceptance: `cabal build all` no longer emits `-Wx-partial` warnings for `Seihou.Composition.Recipe`.


## Idempotence and Recovery

Changing `expandRecipe`'s signature will cause compile errors at every caller until they are updated. Use those compiler errors as a guide. If broad validation-at-discovery changes become too invasive, keep the safer total `expandRecipe` change and validate at `Run.hs`, then record the narrower scope.


## Interfaces and Dependencies

This plan touches `Seihou.Composition.Recipe`, `Seihou.Core.Recipe`, `Seihou.Core.Module`, and `seihou-cli/src-exe/Seihou/CLI/Run.hs`. It does not require external libraries.
