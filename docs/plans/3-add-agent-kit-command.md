---
id: 3
slug: add-agent-kit-command
title: "Add Agent Kit Command"
kind: exec-plan
created_at: 2026-04-03T14:40:08Z
intention: "intention_01kn9vq8ayerxab7m295qqpnb6"
---


# Add Agent Kit Command

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Users of seihou should be able to install, update, and remove Claude Code skills and
subagents from a distributable GitHub repository (`seihou-kit`), separately from seihou
binary releases. After this change a user can run:

```
seihou kit list                       # See available skills and agents
seihou kit install exec-plan          # Install a skill globally
seihou kit install exec-plan --project  # Install into the current project
seihou kit status                     # See what's installed and where
seihou kit update                     # Pull latest and re-install
seihou kit uninstall exec-plan        # Remove a skill
```

When the user then launches any agent session (`seihou agent assist`, etc.), the installed
skills and agents are automatically discovered via `--add-dir` flags passed to the `claude`
CLI, making them immediately available as slash commands and specialized agents in the
session.

This is an adaptation of the proven "Skill & Agent Registry (Kit)" pattern from the mori
project (reference implementation: `mori-cli/src/Mori/Command/Kit.hs`).


## Progress

- [x] M1-1: Add `KitCommand` and related types to `Kit.hs` (2026-04-03)
- [x] M1-2: Add kit command parser to `Commands.hs` and wire into command tree (2026-04-03)
- [x] M1-3: Create `Kit.hs` handler module with manifest types and all 5 subcommands (2026-04-03)
- [x] M1-4: Wire `Kit` dispatch into `Main.hs` (2026-04-03)
- [x] M1-5: Register `Seihou.CLI.Kit` in `seihou-cli.cabal` (2026-04-03)
- [x] M1-6: Add `kit` help topic (help file + wiring in `Help.hs`) (2026-04-03)
- [x] M1-7: Build and verify `seihou kit --help` shows all subcommands (2026-04-03)
- [x] M2-1: Add `agentDirsForSession` to `AgentLaunch.hs` (2026-04-03)
- [x] M2-2: Update `launchAgentWith` to accept and pass `--add-dir` arguments (2026-04-03)
- [x] M2-3: Update all agent handlers (Assist, Bootstrap, Setup) to call `agentDirsForSession` and pass dirs (2026-04-03)
- [x] M2-4: Build succeeds, all 99 CLI tests pass, `seihou kit status` works (2026-04-03)


## Surprises & Discoveries

- `NoFieldSelectors` is enabled globally via the cabal default-extensions. Bare field selectors
  like `skills manifest` don't work — must use `manifest.skills` (OverloadedRecordDot) or
  explicit pattern-match accessors. Fixed by using dot syntax for manifest access and keeping
  explicit accessors for use in `map`/`filter` callbacks.

- `DeriveAnyClass` is not implied by GHC2024 — needed an explicit `{-# LANGUAGE DeriveAnyClass #-}`
  pragma in Kit.hs for `deriving anyclass (FromJSON)` on manifest types.


## Decision Log

- Decision: Kit is a top-level command (`seihou kit`), not nested under `seihou agent kit`.
  Rationale: Kit manages files on disk (clone, copy, delete) — it is a lifecycle command, not
  an agent session. The agent integration is automatic and transparent. This matches the mori
  reference implementation.
  Date: 2026-04-03

- Decision: Use `seihou-kit` as the default kit repository name (`https://github.com/shinzui/seihou-kit.git`).
  Rationale: Follows the `<project>-kit` naming convention from the pattern document.
  Date: 2026-04-03

- Decision: Directory conventions — user scope: `~/.config/seihou/agents/`, project scope: `.seihou/agents/`, cache: `~/.cache/seihou/kit/`.
  Rationale: Aligns with seihou's existing config directory (`~/.config/seihou/`) and project directory (`.seihou/`).
  Date: 2026-04-03

- Decision: No new library dependencies. Uses `System.Process`, `System.Directory`, `Data.Aeson` (all already depended on).
  Rationale: The kit command is pure filesystem + git operations. All required modules are already in the dependency set.
  Date: 2026-04-03

- Decision: Use explicit record field accessors (pattern-match style) in Kit.hs to avoid DuplicateRecordFields ambiguity between `SkillEntry` and `AgentEntry`.
  Rationale: Both types share `name`, `description`, `path` fields. While `OverloadedRecordDot` works in many contexts, explicit accessors are clearer in `map` and `filter` callbacks. This matches the mori reference implementation's approach.
  Date: 2026-04-03


## Outcomes & Retrospective

Both milestones implemented and verified:

- `seihou kit` command with all 5 subcommands (list, install, update, uninstall, status)
- `seihou help kit` topic explaining usage, scopes, and caching
- Agent session integration via `--add-dir` for automatic kit content discovery
- All 99 existing CLI tests pass — no regressions
- Implementation closely follows the mori-kit reference (~480 lines in Kit.hs)

Files created: `seihou-cli/src/Seihou/CLI/Kit.hs`, `seihou-cli/help/kit.md`
Files modified: `Commands.hs`, `Main.hs`, `AgentLaunch.hs`, `Assist.hs`, `Bootstrap.hs`,
`Setup.hs`, `Help.hs`, `seihou-cli.cabal`


## Context and Orientation

### Project Structure

Seihou is a multi-package Haskell workspace:

- `seihou-core/` — core library (modules, types, engines, effects)
- `seihou-cli/` — CLI executable and handlers

The CLI uses `optparse-applicative` for command parsing with a central `Command` ADT in
`seihou-cli/src/Seihou/CLI/Commands.hs`. Each command has a handler module in
`seihou-cli/src/Seihou/CLI/<Name>.hs`.

### Key Files

| File | Purpose |
|------|---------|
| `seihou-cli/src/Seihou/CLI/Commands.hs` | Command ADT, all option types, all parsers (~1004 lines) |
| `seihou-cli/src/Main.hs` | Command dispatch (pattern match on `Command`) |
| `seihou-cli/src/Seihou/CLI/AgentLaunch.hs` | Agent session infrastructure (`launchAgent`, `gatherAgentContext`, allowed tools) |
| `seihou-cli/src/Seihou/CLI/Assist.hs` | Agent assist handler (embed prompt, launch claude) |
| `seihou-cli/src/Seihou/CLI/Bootstrap.hs` | Agent bootstrap handler |
| `seihou-cli/src/Seihou/CLI/Setup.hs` | Agent setup handler |
| `seihou-cli/src/Seihou/CLI/Help.hs` | Help topic system (`HelpTopic` list, `embedStringFile`) |
| `seihou-cli/seihou-cli.cabal` | Build config (module list, dependencies) |

### Existing Command ADT (relevant excerpt)

```haskell
data Command
  = Init | Run RunOpts | ... | Agent AgentOpts | HelpCmd HelpCommand | Completions CompletionsCommand
  deriving stock (Eq, Show, Generic)
```

The `Agent` variant nests `AgentOpts` which contains `AgentCommand` (a subparser for
`assist`, `bootstrap`, `setup`). Kit will NOT nest under `Agent` — it will be its own
top-level variant.

### Agent Launch Mechanism

`AgentLaunch.hs` exports `launchAgentWith :: [String] -> Bool -> Text -> Maybe Text -> IO ()`
which spawns `claude` with `--system-prompt` and `--allowedTools` flags. Currently it does NOT
pass `--add-dir`. After this plan, it will accept an additional `[FilePath]` argument for
add-dirs, enabling kit content discovery.

### Reference Implementation

The mori kit implementation at `mori-cli/src/Mori/Command/Kit.hs` (493 lines) provides all 5
subcommands (`list`, `install`, `update`, `uninstall`, `status`) with git caching, manifest
parsing, scope-aware installation, and graceful offline degradation. The seihou implementation
will follow this structure closely, adapted for seihou's conventions.

### Terms

- **Kit** — a distributable GitHub repository containing Claude Code skills and subagents
- **Skill** — a directory with a `SKILL.md` file; becomes a `/name` slash command in Claude Code
- **Subagent** — a markdown file defining a specialized autonomous agent for Claude Code
- **Kit manifest** — `kit.json` at the kit repo root; enumerates all available skills and agents
- **User scope** — `~/.config/seihou/agents/`; skills available across all projects
- **Project scope** — `.seihou/agents/`; skills scoped to a single project
- **Cache** — `~/.cache/seihou/kit/`; shallow clone of the kit repo


## Plan of Work

### Milestone 1: Kit Command (list, install, update, uninstall, status)

After this milestone, `seihou kit list` and all subcommands work end-to-end against a
`seihou-kit` GitHub repo. The kit repo does not need to exist yet — the command will print
a clear error if it cannot be cloned.

**Acceptance criteria:**
- `seihou kit --help` shows all 5 subcommands
- `seihou kit list` clones the kit repo and lists available items
- `seihou kit install <name>` copies files to user scope
- `seihou kit install <name> --project` copies files to project scope
- `seihou kit status` shows installed items with scope
- `seihou kit update` pulls latest and re-installs
- `seihou kit uninstall <name>` removes installed files
- `seihou help kit` shows the help topic
- `cabal build seihou` succeeds

#### Step 1: Add types to Commands.hs

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

Add a `Kit !KitCommand` variant to the `Command` ADT, between `SchemaUpgrade` and `Agent`.

Add the `KitCommand` and option types:

```haskell
data KitCommand
  = KitList
  | KitInstall !KitInstallOpts
  | KitUpdate !KitUpdateOpts
  | KitUninstall !KitUninstallOpts
  | KitStatus
  deriving stock (Eq, Show, Generic)

data KitInstallOpts = KitInstallOpts
  { kitItemName :: !Text,
    kitProjectScope :: !Bool
  }
  deriving stock (Eq, Show, Generic)

data KitUpdateOpts = KitUpdateOpts
  { kitUpdateName :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

data KitUninstallOpts = KitUninstallOpts
  { kitUninstallName :: !Text,
    kitUninstallProjectScope :: !Bool
  }
  deriving stock (Eq, Show, Generic)
```

Export `KitCommand (..)`, `KitInstallOpts (..)`, `KitUpdateOpts (..)`, `KitUninstallOpts (..)`.

#### Step 2: Add kit parser to Commands.hs

Add a `kitInfo :: ParserInfo Command` and `kitCommandParser :: Parser KitCommand` following
the pattern of the existing `agentInfo`/`agentCommandParser`. Wire it into the main
`commandParser` with `command "kit" kitInfo`.

The kit subparser uses `hsubparser` with a fallback to `KitList` (default when no subcommand
given), matching the mori reference.

#### Step 3: Create Kit.hs handler module

Create `seihou-cli/src/Seihou/CLI/Kit.hs` containing:

- Manifest types: `KitManifest`, `SkillEntry`, `AgentEntry`, `KitItem`, `KitScope`
- Constants: `defaultKitRepoUrl`
- Git operations: `ensureKitRepo`, `pullKitRepo`, `kitCacheDir`
- Manifest operations: `loadManifest`, `lookupItem`
- Directory helpers: `resolveTargetDir`, `isInstalled`, `scopeLabel`
- Subcommand handlers: `listAvailable`, `installItem`, `updateKit`, `uninstallItem`, `kitStatus`
- Top-level dispatch: `runKit :: KitCommand -> IO ()`

This follows the mori `Kit.hs` structure closely, replacing `"mori"` with `"seihou"` in
all paths and messages.

#### Step 4: Wire dispatch in Main.hs

Add `import Seihou.CLI.Kit (runKit)` and a `Kit kitCmd -> runKit kitCmd` case in the main
dispatch.

#### Step 5: Register module in cabal

Add `Seihou.CLI.Kit` to `other-modules` in the `executable seihou` stanza of
`seihou-cli/seihou-cli.cabal`.

#### Step 6: Add help topic

Create `seihou-cli/help/kit.md` explaining the kit system: what it is, how to use each
subcommand, scoping, caching, and how installed content is discovered by agent sessions.

In `seihou-cli/src/Seihou/CLI/Help.hs`, add a `HelpTopic "kit" "Manage Claude Code skills and subagents" kitContent` entry and embed the file with `$(embedStringFile "help/kit.md")`.

### Milestone 2: Agent Session Integration

After this milestone, `seihou agent assist` (and bootstrap, setup) automatically discover
installed kit content and pass it to the claude CLI via `--add-dir`.

**Acceptance criteria:**
- `seihou agent --debug assist` output includes `--add-dir` flags for existing scope directories
- Skills installed via `seihou kit install` are available as slash commands in agent sessions
- If no kit content is installed, no `--add-dir` flags are added (no error)

#### Step 1: Add agentDirsForSession to AgentLaunch.hs

Add a function that checks both scope directories and returns those that exist:

```haskell
agentDirsForSession :: IO [FilePath]
agentDirsForSession = do
  home <- getHomeDirectory
  cwd <- getCurrentDirectory
  let userAgentDir    = home </> ".config" </> "seihou" </> "agents"
      projectAgentDir = cwd </> ".seihou" </> "agents"
  filterM doesDirectoryExist [userAgentDir, projectAgentDir]
```

Export it from the module.

#### Step 2: Update launchAgentWith signature

Change `launchAgentWith` to accept an additional `[FilePath]` parameter for add-dirs:

```haskell
launchAgentWith :: [FilePath] -> [String] -> Bool -> Text -> Maybe Text -> IO ()
```

In the argument construction, add `concatMap (\d -> ["--add-dir", d]) addDirs` before the
`--allowedTools` flags.

Update `launchAgent` to call `agentDirsForSession` and pass the result.

#### Step 3: Update all agent handlers

Update `Assist.hs`, `Bootstrap.hs`, and `Setup.hs` to call `agentDirsForSession` and pass
the result to the updated `launchAgentWith`.


## Concrete Steps

All commands are run from the repository root:
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

### Build after each milestone

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
cabal build seihou
```

Expected: compiles successfully with no errors.

### Verify CLI help

```bash
cabal run seihou -- kit --help
```

Expected output (approximately):
```
Usage: seihou kit COMMAND

  Manage Claude Code skills and subagents

Available commands:
  list                     List available skills and subagents
  install                  Install a skill or subagent
  update                   Update installed skills and subagents
  uninstall                Uninstall a skill or subagent
  status                   Show installed skills and subagents
```

### Verify help topic

```bash
cabal run seihou -- help kit
```

Expected: Prints the kit help topic content.

### Verify agent debug output includes add-dirs

```bash
mkdir -p ~/.config/seihou/agents/.claude/skills/test-skill
echo "test" > ~/.config/seihou/agents/.claude/skills/test-skill/SKILL.md
cabal run seihou -- agent --debug assist 2>&1 | head -5
# (verify system prompt is printed — the --add-dir integration happens at launch time,
#  so debug mode won't show it, but we can verify the code path by reading the source)
rm -rf ~/.config/seihou/agents/.claude/skills/test-skill
```


## Validation and Acceptance

1. **Build succeeds:** `cabal build seihou` completes without errors.

2. **Kit subcommands parse:** `seihou kit --help` shows all 5 subcommands. Each subcommand's
   `--help` shows its flags.

3. **Help topic works:** `seihou help kit` prints the kit documentation. `seihou help` lists
   "kit" in the topic list.

4. **End-to-end with mock repo:** If `seihou-kit` repo exists on GitHub:
   - `seihou kit list` shows available items
   - `seihou kit install <name>` copies to `~/.config/seihou/agents/.claude/skills/<name>/`
   - `seihou kit status` shows the installed item with "user" scope
   - `seihou kit uninstall <name>` removes it
   - `seihou kit install <name> --project` copies to `.seihou/agents/.claude/skills/<name>/`

5. **Agent integration:** After installing a kit skill, running `seihou agent assist` launches
   claude with `--add-dir ~/.config/seihou/agents` (if directory exists), making the skill
   available as a slash command.

6. **Graceful degradation:** If `seihou-kit` repo doesn't exist yet, `seihou kit list` prints
   a clear error about the clone failure (or uses cached data if available).

7. **Idempotence:** Re-installing overwrites cleanly. Uninstalling a non-installed item prints
   a message without failing.


## Idempotence and Recovery

- **All kit operations are idempotent.** Install overwrites existing files. Uninstall of
  missing items prints a message but exits 0. Update re-copies changed files.

- **Cache is disposable.** Deleting `~/.cache/seihou/kit/` triggers a fresh clone on next use.

- **Shallow clone** (`--depth 1`) minimizes bandwidth. `git pull --ff-only` updates safely.

- **Build is safe to repeat.** `cabal build seihou` is always safe to re-run.

- **Recovery from failed clone:** If the initial clone fails and no cache exists, the command
  prints an error and exits. The user can retry after fixing network connectivity.


## Interfaces and Dependencies

### No new library dependencies

All required modules are already in `seihou-cli.cabal`'s build-depends:

| Module | Package | Purpose |
|--------|---------|---------|
| `Data.Aeson` | aeson | Parse `kit.json` manifest |
| `System.Directory` | directory | File/directory operations |
| `System.Process` | process | Run `git clone` and `git pull` |
| `System.FilePath` | filepath | Path manipulation |
| `Options.Applicative` | optparse-applicative | Kit subcommand parsers |
| `Data.FileEmbed` | file-embed | Embed help topic at compile time |

### New module

In `seihou-cli/src/Seihou/CLI/Kit.hs`, define and export:

```haskell
module Seihou.CLI.Kit
  ( KitCommand (..),
    KitInstallOpts (..),
    KitUpdateOpts (..),
    KitUninstallOpts (..),
    runKit,
    kitCommandParser,
  )
where
```

Note: The types `KitCommand`, `KitInstallOpts`, etc. are defined in `Kit.hs` rather than
`Commands.hs` because the kit command is self-contained and does not share types with other
commands. The `Command` ADT in `Commands.hs` simply wraps `KitCommand`.

### Updated module

In `seihou-cli/src/Seihou/CLI/AgentLaunch.hs`, add to exports:

```haskell
agentDirsForSession :: IO [FilePath]
```

Update signature of `launchAgentWith`:

```haskell
launchAgentWith :: [FilePath] -> [String] -> Bool -> Text -> Maybe Text -> IO ()
```

### Files created

| Path | Purpose |
|------|---------|
| `seihou-cli/src/Seihou/CLI/Kit.hs` | Kit command handler (~500 lines) |
| `seihou-cli/help/kit.md` | Help topic for `seihou help kit` |

### Files modified

| Path | Change |
|------|--------|
| `seihou-cli/src/Seihou/CLI/Commands.hs` | Add `Kit !KitCommand` to `Command`, import and re-export kit types, add parser |
| `seihou-cli/src/Main.hs` | Add `Kit` dispatch case, import `runKit` |
| `seihou-cli/src/Seihou/CLI/AgentLaunch.hs` | Add `agentDirsForSession`, update `launchAgentWith` signature to accept add-dirs |
| `seihou-cli/src/Seihou/CLI/Assist.hs` | Call `agentDirsForSession`, pass to `launchAgentWith` |
| `seihou-cli/src/Seihou/CLI/Bootstrap.hs` | Call `agentDirsForSession`, pass to `launchAgentWith` |
| `seihou-cli/src/Seihou/CLI/Setup.hs` | Call `agentDirsForSession`, pass to `launchAgentWith` |
| `seihou-cli/src/Seihou/CLI/Help.hs` | Add "kit" help topic entry |
| `seihou-cli/seihou-cli.cabal` | Add `Seihou.CLI.Kit` to `other-modules` |
