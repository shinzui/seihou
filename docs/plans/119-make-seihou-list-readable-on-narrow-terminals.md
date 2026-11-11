---
id: 119
slug: make-seihou-list-readable-on-narrow-terminals
title: "Make seihou list readable on narrow terminals"
kind: exec-plan
created_at: 2026-11-11T13:34:41Z
intention: "intention_01m75czxj2ep7vd7ty4c9dgaxb"
provenance:
  created_by:
    model: "claude-opus-5-5"
    harness: "claude-code"
    at: 2026-11-11T13:34:41Z
  revisions:
    - model: "claude-opus-5-5"
      harness: "claude-code"
      at: 2026-11-11T13:47:17Z
      mode: "implement"
      note: "Implemented milestones 1-4"
---

# Make seihou list readable on narrow terminals

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

`seihou list` is how a developer finds out which modules, recipes, blueprints, and prompts
Seihou can run. Today its output is close to unreadable once a few installed artifacts carry
long descriptions. Every entry is printed as one line made of three padded columns — name,
description, source — and the description column is padded to the length of the *longest*
description in the whole list. One artifact with a 500-character description therefore pushes
every row to more than 500 characters. The terminal soft-wraps each of those rows, so the
source label `(installed: seihou-modules v0.1.0 [recipe])` of one entry lands on a line of its
own just above the *next* entry's name, and a reader cannot tell which label belongs to which
artifact. On a laptop screen or a split pane it is worse: nothing lines up at all.

After this change `seihou list` prints a scannable view that fits in 76 columns regardless of
how long any description is. Entries are grouped under one heading per kind (Modules,
Recipes, Blueprints, Prompts), sorted by name, and each entry takes exactly two lines: the
name with its source on the first, and the description — collapsed to one line and cut with
an ellipsis — indented on the second. A new `seihou list --full` flag prints every
description in full, word-wrapped under the same indentation, for when the reader wants the
whole text. Someone can see it working by running `seihou list` in a terminal 80 columns wide
and observing that no line wraps and every source sits on the same line as its name.


## Progress

- [x] Milestone 1 — one shared text-layout module: `truncateForSummary` moves out of
  `seihou-cli/src/Seihou/CLI/StatusRender.hs` into a new `Seihou.CLI.TextLayout`, which also
  gains `wrapParagraphs`; status output is byte-identical and the new module's unit tests pass.
  Done 2026-11-11: `TextLayoutSpec` (10 tests) passes; `cabal test all --enable-tests` passes
  with `StatusSpec` untouched; fourmolu, placement, and record-convention checks clean.
- [ ] Milestone 2 — the bounded list view: `seihou list` renders kind sections, name-sorted
  two-line entries, no `[kind]` source suffix, and no rendered line wider than 76 columns;
  `Seihou.CLI.List` tests assert this exact rendering.
- [ ] Milestone 3 — `seihou list --full` prints complete descriptions word-wrapped at 72
  columns under a four-space indent, with a blank line between entries.
- [ ] Milestone 4 — user documentation, command help, CHANGELOG, and ADR 0013 describe the new
  output; a manual run against the real installed artifacts confirms the result.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Render a fixed-width view (at most 76 columns) rather than querying the terminal's
  width and adapting the layout to it.
  Rationale: [ADR 0013](../adr/0013-status-is-a-bounded-summary-the-manifest-is-the-record.md)
  already rejected terminal-width-dependent rendering for `seihou status`: the same data would
  render differently in two shells and there would be no stable text for a test to assert. The
  two available ways to learn the width are also poor fits. `System.Console.ANSI.getTerminalSize`
  from `ansi-terminal` (already a dependency) learns the size by writing an escape-sequence query
  to stdout and reading the reply from stdin, which misbehaves when stdin is piped. The
  `terminal-size` package (Hackage, latest 0.3.4, uses the `TIOCGWINSZ` ioctl) would be a new
  dependency for a cosmetic gain. 76 columns fits an 80-column terminal, the conventional
  minimum, with margin; on anything narrower the two-line layout still degrades to a soft wrap
  of the description line only, which keeps each entry visually attached to its name.
  Date: 2026-11-11

- Decision: Each entry occupies two lines (name and source, then the indented description)
  instead of one line of three columns.
  Rationale: Name plus source alone is already up to about 70 columns for installed artifacts
  (`upgrade-haskell-nix2container` is 29 characters and `installed: seihou-modules v0.37.1`
  is 33). A single 76-column line would leave the description fewer than 10 characters, which is
  not worth showing. Two lines keep the description at a useful 72 characters.
  Date: 2026-11-11

- Decision: Group entries under one heading per kind and drop the `[recipe]`, `[blueprint]`,
  and `[prompt]` suffixes from source labels.
  Rationale: The heading carries the kind once instead of on every line, which shortens the
  longest source labels by up to 12 characters and makes "which recipes do I have?" answerable by
  scanning one block. Kind filters (`--recipes` and friends) keep working; they simply produce
  fewer sections.
  Date: 2026-11-11

- Decision: Bound descriptions with the existing `truncateForSummary` helper, moved into a new
  shared module, and add `--full` as the explicit opt-in to see whole descriptions.
  Rationale: ADR 0013 rule 1 requires one truncation helper rather than one per command, and
  rule 2 requires that a bounded view always offer an opt-in flag for the whole value. The flag
  is named `--full` (not `--long`) to match the "full" vocabulary of `seihou status --full-prompt`.
  Date: 2026-11-11

- Decision: Out of scope: a machine-readable `--json` mode, colourised kind headings beyond
  bold, and any change to `seihou browse` (the fzf picker).
  Rationale: The request is about human readability of `seihou list`; these are separate
  features with their own consumers.
  Date: 2026-11-11


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Seihou is a Haskell command-line tool (executable `seihou`) that scaffolds projects from
reusable *artifacts*. There are four kinds of runnable artifact: a *module* (a template with
files and variables), a *recipe* (a named composition of modules with preset variables), a
*blueprint* (an agent-driven workflow), and a *prompt* (an agent prompt). Artifacts are found
on three *search paths*: project-local (`.seihou/modules/` in the current directory), user
(`~/.config/seihou/modules/`), and installed (`~/.config/seihou/installed/`, populated by
`seihou install` from a registry repository). An installed artifact's directory holds a
`.seihou-origin.json` file recording the registry's `repoName`, the artifact `version`, and
`tags`.

The repository has two Haskell packages relevant here. `seihou-core/` holds the engine;
`Seihou.Core.Module` (in `seihou-core/src/Seihou/Core/Module.hs`) provides
`discoverAllRunnables`, which returns one `DiscoveredRunnable` per artifact with its `name`,
`description :: Maybe Text`, `kind :: RunnableKind` (`KindModule`, `KindRecipe`,
`KindBlueprint`, `KindPrompt`), `source :: ModuleSource` (`SourceProject`, `SourceUser`,
`SourceInstalled`), `dir`, `isError`, and `error`. `seihou-cli/` holds the command-line front
end, split into a library `seihou-cli-internal` (sources in `seihou-cli/src/`) and the
executable (sources in `seihou-cli/src-exe/`). New code goes in the library unless it needs
`Options.Applicative`, `Data.FileEmbed`, `GitHash`, or `Paths_seihou_cli`; this is enforced by
`nix/check-cli-module-placement.sh`.

The pieces of `seihou list`:

`seihou-cli/src-exe/Seihou/CLI/Commands.hs` defines the record `ListOpts` (around line 302:
`repo`, `tag`, `modulesOnly`, `recipesOnly`, `blueprintsOnly`, `promptsOnly`), its parser
`listParser`, and the help text `listInfo` (around lines 802–832).

`seihou-cli/src-exe/Main.hs` (around line 104) turns `ListOpts` into a `ListFilter` and calls
`handleList`.

`seihou-cli/src/Seihou/CLI/List.hs` does all the work. `handleList` discovers runnables, reads
each one's `.seihou-origin.json`, converts them to `Entry` records with
`runnableToEntryWithOrigin`, filters them with `applyFilters`, and prints
`formatListOutputEntries`. `runnableToEntryWithOrigin` builds the source label with
`sourceLabelWithOrigin` (`project`, `user`, `installed`, `installed: <repo> v<version>`) and
then appends a kind suffix (`" [recipe]"` and so on). `formatListOutputEntries` prints the
header `Available modules, recipes, blueprints, and prompts:`, one `formatEntry` line per
entry, and a summary such as `27 items found (3 sources searched)` with an optional
`[filtered: repo=…, kind=…]` suffix. `formatEntry` is where the defect lives: it pads the name
to the longest name plus three, pads the description to the longest description plus three,
and appends `(<source>)`, dimmed when colour is on. Error entries have the description
`[error: <brief reason>]`, red when colour is on. `formatListOutput` is an older entry point,
taking `DiscoveredModule` values, kept for tests. Colour helpers (`dim`, `red`, `bold`,
`useColor`) are in `seihou-cli/src/Seihou/CLI/Style.hs`.

`seihou-cli/test/Seihou/CLI/ListSpec.hs` holds the list tests (hspec specs run under tasty,
registered in `seihou-cli/test/Main.hs` and listed in the `test-suite seihou-cli-test`
`other-modules` of `seihou-cli/seihou-cli.cabal`). Several tests assert on substrings of the
old layout, and two assert that `runnableToEntryWithOrigin` produces `"project [blueprint]"`
and `"project [prompt]"`; those two will change.

`seihou-cli/src/Seihou/CLI/StatusRender.hs` (around line 475) defines
`truncateForSummary :: Int -> Text -> Text`, which collapses all whitespace runs to single
spaces and, when the result is longer than `width`, keeps `width - 1` characters, strips
trailing whitespace, and appends `…`. It is private to that module and used for the receipt
reason (`reasonWidth = 60`) and the blueprint prompt (`promptWidth = 72`). Its tests live in
`seihou-cli/test/Seihou/CLI/StatusSpec.hs`.

Relevant ADR: [ADR 0013 — `seihou status` is a bounded summary; the manifest is the
record](../adr/0013-status-is-a-bounded-summary-the-manifest-is-the-record.md). It decides that
a summary command renders unbounded free text collapsed to one line and cut at a fixed width
with a trailing ellipsis, through one shared helper (`truncateForSummary`) with a per-field
width constant; that the bounded default is unconditional and an explicit opt-in flag shows
the whole value; that the full form is delimited by indentation; and that wrapping to the
*terminal's* width is rejected because the output would vary by environment and could not be
tested. Its scope is stated as `seihou status` only. This plan applies the same rule to
`seihou list`, moves the helper (so ADR 0013's reference to its location must be updated), and
amends the ADR's scope. ADRs in this repository are plain Markdown files named
`docs/adr/NNNN-<slug>.md` with a `- Status:` and `- Date:` list under the title; there is no
OKF profile (`docs/adr/profile.dhall` does not exist), so edit them as ordinary files. No other
ADR bears on this work; [ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md)
is about diagnostic naming and is not affected.

User documentation that shows or describes `seihou list` output: `docs/cli/list.md` (the
command reference, which documents the `[recipe]` suffixes), `docs/user/getting-started.md`
(Step 10, around lines 412–440, with a sample output block, and line 479), and mentions of the
kind tags in `docs/user/registries-and-multi-module-repos.md` and
`docs/user/config-and-variables.md`. `CHANGELOG.md` at the repository root has an
`## [Unreleased]` section.


## Plan of Work


### Milestone 1 — one shared text-layout module

Create `seihou-cli/src/Seihou/CLI/TextLayout.hs` exporting `truncateForSummary` and a new
`wrapParagraphs`. Move `truncateForSummary` and its Haddock comment out of
`StatusRender.hs` unchanged, and make `StatusRender` import it from the new module (its width
constants `reasonWidth` and `promptWidth` stay in `StatusRender`, beside their only use). Add
`Seihou.CLI.TextLayout` to `exposed-modules` of `library seihou-cli-internal` in
`seihou-cli/seihou-cli.cabal`, keeping the list alphabetical.

`wrapParagraphs :: Int -> Text -> [Text]` greedily word-wraps text to lines of at most
`width` characters. It splits the input into paragraphs at blank lines (a line that is empty
after stripping), collapses whitespace inside each paragraph exactly as `truncateForSummary`
does, fills lines word by word, and separates paragraphs in the output with one empty line. A
single word longer than `width` goes on its own line unbroken (cutting a URL or path in two is
worse than an over-long line). Empty or all-whitespace input yields `[]`.

Add `seihou-cli/test/Seihou/CLI/TextLayoutSpec.hs`, register it in `seihou-cli/test/Main.hs`
and the test-suite `other-modules`, and cover: `truncateForSummary` keeps short text, cuts long
text to exactly `width` with `…`, collapses newlines; `wrapParagraphs` never returns a line
longer than `width` except a single over-long word, keeps an over-long word whole, preserves a
paragraph break as one empty line, and returns `[]` for blank input. The milestone is accepted
when the full test suite passes with `StatusSpec` untouched, which proves status output did not
change.


### Milestone 2 — the bounded list view

Rewrite the non-empty branch of `formatListOutputEntries` in `seihou-cli/src/Seihou/CLI/List.hs`
and replace `formatEntry`. Behaviour to implement:

Entries are grouped by `kind` in the fixed order Modules, Recipes, Blueprints, Prompts; a
section with no entries is omitted. Within a section entries are sorted by name (plain `Text`
ordering, which matches the lowercase names Seihou enforces). Each section starts with a
heading line `<Kind plural> (<count>)` — `Modules (2)` — bold when colour is on, followed by an
empty line, then its entries, then an empty line. After the last section comes the existing
summary line, unchanged in wording (`4 items found (3 sources searched)` plus any filter
suffix). The old `Available modules, recipes, blueprints, and prompts:` header is removed.

Each entry is two lines. The first is two spaces, the name padded with spaces to the *name
column width*, two spaces, and the source label (dimmed when colour is on, no parentheses).
The name column width is the longest name among all shown entries, capped at 32; a longer name
is not truncated, it simply pushes its source further right. The second line is four spaces
followed by `truncateForSummary descriptionWidth desc`, with `descriptionWidth = 72` defined
as a named constant in `List.hs` beside a comment pointing at ADR 0013; for an error entry this
text is red when colour is on. Neither line has trailing spaces. With the 32 cap, a first line
exceeds 76 columns only when a name plus its source label is unusually long; that is
acceptable and the description line is always at most 76.

In `runnableToEntryWithOrigin`, delete `kindSuffix` so `source` is just the
`sourceLabelWithOrigin` result. `Entry.kind` already records the kind, and the section heading
now displays it. Keep `formatListOutput` working (it feeds `toEntry` results, all modules, into
the same renderer). The empty-list branch is unchanged.

Update `seihou-cli/test/Seihou/CLI/ListSpec.hs`: change the two `runnableToEntryWithOrigin`
tests to expect `"project"`; replace the old substring tests that depended on the one-line
layout (`shows available modules header`, `shows source tag in parentheses`) with tests for the
new shape; and add a test that renders the four-entry fixture shown under Validation and
Acceptance with colour off and compares it to that exact text, plus a test that a
1,000-character description yields no line longer than 76 characters.


### Milestone 3 — `seihou list --full`

Introduce in `List.hs` a type describing how descriptions are shown:

```haskell
data DescriptionMode = BoundedDescriptions | FullDescriptions
  deriving stock (Eq, Show, Generic)
```

Thread it through: `handleList :: ListFilter -> DescriptionMode -> IO ()` and
`formatListOutputEntries :: Bool -> DescriptionMode -> [Entry] -> [Text] -> ListFilter -> Text`
(`formatListOutput` passes `BoundedDescriptions`). In `FullDescriptions` mode the description
lines are `wrapParagraphs descriptionWidth desc`, each prefixed by four spaces (an empty
paragraph-separator line stays empty, with no trailing spaces), and one empty line separates
consecutive entries within a section. Everything else is identical to the bounded mode.

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs` add a strict field `full :: !Bool` to
`ListOpts` and `<*> switch (long "full" <> help "Show complete descriptions, word-wrapped,
instead of one truncated line")` to `listParser`. In `seihou-cli/src-exe/Main.hs` pass
`if listOpts ^. #full then FullDescriptions else BoundedDescriptions` to `handleList`. Add a
`ListSpec` test rendering one entry with a description long enough to wrap and comparing it to
the `--full` sample under Validation and Acceptance.


### Milestone 4 — documentation, ADR, and a real run

Update `listInfo`'s footer in `Commands.hs` to describe the grouped, two-line layout and
`--full`, and remove the claim that entries show their kind. Rewrite the Description section of
`docs/cli/list.md` (add `--full` to the options table, replace the `[recipe]` suffix paragraph
and its examples with a short sample of the new output, and add `seihou list --full` to
Examples). Replace the sample block and the "distinguished with `[recipe]` … tags" sentence in
`docs/user/getting-started.md` Step 10, fix line 479's "(with a `[recipe]` tag)", and fix the
kind-tag mentions in `docs/user/registries-and-multi-module-repos.md` and
`docs/user/config-and-variables.md` (find them with the grep under Concrete Steps; leave any
mention that is not about `seihou list` output alone). Add a `### Changed` entry under
`## [Unreleased]` in `CHANGELOG.md`.

Amend ADR 0013: change its references to `truncateForSummary`'s location to
`seihou-cli/src/Seihou/CLI/TextLayout.hs`, and replace the sentence "This decision covers the
`status` summary." with a short paragraph, dated 2026-11-11, extending the decision to `seihou
list` (`descriptionWidth = 72`, opt-in `--full`, full form word-wrapped at a fixed width and
delimited by indentation) and citing this plan. Fixed-width word wrapping in an opt-in full
mode does not contradict the ADR's rejection of wrapping: that rejection is of wrapping the
*default* view, and of wrapping to the *terminal's* width; say so in the amendment.

Finally run the built binary against the real installed artifacts (Concrete Steps) and record
the evidence in Progress.


## Concrete Steps

All commands run from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`, inside the project's development shell
(`nix develop`, or direnv if configured) so that `cabal` and GHC are on the path.

Build and run the focused tests while working:

```bash
cabal build all
cabal test all --enable-tests --test-options='-p "TextLayout"'
cabal test all --enable-tests --test-options='-p "Seihou.CLI.List"'
cabal test all --enable-tests --test-options='-p "StatusRender"'
```

Find documentation that mentions the old kind tags:

```bash
grep -rn '\[recipe\]\|\[blueprint\]\|\[prompt\]' docs/user docs/cli seihou-cli/help
```

Run the real command at a known width (Milestone 2 onward) and check that no line is wider
than 76 columns:

```bash
SEIHOU=$(cabal list-bin seihou)
"$SEIHOU" list | perl -CSD -lne 'print "TOO WIDE: $.: $_" if length > 76'
"$SEIHOU" list --recipes
"$SEIHOU" list --full --blueprints | head -40
```

The first command should print nothing (piped stdout disables colour, and `perl -CSD` counts
characters rather than bytes, so `…` and `—` count as one column each; a first line pushed past 76 by an over-long name plus source is the one
permitted exception and should be inspected rather than treated as failure).

Before each commit run the whole suite and the repository checks:

```bash
cabal test all --enable-tests
nix flake check
```

Commit at each milestone boundary with a Conventional Commits message and both trailers, for
example:

```text
feat(list): group seihou list by kind with bounded two-line entries

ExecPlan: docs/plans/119-make-seihou-list-readable-on-narrow-terminals.md
Intention: intention_01m75czxj2ep7vd7ty4c9dgaxb
```


## Validation and Acceptance

The milestone 2 golden test renders these four entries with colour off and one searched path
list of three sources. Fixture: module `agent-gitignore`, source `installed: seihou-modules
v0.1.0`, description "Ensure .claude/, .codex/, .agents/, and CLAUDE.local.md are in
.gitignore. Shared base module for skill modules that publish into all three discovery
directories."; module `upgrade-haskell-nix2container`, source `installed: seihou-modules
v0.2.0`, description "Migrate existing nix-haskell-flake service images from dockerTools to
pinned nix2container, preserving configuration, runtime files, inputs and Seihou ownership";
recipe `haskell-cli-app`, source `installed: seihou-modules v0.1.0`, description "Bootstrap a
tested two-package Haskell CLI app (reusable core library + CLI executable) under GHC2024, with
GHC 9.12.4 as the HLS-backed default and GHC 9.14.1 as a secondary build shell."; blueprint
`exec-plan`, source `installed: agent-seihou v0.14.0`, description "Claude skill for creating,
implementing, and managing execution plans (ExecPlans) — self-contained design documents that
guide implementation of features and system changes." Pass the entries in a scrambled order so
the test also proves the sorting and grouping. The expected output is exactly:

```text
Modules (2)

  agent-gitignore                installed: seihou-modules v0.1.0
    Ensure .claude/, .codex/, .agents/, and CLAUDE.local.md are in .gitigno…
  upgrade-haskell-nix2container  installed: seihou-modules v0.2.0
    Migrate existing nix-haskell-flake service images from dockerTools to p…

Recipes (1)

  haskell-cli-app                installed: seihou-modules v0.1.0
    Bootstrap a tested two-package Haskell CLI app (reusable core library +…

Blueprints (1)

  exec-plan                      installed: agent-seihou v0.14.0
    Claude skill for creating, implementing, and managing execution plans (…

4 items found (3 sources searched)
```

The milestone 3 test renders only the `exec-plan` blueprint in `FullDescriptions` mode; its
entry lines are exactly:

```text
  exec-plan  installed: agent-seihou v0.14.0
    Claude skill for creating, implementing, and managing execution plans
    (ExecPlans) — self-contained design documents that guide implementation
    of features and system changes.
```

(The name column is only as wide as `exec-plan` because it is the sole entry.)

Behavioural acceptance, checked by hand at milestone 4 in a terminal 80 columns wide: `seihou
list` shows kind headings with counts, every source on the same line as its name, no soft-wrapped
lines, and an ellipsis on long descriptions; `seihou list --full` shows those same descriptions
in full; `seihou list --recipes --repo <some repo>` shows only a `Recipes` section and the
summary still carries `[filtered: repo=…, kind=recipe]`; `seihou status` output is unchanged.
The whole suite (`cabal test all --enable-tests`) and `nix flake check` pass.


## Idempotence and Recovery

Every step is an ordinary source edit followed by a build and test run; repeating any of them
is harmless. Nothing writes to `.seihou/`, the manifest, or the install cache — `seihou list`
only reads search paths and `.seihou-origin.json` files. If a milestone goes wrong, `git
restore` the touched files or revert that milestone's commit; milestones 1–3 each leave the
tree building and tested, so stopping after any of them is safe.


## Interfaces and Dependencies

No new package dependencies. The work uses `text`, `containers`, and the existing
`Seihou.CLI.Style` colour helpers.

At the end of the plan these interfaces exist:

In `seihou-cli/src/Seihou/CLI/TextLayout.hs` (library `seihou-cli-internal`):

```haskell
module Seihou.CLI.TextLayout (truncateForSummary, wrapParagraphs) where

truncateForSummary :: Int -> Text -> Text   -- moved verbatim from StatusRender
wrapParagraphs     :: Int -> Text -> [Text] -- greedy word wrap, paragraphs kept
```

In `seihou-cli/src/Seihou/CLI/List.hs`, newly exported `DescriptionMode (..)` and the changed
signatures:

```haskell
data DescriptionMode = BoundedDescriptions | FullDescriptions

handleList :: ListFilter -> DescriptionMode -> IO ()
formatListOutputEntries :: Bool -> DescriptionMode -> [Entry] -> [Text] -> ListFilter -> Text
```

`Entry`'s fields are unchanged; only the content of `source` changes (no kind suffix). In
`seihou-cli/src-exe/Seihou/CLI/Commands.hs`, `ListOpts` gains `full :: !Bool`, parsed from
`--full`. All new or changed records follow the repository's record conventions (strict
fields, no field prefixes, explicit `deriving stock`, `Generic`, access through `generic-lens`
labels), which `nix/check-record-conventions.sh` enforces.
