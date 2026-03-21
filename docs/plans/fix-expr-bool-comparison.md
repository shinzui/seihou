# Fix Bool Value Comparison in Conditional Expressions

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

When a module step uses a `when` condition like `Eq intentions.enabled true` to gate on a bool-typed variable, the condition silently evaluates to `False` even when the variable is set to `true`. This means conditional steps (including patch operations like `append-section`) are skipped entirely, breaking module composition for any feature gated on a boolean variable.

After this fix, `Eq var true` and `Eq var false` conditions will correctly match against bool-typed variables resolved as `VBool True` or `VBool False`. A user writing `when = Some "Eq intentions.enabled true"` in their module.dhall will see the step execute when the variable is true and skip when it is false, as expected.


## Progress

- [x] Fix `parseBareWord` in `seihou-core/src/Seihou/Core/Expr.hs` to classify `true`/`false` as `VBool` (2026-03-21)
- [x] Update `parseExpr` tests in `seihou-core/test/Seihou/Core/ExprSpec.hs` for new parse behavior (2026-03-21)
- [x] Add `evalExpr` tests that exercise `Eq` with `VBool` variables (2026-03-21)
- [x] Run the full test suite and confirm all tests pass — 605/605 passed (2026-03-21)
- [ ] Rebuild seihou CLI and verify fix end-to-end with agent-seihou registry


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Fix in the expression parser (`parseBareWord`) rather than in `evalExpr`.
  Rationale: The parser is the correct place to assign types to literal values. The bare words `true` and `false` have unambiguous boolean semantics — they are already recognized as boolean literals in `parseAtom`. Having `parseBareWord` return `VText "true"` when the user writes `Eq var true` is inconsistent with the rest of the expression language. Fixing in `evalExpr` (e.g., normalizing both sides) would add runtime complexity and mask the real issue: the parser is producing the wrong AST node. Additionally, integer bare words should also be recognized as `VInt` for consistency, but that is out of scope for this fix; a follow-up can address it.
  Date: 2026-03-21


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Seihou's conditional expression system lives in two files. The parser in `seihou-core/src/Seihou/Core/Expr.hs` converts a text expression like `Eq intentions.enabled true` into an AST (`Expr` type from `seihou-core/src/Seihou/Core/Types.hs`). The evaluator in the same file walks the AST against a `Map VarName VarValue` to produce a `Bool`.

The `VarValue` algebraic type has four constructors: `VText Text`, `VBool Bool`, `VInt Int`, and `VList [VarValue]`. When variables are resolved, the `coerceValue` function in `seihou-core/src/Seihou/Core/Variable.hs` converts raw text inputs to the appropriate `VarValue` based on the declared type. A bool-typed variable with value `"true"` is coerced to `VBool True`.

The `Expr` type for equality is `ExprEq VarName VarValue`. When parsing `Eq var true`, the parser calls `parseValue` which delegates to `parseBareWord` (since `true` is not quoted). `parseBareWord` unconditionally wraps any bare word in `VText`, producing `VText "true"`. The evaluator then does a direct `==` comparison: `Map.lookup name vars == Just val`. Since `VBool True /= VText "true"`, the comparison fails.

The existing test suite in `seihou-core/test/Seihou/Core/ExprSpec.hs` has tests for `ExprEq` with `VText` values but none that exercise boolean variable comparison. The test vars map does include `("enabled", VBool True)` but no test case uses it with `ExprEq`.


## Plan of Work

The fix is contained entirely within `seihou-core/src/Seihou/Core/Expr.hs`. The `parseBareWord` function (lines 164-168) needs to recognize `true` and `false` as boolean values before falling through to the text case.

The change is small: add a classification step after extracting the bare word that checks for `"true"` and `"false"` and returns the corresponding `VBool` constructor. All other bare words continue to produce `VText` as before.

The test file `seihou-core/test/Seihou/Core/ExprSpec.hs` needs two kinds of additions. First, the existing `parseExpr` test for `"Eq license MIT"` (which asserts `VText "MIT"`) remains correct — only `true` and `false` change behavior. A new parse test should verify that `"Eq enabled true"` produces `ExprEq "enabled" (VBool True)` and `"Eq enabled false"` produces `ExprEq "enabled" (VBool False)`. Second, new `evalExpr` tests should verify that `ExprEq "enabled" (VBool True)` evaluates to `True` against the existing vars map (which already contains `("enabled", VBool True)`), and that `ExprEq "enabled" (VBool False)` evaluates to `False`.


## Concrete Steps

All commands are run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Milestone 1: Fix the parser.

Edit `seihou-core/src/Seihou/Core/Expr.hs`, replacing the `parseBareWord` function. The current implementation is:

    parseBareWord :: Parser VarValue
    parseBareWord input =
      let (word, rest) = T.break (\c -> c == ' ' || c == ')' || c == '&' || c == '|') input
       in if T.null word
            then Left "expected value"
            else Right (VText word, rest)

Replace with:

    parseBareWord :: Parser VarValue
    parseBareWord input =
      let (word, rest) = T.break (\c -> c == ' ' || c == ')' || c == '&' || c == '|') input
       in if T.null word
            then Left "expected value"
            else Right (classifyBareWord word, rest)
      where
        classifyBareWord "true" = VBool True
        classifyBareWord "false" = VBool False
        classifyBareWord w = VText w

Milestone 2: Update and add tests.

Edit `seihou-core/test/Seihou/Core/ExprSpec.hs`. In the `parseExpr` describe block, add after the existing "parses Eq with bare word value" test:

    it "parses Eq with bare word true as VBool" $ do
      parseExpr "Eq enabled true"
        `shouldBe` Right (ExprEq "enabled" (VBool True))

    it "parses Eq with bare word false as VBool" $ do
      parseExpr "Eq enabled false"
        `shouldBe` Right (ExprEq "enabled" (VBool False))

In the `evalExpr` describe block, add after the existing "evaluates ExprEq when values differ" test:

    it "evaluates ExprEq with VBool True" $ do
      evalExpr vars (ExprEq "enabled" (VBool True)) `shouldBe` True

    it "evaluates ExprEq with VBool False against VBool True" $ do
      evalExpr vars (ExprEq "enabled" (VBool False)) `shouldBe` False

Milestone 3: Run the test suite.

    cabal test seihou-core

Expected: all tests pass, including the new ones. The existing test "parses Eq with bare word value" (`Eq license MIT`) should still pass because `MIT` is neither `true` nor `false`.


## Validation and Acceptance

Run the full test suite from the repository root:

    cabal test all

All tests must pass. In particular:

1. `Seihou.Core.Expr / parseExpr / parses Eq with bare word value` — still produces `VText "MIT"` (regression check).
2. `Seihou.Core.Expr / parseExpr / parses Eq with bare word true as VBool` — produces `VBool True`.
3. `Seihou.Core.Expr / parseExpr / parses Eq with bare word false as VBool` — produces `VBool False`.
4. `Seihou.Core.Expr / evalExpr / evaluates ExprEq with VBool True` — returns `True`.
5. `Seihou.Core.Expr / evalExpr / evaluates ExprEq with VBool False against VBool True` — returns `False`.

After the fix, return to the `agent-seihou` registry and re-test:

    cd /Users/shinzui/Keikaku/bokuno/agent-seihou
    seihou run exec-plan --dry-run --var skill.name=exec-plan --var intentions.enabled=true

The `append-section` step for `INTENTIONS-SECTION.md` should now appear in the plan and the generated SKILL.md should contain the "Intention Tracking" section.


## Idempotence and Recovery

All changes are additive. The parser fix is a pure function change with no side effects. Running the tests multiple times is safe. If the fix is incorrect, reverting the single function `parseBareWord` restores the original behavior.


## Interfaces and Dependencies

No new dependencies or interfaces. The change is internal to the `parseBareWord` function in `seihou-core/src/Seihou/Core/Expr.hs`. The function signature `Parser VarValue` (i.e., `Text -> Either Text (VarValue, Text)`) is unchanged. The `VBool` constructor already exists in the `VarValue` type and is used elsewhere (variable resolution, config display). The `ExprEq` constructor already accepts any `VarValue`.
