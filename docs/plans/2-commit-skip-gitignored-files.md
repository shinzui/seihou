---
id: 2
slug: commit-skip-gitignored-files
title: "Skip git-ignored files when committing generated output"
kind: exec-plan
created_at: 2026-04-02T13:40:06Z
intention: "intention_01kn76py8wee3bg5j7vvp2a48h"
---


# Skip git-ignored files when committing generated output

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

When a seihou module generates files that are also covered by `.gitignore` (e.g. a
module writes `dist/bundle.js` and also patches `.gitignore` to include `dist/`), the
`--commit` flag fails because `git add` refuses to stage ignored paths. The entire
commit is skipped and the user sees a warning.

After this change, `seihou run --commit` will filter out git-ignored files before
staging, so the commit succeeds with only the trackable files. Files that are both
generated and git-ignored are still written to disk and tracked in the manifest — they
just aren't staged for the commit. This lets module authors freely generate build
artifacts, caches, or environment files alongside committed scaffolding.

**Observable outcome:** `seihou run my-module --commit` succeeds even when the module
generates files matching `.gitignore` patterns. The commit contains only the
non-ignored generated files plus the manifest.


## Progress

- [x] Add `gitCheckIgnore` helper to `Seihou.CLI.Git` (2026-04-02)
- [x] Update `--commit` logic in `Run.hs` to filter files through `gitCheckIgnore` (2026-04-02)
- [x] Add tests for `gitCheckIgnore` in the CLI test suite (2026-04-02)
- [x] Build passes, all existing tests still pass — 660 core + 99 CLI (2026-04-02)
- [ ] Manual verification: module that generates an ignored file commits cleanly


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Use `git check-ignore` to filter files rather than parsing `.gitignore` ourselves.
  Rationale: Git's ignore rules are complex (nested `.gitignore` files, global ignore,
  `info/exclude`, negation patterns). Shelling out to `git check-ignore` gives us
  correct behavior for free, consistent with how we already shell out for all git ops.
  Date: 2026-04-02

- Decision: Filter at `git add` time in the CLI layer, not in the core diff/plan engine.
  Rationale: The core engine should remain git-agnostic. Whether a file is committed is
  a CLI/VCS concern, not a generation concern. The manifest should still track all
  generated files regardless of their git status — this is important for incremental
  diff, orphan detection, and `seihou status`.
  Date: 2026-04-02

- Decision: Do not add a `noCommit` or `gitignore` annotation to the Dhall Step schema.
  Rationale: The existing `.gitignore` mechanism already expresses which files should
  not be tracked. Adding a parallel annotation in the module schema would create a
  second source of truth that could drift. Module authors already patch `.gitignore`
  via `AppendLineIfAbsent` — the right pattern is to generate the file AND add its
  pattern to `.gitignore` in the same module. The commit flow should respect that.
  Date: 2026-04-02


## Outcomes & Retrospective

Implementation complete. The fix is minimal — 2 files changed in the CLI layer:

- `Git.hs`: added `gitCheckIgnore` (8 lines) using `git check-ignore` with graceful
  fallback for error/no-match exit codes.
- `Run.hs`: inserted a filter step between building `filesToStage` and calling `gitAdd`,
  with a skip path when all files are ignored.

No changes to seihou-core, Dhall schema, or manifest format. The core engine remains
git-agnostic. Four new tests cover the `gitCheckIgnore` helper (success, no-match,
error, empty input). All 759 tests pass.


## Context and Orientation

**The bug:** In `seihou-cli/src/Seihou/CLI/Run.hs` (lines 278-300), the `--commit`
flow builds a list of files to stage from `diff.new` and `diff.modified`, then calls
`gitAdd filesToStage`. If any file in that list is covered by a `.gitignore` rule,
`git add` exits non-zero with a message like:

    The following paths are ignored by one of your .gitignore files:
        dist/bundle.js
    hint: Use -f if you really want to add them.

The `ExitFailure` branch logs a warning and skips the commit entirely — no files get
committed, even the ones that are perfectly fine to stage.

**Key files:**

- `seihou-cli/src/Seihou/CLI/Git.hs` — Git helper functions (`gitAdd`, `gitCommit`,
  `gitDiffCached`, `isGitRepo`). Uses the `Process` effect.
- `seihou-cli/src/Seihou/CLI/Run.hs` — `handleRun` function, lines 278-300 contain
  the commit logic.
- `seihou-core/src/Seihou/Effect/Process.hs` — The `Process` effect with
  `runProcess :: Text -> [Text] -> Maybe FilePath -> Eff es (ExitCode, Text, Text)`.
- `seihou-cli/test/` — CLI test suite.

**How `git check-ignore` works:**

```
$ git check-ignore file1 file2 file3
file2
```

It prints the paths that ARE ignored (one per line) and exits 0 if at least one match,
1 if no matches, 128 on error. With `--stdin`, it reads paths from stdin (useful for
large lists, but we won't need that for typical seihou runs).


## Plan of Work

### Milestone 1: Add `gitCheckIgnore` and filter staging list

**Scope:** Add a new helper to `Git.hs`, then use it in `Run.hs` to filter the file
list before calling `git add`. At the end of this milestone, `--commit` gracefully
skips ignored files.

**Edits:**

1. **`seihou-cli/src/Seihou/CLI/Git.hs`** — Add a new exported function:

   ```haskell
   gitCheckIgnore :: (Process :> es) => [FilePath] -> Eff es [FilePath]
   ```

   Implementation: call `git check-ignore` with the file list, parse stdout to get
   the set of ignored paths, return them. Handle the exit codes:
   - Exit 0: some files are ignored (stdout has the list)
   - Exit 1: no files are ignored (empty result)
   - Exit 128: error (treat as empty — don't block the commit over a check-ignore failure)

2. **`seihou-cli/src/Seihou/CLI/Run.hs`** (lines ~278-286) — Between building
   `filesToStage` and calling `gitAdd`, insert a filtering step:

   ```haskell
   ignored <- runEff $ runProcessIO $ gitCheckIgnore filesToStage
   let filteredFiles = filter (`notElem` ignored) filesToStage
   ```

   Then call `gitAdd filteredFiles` instead of `gitAdd filesToStage`. If
   `filteredFiles` is empty after filtering (every generated file is ignored), skip
   the commit with a debug log message instead of staging nothing.

**Acceptance:** Build passes. Running `--commit` when a module generates an ignored
file no longer produces "git add failed" warnings; the commit succeeds with only the
non-ignored files.


### Milestone 2: Tests

**Scope:** Add unit tests for the new helper and the filtering behavior.

**Edits:**

3. **CLI test suite** — Add tests for `gitCheckIgnore`:
   - When `git check-ignore` returns exit 0 with paths, those paths are returned.
   - When `git check-ignore` returns exit 1 (no matches), empty list returned.
   - When `git check-ignore` returns exit 128 (error), empty list returned (graceful fallback).

4. **CLI test suite** — Add a test verifying that ignored files are excluded from
   the staging list (test the filtering logic in `handleRun` or extract it into a
   pure helper for easier testing).


## Concrete Steps

All commands run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

**Step 1: Edit `Git.hs`**

Add `gitCheckIgnore` to the module export list and implement it:

```haskell
-- | Check which files are ignored by git. Returns the subset of input paths
-- that are covered by .gitignore rules.
gitCheckIgnore :: (Process :> es) => [FilePath] -> Eff es [FilePath]
gitCheckIgnore [] = pure []
gitCheckIgnore paths = do
  (exitCode, stdout', _) <- runProcess "git" ("check-ignore" : map T.pack paths) Nothing
  case exitCode of
    ExitSuccess -> pure (map T.unpack $ filter (not . T.null) $ T.lines stdout')
    _           -> pure []  -- exit 1 = no matches, exit 128 = error; both → empty
```

**Step 2: Edit `Run.hs`**

Add `gitCheckIgnore` to the import from `Seihou.CLI.Git`. Then modify the commit
block (around line 279-286):

Before:
```haskell
let filesToStage =
      map (.path) diff.new
        ++ map (.path) diff.modified
        ++ [manifestPath]
...
(addExit, _, addErr) <- runEff $ runProcessIO $ gitAdd filesToStage
```

After:
```haskell
let filesToStage =
      map (.path) diff.new
        ++ map (.path) diff.modified
        ++ [manifestPath]
ignored <- runEff $ runProcessIO $ gitCheckIgnore filesToStage
let filteredFiles = filter (\f -> f `notElem` ignored) filesToStage
if null filteredFiles
  then logIO level (logDebug "--commit: all generated files are git-ignored, skipping commit.")
  else do
    (addExit, _, addErr) <- runEff $ runProcessIO $ gitAdd filteredFiles
    ...
```

**Step 3: Build and test**

```bash
cabal build all
cabal test all
```

Expected: all existing tests pass, build succeeds.

**Step 4: Add tests**

Add tests to the CLI test suite following existing patterns (pure `Process` effect
interpreter mocking `git check-ignore` responses).

**Step 5: Manual verification**

Create a test module that generates a file and patches `.gitignore` to ignore it,
then run with `--commit` and verify the commit succeeds.


## Validation and Acceptance

1. **Build:** `cabal build all` succeeds with no warnings related to these changes.

2. **Existing tests:** `cabal test all` — all tests pass (no regressions).

3. **New tests pass:** The `gitCheckIgnore` tests and filtering tests pass.

4. **Manual test:**
   - Create a temporary module that generates both `README.md` (tracked) and
     `tmp/cache.txt` (ignored via `.gitignore` patch).
   - Run `seihou run test-module --commit`.
   - Verify: commit is created, `README.md` is in the commit, `tmp/cache.txt` is
     not staged, no warnings about `git add` failure.
   - Run `seihou status` — both files should appear in the manifest.


## Idempotence and Recovery

All steps are safe to repeat. The `gitCheckIgnore` call is read-only. If the commit
fails for other reasons (e.g. nothing to commit), the existing warning-and-continue
behavior handles it. The manifest is written before the commit step, so a failed
commit does not corrupt state.


## Interfaces and Dependencies

No new library dependencies. Uses the existing `Process` effect for `git check-ignore`.

In `seihou-cli/src/Seihou/CLI/Git.hs`, add:

```haskell
gitCheckIgnore :: (Process :> es) => [FilePath] -> Eff es [FilePath]
```

No changes to `seihou-core` types, Dhall schema, or manifest format.
