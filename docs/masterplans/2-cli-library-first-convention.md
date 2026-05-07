---
id: 2
slug: cli-library-first-convention
title: "Establish a CLI Library-First Convention to Prevent Recurring Helper-Extraction Refactors"
kind: master-plan
created_at: 2026-04-27T02:09:55Z
intention: "intention_01kq63sz0ced98e23qvad7zpnp"
---


# Establish a CLI Library-First Convention to Prevent Recurring Helper-Extraction Refactors

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/master-plan/MASTERPLAN.md`.


## Vision & Scope

After this initiative, the seihou CLI codebase has a single, self-enforcing rule for where
new code lives: a CLI helper goes into the `seihou-cli-internal` library by default, and
the `seihou` executable target is reserved for the IO shell — `Main.hs`, the
optparse-applicative parser hub, command dispatchers, and the small set of modules that
genuinely require executable-only dependencies (`optparse-applicative`, `file-embed`,
`githash`, `Paths_seihou_cli`).

What a contributor (human or agent) sees after this initiative:

- The architecture doc, the project root `CLAUDE.md`, and a developer contributing doc
  state the rule plainly and enumerate the specific dependencies that justify
  executable-only placement.
- The `seihou-cli.cabal` file is restructured so `executable seihou` `build-depends:
  seihou-cli-internal` and its `other-modules` list contains only the small set of
  modules that legitimately cannot live in the library, each annotated with a one-line
  comment naming the executable-only dependency that traps it.
- The remaining helpers identified by the audit captured in this masterplan
  (`AgentLaunch.hs`'s pure surface, `SchemaVersion.hs`, and the redundant re-exports in
  `Outdated.hs`) have been moved or cleaned up so the post-restructure layout is free of
  known violations.
- An automated check, wired into `nix flake check` and the existing pre-commit
  configuration, fails the build when a new module is added to `executable seihou`'s
  `other-modules` without importing one of the recognised executable-only dependencies
  (or appearing on a small, justified exempt list).

The user-visible behaviour after the full initiative is that when a future contributor
adds, for example, a new pure helper in support of a new `seihou audit` command, the
following sequence happens automatically: they put it in the executable's `other-modules`,
the build (or pre-commit) fails with a message pointing them at
`docs/dev/architecture/overview.md`'s "CLI Module Placement" section, and the fix is to
add the module to `seihou-cli-internal`'s `exposed-modules`. No more mid-implementation
discovery that "oh, the test suite can't reach this helper because it's executable-only"
followed by an unscheduled extraction refactor.

In scope:

- Documentation of the convention in three discoverable places (architecture overview,
  project-root CLAUDE.md, developer contributing doc).
- Cabal restructure of `seihou-cli/seihou-cli.cabal`: executable depends on the library;
  duplicate `other-modules` removed; modules that have no executable-only dependencies
  moved into the library `exposed-modules` as part of the restructure.
- Extraction of three specific helper sets identified by the audit done while writing
  this masterplan: `AgentLaunch.hs` split into a library module (pure surface plus
  `AgentContext`) and an executable wrapper (process invocation), `SchemaVersion.hs`
  promoted whole, and `Outdated.hs`'s redundant re-exports of `OriginInfo` /
  `OutdatedEntry` retired in favour of the canonical sites in `InstallShared` and
  `VersionCompare`.
- An automated check that flags violations of the convention, runnable via `nix flake
  check` and as a pre-commit hook.
- Documentation entries in `docs/user/CHANGELOG.md` for each child plan as it lands.

Out of scope:

- Any refactor of `Migrate.hs` to extract its pure migration-engine surface into a
  library module. The audit flagged this as Tier 3 (high effort, requires careful
  effect-boundary design) and it does not block the convention.
- Restructuring `seihou-core`'s own internal organisation; this initiative concerns the
  CLI package only.
- Moving `Commands.hs`, `Help.hs`, `Kit.hs`, `Version.hs`, or the agent-prompt wrappers
  (`Assist`, `Bootstrap`, `Setup`) out of the executable. Each one legitimately imports
  an executable-only dependency (the audit confirmed this exhaustively); they will stay
  but receive a one-line comment in the cabal file naming the trapping dependency.
- Adding new commands. Plans that add `seihou audit`, alternate JSON status formatters,
  or other surfaces hinted at in the EP-1/EP-2/EP-4 retrospectives of the
  `1-migrations-dx.md` masterplan are deliberately deferred.


## Decomposition Strategy

The decomposition follows the natural lifecycle of a project-wide convention: state the
rule, make the codebase express the rule, bring legacy code into compliance, and arm the
build to keep it compliant. Each child plan corresponds to one phase of that lifecycle
and produces an independently demonstrable behaviour.

The principles applied:

- **Stating the rule before encoding it.** EP-1 owns the canonical text of the
  convention. EP-2 (cabal restructure) and EP-4 (enforcement) are mechanical
  expressions of the same rule and reference EP-1's text rather than re-stating it.
  This avoids divergence between the documented rule and the enforced rule.
- **Functional concerns over file boundaries.** "Document the convention",
  "restructure the cabal file so the convention is the default", "extract the legacy
  helpers that the convention demands", and "enforce the convention automatically" are
  four distinct concerns even though they overlap on the same files
  (`seihou-cli/seihou-cli.cabal`, `docs/dev/architecture/overview.md`).
- **Independent verifiability.** Each child plan ends with a concrete, observable
  outcome: EP-1 produces docs that a contributor can read; EP-2 produces a `cabal
  build` that succeeds against a smaller, intentional executable target; EP-3
  produces a passing test suite that exercises previously-untestable helpers; EP-4
  produces a deliberately-introduced violation that fails the new check with a clear
  message.
- **Respect natural ordering.** Documentation comes before mechanical change because
  the cabal layout and the enforcement script are both derived from the convention's
  text. Extraction (EP-3) comes after the restructure (EP-2) because EP-2 makes module
  moves trivial cabal edits rather than two-target updates. Enforcement (EP-4) comes
  last so the check is asserted against a clean tree, not a tree with known
  violations.

Alternatives considered:

- **One mega-plan that does everything.** Rejected: more than seven milestones across
  four unrelated concerns (docs, cabal, code extraction, build infrastructure), and
  impossible to validate incrementally. The masterplan-level decomposition principles
  in `.claude/skills/master-plan/MASTERPLAN.md` explicitly favour two-to-seven plans.
- **Skip the documentation plan and let the cabal change speak for itself.** Rejected:
  the recurring pain documented in `docs/masterplans/1-migrations-dx.md` (EP-1, EP-2,
  EP-4 retrospective) was discoverability, not just structure. A future contributor
  who sees the cabal layout but not the rule has no reason to put a new helper in the
  library; they'll match whatever the nearest existing module does.
- **Skip the enforcement plan and rely on convention.** Rejected for the same reason
  the recurring refactors happened in the first place: a convention that depends on
  every contributor having read the docs is a convention that erodes. Even a simple
  shell script that names violations is dramatically better than nothing.
- **Fold extraction into the cabal restructure plan.** Rejected because the
  `AgentLaunch.hs` split is real code restructuring (it changes module boundaries and
  consumer imports), while the cabal restructure is a build-system change. Mixing
  them would obscure the diff and make rollback awkward if either piece needs more
  iteration.
- **Use Haskell-side tooling (weeder, hlint custom rule) for enforcement.** Rejected
  for the v1 of this initiative: a small shell script that parses the cabal file and
  greps for executable-only imports is cheaper to write and easier for a contributor
  to debug than a custom hlint rule. EP-4's plan will note this as a future
  enhancement if the simple check proves brittle.


## Exec-Plan Registry

| #   | Title                                                                | Path                                                            | Hard Deps | Soft Deps | Status      |
|-----|----------------------------------------------------------------------|-----------------------------------------------------------------|-----------|-----------|-------------|
| 1   | Document the CLI library-first module-placement convention            | docs/plans/18-document-cli-library-first-convention.md          | None      | None      | Complete    |
| 2   | Restructure `seihou-cli.cabal` so the library is the default home     | docs/plans/19-restructure-cli-cabal-library-first.md            | EP-1      | None      | Complete    |
| 3   | Extract remaining executable-only helpers identified by the audit     | docs/plans/20-extract-trapped-cli-helpers.md                    | EP-2      | EP-1      | Complete    |
| 4   | Add an automated enforcement check for the convention                 | docs/plans/21-enforce-cli-library-first-convention.md           | EP-2      | EP-3      | Complete    |

Status values: Not Started, In Progress, Complete, Cancelled.


## Dependency Graph

EP-1 (documentation) is foundational. It defines the canonical text of the convention,
the enumerated list of dependencies that justify executable-only placement
(`optparse-applicative`, `file-embed`, `githash`, `Paths_seihou_cli`), and the
exemption rationale format. Every later plan refers back to this text. Without EP-1,
the cabal comments in EP-2 and the script messages in EP-4 would drift apart.

EP-2 (cabal restructure) hard-depends on EP-1 because the restructure encodes the
convention's specific rules. The decision of which modules move into the library and
which stay in the executable is exactly the rule EP-1 documents. Doing EP-2 first
would mean either guessing the rule or writing the rule into the cabal file as code
comments and then duplicating the same text into a doc, which is the divergence we
explicitly want to avoid.

EP-3 (extract trapped helpers) hard-depends on EP-2 because once the executable
`build-depends: seihou-cli-internal`, moving a module from the executable's
`other-modules` to the library's `exposed-modules` is a single cabal edit rather than
a two-target dance. EP-3 has a soft dependency on EP-1 because the convention's text
provides the rationale a reviewer expects in the EP-3 commit messages.

EP-4 (enforcement check) hard-depends on EP-2 because the check inspects the
post-restructure layout: it parses the executable's `other-modules` and verifies each
entry imports one of the executable-only dependencies (or appears on the exempt
list). Running the check against the pre-restructure tree would produce dozens of
false positives. EP-4 has a soft dependency on EP-3 because EP-3 retires the last
known violations; without EP-3, the EP-4 check would have to start with a longer
exempt list and shrink it later, which is workable but messier.

Parallelism: After EP-1 ships, EP-2 can begin. EP-3 and EP-4 cannot proceed in
parallel — both need EP-2's restructure complete — but EP-3 and EP-4 can be worked on
by different contributors once EP-2 lands, with the EP-4 contributor using EP-3's
in-progress branch as the reference for the empty exempt list.

Critical path: EP-1 → EP-2 → EP-3 → EP-4 (four plans serial, but EP-3 and EP-4 are
small and can be tightly interleaved).


## Integration Points

This section enumerates every shared artifact two or more child plans touch. Each
child plan must consult this list before defining its own contracts.

**1. Convention text and the enumerated executable-only dependencies.**

- Involved plans: EP-1 (definer), EP-2 (consumer), EP-3 (consumer), EP-4 (consumer).
- Artifact: A short prose section (around half a page) in
  `docs/dev/architecture/overview.md`, mirrored into the project-root `CLAUDE.md`
  EP-1 will create. The section names the convention, lists the four
  executable-only Haskell-package dependencies that justify a module staying in the
  executable target (`optparse-applicative`, `Data.FileEmbed` / `file-embed`,
  `GitHash` / `githash`, `Paths_seihou_cli`), states the fifth transitive
  criterion (importing another executable-only seihou module — most often
  `Seihou.CLI.Commands`), and shows the cabal-comment format that EP-2 will use to
  annotate each entry in the executable's `other-modules` list.
- Owning plan: EP-1. EP-2's cabal comments must quote or paraphrase the EP-1 text so
  a reader of the cabal file can locate the full rationale. EP-4's enforcement
  script must use the same dependency list as the matchable pattern and implement
  the transitive criterion as a closure computation.

**2. The post-restructure list of legitimately executable-only modules.**

- Involved plans: EP-2 (definer), EP-3 (consumer — what NOT to move), EP-4 (consumer
  — the closure-computation input plus the exempt list).
- Artifact: The set of modules that remain in `executable seihou`'s `other-modules`
  after EP-2 lands. Two groups make up this set:
  - **Directly trapped** (seven modules): `Seihou.CLI.Commands` (`Options.Applicative`),
    `Seihou.CLI.Kit` (`Options.Applicative`), `Seihou.CLI.Help` (`Data.FileEmbed`),
    `Seihou.CLI.Assist` (`Data.FileEmbed`), `Seihou.CLI.Bootstrap`
    (`Data.FileEmbed`), `Seihou.CLI.Setup` (`Data.FileEmbed`), `Seihou.CLI.Version`
    (`GitHash` and `Paths_seihou_cli`). After EP-3 lands, add
    `Seihou.CLI.AgentLaunchExec` (uses `System.Process.rawSystem` and
    `System.Exit.exitWith` to launch the claude binary; EP-3 splits the current
    `AgentLaunch` and leaves the launcher half here).
  - **Transitively trapped** (about eighteen modules): every command-handler module
    that imports `Seihou.CLI.Commands` for its `Opts` type — `Browse`, `Config`,
    `Context`, `Install`, `NewModule`, `NewRecipe`, `Outdated`, `Remove`, `Run`,
    `SchemaUpgrade`, `Status`, `Upgrade`, `Validate`, `Vars` — plus the four
    `Completions.*` modules. These are trapped until a future plan extracts the
    `Opts` types out of `Commands` into a library-eligible module; that extraction
    is explicitly out of scope for this masterplan and is recorded in the Decision
    Log as deferred.
  - Plus `Paths_seihou_cli`, the auto-generated module that has no source file and
    therefore appears on EP-4's `EXEMPT_MODULES` list.
- Owning plan: EP-2 produces the annotated list; EP-3 must not move any module from
  this set; EP-4's enforcement script computes the transitive closure rather than
  maintaining a static list, so the only static input it needs is the
  `EXEMPT_MODULES` array (just `Paths_seihou_cli` today).

**3. The audit-identified extraction targets.**

- Involved plans: EP-2 (executes the trivial moves: SchemaVersion, mechanical
  cabal-only changes), EP-3 (executes the code-restructuring moves: AgentLaunch
  split, Outdated re-export cleanup).
- Artifact: A division of labour. EP-2 may move a module that currently sits in the
  executable's `other-modules` and would compile unchanged in the library — that is
  a pure cabal edit. EP-3 owns moves that require source changes (splitting a module
  into two, deleting re-exports, updating consumer imports). The masterplan
  explicitly lists these:
  - **EP-2 (mechanical)**: `Seihou.CLI.SchemaVersion` (pure constants, no
    executable-only deps; verified by inspecting
    `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`).
  - **EP-3 (restructuring)**: split `Seihou.CLI.AgentLaunch` into a library module
    (the pure surface — `AgentContext`, `gatherAgentContext`, `agentDirsForSession`,
    `defaultAllowedTools`, `setupAllowedTools`, `bootstrapAllowedTools`,
    `substitute`, `formatSeihouProjectState`, `formatManifestState`,
    `formatModuleDhallState`, `formatLocalModules`, `formatAvailableModules`) and
    an executable module (`launchAgent`, `launchAgentWith` — these call
    `findExecutable` and `rawSystem` and use `exitWith`, but more importantly they
    are the only consumers of the launcher and live alongside the agent-prompt
    wrappers that already stay executable-only).
  - **EP-3 (cleanup)**: drop the re-exports of `OriginInfo`, `OutdatedStatus`,
    `OutdatedEntry`, `CheckStats`, and `compareVersions` from
    `Seihou.CLI.Outdated`'s export list (lines 3-10 of
    `seihou-cli/src/Seihou/CLI/Outdated.hs`). The canonical sites are
    `Seihou.CLI.InstallShared` (for `OriginInfo`) and `Seihou.CLI.VersionCompare`
    (for the rest), already library-exposed. Update any consumer that imports these
    names from `Outdated` to import from the canonical site instead.

**4. The enforcement script's interface.**

- Involved plans: EP-4 (definer), EP-2 (informs the layout the script enforces),
  EP-3 (informs the empty-or-near-empty exempt list the script starts with).
- Artifact: A small, standalone script (Bash or Haskell) that lives at a path EP-4
  will choose (likely `nix/check-cli-module-placement.sh` or
  `scripts/check-cli-module-placement`). The script reads
  `seihou-cli/seihou-cli.cabal` and `seihou-cli/src/**/*.hs`, walks the executable's
  `other-modules`, and verifies each module either imports one of the four
  executable-only dependencies enumerated in EP-1 or appears on the exempt list.
  EP-4 wires it into `flake.nix`'s `checks` attribute so `nix flake check` runs it,
  and into `.pre-commit-config.yaml` (or the equivalent flake-driven pre-commit
  configuration) so a normal commit catches violations early.

**5. Documentation cross-references.**

- Involved plans: All four.
- Artifact: `docs/dev/architecture/overview.md` (EP-1 adds the convention section),
  the project root `CLAUDE.md` (EP-1 creates it; EP-4 updates it with a one-line
  pointer to the new check), `docs/dev/contributing.md` (EP-1 creates it as a
  developer-facing doc that includes the convention plus general guidance),
  `seihou-cli/seihou-cli.cabal` (EP-2 adds annotated comments referencing the
  convention section), and `docs/user/CHANGELOG.md`. Each child plan owns its own
  CHANGELOG entry; each entry includes the date and a one-sentence summary.


## Progress

Track milestone-level progress across all child plans. Each entry names the child
plan and the milestone. This section provides an at-a-glance view of the entire
initiative.

- [x] EP-1: Draft and land the "CLI Module Placement" section of `docs/dev/architecture/overview.md`.
- [x] EP-1: Create the project-root `CLAUDE.md` with a quick-reference pointer to the convention.
- [x] EP-1: Create `docs/dev/contributing.md` containing the convention plus general contributor guidance, and cross-link it from the architecture overview.
- [x] EP-2: Reproduce the duplicate-compilation fingerprint of the current cabal layout (a short note for the EP-2 retrospective; not a regression test).
- [x] EP-2: Make `executable seihou` `build-depends: seihou-cli-internal`; remove from its `other-modules` every entry that already exists in the library's `exposed-modules`; verify `cabal build all` and `cabal test all` succeed.
- [x] EP-2: Move `Seihou.CLI.SchemaVersion` from the executable's `other-modules` to the library's `exposed-modules`; annotate every remaining entry in the executable's `other-modules` (record the trapping reason — see Surprises & Discoveries for the format change from per-line cabal comments to a doc-driven inventory table).
- [x] EP-3: Split `Seihou.CLI.AgentLaunch` into `Seihou.CLI.AgentLaunch` (library, pure surface plus `AgentContext`) and `Seihou.CLI.AgentLaunchExec` (executable, process invocation); update `Assist`, `Bootstrap`, `Setup`, and `Main.hs` imports.
- [x] EP-3: Drop the re-exports of `OriginInfo`, `OutdatedStatus`, `OutdatedEntry`, `CheckStats`, and `compareVersions` from `Seihou.CLI.Outdated`'s export list; update any consumer to import from the canonical site (`InstallShared` or `VersionCompare`).
- [x] EP-3: Add a regression test under `seihou-cli/test/Seihou/CLI/AgentLaunchSpec.hs` that exercises the now-library-exposed pure surface (e.g., `substitute` and one of the formatters) to demonstrate the extraction enabled testing that was impossible before.
- [x] EP-4: Write the enforcement script (Bash) at `nix/check-cli-module-placement.sh`; verify it passes against the post-EP-3 tree (after promoting `Completions.{Bash,Fish,Zsh}` to the library — see Surprises & Discoveries).
- [x] EP-4: Wire the script into `flake.nix`'s `checks` attribute so `nix flake check` runs it; verified the check fails with a clear message when `Seihou.CLI.RemoteVersion` is deliberately added to `executable seihou`'s `other-modules`.
- [x] EP-4: Wire the script into the `pre-commit-check.hooks` block in `flake.nix` so a violation is caught at commit time, and updated the project-root `CLAUDE.md` with a one-line pointer to the check.


## Surprises & Discoveries

Discoveries captured during the masterplan's pre-implementation audit. Add to this
section as work proceeds and cross-plan insights emerge.

- **The executable target does not depend on the library.** `seihou-cli/seihou-cli.cabal`
  declares both `library seihou-cli-internal` and `executable seihou` with the same
  `hs-source-dirs: src`. The executable's `build-depends` lists `seihou-core` but not
  `seihou-cli-internal`, and its `other-modules` enumerates ~30 modules — most of
  which are also in the library's `exposed-modules`. The result is that every shared
  module is compiled twice (once for each target) and the executable can freely
  reach any module under `src/`, regardless of whether it's library-exposed. This is
  the structural root cause of the "helper trapped in executable" pattern: there is
  no compile-time signal that distinguishes library-exposed from executable-only.

- **Only seven CLI modules legitimately need executable-only dependencies.** A grep
  for `Options.Applicative`, `Data.FileEmbed`, `GitHash`, and `Paths_seihou_cli`
  across `seihou-cli/src/Seihou/CLI/**/*.hs` identifies exactly seven modules:
  `Assist.hs`, `Bootstrap.hs`, `Commands.hs`, `Help.hs`, `Kit.hs`, `Setup.hs`, and
  `Version.hs`. Plus the three shell-specific completion modules under
  `Completions/`. Plus their dispatcher and `Main.hs`. That is the entire defensible
  population of the executable's `other-modules` after the restructure. Every other
  current entry is either already library-exposed (and can be removed from the
  executable's list) or is library-eligible (and should be moved to the library's
  `exposed-modules`).

- **`AgentLaunch.hs` is the only remaining moderately-sized extraction target.** The
  audit confirmed that all other "large" modules (`Run.hs`, `Migrate.hs`,
  `Install.hs`, `Status.hs`, `Outdated.hs`) are either already correctly factored
  (their pure surface lives in a library sibling) or out of scope. `AgentLaunch`
  bundles a substantial pure surface (`AgentContext` plus six formatters plus the
  three tool-list constants plus `substitute`) with two genuinely IO-shell functions
  (`launchAgent`, `launchAgentWith`). Splitting it is mechanical but real
  restructuring work.

- **`Outdated.hs` already imports from the canonical sites but re-exports the same
  names.** Lines 22-31 of `seihou-cli/src/Seihou/CLI/Outdated.hs` import `OriginInfo`
  from `InstallShared` and `OutdatedEntry` / `OutdatedStatus` / `CheckStats` /
  `compareVersions` from `VersionCompare`. The export list (lines 1-13) re-exports
  all of these names. Any future consumer that imports from `Outdated` is reaching
  through the executable to access types that live in the library — a circular
  dependency waiting to happen. The cleanup is purely an export-list edit plus
  consumer-import updates; no code logic moves.

- **`SchemaVersion.hs` is 17 lines of pure constants and is trivially library-eligible.**
  Imports nothing executable-only; defines `schemaUrl`, `schemaHash`, and
  `schemaImportLine`; consumed by `NewModule.hs` and `SchemaUpgrade.hs`. The audit
  flagged this as the highest-value lowest-effort extraction. EP-2 will fold the
  move into the cabal restructure since no source change is needed.

- **The flake.nix `checks` attribute already runs `treefmt` and `pre-commit-check`,
  so the enforcement script slots in cleanly.** EP-4 can add a third `checks`
  attribute (`cli-module-placement` or similar) and wire it into the same
  `pre-commit-check` hooks block that already runs `treefmt`. No new flake input is
  needed.

- **There is no project-level `CLAUDE.md` or `CONTRIBUTING.md` today.** The exploration
  agent confirmed that only `README.md` exists at the project root and only
  `docs/dev/architecture/overview.md`, `docs/dev/versioning.md`, and the design /
  roadmap docs exist under `docs/dev/`. EP-1 is creating new top-level documents,
  not amending existing ones. This makes EP-1 simpler (no merge concerns) but
  raises the question of whether the new docs should also be linked from the
  README; EP-1 should answer this in its own scoping.

- **EP-2: shared `hs-source-dirs` made `other-modules` a non-control over
  compilation.** The plan's Milestone 2 assumption that removing duplicate
  `other-modules` entries from the executable would eliminate duplicate
  compilation was wrong. GHC walks `hs-source-dirs: src` and compiles
  every reachable source file regardless of `other-modules`, preferring
  local source over the package binary that `build-depends` would
  otherwise provide. The fix — splitting `hs-source-dirs` so the
  executable lives in `src-exe/` while the library keeps `src/` —
  required moving Main.hs and 27 executable-only modules. This change is
  invisible to users and to test code, but it makes the convention
  enforceable at the GHC level: a new helper added to `src/` is
  automatically library-visible, and a new helper added to `src-exe/`
  cannot be reached by the test suite. Impact on EP-3 and EP-4: no
  change. EP-3's `AgentLaunch` split lands the library half in `src/`
  and the executable half in `src-exe/`. EP-4's enforcement script
  inspects imports directly and works on either layout.

- **EP-2: per-line cabal comments don't survive `cabal-gild`.** The
  project's formatter (configured in `treefmt.nix`) sorts
  `other-modules` entries alphabetically and floats every `--` comment
  to the top of the section, silently desynchronising the originally
  planned per-module annotations from the modules they describe. The
  trapping inventory now lives in
  `docs/dev/architecture/overview.md` as a Markdown table. EP-1's
  documentation, EP-2's cabal file, the project-root `CLAUDE.md`, and
  `docs/dev/contributing.md` were updated to describe the
  doc-table format. Impact on EP-4: the enforcement script does not
  rely on the cabal-comment format — it inspects imports directly —
  so the format change is purely a documentation deviation.

- **EP-2 also promoted `Seihou.CLI.Shared` and `Seihou.CLI.Style` to
  the library's `exposed-modules`.** Twelve executable-only handlers
  import them. With the source-dir split, library-private placement
  no longer worked. This was not in the original audit; it surfaced
  during Milestone 2 of EP-2.

- **EP-3: the EP-3 plan body referenced pre-split file paths
  (`src/Seihou/CLI/AgentLaunch.hs`, `src/Seihou/CLI/Outdated.hs`).**
  EP-2's source-dir split moved those files to `src-exe/`, but the EP-3
  plan was authored before that landed and never refreshed. Implementation
  worked around it by reading the actual layout, creating the library
  half fresh at `src/Seihou/CLI/AgentLaunch.hs`, and editing the
  executable-side `src-exe/Seihou/CLI/Outdated.hs` directly. Lesson for
  future masterplans that ship in this lifecycle order: refresh every
  unstarted child plan's file paths after each parent milestone, since
  later plans were drafted against the earlier plans' projections, not
  their post-implementation reality.

- **EP-3: `OverloadedRecordDot` requires `Type (..)` imports.** With the
  CLI default-extensions (`OverloadedRecordDot`, `OverloadedLabels`),
  `ctx.cwd` only compiles when the data type's field selectors are in
  scope. Importing `AgentContext` alone fails with
  `No instance for HasField`. Importing `AgentContext (..)` works.
  EP-4's enforcement script does not need to know this, but any future
  library/executable split touching record types under these
  extensions should default to `(..)` imports.

- **EP-3: Outdated re-export consumers numbered exactly two
  (`Status.hs`, `Upgrade.hs`).** The masterplan's audit said "limited";
  this was correct. `Main.hs` only ever imported `handleOutdated`.

- **EP-3: AgentLaunchSpec contributed 14 new tests previously
  impossible.** Test count went from 143 → 157, exactly matching the
  new spec. This is the first concrete evidence that the convention
  pays back: helpers that were trapped in the executable became
  test-reachable the moment they moved to the library.

- **EP-4 starting position is now clean.** The library `exposed-modules`
  contains every helper that can legitimately live there. The
  executable's `other-modules` contains exactly the directly-trapped
  modules (seven via the four enumerated dependencies plus
  `AgentLaunchExec` via `System.Process`/`System.Exit`) and the
  transitively-trapped handlers (eighteen modules importing
  `Seihou.CLI.Commands` for their `Opts` type), plus the auto-generated
  `Paths_seihou_cli`. EP-4's enforcement script can be authored with an
  empty exempt list apart from `Paths_seihou_cli`.

- **EP-4: the "clean starting position" claim was off by three modules.**
  The enforcement script's first run flagged
  `Seihou.CLI.Completions.{Bash,Fish,Zsh}` as violations. They import
  only `Data.Text` and `Seihou.Prelude`; nothing exec-only and no
  transitive trap. The pre-EP-4 audits (EP-1 and EP-2) had categorised
  them as "shell-specific completion modules" and assumed they
  belonged in the executable, but the strict import-based rule
  disagreed. Fix: promoted all three to `seihou-cli-internal`'s
  `exposed-modules` (one cabal edit plus three `git mv` from
  `src-exe/Seihou/CLI/Completions/` to `src/Seihou/CLI/Completions/`).
  Post-fix, the executable's `other-modules` count dropped from 27 to
  24. This is the first concrete payoff of the enforcement check —
  it caught a soft assumption the human audit had missed.

- **EP-4: `AgentLaunchExec` had to be exempt, not "directly trapped".**
  This masterplan's earlier note implied
  `System.Process`/`System.Exit` would justify trapping. They do not
  — the rule is strictly the four enumerated dependencies plus the
  transitive criterion. `AgentLaunchExec` imports neither (it imports
  the library `AgentLaunch` and wraps it with system calls), so it
  appears in `EXEMPT_MODULES` with an inline comment. This is the
  second EP-4 deviation from the masterplan's planning text and the
  honest framing for any future reader.

- **EP-4: the script's repo-root resolution had to handle three
  callers.** Direct invocation (script and `$PWD` both at the repo
  root), `pkgs.runCommand` in the flake (`cd ./repo`), and
  pre-commit (script lives in `/nix/store/...` but `$PWD` is the
  repo root). The initial `BASH_SOURCE`-based logic was correct only
  for the first case. The fix prefers `$PWD` when it looks like a
  seihou checkout, with a `BASH_SOURCE` fallback and a
  `SEIHOU_REPO_ROOT` env-var override.

- **EP-4: `nix flake check`'s `pre-commit-check` derivation
  exercises the new hook end-to-end.** Adding a hook to
  `pre-commit-check.hooks` causes `pre-commit run --all-files` to
  invoke it during `nix flake check`, so a single deliberate-violation
  test verified both the standalone `cli-module-placement` check and
  the pre-commit wiring.


## Decision Log

- Decision: Decompose by lifecycle phase of the convention (state, encode, comply,
  enforce) rather than by file or by the audit's tier ranking.
  Rationale: Each phase produces a verifiable, demonstrable outcome. A by-file
  decomposition would scatter the convention's text, the cabal change, and the
  enforcement script across multiple plans. A by-tier decomposition would mix
  documentation work (no tier) with code-extraction work and make the enforcement
  story implicit.
  Date: 2026-04-26.

- Decision: Make EP-2 (cabal restructure) hard-depend on EP-1 (documentation), not
  the other way around.
  Rationale: The cabal layout encodes the convention's specific rules (which
  dependencies justify executable-only placement). Writing the cabal first and
  back-filling the docs invites divergence between the documented rule and the
  enforced rule. Writing the docs first means EP-2's cabal comments quote the docs
  and EP-4's enforcement script lists the same four dependencies the docs name.
  Date: 2026-04-26.

- Decision: Defer extracting `Migrate.hs`'s pure migration-engine surface.
  Rationale: The audit captured during this masterplan flagged it as Tier 3 (high
  effort, requires careful effect-boundary design) and noted it does not block the
  convention. Folding it in would inflate EP-3 to a multi-day plan. The convention,
  the cabal layout, and the enforcement check do not depend on `Migrate.hs` being
  factored further; if a future contributor adds a new helper alongside `Migrate`,
  the EP-4 check will catch it. Recording the deferral here so a future masterplan
  can pick it up.
  Date: 2026-04-26.

- Decision: Keep `Commands.hs`, `Help.hs`, `Kit.hs`, `Version.hs`, `Assist.hs`,
  `Bootstrap.hs`, `Setup.hs`, the three `Completions.*` shell modules and their
  dispatcher, and `Main.hs` in the executable target.
  Rationale: Each one imports `Options.Applicative`, `Data.FileEmbed`, `GitHash`,
  or `Paths_seihou_cli` (verified by grep). Moving them to the library would either
  pollute the library's dependency footprint or require a circular import. Each
  will receive a one-line cabal comment naming the trapping dependency so a future
  reader does not have to re-derive the rationale.
  Date: 2026-04-26.

- Decision: Use a small Bash script (or equivalent shell-callable Haskell binary)
  for EP-4's enforcement check rather than an HLint custom rule or a Weeder
  configuration.
  Rationale: The check is a build-system concern, not a code-style concern. Parsing
  the cabal file's `other-modules` list and grepping each named source file for
  one of four imports is a ~120-line shell script (the closure computation expands
  it beyond a one-liner but it remains compact). An HLint rule would require
  HLint's plugin API; a Weeder configuration cannot express "executable-only is
  fine if you justify it". The shell script keeps the enforcement transparent and
  modifiable; future contributors can add a justification by adding the module to
  the script's `EXEMPT_MODULES` array with an inline comment.
  Date: 2026-04-26.

- Decision: Defer the extraction of `Opts` types out of `Seihou.CLI.Commands`
  into a library-eligible module to a future plan.
  Rationale: Eighteen handler modules currently import their `Opts` type from
  `Commands.hs`; extracting `Opts` would unlock those handlers to move to the
  library. But the extraction is its own substantial refactor (the file is 1282
  lines and intermixes types with parsers) and is not on the critical path for
  the convention. The fifth, transitive trapping criterion (added during the
  masterplan's pre-implementation revision) handles the eighteen handlers
  cleanly without requiring them to move. Deferred to a future plan to keep
  this masterplan's scope finite.
  Date: 2026-04-26.


## Revision Notes

- 2026-04-26 (initial draft + same-day revision after EP-2 research): added the
  fifth, transitive trapping criterion ("imports another executable-only seihou
  module") to Integration Point #1 and to the convention's text in EP-1; rewrote
  Integration Point #2 to be honest that the executable's residual
  `other-modules` list is roughly twenty-five entries (seven directly trapped,
  eighteen transitively trapped via `Seihou.CLI.Commands`) rather than the ten
  the initial draft projected; added a Decision Log entry deferring the
  `Commands.hs` `Opts`-type extraction to a future plan.


## Outcomes & Retrospective

The four-plan decomposition delivered the convention end-to-end:
documented (EP-1), encoded in cabal (EP-2), brought into compliance
(EP-3), and mechanically enforced (EP-4). The post-EP-4 state is one
where a future contributor who adds a new pure helper to
`executable seihou`'s `other-modules` will see the
`cli-module-placement` check fail in `nix flake check` and at commit
time, with a message that names the module and points at
`docs/dev/architecture/overview.md`.

**Did the decomposition hold up?** Mostly yes. The lifecycle ordering
(state → encode → comply → enforce) survived intact. Two mid-flight
discoveries forced revisions:

- EP-2 hit the source-dir trap (shared `hs-source-dirs` made
  `other-modules` non-controlling for compilation), requiring a
  source-dir split into `src/` and `src-exe/`. This was invisible to
  EP-3's plan body but EP-3 worked around the path drift by reading
  the actual layout. EP-4's script body had the same drift and was
  adapted to read `src-exe/`.
- EP-4 found three latent violations (`Completions.{Bash,Fish,Zsh}`)
  that the EP-1/EP-2 audits had implicitly excused. The enforcement
  check upgraded a soft assumption into a hard error. This is exactly
  what the masterplan hoped for.

**Did documentation-first ordering pay off?** Yes. EP-2's cabal
restructure quotes the EP-1 doc table; EP-4's script reuses the same
four enumerated dependencies the docs name; EP-4's FAIL message points
back to the same doc section. There is one source of truth for "what
makes a module executable-only", and three places (cabal, script,
docs) that all reference it.

**Was `AgentLaunch` the only significant code restructuring?** No —
EP-2's source-dir split was a substantial restructuring not anticipated
by the masterplan. EP-3's `AgentLaunch` split was the only audit-listed
code move; EP-4 added a fourth (`Completions.{Bash,Fish,Zsh}` to the
library) that the audit missed.

**Is the build feedback loop short enough?** Yes.
- The script alone runs in well under a second.
- `nix flake check` completes in normal flake-check time and surfaces
  the `FAIL:` message verbatim in the build log.
- The pre-commit hook fires on every commit (regardless of which
  files changed) because `pass_filenames = false`; the script always
  inspects the cabal file.
- A clean checkout reports `OK: 24 modules in executable
  other-modules, all justified.`

**Follow-on initiatives uncovered by this work:**

- The deferred `Seihou.CLI.Commands` `Opts`-type extraction (recorded
  in the Decision Log) is now even more attractive: with the
  enforcement check in place, extracting `Opts` would unlock all
  eighteen handler modules to move to the library, shrinking the
  executable's `other-modules` from 24 to about six.
- The deferred `Migrate.hs` pure-surface extraction stays available;
  the enforcement check will catch any future `Migrate`-adjacent
  helper added to the wrong target.
- The script's `EXEMPT_MODULES` mechanism is the right escape valve
  but should remain rare. Today it carries two entries
  (`Paths_seihou_cli` and `Seihou.CLI.AgentLaunchExec`). A growing
  list would be a smell that the rule needs another criterion.
