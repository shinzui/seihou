---
type: Bug Report
title: "A blueprint baseline applies its modules' files but silently skips their commands"
description: >-
  `seihou agent run` applies `baseModules` without running the modules' Apply commands, which
  `seihou run` of the same module runs, and neither the guide nor the run output says so, so a
  baseline whose commands check or complete the generated files leaves them unchecked.
bugId: BUG-4
affects: mori://shinzui/seihou
affectedVersion: 0.16.0.0
origin: mori://tan/tan-seihou-modules
severity: degraded
status: reported
generated:
  by: process:claude-code
  at: "2026-11-14T05:05:00Z"
observed: >-
  With Seihou 0.16.0.0 (`63cb35d`), a blueprint whose only baseline is a module with one Apply
  command wrote the module's seed files under `seihou agent --debug run` and under a real
  `--batch` run, but the command never ran (the file it appends to was never created). Running
  the same module with `seihou run` runs the command. The run prints no notice that commands
  were skipped.
expected: >-
  `applyBaseline` in `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` describes itself as mirroring
  the composition pipeline in `Seihou.CLI.Run.handleRun`, and `docs/user/blueprints.md` says
  baselines apply "deterministic scaffolding" and are checked "the same way `seihou run` does".
  A baseline should therefore run its modules' Apply commands as `seihou run` would, or, if
  skipping them is intended, the guide and the run output should say so explicitly.
workaround: >-
  Make the blueprint prompt instruct the agent to run the module's commands first, and
  pre-approve them in `allowedTools`. `mori://tan/tan-seihou-modules` does this in
  `blueprints/tan-staging-stack-onboarding/prompt.md`.
reproduction:
  - Create a project with `.seihou/modules/proto-stack/module.dhall` declaring one seed template step and one command `S.Command.Action.Apply "echo ran >> cmd.log"`.
  - Run `seihou run proto-stack --no-save-prompted --var ...` and observe `cmd.log` is created.
  - In a fresh project, add `.seihou/modules/proto-bp/blueprint.dhall` with `baseModules = [ S.Dependency::{ module = "proto-stack" } ]`.
  - Run `seihou agent --debug run proto-bp --var ...` and observe the seed file is created and `.seihou/manifest.json` records the baseline, but `cmd.log` does not exist.
timestamp: "2026-11-14T05:05:00Z"
---

# Bug Report: A Blueprint Baseline Silently Skips Its Modules' Commands

## What is wrong

A blueprint's `baseModules` are applied by `applyBaseline` in
`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`. It compiles the composed plan, executes the file
operations, records seeds and writes the manifest, then returns. It never runs the modules'
`commands`. `seihou run` of the same module runs them after the files are written.

Nothing tells the author or the person running the blueprint. `docs/user/blueprints.md`
describes baselines only as deterministic scaffolding that the artifact guard checks "the
same way `seihou run` does", and the run prints the seed plan and a `Baseline applied` line
with no mention of commands.

## Where it was observed

Found while implementing the `tan-staging-stack-onboarding` blueprint in
`mori://tan/tan-seihou-modules` (ExecPlan 4 there, friction entry
`mori://tan/tan-seihou-modules/okf/friction-log/concepts/FRIC-4`). Its baseline module
`tan-staging-stack` writes a service's staging files and then runs two commands: a Pulumi
version check that fails the application when the generated pin disagrees with the
repository, and a generator that refreshes an index of records. As a baseline, neither ran,
so a blueprint run would have left the version unchecked and the index stale. It was caught
only by a throwaway prototype: a module whose command appends to `cmd.log`, applied once by
`seihou run` (file created) and once as a baseline under `seihou agent --debug run` (file
absent).

## Why this is a bug, not an improvement request

A module's commands are part of what applying that module means; `seihou run` treats a
failing command as a failed application. The baseline path claims, in its own documentation
comment, to mirror that pipeline, and the user guide offers no exception. Silently dropping
part of the module's declared behaviour, with no notice, contradicts both. If skipping is the
intended design (for example, to keep side effects out of the step before the agent starts),
the defect is that it is undocumented and invisible.

## Suggested direction

Either run the composition's Apply commands after the baseline's files, with the same
failure semantics as `seihou run` (a failed command fails the baseline before the agent
starts), or keep skipping them and make it explicit: state it in `docs/user/blueprints.md`
under "Baseline modules", print a line naming each skipped command when a baseline declares
any, and have `seihou validate-blueprint --lint` warn when a base module has commands. A
regression would apply a baseline module whose command creates a file and assert the chosen
behaviour.
