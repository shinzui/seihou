---
id: 40
slug: support-codex-kit-skills-and-agents
title: "Support Codex kit skills and agents"
kind: exec-plan
created_at: 2026-05-24T19:46:56Z
intention: "intention_01ksbgksmgeaesf6sft8prdvyn"
master_plan: "docs/masterplans/4-baikai-backed-configurable-agent-assistance.md"
---

# Support Codex kit skills and agents

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

Users who install a Seihou kit skill or agent should have that content available in both supported interactive agent providers. Today `seihou kit install NAME` copies skills and agents only into Claude Code's `.claude/...` layout under the Seihou user or project agent directory. When `seihou agent --provider codex-cli assist` starts Codex, Seihou passes the same agent directory with `--add-dir`, but there is no Codex-native kit content in that directory for Codex to load.

After this change, installing, updating, uninstalling, and inspecting kit content handles both agent layouts. A project-scope kit skill appears under `.seihou/agents/.claude/skills/<name>/` for Claude Code and `.agents/skills/<name>/` for Codex. A project-scope kit agent appears under `.seihou/agents/.claude/agents/<name>.md` for Claude Code and `.codex/agents/<name>.toml` for Codex. User-scope Codex copies use `$HOME/.agents/skills/<name>/` and `$HOME/.codex/agents/<name>.toml`. The observable result is that `seihou kit install seihou-module-readme --project` creates both provider skill copies, `seihou kit status` reports `claude,codex` provider coverage, and `seihou agent --provider codex-cli --debug assist "..."` still resolves the Codex launch path without routing through Baikai.


## Progress

- [x] Confirm Codex skill and agent discovery paths from local Codex state and official docs before editing code. (2026-05-24T21:10:00Z)
- [x] Extract provider layout path helpers for Claude and Codex kit installations. (2026-05-24T21:28:00Z)
- [x] Update `install`, `update`, `uninstall`, `status`, and installed detection to handle both provider layouts idempotently. (2026-05-24T21:30:00Z)
- [x] Add focused tests or smoke fixtures that prove kit install/status/uninstall covers Codex as well as Claude. (2026-05-24T21:33:00Z)
- [x] Update user help, CLI docs, and architecture notes so kit is no longer described as Claude-only. (2026-05-24T21:35:00Z)
- [x] Run build, tests, and manual smoke checks for `seihou kit` and Codex agent launch behavior. (2026-05-24T21:38:00Z)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Seihou already passes user and project agent directories to Codex interactive sessions. Evidence: `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs` calls `agentDirsForSession` and adds each returned path to Codex with `--add-dir`; `seihou-cli/src/Seihou/CLI/AgentLaunch.hs` returns `~/.config/seihou/agents` and `.seihou/agents` when those directories exist. The gap is not mounting; it is that kit installation writes only `.claude/...` content below those directories.

- The local Codex home on this machine contains `/Users/shinzui/.codex/skills/canonicalise-mori-refs/SKILL.md` and no local `agents` directory, so the implementation could not assume agent support from local state alone. The current Codex agent/subagent path was confirmed from official Codex docs before implementing Codex agent copying.

- Official Codex documentation confirms that repository skills live in `.agents/skills` and user skills live in `$HOME/.agents/skills`, not `.codex/skills`. The same documentation confirms custom agents live in `.codex/agents/` for project scope and `~/.codex/agents/` for personal scope as standalone TOML files. Evidence: <https://developers.openai.com/codex/skills> says Codex scans `.agents/skills` from the working directory up to the repo root and `$HOME/.agents/skills`; <https://developers.openai.com/codex/subagents> says custom agents are TOML files under `~/.codex/agents/` or `.codex/agents/`.

- The first attempt to run `cabal build seihou` and `cabal test seihou-cli-test` in parallel collided in Cabal's shared `dist-newstyle` package database. Evidence: the test command failed with `ghc-pkg-9.12.2: cannot create: ... package.conf.inplace already exists`. Rerunning build and tests sequentially succeeded.


## Decision Log

Record every decision made while working on the plan.

- Decision: Keep this as a follow-up child of `docs/masterplans/4-baikai-backed-configurable-agent-assistance.md` rather than reopening the completed migration plans.
  Rationale: The completed MasterPlan already established `codex-cli` as an interactive provider. This work extends the kit lifecycle so installed content loads in that provider; it does not change Baikai API provider behavior.
  Date: 2026-05-24

- Decision: Preserve Claude Code installation behavior while adding Codex copies.
  Rationale: Existing users of `seihou kit` expect `.claude/skills` and `.claude/agents` to keep working. Writing both provider layouts is simple, idempotent, and avoids requiring users to pick a provider at install time.
  Date: 2026-05-24

- Decision: Verify Codex agent layout before implementing agent support.
  Rationale: Local evidence confirms Codex skills under `.codex/skills`, but does not confirm an agent/subagent directory. Guessing would risk copying kit agents into a path Codex never reads.
  Date: 2026-05-24

- Decision: Install Codex kit content into Codex's documented discovery roots rather than below Seihou's Claude agent base directory.
  Rationale: The plan initially suggested `.codex/skills` below the Seihou target base, but the current official docs identify `.agents/skills` and `.codex/agents` as the discoverable project paths, with `$HOME/.agents/skills` and `~/.codex/agents` for user scope. Matching the documented paths makes installed content discoverable without relying on unverified `--add-dir` scanning behavior.
  Date: 2026-05-24

- Decision: Convert kit agent Markdown into Codex custom-agent TOML files for Codex.
  Rationale: Claude Code consumes Markdown agent files, while Codex custom agents require standalone TOML with `name`, `description`, and `developer_instructions`. Wrapping the Markdown body as `developer_instructions` preserves the kit instructions while producing a valid Codex agent file.
  Date: 2026-05-24


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

Implemented provider-aware kit installation for Claude Code and Codex. `Seihou.CLI.KitPaths` centralizes Seihou's install-scope policy and scan behavior while delegating provider-native asset paths and Codex custom-agent TOML rendering to `Baikai.AgentAssets`. `seihou kit install` writes skills to Claude's `.claude/skills` layout and Codex's documented `.agents/skills` layout; kit agents are copied as Claude Markdown and converted into Codex custom-agent TOML. `seihou kit status` now reports provider coverage with a `PROVIDERS` column, `kit update` repairs missing provider copies when either provider layout is present, and `kit uninstall` removes all provider copies for the selected item and scope.

Validation passed with `nix fmt`, `cabal build seihou`, `cabal test seihou-cli-test`, a project-scope smoke install/status/uninstall for `seihou-module-readme`, and `seihou agent --provider codex-cli --debug assist "confirm kit content is mounted"`. One residual limitation is that the current cached kit manifest has no agent entries, so agent conversion is covered by focused helper tests rather than a live kit-agent smoke install.


## Context and Orientation

Seihou is a Haskell CLI with a core package in `seihou-core/` and executable/library code in `seihou-cli/`. The relevant command is `seihou kit`, implemented in `seihou-cli/src-exe/Seihou/CLI/Kit.hs`. A kit is a separate Git repository, currently `https://github.com/shinzui/seihou-kit.git`, cached at `~/.cache/seihou/kit/`. Its `kit.json` manifest lists `skills` and `agents`. A skill is a directory whose important entry point is `SKILL.md`; an agent is a markdown file that an interactive coding assistant can load as a specialized assistant profile.

The current `Kit.hs` manifest types are `KitManifest`, `SkillEntry`, and `AgentEntry`. `runKit` dispatches to `listAvailable`, `installItem`, `updateKit`, `uninstallItem`, and `kitStatus`. `Seihou.CLI.KitPaths` defines Seihou's provider install bases in one place and uses `Baikai.AgentAssets` for the provider-native relative layouts. Claude Code targets still live below Seihou's agent base: user scope maps to `~/.config/seihou/agents/.claude/...` and project scope maps to `.seihou/agents/.claude/...`. Codex targets use Codex-native discovery roots: user scope maps to `$HOME/.agents/skills` and `$HOME/.codex/agents`, while project scope maps to `.agents/skills` and `.codex/agents`.

The interactive agent launch path already supports both Claude and Codex providers. `seihou-cli/src/Seihou/CLI/AgentLaunch.hs` defines `agentDirsForSession`, which returns the user and project Seihou agent directories if they exist. `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs` launches Claude Code with `--add-dir <dir>` and launches Codex with `--add-dir <dir>`, so either CLI can inspect provider-specific content below the mounted directory. `seihou-cli/src-exe/Main.hs` resolves `seihou agent --provider codex-cli ...` into `AgentProviderCodexCli` and calls the interactive launcher for `assist`, `bootstrap`, `setup`, and `run`.

The completed MasterPlan `docs/masterplans/4-baikai-backed-configurable-agent-assistance.md` records the important provider split: `claude-cli` and `codex-cli` are interactive local CLI sessions, while `anthropic` and `openai` are API providers through Baikai. This plan only affects the interactive local CLI sessions because API providers do not load local skills or agents.

Documentation that must be updated includes `docs/cli/kit.md`, `seihou-cli/help/kit.md`, and the trapped-module table and agent architecture paragraphs in `docs/dev/architecture/overview.md`. The old kit plan `docs/plans/3-add-agent-kit-command.md` is historical context and should not be edited unless the implementation discovers that its retrospective needs a correction note.

Tests currently cover `Seihou.CLI.AgentLaunch` formatters in `seihou-cli/test/Seihou/CLI/AgentLaunchSpec.hs`; there is no dedicated `KitSpec` yet. `Seihou.CLI.Kit` lives in the executable target because it imports `Options.Applicative`, so direct unit tests may require extracting filesystem helper functions into a library module, or testing via `cabal run seihou -- kit ...` against temporary `HOME` and project directories. Choose the smallest test shape that proves the new behavior without destabilizing command parsing.


## Plan of Work

Milestone 1 confirms the target layouts and protects existing behavior. Read the current Codex docs or CLI source for skills and agents, and inspect the local Codex home under `/Users/shinzui/.codex` only as corroborating evidence. Do not search `/` or `/nix/store`. Record the confirmed Codex paths in this plan's Surprises & Discoveries before code edits. This milestone confirmed `.agents/skills/<name>/` for project skills, `$HOME/.agents/skills/<name>/` for user skills, `.codex/agents/<name>.toml` for project custom agents, and `$HOME/.codex/agents/<name>.toml` for user custom agents.

Milestone 2 makes `Kit.hs` layout-aware. `seihou-cli/src/Seihou/CLI/KitPaths.hs` defines `KitProviderLayout = ClaudeLayout | CodexLayout` and helper functions that compute skill and agent destinations from a provider base and item name. `doInstall` copies every declared skill file into both the Claude and Codex skill directories. Agent installation writes the Claude Markdown file and writes a Codex custom-agent TOML file whose `developer_instructions` contains the kit agent Markdown.

Milestone 3 makes lifecycle operations symmetrical. Update `isInstalled` so `kit update` finds an item if either provider layout is installed, not only `.claude`. Update `uninstallItem` so it removes all installed provider copies for the named skill or agent and prints a message that does not falsely imply only one provider was affected. Update `scanInstalled` and `kitStatus` so status can show provider coverage. Prefer adding a `PROVIDERS` column with values such as `claude,codex`, because a single row per item remains easy to scan. If this would make the output too broad, print one row per provider with columns `NAME`, `TYPE`, `PROVIDER`, and `SCOPE`.

Milestone 4 adds validation. The implementation extracts pure and filesystem-only helpers into `seihou-cli/src/Seihou/CLI/KitPaths.hs`, adds it to the internal library, and tests it from `seihou-cli/test/Seihou/CLI/KitPathsSpec.hs`. Tests prove the Claude and Codex path helpers, Codex custom-agent TOML wrapping, and provider-specific installed scans. Manual smoke tests prove install/status/uninstall behavior for the current cached skill manifest.

Milestone 5 updates documentation and performs end-to-end smoke checks. Revise `docs/cli/kit.md` and `seihou-cli/help/kit.md` to say "Claude Code and Codex" rather than "Claude Code" only. Document both user and project scope layouts. Update `docs/dev/architecture/overview.md` so the agent command path and trapped-module table do not imply kit is Claude-only. Then build and test the repository, install a cached kit skill into a temporary project scope, and verify that a Codex debug launch reaches the interactive Codex launcher path.


## Concrete Steps

Run all commands from the repository root:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
```

Start by confirming the current code paths and Codex layout assumptions:

```bash
sed -n '1,540p' seihou-cli/src-exe/Seihou/CLI/Kit.hs
sed -n '1,120p' seihou-cli/src/Seihou/CLI/AgentLaunch.hs
sed -n '1,140p' seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs
find /Users/shinzui/.codex -maxdepth 3 -type d -name skills -o -name agents -o -name '.codex'
find /Users/shinzui/.codex/skills -maxdepth 2 -type f -name SKILL.md
```

Expected local evidence includes a Codex skills directory:

```text
/Users/shinzui/.codex/skills
/Users/shinzui/.codex/skills/canonicalise-mori-refs/SKILL.md
```

Use `mori` before relying on dependency APIs. The current project has `mori.dhall`, so inspect it and the schema dependency when needed:

```bash
mori show --full
mori registry show shinzui/seihou-schema --full
mori registry docs shinzui/seihou-schema
```

After implementing the code changes, format if the repository normally requires it, then build and run tests:

```bash
cabal build seihou
cabal test seihou-cli-test
```

Create a manual smoke directory and install a kit skill in project scope. Use an existing cached kit item such as `seihou-module-readme` if the cache exists; otherwise run `seihou kit list` first to fetch the kit repository:

```bash
tmpdir="$(mktemp -d)"
cd "$tmpdir"
/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/dist-newstyle/build/*/*/seihou-cli-*/x/seihou/build/seihou/seihou kit install seihou-module-readme --project
find .seihou .agents .codex -maxdepth 5 -type f | sort
```

The exact executable path may differ by Cabal build directory. If glob expansion is inconvenient, use `cabal run seihou --` from the repository root for command-level smoke checks. The installed files should include both provider layouts:

```text
.seihou/agents/.claude/skills/seihou-module-readme/SKILL.md
.agents/skills/seihou-module-readme/SKILL.md
```

From the temporary project, confirm status and uninstall:

```bash
/path/to/seihou kit status
/path/to/seihou kit uninstall seihou-module-readme --project
find .seihou .agents .codex -maxdepth 5 -type f | sort
```

Finally, from a real project or the temporary project after reinstalling, verify the Codex launch path reaches the interactive launcher in debug mode:

```bash
seihou agent --provider codex-cli --debug assist "confirm kit content is mounted"
```

Debug mode prints the generated system prompt and exits successfully. For a non-debug smoke check in a non-TTY environment, the command may fail with `stdin is not a terminal`; that still proves Seihou started Codex rather than routing to Baikai. Do not require an authenticated interactive Codex session for automated tests.


## Validation and Acceptance

Acceptance requires all of the following behavior:

- `seihou kit install <skill> --project` creates the existing Claude Code skill copy and a Codex skill copy at `.agents/skills/<name>/`.
- `seihou kit install <agent> --project` creates the existing Claude Code agent copy and a Codex custom-agent TOML file at `.codex/agents/<name>.toml`.
- `seihou kit status` reports installed items across user and project scopes and makes provider coverage visible.
- `seihou kit update` repairs a partial installation. If a user has only `.claude/skills/<name>/`, update should restore the matching Codex `.agents/skills/<name>/` copy for the same kit item.
- `seihou kit uninstall <name>` removes all installed provider copies for that item in the selected scope.
- `seihou agent --provider claude-cli ...` continues to receive the Seihou agent directories via `--add-dir`, preserving existing Claude behavior.
- `seihou agent --provider codex-cli ...` continues to start the Codex interactive launcher, and project-scope kit content is now in Codex-native discovery paths below the working tree.

Run these validation commands from the repository root:

```bash
cabal build seihou
cabal test seihou-cli-test
cabal run seihou -- kit status
cabal run seihou -- agent --provider codex-cli --debug assist "confirm kit content is mounted"
```

Expected results are a successful build, a passing CLI test suite, kit status output with provider-aware installed rows when items exist, and a debug agent prompt printed without attempting a Baikai API completion.


## Idempotence and Recovery

The implementation should be additive and idempotent. Copying kit files into both provider layouts can be repeated safely because existing `copyFile` behavior overwrites the destination with the current cached kit file. Creating directories with `createDirectoryIfMissing True` is safe to repeat. `kit update` should deliberately use the same install path as `kit install` so rerunning update repairs missing provider copies.

Be careful with uninstall. It should remove only the selected kit item's provider directories or files, not the entire `.claude`, `.agents`, `.codex`, or Seihou agent base directory. If testing in user scope, use a temporary `HOME` where possible. If a manual smoke test writes into the real user scope by mistake, recover by running `seihou kit uninstall <name>` for the installed item and checking that unrelated kit items remain.

The Codex agent layout has been confirmed as standalone TOML files under `.codex/agents` for project scope and `~/.codex/agents` for user scope. Kit agent Markdown is wrapped into those TOML files as `developer_instructions`, so rerunning install or update overwrites the generated TOML with the current kit contents.


## Interfaces and Dependencies

This plan should not add new package dependencies. `seihou-cli/src-exe/Seihou/CLI/Kit.hs` already uses `directory`, `filepath`, `process`, `aeson`, and `text`, which are enough for layout-aware filesystem copying and status scanning.

At the end of the implementation, `seihou-cli/src/Seihou/CLI/KitPaths.hs` exposes internally coherent helpers equivalent to these shapes:

```haskell
data KitProviderLayout = ClaudeLayout | CodexLayout

skillTargetDir :: KitProviderLayout -> FilePath -> Text -> FilePath
agentTargetFile :: KitProviderLayout -> FilePath -> Text -> FilePath
installedProviders :: Text -> KitScope -> IO [(Text, Text)]
```

The exact names may differ, but the code should have one place that defines provider-specific paths for skills and agents. `doInstall`, `uninstallItem`, `scanInstalled`, and `isInstalled` should call those helpers rather than duplicating `.claude`, `.agents`, and `.codex` literals.

The launch interface in `seihou-cli/src/Seihou/CLI/AgentLaunch.hs` should remain `agentDirsForSession :: IO [FilePath]`. `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs` should continue passing Seihou agent directories to both Claude and Codex. Codex skills and custom agents are installed into Codex's native working-tree and home-directory discovery paths rather than relying on `--add-dir` scanning.
