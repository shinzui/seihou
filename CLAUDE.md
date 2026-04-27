# Seihou — Project CLAUDE.md

This file orients coding agents working in the seihou repository. Combine
these notes with any global guidance in your user-level `CLAUDE.md`.

## CLI Module Placement (library-first)

New code under `seihou-cli/src/Seihou/` goes in the `seihou-cli-internal`
library by default. The `seihou` executable target is reserved for
`Main.hs`, command dispatchers, and modules that genuinely need one of
these four dependencies:

- `Options.Applicative`
- `Data.FileEmbed`
- `GitHash`
- `Paths_seihou_cli`

A fifth, transitive criterion also keeps a module in the executable: it
imports another seihou module that is itself executable-only (most
commonly `Seihou.CLI.Commands`, which is trapped by `Options.Applicative`).

Full convention and rationale: `docs/dev/architecture/overview.md`,
section "CLI Module Placement Convention". Coordinating masterplan:
`docs/masterplans/2-cli-library-first-convention.md`.

## Commit messages

Conventional Commits, per the global guidance.

## Where to put plans

ExecPlans live in `docs/plans/<N>-<slug>.md`. MasterPlans live in
`docs/masterplans/<N>-<slug>.md`. See the skills under `.claude/skills/`
for the authoring protocol.
