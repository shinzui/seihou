# Contributing to Seihou

This document is the developer-facing guide for the seihou project. The
user-facing CHANGELOG is at `docs/user/CHANGELOG.md`; the architecture
overview is at `docs/dev/architecture/overview.md`; the v1 milestones
roadmap is at `docs/dev/roadmap/v1-milestones.md`.

## CLI Module Placement Convention

Code under `seihou-cli/src/Seihou/` defaults to the `seihou-cli-internal`
library. The `seihou` executable target is reserved for the IO shell:
`Main.hs`, command dispatchers, and the small set of modules that
genuinely cannot live in the library.

A module belongs in the executable target only if it imports one of
these four Haskell-package dependencies:

- `Options.Applicative` (the optparse-applicative CLI parser).
- `Data.FileEmbed` (compile-time `embedFile` for prompt and help text).
- `GitHash` (compile-time git hash exposed by `--version`).
- `Paths_seihou_cli` (Cabal's generated module exposing the package
  version).

A fifth, transitive criterion also keeps a module in the executable: it
imports another seihou module that is itself executable-only. The most
common case today is `Seihou.CLI.Commands` (trapped by
`Options.Applicative`); every command-handler module that imports
`Commands` for its `Opts` type is transitively trapped.

Any other module — pure helpers, formatters, IO-bearing primitives that
other commands or tests might call — belongs in the library. The
library already exposes IO-bearing helpers (for example, `cloneRepo`
and `installModuleDir` in `Seihou.CLI.InstallShared`); needing IO is
not a reason to stay in the executable.

The executable target lives in `seihou-cli/src-exe/`. The library
lives in `seihou-cli/src/`. The split source directories make GHC
resolve library imports through the package binary instead of
finding the source files locally — a module added to `src/` is
automatically library-visible, and a module added to `src-exe/`
cannot be reached by the test suite.

`seihou-cli/seihou-cli.cabal`'s `executable seihou` block carries a
single header comment above its `other-modules` list pointing
readers at the architecture doc's "Trapped-modules inventory" table
(under section "CLI Module Placement Convention"). Per-line cabal
comments are not used because the project's formatter (`cabal-gild`)
sorts module entries alphabetically and floats `--` comments to the
top of the section, which would silently desynchronise per-module
annotations from the modules they describe.

To add a new executable-only module, demonstrate the trapping
dependency in the module's import list, add the file under
`seihou-cli/src-exe/Seihou/CLI/...`, list it in the executable's
`other-modules`, and add a row to the "Trapped-modules inventory"
table in the architecture doc. To add an exemption (a module that
legitimately stays in the executable despite not importing one of
the four dependencies), add it to the `EXEMPT_MODULES` list in the
enforcement script (see the path declared in
`docs/plans/21-enforce-cli-library-first-convention.md`) with an
inline comment naming the reason.

The architecture doc at `docs/dev/architecture/overview.md` is the
canonical home for this convention; this section mirrors it for
contributors landing on the contributing guide. If the two diverge,
treat the architecture doc as authoritative.

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):
`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`, optionally
with a scope (for example, `feat(parser): ...`) and a `!` or
`BREAKING CHANGE:` footer for breaking changes.

Commits made under an ExecPlan must include an `ExecPlan:` git trailer
(see `.claude/skills/exec-plan/SKILL.md`). Commits under a MasterPlan
must additionally include a `MasterPlan:` trailer (see
`.claude/skills/master-plan/SKILL.md`). When an Intention ID is in
play, also add an `Intention:` trailer.

## Plans and Master Plans

ExecPlans live in `docs/plans/<N>-<slug>.md`. MasterPlans live in
`docs/masterplans/<N>-<slug>.md`. Each ExecPlan is a self-contained,
living document — a contributor with only the plan and the working
tree must be able to implement the feature end-to-end. The full
specification is in `.claude/skills/exec-plan/PLANS.md`; the
masterplan specification is in `.claude/skills/master-plan/MASTERPLAN.md`.

## Tests

The CLI test suite lives at `seihou-cli/test/`. Run it with:

    cabal test seihou-cli-test

A new pure helper added to the library should usually carry a `Spec.hs`
file alongside the existing ones (for example,
`seihou-cli/test/Seihou/CLI/RemoteVersionSpec.hs` is a model for a
helper that exercises a single library function).
