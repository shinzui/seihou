# Group CLI help output into coherent command groups

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Running `seihou --help` currently lists all 19 commands in a flat "Available commands"
section. As the command set has grown, this wall of commands is hard to scan. After this
change, `seihou --help` will group commands under labeled headings so users can quickly
find what they need:

```
Available commands:
  init                     Initialize Seihou configuration
  run                      Run modules to generate a project
  remove                   Remove an applied module and delete its generated files
  status                   Show manifest state
  diff                     Show changes since last generation

Module management:
  list                     List available modules
  install                  Install module(s) from git
  browse                   Browse modules in a git repository
  outdated                 Check installed modules for newer versions
  upgrade                  Upgrade installed modules to latest versions

Authoring:
  new-module               Scaffold a new module
  validate-module          Validate a module
  vars                     Inspect resolved variables
  schema-upgrade           Upgrade module.dhall files to the current schema

Configuration:
  config                   Read and write config values
  context                  Manage the active context (work, personal, etc.)

AI agent:
  agent                    AI-powered agent commands

Help & shell integration:
  help                     Show help for commands and topics
  completions              Generate shell completion scripts
```


## Progress

- [x] Refactor `commandParser` in `seihou-cli/src/Seihou/CLI/Commands.hs` to use
      grouped `hsubparser` blocks with `commandGroup` labels (2026-03-24)
- [x] Build and verify the new help output matches the expected grouping (2026-03-24)
- [x] Run `cabal test all` to confirm nothing is broken — all 56 tests pass (2026-03-24)


## Surprises & Discoveries

- Using multiple `hsubparser` blocks without `hidden` causes the usage line to show
  `(COMMAND | COMMAND | COMMAND | COMMAND | COMMAND | COMMAND)` instead of just `COMMAND`.
  Adding `hidden` to all non-first groups collapses this back to a clean `seihou COMMAND [--version]`
  usage line while still showing all groups in the help body.


## Decision Log

- Decision: Use six groups — core (unlabeled), Module management, Authoring, Configuration,
  AI agent, Help & shell integration.
  Rationale: These reflect the natural workflow: core commands for day-to-day use, module
  management for discovery/install, authoring for module creators, config for settings, agent
  for AI features, and help/completions as utilities. The core group is left unlabeled so it
  appears under the default "Available commands" heading, making the most common commands
  prominent.
  Date: 2026-03-24

- Decision: Use `hsubparser` (not `subparser`) for each group combined with `<|>`.
  Rationale: `commandGroup` only works as a `Mod CommandFields` modifier on a subparser
  block. To get multiple labeled groups, optparse-applicative requires separate `hsubparser`
  calls combined with `<|>`. The first group (without `commandGroup`) gets the default
  "Available commands" heading; subsequent groups each get their own heading.
  Date: 2026-03-24


## Outcomes & Retrospective

Implementation complete. The single `subparser` was replaced with six `hsubparser` blocks
using `commandGroup` and `hidden`. The help output now shows commands under labeled headings
matching the planned grouping exactly. Usage line remains clean. All 56 tests pass. The only
addition beyond the original plan was using `hidden` on non-first groups to fix the usage
line — a minor detail documented in Surprises & Discoveries.


## Context and Orientation

**optparse-applicative command groups**: The library provides `commandGroup :: String -> Mod
CommandFields a` which sets a group heading for commands within a subparser block. To create
multiple groups, you use multiple `hsubparser` calls (each with its own `commandGroup`)
combined with `<|>`. Commands without a `commandGroup` modifier display under "Available
commands".

**Key file**: `seihou-cli/src/Seihou/CLI/Commands.hs` — contains the `commandParser`
function (line 216) which currently uses a single `subparser` call with all 19 commands
concatenated via `<>`.

**Current command list** (19 commands): init, run, remove, vars, install, status, diff,
list, new-module, validate-module, config, context, browse, outdated, upgrade,
schema-upgrade, agent, help, completions.

**Imports already present**: `Options.Applicative` is imported (line 30), which re-exports
`commandGroup` and `hsubparser`. No new imports are needed.


## Plan of Work

### Milestone 1: Refactor commandParser into grouped hsubparser blocks

The only file to edit is `seihou-cli/src/Seihou/CLI/Commands.hs`. The change is entirely
within the `commandParser` function (lines 216–238).

Replace the single `subparser (...)` with six `hsubparser` calls combined via `<|>`:

1. **Core** (no `commandGroup`, shows as "Available commands"):
   `init`, `run`, `remove`, `status`, `diff`

2. **Module management** (`commandGroup "Module management:"`):
   `list`, `install`, `browse`, `outdated`, `upgrade`

3. **Authoring** (`commandGroup "Authoring:"`):
   `new-module`, `validate-module`, `vars`, `schema-upgrade`

4. **Configuration** (`commandGroup "Configuration:"`):
   `config`, `context`

5. **AI agent** (`commandGroup "AI agent:"`):
   `agent`

6. **Help & shell integration** (`commandGroup "Help & shell integration:"`):
   `help`, `completions`

No other functions, types, or modules need to change. The `Command` data type, all
`*Info` and `*Parser` functions, and the `Main.hs` dispatch all remain identical.

**What exists at the end**: `seihou --help` displays commands under labeled group headings
instead of a single flat list.

**Acceptance**: `seihou --help` output shows six sections. `cabal test all` passes.


## Concrete Steps

All commands run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

1. Edit `seihou-cli/src/Seihou/CLI/Commands.hs`, replacing the `commandParser` function body.

2. Build:
   ```
   cabal build seihou-cli
   ```

3. Verify help output:
   ```
   cabal run seihou -- --help
   ```
   Expected: commands appear under six group headings as shown in Purpose / Big Picture.

4. Run tests:
   ```
   cabal test all
   ```
   Expected: all tests pass.


## Validation and Acceptance

1. `cabal run seihou -- --help` shows grouped output with headings:
   - "Available commands:" containing init, run, remove, status, diff
   - "Module management:" containing list, install, browse, outdated, upgrade
   - "Authoring:" containing new-module, validate-module, vars, schema-upgrade
   - "Configuration:" containing config, context
   - "AI agent:" containing agent
   - "Help & shell integration:" containing help, completions

2. Each individual command's `--help` still works: `cabal run seihou -- run --help`

3. `cabal test all` passes with no failures.

4. Functional spot-check: `cabal run seihou -- init` still works (ensures parsing is intact).


## Idempotence and Recovery

This change is a pure refactor of the parser combinator expression. If the build fails,
revert the single function (`commandParser`) and the output returns to the flat list.
`git checkout -- seihou-cli/src/Seihou/CLI/Commands.hs` is a safe rollback.


## Interfaces and Dependencies

**Library**: `optparse-applicative` (already a dependency)

**Functions used** (all from `Options.Applicative`):
- `hsubparser :: Mod CommandFields a -> Parser a` — like `subparser` but usable with `<|>`
- `commandGroup :: String -> Mod CommandFields a` — sets the group heading
- `command :: String -> ParserInfo a -> Mod CommandFields a` — unchanged usage
- `(<|>) :: Parser a -> Parser a -> Parser a` — combines the group parsers

**No new types or signatures**. The only change is the body of:
```haskell
commandParser :: Parser Command
```
