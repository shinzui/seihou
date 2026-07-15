---
id: 62
slug: deliver-blueprint-reference-files-and-honor-allowedtools-in-the-agent-runner
title: "Deliver blueprint reference files and honor allowedTools in the agent runner"
kind: exec-plan
created_at: 2026-07-15T14:00:26Z
intention: intention_01kxkabjrge3gtsqff461r7nv5
---

# Deliver blueprint reference files and honor allowedTools in the agent runner

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

A Seihou **blueprint** is an agent-driven scaffolding artifact: a directory holding
`blueprint.dhall` (metadata), `prompt.md` (the author's instructions), and a `files/`
subdirectory of curated **reference files**. An operator runs it with `seihou agent run
<name>`, which renders a system prompt and hands it to an interactive coding agent (Claude
Code or Codex) that edits the target repository.

Today the blueprint runner tells the agent that reference files exist but never lets the
agent read them, and it silently ignores the blueprint's declared tool allow-list. Both
gaps were found while validating a database-migration blueprint that leans heavily on four
reference files (see the agent-seihou repository's ExecPlan
`docs/plans/1-add-an-adaptive-pg-migrate-keiro-stack-blueprint.md`, "Revision Notes"). The
blueprint author reasonably expected the files to reach the agent; they do not.

After this change an operator gains two concrete, observable behaviors. First, when they run
`seihou agent run <blueprint>` under the default `claude-cli` (or `codex-cli`) provider, the
agent can actually open and read the blueprint's `files/*.md` — the rendered prompt now
prints the absolute directory where those files are mounted and instructs the agent to read
them directly, and the directory is passed to the provider as an accessible path. Second, a
blueprint that declares `allowedTools` in its `blueprint.dhall` now has those tools added to
the always-present base set and passed to the interactive launcher instead of leaving the
field as dead metadata. Claude Code receives the effective set as pre-approved tools; Codex
keeps its sandbox and approval policy because it has no per-tool allow-list option. You can
see the first behavior by running `seihou agent --debug run
<blueprint>` and reading the new "## Reference Files" block, which names the real on-disk
directory; and you can see both working through new unit tests that assert the rendered
directory guidance and the resolved tool list.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] (2026-07-15 09:47 PDT) Milestone 1: Delivered `files/` to the running agent (template var, pure helper, IO
      wiring, update the shared `runRenderedAgentPrompt` and its second caller `PromptRun.hs`,
      tests). `cabal build seihou-cli` succeeded, all 253 CLI tests passed, and debug smoke
      checks rendered both the absolute mounted path and the no-directory fallback.
- [x] (2026-07-15 09:49 PDT) Milestone 2: Honored `blueprint.allowedTools` (pure resolver unioned with the base set,
      thread resolved tools through `runRenderedAgentPrompt`, keep `PromptRun.hs` passing the
      base set, tests). `cabal build seihou-cli` succeeded and all 256 CLI tests passed,
      including the three new resolver cases.
- [x] (2026-07-15 09:54 PDT) Milestone 3: Corrected stale docs/comments, updated
      `CHANGELOG.md`, and completed full validation. `just format`, `cabal build all`,
      `cabal test all` (256 CLI, 939 core, and 16 OKF extension tests), `just check`, and
      `git diff --check` all passed.
- [x] (2026-07-15 09:43 PDT) Captured a green baseline: `cabal build seihou-cli` succeeded
      and `cabal test seihou-cli-test` passed all 251 tests.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Discovery: The plan's sample `mFilesDir` calculation treated every existing `files/`
  directory as mounted, but API-provider runs cannot receive `extraDirs`. The implementation
  therefore gates the mounted path on `claude-cli` or `codex-cli`; otherwise it renders the
  fallback even when the directory exists.
  Evidence: Baikai's `launchClaudeInteractive` and `launchCodexInteractive` consume
  `extraDirs`, while `AgentRun.runAgentCompletion` has no directory parameter.

- Discovery: `seihou agent --debug run` does not contact a provider, but it does record
  applied-blueprint provenance in `.seihou/manifest.json` after printing the prompt.
  Evidence: the first debug smoke check created
  `/tmp/seihou-bp-demo.1JC1k6/.seihou/manifest.json`; the second debug render reported that
  manifest as present. Smoke checks must therefore run in a disposable directory.

- Discovery: Baikai applies `ClaudeAllowedTools` only in its Claude Code command builder;
  the Codex command builder ignores that safety constructor and uses `CodexSandbox` instead.
  Evidence: `baikai-claude/src/Baikai/Provider/Claude/Interactive.hs` renders
  `--allowedTools`, while `baikai-openai/src/Baikai/Provider/OpenAI/Interactive.hs` maps
  `ClaudeAllowedTools _` to no arguments. The runner can resolve and pass the effective list,
  but only Claude Code can pre-approve it as a per-tool allow-list.


## Decision Log

Record every decision made while working on the plan.

- Decision: Mount the blueprint's `files/` directory as an accessible provider directory and
  also print its absolute path in the rendered prompt, rather than inlining every file's
  bytes into the system prompt.
  Rationale: Inlining would bloat the prompt unboundedly and cannot work for large corpora;
  it also duplicates content the agent can read on demand. The interactive providers already
  accept extra readable directories (`extraDirs` → the CLI's `--add-dir`), so mounting the
  directory and telling the agent where it is is the smallest change that makes the existing
  "## Reference Files" listing truthful. The prompt keeps a graceful fallback for the
  tool-less API path (no directory available → ask the operator).
  Date: 2026-07-15

- Decision: Treat `blueprint.allowedTools` as additive on top of the base
  `setupAllowedTools` set (union, de-duplicated, base first), not as a replacement.
  Rationale: Every blueprint run needs the base tools (`Read`, `Write`, `Edit`, `git`,
  `seihou`, …) to function; letting a blueprint replace the whole set would let an author
  accidentally strip essential tools. Authors declaring `allowedTools` want to *grant extra*
  domain tools (e.g. `Bash(mori *)`, `Bash(cabal *)`) for a smoother session, so union is
  the least-surprising semantics and keeps the destructive-operation safety story intact
  (a blueprint still cannot silently pre-approve, say, `Bash(dropdb *)` unless its author
  writes it explicitly).
  Date: 2026-07-15

- Decision: Put the new *pure* logic (`formatReferenceFilesDir`, `resolveBlueprintTools`) in
  the library module `Seihou.CLI.AgentLaunch` and keep only IO wiring in the exe module
  `Seihou.CLI.AgentRun`.
  Rationale: `AgentLaunch` already hosts the sibling helpers `formatReferenceFiles` and
  `setupAllowedTools` and is already covered by `test/Seihou/CLI/AgentLaunchSpec.hs`. The exe
  module `src-exe/.../AgentRun.hs` is not on the test suite's import path. Following the
  existing split keeps every new decision unit-testable.
  Date: 2026-07-15

- Decision: Scope this plan to `seihou agent run` (blueprints). Note but do not fix the
  parallel first-class-prompt runner (`seihou prompt`) here.
  Rationale: The reported problems are about blueprints. `AgentPrompt` shares the same
  `files` shape and a similar renderer (`Seihou.CLI.PromptRender`), and it additionally has a
  `launch` field that may already thread directories; folding it in would widen scope and
  risk. The pure helpers introduced here are reusable, so a focused follow-up can adopt them
  for prompts after confirming how `launch` behaves. Recorded here so the follow-up is not
  forgotten.
  Date: 2026-07-15

- Decision: Even though `seihou prompt` is out of behavioral scope, this plan must edit
  `Seihou.CLI.PromptRun` because it imports and calls the exported
  `AgentRun.runRenderedAgentPrompt` — the exact function whose signature Milestones 1 and 2
  change. Keep the prompt path's behavior identical by passing `Nothing` (no mounted `files/`)
  and `setupAllowedTools` (its current tool set) at that call site.
  Rationale: `runRenderedAgentPrompt` is shared by the blueprint runner and the prompt runner;
  changing its type without updating the second caller would not compile. Passing the
  behavior-preserving arguments keeps the scope limited to blueprints while keeping the build
  green. Discovered during plan validation via
  `grep -rn runRenderedAgentPrompt seihou-cli/` (two importing call sites: `AgentRun` and
  `PromptRun`; the `Assist`/`Setup`/`Bootstrap` matches are distinct local definitions).
  Date: 2026-07-15

- Decision: Define `mFilesDir` as a directory that the selected provider can actually mount,
  not merely a `files/` directory that exists on disk. Gate it on the two interactive CLI
  providers as well as `doesDirectoryExist`.
  Rationale: The rendered sentence says the files are readable in the current session. API
  completion requests have no `extraDirs` channel, so printing a path for them would recreate
  the same false promise this plan fixes. The default and supported interactive runners still
  receive the absolute path exactly as intended.
  Date: 2026-07-15

- Decision: Do not invent a Codex translation for blueprint `allowedTools`; document that
  Claude Code consumes the effective list while Codex retains its existing sandbox and
  on-request approval policy.
  Rationale: Codex exposes no equivalent per-tool allow-list in Baikai or the installed CLI.
  Translating Claude tool strings into sandbox or approval settings would be lossy and could
  weaken safety. The runner still resolves and passes one effective list through the shared
  interface, and Claude Code honors it exactly.
  Date: 2026-07-15


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

- Milestone 1 outcome: Blueprint reference directories are now appended to Baikai's existing
  session directories for interactive CLI providers, and the rendered prompt tells the agent
  the canonical absolute path. The shared first-class-prompt call site preserves its old
  behavior by passing no extra directory. Unit tests cover mounted and fallback guidance;
  debug smoke checks demonstrated both user-visible branches.

- Milestone 2 outcome: `resolveBlueprintTools` now returns the base setup tools followed by
  de-duplicated blueprint additions, and the blueprint runner passes that effective set into
  the interactive launcher. The shared prompt runner explicitly passes `setupAllowedTools`,
  so its behavior remains unchanged. Three unit tests cover no declaration, a new tool, and a
  repeated base tool.

- Final outcome: The blueprint runner now delivers existing reference directories to both
  interactive CLI providers, prints truthful mounted-or-fallback guidance, and resolves
  blueprint tool additions on top of the required base set. Claude Code consumes that set as
  pre-approved tools; Codex retains its native sandbox/approval model. The help topic, user
  guides, changelog, Haddock, prompt template, shared prompt caller, and living plan all match
  the implemented behavior. No in-scope work remains. Full Cabal and Nix validation passed;
  the only warnings were pre-existing partial-function and missing-record-field warnings in
  unrelated tests.


## Context and Orientation

Work from the repository root `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`. This is
a Haskell project built with Cabal (and a Nix flake). Two packages matter here:
`seihou-core` (the library of core types) and `seihou-cli` (the CLI, split into a testable
library under `seihou-cli/src/` and the executable's own modules under `seihou-cli/src-exe/`,
with tests under `seihou-cli/test/`). There is no `docs/adr/` directory in this repository,
so no ADR is relevant; if this change establishes a durable convention, create an ADR during
the final distillation pass. The most closely related prior plan is
`docs/plans/31-blueprint-agent-runner.md` (the original blueprint runner design, "EP-31"),
referenced from the runner's own comments.

The relevant runtime path is `seihou agent run <blueprint>`. Its code lives in these files:

- `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` — `handleAgentRun` discovers the blueprint,
  resolves variables, optionally applies baseline modules, renders the system prompt via the
  pure `renderSystemPrompt`, then launches the provider via `runRenderedAgentPrompt`.
  Discovery returns the pair `(bp, blueprintDir)` where `blueprintDir` is the directory
  containing `blueprint.dhall`, `prompt.md`, and `files/`. `renderSystemPrompt` fills a fixed
  template with a substitution list; `runRenderedAgentPrompt` currently launches with the
  hard-coded `setupAllowedTools` and does **not** pass the blueprint's `files/` directory.
- `seihou-cli/src/Seihou/CLI/AgentLaunch.hs` — the library module. It defines the tool
  allow-lists (`defaultAllowedTools`, `setupAllowedTools`, `bootstrapAllowedTools`), the
  formatter `formatReferenceFiles :: [BlueprintFile] -> Text` (whose Haddock already claims,
  incorrectly, that the runner "mounts the blueprint's `files/` directory via `--add-dir`"),
  and other prompt-block formatters.
- `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs` — the launcher. `launchConfiguredAgent`
  computes the session's accessible directories with `Baikai.Kit.Session.agentDirsForSession
  seihouKitConfig` and delegates to `launchConfiguredAgentWith addDirs …`, which sets the
  provider request's `extraDirs = addDirs` and `safety = ClaudeAllowedTools (map T.pack
  tools)`. `agentDirsForSession` (in the `baikai` project at
  `/Users/shinzui/Keikaku/bokuno/baikai/baikai-kit/src/Baikai/Kit/Session.hs`) returns only
  the existing subset of `~/.config/<tool>/agents` and `<cwd>/.<tool>/agents` — never the
  blueprint's `files/`. This is the root cause of the delivery gap.
- `seihou-cli/data/blueprint-prompt.md` — the system-prompt template, embedded at compile
  time by `AgentRun.hs` via `Data.FileEmbed.embedFile`. Its "## Reference Files" block lists
  files by name/description and tells the agent that when a reference "is not shown in this
  prompt" it must "ask the user to provide it rather than claiming to have read it."
- `seihou-cli/src-exe/Seihou/CLI/Assist.hs`, `Setup.hs`, `Bootstrap.hs` — the other three
  commands that call `launchConfiguredAgent` (with `defaultAllowedTools`, `setupAllowedTools`,
  and `bootstrapAllowedTools` respectively). They generate modules and have no blueprint
  `files/` directory, so they must keep their current behavior unchanged. Note: each of these
  three defines its **own** local `runRenderedAgentPrompt :: … -> IO ()`; they do **not** share
  `AgentRun.runRenderedAgentPrompt` and are therefore unaffected by its signature change.
- `seihou-cli/src-exe/Seihou/CLI/PromptRun.hs` — the `seihou prompt` runner (first-class
  prompts). It **imports and calls `AgentRun.runRenderedAgentPrompt`** directly
  (`import Seihou.CLI.AgentRun (runRenderedAgentPrompt)` at line 12; the call is at line 140,
  `runRenderedAgentPrompt opts.runPromptDebug modelConfig systemPrompt opts.runPromptPrompt`).
  Because this is the *same* function whose signature Milestones 1 and 2 change, its call site
  **must** be updated in lockstep or the build breaks. `AgentPrompt` has no `files/` directory
  and no `allowedTools` field to honor here, so the prompt path must preserve its current
  behavior: pass `Nothing` for the mounted directory and `setupAllowedTools` for the tools
  (exactly what `runRenderedAgentPrompt` hard-codes today). Delivering `files/` to prompts is
  the out-of-scope follow-up recorded in the Decision Log.

The blueprint data type is in `seihou-core/src/Seihou/Core/Types.hs`:

```haskell
data BlueprintFile = BlueprintFile
  { src :: FilePath,
    description :: Maybe Text
  }

data Blueprint = Blueprint
  { name :: ModuleName,
    version :: Maybe Text,
    description :: Maybe Text,
    prompt :: Text,
    vars :: [VarDecl],
    prompts :: [Prompt],
    baseModules :: [Dependency],
    files :: [BlueprintFile],
    allowedTools :: Maybe [Text],   -- added to the base runner tool set
    tags :: [Text]
  }
```

The Dhall schema field already exists: `schema/Blueprint.dhall` declares `allowedTools :
Optional (List Text)` defaulting to `None (List Text)`. No schema change is required.

Two facts constrain the change. First, `runRenderedAgentPrompt` short-circuits in `--debug`
mode: it prints the rendered system prompt without launching a provider, after which
`handleAgentRun` still records applied-blueprint provenance. So `--debug` can demonstrate the
new *prompt text* (the printed directory path) but cannot demonstrate the `--add-dir` wiring;
the directory-composition and tool-resolution logic must be proven by unit tests and source
inspection instead. Second, `AgentRun` sends `anthropic` and `openai` through one-shot API
completion, which has no `extraDirs`; only the `claude-cli`/`codex-cli` paths receive mounted
directories, so the template must degrade gracefully for API providers.

Existing tests to mirror: `seihou-cli/test/Seihou/CLI/AgentLaunchSpec.hs` already unit-tests
`formatReferenceFiles` (import list, `describe`/`it`/`shouldBe` hspec style, wrapped as a
`Test.Tasty.Hspec.testSpec` tree). `seihou-cli/test/Seihou/CLI/PromptRenderSpec.hs` shows the
render-assertion style (`shouldSatisfy` / `T.isInfixOf`). New tests go into
`AgentLaunchSpec.hs`, which is already registered in the test suite's tasty tree.


## Plan of Work

### Milestone 1: Deliver the blueprint's `files/` directory to the running agent

Scope: make the "## Reference Files" listing truthful by (a) mounting the blueprint's
`files/` directory as an accessible provider directory and (b) printing its absolute path in
the rendered prompt with instructions to read the files directly, keeping a fallback when no
directory is available. At the end, `seihou agent --debug run <blueprint>` prints the real
`files/` path, a unit test pins the rendered guidance, and a launcher unit test proves the
directory is appended to the provider's accessible directories.

Edits:

1. `seihou-cli/data/blueprint-prompt.md` — replace the body of the "## Reference Files"
   section so it consumes a new `{{reference_files_dir}}` placeholder in addition to the
   existing `{{reference_files}}` list. New wording (prose): the files listed below live in
   the blueprint's `files/` directory; then `{{reference_files_dir}}` renders either
   "These files are readable at: `<abs path>` — open them directly with your file tools
   before asking the user." (interactive, directory mounted) or "These files are not mounted
   in this session; ask the user to paste any reference you need and never claim to have read
   one." (no directory). Keep `{{reference_files}}` as the name/description list. Update
   Workflow step 1 to prefer reading from the mounted directory over asking.

2. `seihou-cli/src/Seihou/CLI/AgentLaunch.hs` — add and export a pure helper:

   ```haskell
   -- | Render the "reference files directory" guidance line. @Just dir@ means
   -- the blueprint's @files/@ directory is mounted and readable at @dir@;
   -- @Nothing@ means no directory is available (API providers / no files/).
   formatReferenceFilesDir :: Maybe FilePath -> Text
   formatReferenceFilesDir (Just dir) =
     "These files are readable at: " <> T.pack dir
       <> " — open them directly with your file tools before asking the user."
   formatReferenceFilesDir Nothing =
     "These files are not mounted in this session; ask the user to paste any "
       <> "reference you need and never claim to have read one."
   ```

   Correct the misleading Haddock on `formatReferenceFiles` so it describes the real
   mechanism (the runner mounts `files/` when it exists and prints its path via
   `formatReferenceFilesDir`).

3. `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`:
   - Add imports: `System.FilePath ((</>))` (extend the existing `takeDirectory` import),
     `System.Directory (doesDirectoryExist, makeAbsolute)`, and `formatReferenceFilesDir`
     from `Seihou.CLI.AgentLaunch`.
   - In `handleAgentRun`, after `(bp, blueprintDir)` is bound and before rendering, compute
     the optional mounted directory:

     ```haskell
     let filesDir = blueprintDir </> "files"
     filesExist <- doesDirectoryExist filesDir
     mFilesDir <- if filesExist then Just <$> makeAbsolute filesDir else pure Nothing
     ```

   - Change `renderSystemPrompt` to take `mFilesDir` and add
     `("reference_files_dir", formatReferenceFilesDir mFilesDir)` to its substitution list.
   - Change `runRenderedAgentPrompt` to also receive `mFilesDir :: Maybe FilePath` (the extra
     directory to mount). In its `claude-cli`/`codex-cli` branch, pass it through to the
     launcher (see edit 4). Thread `mFilesDir` from `handleAgentRun`'s call site.
     **This is an exported, shared function** — see edit 5.

5. `seihou-cli/src-exe/Seihou/CLI/PromptRun.hs` — `AgentRun.runRenderedAgentPrompt` is also
   called here (the `seihou prompt` runner), so the signature change in edit 3 breaks this
   module unless its call site is updated in lockstep. Update the call at line 140 to pass
   `Nothing` for the new `mFilesDir` argument, preserving the prompt path's current behavior
   (no `files/` directory is mounted for prompts in this plan). No other change to `PromptRun`
   is needed for Milestone 1.

4. `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs` — refactor so the blueprint run can add
   directories without duplicating the session-dir logic and without disturbing
   assist/setup/bootstrap:

   ```haskell
   -- Existing entry point keeps its behavior:
   launchConfiguredAgent :: AgentModelConfig -> [String] -> Bool -> Text -> Maybe Text -> IO ExitCode
   launchConfiguredAgent = launchConfiguredAgentAddingDirs []

   -- New: session dirs PLUS caller-supplied extra dirs (e.g. a blueprint's files/):
   launchConfiguredAgentAddingDirs :: [FilePath] -> AgentModelConfig -> [String] -> Bool -> Text -> Maybe Text -> IO ExitCode
   launchConfiguredAgentAddingDirs extra modelConfig tools debug systemPrompt initialPrompt = do
     sessionDirs <- KitSession.agentDirsForSession seihouKitConfig
     launchConfiguredAgentWith (sessionDirs <> extra) modelConfig tools debug systemPrompt initialPrompt
   ```

   Export `launchConfiguredAgentAddingDirs`. `AgentRun.runRenderedAgentPrompt` calls it with
   `maybeToList mFilesDir` as the extra dirs. `Assist`/`Setup`/`Bootstrap` continue calling
   `launchConfiguredAgent` unchanged.

Tests (Milestone 1):

- In `seihou-cli/test/Seihou/CLI/AgentLaunchSpec.hs`, add a `describe "formatReferenceFilesDir"`:
  - `formatReferenceFilesDir (Just "/tmp/bp/files")` satisfies `T.isInfixOf "/tmp/bp/files"`
    and `T.isInfixOf "open them directly"`.
  - `formatReferenceFilesDir Nothing` satisfies `T.isInfixOf "ask the user"` and does **not**
    contain `"readable at"`.

Acceptance (Milestone 1): `cabal build seihou-cli` and `cabal test seihou-cli-test` pass;
`seihou agent --debug run <blueprint>` on a blueprint whose directory contains a `files/`
subdirectory prints the absolute `files/` path inside the "## Reference Files" block; on a
blueprint with no `files/` it prints the "not mounted … ask the user" fallback.

### Milestone 2: Honor the blueprint's `allowedTools`

Scope: stop discarding `blueprint.allowedTools`. Resolve the effective tool list as the base
`setupAllowedTools` unioned with the blueprint's declared tools, and pass that to the
launcher. At the end a blueprint declaring extra tools passes the effective set through the
runner, and Claude Code pre-approves it; unit tests prove the resolution semantics. Codex
keeps its existing sandbox and approval policy because it has no per-tool allow-list.

Edits:

1. `seihou-cli/src/Seihou/CLI/AgentLaunch.hs` — add and export:

   ```haskell
   -- | Effective pre-approved tools for a blueprint run: the base set every
   -- blueprint needs, plus any the blueprint declares, de-duplicated,
   -- base-first. @Nothing@ (no declaration) yields exactly the base set.
   resolveBlueprintTools :: Maybe [Text] -> [String]
   resolveBlueprintTools declared =
     let extra = map T.unpack (concat (maybeToList declared))
      in nub (setupAllowedTools <> extra)
   ```

   (Add `Data.List (nub)` and `Data.Maybe (maybeToList)` imports as needed.)

2. `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` — give `runRenderedAgentPrompt` a `tools ::
   [String]` parameter (replacing the internal hard-coded `setupAllowedTools`), and pass
   `resolveBlueprintTools bp.allowedTools` from `handleAgentRun`'s call site. Combined with
   Milestone 1, the `claude-cli`/`codex-cli` branch now reads:

   ```haskell
   exitCode <- launchConfiguredAgentAddingDirs (maybeToList mFilesDir) modelConfig tools debug systemPrompt initialPrompt
   ```

   where `tools` is the new parameter, supplied at the blueprint call site as
   `resolveBlueprintTools bp.allowedTools`.

3. `seihou-cli/src-exe/Seihou/CLI/PromptRun.hs` — the shared `runRenderedAgentPrompt` gains
   the `tools` parameter, so update the call at line 140 (already touched in Milestone 1) to
   pass `setupAllowedTools`, preserving the prompt path's exact current tool set. Add
   `setupAllowedTools` to the existing `Seihou.CLI.AgentLaunch` import in `PromptRun.hs`
   (it currently imports only `gatherAgentContext` from that module).

Tests (Milestone 2): in `AgentLaunchSpec.hs`, add `describe "resolveBlueprintTools"`:
- `resolveBlueprintTools Nothing` `shouldBe` `setupAllowedTools`.
- `resolveBlueprintTools (Just ["Bash(mori *)"])` contains every element of
  `setupAllowedTools` and also `"Bash(mori *)"`, with no duplicates
  (`length result == length (nub result)`).
- `resolveBlueprintTools (Just ["Read"])` (a base member) does not lengthen the list beyond
  the base set (idempotent union).

Acceptance (Milestone 2): `cabal test seihou-cli-test` passes including the new cases.

### Milestone 3: Correct documentation and finalize

Scope: bring the prose in sync with the new behavior and validate the whole change.

Edits:
- `seihou-cli/help/blueprints.md`, `docs/user/blueprints.md`, and
  `docs/user/agent-assistance.md`: state that reference
  files are readable from the mounted `files/` directory during interactive
  (`claude-cli`/`codex-cli`) runs and that `allowedTools` is added to the base set, with the
  Claude Code pre-approval and Codex sandbox boundary stated explicitly.
- Confirm the `formatReferenceFiles` Haddock in `AgentLaunch.hs` now matches reality (done in
  M1).
- `CHANGELOG.md` — add entries under the unreleased section: "blueprint runner now mounts the
  blueprint's `files/` directory and points the agent at it" and "blueprint `allowedTools`
  is now honored (unioned with the base tool set)."

Acceptance (Milestone 3): the full validation block in "Concrete Steps" passes, docs mention
both behaviors, and the working tree is clean except for the intended files.


## Concrete Steps

Work from the repository root. Capture a baseline first:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
git status --short
git rev-parse --abbrev-ref HEAD
```

Build and run the existing tests to confirm a green starting point:

```bash
cabal build seihou-cli
cabal test seihou-cli-test
```

Make the Milestone 1 and 2 edits described above, then rebuild and re-test:

```bash
cabal build seihou-cli
cabal test seihou-cli-test
```

Expected: the suite passes, including the new `formatReferenceFilesDir` and
`resolveBlueprintTools` cases. Example expected fragment:

```text
Seihou.CLI.AgentLaunch
  formatReferenceFilesDir
    renders the mounted path with read-directly guidance [✔]
    renders the ask-the-user fallback when no directory [✔]
  resolveBlueprintTools
    returns exactly the base set when nothing is declared [✔]
    unions declared tools onto the base set without duplicates [✔]
```

Demonstrate the user-visible prompt change with `--debug` (which prints the rendered system
prompt and does not launch a provider). Point it at any blueprint directory that has a
`files/` subdirectory — for example a scratch fixture:

```bash
mkdir -p /tmp/bp-demo/blueprints/demo/files
cat > /tmp/bp-demo/blueprints/demo/files/notes.md <<'EOF'
# demo reference
EOF
cat > /tmp/bp-demo/blueprints/demo/blueprint.dhall <<'EOF'
let S = <the same schema import used by an existing blueprint>
in  S.Blueprint::{ name = "demo", prompt = "Do the thing.", files = [ S.Blueprint.BlueprintFile::{ src = "notes.md" } ] }
EOF
```

Then render it (adjust discovery so the runner finds it — e.g. run from a directory whose
search path includes `blueprints/`), and confirm the "## Reference Files" block now contains
an absolute path ending in `/blueprints/demo/files` plus the "open them directly" guidance:

```bash
seihou agent --debug run demo --no-baseline | sed -n '/## Reference Files/,/## Your Task/p'
```

Expected fragment (path will differ):

```text
## Reference Files

The blueprint includes the following reference files in its `files/` subdirectory.

  - notes.md
These files are readable at: /private/tmp/bp-demo/blueprints/demo/files — open them directly with your file tools before asking the user.
```

Format, then run the full check the way CI would. The repository's `Justfile` defines the
relevant targets (`just format`, `just build`, `just test`, `just check`):

```bash
just format
just check      # build + test + any configured lints
git diff --check
git status --short
```

If `just` is unavailable, the equivalent direct commands are `cabal build all` and
`cabal test all` (the test suites are `seihou-cli-test` and `seihou-core-test`).

Review the diff, update this living document (Progress, Surprises, Decision Log, Outcomes),
then commit with a Conventional Commit subject and the active ExecPlan and Intention trailers:

```text
feat(agent-run): mount blueprint files/ and honor allowedTools

ExecPlan: docs/plans/62-deliver-blueprint-reference-files-and-honor-allowedtools-in-the-agent-runner.md
Intention: intention_01kxkabjrge3gtsqff461r7nv5
```


## Validation and Acceptance

Acceptance is behavioral, not merely "it compiles."

1. Reference files are reachable. After the change, `seihou agent --debug run <blueprint>` for
   a blueprint with a `files/` directory prints that directory's absolute path in the
   "## Reference Files" block with instructions to read the files directly. For a blueprint
   with no `files/`, it prints the "not mounted … ask the user" fallback and no path. The unit
   test `formatReferenceFilesDir` pins both strings. The launcher change is proven by
   inspection plus the fact that `runRenderedAgentPrompt` now calls
   `launchConfiguredAgentAddingDirs (maybeToList mFilesDir) …`, appending the directory to the
   provider's `extraDirs` (the same channel that already delivers the session agent dirs).

2. `allowedTools` is honored. The unit test `resolveBlueprintTools` proves: `Nothing`
   yields exactly `setupAllowedTools`; a declared tool appears in the result alongside the
   full base set; and the union never duplicates. `runRenderedAgentPrompt` passes
   `resolveBlueprintTools bp.allowedTools` (not the bare `setupAllowedTools`) to the launcher,
   so a blueprint declaring `allowedTools = Some [ "Bash(mori *)" ]` gets that tool
   pre-approved in Claude Code. Codex receives its existing workspace-write sandbox and
   on-request approval settings because it has no per-tool allow-list option.

3. No regressions. `seihou agent run` for the `assist`, `setup`, and `bootstrap` commands is
   unchanged: they still call `launchConfiguredAgent` with their existing tool sets and gain
   no blueprint directory. `seihou prompt` is likewise unchanged behaviorally: its updated
   call to the shared `runRenderedAgentPrompt` passes `setupAllowedTools` and `Nothing`, so it
   still launches with the same tools and mounts no `files/` directory — the only reason it is
   edited is to satisfy the new signature. `cabal test all` passes. `git diff --check` reports
   no whitespace errors.

Exact commands: `cabal build all`, `cabal test all` (which includes `seihou-cli-test` and
`seihou-core-test`), and `git diff --check` must all succeed. The new hspec cases in
`seihou-cli/test/Seihou/CLI/AgentLaunchSpec.hs` must pass.


## Idempotence and Recovery

All steps are repeatable. `cabal build`, `cabal test`, and the formatter can be re-run freely.
The `--debug` render does not contact a provider, but it does update applied-blueprint
provenance in `.seihou/manifest.json`, so run it only in a disposable fixture. The
`/tmp/bp-demo` fixture is disposable — delete it with `rm -rf /tmp/bp-demo` when done; nothing
in the repository depends on it. If an edit breaks the build, revert the specific file with `git checkout --
<path>` and reapply following the Plan of Work; because the pure helpers live in
`AgentLaunch.hs` behind explicit signatures, they can be developed and tested in isolation
before wiring them into `AgentRun.hs`. No data is migrated and no external service is touched.


## Interfaces and Dependencies

New/changed interfaces in `Seihou.CLI.AgentLaunch` (library, `seihou-cli/src/`):

```haskell
formatReferenceFilesDir :: Maybe FilePath -> Text
resolveBlueprintTools   :: Maybe [Text] -> [String]
```

New/changed interface in `Seihou.CLI.AgentLaunchExec` (exe, `seihou-cli/src-exe/`):

```haskell
launchConfiguredAgent          :: AgentModelConfig -> [String] -> Bool -> Text -> Maybe Text -> IO ExitCode
launchConfiguredAgentAddingDirs :: [FilePath] -> AgentModelConfig -> [String] -> Bool -> Text -> Maybe Text -> IO ExitCode
```

`launchConfiguredAgent = launchConfiguredAgentAddingDirs []` preserves the existing three
callers. `launchConfiguredAgentWith` is unchanged.

Changed internals in `Seihou.CLI.AgentRun` (exe): `renderSystemPrompt` gains a `Maybe FilePath`
parameter and a `("reference_files_dir", …)` substitution entry; the **exported**
`runRenderedAgentPrompt` gains a `tools :: [String]` parameter and a `mFilesDir :: Maybe
FilePath` parameter and calls `launchConfiguredAgentAddingDirs`. Its new signature is:

```haskell
runRenderedAgentPrompt :: Bool -> AgentModelConfig -> [String] -> Maybe FilePath -> Text -> Maybe Text -> IO Bool
```

Because `runRenderedAgentPrompt` is exported and reused by `Seihou.CLI.PromptRun`
(`seihou prompt`), that second call site is updated in the same change to pass
`setupAllowedTools` and `Nothing`, preserving the prompt path's current behavior. The three
`Assist`/`Setup`/`Bootstrap` modules define their own same-named local helpers and are not
affected.

Dependencies used (all already in scope for these packages): `System.Directory
(doesDirectoryExist, makeAbsolute)`, `System.FilePath ((</>))`, `Data.List (nub)`,
`Data.Maybe (maybeToList)`, and `Baikai.Kit.Session (agentDirsForSession)` via the existing
`seihouKitConfig`. No new package dependency and no Dhall schema change (`allowedTools`
already exists in `schema/Blueprint.dhall`). The interactive providers consume the mounted
directory through the already-wired `extraDirs` field of the Baikai interactive launch
request. Claude Code consumes the resolved tools through `ClaudeAllowedTools`; Codex uses its
existing `CodexSandbox` settings and has no per-tool allow-list. No Baikai change is required.

Types that must exist at completion: `Blueprint.files :: [BlueprintFile]` and
`Blueprint.allowedTools :: Maybe [Text]` (already present in
`seihou-core/src/Seihou/Core/Types.hs`); the two new library functions above; and the
augmented launcher signature. The blueprint prompt template
`seihou-cli/data/blueprint-prompt.md` must contain a `{{reference_files_dir}}` placeholder
that `renderSystemPrompt` fills.


## Revision Notes

- 2026-07-15 — Validation pass against the working tree. Confirmed the plan's claims are
  accurate: file paths, the `Blueprint`/`BlueprintFile` types and `allowedTools :: Maybe
  [Text]`, `schema/Blueprint.dhall`'s `allowedTools`, the `extraDirs` + `ClaudeAllowedTools`
  wiring in `AgentLaunchExec` (both the `claude-cli` and `codex-cli` branches pass
  `extraDirs`), the `--debug` short-circuit in `runRenderedAgentPrompt` and
  `launchConfiguredAgentWith`, the template placeholders, and the existing
  `AgentLaunchSpec.hs` test style all check out. Fixed one build-breaking omission: the
  exported `AgentRun.runRenderedAgentPrompt` is also called by
  `seihou-cli/src-exe/Seihou/CLI/PromptRun.hs` (`seihou prompt`), so its signature change in
  Milestones 1 and 2 requires updating that call site (pass `Nothing` and `setupAllowedTools`
  to preserve behavior). Added `PromptRun.hs` to Context and Orientation, new edit steps in
  Milestones 1 and 2, the Progress checklist, the Decision Log, the No-regressions acceptance
  criterion, and the Interfaces section; also confirmed the `Assist`/`Setup`/`Bootstrap`
  modules define their own local `runRenderedAgentPrompt` and are unaffected. Tightened the
  Milestone 3 docs edit to name the real files (`docs/user/blueprints.md`,
  `docs/user/agent-assistance.md`, `seihou-cli/help/blueprints.md`).

- 2026-07-15 — Implementation pass. Added the requested Intention ID and completed all three
  milestones. Corrected two assumptions with runtime/source evidence: blueprint debug
  renders update manifest provenance, and Baikai supports per-tool pre-approval only for
  Claude Code while Codex retains sandbox/on-request approval semantics. Updated Purpose,
  Context, Milestone 2, documentation instructions, validation, recovery guidance,
  dependencies, Surprises, and Decision Log so the plan remains self-contained and does not
  overpromise provider behavior.
