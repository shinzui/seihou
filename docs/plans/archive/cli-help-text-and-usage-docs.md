---
slug: cli-help-text-and-usage-docs
title: "Improve CLI Help Text and Usage Documentation"
kind: exec-plan
created_at: 2026-03-02T06:20:06Z
---


# Improve CLI Help Text and Usage Documentation

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, every `seihou` subcommand supports `--help` (currently broken — only the top-level does), every help screen includes enough context for a new user to understand what the command does and how to use it, and there is a proper `README.md` at the repository root that serves as the entry point for anyone encountering the project. A user who types `seihou run --help` will see the full flag list with descriptions, examples, and workflow context instead of "Invalid option `--help`". A user who opens the repository on GitHub will see a quickstart guide, command reference, and orientation to the project.


## Progress

- [x] Milestone 1: Fix subcommand `--help` and enrich help text in `Commands.hs` (2026-03-01)
- [x] Milestone 2: Write user-facing `README.md` (2026-03-01)
- [x] Milestone 3: Validate all help screens and README accuracy (2026-03-01)


## Surprises & Discoveries

- optparse-applicative 0.19.0.0 is installed (not 0.18 as the cabal constraint lower bound suggests). The `Options.Applicative.Help.Pretty` module re-exports `prettyprinter` combinators (`vsep`, `indent`, `line`, `pretty`). The `footerDoc` and `progDescDoc` functions take `Maybe Doc`, not `Doc`.
- optparse-applicative's `footerDoc` output has double-spaced blank lines between `vsep` entries that use `line` as a separator. This is because `line` renders as a newline and `vsep` adds another between items. The visual result is acceptable — it creates clear paragraph breaks in help output.


## Decision Log

- Decision: Scope this plan to help text enrichment and a README, not CLI parser tests or error format changes.
  Rationale: Help text and README are the highest-impact improvements for a user's first experience. Parser tests and error format standardisation are separate concerns that deserve their own plan. Keeping scope tight means this plan can be completed in a single session.
  Date: 2026-03-01

- Decision: Use optparse-applicative's `headerDoc`, `footerDoc`, and `progDescDoc` with `Pretty` combinators for rich help formatting rather than plain strings.
  Rationale: Plain `progDesc` strings are limited to a single line. The `Doc`-based variants allow multi-paragraph descriptions with examples. optparse-applicative re-exports `Options.Applicative.Help.Pretty` which provides `vsep`, `indent`, `line`, and other combinators.
  Date: 2026-03-01

- Decision: Place the user-facing CLI reference directly in the root `README.md` rather than a separate `docs/cli-usage.md`.
  Rationale: The README is the de facto entry point on GitHub and in a cloned repo. A single-file reference is easier to maintain and more discoverable than a doc nested in subdirectories. The design specs in `docs/dev/` remain the authoritative internal reference.
  Date: 2026-03-01


## Outcomes & Retrospective

All three milestones completed. The plan achieved its purpose: every subcommand now responds to `--help` with exit code 0 and a rich description including workflow context and examples. The README was replaced with a proper project entry point.

Files changed: `seihou-cli/src/Seihou/CLI/Commands.hs` (enriched help text, added `<**> helper` to all 7 subcommands, added `footerDoc` to top-level and all subcommands), `README.md` (complete rewrite with quickstart, command reference, build instructions, project structure).

Validation: all 263 tests pass, `nix fmt` clean, all 8 `--help` variants exit 0 with descriptive output.


## Context and Orientation

Seihou is a composable, type-safe project scaffolding system written in Haskell. The project is structured as a Cabal multi-package workspace with two packages: `seihou-core` (the library, in `seihou-core/`) and `seihou-cli` (the executable, in `seihou-cli/`). It builds with GHC 9.12.2 and the GHC2024 language standard inside a Nix flakes dev shell.

The CLI is the primary user interface. It is built with `optparse-applicative` (version >=0.18), a Haskell library that generates `--help` screens from declarative parser definitions. The CLI currently has seven commands: `init`, `run`, `vars`, `install`, `status`, `new-module`, and `validate-module`.

The key file for this plan is `seihou-cli/src/Seihou/CLI/Commands.hs`. This module defines the `Command` ADT, all option record types (`RunOpts`, `VarsOpts`, etc.), and the optparse-applicative parsers. The top-level parser is exported as `opts :: ParserInfo Command`. The executable entry point is `seihou-cli/src/Main.hs`, which calls `execParser opts`.

The current `README.md` at the repository root contains only Nix flake template instructions unrelated to Seihou itself. It needs to be replaced entirely.

There is a comprehensive design spec at `docs/dev/design/proposed/cli-commands.md` that describes each command's arguments, output format, exit codes, and business rules. This plan draws on that spec but the README and help text must stand alone — a user should never need to read the design docs.

Current state of help text:

The top-level `seihou --help` works correctly because `opts` applies `<**> helper` to the root parser. However, none of the seven subcommand parsers include `helper`, so `seihou run --help` (and all other subcommands) prints "Invalid option `--help`" and exits with code 1. This is because each subcommand's `info` block wraps only the bare parser (e.g., `info runParser (progDesc "...")`) without `<**> helper`.

The existing help descriptions are single-line `progDesc` strings like "Run modules to generate a project". These are technically correct but too terse for a first-time user who needs to understand flags, workflow, and examples.


## Plan of Work

The work is divided into three milestones.


### Milestone 1: Fix subcommand `--help` and enrich help text

This milestone addresses the broken `--help` on subcommands and replaces terse one-line descriptions with rich, multi-paragraph help screens.

In `seihou-cli/src/Seihou/CLI/Commands.hs`, each `command` entry in `commandParser` wraps its parser in an `info` block. Currently these look like:

    command "run" (info runParser (progDesc "Run modules to generate a project"))

The fix is to add `<**> helper` to each subparser, and to use `progDescDoc` / `headerDoc` / `footerDoc` with Pretty-printer combinators to produce richer help output. The import `Options.Applicative.Help.Pretty` (or equivalently `Options.Applicative` which re-exports the Pretty module) provides `Doc`, `vsep`, `indent`, `line`, `pretty`, and `(<+>)`.

The concrete edits in `seihou-cli/src/Seihou/CLI/Commands.hs` are:

1. Add the import for Pretty combinators at the top of the module. The exact import is `import Options.Applicative.Help.Pretty` which provides `Doc`, `vsep`, `indent`, `line`, `pretty`, and the `Pretty` class.

2. In `commandParser`, change every `info` call to include `<**> helper`. For example:

       command "run" (info (runParser <**> helper) (progDesc "Run modules to generate a project"))

   Do this for all seven commands: init, run, vars, install, status, new-module, validate-module.

3. Replace plain `progDesc` strings with richer `progDescDoc` (or supplement with `footerDoc`) for each subcommand. The enriched descriptions should include:

   For `init`: Explain that it creates `~/.config/seihou/` with module directories. Mention it is idempotent.

   For `run`: Explain the workflow (load modules, resolve variables, compile plan, execute). Document the `--dry-run` and `--diff` safety modes. Note that `--module` and `--var` are repeatable.

   For `vars`: Explain the two modes — declaration listing (default) and provenance display (`--explain`). Note that `--var` provides context values.

   For `install`: Explain what happens (git clone, validate, copy to `~/.config/seihou/installed/`). Note that the module name defaults to the repo name.

   For `status`: Explain that it reads `.seihou/manifest.json` and shows applied modules, tracked files, and variables.

   For `new-module`: Explain what gets scaffolded (module.dhall, files/README.md.tpl). Note the name validation rule. Note the default output directory.

   For `validate-module`: Explain the validation checks performed. Note that the path defaults to the current directory.

4. Enrich the top-level `opts` with a `footerDoc` that shows a typical workflow:

       seihou init
       seihou run haskell-base --var project.name=my-app
       seihou status

At the end of this milestone, `seihou run --help` prints a multi-line help screen with all flags, descriptions, and workflow context. Every subcommand's `--help` works.


### Milestone 2: Write user-facing README.md

Replace the current `README.md` (which contains only Nix flake template commands) with a proper project README. The README should contain:

1. A title and one-sentence description of what Seihou is.

2. A "Quick Start" section showing the minimal workflow: init, run, status.

3. A "Commands" section with a brief reference for each of the seven commands — synopsis line, one-paragraph description, and a table of flags. This mirrors what `--help` shows but in a scannable document format.

4. A "Building from Source" section with the Nix and Cabal commands:

       nix develop
       cabal build all
       cabal run seihou -- --help

5. A "Module Authoring" section briefly explaining `new-module` and `validate-module` and pointing to the design docs for full details.

6. A "Project Structure" section listing the two packages and their roles.


### Milestone 3: Validate all help screens and README accuracy

Run every `--help` variant and verify the output is correct and complete. Verify that `nix fmt` passes (the formatter may reformat the module after edits). Verify that `cabal build all` succeeds with no warnings in `Commands.hs`.


## Concrete Steps

All commands are run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

Build and verify current state:

    cabal build all

After editing `Commands.hs`, rebuild and test help screens:

    cabal build seihou-cli
    cabal run seihou -- --help
    cabal run seihou -- run --help
    cabal run seihou -- vars --help
    cabal run seihou -- install --help
    cabal run seihou -- init --help
    cabal run seihou -- status --help
    cabal run seihou -- new-module --help
    cabal run seihou -- validate-module --help

Each command should exit 0 and print a help screen (currently only the top-level exits 0; subcommands exit 1).

Run the formatter:

    nix fmt

Run the full test suite to verify no regressions:

    cabal test all

Expected: 263 tests passing (same as before — this plan does not add or change tests).


## Validation and Acceptance

After implementation, the following must hold:

1. `cabal run seihou -- --help` prints the top-level help screen with a workflow example in the footer. Exit code 0.

2. `cabal run seihou -- run --help` prints a rich help screen describing the run command, its flags, and their purposes. Exit code 0. (Currently this exits 1 with "Invalid option".)

3. Every other subcommand (`vars`, `install`, `init`, `status`, `new-module`, `validate-module`) responds to `--help` with exit code 0 and a descriptive help screen.

4. `README.md` at the repository root contains a quickstart guide, command reference, build instructions, and project structure overview. The previous Nix template content is removed.

5. `cabal test all` passes with 263 tests.

6. `nix fmt` produces no changes (code is formatted).


## Idempotence and Recovery

All edits in this plan are to two files: `seihou-cli/src/Seihou/CLI/Commands.hs` and `README.md`. Both can be reverted with `git checkout -- <file>` if something goes wrong. No database, manifest, or configuration state is affected. The changes are purely additive to help text and documentation — no runtime behavior changes.


## Interfaces and Dependencies

This plan uses only `optparse-applicative` (already a dependency of `seihou-cli`). The Pretty-printer module `Options.Applicative.Help.Pretty` is part of optparse-applicative and does not require adding any new dependency.

No new Haskell modules are created. No new types or functions are exported. The only interface change is that the existing parsers gain `<**> helper` and richer `InfoMod` metadata.

The README is plain Markdown with no tooling dependencies.
