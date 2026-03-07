# Add Native CLI Agent Assist Command

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, users can run `seihou assist` from any directory to launch an interactive Claude Code session purpose-built for creating and modifying Seihou modules and templates. Unlike a static prompt file, this is a native CLI command that dynamically gathers context — existing modules in the current directory, manifest state, installed modules, config values — and passes that context to Claude along with the full module schema reference. Claude starts with awareness of the user's current situation and has permissions pre-configured to run seihou commands, git, and file operations.

Observable outcome: a user runs `seihou assist` (optionally with a description like `seihou assist "create a rust project template"`) and Claude Code launches in interactive mode, greeting the user with awareness of any modules already present, and ready to help scaffold, author, validate, and test modules.


## Progress

- [x] Add `Assist` constructor and `AssistOpts` type to `seihou-cli/src/Seihou/CLI/Commands.hs` (2026-03-07)
- [x] Add `assist` subcommand parser to `commandParser` in `Commands.hs` (2026-03-07)
- [x] Create `seihou-cli/src/Seihou/CLI/Assist.hs` handler module (2026-03-07)
- [x] Implement context gathering: scan for modules in cwd, read manifest, detect seihou init state (2026-03-07)
- [x] Implement system prompt construction with dynamic context + embedded schema reference (2026-03-07)
- [x] Implement `claude` process launch with `--system-prompt`, `--allowedTools`, and optional initial prompt (2026-03-07)
- [x] Wire up `Assist` case in `Main.hs` (2026-03-07)
- [x] Register module in `seihou-cli.cabal` (2026-03-07)
- [x] Build and test: `cabal build all` — all tests pass (2026-03-07)
- [x] Restructure to `seihou agent assist` with shared `AgentOpts` and `--debug` flag (2026-03-07)
- [x] Extract shared agent infrastructure into `AgentLaunch.hs` (context gathering, claude launching, substitution) (2026-03-07)
- [x] Move system prompt to embedded Markdown template `data/assist-prompt.md` with `{{placeholder}}` substitution (2026-03-07)
- [x] Add `seihou agent bootstrap` command with `--repo` flag for multi-module repos (2026-03-07)
- [x] Create `data/bootstrap-prompt.md` with registry docs and `{{bootstrap_mode}}` placeholder (2026-03-07)
- [x] Build, test, and verify all agent subcommands with `--debug` (2026-03-07)
- [ ] Manual test: run `seihou agent assist` and verify context-aware greeting and template authoring workflow
- [ ] Manual test: run `seihou agent bootstrap` and `seihou agent bootstrap --repo`


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Implement as a native Haskell CLI subcommand (`seihou assist`) rather than a static `.claude/commands/` file.
  Rationale: A native command gathers dynamic context at invocation time — what modules exist in the current directory, manifest state, installed modules, config — and injects it into the Claude session. A static command file cannot do this. The native command also works from any directory where seihou is available, not just the seihou repo itself.
  Date: 2026-03-07

- Decision: Use `System.Process.rawSystem` to exec into `claude` with inherited stdio rather than the existing `Process` effect.
  Rationale: The `Process` effect uses `readCreateProcessWithExitCode` which captures stdout/stderr, making it unsuitable for an interactive terminal session. `rawSystem` inherits the parent's stdio handles, allowing Claude to interact directly with the user's terminal. This is a one-shot terminal handoff, not a programmatic process invocation, so the effect system is unnecessary overhead.
  Date: 2026-03-07

- Decision: Pass context via `--system-prompt` rather than `--append-system-prompt`.
  Rationale: `--system-prompt` replaces the default system prompt entirely, giving us full control over the agent's behavior. Since we embed the complete module schema and workflow instructions, we do not need Claude Code's default system prompt — our prompt is self-contained for the template authoring use case.
  Date: 2026-03-07

- Decision: Use `--allowedTools` to pre-authorize specific tool patterns so the user is not repeatedly prompted.
  Rationale: The assist session needs to run `seihou`, `git`, and file operations freely. Pre-authorizing `Bash(seihou:*,git:*,ls:*,cat:*,mkdir:*)`, `Read`, `Write`, `Edit`, `Glob`, `Grep` reduces friction. The user still controls permissions via Claude Code's own settings, but these defaults make the experience smooth.
  Date: 2026-03-07


## Outcomes & Retrospective

Milestone 1 implementation complete. The `seihou assist` command builds cleanly, all 28 CLI tests + all core tests pass. The command:
- Gathers dynamic context (cwd, .seihou/ state, manifest, local module.dhall, discovered modules)
- Builds a system prompt with embedded module schema, template syntax, CLI reference, and workflow guidance
- Launches `claude` via `rawSystem` with `--system-prompt` and `--allowedTools` for frictionless tool access
- Supports an optional positional PROMPT argument for direct task specification

Remaining: manual end-to-end testing with actual `claude` invocation.


## Context and Orientation

Seihou is a composable, type-safe project scaffolding system built in Haskell. Its CLI is defined in the `seihou-cli` package using optparse-applicative. Commands are defined as constructors of the `Command` ADT in `seihou-cli/src/Seihou/CLI/Commands.hs`, with each command dispatched to a handler module in `Main.hs`. There are currently 11 commands (init, run, vars, install, status, diff, list, new-module, validate-module, config, browse).

Each handler is a module in `seihou-cli/src/Seihou/CLI/` that exports a `handle*` function (e.g., `handleList :: IO ()`). Handlers use the effectful library for effects but the top-level handler functions are plain `IO`.

The `claude` CLI (Claude Code) is installed at `/Users/shinzui/.local/bin/claude`. Key flags for programmatic launching:

- `--system-prompt <prompt>` — set the system prompt for the session
- `--allowedTools <tools...>` — pre-authorize tool patterns (e.g., `"Bash(seihou:*) Read Write Edit"`)
- `--permission-mode <mode>` — set permission mode (default, acceptEdits, plan, etc.)
- The first positional argument is the initial prompt/message

The module.dhall schema is a Dhall record: `{ name, description, vars, exports, prompts, steps, commands, dependencies }`. Templates use `{{variable.name}}` placeholder syntax. Four generation strategies exist: copy, template, dhall-text, structured.

Context the assist command will gather dynamically:

1. Whether `.seihou/` exists in cwd (indicates a seihou-managed project)
2. Whether `.seihou/manifest.json` exists and what modules/files are tracked
3. Any `module.dhall` files in the current directory (user might be authoring a module)
4. Available modules from search paths via `discoverAllModules`
5. Whether `~/.config/seihou/` exists (seihou initialized globally)


## Plan of Work

The work proceeds in a single milestone. We add the `Assist` command variant, create its handler, and wire everything together.

In `seihou-cli/src/Seihou/CLI/Commands.hs`, we add an `Assist AssistOpts` constructor to the `Command` type. The `AssistOpts` record holds an optional initial prompt (the user's description of what they want). We add an `assist` subparser to `commandParser`.

In `seihou-cli/src/Seihou/CLI/Assist.hs`, we create the handler. The handler does three things in sequence: gather context, build the system prompt, and exec into `claude`.

Context gathering reads the current directory for module.dhall files, checks for `.seihou/manifest.json`, discovers available modules via `discoverAllModules`, and checks whether seihou has been initialized globally. Each piece of context becomes a section in the system prompt.

The system prompt is built by concatenating: a role statement, the embedded module.dhall schema reference, the dynamic context sections, workflow instructions, and tool usage guidelines. This is assembled as a `Text` value.

The handler then launches `claude` via `System.Process.rawSystem` with arguments: `--system-prompt`, the built prompt text, `--allowedTools`, the tool permissions string, and optionally the user's initial prompt as a positional argument.

In `Main.hs`, we add the `Assist` case to the dispatch. In `seihou-cli.cabal`, we add `Seihou.CLI.Assist` to `other-modules` of the executable.


### Milestone 1: Create the assist command

At the end of this milestone, `cabal build all` succeeds and `cabal run seihou -- assist` launches an interactive Claude Code session with dynamic context about the current directory and full seihou module schema knowledge.

Acceptance criteria:

- `cabal build all` compiles without errors.
- `seihou assist --help` shows the command's help text.
- `seihou assist` launches Claude Code interactively with a system prompt containing the module schema and current directory context.
- `seihou assist "create a nix module"` launches Claude Code with the initial prompt pre-filled.
- The Claude session can run `seihou new-module`, `seihou validate-module`, `seihou list`, etc.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/`.

Step 1: Edit `seihou-cli/src/Seihou/CLI/Commands.hs` to add the `Assist` command variant and parser.

Step 2: Create `seihou-cli/src/Seihou/CLI/Assist.hs` with the handler implementation.

Step 3: Edit `seihou-cli/src/Main.hs` to import the handler and add the dispatch case.

Step 4: Edit `seihou-cli/seihou-cli.cabal` to add the new module.

Step 5: Build and verify.

    cabal build all

    Expected: compiles with no errors.

Step 6: Test the help text.

    cabal run seihou -- assist --help

    Expected: shows assist command description and options.

Step 7: Test the command launches Claude.

    cabal run seihou -- assist

    Expected: Claude Code starts with a context-aware greeting.


## Validation and Acceptance

Run `cabal build all` from the repository root — it must succeed. Run `cabal run seihou -- assist --help` and verify the help text describes the command. Run `cabal run seihou -- assist` from a directory containing seihou modules and verify that Claude's greeting mentions the modules it found. Try `seihou assist "create a simple readme-only module"` and verify Claude starts working on the task immediately.

Within the Claude session, verify that running seihou commands works: the agent should be able to run `seihou new-module test-mod`, `seihou validate-module ./test-mod`, and `seihou list`.


## Idempotence and Recovery

All changes are additive — new files and new constructors. Nothing existing is modified destructively. If the build fails, fix the error and rebuild. The command itself is stateless; it gathers context fresh each time it runs.


## Interfaces and Dependencies

The command depends on the `claude` CLI being available on `PATH`. If `claude` is not found, the handler prints an error message and exits.

No new library dependencies are required. The handler uses `System.Process.rawSystem` (from the `process` package, already a dependency) and `System.Directory` (from `directory`, already a dependency).

New types and functions:

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

    data AssistOpts = AssistOpts
      { assistPrompt :: Maybe Text
      }

    -- New constructor in Command:
    | Assist AssistOpts

In `seihou-cli/src/Seihou/CLI/Assist.hs`:

    handleAssist :: AssistOpts -> IO ()

In `seihou-cli/src/Main.hs`:

    Assist assistOpts -> handleAssist assistOpts
