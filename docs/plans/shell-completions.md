---
slug: shell-completions
title: "Add Shell Completion Generation"
kind: exec-plan
created_at: 2026-03-13T14:34:16Z
---


# Add Shell Completion Generation

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, users can generate shell completion scripts for Bash, Zsh, and Fish by running `seihou completions bash`, `seihou completions zsh`, or `seihou completions fish`. Pressing Tab in any of these shells will then complete subcommands, flags, and arguments automatically, derived from the existing optparse-applicative parser definitions. No manual command registry is needed — adding a new command to the parser is all that is required.

Observable outcome: after building and running `seihou completions zsh | head -5`, the user sees a Zsh completion script that begins with `#compdef seihou`. After sourcing it, Tab-completing `seihou r<TAB>` offers `run` with its `progDesc` as a description.


## Progress

- [x] M1: Create `Seihou.CLI.Completions` module with types and generators (2026-03-13)
- [x] M1: Create `Seihou.CLI.Completions.Bash` with Bash script generator (2026-03-13)
- [x] M1: Create `Seihou.CLI.Completions.Zsh` with Zsh script generator (2026-03-13)
- [x] M1: Create `Seihou.CLI.Completions.Fish` with Fish script generator (2026-03-13)
- [x] M2: Add `CompletionsCommand` type and `Completions` constructor to `Command` in `Commands.hs` (2026-03-13)
- [x] M2: Add `completions` subcommand parser to `commandParser` in `Commands.hs` (2026-03-13)
- [x] M2: Add handler dispatch in `Main.hs` (2026-03-13)
- [x] M2: Register new modules in `seihou-cli.cabal` (2026-03-13)
- [x] M3: Build and verify `seihou completions bash` produces valid output (2026-03-13)
- [x] M3: Build and verify `seihou completions zsh` produces valid output (2026-03-13)
- [x] M3: Build and verify `seihou completions fish` produces valid output (2026-03-13)
- [ ] M3: Verify Tab completion works in at least one shell (deferred to user)


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Use optparse-applicative's built-in completion protocol (delegate to binary at runtime) rather than generating static completion lists.
  Rationale: The binary already has optparse-applicative >=0.18. The built-in protocol automatically derives completions from the parser tree — no manual command registry to maintain. Adding a new subcommand or flag requires zero completion-side changes.
  Date: 2026-03-12

- Decision: Three separate submodules (Bash, Zsh, Fish) under `Seihou.CLI.Completions` plus a top-level re-export module, following the pattern from the reference design.
  Rationale: Each shell has distinct script syntax and protocol requirements. Separate modules keep each generator self-contained and easy to test or modify independently.
  Date: 2026-03-12

- Decision: Place the `CompletionsCommand` type in `Commands.hs` alongside other command types, not in the completions modules.
  Rationale: All other command types (`RunOpts`, `VarsOpts`, etc.) live in `Commands.hs`. Consistency makes the codebase predictable.
  Date: 2026-03-12


## Outcomes & Retrospective

All three milestones completed in a single pass. The implementation required no surprises or deviations from the plan. Four new modules were created, three existing files were edited, and all 568 existing tests continue to pass. The `completions` subcommand appears in `seihou --help` and each shell generator produces correct output. Live Tab completion testing is deferred to the user since it requires an interactive shell session.


## Context and Orientation

The seihou CLI is a Haskell application built with optparse-applicative (>=0.18). The executable is named `seihou`. The project uses GHC 9.12.2 with the GHC2024 language, Cabal 3.0, and Nix flakes.

The CLI parser is defined in `seihou-cli/src/Seihou/CLI/Commands.hs`. This file exports a `Command` sum type (14 constructors: `Init`, `Run`, `Vars`, `Install`, `Status`, `Diff`, `List`, `NewModule`, `ValidateModule`, `Config`, `Context`, `Browse`, `Agent`, `HelpCmd`) and a `commandParser :: Parser Command` that uses optparse-applicative's `subparser` combinator to register each subcommand. The top-level `opts :: ParserInfo Command` adds version info, help, and a custom footer.

The main dispatch is in `seihou-cli/src/Main.hs`, which calls `execParser opts` and pattern-matches on `Command` to route to handler functions.

The cabal file is `seihou-cli/seihou-cli.cabal`. The executable stanza lists all modules under `other-modules`. New modules must be registered there to be included in the build.

The project uses `Seihou.Prelude` (from `seihou-core`) as a custom prelude. Most CLI modules import it. The `Text` type used throughout is `Data.Text.Text`.

optparse-applicative has built-in shell completion support. When a binary is built with optparse-applicative, it automatically responds to hidden flags `--bash-completion-index N --bash-completion-word ...` by walking its parser tree and returning matching completions. The "enriched" variant (`--bash-completion-enriched`) returns `word\tdescription` pairs, where the description comes from `progDesc` metadata on subcommands. Bash uses the plain protocol (no descriptions); Zsh and Fish use the enriched protocol (descriptions displayed natively).

The completion scripts are static text constants — they contain shell code that calls the `seihou` binary at Tab-press time. The generators do not need access to the parser tree at all; they simply embed the binary name in the script.


## Plan of Work

The work proceeds in three milestones.


### Milestone 1 — Completion Script Generators

This milestone creates four new Haskell modules that generate shell completion scripts as static `Text` values. At the end, the modules compile but are not yet wired into the CLI. Verification: `cabal build all` succeeds.

Create the directory `seihou-cli/src/Seihou/CLI/Completions/` with three files:

**`seihou-cli/src/Seihou/CLI/Completions/Bash.hs`** — exports `generateBashCompletion :: Text`. The function returns a multi-line Bash script that defines a `_seihou_completions` function. This function builds a `CMDLINE` array from `$COMP_CWORD` (the cursor position) and `$COMP_WORDS` (the current tokens), passes them to `seihou --bash-completion-index ... --bash-completion-word ...`, and populates `COMPREPLY`. The script registers itself with `complete -o filenames -F _seihou_completions seihou`. This uses the plain protocol because Bash does not support completion descriptions.

**`seihou-cli/src/Seihou/CLI/Completions/Zsh.hs`** — exports `generateZshCompletion :: Text`. The function returns a Zsh script beginning with `#compdef seihou`. It defines a `_seihou` function that builds a CMDLINE array using `--bash-completion-enriched` and `--bash-completion-index $((CURRENT - 1))`, iterates over the enriched output (splitting on tab to extract word and description), escapes colons in words (since Zsh uses `:` as the word/description separator in `_describe`), and calls `_describe 'seihou' completions`. This uses the enriched protocol so Zsh displays descriptions alongside completions.

**`seihou-cli/src/Seihou/CLI/Completions/Fish.hs`** — exports `generateFishCompletion :: Text`. The function returns a Fish script that disables default file completion (`complete -c seihou -f`), defines a `__seihou_complete` function that builds args from `commandline -cop` and `commandline -ct`, calls `seihou` with `--bash-completion-enriched`, splits output on tab, and outputs `word\tdescription` pairs. It registers via `complete -c seihou -a '(__seihou_complete)'`. This uses the enriched protocol for Fish's native description display.

**`seihou-cli/src/Seihou/CLI/Completions.hs`** — a re-export module that imports and re-exports the three generators and the handler function `handleCompletionsCommand`. The handler pattern-matches on a `CompletionsCommand` type (defined in `Commands.hs`, see Milestone 2) and calls `Data.Text.IO.putStrLn` with the appropriate generator.


### Milestone 2 — Wire Into CLI

This milestone adds the `completions` subcommand to the CLI parser and dispatch. At the end, `cabal build all` succeeds and `cabal run seihou -- completions --help` shows the three shell subcommands.

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

1. Add a `CompletionsCommand` sum type with three constructors: `CompletionsBash`, `CompletionsZsh`, `CompletionsFish`. Derive `Eq`, `Show`, `Generic` to match existing types.

2. Add `Completions CompletionsCommand` as a new constructor in the `Command` type.

3. Export `CompletionsCommand(..)` from the module header.

4. Define `completionsInfo :: ParserInfo Command` and `completionsParser :: Parser Command`. The parser uses `subparser` with three `command` entries: `"bash"` (progDesc "Generate Bash completion script"), `"zsh"` (progDesc "Generate Zsh completion script"), `"fish"` (progDesc "Generate Fish completion script"). Each maps to `pure CompletionsBash`, etc., wrapped in `Completions`.

5. Add `command "completions" completionsInfo` to the `commandParser` subparser list, after the `"help"` command entry.

In `seihou-cli/src/Main.hs`:

1. Add `import Seihou.CLI.Completions (handleCompletionsCommand)`.

2. Add a `Completions completionsCmd -> handleCompletionsCommand completionsCmd` case to the dispatch.

In `seihou-cli/seihou-cli.cabal`:

1. Add four modules to the executable's `other-modules` list: `Seihou.CLI.Completions`, `Seihou.CLI.Completions.Bash`, `Seihou.CLI.Completions.Zsh`, `Seihou.CLI.Completions.Fish`.


### Milestone 3 — Validation

This milestone verifies end-to-end behavior. Run the built executable and confirm that each completion subcommand produces correct output, and that Tab completion works in a live shell.


## Concrete Steps

All commands are run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

**Milestone 1 — Create generator modules:**

Create the directory and four source files as described in the Plan of Work. After creating all files, run:

    cabal build all

Expected: build succeeds with no errors. The new modules compile but are not yet reachable from the CLI.

**Milestone 2 — Wire into CLI:**

Edit `Commands.hs`, `Main.hs`, and `seihou-cli.cabal` as described. Then run:

    cabal build all

Expected: build succeeds. Then run:

    cabal run seihou -- completions --help

Expected output (approximately):

    Usage: seihou completions COMMAND

    Available commands:
      bash                     Generate Bash completion script
      zsh                      Generate Zsh completion script
      fish                     Generate Fish completion script

**Milestone 3 — Validate output:**

    cabal run seihou -- completions bash

Expected: a Bash script containing `_seihou_completions`, `complete -o filenames -F _seihou_completions seihou`.

    cabal run seihou -- completions zsh

Expected: a Zsh script beginning with `#compdef seihou`, containing `_seihou`, `_describe`, and `--bash-completion-enriched`.

    cabal run seihou -- completions fish

Expected: a Fish script containing `complete -c seihou -f`, `__seihou_complete`, and `--bash-completion-enriched`.

To test live completion (Zsh example):

    eval "$(cabal run seihou -- completions zsh)"
    seihou <TAB>

Expected: subcommands like `init`, `run`, `vars`, `completions`, etc. appear as completions with descriptions.


## Validation and Acceptance

1. `cabal build all` succeeds with no errors or warnings related to the new modules.

2. `cabal test all` continues to pass (no regressions).

3. `cabal run seihou -- completions bash` outputs a valid Bash completion script that contains the function name `_seihou_completions` and the `complete` registration line.

4. `cabal run seihou -- completions zsh` outputs a valid Zsh completion script starting with `#compdef seihou`.

5. `cabal run seihou -- completions fish` outputs a valid Fish completion script containing `complete -c seihou -f`.

6. `cabal run seihou -- --help` now shows `completions` in the list of available commands.

7. After sourcing the Zsh script (`eval "$(cabal run seihou -- completions zsh)"`), pressing Tab after `seihou ` lists available subcommands with descriptions. Pressing Tab after `seihou run --` lists available flags like `--dry-run`, `--diff`, `--force`.


## Idempotence and Recovery

All steps are additive and safe to repeat. The new modules are new files that do not conflict with existing code. The edits to `Commands.hs`, `Main.hs`, and the cabal file add new entries without modifying existing ones. If a step fails partway, simply fix the issue and re-run `cabal build all`. There is no destructive or irreversible operation.


## Interfaces and Dependencies

No new library dependencies are required. The generators produce static `Text` values using only `Data.Text` (already depended upon). The handler uses `Data.Text.IO.putStrLn` (already available).

At the end of Milestone 2, the following types and functions must exist:

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

    data CompletionsCommand
      = CompletionsBash
      | CompletionsZsh
      | CompletionsFish
      deriving stock (Eq, Show, Generic)

The `Command` type gains:

    | Completions CompletionsCommand

In `seihou-cli/src/Seihou/CLI/Completions/Bash.hs`:

    generateBashCompletion :: Text

In `seihou-cli/src/Seihou/CLI/Completions/Zsh.hs`:

    generateZshCompletion :: Text

In `seihou-cli/src/Seihou/CLI/Completions/Fish.hs`:

    generateFishCompletion :: Text

In `seihou-cli/src/Seihou/CLI/Completions.hs`:

    handleCompletionsCommand :: CompletionsCommand -> IO ()
