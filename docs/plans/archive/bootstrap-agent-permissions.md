---
slug: bootstrap-agent-permissions
title: "Expand Bootstrap Agent Permissions to Reduce User Prompts"
kind: exec-plan
created_at: 2026-03-24T15:00:54Z
---


# Expand Bootstrap Agent Permissions to Reduce User Prompts

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

When a user runs `seihou agent bootstrap`, the launched Claude Code agent constantly prompts for permission to run basic commands like `mktemp`, `cp`, `rm`, `tree`, and `git commit`. This makes the bootstrap experience frustrating and disruptive. After this change, the bootstrap agent will have ample pre-approved permissions for temporary directory creation, file manipulation, git operations (including staging and committing), and common shell utilities — so it can scaffold, validate, test, and commit modules without interrupting the user for routine operations.


## Progress

- [x] Create `bootstrapAllowedTools` in `AgentLaunch.hs` with expanded permissions (2026-03-24)
- [x] Export `bootstrapAllowedTools` from `AgentLaunch` module (2026-03-24)
- [x] Update `Bootstrap.hs` to use `launchAgentWith bootstrapAllowedTools` instead of `launchAgent` (2026-03-24)
- [x] Build and verify compilation (2026-03-24)
- [x] Bootstrap prompt tool guidelines already say "Commit with git after completing each module" — now aligned with permissions (2026-03-24)


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Create a dedicated `bootstrapAllowedTools` rather than expanding `defaultAllowedTools`.
  Rationale: The `defaultAllowedTools` list is shared between `assist` and `bootstrap`. The assist agent is a template authoring helper that does not need full git access or temp-directory permissions. Giving bootstrap its own tool list follows the same pattern as `setupAllowedTools` and avoids over-permissioning the assist agent.
  Date: 2026-03-24

- Decision: Grant full `Bash(git *)` rather than enumerating specific git subcommands.
  Rationale: The bootstrap prompt explicitly instructs the agent to "Commit with git after completing each module." Enumerating every git subcommand (add, commit, branch, checkout, etc.) is fragile and incomplete. The setup agent already uses `Bash(git *)` for the same reason. The user explicitly requested git and commit capabilities.
  Date: 2026-03-24

- Decision: Include `Bash(mktemp *)`, `Bash(cp *)`, `Bash(rm *)`, `Bash(mv *)`, `Bash(touch *)`, `Bash(tree *)`, `Bash(find *)`, `Bash(wc *)`, `Bash(diff *)`, `Bash(head *)`, `Bash(tail *)`, `Bash(echo *)`, and `Bash(chmod *)` in the bootstrap tool list.
  Rationale: The bootstrap workflow involves scaffolding module directories, creating template files, copying examples, testing with dry-run (which may produce temp output), and inspecting results. These are all standard non-destructive shell operations that the agent needs during a typical bootstrap session. The user reported `mktemp` specifically as a pain point.
  Date: 2026-03-24


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The Seihou CLI includes three agent subcommands (`assist`, `bootstrap`, `setup`) that launch Claude Code with a system prompt and a set of pre-approved tool permissions. The permission lists are defined in `seihou-cli/src/Seihou/CLI/AgentLaunch.hs` and control which `Bash(...)` patterns and built-in tools the agent can use without prompting the user.

Currently, both `assist` and `bootstrap` share `defaultAllowedTools` (line 84-101 of `AgentLaunch.hs`), which allows only `seihou *`, three read-only git subcommands (`status`, `log`, `diff`), `ls`, `mkdir`, `cat`, `pwd`, plus the file tools (`Read`, `Write`, `Edit`, `Glob`, `Grep`) and worktree tools. The `setup` command has its own `setupAllowedTools` (line 105-120) with full `Bash(git *)`.

The bootstrap agent's system prompt (in `seihou-cli/data/bootstrap-prompt.md`) tells the agent to scaffold modules, validate them, run dry-runs, and commit with git — but the tool permissions don't grant git write access or many common shell utilities, causing constant permission prompts.

Key files:

- `seihou-cli/src/Seihou/CLI/AgentLaunch.hs` — Defines `defaultAllowedTools`, `setupAllowedTools`, `launchAgent`, `launchAgentWith`, and the module export list.
- `seihou-cli/src/Seihou/CLI/Bootstrap.hs` — The bootstrap command handler. Currently calls `launchAgent` (line 23), which uses `defaultAllowedTools`.


## Plan of Work

This is a single-milestone change touching two files.

In `seihou-cli/src/Seihou/CLI/AgentLaunch.hs`, add a new `bootstrapAllowedTools` list after the existing `setupAllowedTools` definition (after line 120). This list will include everything from `defaultAllowedTools` plus full git access and common shell utilities. Then add `bootstrapAllowedTools` to the module export list.

In `seihou-cli/src/Seihou/CLI/Bootstrap.hs`, change `handleBootstrap` to call `launchAgentWith bootstrapAllowedTools` instead of `launchAgent`. This requires importing `bootstrapAllowedTools` (already available via the `Seihou.CLI.AgentLaunch` import).

The new `bootstrapAllowedTools` list:

    bootstrapAllowedTools :: [String]
    bootstrapAllowedTools =
      [ "Bash(seihou *)",
        "Bash(git *)",
        "Bash(ls *)",
        "Bash(mkdir *)",
        "Bash(cat *)",
        "Bash(pwd)",
        "Bash(mktemp *)",
        "Bash(cp *)",
        "Bash(rm *)",
        "Bash(mv *)",
        "Bash(touch *)",
        "Bash(tree *)",
        "Bash(find *)",
        "Bash(wc *)",
        "Bash(diff *)",
        "Bash(head *)",
        "Bash(tail *)",
        "Bash(echo *)",
        "Bash(chmod *)",
        "Read",
        "Write",
        "Edit",
        "Glob",
        "Grep",
        "EnterWorktree",
        "ExitWorktree"
      ]


## Concrete Steps

All commands should be run from the repository root `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Step 1: Edit `seihou-cli/src/Seihou/CLI/AgentLaunch.hs` — add `bootstrapAllowedTools` to the export list and define the new tool list after `setupAllowedTools`.

Step 2: Edit `seihou-cli/src/Seihou/CLI/Bootstrap.hs` — change line 23 from `launchAgent debug systemPrompt bootstrapOpts.bootstrapPrompt` to `launchAgentWith bootstrapAllowedTools debug systemPrompt bootstrapOpts.bootstrapPrompt`.

Step 3: Build to verify:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal build seihou-cli

Expected: clean compilation, no errors.

Step 4: Verify the new list is used at runtime by running in debug mode:

    cabal run seihou -- agent bootstrap --debug

Expected: the system prompt is printed to stdout (debug mode does not launch claude). This confirms the code path works. The tool list is not printed in debug mode, but compilation success plus the code change is sufficient.


## Validation and Acceptance

After building, run:

    cabal run seihou -- agent bootstrap --debug

This should print the bootstrap system prompt without errors, confirming the code compiles and the bootstrap handler dispatches correctly.

To verify the permissions are effective, launch the actual agent:

    cabal run seihou -- agent bootstrap "a simple readme module"

The agent should be able to run `mktemp`, `git add`, `git commit`, `cp`, `tree`, and other shell utilities without prompting for permission. If any of these commands trigger a permission prompt, the tool pattern needs to be added to `bootstrapAllowedTools`.

The assist agent (`seihou agent assist`) should be unaffected — it continues to use the restricted `defaultAllowedTools`.


## Idempotence and Recovery

All edits are additive. The new `bootstrapAllowedTools` list does not modify `defaultAllowedTools` or `setupAllowedTools`. If something goes wrong, revert the two file edits and rebuild. The change is safe to apply multiple times — subsequent applications will be no-ops since the code will already contain the new list.


## Interfaces and Dependencies

No new library dependencies. The change uses only existing infrastructure in `Seihou.CLI.AgentLaunch`.

After the change, the module exports:

    module Seihou.CLI.AgentLaunch
      ( AgentContext (..),
        gatherAgentContext,
        launchAgent,
        launchAgentWith,
        defaultAllowedTools,
        setupAllowedTools,
        bootstrapAllowedTools,
        substitute,
        formatSeihouProjectState,
        formatManifestState,
        formatModuleDhallState,
        formatLocalModules,
        formatAvailableModules,
      )

In `Seihou.CLI.Bootstrap`, the signature of `handleBootstrap` is unchanged — only its implementation changes from `launchAgent` to `launchAgentWith bootstrapAllowedTools`.
