---
slug: run-commit-flag
title: "Add --commit flag to seihou run with AI-generated commit messages"
kind: exec-plan
created_at: 2026-03-27T13:05:09Z
intention: "intention_01kjjgfv60e8y9qata1sfk8qrc"
---


# Add --commit flag to seihou run with AI-generated commit messages

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, users can run `seihou run my-module --commit` and have all generated
files automatically committed to git with an AI-generated commit message that describes
the actual changes made. The commit message is produced by invoking `claude -p` (Claude
Code CLI in print mode) with the staged diff as context. This saves users from manually
staging, reviewing, and writing a commit message after every scaffolding run.

An optional `--commit-message "custom message"` flag allows overriding the AI-generated
message with a user-supplied one. The flag is silently ignored if the working directory
is not inside a git repository.


## Progress

- [x] Add `runCommit` and `runCommitMessage` fields to `RunOpts` in `Commands.hs` (2026-03-27)
- [x] Add `--commit` switch and `--commit-message` option to `runParser` in `Commands.hs` (2026-03-27)
- [x] Create `Seihou.CLI.Git` module with git helper functions (2026-03-27)
- [x] Create `Seihou.CLI.CommitMessage` module with Claude-based message generation (2026-03-27)
- [x] Wire commit logic into `handleRun` post-execution in `Run.hs` (2026-03-27)
- [x] Build passes, all 655 core tests pass (2026-03-27)
- [x] Add tests for git helpers (pure process mocks) and commit message generation (2026-03-27)
- [x] All 89 CLI tests pass (2026-03-27)
- [x] Verify end-to-end: `--commit-message` creates commit with custom message (2026-03-27)
- [x] Verify end-to-end: `--commit` creates commit with AI-generated message via `claude -p` (2026-03-27)
- [x] Verify end-to-end: `--commit` outside git repo shows debug skip message (2026-03-27)


## Surprises & Discoveries

- `claude -p --no-input` flag does not exist. Removed `--no-input` from the `claude` invocation — `claude -p` alone is sufficient for non-interactive single-response mode. (2026-03-27)
- CommitMessage tests that invoke `claude -p` are slow (~20s each) since they make real API calls. Consider tagging as integration tests in the future. (2026-03-27)


## Decision Log

- Decision: Use the `Process` effect to shell out to `git` rather than adding a git library dependency.
  Rationale: The project already uses `System.Process` for git clone in `Install.hs` and has a `Process` effect with IO and pure interpreters. Shelling out to `git` is simpler, avoids a heavy dependency like `libgit2`, and is consistent with the existing codebase pattern.
  Date: 2026-03-27

- Decision: Place git helpers in `Seihou.CLI.Git` and commit message generation in `Seihou.CLI.CommitMessage`.
  Rationale: Separation of concerns — git operations are reusable across commands, while commit message generation is specific to the AI integration. Both keep `Run.hs` focused on orchestration.
  Date: 2026-03-27

- Decision: Generate commit messages by invoking `claude -p` (Claude Code CLI print mode) rather than calling the Claude API directly.
  Rationale: The project already integrates with Claude exclusively through the `claude` CLI (`AgentLaunch.hs` uses `rawSystem "claude"`). There are no HTTP library dependencies in either cabal file. Using `claude -p` is consistent with the existing pattern, requires no new dependencies, and delegates authentication/model selection to the user's Claude Code configuration.
  Date: 2026-03-27

- Decision: Silently skip commit (with a debug log) when not in a git repo, rather than erroring.
  Rationale: `--commit` is a convenience flag. Erroring would break scripts that run across mixed git/non-git directories. A debug-level log (visible with `--verbose`) is sufficient.
  Date: 2026-03-27

- Decision: Stage only the files that seihou generated/modified (from the diff result), not `git add -A`.
  Rationale: `git add -A` would capture unrelated changes. Staging only the files seihou touched keeps the commit scoped to the scaffolding operation.
  Date: 2026-03-27

- Decision: Also stage `.seihou/manifest.json` in the commit.
  Rationale: The manifest is updated on every run and is part of the scaffolding state that should be tracked in version control.
  Date: 2026-03-27

- Decision: Fall back to a static template message if `claude` CLI is not available or the call fails.
  Rationale: The `--commit` flag should be robust. If Claude Code is not installed or the API call fails, the user still wants their files committed. The fallback message format is `seihou: apply module <name>`.
  Date: 2026-03-27

- Decision: Use `readCreateProcessWithExitCode` (via Process effect) to capture `claude -p` output, not `rawSystem`.
  Rationale: `rawSystem` inherits the terminal's stdout (used for interactive agent sessions). For commit message generation we need to capture the output text. The `Process` effect already wraps `readCreateProcessWithExitCode`.
  Date: 2026-03-27


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

### Key files

- **`seihou-cli/src/Seihou/CLI/Commands.hs`** — Defines `RunOpts` (lines 78–91) and the optparse-applicative parser `runParser` (lines 533–558). All CLI option types and parsers live here.

- **`seihou-cli/src/Seihou/CLI/Run.hs`** — The `handleRun :: RunOpts -> IO ()` function (line 49) orchestrates the entire run pipeline: module resolution → variable resolution → plan compilation → diff computation → execution → manifest write → command execution → save-prompted offer. The commit step will be inserted after the manifest write and result reporting, before command execution.

- **`seihou-core/src/Seihou/Effect/Process.hs`** — The `Process` effect with a single operation `RunProcess :: Text -> [Text] -> Maybe FilePath -> Process m (ExitCode, Text, Text)`. Used via `runProcess` helper.

- **`seihou-core/src/Seihou/Effect/ProcessInterp.hs`** — IO interpreter `runProcessIO` that delegates to `System.Process.readCreateProcessWithExitCode`.

- **`seihou-cli/src/Seihou/CLI/AgentLaunch.hs`** — Existing Claude Code CLI integration. Uses `findExecutable "claude"` to check availability, `rawSystem "claude"` for interactive sessions. Our commit message generator follows the same `findExecutable` pattern but uses the `Process` effect to capture output from `claude -p`.

- **`seihou-cli/src/Seihou/CLI/Install.hs`** — Contains `cloneRepo` (lines 77–88), the only existing runtime git usage. Uses `readProcessWithExitCode` directly. Our implementation will use the `Process` effect for consistency and testability.

### How `claude -p` works

Claude Code CLI's `-p` (print) flag runs a single prompt non-interactively and prints the response to stdout. Input can be provided as a positional argument or piped via stdin. For commit message generation:

```bash
git diff --cached | claude -p "Generate a concise git commit message for these changes. Output ONLY the commit message, no explanation."
```

Since the `Process` effect doesn't support stdin piping, we'll pass the diff as part of the prompt argument:

```bash
claude -p "Generate a concise git commit message for these seihou scaffolding changes:\n\nModules applied: my-module\n\n<diff>\n...git diff output...\n</diff>\n\nOutput ONLY the commit message text."
```

### Relevant types

```haskell
-- From Seihou.Core.Types
data DiffResult = DiffResult
  { new       :: [PlannedFile]    -- path field
  , modified  :: [ModifiedFile]   -- path field
  , unchanged :: [FilePath]
  , conflicts :: [ConflictFile]   -- path field
  , orphaned  :: [OrphanedFile]   -- path field
  }
```

The files to stage come from `diff.new` (new files) and `diff.modified` (changed files), plus `.seihou/manifest.json`.

### Effect composition pattern

Effects are composed with nested interpreters run inside `runEff`:

```haskell
runEff $ runProcessIO $ do
  runProcess "git" ["add", ...] Nothing
  runProcess "claude" ["-p", prompt] Nothing
```


## Plan of Work

### Milestone 1: CLI option plumbing

Add two new fields to `RunOpts` and wire them into the parser.

**In `seihou-cli/src/Seihou/CLI/Commands.hs`:**

1. Add `runCommit :: Bool` and `runCommitMessage :: Maybe Text` fields to the `RunOpts` record (after `runSavePrompted`).

2. Add parser entries in `runParser`:
   - `switch (long "commit" <> help "Commit generated files to git after execution (uses AI-generated message)")`
   - `optional (option (T.pack <$> str) (long "commit-message" <> metavar "MSG" <> help "Custom commit message (implies --commit)"))`

**Acceptance:** `seihou run --help` shows `--commit` and `--commit-message` flags. Project compiles.

### Milestone 2: Git helper module

Create `seihou-cli/src/Seihou/CLI/Git.hs` with functions that use the `Process` effect:

```haskell
module Seihou.CLI.Git
  ( isGitRepo,
    gitAdd,
    gitCommit,
    gitDiffCached,
  )
where

-- | Check if the current directory is inside a git work tree.
isGitRepo :: (Process :> es) => Eff es Bool

-- | Stage specific files.
gitAdd :: (Process :> es) => [FilePath] -> Eff es (ExitCode, Text, Text)

-- | Create a commit with the given message.
gitCommit :: (Process :> es) => Text -> Eff es (ExitCode, Text, Text)

-- | Get the diff of staged changes (for feeding to the commit message generator).
gitDiffCached :: (Process :> es) => Eff es Text
```

`isGitRepo` runs `git rev-parse --is-inside-work-tree` and checks for `ExitSuccess`.

`gitDiffCached` runs `git diff --cached --stat` (summary) plus `git diff --cached` (full diff, truncated to a reasonable size to fit in a prompt).

**Acceptance:** Module compiles. Functions have correct type signatures.

### Milestone 3: Commit message generation module

Create `seihou-cli/src/Seihou/CLI/CommitMessage.hs`:

```haskell
module Seihou.CLI.CommitMessage
  ( generateCommitMessage,
  )
where

-- | Generate a commit message using Claude Code CLI.
-- Takes the module names applied and the staged diff.
-- Returns the AI-generated message, or a fallback if claude is unavailable.
generateCommitMessage ::
  [ModuleName] ->  -- modules applied
  Text ->          -- staged diff
  IO Text
```

Implementation:
1. Check if `claude` is on PATH via `findExecutable "claude"`.
2. If available, invoke `claude -p` with a prompt containing:
   - The module names being applied
   - The staged diff (truncated to ~4000 chars to avoid excessive token usage)
   - Instructions to produce a concise conventional-commit-style message
3. Parse the output: strip whitespace, take the first line if multi-line.
4. If `claude` is not found or the call fails, fall back to:
   `"seihou: apply module <name>"` (or `"seihou: apply modules <name1>, <name2>"` for multi-module runs).

The prompt template:

```
Generate a concise git commit message for seihou scaffolding changes.

Modules applied: {{modules}}

Staged changes:
{{diff}}

Rules:
- Use conventional commit style (e.g., "feat: ...", "chore: ...")
- Keep the subject line under 72 characters
- Mention which seihou module(s) were applied
- Output ONLY the commit message, nothing else
```

**Acceptance:** Module compiles. `generateCommitMessage` returns a non-empty text message.

### Milestone 4: Wire into handleRun

**In `seihou-cli/src/Seihou/CLI/Run.hs`:**

After the manifest write (line 260) and result reporting (line 272), before command execution (line 275), insert the commit logic:

```haskell
-- Commit generated files if --commit or --commit-message
when (runOpts.runCommit || isJust runOpts.runCommitMessage) $ do
  let filesToStage =
        map (.path) diff.new
          ++ map (.path) diff.modified
          ++ [manifestPath]
  inGit <- runEff $ runProcessIO $ isGitRepo
  if inGit
    then do
      -- Stage files
      (addExit, _, addErr) <- runEff $ runProcessIO $ gitAdd filesToStage
      case addExit of
        ExitFailure _ -> logIO level (logWarn $ "git add failed: " <> addErr)
        ExitSuccess -> do
          -- Generate or use provided commit message
          commitMsg <- case runOpts.runCommitMessage of
            Just msg -> pure msg
            Nothing -> do
              diffText <- runEff $ runProcessIO $ gitDiffCached
              generateCommitMessage modNames diffText
          -- Commit
          (commitExit, _, commitErr) <- runEff $ runProcessIO $ gitCommit commitMsg
          case commitExit of
            ExitSuccess -> logIO level (logInfo "Committed generated files to git.")
            ExitFailure _ -> logIO level (logWarn $ "git commit failed: " <> commitErr)
    else
      logIO level (logDebug "--commit: not inside a git repository, skipping.")
```

The commit happens **before** shell commands so that the commit captures exactly the scaffolded output, not any side effects from post-generation commands.

**Acceptance:** `seihou run my-module --commit` in a git repo creates a commit with an AI-generated message describing the changes.

### Milestone 5: Tests

Add tests that verify:

1. `isGitRepo` returns `True` in a git repo and `False` outside one.
2. `gitAdd` and `gitCommit` work correctly in a temporary git repo.
3. `generateCommitMessage` returns a fallback message when `claude` is not available.
4. `generateCommitMessage` returns a non-empty message (integration test, requires `claude` on PATH).

**Acceptance:** `cabal test all` passes with new tests.


## Concrete Steps

All commands run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

### Step 1: Edit `RunOpts` and parser

```bash
# After editing, verify compilation:
cabal build seihou-cli
```

Expected: Build succeeds with no errors.

### Step 2: Create `Seihou.CLI.Git`

```bash
# After creating the file and adding to cabal:
cabal build seihou-cli
```

Expected: Build succeeds.

### Step 3: Create `Seihou.CLI.CommitMessage`

```bash
# After creating the file and adding to cabal:
cabal build seihou-cli
```

Expected: Build succeeds.

### Step 4: Wire into `Run.hs`

```bash
# After editing, verify compilation:
cabal build seihou-cli
```

Expected: Build succeeds.

### Step 5: Verify help output

```bash
cabal run seihou -- run --help
```

Expected output includes:
```
  --commit                 Commit generated files to git after execution (uses AI-generated message)
  --commit-message MSG     Custom commit message (implies --commit)
```

### Step 6: End-to-end test

```bash
# In a temp directory:
mkdir /tmp/seihou-commit-test && cd /tmp/seihou-commit-test
git init
seihou init
seihou run <some-test-module> --commit
git log --oneline -1
```

Expected: `git log` shows a commit with a descriptive AI-generated message (e.g., `feat: scaffold project with my-module`).

### Step 7: Test with custom message

```bash
seihou run <some-test-module> --commit-message "chore: re-scaffold with updated module"
git log --oneline -1
```

Expected: `git log` shows the exact custom message provided.

### Step 8: Run test suite

```bash
cabal test all
```

Expected: All tests pass.


## Validation and Acceptance

1. **`seihou run my-module --commit`** in a git repo creates a single commit containing exactly the generated/modified files plus `.seihou/manifest.json`. The commit message is AI-generated by Claude, describing the actual changes.

2. **`seihou run my-module --commit-message "custom msg"`** creates a commit with the exact message `custom msg` (bypasses AI generation, also implies `--commit`).

3. **`seihou run my-module --commit`** when `claude` CLI is not on PATH still creates a commit using the fallback message format `seihou: apply module my-module`.

4. **`seihou run my-module --commit`** outside a git repo completes normally without error. With `--verbose`, a debug message indicates the skip.

5. **`seihou run my-module --commit --dry-run`** does not commit (dry-run takes precedence — no execution means no commit).

6. **`seihou run my-module`** (no `--commit`) behaves exactly as before — no regression.

7. **`cabal test all`** passes.


## Idempotence and Recovery

- Running `seihou run --commit` multiple times is safe. If there are no changes (all files unchanged), `git commit` will fail with "nothing to commit" — a warning is logged. No harm done.

- If `git add` succeeds but `git commit` fails, files remain staged but no commit is created. The user can inspect with `git status` and either commit manually or reset.

- If `claude -p` hangs or takes too long, the user can Ctrl-C. The files are still generated and the manifest is written — only the commit step is interrupted.

- The flag has no effect on the manifest or file generation — it is purely a post-execution convenience. Removing or adding `--commit` between runs does not affect scaffolding behavior.


## Interfaces and Dependencies

No new library dependencies. Uses the existing `Process` effect to shell out to `git`, and `System.Process.readCreateProcessWithExitCode` (via IO) to call `claude -p`. Uses `System.Directory.findExecutable` (already imported in `AgentLaunch.hs`) to check for `claude` availability.

### New modules

In `seihou-cli/src/Seihou/CLI/Git.hs`:

```haskell
isGitRepo :: (Process :> es) => Eff es Bool

gitAdd :: (Process :> es) => [FilePath] -> Eff es (ExitCode, Text, Text)

gitCommit :: (Process :> es) => Text -> Eff es (ExitCode, Text, Text)

gitDiffCached :: (Process :> es) => Eff es Text
```

In `seihou-cli/src/Seihou/CLI/CommitMessage.hs`:

```haskell
generateCommitMessage :: [ModuleName] -> Text -> IO Text
```

### Modified types

In `seihou-cli/src/Seihou/CLI/Commands.hs`, extend:

```haskell
data RunOpts = RunOpts
  { ...existing fields...
  , runCommit :: Bool
  , runCommitMessage :: Maybe Text
  }
```

### Modified functions

In `seihou-cli/src/Seihou/CLI/Run.hs`, extend `handleRun` with post-execution commit logic.

### Cabal file

Add `Seihou.CLI.Git` and `Seihou.CLI.CommitMessage` to the `other-modules` list in `seihou-cli.cabal`.
