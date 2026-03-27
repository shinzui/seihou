# Grant full git access to all agent commands

Intention: intention_01kjjgfv60e8y9qata1sfk8qrc

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, all three seihou agent commands (`seihou agent assist`, `seihou agent bootstrap`, and `seihou agent setup`) grant the Claude Code agent full `git *` access without prompting the user for permission. Currently, the `assist` command restricts git to read-only operations (`git status`, `git log`, `git diff`), which forces the user to approve every `git add`, `git commit`, or `git push` manually. The `bootstrap` and `setup` commands already have full git access. This change makes the behavior consistent: all agent commands trust the user to have invoked them intentionally and allow the agent to perform any git operation autonomously.

To verify: run `seihou agent assist --debug` and inspect the system prompt output — the `--allowedTools` list should include `Bash(git *)` instead of the three individual read-only git patterns. Or simply run `seihou agent assist` and ask the agent to commit something — it should proceed without a permission prompt.


## Progress

- [x] Update `defaultAllowedTools` in `AgentLaunch.hs` to use `Bash(git *)` instead of individual read-only git patterns. (2026-03-27)
- [x] Verify compilation with `cabal build seihou-cli`. (2026-03-27)
- [x] Run `cabal test all` to confirm no regressions — 655 core + 89 CLI tests pass. (2026-03-27)
- [ ] Verify `seihou agent assist --debug` output shows `Bash(git *)`.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Modify only `defaultAllowedTools`, not `setupAllowedTools` or `bootstrapAllowedTools`.
  Rationale: `setupAllowedTools` and `bootstrapAllowedTools` already include `Bash(git *)`. Only `defaultAllowedTools` (used by the `assist` command via `launchAgent`) needs updating.
  Date: 2026-03-27

- Decision: Replace the three read-only git patterns with a single `Bash(git *)` wildcard rather than adding write commands individually.
  Rationale: This matches the pattern already used in `setupAllowedTools` and `bootstrapAllowedTools`. A wildcard is simpler, covers all git subcommands (including future ones), and avoids the maintenance burden of enumerating individual commands.
  Date: 2026-03-27


## Outcomes & Retrospective

Implementation complete. The single-line change to `defaultAllowedTools` in `AgentLaunch.hs` replaces three read-only git patterns with `Bash(git *)`, making all three agent commands (`assist`, `bootstrap`, `setup`) consistent in granting full git access. All 744 tests pass with no regressions.


## Context and Orientation

The file `seihou-cli/src/Seihou/CLI/AgentLaunch.hs` is the central module for launching Claude Code as a subprocess. It exports three allowed-tool lists:

- `defaultAllowedTools` (line 85): used by the `assist` command. Currently grants only `Bash(git status *)`, `Bash(git log *)`, and `Bash(git diff *)` — read-only git operations.

- `setupAllowedTools` (line 106): used by the `setup` command. Grants `Bash(git *)` — full git access.

- `bootstrapAllowedTools` (line 125): used by the `bootstrap` command. Grants `Bash(git *)` — full git access.

The `launchAgent` function (line 62) is a convenience wrapper that calls `launchAgentWith defaultAllowedTools`. The `assist` handler at `seihou-cli/src/Seihou/CLI/Assist.hs` calls `launchAgent`, so it inherits `defaultAllowedTools`. The `bootstrap` and `setup` handlers call `launchAgentWith` directly with their own tool lists.

The Claude Code `--allowedTools` flag accepts glob patterns like `Bash(git *)` which match any bash command starting with `git `. When a tool is in the allowed list, Claude Code executes it without prompting the user.


## Plan of Work

The change is a single edit to `defaultAllowedTools` in `seihou-cli/src/Seihou/CLI/AgentLaunch.hs`. Replace the three individual git patterns with the single wildcard `Bash(git *)`.

Currently (lines 87–90):

    "Bash(seihou *)",
    "Bash(git status *)",
    "Bash(git log *)",
    "Bash(git diff *)",

After the edit:

    "Bash(seihou *)",
    "Bash(git *)",

No other files need changes. No new modules, no new dependencies, no type changes.


## Concrete Steps

All commands run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Step 1: Edit `defaultAllowedTools` in `seihou-cli/src/Seihou/CLI/AgentLaunch.hs`. Replace lines 88–90 (the three read-only git entries) with a single `"Bash(git *)"` entry.

Step 2: Build to verify compilation:

    cabal build seihou-cli

Expected: Build succeeds with no errors.

Step 3: Run the test suite:

    cabal test all

Expected: All tests pass (655+ tests).

Step 4: Verify the change takes effect by running in debug mode:

    cabal run seihou -- agent assist --debug

Expected output includes `--allowedTools Bash(git *)` in the generated arguments (or the system prompt is printed without launching Claude). The three individual patterns `Bash(git status *)`, `Bash(git log *)`, `Bash(git diff *)` should no longer appear.


## Validation and Acceptance

1. `cabal build seihou-cli` succeeds.

2. `cabal test all` passes with no regressions.

3. `cabal run seihou -- agent assist --debug` shows a system prompt that, when combined with the `--allowedTools` flags, would include `Bash(git *)` and NOT the individual `Bash(git status *)`, `Bash(git log *)`, `Bash(git diff *)` patterns.

4. Running `seihou agent assist` and asking the agent to run `git add` or `git commit` proceeds without a permission prompt.


## Idempotence and Recovery

This change is fully idempotent. Editing the same list multiple times converges to the same result. If the change needs to be reverted, restore the three individual patterns. There is no migration, no state change, and no destructive operation.


## Interfaces and Dependencies

No new dependencies. No new types or functions. The only change is to the string list `defaultAllowedTools` in `seihou-cli/src/Seihou/CLI/AgentLaunch.hs`.
