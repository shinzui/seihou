# Add `agent consume` Command

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, users can run `seihou agent consume` to launch an AI-powered
session that guides them through the full lifecycle of *using* a Seihou module:
selecting a module, configuring variables, setting up context and config, running the
module to generate files, and committing the resulting changes to a git repository.

Where `agent assist` helps *author* modules and `agent bootstrap` helps *create* them,
`agent consume` helps *use* them — the consumer-side workflow. The agent has full
knowledge of the user's seihou environment (available modules, manifest state, config
layers, contexts) and can orchestrate multi-step workflows that would otherwise require
the user to manually chain `seihou config set`, `seihou context set`, `seihou run`,
and `git commit` commands.

**User-visible behavior after implementation:**

```
$ seihou agent consume
# → launches Claude Code session with consume-oriented system prompt

$ seihou agent consume "set up a haskell project with nix"
# → launches with an initial prompt guiding the agent

$ seihou agent consume --debug
# → prints the resolved system prompt without launching
```


## Progress

- [x] Add `ConsumeOpts` type to `Commands.hs` (2026-03-13)
- [x] Add `AgentConsume` constructor to `AgentCommand` (2026-03-13)
- [x] Add consume subcommand parser in `Commands.hs` (2026-03-13)
- [x] Export new types from `Commands` module (2026-03-13)
- [x] Create `data/consume-prompt.md` prompt template (2026-03-13)
- [x] Create `Seihou.CLI.Consume` handler module (2026-03-13)
- [x] Register `Consume` module in `seihou-cli.cabal` (executable other-modules) (2026-03-13)
- [x] Wire `AgentConsume` case in `Main.hs` (2026-03-13)
- [x] Update agent footer help text in `Commands.hs` (2026-03-13)
- [x] Build and verify `seihou agent consume --help` works (2026-03-13)
- [x] Build and verify `seihou agent consume --debug` prints prompt (2026-03-13)
- [x] Verify prompt template substitution is correct (2026-03-13)


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Model the consume command identically to assist/bootstrap — same `AgentOpts`
  wrapper with `--debug` flag, same `launchAgent` infrastructure, same `gatherAgentContext`
  for environment discovery.
  Rationale: Consistency with existing agent subcommands minimizes new code and cognitive
  load. The differentiation is entirely in the system prompt, not the launch mechanism.
  Date: 2026-03-13

- Decision: The consume prompt should include the full CLI command reference (all commands,
  not just authoring commands) and emphasize the workflow: discover → configure → run →
  verify → commit.
  Rationale: The consumer workflow touches config, context, vars, run, status, diff, and
  git — a broader surface than assist or bootstrap.
  Date: 2026-03-13

- Decision: No new Haskell dependencies required.
  Rationale: All infrastructure (file-embed, AgentLaunch, optparse-applicative) already
  exists.
  Date: 2026-03-13


## Outcomes & Retrospective

All three milestones completed in a single pass. The implementation followed the existing
agent subcommand pattern exactly — no surprises or deviations from the plan.

**Validation results:**
- `cabal build seihou` — succeeded with no errors
- `seihou agent --help` — lists all three subcommands (assist, bootstrap, consume)
- `seihou agent consume --help` — shows usage, PROMPT metavar, and footer
- `seihou agent --debug consume` — prints full system prompt with all placeholders substituted
- Placeholder substitution confirmed: cwd, project state, manifest state, available modules all resolved

**Files changed:** 5 (2 new, 3 modified)
- `seihou-cli/src/Seihou/CLI/Commands.hs` — new types, parser, help text
- `seihou-cli/data/consume-prompt.md` — new prompt template
- `seihou-cli/src/Seihou/CLI/Consume.hs` — new handler module
- `seihou-cli/src/Main.hs` — import + dispatch
- `seihou-cli/seihou-cli.cabal` — module registration


## Context and Orientation

### Project layout

Seihou is a multi-package Haskell workspace:

- `seihou-core/` — library: domain types, effects, engine, Dhall integration
- `seihou-cli/` — executable + internal library: CLI parsing, command handlers, agent launch

### Agent command architecture

The agent system already supports two subcommands (`assist`, `bootstrap`) using this
pattern:

1. **Type** in `seihou-cli/src/Seihou/CLI/Commands.hs`:
   - `AgentOpts` wraps `agentDebug :: Bool` + `agentCommand :: AgentCommand`
   - `AgentCommand` is a sum type with one constructor per subcommand
   - Each subcommand has its own options type (e.g., `AssistOpts`, `BootstrapOpts`)

2. **Parser** in `Commands.hs`:
   - `agentCommandParser` builds a `subparser` with one `command` per subcommand
   - Each subcommand has a `ParserInfo` with progDesc and footer help text

3. **Handler** in a dedicated module (e.g., `Seihou.CLI.Assist`):
   - Embeds a prompt template from `data/` via `file-embed` at compile time
   - Calls `gatherAgentContext` to collect environment state
   - Calls `renderPrompt` to substitute `{{placeholders}}` with context
   - Calls `launchAgent debug systemPrompt initialPrompt` to either print or launch

4. **Prompt template** in `seihou-cli/data/*.md`:
   - Markdown document with `{{placeholder}}` variables
   - Contains: role description, environment context, schema reference, CLI commands,
     workflow guidance, tool guidelines

5. **Wiring** in `seihou-cli/src/Main.hs`:
   - Pattern match on `AgentConsume consumeOpts` to call `handleConsume`

6. **Registration** in `seihou-cli/seihou-cli.cabal`:
   - Add module to `other-modules` list under the `executable seihou` section

### Key files to modify

| File | What to do |
|------|-----------|
| `seihou-cli/src/Seihou/CLI/Commands.hs` | Add `ConsumeOpts`, `AgentConsume` constructor, parser, help text |
| `seihou-cli/src/Seihou/CLI/Consume.hs` | New file: handler (same pattern as Assist.hs) |
| `seihou-cli/data/consume-prompt.md` | New file: system prompt template |
| `seihou-cli/src/Main.hs` | Import + dispatch `AgentConsume` |
| `seihou-cli/seihou-cli.cabal` | Register `Seihou.CLI.Consume` in other-modules |

### Shared infrastructure (no changes needed)

| Module | Purpose |
|--------|---------|
| `Seihou.CLI.AgentLaunch` | `gatherAgentContext`, `launchAgent`, `substitute`, format helpers |
| `file-embed` | Compile-time embedding of prompt templates |


## Plan of Work

### Milestone 1: Types and Parsing

Add the consume subcommand to the CLI parser in `Commands.hs`.

**In `seihou-cli/src/Seihou/CLI/Commands.hs`:**

1. Add `ConsumeOpts` type after `BootstrapOpts` (line ~149):
   ```haskell
   data ConsumeOpts = ConsumeOpts
     { consumePrompt :: Maybe Text
     }
     deriving stock (Eq, Show, Generic)
   ```

2. Add `AgentConsume ConsumeOpts` constructor to `AgentCommand` (line ~64):
   ```haskell
   data AgentCommand
     = AgentAssist AssistOpts
     | AgentBootstrap BootstrapOpts
     | AgentConsume ConsumeOpts
     deriving stock (Eq, Show, Generic)
   ```

3. Add consume to the module export list (add `ConsumeOpts (..)` after `BootstrapOpts (..)`).

4. Add `agentConsumeInfo` and `agentConsumeParser` (after `agentBootstrapParser`, line ~679):
   ```haskell
   agentConsumeInfo :: ParserInfo AgentCommand
   agentConsumeInfo =
     info
       (agentConsumeParser <**> helper)
       ( fullDesc
           <> progDesc "Guided module consumption: configure, run, and commit"
           <> footerDoc
             ( Just $
                 vsep
                   [ pretty ("..." :: String)
                   ...
                   ]
             )
       )

   agentConsumeParser :: Parser AgentCommand
   agentConsumeParser =
     fmap AgentConsume $
       ConsumeOpts
         <$> optional (argument (T.pack <$> str) (metavar "PROMPT" <> help "Description of what you want to set up"))
   ```

5. Register `"consume"` in `agentCommandParser` (line ~607):
   ```haskell
   agentCommandParser =
     subparser
       ( command "assist" agentAssistInfo
           <> command "bootstrap" agentBootstrapInfo
           <> command "consume" agentConsumeInfo
       )
   ```

6. Update the agent footer help text to list the consume subcommand (line ~589).

**Acceptance:** `cabal build seihou` succeeds. `seihou agent --help` lists all three
subcommands.


### Milestone 2: Prompt Template

Create the consume-oriented system prompt at `seihou-cli/data/consume-prompt.md`.

The prompt should:

- Establish the agent's role as a module consumption assistant
- Include the current environment context block (same `{{placeholders}}` as assist/bootstrap)
- Provide the full CLI command reference (broader than assist — includes config, context,
  install, run, status, diff, vars, list)
- Describe a consumption workflow: discover → select → configure (vars, config, context) →
  preview (dry-run) → run → verify (status, diff) → commit
- Include guidance on git operations: initializing a repo if needed, staging generated files,
  writing meaningful commit messages, handling `.seihou/` directory
- Include the module schema reference (so the agent can explain modules to the user)
- Include tool guidelines

**Acceptance:** The file exists and contains all `{{placeholders}}` that `gatherAgentContext`
provides.


### Milestone 3: Handler and Wiring

Create the handler module and wire everything together.

**Create `seihou-cli/src/Seihou/CLI/Consume.hs`:**

Follow the exact pattern of `Assist.hs`:
- Embed `data/consume-prompt.md` via `file-embed`
- Export `handleConsume :: Bool -> ConsumeOpts -> IO ()`
- Gather context, render prompt, launch agent

**In `seihou-cli/src/Main.hs`:**

1. Add import: `import Seihou.CLI.Consume (handleConsume)`
2. Add case in the `Agent agentOpts -> case agentOpts.agentCommand of` block:
   ```haskell
   AgentConsume consumeOpts ->
     handleConsume agentOpts.agentDebug consumeOpts
   ```

**In `seihou-cli/seihou-cli.cabal`:**

Add `Seihou.CLI.Consume` to the `other-modules` list under `executable seihou`
(alphabetically, after `Seihou.CLI.Config`).

**Acceptance:** `cabal build seihou` succeeds. `seihou agent consume --debug` prints the
resolved system prompt with all placeholders substituted.


## Concrete Steps

All commands run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

### Step 1: Edit Commands.hs

Add `ConsumeOpts`, `AgentConsume`, parser, and help text as described in Milestone 1.

### Step 2: Create consume-prompt.md

```bash
# After writing the file:
cat seihou-cli/data/consume-prompt.md | head -5
# Expected: "You are a Seihou module consumption assistant..."
```

### Step 3: Create Consume.hs

```bash
# After writing the file:
cat seihou-cli/src/Seihou/CLI/Consume.hs | head -10
# Expected: module declaration and imports
```

### Step 4: Wire Main.hs and update cabal

### Step 5: Build

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
cabal build seihou
# Expected: builds successfully with no errors
```

### Step 6: Verify help text

```bash
cabal run seihou -- agent --help
# Expected output includes:
#   assist      Launch AI-assisted template authoring session
#   bootstrap   Bootstrap a new module or multi-module repository
#   consume     Guided module consumption: configure, run, and commit

cabal run seihou -- agent consume --help
# Expected: shows consume subcommand help with PROMPT argument
```

### Step 7: Verify debug mode

```bash
cabal run seihou -- agent consume --debug 2>&1 | head -3
# Expected: first lines of the rendered system prompt
```


## Validation and Acceptance

1. **Build succeeds:** `cabal build seihou` completes without errors.

2. **Help text:** `seihou agent --help` lists three subcommands: assist, bootstrap, consume.

3. **Subcommand help:** `seihou agent consume --help` shows the usage, PROMPT metavar,
   and footer description.

4. **Debug mode:** `seihou agent consume --debug` prints the full system prompt with
   `{{placeholders}}` replaced by actual environment values (cwd, module list, etc.).

5. **Initial prompt:** `seihou agent consume --debug "set up haskell"` prints the same
   prompt (the initial prompt is passed to claude, not printed in debug mode — debug only
   shows the system prompt).

6. **Parser completeness:** `seihou agent consume` (without --debug and without claude
   installed) prints the "claude not found" error, confirming the full dispatch path works.


## Idempotence and Recovery

All steps are safe to repeat:

- Editing `Commands.hs` is idempotent — the types and parsers either exist or they don't.
- Creating `Consume.hs` and `consume-prompt.md` can be retried by overwriting.
- Building is always safe to retry.

If the build fails, check:
- Module registered in cabal file
- All new types exported from `Commands` module
- Import added in `Main.hs`
- Pattern match exhaustive in `Main.hs`


## Interfaces and Dependencies

### No new dependencies required

All needed libraries are already in `seihou-cli.cabal`:
- `file-embed` — for compile-time prompt embedding
- `optparse-applicative` — for CLI parsing
- `text` — for Text operations

### New types

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

```haskell
data ConsumeOpts = ConsumeOpts
  { consumePrompt :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)
```

### New functions

In `seihou-cli/src/Seihou/CLI/Consume.hs`:

```haskell
handleConsume :: Bool -> ConsumeOpts -> IO ()
```

### Existing functions used (no changes needed)

In `Seihou.CLI.AgentLaunch`:

```haskell
gatherAgentContext :: IO AgentContext
launchAgent :: Bool -> Text -> Maybe Text -> IO ()
substitute :: [(Text, Text)] -> Text -> Text
formatSeihouProjectState :: AgentContext -> Text
formatManifestState :: AgentContext -> Text
formatModuleDhallState :: AgentContext -> Text
formatLocalModules :: AgentContext -> Text
formatAvailableModules :: AgentContext -> Text
```
