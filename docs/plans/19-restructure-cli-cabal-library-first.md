---
id: 19
slug: restructure-cli-cabal-library-first
title: "Restructure seihou-cli.cabal so the Library is the Default Home"
kind: exec-plan
created_at: 2026-04-27T01:00:01Z
intention: "intention_01kq63sz0ced98e23qvad7zpnp"
master_plan: "docs/masterplans/2-cli-library-first-convention.md"
---


# Restructure `seihou-cli.cabal` so the Library is the Default Home

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this plan, `seihou-cli/seihou-cli.cabal` expresses the library-first convention
mechanically: the `executable seihou` target `build-depends: seihou-cli-internal` and
its `other-modules` list contains only modules that genuinely cannot live in the
library. Each remaining executable-only module carries a one-line cabal comment
naming the dependency that traps it (one of `Options.Applicative`, `Data.FileEmbed`,
`GitHash`, `Paths_seihou_cli`, or — transitively — another executable-only seihou
module).

Why this matters: today `executable seihou` lists ~30 modules in its `other-modules`,
many of which are also exposed by the `library seihou-cli-internal` target. Both
targets share `hs-source-dirs: src`, so each duplicated module is compiled twice and
the executable can freely reach into anything under `src/`, regardless of whether
it's library-exposed. The compile-time signal that distinguishes "library-exposed"
from "executable-only" does not exist. After this plan, that signal exists: the
executable explicitly imports the library, the duplicates are gone, and adding a new
library-exposed module is the path of least resistance.

Observable outcome: after this plan ships, the following commands all succeed and
demonstrate the new shape:

    cabal build all
    cabal test all

    # Confirm the executable imports the library:
    rg -n "build-depends" seihou-cli/seihou-cli.cabal | rg -A 0 "seihou-cli-internal"

    # Confirm the executable's other-modules list is short and annotated:
    rg -A 30 "^executable seihou" seihou-cli/seihou-cli.cabal | rg "other-modules" -A 25

The last command should show that every entry under the executable's `other-modules`
is followed by a comment naming why it stays in the executable, and the entries are
strictly the agent-prompt wrappers, the optparse parser hub, the help/kit modules,
the version module, the four completion modules, and the handler modules that are
transitively trapped by `Seihou.CLI.Commands` until a future plan extracts the Opts
types.


## Progress

- [x] Confirm the current cabal layout matches the assumptions in this plan (executable does not depend on the library; ~30 entries in `other-modules`; many duplicate the library's `exposed-modules`). (2026-04-26)
- [x] Capture a one-paragraph note for the Surprises & Discoveries section recording the duplicate-compilation fingerprint (a `cabal build all -v` snippet showing each duplicated module compiling twice is sufficient evidence; not a regression test). (2026-04-26)
- [x] Add `seihou-cli-internal` to `executable seihou`'s `build-depends` in `seihou-cli/seihou-cli.cabal`. (2026-04-26)
- [x] Remove from `executable seihou`'s `other-modules` every module that already appears in `library seihou-cli-internal`'s `exposed-modules`. Verify `cabal build all` still succeeds and tests still pass. (2026-04-26)
- [x] Move `Seihou.CLI.SchemaVersion` from the executable's `other-modules` to the library's `exposed-modules`. Verify `cabal build all` and `cabal test all` succeed. (2026-04-26)
- [x] Promote `Seihou.CLI.Shared` and `Seihou.CLI.Style` to the library's `exposed-modules` (mid-implementation discovery; required by the source-dir split below). (2026-04-26)
- [x] Split `hs-source-dirs` so the executable lives in `src-exe/` while the library keeps `src/`. Move Main.hs and the 27 executable-only modules. (2026-04-26)
- [x] Annotate every remaining entry in `executable seihou`'s `other-modules` with a one-line cabal comment naming the trapping dependency. Use the four-import detection plus the transitive "imports another executable-only seihou module" rule. (2026-04-26)
- [x] Update `docs/user/CHANGELOG.md` with the cabal-restructure entry. (2026-04-26)


## Surprises & Discoveries

- **Baseline duplicate-compilation fingerprint (Milestone 1).** Before
  any cabal edit, `cabal build all -v 2>&1 | rg "Compiling
  Seihou.CLI.Migrate"` returned two lines: one for the library target
  (`l/seihou-cli-internal/...`) and one for the executable target
  (`x/seihou/...`). The executable build reported `[N of 52]` for each
  module, confirming GHC was compiling 52 files for the executable
  including all the library-exposed modules.

- **`other-modules` does not control GHC's import resolution when both
  targets share `hs-source-dirs: src`.** The original plan assumed
  removing duplicate entries from the executable's `other-modules`
  would stop the executable from compiling them. Empirically that is
  false: GHC follows imports from `Main.hs`, finds the library
  modules' source files in `src/` (because `hs-source-dirs: src` is on
  the executable too), and compiles them locally — preferring the
  local source over the package import declared by `build-depends:
  seihou-cli-internal`. After Milestone 2 (deduplicating
  `other-modules`), the executable still compiled 52 modules and
  Migrate still compiled twice. This is structural: the only fix that
  actually eliminates the duplicate compilation and lets `build-depends`
  do its job is to give the executable its own `hs-source-dirs`. The
  decision to split source dirs is recorded in the Decision Log.

- **Library-private modules (`Shared`, `Style`) had to be promoted to
  `exposed-modules`.** Once the executable depends on the library and
  cannot reach into `src/` directly, every executable-only module that
  imports `Seihou.CLI.Shared` or `Seihou.CLI.Style` (Outdated, Remove,
  Browse, Status, Run, Validate, Config, Install, NewRecipe, NewModule,
  Vars, SchemaUpgrade — twelve handlers) needs those modules visible
  through the library. They were already library code in every other
  sense; the `other-modules` placement was an oversight from before
  the executable depended on the library.

- **Post-restructure baseline.** After Milestones 1-3 plus the
  source-dir split: the library compiles 24 modules (up from 21 with
  the addition of `SchemaVersion`, `Shared`, `Style`); the executable
  compiles exactly 28 modules (down from 52); `cabal build -v | rg
  "Compiling Seihou.CLI.Migrate"` returns one line. The CLI test suite
  remains green at 143 tests.

- **Per-line cabal annotations don't survive `cabal-gild`.** The
  project's formatter (configured in `treefmt.nix`) sorts
  `other-modules` entries alphabetically and floats every `--`
  comment to the top of the section. The originally-planned
  per-module annotation format (`Seihou.CLI.Foo  -- needs X`) was
  silently desynchronised on the first pre-commit format run.
  Resolution: the cabal file carries one header comment pointing
  readers at a "Trapped-modules inventory" table in
  `docs/dev/architecture/overview.md`; the table is the canonical
  per-module mapping. EP-1's documentation, EP-2's cabal file, and
  the project-root `CLAUDE.md` plus `docs/dev/contributing.md` were
  updated to describe this format. EP-4's enforcement script will
  inspect imports directly and does not rely on the cabal-comment
  format, so the loss is purely a doc-format deviation.


## Decision Log

- Decision: Do not extract Opts types out of `Seihou.CLI.Commands` as part of this
  plan.
  Rationale: Eighteen handler modules (verified by `grep -l "import
  Seihou.CLI.Commands"`) import their `Opts` type from `Commands.hs`. Extracting
  Opts into a library-eligible module would unlock those handlers to move to the
  library, but it is its own substantial refactor (the file is 1282 lines and
  intermixes types with parsers). The masterplan
  (`docs/masterplans/2-cli-library-first-convention.md`) explicitly defers this to a
  future plan and is honest that the executable's `other-modules` will remain in the
  twenty-plus range. The transitive-import rule documented in EP-1 covers these
  handlers cleanly.
  Date: 2026-04-26.

- Decision: Treat "imports another executable-only seihou module" as a fifth (and
  transitive) trapping criterion alongside the four explicit Haskell-package
  dependencies.
  Rationale: `Seihou.CLI.Commands` is trapped by `Options.Applicative`. Every
  handler that imports `Commands` for its Opts type is therefore transitively
  trapped: it cannot live in the library without dragging `Commands` along, which
  would drag `Options.Applicative` along, which would pollute the library's
  dependency footprint. Stating the rule transitively is more honest than
  enumerating every transitively-trapped module; the EP-4 enforcement script
  computes the closure rather than maintaining a static list.
  Date: 2026-04-26.

- Decision: Split `hs-source-dirs` between the library (`src/`) and the
  executable (`src-exe/`), moving Main.hs and the 27 executable-only
  modules into `src-exe/`.
  Rationale: The original plan assumed that `other-modules` controlled
  what GHC compiled, so removing duplicates from the executable's
  `other-modules` would eliminate duplicate compilation. Empirically,
  GHC walks imports through `hs-source-dirs: src` and compiles every
  reachable source file locally regardless of `other-modules`,
  preferring the local source over the package binary that
  `build-depends` would otherwise provide. The result was that even
  after deduplicating `other-modules`, the executable still recompiled
  52 modules including all the library code. Splitting source dirs is
  the only fix that actually elicits `build-depends` resolution: the
  executable cannot find `Seihou.CLI.Migrate` in `src-exe/`, so it
  loads the library binary instead. This change is invisible to users
  (modules keep their Haskell module names) and to test code (tests
  always went through the library). It also makes the convention
  enforceable at the GHC level — a new helper added to `src/` is
  automatically library-visible, and a new helper added to `src-exe/`
  cannot be reached by the test suite.
  Date: 2026-04-26.

- Decision: Promote `Seihou.CLI.Shared` and `Seihou.CLI.Style` from
  the library's `other-modules` to its `exposed-modules`.
  Rationale: Once the executable lives in `src-exe/` and depends on
  the library, executable-only handlers (Outdated, Remove, Browse,
  Status, Run, Validate, Config, Install, NewRecipe, NewModule, Vars,
  SchemaUpgrade) need to import `Shared` and `Style` through the
  library. Library-private placement only worked while both targets
  shared `hs-source-dirs: src`. Promoting them is consistent with
  their actual role — they are shared CLI utilities used both inside
  and outside the library — and aligns with the library-first
  convention.
  Date: 2026-04-26.


## Outcomes & Retrospective

The cabal restructure landed and the build is structurally healthier
than the plan promised. The executable now compiles exactly 28
modules (its IO-shell layer) and the library compiles 24; previously
both targets compiled overlapping subsets totaling 23 + 52. `cabal
build -v 2>&1 | rg "Compiling Seihou.CLI.Migrate"` returns one line
where it returned two before. The 143-test CLI suite still passes,
and `seihou --version` / `seihou --help` exercise the path through
`Data.FileEmbed` (Help.hs) and `GitHash` + `Paths_seihou_cli`
(Version.hs) without issue.

The biggest deviation from the plan was the source-dir split. The
original plan correctly identified `build-depends:
seihou-cli-internal` and the deduplicated `other-modules` as the two
necessary cabal edits, but it assumed those alone would eliminate
duplicate compilation. They did not, because `hs-source-dirs: src`
in the executable lets GHC find every library source file directly
and prefer local compilation over package resolution. The fix —
moving Main.hs and the 27 executable-only modules into `src-exe/`,
leaving `src/` library-only — is invisible to users and to test
code (which always went through the library), but it makes the
convention enforceable at the GHC level: a new helper added to
`src/` is automatically library-visible, and a new helper added to
`src-exe/` cannot be reached by the test suite.

Two additional cleanups landed alongside the source-dir split.
`Seihou.CLI.Shared` and `Seihou.CLI.Style` were promoted from the
library's `other-modules` to its `exposed-modules` because twelve
executable-only handlers import them; the library-private placement
only worked while both targets shared `src/`.
`Seihou.CLI.SchemaVersion` was promoted as planned (no source
change, just a cabal edit).

EP-3's work (the AgentLaunch split, the Outdated re-export cleanup,
and a regression test for the now-library-visible AgentLaunch
helpers) is now a single-target edit per the plan: the executable
already depends on the library, so moving a module is a single
cabal-line change.

EP-4's enforcement script will assert this layout. The
`EXEMPT_MODULES` array can stay tiny — only `Paths_seihou_cli` (and
optionally `AgentLaunch` until EP-3 splits it) needs an exemption.


## Context and Orientation

This subsection orients a reader who has only this plan and the working tree.

The repository at `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` is a
multi-package Haskell (GHC2024) cabal workspace. The package this plan touches is
`seihou-cli/`, which has three targets declared in `seihou-cli/seihou-cli.cabal`:

- `library seihou-cli-internal` (private library, used by the test suite). Its
  `hs-source-dirs` is `src`. Its `exposed-modules` (as of 2026-04-26) is:
  `Seihou.CLI.BrowseFormat`, `CommitMessage`, `Diff`, `Git`, `Init`,
  `InstallHistory`, `InstallShared`, `List`, `Migrate`, `PendingMigrations`,
  `Registry`, `Registry.Sync`, `RemoteVersion`, `SavePrompted`, `StatusRender`,
  `VersionCompare`, plus `Seihou.Effect.Fzf`, `Seihou.Effect.FzfInterp`,
  `Seihou.Fzf`, `Seihou.Fzf.Selector`, and `Seihou.Fzf.Selector.Module`. Its
  `other-modules` (private to the library) is: `Seihou.CLI.Shared` and
  `Seihou.CLI.Style`.
- `executable seihou` (the binary). `hs-source-dirs: src`. `main-is: Main.hs`.
  Its `build-depends` lists `seihou-core` but NOT `seihou-cli-internal`. Its
  `other-modules` lists ~30 modules — many of which are duplicates of the
  library's `exposed-modules`, and the rest are handler modules, agent-prompt
  wrappers, the parser hub, help, kit, version, and completions.
- `test-suite seihou-cli-test`. `hs-source-dirs: test`. `build-depends`
  `seihou-cli-internal` and `seihou-core`. Cannot reach modules that live only in
  the executable target.

Two facts make the duplication possible without an immediate compiler error:

1. Both `library` and `executable` have `hs-source-dirs: src`, so each target sees
   every module under `src/` as a candidate; the `other-modules` and
   `exposed-modules` lists determine which of those candidates each target actually
   compiles.
2. Cabal does not flag "module appears in two targets' module lists" as an error.
   It happily compiles the same source file twice, once for each target.

So the current state is: the library compiles its 21 exposed modules and 2 internal
modules; the executable independently re-compiles ~14 of those same modules (because
they appear in both `library.exposed-modules` and `executable.other-modules`) plus
the ~16 modules that are exclusively executable. This is the duplicate-compilation
fingerprint to capture in Surprises & Discoveries.

The seven modules that legitimately need executable-only Haskell-package
dependencies (verified by grep on 2026-04-26):

- `Seihou.CLI.Assist` — imports `Data.FileEmbed`.
- `Seihou.CLI.Bootstrap` — imports `Data.FileEmbed`.
- `Seihou.CLI.Commands` — imports `Options.Applicative`.
- `Seihou.CLI.Help` — imports `Data.FileEmbed`.
- `Seihou.CLI.Kit` — imports `Options.Applicative`.
- `Seihou.CLI.Setup` — imports `Data.FileEmbed`.
- `Seihou.CLI.Version` — imports `GitHash` and `Paths_seihou_cli`.

Eighteen modules import `Seihou.CLI.Commands` (and so are transitively trapped)
and the four `Seihou.CLI.Completions[.*]` modules also import `Commands`. The
combined set of executable-trapped modules after this plan should therefore be
roughly: the seven directly-trapped modules above, the four completion modules,
and the fifteen-or-so handler modules that import `Commands`.

`Seihou.CLI.SchemaVersion` is the one currently-executable-only module that does
NOT import `Commands` and does NOT import any of the four executable-only
Haskell-package dependencies. It is 17 lines of pure constants
(`schemaUrl`, `schemaHash`, `schemaImportLine`) consumed by `NewModule.hs` and
`SchemaUpgrade.hs`. It is the trivial promotion this plan does as part of the
restructure.

`Seihou.CLI.AgentLaunch` does not import `Commands` either, but it is a moderate
extraction (the module mixes pure helpers with `launchAgent`/`launchAgentWith`
that do `findExecutable` and `rawSystem` and `exitWith`). The split is owned by
sibling plan `docs/plans/20-extract-trapped-cli-helpers.md`, not this one. This
plan leaves `AgentLaunch` in `executable seihou`'s `other-modules` with a
placeholder comment that the EP-3 work will refine.

Key terms:

- **"Trapping dependency"**: the specific Haskell import or upstream-module import
  that prevents a module from living in the library. The convention enumerates
  four direct Haskell-package candidates (`Options.Applicative`, `Data.FileEmbed`,
  `GitHash`, `Paths_seihou_cli`) plus the transitive "imports another
  executable-only seihou module" criterion.
- **"Duplicate compilation fingerprint"**: the visible signal in `cabal build -v`
  output that a single source file is compiled once for the library target and
  once for the executable target. In `cabal build` log lines, this looks like
  two "Compiling Seihou.CLI.Migrate" entries — one under the library, one under
  the executable.


## Plan of Work

This plan has three milestones, each independently verifiable by running `cabal
build all` and `cabal test all` after the change.


### Milestone 1: Capture the current state and add the library dependency

Scope: take a baseline of the duplicate-compilation behaviour (one cabal-build log
snippet is enough), then make the executable depend on the library. Expect that
adding the dependency alone, without removing the duplicate `other-modules`
entries, leaves the build still working — Cabal does not refuse a module being
"available from two sources" when both sources resolve to the same file.

What will exist at the end: the executable target carries
`build-depends: seihou-cli-internal` and the build still succeeds.

Commands to run:

    cabal clean
    cabal build all -v 2>&1 | rg "Compiling Seihou.CLI.Migrate"

Expected before the edit: at least two lines, one for the library and one for the
executable. Capture this in the Surprises & Discoveries section.

Then edit `seihou-cli/seihou-cli.cabal`. In the `executable seihou` block, add
`seihou-cli-internal,` to the `build-depends` list (alphabetised between
`process` and `seihou-core` is fine; cabal does not require an order).

Re-run:

    cabal build all
    cabal test all

Expected: both succeed. The duplicate compilation may persist at this point
(modules are still listed in both targets); the next milestone removes the
duplicates.

Acceptance: build green, tests green, `seihou-cli-internal` appears in the
executable's `build-depends`.


### Milestone 2: Remove the duplicate `other-modules` entries

Scope: every module that appears in BOTH `library seihou-cli-internal`'s
`exposed-modules` AND `executable seihou`'s `other-modules` is removed from the
executable's list. After this milestone, each shared module is compiled exactly
once (by the library) and the executable imports it through the library.

What will exist at the end: the executable's `other-modules` list contains only
modules that are NOT in the library's `exposed-modules` (or `other-modules`).

To compute the diff, run:

    rg "^    Seihou\." seihou-cli/seihou-cli.cabal | sort | uniq -d

This finds module lines that appear at least twice in the cabal file with the
same indentation; each duplicate is a candidate for removal from the executable's
list. (If your cabal file uses a different indentation, adjust the regex.)

Edit `seihou-cli/seihou-cli.cabal`'s `executable seihou` block. For each module
name that also appears in `library seihou-cli-internal`'s `exposed-modules` or
`other-modules`, delete the line from the executable's `other-modules` list. Do
not touch the library's lists. Do not touch `Paths_seihou_cli` (it is the
auto-generated module and stays in the executable).

After editing, re-run:

    cabal clean
    cabal build all
    cabal test all

Expected: both succeed. The build should now compile each shared module exactly
once. To confirm:

    cabal clean
    cabal build all -v 2>&1 | rg "Compiling Seihou.CLI.Migrate"

Expected: exactly one match (compiled once for the library), down from the
multiple matches captured in Milestone 1's baseline.

If the build fails with "Could not find module Seihou.CLI.X" while compiling an
executable-only module, the executable-only module is importing X but the
library does not re-export it the way the executable expected. The fix is
usually to verify X is in the library's `exposed-modules`; if X is in the
library's `other-modules` (private to the library), promote it to
`exposed-modules` in this same milestone with a one-line note in Surprises &
Discoveries.

Acceptance: build green, tests green, `cabal build -v` shows each previously
duplicated module compiled once.


### Milestone 3: Move SchemaVersion and annotate the residual list

Scope: move `Seihou.CLI.SchemaVersion` from the executable's `other-modules` to
the library's `exposed-modules`. Then, for every remaining entry in the
executable's `other-modules`, add a one-line cabal comment naming the trapping
dependency.

What will exist at the end: the executable's `other-modules` list is annotated
end-to-end. A reader can scan it and see, for each module, why it has not been
promoted.

Step 3.1: Move `Seihou.CLI.SchemaVersion`.

    1. In `seihou-cli/seihou-cli.cabal`, remove `Seihou.CLI.SchemaVersion`
       from `executable seihou`'s `other-modules`.
    2. Add `Seihou.CLI.SchemaVersion` to `library seihou-cli-internal`'s
       `exposed-modules` (alphabetised between `Seihou.CLI.SavePrompted` and
       `Seihou.CLI.StatusRender`).
    3. Run `cabal clean && cabal build all && cabal test all`. Expect both
       to succeed without source-file changes; the file already does not
       import any executable-only dependency (verified by grep on
       2026-04-26).

Step 3.2: Annotate the residual `other-modules`.

For each entry remaining in `executable seihou`'s `other-modules` after Steps
3.1 and Milestone 2, add a one-line cabal comment naming the trapping
dependency. Use the following classifications, derived from the imports already
present in each file:

    other-modules:
      Paths_seihou_cli
        -- generated by cabal; lives in the executable
      Seihou.CLI.AgentLaunch
        -- mixed: pure surface plus launchAgent (process invocation);
        --   split deferred to docs/plans/20-extract-trapped-cli-helpers.md
      Seihou.CLI.Assist
        -- needs Data.FileEmbed for the embedded prompt template
      Seihou.CLI.Bootstrap
        -- needs Data.FileEmbed for the embedded prompt template
      Seihou.CLI.Browse
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.Commands
        -- needs Options.Applicative
      Seihou.CLI.Completions
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.Completions.Bash
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.Completions.Fish
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.Completions.Zsh
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.Config
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.Context
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.Help
        -- needs Data.FileEmbed for embedded help-topic content
      Seihou.CLI.Install
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.Kit
        -- needs Options.Applicative
      Seihou.CLI.NewModule
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.NewRecipe
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.Outdated
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.Remove
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.Run
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.SchemaUpgrade
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.Setup
        -- needs Data.FileEmbed for the embedded prompt template
      Seihou.CLI.Status
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.Upgrade
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.Validate
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.Vars
        -- imports Seihou.CLI.Commands (transitively trapped)
      Seihou.CLI.Version
        -- needs GitHash and Paths_seihou_cli

Cabal accepts `--` line comments inside stanza bodies; verify by re-running
`cabal build all` after the edit. If any of the comments above does not match
what `grep "^import"` on the relevant file shows, update the comment to match
the actual imports rather than the comment.

Acceptance: build green, tests green; every entry in the executable's
`other-modules` carries a one-line comment; no module without a recognised
trapping dependency or a transitive trap is listed.


## Concrete Steps

### Step 1: Baseline

From the repo root (`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`):

    cabal clean
    cabal build all -v 2>&1 | rg "Compiling Seihou.CLI.Migrate" | tee /tmp/baseline-migrate.txt

Expected output: at least two lines (one per target). Save the file path for the
Surprises & Discoveries entry.

### Step 2: Add `seihou-cli-internal` to the executable's `build-depends`

Open `seihou-cli/seihou-cli.cabal`. Locate the `executable seihou` stanza
(starts around line 62). Find its `build-depends:` block (around line 128). Add
`seihou-cli-internal,` to the list (alphabetised between `process` and
`seihou-core`). Save.

Verify:

    rg -A 20 "^executable seihou" seihou-cli/seihou-cli.cabal | rg "seihou-cli-internal"

Expected: one match.

Build:

    cabal build all
    cabal test all

Expected: both succeed.

### Step 3: Remove duplicate `other-modules` entries

Compute the duplicate set:

    rg "^    Seihou\." seihou-cli/seihou-cli.cabal | sort | uniq -d

Expected: ~14 module names, each one currently in both `library
seihou-cli-internal`'s `exposed-modules` and `executable seihou`'s
`other-modules`.

Edit `seihou-cli/seihou-cli.cabal` to delete each duplicate from the
executable's `other-modules` list. Do not touch the library. Save.

Build and test:

    cabal clean
    cabal build all
    cabal test all

Expected: both succeed. If `cabal build` reports "Could not find module
Seihou.CLI.X" while compiling an executable-only file, X is library-private; if
moving X to the library's `exposed-modules` is correct (because it's already
imported across the boundary), do that move and re-run.

Verify the duplicate-compilation is gone:

    cabal clean
    cabal build all -v 2>&1 | rg "Compiling Seihou.CLI.Migrate"

Expected: one match, not two.

### Step 4: Move `Seihou.CLI.SchemaVersion`

Confirm SchemaVersion has no exec-only imports:

    rg "^import" seihou-cli/src/Seihou/CLI/SchemaVersion.hs

Expected: imports only base / Text. Confirm it does not import
`Seihou.CLI.Commands` either.

Edit `seihou-cli/seihou-cli.cabal`:

    1. Remove `Seihou.CLI.SchemaVersion` from `executable seihou`'s
       `other-modules`.
    2. Add `Seihou.CLI.SchemaVersion` to `library seihou-cli-internal`'s
       `exposed-modules`, alphabetised.

Build and test:

    cabal build all
    cabal test all

Expected: both succeed.

### Step 5: Annotate the residual `other-modules`

For each remaining entry in `executable seihou`'s `other-modules`, add a
one-line cabal comment underneath naming the trapping dependency. Use the
classifications in Milestone 3 above. The classifications were derived as
follows; verify each by inspection if you suspect drift:

    # Modules that import one of the four exec-only Haskell deps
    rg -l "Options.Applicative|Data.FileEmbed|GitHash|Paths_seihou_cli" \
       seihou-cli/src/Seihou/CLI/*.hs seihou-cli/src/Seihou/CLI/Completions/*.hs

    # Modules that import Seihou.CLI.Commands (transitively trapped)
    rg -l "^import Seihou.CLI.Commands" seihou-cli/src/Seihou/CLI/*.hs \
       seihou-cli/src/Seihou/CLI/Completions/*.hs

Build and test once after annotating:

    cabal build all
    cabal test all

Expected: both succeed. Cabal `--` comments are syntactically valid inside
stanza bodies but if the build fails on a cabal parse error, check the comment
indentation matches the surrounding lines.

### Step 6: Update the CHANGELOG

Add an entry to `docs/user/CHANGELOG.md`:

    - 2026-04-26: Restructured `seihou-cli/seihou-cli.cabal` so the
      `seihou` executable target depends on the `seihou-cli-internal`
      library and no longer duplicates library modules in its
      `other-modules`. Promoted `Seihou.CLI.SchemaVersion` to the
      library. Annotated each remaining entry in the executable's
      `other-modules` with the trapping dependency. See
      `docs/dev/architecture/overview.md` section "CLI Module Placement
      Convention".

### Step 7: Commit

    git add seihou-cli/seihou-cli.cabal docs/user/CHANGELOG.md
    git commit -m "$(cat <<'EOF'
    refactor(cli): make executable depend on the library and annotate trapped modules

    The executable target now build-depends on seihou-cli-internal and no
    longer duplicates library modules in its other-modules. Each remaining
    entry carries a comment naming the trapping dependency
    (Options.Applicative, Data.FileEmbed, GitHash, Paths_seihou_cli, or
    transitive via Seihou.CLI.Commands). Promotes
    Seihou.CLI.SchemaVersion to the library; the file is 17 lines of pure
    constants and was the only mechanically-promotable module identified
    by the audit captured in the masterplan.

    MasterPlan: docs/masterplans/2-cli-library-first-convention.md
    ExecPlan: docs/plans/19-restructure-cli-cabal-library-first.md
    Intention: intention_01kq63sz0ced98e23qvad7zpnp
    EOF
    )"


## Validation and Acceptance

Acceptance is two-fold: the build is green, and the cabal layout reflects the
convention.

Build acceptance:

    cabal clean
    cabal build all
    cabal test all

Both succeed.

Layout acceptance:

    rg "build-depends" seihou-cli/seihou-cli.cabal | rg "seihou-cli-internal"

Returns at least one match (in the executable stanza).

    rg "^    Seihou\." seihou-cli/seihou-cli.cabal | sort | uniq -d

Returns nothing (no duplicates between library and executable module lists).

    rg -A 30 "^executable seihou" seihou-cli/seihou-cli.cabal | rg "^      --" | wc -l

Returns at least one comment per residual `other-modules` entry (count should
match the residual count, roughly 25-27).

Behavioural confirmation: the binary still works end-to-end. From the repo root:

    cabal run seihou -- --version
    cabal run seihou -- --help

Both produce output. Run a representative end-user command in a temp directory:

    cd /tmp && mkdir cabal-restructure-check && cd cabal-restructure-check
    /path/to/seihou init
    /path/to/seihou status

`init` should scaffold a project; `status` should run without error.


## Idempotence and Recovery

This plan is safe to re-run at any milestone boundary. Each step edits
`seihou-cli/seihou-cli.cabal` and is idempotent: if `seihou-cli-internal` is
already in `build-depends`, Step 2 is a no-op; if a module has already been
removed from the executable's `other-modules`, Step 3 has nothing to delete; if
SchemaVersion is already library-exposed, Step 4 is a no-op; if a comment is
already in place, Step 5 leaves it.

If the build fails partway through, the safe recovery is `git diff
seihou-cli/seihou-cli.cabal` to see what has changed and `git checkout --
seihou-cli/seihou-cli.cabal` to revert if needed; no source files are touched
by this plan.

Note: a partial state (Milestone 1 done, Milestone 2 not done) is a working
build. The duplicate compilation persists, but cabal handles it without error.


## Interfaces and Dependencies

Files edited:

- `seihou-cli/seihou-cli.cabal`: add a build-depends entry, remove ~14
  duplicate `other-modules` entries, move `Seihou.CLI.SchemaVersion` from
  executable to library, annotate ~25 remaining executable `other-modules`
  entries.
- `docs/user/CHANGELOG.md`: prepend one entry.

No source files edited. No new modules created. No tests added (sibling plan
`docs/plans/20-extract-trapped-cli-helpers.md` adds tests as part of
extraction).

External dependencies: this plan introduces no new Haskell packages. The
`seihou-cli-internal` library already exists; this plan only adds it to the
executable's `build-depends`.

The convention this plan encodes lives at:

- Canonical: `docs/dev/architecture/overview.md`, section "CLI Module
  Placement Convention" (created by sibling plan
  `docs/plans/18-document-cli-library-first-convention.md`).
- Quick reference: `CLAUDE.md` at the repo root (created by the same sibling
  plan).

Sibling plans this plan unblocks:

- `docs/plans/20-extract-trapped-cli-helpers.md` — once the executable depends
  on the library, splitting `Seihou.CLI.AgentLaunch` and updating consumer
  imports is a single-target edit instead of a two-target dance.
- `docs/plans/21-enforce-cli-library-first-convention.md` — the enforcement
  script asserts the post-restructure layout, which this plan produces.
