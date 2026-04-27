# Document the CLI Library-First Module-Placement Convention

MasterPlan: docs/masterplans/2-cli-library-first-convention.md

Intention: intention_01kq63sz0ced98e23qvad7zpnp

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this plan, anyone (a human contributor, a coding agent, the author returning to
the project after a break) who needs to add a new module under `seihou-cli/src/Seihou/`
can answer the question "library or executable?" in under thirty seconds by reading one
of three discoverable docs. They will see the rule plainly stated, the four specific
dependencies that justify executable-only placement, and an example of how the rule
shows up in `seihou-cli/seihou-cli.cabal`.

Why this matters: previous work on the migrations DX initiative
(`docs/masterplans/1-migrations-dx.md`) repeatedly hit the same surprise — a helper
written in an executable-only module had to be hoisted to a library module mid-plan
because the test suite could not reach it, costing roughly three hours of unscheduled
refactor work across EP-1, EP-2, and EP-4 of that masterplan. The retrospective there
explicitly called for "a repo-wide convention: CLI helpers default to the library;
executable target is for the IO shell only." This plan delivers the convention's text;
sibling plans encode the convention in the cabal layout (`docs/plans/19-restructure-cli-cabal-library-first.md`),
extract the legacy violations (`docs/plans/20-extract-trapped-cli-helpers.md`), and
arm an automated check (`docs/plans/21-enforce-cli-library-first-convention.md`).

Observable outcome: after this plan ships, a contributor can run

    grep -A 5 "CLI Module Placement" docs/dev/architecture/overview.md

and see a paragraph that names the convention; can read `CLAUDE.md` at the repo root
and see a one-paragraph summary plus a pointer to the architecture doc; and can read
`docs/dev/contributing.md` and see the same convention alongside other developer
guidance such as the project's commit-message conventions.


## Progress

- [x] Confirm the absence of pre-existing project-root convention docs (`CLAUDE.md`, `CONTRIBUTING.md`) and the structure of `docs/dev/architecture/overview.md`. (2026-04-26)
- [x] Draft the canonical "CLI Module Placement Convention" prose: the rule, the four enumerated executable-only dependencies, the cabal-comment format, the appeal procedure for adding a new exemption. (2026-04-26)
- [x] Add the section to `docs/dev/architecture/overview.md` after the existing "Project Structure" section and before any "Technology Stack" section. (2026-04-26)
- [x] Create the project-root `CLAUDE.md` containing a one-paragraph summary of the convention and a pointer (with full path) to the architecture doc section. (2026-04-26)
- [x] Create `docs/dev/contributing.md` containing the convention's full text, a section on commit-message conventions (Conventional Commits, per the user's global instructions), and a pointer to the masterplan. (2026-04-26)
- [x] Add a CHANGELOG entry under `docs/user/CHANGELOG.md` recording the convention's adoption with the date. (2026-04-26)
- [x] Verify all internal cross-references resolve (no dangling links between `architecture/overview.md`, `CLAUDE.md`, `contributing.md`, and the masterplan). (2026-04-26)


## Surprises & Discoveries

(None yet. Add to this section as work proceeds.)


## Decision Log

- Decision: Place the canonical convention text in `docs/dev/architecture/overview.md`,
  not in `CLAUDE.md` at the root.
  Rationale: The architecture doc is already the single source of truth for "how this
  project is organised". Putting the rule there keeps it near the existing "Project
  Structure" section that diagrams the library/executable split, so a reader who
  reaches the layout naturally encounters the rule. `CLAUDE.md` and
  `docs/dev/contributing.md` mirror a one-paragraph summary and link back, ensuring
  agents and contributors who land on those files first still find the rule, but a
  single edit to the architecture doc remains the way to evolve the convention.
  Date: 2026-04-26.

- Decision: Create the project-root `CLAUDE.md` even though no previous file exists.
  Rationale: Coding agents (Claude Code in particular) read `CLAUDE.md` at the repo
  root as their first orienting document. Without one, an agent considering where to
  add a new helper has nothing to consult and will pattern-match the nearest existing
  module. A short `CLAUDE.md` that enforces the convention by the second paragraph
  will catch the case the existing global CLAUDE.md cannot.
  Date: 2026-04-26.


## Outcomes & Retrospective

The convention is now documented in three discoverable places.
`docs/dev/architecture/overview.md` carries the canonical "CLI Module
Placement Convention" section between "Project Structure" and
"Technology Stack". The new project-root `CLAUDE.md` mirrors a
one-paragraph summary and points back to the canonical doc. The new
`docs/dev/contributing.md` carries the full convention plus
Conventional Commits expectations and `ExecPlan:` / `MasterPlan:` /
`Intention:` git-trailer guidance. `docs/user/CHANGELOG.md` records the
adoption.

The plan held up exactly as drafted: every step landed without
adjustment. One small refinement against the draft: the CHANGELOG used
date-headed `### YYYY-MM-DD (description)` blocks rather than the
bullet style the plan suggested, and the new entry was matched to that
style. No surprise content emerged that would require a Decision Log
update.

Downstream impact: EP-2's cabal comments and EP-4's enforcement script
can now quote or paraphrase the architecture-doc section rather than
restating the rule, fulfilling the masterplan's "single source of
truth" goal for the convention text.


## Context and Orientation

This subsection orients a reader who has only this plan and the working tree.

The repository is a multi-package Haskell (GHC2024) cabal workspace at
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`. Two cabal packages exist:
`seihou-core/` (a pure library of domain types, the engine, effects) and `seihou-cli/`
(the CLI). Inside `seihou-cli/seihou-cli.cabal` there are three targets: `library
seihou-cli-internal` (private library used by tests and intended to be used by the
executable), `executable seihou` (the user-facing binary), and `test-suite
seihou-cli-test`. Today the executable does not `build-depends` on the library and
duplicates many module names in its `other-modules`; sibling plan
`docs/plans/19-restructure-cli-cabal-library-first.md` will fix that.

The architecture doc lives at `docs/dev/architecture/overview.md`. As of 2026-04-26 it
contains sections including "Effect Stack" (around line 80), "Project Structure"
(around line 109, ending around line 208), "Technology Stack" (around line 210), and
"Key Architectural Decisions" (around line 224). The "Project Structure" section
diagrams the library/executable layout in an indented tree but does not state any
rule about where new code should live. The new "CLI Module Placement Convention"
section will sit between "Project Structure" and "Technology Stack".

There is no project-level `CLAUDE.md`, `CONTRIBUTING.md`, `DEVELOPMENT.md`, or
`HACKING.md` at the repo root or under `docs/dev/`. A user-level (global) `CLAUDE.md`
at `/Users/shinzui/.claude/CLAUDE.md` exists and contains rules about dependency
lookup, never searching `/nix/store`, and Conventional Commits — none of which
duplicate the CLI-placement rule this plan introduces. There is a `README.md` at the
project root with a brief "Project Structure" section (around lines 161-173) that
does not describe contribution conventions.

The `docs/user/CHANGELOG.md` file is the user-visible changelog; existing entries
follow a date-prefixed format that this plan should match.

Key terms used in this plan:

- **"Library-first"**: the rule that a new module should default to being added to
  `library seihou-cli-internal`'s `exposed-modules` list, and only end up in
  `executable seihou`'s `other-modules` if it imports one of four specific
  executable-only dependencies (or genuinely cannot otherwise).
- **"Executable-only dependency"**: a Haskell package or generated module that the
  library deliberately does not depend on, so any source file that imports one of
  them must live in the executable target. The four are: `optparse-applicative` (CLI
  parser), `file-embed` (compile-time `embedFile` for prompt and help text),
  `githash` (compile-time git hash for `--version`), and `Paths_seihou_cli` (Cabal's
  generated module exposing the package version).
- **"IO shell"**: the thin layer of code in the executable that parses arguments,
  reads the resulting options, calls into library functions to do the work, prints
  the outcome, and exits with an appropriate code. No business logic, no pure
  formatters, no helpers that another command might one day want.


## Plan of Work

This plan has one milestone: write the convention's text and place it in three
discoverable documents. The work is small enough that a milestone breakdown would be
overkill, but the steps are sequential because each later edit references the earlier
one.

### Milestone: Document the convention in three places

Scope: write the canonical convention in `docs/dev/architecture/overview.md`, mirror
a one-paragraph summary in a new `CLAUDE.md` at the repo root, and create
`docs/dev/contributing.md` carrying the full convention plus general contributor
guidance. Update `docs/user/CHANGELOG.md`.

What will exist at the end: three documents (one new section in an existing file,
two new files) that collectively answer "library or executable?" for every CLI
module addition.

Acceptance: a contributor (or agent) reading any of the three documents arrives at
the same rule, sees the same enumerated dependencies, and learns where to look for
the next layer of detail (the architecture doc is the canonical reference; the
masterplan at `docs/masterplans/2-cli-library-first-convention.md` is the
coordination layer; the cabal file's comments are the per-module rationale).

Commands to run:

    rg "CLI Module Placement" docs/ CLAUDE.md
    rg "library-first" docs/ CLAUDE.md

Both should return matches in all three target files.


## Concrete Steps

The following steps are written so they can be performed in order. Each edits a file
with a known structure; if your tree differs, adjust paths accordingly.

### Step 1: Verify the assumed file states

Run from the repo root (`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`):

    ls CLAUDE.md docs/dev/contributing.md 2>&1
    rg -n "## Project Structure|## Technology Stack" docs/dev/architecture/overview.md

Expected: `CLAUDE.md` and `docs/dev/contributing.md` do not exist (`ls: cannot
access ...`). The `rg` returns two matches in `overview.md` with line numbers; the
"Technology Stack" line is the insertion-after target for the new section.

If `CLAUDE.md` already exists when you start, read it first and decide whether to
extend it rather than create it. The plan's intent is one summary paragraph at the
top of the file, regardless of what else lives there.

### Step 2: Draft the canonical convention text

Compose the following content (or equivalent prose; feel free to refine the wording,
but preserve the four enumerated dependencies, the cabal-comment format, and the
appeal procedure). This text becomes the new section in
`docs/dev/architecture/overview.md`.

    ## CLI Module Placement Convention

    Code under `seihou-cli/src/Seihou/` defaults to the `seihou-cli-internal`
    library. The `seihou` executable target is reserved for the IO shell:
    `Main.hs`, command dispatchers, and the small set of modules that genuinely
    cannot live in the library.

    A module belongs in the executable target only if it imports one of these
    four Haskell-package dependencies:

    - `Options.Applicative` (the optparse-applicative CLI parser).
    - `Data.FileEmbed` (compile-time `embedFile` for prompt and help text).
    - `GitHash` (compile-time git hash exposed by `--version`).
    - `Paths_seihou_cli` (Cabal's generated module exposing the package version).

    A fifth, transitive criterion also keeps a module in the executable: it
    imports another seihou module that is itself executable-only. The most
    common case today is `Seihou.CLI.Commands` (trapped by
    `Options.Applicative`); every command-handler module that imports
    `Commands` for its `Opts` type is transitively trapped.

    Any other module — pure helpers, formatters, IO-bearing primitives that
    other commands or tests might call — belongs in the library. The library
    already exposes IO-bearing helpers (for example, `cloneRepo` and
    `installModuleDir` in `Seihou.CLI.InstallShared`); needing IO is not a
    reason to stay in the executable.

    Each entry in `executable seihou`'s `other-modules` list in
    `seihou-cli/seihou-cli.cabal` carries a one-line cabal comment naming the
    trapping dependency, for example:

        other-modules:
          Seihou.CLI.Commands         -- needs Options.Applicative
          Seihou.CLI.Help             -- needs Data.FileEmbed for embedded help
          Seihou.CLI.Version          -- needs GitHash and Paths_seihou_cli
          Seihou.CLI.Run              -- imports Seihou.CLI.Commands (transitively trapped)

    To add a new executable-only module, demonstrate the trapping dependency in
    the module's import list and add the matching one-line comment in the cabal
    file. To add an exemption (a module that legitimately stays in the
    executable despite not importing one of the four dependencies), add it to
    the `EXEMPT_MODULES` list in the enforcement script (see the path declared
    in `docs/plans/21-enforce-cli-library-first-convention.md`) with an inline
    comment naming the reason.

    Why this convention exists: the masterplan
    `docs/masterplans/1-migrations-dx.md` retrospective records that helpers
    repeatedly had to be hoisted from executable-only modules into library
    siblings during EP-1, EP-2, and EP-4, costing about three hours of
    unscheduled refactor work, because tests cannot import from the executable
    target. Defaulting to the library prevents the discovery from happening
    mid-implementation.

### Step 3: Insert the section into the architecture doc

Open `docs/dev/architecture/overview.md`. Find the line that ends the "Project
Structure" section (the closing of the indented tree, around line 208) and the line
that begins "## Technology Stack" (around line 210). Insert the entire content of
Step 2 between them, surrounded by two blank lines on each side. Do not modify the
"Project Structure" or "Technology Stack" sections.

After saving, verify with:

    rg -n "^## " docs/dev/architecture/overview.md | head -20

The output should now show "## CLI Module Placement Convention" between "## Project
Structure" and "## Technology Stack".

### Step 4: Create the project-root CLAUDE.md

Create `CLAUDE.md` at the repo root with the following structure:

    # Seihou — Project CLAUDE.md

    This file orients coding agents working in the seihou repository. Combine
    these notes with any global guidance in your user-level `CLAUDE.md`.

    ## CLI Module Placement (library-first)

    New code under `seihou-cli/src/Seihou/` goes in the
    `seihou-cli-internal` library by default. The `seihou` executable target
    is reserved for `Main.hs`, command dispatchers, and modules that
    genuinely need one of these four dependencies:

    - `Options.Applicative`
    - `Data.FileEmbed`
    - `GitHash`
    - `Paths_seihou_cli`

    Full convention and rationale: `docs/dev/architecture/overview.md`,
    section "CLI Module Placement Convention". Coordinating masterplan:
    `docs/masterplans/2-cli-library-first-convention.md`.

    ## Commit messages

    Conventional Commits, per the global guidance.

    ## Where to put plans

    ExecPlans live in `docs/plans/<N>-<slug>.md`. MasterPlans live in
    `docs/masterplans/<N>-<slug>.md`. See the skills under `.claude/skills/`
    for the authoring protocol.

The "Where to put plans" and "Commit messages" stubs are intentional: the file is
small but discoverable, and future contributors can extend it without re-deriving
the structure.

### Step 5: Create docs/dev/contributing.md

Create `docs/dev/contributing.md` with the following structure:

    # Contributing to Seihou

    This document is the developer-facing guide for the seihou project. The
    user-facing CHANGELOG is at `docs/user/CHANGELOG.md`; the architecture
    overview is at `docs/dev/architecture/overview.md`; the v1 milestones
    roadmap is at `docs/dev/roadmap/v1-milestones.md`.

    ## CLI Module Placement Convention

    [Paste the full text from Step 2 here, identical to the architecture-doc
    section. Yes, this is intentional duplication: the architecture doc is
    the canonical home for the convention, and this file mirrors it so a
    contributor reading "how do I contribute?" sees the rule without an
    extra hop.]

    ## Commit Messages

    Use Conventional Commits
    (https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`,
    `refactor:`, `test:`, `chore:`, optionally with a scope (for example,
    `feat(parser): ...`) and a `!` or `BREAKING CHANGE:` footer for
    breaking changes.

    Commits made under an ExecPlan must include an `ExecPlan:` git trailer
    (see `.claude/skills/exec-plan/SKILL.md`). Commits under a MasterPlan
    must additionally include a `MasterPlan:` trailer (see
    `.claude/skills/master-plan/SKILL.md`). When an Intention ID is in
    play, also add an `Intention:` trailer.

    ## Plans and Master Plans

    ExecPlans live in `docs/plans/<N>-<slug>.md`. MasterPlans live in
    `docs/masterplans/<N>-<slug>.md`. Each ExecPlan is a self-contained,
    living document — a contributor with only the plan and the working tree
    must be able to implement the feature end-to-end. The full
    specification is in `.claude/skills/exec-plan/PLANS.md`; the masterplan
    specification is in `.claude/skills/master-plan/MASTERPLAN.md`.

    ## Tests

    The CLI test suite lives at `seihou-cli/test/`. Run it with:

        cabal test seihou-cli-test

    A new pure helper added to the library should usually carry a
    `Spec.hs` file alongside the existing ones (for example,
    `seihou-cli/test/Seihou/CLI/RemoteVersionSpec.hs` is a model for a
    helper that exercises a single library function).

The "Paste the full text from Step 2 here" instruction is literal: the text in the
architecture doc and in this file should match, so a future search for "library-first"
finds both. If a future revision diverges them, treat the architecture doc as
canonical.

### Step 6: Add a CHANGELOG entry

Open `docs/user/CHANGELOG.md`. Locate the most recent entry to confirm the existing
date-prefixed format. Add a new entry at the top of the file's chronological list
with the format the file already uses, with content along these lines:

    - 2026-04-26: Documented the CLI library-first module-placement
      convention in `docs/dev/architecture/overview.md` (canonical),
      `CLAUDE.md` (quick reference), and `docs/dev/contributing.md`. New
      modules under `seihou-cli/src/Seihou/` default to the
      `seihou-cli-internal` library.

If the existing CHANGELOG uses a different bullet style or grouping (e.g., release
sections), match that style instead.

### Step 7: Verify cross-references

Run from the repo root:

    rg -n "CLI Module Placement|library-first" docs/dev/architecture/overview.md CLAUDE.md docs/dev/contributing.md docs/user/CHANGELOG.md

Expected: matches in all four files. The architecture doc match should be the
section heading and the body. The other matches confirm the cross-references
resolve.

Run also:

    rg -n "docs/dev/architecture/overview.md" CLAUDE.md docs/dev/contributing.md

Expected: at least one match in each, confirming the pointers from `CLAUDE.md` and
`contributing.md` back to the canonical doc are present.

### Step 8: Commit

Stage all four files and commit with a Conventional Commits message and the
required trailers (the `Intention:` trailer is mandatory for this masterplan; see
its frontmatter):

    git add docs/dev/architecture/overview.md CLAUDE.md docs/dev/contributing.md docs/user/CHANGELOG.md
    git commit -m "$(cat <<'EOF'
    docs(cli): document the library-first module-placement convention

    Adds the canonical "CLI Module Placement Convention" section to
    docs/dev/architecture/overview.md and mirrors the rule into a new
    project-root CLAUDE.md and a new docs/dev/contributing.md. Records the
    rule's adoption in docs/user/CHANGELOG.md.

    MasterPlan: docs/masterplans/2-cli-library-first-convention.md
    ExecPlan: docs/plans/18-document-cli-library-first-convention.md
    Intention: intention_01kq63sz0ced98e23qvad7zpnp
    EOF
    )"


## Validation and Acceptance

Acceptance is observable: the convention is discoverable from three reasonable
landing pages (architecture doc, CLAUDE.md, contributing doc) and the four files
agree on the rule.

To verify after the commit:

    rg -c "library-first|CLI Module Placement" docs/dev/architecture/overview.md CLAUDE.md docs/dev/contributing.md

Expected: each file returns at least 1.

Manually re-read the three documents in this order to confirm the story flows:

1. `CLAUDE.md` (a coding agent's first stop) — should resolve the rule in the
   second paragraph and point a reader to the architecture doc for detail.
2. `docs/dev/architecture/overview.md` "CLI Module Placement Convention"
   (canonical) — should fully state the rule, name the four dependencies, show the
   cabal-comment format, and explain why the convention exists.
3. `docs/dev/contributing.md` — should mirror the convention and add the
   commit-message and plan-authoring guidance.

Behavioural acceptance for downstream plans: when EP-2
(`docs/plans/19-restructure-cli-cabal-library-first.md`) edits
`seihou-cli/seihou-cli.cabal`, its commit comments quote phrases from the
architecture-doc section. When EP-4
(`docs/plans/21-enforce-cli-library-first-convention.md`) writes the enforcement
script, the script's matchable list is exactly the four dependencies named here.


## Idempotence and Recovery

Re-running this plan after a partial failure is safe: each step edits a distinct
file, so a partial state is at worst "two of three files updated". To resume,
re-read the three target files and continue from the missing one. The CHANGELOG
entry should be added once; if you find an earlier draft of it, edit rather than
duplicate.

If the architecture doc has been edited between the time this plan was authored
and the time it is implemented (e.g., a new section was added that displaces
"Project Structure"'s line numbers), use `rg -n "^## "` to find the current
boundaries and insert the new section in the same logical position (after Project
Structure, before Technology Stack). The exact line numbers are not load-bearing;
the section ordering is.


## Interfaces and Dependencies

This plan touches only Markdown files; no Haskell modules, no cabal targets, no
test files.

Files created:

- `CLAUDE.md` (project root, ~30 lines).
- `docs/dev/contributing.md` (~80 lines).

Files edited:

- `docs/dev/architecture/overview.md`: insert one new section (~40 lines)
  between existing "Project Structure" and "Technology Stack" sections.
- `docs/user/CHANGELOG.md`: prepend one entry to the chronological list.

No new dependencies. No test changes. No build-system changes.
