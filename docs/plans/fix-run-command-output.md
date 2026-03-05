# Fix Run Command Output Format

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

The `seihou run` command generates files from modules but its output does not match the design specification. After this change:

1. The plan view (shown in `--dry-run`, `--diff`, and before execution in normal mode) uses the design spec format: `Generation Plan (module1 + module2):` header, a Variables section showing resolved values, bracket-style status tags (`[new]`, `[modified]`), module attribution on operations (`(template, haskell-base)`), and a clean summary (`6 files to write, 0 conflicts`).

2. Normal mode shows the plan and asks `Proceed? [Y/n]` before executing, matching the design spec flow. The prompt is skipped in non-interactive situations (piped stdin) and when `--force` is used.

3. Operations include which module produced each file, so multi-module compositions clearly show provenance.

A user running `seihou run haskell-base --dry-run --var project.name=hello` will see output like:

    Generation Plan (haskell-base):

      Variables:
        project.name     = "hello"
        project.version  = "0.1.0.0"

      Operations:
        [new]  README.md       (template, haskell-base)
        [new]  hello.cabal     (dhall-text, haskell-base)
        [new]  src/Lib.hs      (template, haskell-base)

      3 files to write, 0 conflicts


## Progress

- [x] M1-1: Update `mergeOperations` to return file ownership map (2026-03-04)
- [x] M1-2: Add `previewModule` field to `FilePreview` and update `buildPreview` (2026-03-04)
- [x] M1-3: Update `renderPreviewPlain` to use bracket tags, module attribution, column alignment (2026-03-04)
- [x] M1-4: Update `renderPreviewColor` (in `Style.hs`) to use bracket tags, module attribution, column alignment (2026-03-04)
- [x] M1-5: Build — `cabal build all` (2026-03-04)
- [x] M2-1: Add `formatPlanView` function to `Preview.hs` (header + variables + operations + summary) (2026-03-04)
- [x] M2-2: Update `handleRun` dry-run path to use `formatPlanView` (2026-03-04)
- [x] M2-3: Update `handleRun` normal path — show plan, add `Proceed? [Y/n]` prompt (2026-03-04)
- [x] M2-4: Update `formatDiff` to use bracket tags and module attribution (2026-03-04)
- [x] M2-5: Build — `cabal build all` (2026-03-04)
- [x] M3-1: Update `PreviewSpec.hs` tests for new format (2026-03-04)
- [x] M3-1b: Update `PlanSpec.hs` tests for triple return from `mergeOperations` (2026-03-04)
- [x] M3-1c: Update `CompositionSpec.hs` tests for triple return from `compileComposedPlan` (2026-03-04)
- [x] M3-2: Add tests for `formatPlanView` (5 tests: header, multi-module header, variables present, variables absent, summary counts) (2026-03-04)
- [x] M3-3: Build and test — `cabal test all` passes (484/484) (2026-03-04)


## Surprises & Discoveries

- `DiffResult` was not imported in `Style.hs` — needed to add it to the import of `Seihou.Core.Types` for the `formatPlanViewColor` type signature.
- Test files `CompositionSpec.hs` also needed updating for the `compileComposedPlan` triple return — not just `PlanSpec.hs`.
- The `renderPlainLine` function does not pad status tags to align them; only file paths are column-aligned. Test assertions initially assumed tag padding.


## Decision Log

- Decision: Return file ownership map from `mergeOperations` rather than adding `ModuleName` to `WriteFileOp`/`CopyFileOp` constructors.
  Rationale: Adding `ModuleName` to `WriteFileOp` and `CopyFileOp` would require updating every call site that constructs these operations (in `compilePlan`, `compileComposedPlan`, tests, etc.) and would change a core type that many modules depend on. Returning the ownership map as a third element of the `mergeOperations` result is minimally invasive — `mergeOperations` already tracks this information internally in its `fileOwner :: Map FilePath ModuleName` accumulator. The only consumers that need the map are the preview/plan-view formatters.
  Date: 2026-03-04

- Decision: Use `hIsTerminalDevice stdin` to detect interactive mode for the `Proceed?` prompt, rather than adding a new `--yes` flag.
  Rationale: The design spec shows `Proceed? [Y/n]` as part of normal mode output but does not define a `--yes` flag. The existing `--force` flag already bypasses conflict resolution. Checking whether stdin is a terminal is the standard Unix approach — when piped, skip the prompt and proceed. This avoids adding CLI flags beyond the spec.
  Date: 2026-03-04

- Decision: For single-module runs, `buildPreview` receives a single-entry ownership map from `handleRun` rather than requiring `mergeOperations`.
  Rationale: In single-module runs, `compileComposedPlan` still calls `mergeOperations` internally, so the ownership map flows naturally. However, `compilePlan` (the per-module planner) returns `[Operation]` without module names. The composed plan path always goes through `mergeOperations` which tracks ownership, so the flow is: `compileComposedPlan` → `mergeOperations` → returns `(ops, warnings, ownerMap)` → threaded to preview. This works for both single and multi-module runs without special-casing.
  Date: 2026-03-04

- Decision: Drop the `previewVerb` field from `FilePreview` since the design spec format does not include verbs.
  Rationale: The design spec shows `[new]  README.md  (template, haskell-base)` — no "write", "copy", or "patch" verb. The verb was a detail of the current (non-spec) format. Removing it simplifies the type and the rendering code. The strategy annotation (`template`, `copy`, `dhall-text`, `structured`) already communicates what type of operation is happening.
  Date: 2026-03-04


## Outcomes & Retrospective

All milestones completed. 484 tests pass (5 new `formatPlanView` tests added).

**Changes made:**
- `mergeOperations` returns `(ops, warnings, ownerMap)` triple — file ownership threaded to preview
- `PreviewLine.FilePreview` lost `previewVerb`, gained `previewModule :: Maybe ModuleName`
- `buildPreview` accepts ownership map; preview lines carry module attribution
- `renderPreviewPlain` / `renderPreviewColor` use bracket tags (`[new]`, `[modified]`, etc.) and column-aligned paths with `(strategy, module)` annotations
- `formatPlanView` (plain) and `formatPlanViewColor` (ANSI) produce the design spec format: header, variables, operations, summary
- `handleRun` dry-run and normal paths use `formatPlanViewColor`; normal mode shows plan then prompts `Proceed? [Y/n]` (skipped when non-interactive or `--force`)
- `formatDiff` uses bracket tags with module attribution

**Files changed (source):** Plan.hs, Preview.hs, Style.hs, Run.hs
**Files changed (tests):** PlanSpec.hs, PreviewSpec.hs, CompositionSpec.hs


## Context and Orientation

Seihou is a composable project scaffolding tool written in Haskell (GHC 9.12.2, GHC2024). It uses a multi-package Cabal workspace: `seihou-core` (library) and `seihou-cli` (executable).

The `run` command generates files from one or more modules. Its code spans several layers:

The CLI handler at `seihou-cli/src/Seihou/CLI/Run.hs` contains `handleRun`, which orchestrates: loading modules, resolving variables, compiling the plan, computing the diff, and dispatching to dry-run, diff, or execution paths. The dry-run path (lines 141–145) prints a header and calls `renderPreviewColor`. The diff path (line 148) calls `formatDiff`. The execution path (lines 150+) resolves conflicts, executes operations, and prints a summary. There is no confirmation prompt before execution in the current implementation.

The preview engine at `seihou-core/src/Seihou/Engine/Preview.hs` defines `PreviewLine` (a sum type with `FilePreview`, `DirPreview`, `CommandPreview`, `OrphanPreview` constructors), `buildPreview` (converts operations + diff into preview lines), and `renderPreviewPlain` (renders to text). `FilePreview` has fields: `previewStatus :: FileStatus`, `previewVerb :: Text`, `previewPath :: FilePath`, `previewAnnotation :: Text`. The status symbols are `+`, `~`, `=`, `!`, `-` in the current format.

The color renderer at `seihou-cli/src/Seihou/CLI/Style.hs` contains `renderPreviewColor` (renders preview lines with ANSI codes) and a `summaryLine` helper that produces `"N new, M modified, N unchanged, N conflicts, N orphaned"`.

The composition plan compiler at `seihou-core/src/Seihou/Composition/Plan.hs` contains `compileComposedPlan` which calls `mergeOperations`. The `mergeOperations` function takes `[(ModuleName, [Operation])]` and returns `([Operation], [CompositionWarning])`. Internally it tracks `fileOwner :: Map FilePath ModuleName` to detect overwrites, but this map is not returned — it is discarded after generating warnings.

The `Operation` type at `seihou-core/src/Seihou/Core/Types.hs` (lines 170–194) has five constructors: `WriteFileOp` (dest, content, strategy), `CreateDirOp` (path), `CopyFileOp` (src, dest), `RunCommandOp` (command, workdir), `PatchFileOp` (dest, content, patchOp, strategy, moduleName). Only `PatchFileOp` carries a `ModuleName`.

The design specification at `docs/dev/design/proposed/cli-commands.md` (lines 150–170) defines the plan view format with a `Generation Plan (...)` header, Variables section, Operations section with bracket tags and module attribution, a summary line, and a `Proceed? [Y/n]` prompt.

The `RunOpts` type at `seihou-cli/src/Seihou/CLI/Commands.hs` has nine fields including `runDryRun`, `runDiff`, `runForce`, `runVerbose`. There is no `runYes` or `runNonInteractive` field.

The test suite at `seihou-core/test/Seihou/Engine/PreviewSpec.hs` has tests for `buildPreview` (9 tests covering status classification, orphan handling, verbs, annotations) and `renderPreviewPlain` (3 tests checking exact output strings). These tests reference the current format (`"  + write  README.md  (template)"`) and will need updating.


## Plan of Work

### Milestone 1: Module attribution and preview format

This milestone threads module ownership through the preview system and updates the line-level rendering to use the design spec format. At the end, `renderPreviewPlain` and `renderPreviewColor` produce bracket tags and module attribution, but the plan-level structure (header, variables, summary) is not yet changed.

In `seihou-core/src/Seihou/Composition/Plan.hs`, update `mergeOperations` to return a triple `([Operation], [CompositionWarning], Map FilePath ModuleName)` instead of a pair. The internal `go` function already accumulates `fileOwner :: Map FilePath ModuleName`. Return it as the third element. Update `compileComposedPlan` to pass through this new return value.

In `seihou-core/src/Seihou/Engine/Preview.hs`, make these changes. Remove the `previewVerb` field from `FilePreview` and add `previewModule :: Maybe ModuleName`. Update `buildPreview` to accept a `Map FilePath ModuleName` parameter and pass it to `opToPreview`. In `opToPreview`, look up the module name from the ownership map and set `previewModule`. Update `renderPreviewPlain` and `renderPlainLine` to produce bracket-style status tags (`[new]`, `[modified]`, `[unchanged]`, `[conflict]`, `[orphaned]`), include module name in annotations (`(template, haskell-base)`), and column-align the output. Update `statusSymbol` to produce bracket tags.

In `seihou-cli/src/Seihou/CLI/Style.hs`, update `renderColorLine` and `statusStyle` to use the new bracket tags and module annotations, with column alignment.

In `seihou-cli/src/Seihou/CLI/Run.hs`, update the `handleRun` call to `compileComposedPlan` to destructure the triple return value. Thread the ownership map to `buildPreview`. Update `formatDiff` to accept the ownership map and include module names.


### Milestone 2: Plan view structure and confirmation prompt

This milestone adds the full plan view format (header, variables, operations, summary) and a confirmation prompt before execution. At the end, `--dry-run` shows the complete plan view, and normal mode asks `Proceed? [Y/n]`.

In `seihou-core/src/Seihou/Engine/Preview.hs`, add a new function `formatPlanView` that takes the module names (for the header), resolved variables (for the Variables section), preview lines (for Operations), and diff result (for the summary). It produces the complete plan text: `Generation Plan (module1 + module2):`, a blank line, the Variables block (aligned key-value pairs with 4-space indent), a blank line, the Operations block (rendered preview lines), a blank line, and the summary (`N files to write, M conflicts`). Export `formatPlanView` from the module.

In `seihou-cli/src/Seihou/CLI/Run.hs`, update the dry-run path: replace the `"Dry run — plan preview:"` header and `renderPreviewColor` call with a call to `formatPlanView`, passing module names, resolved variables, preview lines, and diff result. For color output, wrap `formatPlanView` in a color-aware variant or add a `formatPlanViewColor` in `Style.hs`.

For the normal execution path, add plan display and confirmation prompt. After computing the diff and before resolving conflicts: build the plan view, print it, and prompt `Proceed? [Y/n]`. Use `hIsTerminalDevice stdin` to detect interactive mode — if not interactive (piped), proceed without prompting. If `--force` is set, also skip the prompt. Read a line from stdin; if the response is empty, "y", or "Y", proceed; otherwise exit with code 3 (user aborted). Import `System.IO (hIsTerminalDevice, stdin)`.

Update `formatDiff` similarly: use bracket tags and include module attribution from the ownership map.


### Milestone 3: Tests

This milestone updates existing `PreviewSpec.hs` tests and adds new tests for `formatPlanView`. At the end, all tests pass.

In `seihou-core/test/Seihou/Engine/PreviewSpec.hs`, update the `buildPreview` tests to pass the ownership map parameter. Update `renderPreviewPlain` tests to check for the new bracket-tag format instead of the old `+ write` format. Add tests for `formatPlanView` that verify the header, variables section, operations section, and summary line.


## Concrete Steps

**Working directory**: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

**Step 1** (M1): Edit `seihou-core/src/Seihou/Composition/Plan.hs`:
- Update `mergeOperations` return type to `([Operation], [CompositionWarning], Map FilePath ModuleName)`
- Return `fileOwner` as the third element from `go`
- Update `compileComposedPlan` to pass through the triple

**Step 2** (M1): Edit `seihou-core/src/Seihou/Engine/Preview.hs`:
- Remove `previewVerb` from `FilePreview`, add `previewModule :: Maybe ModuleName`
- Update `buildPreview` signature to accept `Map FilePath ModuleName`
- Update `opToPreview` to set `previewModule` from the map
- Update `renderPreviewPlain` and `renderPlainLine` for bracket tags, module attribution, column alignment
- Update `statusSymbol` to produce `[new]`, `[modified]`, etc.

**Step 3** (M1): Edit `seihou-cli/src/Seihou/CLI/Style.hs`:
- Update `renderColorLine` for bracket tags and module attribution
- Update `statusStyle` to return bracket-format prefixes
- Update `summaryLine` format

**Step 4** (M1): Edit `seihou-cli/src/Seihou/CLI/Run.hs`:
- Destructure triple from `compileComposedPlan`
- Thread ownership map to `buildPreview`
- Update `formatDiff` to accept and use ownership map

**Step 5** (M1): Build:

    cabal build all

Expected: compiles cleanly.

**Step 6** (M2): Edit `seihou-core/src/Seihou/Engine/Preview.hs`:
- Add `formatPlanView :: [ModuleName] -> Map VarName VarValue -> [PreviewLine] -> DiffResult -> Text`
- Export `formatPlanView`

**Step 7** (M2): Edit `seihou-cli/src/Seihou/CLI/Style.hs`:
- Add `formatPlanViewColor :: Bool -> [ModuleName] -> Map VarName VarValue -> [PreviewLine] -> DiffResult -> Text`

**Step 8** (M2): Edit `seihou-cli/src/Seihou/CLI/Run.hs`:
- Update dry-run path to use `formatPlanViewColor`
- Add plan display + `Proceed? [Y/n]` prompt in normal execution path
- Add `hIsTerminalDevice` check for non-interactive detection
- Update `formatDiff` for bracket tags

**Step 9** (M2): Build:

    cabal build all

Expected: compiles cleanly.

**Step 10** (M3): Edit `seihou-core/test/Seihou/Engine/PreviewSpec.hs`:
- Update `buildPreview` tests to pass ownership map parameter
- Update `renderPreviewPlain` tests for new bracket format
- Add `formatPlanView` tests

**Step 11** (M3): Build and run tests:

    cabal build all && cabal test all

Expected: all tests pass.


## Validation and Acceptance

### Automated

    cabal test all

All existing tests pass with updated assertions. The `renderPreviewPlain` tests verify bracket notation output and module attribution. New `formatPlanView` tests verify the header, variables section, operations listing, and summary line.

### Manual acceptance

Dry-run a module:

    seihou run <module> --dry-run --var project.name=hello

Expected: plan view matching design spec format:

    Generation Plan (<module>):

      Variables:
        project.name     = "hello"
        project.version  = "0.1.0.0"

      Operations:
        [new]  README.md       (template, <module>)
        [new]  hello.cabal     (dhall-text, <module>)

      2 files to write, 0 conflicts

Show diff:

    seihou run <module> --diff --var project.name=hello

Expected: bracket-tagged file list with module attribution.

Normal mode (if a module is available):

    seihou run <module> --var project.name=hello

Expected: plan view shown, then `Proceed? [Y/n]` prompt. Typing `n` exits with code 3. Typing `y` or Enter proceeds with execution.


## Idempotence and Recovery

All steps are safe to repeat. The changes modify existing formatting functions and add new ones. If a step fails partway, `git checkout` on the affected files reverts to the previous working state.


## Interfaces and Dependencies

No new external dependencies.

In `seihou-core/src/Seihou/Composition/Plan.hs`, the updated signature:

    mergeOperations :: [(ModuleName, [Operation])] -> ([Operation], [CompositionWarning], Map FilePath ModuleName)

In `seihou-core/src/Seihou/Engine/Preview.hs`, the updated types and functions:

    data PreviewLine
      = FilePreview
          { previewStatus :: FileStatus,
            previewPath :: FilePath,
            previewAnnotation :: Text,
            previewModule :: Maybe ModuleName
          }
      | DirPreview FilePath
      | CommandPreview Text
      | OrphanPreview FilePath ModuleName

    buildPreview :: [Operation] -> Maybe DiffResult -> Map FilePath ModuleName -> [PreviewLine]

    formatPlanView :: [ModuleName] -> Map VarName VarValue -> [PreviewLine] -> DiffResult -> Text

In `seihou-cli/src/Seihou/CLI/Style.hs`, the new function:

    formatPlanViewColor :: Bool -> [ModuleName] -> Map VarName VarValue -> [PreviewLine] -> DiffResult -> Text

In `seihou-cli/src/Seihou/CLI/Run.hs`, the handler signature does not change:

    handleRun :: RunOpts -> IO ()
