# Seihou — Project CLAUDE.md

This file orients coding agents working in the seihou repository. Combine
these notes with any global guidance in your user-level `CLAUDE.md`.

## CLI Module Placement (library-first)

The `seihou-cli-internal` library lives at `seihou-cli/src/`. The
`seihou` executable target lives at `seihou-cli/src-exe/`. New code
goes in `src/` (the library) by default; `src-exe/` is reserved for
`Main.hs`, command dispatchers, and modules that genuinely need one of
these four dependencies:

- `Options.Applicative`
- `Data.FileEmbed`
- `GitHash`
- `Paths_seihou_cli`

A fifth, transitive criterion also keeps a module in the executable:
it imports another seihou module that is itself executable-only (most
commonly `Seihou.CLI.Commands`, which is trapped by
`Options.Applicative`).

Full convention, the per-module trapping inventory, and rationale:
`docs/dev/architecture/overview.md`, section "CLI Module Placement
Convention". Coordinating masterplan:
`docs/masterplans/2-cli-library-first-convention.md`.

The convention is mechanically enforced by
`nix/check-cli-module-placement.sh`, wired into both `nix flake check`
and the pre-commit hook. A new module added to `executable seihou`'s
`other-modules` without a recognised trapping import will fail the
check.

## Commit messages

Conventional Commits, per the global guidance.

## Where to put plans

ExecPlans live in `docs/plans/<N>-<slug>.md`. MasterPlans live in
`docs/masterplans/<N>-<slug>.md`. See the skills under `.claude/skills/`
for the authoring protocol.
