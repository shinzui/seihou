---
id: 91
slug: truncate-the-blueprint-prompt-in-status-output
title: "Truncate the blueprint prompt in status output"
kind: exec-plan
created_at: 2026-09-16T13:22:48Z
intention: "intention_01m2n64h7bevtr2xxfcn81f49b"
provenance:
  created_by:
    model: "claude-opus-5[1m]"
    harness: "claude-code"
    at: 2026-09-16T13:22:48Z
  revisions:
    - model: "claude-opus-5[1m]"
      harness: "claude-code"
      at: 2026-09-16T15:58:37Z
      mode: "implement"
      note: "Implementing all three milestones; ADR renumbered 0012 -> 0013"
---

# Truncate the blueprint prompt in status output

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

`seihou status` is the command a developer runs to see, at a glance, what Seihou has
done to the project they are standing in: which recipe or blueprint produced it, which
modules are applied and at what versions, which generated files they have since edited,
and what they should run next. It earns its keep by fitting on a screen.

Today one line can destroy that. When a project was set up with `seihou agent run
<blueprint> "<prompt>"`, the prompt the developer typed is recorded in the manifest and
then echoed back by `seihou status` in full, with no length limit. A prompt for a real
blueprint run is rarely one sentence — it is several paragraphs of pre-established
facts, per-file caveats and "do not commit" instructions, because that is the context
the agent needs. So the summary opens with a dozen lines of quoted prose, and everything
a developer actually came to read gets pushed off the top of the terminal.

After this change, running `seihou status` in such a project prints the prompt as one
bounded line ending in an ellipsis, so the block stays three lines tall no matter how
long the prompt was, and the rest of the status is visible without scrolling. Nothing is
lost: the whole prompt stays in `.seihou/manifest.json`, and anyone who wants to read it
in the terminal runs `seihou status --full-prompt`, a new flag added by this plan, which
prints it verbatim.

You can see the difference without writing a line of Haskell first. In a project whose
`.seihou/manifest.json` records a blueprint with a long `userPrompt`, `seihou status`
today prints something like this (abridged):

```text
Blueprint: fix-nix-haskell-flake-customizations (applied 2026-09-13 09:41 UTC)
  Baseline: (none declared)
  Prompt: "Upgrade this repository to nix-haskell-flake 0.24.0. The flake already
pins baikai 0.7, so do not re-pin it. flake.nix carries three local customizations
that must survive the upgrade: the haskell-overlay import, the okf-core Hackage pin,
and the dontHaddock wrapper on seihou-okf-extension. Do not commit anything; leave
the tree dirty for review. If a customization cannot be preserved, stop and say so
rather than dropping it. ..."
```

After this change the same project prints:

```text
Blueprint: fix-nix-haskell-flake-customizations (applied 2026-09-13 09:41 UTC)
  Baseline: (none declared)
  Prompt: "Upgrade this repository to nix-haskell-flake 0.24.0. The flake already…"
```

This plan implements improvement request IR-7, filed at
[`docs/improvement-requests/truncate-the-blueprint-prompt-in-status-output.md`](../improvement-requests/truncate-the-blueprint-prompt-in-status-output.md).


## Progress

- [x] Milestone 1 — shared truncation helper and a bounded `Prompt:` line (2026-09-16)
  - [x] Hoist `truncateReason` / `reasonWidth` out of `formatBlueprintMigrations`'s
        `where` clause into module-level `truncateForSummary` and `reasonWidth` in
        `seihou-cli/src/Seihou/CLI/StatusRender.hs`
  - [x] Add module-level `promptWidth = 72`
  - [x] Route `blueprintSection`'s `Prompt:` line through `truncateForSummary promptWidth`
  - [x] Add tests to `seihou-cli/test/Seihou/CLI/StatusSpec.hs` covering a long prompt,
        a short multi-line prompt, and a short prompt left alone; confirm the
        pre-existing reason-truncation test passes unmodified — all 23
        `StatusRender` tests pass, the 5 pre-existing blueprint-provenance tests
        and the long-reason receipt test untouched
  - [x] `cabal test all --enable-tests` green; commit `e104f80`
- [x] Milestone 2 — `seihou status --full-prompt` (2026-09-16)
  - [x] Add `PromptDisplay` and `formatStatusWith` to
        `seihou-cli/src/Seihou/CLI/StatusRender.hs`; redefine `formatStatus` in terms of it
  - [x] Add `statusFullPrompt` to `StatusOpts` and a `--full-prompt` switch to
        `statusParser` in `seihou-cli/src-exe/Seihou/CLI/Commands.hs`
  - [x] Thread the flag through `handleStatus` in
        `seihou-cli/src-exe/Seihou/CLI/Status.hs`
  - [x] Add tests for `PromptFull` rendering — 10 blueprint-provenance tests pass
  - [x] End-to-end walkthrough against a scratch manifest: bounded line by
        default, whole prompt under `--full-prompt`, flag listed in `--help`,
        manifest hash unchanged across a `status` run
  - [x] `cabal test all --enable-tests` green; `cabal build all` clean; commit `a018bb9`
- [x] Milestone 3 — documentation, ADR, and IR bookkeeping (2026-09-16)
  - [x] Update `docs/cli/status.md` (options table and the Blueprint bullet)
  - [x] Add a user-facing entry under `## Unreleased` in `docs/user/CHANGELOG.md`
  - [x] Correct the `seihou status` example in
        `docs/dev/design/proposed/blueprints.md`
  - [x] Write `docs/adr/0013-status-is-a-bounded-summary-the-manifest-is-the-record.md`
  - [x] Mark IR-7 accepted: frontmatter `status`, `targetPlan`, `timestamp`, and a
        `## Status` section; append an `okf log add` entry to
        `docs/improvement-requests/log.md`
  - [x] `okf validate` output byte-identical to the pre-plan baseline
  - [x] `nix flake check` green; commit


## Surprises & Discoveries

Observations made while researching this plan; add to this section during
implementation with evidence.

- **The documented test command does not work as written.**
  `docs/dev/contributing.md` says to run `cabal test seihou-cli-test`. On this
  checkout that fails before compiling anything:

  ```text
  $ cabal test seihou-cli-test
  Resolving dependencies...
  Error: [Cabal-7043]
  Cannot test the test suite 'seihou-cli-test' because the solver did not find a
  plan that included the test suites for seihou-cli-0.8.0.0.
  ```

  `cabal.project` does not enable tests, so the solver plans without them. The
  command that works is `cabal test all --enable-tests`, which is what this plan
  uses throughout. Verified 2026-09-16 with cabal-install 3.16.1.0 and GHC 9.12.4.

- **`okf validate` on the improvement-request bundle already exits 1.** Every
  existing improvement request is missing the profile-*recommended* `reviews`
  field, so the validator reports eight advisory lines and exits non-zero before
  this plan changes anything:

  ```text
  $ okf validate docs/improvement-requests --strict \
      --profile docs/improvement-requests/profile.dhall --profile-enforce --log-enforce
  profile: add-a-not-applicable-outcome-for-blueprint-migration-edges: missing profile-recommended field: reviews (...)
  ... eight such lines ...
  $ echo $?
  1
  ```

  Acceptance for the IR bookkeeping in Milestone 3 is therefore "no *new*
  diagnostic lines", not "exit 0". Do not try to make it exit 0; fixing the
  corpus-wide missing `reviews` field is separate work.

- **ADR 0012 was taken before this plan started work.** The plan's Context and
  Orientation says "the highest allocated number today is 0011, so a new record
  takes 0012". Between the plan being written and implementation beginning,
  commit `d24126c` landed
  `docs/adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md`:

  ```text
  $ ls docs/adr/ | tail -2
  0011-a-migration-receipt-asserts-a-claim-about-the-project.md
  0012-an-additive-co-write-is-not-a-shared-path-conflict.md
  ```

  This plan's ADR is therefore **0013**, not 0012. The `truncateForSummary`
  Haddock written in Milestone 1 already points at 0013.

- **The full form indents blank lines too.** `renderPrompt PromptFull` maps
  `("    " <>)` over every line, so a paragraph break inside the prompt renders
  as a line of four spaces rather than a truly empty line:

  ```text
    Prompt:
      Upgrade this repository to nix-haskell-flake 0.24.0.
  ....
      The flake already pins baikai 0.7, so do not re-pin it. ...
  ```

  (the `....` marks four trailing spaces). This is left as-is deliberately: the
  Decision Log's reasoning is that indentation, not quoting, delimits the value,
  and an indented blank line is inside the value while an unindented one would be
  ambiguous. The whitespace is invisible in a terminal and does not affect any
  assertion.

- **`okf log add` warns `concept not found: IR-7` but writes the entry correctly.**

  ```text
  $ okf log add docs/improvement-requests IR-7 --kind Update -m "..."
  log: warning: concept not found: IR-7
  Wrote log.md for 2026-09-16
  ```

  The bundle has no `concepts/` directory — improvement requests are plain
  documents keyed by slug, and `requestId` is a frontmatter field rather than a
  concept key — so the resolver has nothing to match `IR-7` against. It is
  advisory: exit status is 0, one line was appended to
  `docs/improvement-requests/log.md` in the same shape as every existing entry,
  and `okf validate --log-enforce` afterwards reports exactly the same eight
  lines as the pre-plan baseline, byte for byte. The same warning applies to the
  IR-8 entries already in the log.

- **GHC is 9.12.4 on this checkout**, not the 9.12.2 that the repository's
  `CLAUDE.md` states. Nothing in this plan depends on the difference; noted so a
  reader is not surprised by the version string in build output.


## Decision Log

- Decision: The truncation width for the prompt is a module-level constant
  `promptWidth = 72`, separate from the existing `reasonWidth = 60`.
  Rationale: IR-7 asks for a width "somewhat wider than 60 … given it is a whole
  instruction, not a reason clause", and leaves the exact number to the author. 72
  renders as `  Prompt: "` + 72 characters + `"` = 84 columns. That is wider than a
  conventional 80-column terminal by four characters but comfortably inside the
  100-plus columns a modern terminal has, and it is a large improvement on the
  dozen wrapped lines it replaces. Two constants rather than one shared width,
  because the two values genuinely differ in kind: a reason is a clause appended to
  an already-long receipt line, a prompt is a whole instruction on a line of its own.
  Date: 2026-09-16

- Decision: The `--full-prompt` escape hatch is in scope, as a second milestone.
  Rationale: IR-7 lists it as optional. Without it, the only way to read the full
  prompt is to open `.seihou/manifest.json` and find the `userPrompt` key by hand,
  which is exactly the kind of "the tool knows but will not tell you" gap that makes
  a truncation feel like data loss. The user confirmed this scope when the plan was
  commissioned. It is a separate milestone so that Milestone 1 can ship the fix on
  its own if Milestone 2 runs into trouble.
  Date: 2026-09-16

- Decision: The flag is spelled `--full-prompt`, with no short form.
  Rationale: IR-7 suggests "`--full` / verbose". A bare `--full` on `status` does not
  say full *what* — `status` renders six blocks and truncates one value. `-u` is
  already taken by `--check-updates` on this command, and `-v` is `--verbose` on six
  other commands in `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, where it means
  "show progress messages" rather than "show more of a stored value"; reusing it here
  would mean two different things under one letter.
  Date: 2026-09-16

- Decision: `formatStatus` keeps its current five-argument signature and delegates to
  a new `formatStatusWith :: PromptDisplay -> ...`, rather than growing a sixth
  parameter or being replaced by an options record.
  Rationale: `formatStatus` is called from 18 places in
  `seihou-cli/test/Seihou/CLI/StatusSpec.hs` and one place in
  `seihou-cli/src-exe/Seihou/CLI/Status.hs`. Adding a sixth positional argument would
  put a second `Bool` next to the existing `color :: Bool`, which is easy to
  transpose silently, and would force 18 mechanical test edits that obscure the four
  real ones. Keeping `formatStatus` as the default-behaviour entry point means the
  existing 18 call sites go on asserting the *default* rendering, which is precisely
  what this plan changes and therefore what most needs regression cover.
  Date: 2026-09-16

- Decision: `PromptDisplay` is a two-constructor data type (`PromptTruncated`,
  `PromptFull`), not a `Bool`.
  Rationale: `formatStatusWith PromptFull False manifest …` reads correctly at the
  call site; `formatStatusWith True False manifest …` does not, and the compiler
  cannot tell the two `Bool`s apart.
  Date: 2026-09-16

- Decision: In full mode the prompt is rendered as a bare `  Prompt:` header
  followed by the stored prompt's own lines, each indented four spaces — not as a
  quoted string spanning lines.
  Rationale: A quoted multi-line value is ambiguous, because a prompt may itself
  contain a `"` and nothing escapes it today, so a reader cannot tell where the value
  ends. Indentation delimits it unambiguously and preserves the prompt's paragraph
  structure, which is the reason someone asked for it in full. It is also total: no
  `head`/`last` on a possibly-empty list of lines.
  Date: 2026-09-16

- Decision: `truncateForSummary` strips a trailing space before appending the
  ellipsis, which the current `truncateReason` does not.
  Rationale: The cut lands wherever the width falls, which for realistic text is often
  mid-gap, and `"… The flake already …"` reads like an elision inside the sentence
  rather than a cut at the end of it. This is a deliberate, cosmetic change to the
  *existing* reason rendering as well as the new prompt rendering, and it is safe: the
  pre-existing test at `seihou-cli/test/Seihou/CLI/StatusSpec.hs` line 253 uses
  `T.replicate 200 "x"`, which contains no spaces, so it is unaffected and still pins
  the arithmetic. The consequence for the Haddock contract is that the result is now
  "at most `width` characters" rather than "exactly `width` when cut".
  Date: 2026-09-16

- Decision: The long-prompt test asserts `promptLines \`shouldBe\` [<exact line>]`
  rather than the plan's `length promptLines \`shouldBe\` 1` plus
  `head promptLines \`shouldBe\` <exact line>`.
  Rationale: The list equality asserts both properties at once and is total. GHC
  9.12 warns on `head` under `-Wx-partial` (there is an existing such warning at
  `seihou-cli/test/Seihou/CLI/StatusSpec.hs` line 297), and there was no reason to
  add a second one.
  Date: 2026-09-16

- Decision: The end-to-end walkthrough used the session scratchpad directory
  rather than `/tmp/seihou-ir7`.
  Rationale: The harness designates a session-specific scratchpad and asks that it
  be used in place of system temp directories. The manifest content, commands and
  expected output were otherwise exactly as the plan specifies.
  Date: 2026-09-16

- Decision: This plan writes a new ADR (0013) rather than only citing existing ones.
  Rationale: The rule being applied — the summary view is bounded, the manifest is
  the record — is now on its second free-text field and there will be a third. It is
  currently recorded only as a code comment inside one `where` clause. Writing it
  down means the next person adding a free-text field to `status` does not have to
  re-derive it or re-litigate it. See "Milestone 3" for the exact content.
  Date: 2026-09-16


## Outcomes & Retrospective

All three milestones landed on `master` on 2026-09-16, in the order planned, each
leaving the tree green.

**What a user can now do that they could not before.** In a project whose
`.seihou/manifest.json` records a blueprint with a multi-paragraph `userPrompt`,
`seihou status` prints a `Blueprint:` block exactly three lines tall, the third
being a single bounded `Prompt:` line ending in an ellipsis. Verified against the
real binary with a scratch manifest carrying a 232-character three-paragraph
prompt:

```text
Blueprint: fix-nix-haskell-flake-customizations (applied 2026-09-13 09:41 UTC)
  Baseline: (none declared)
  Prompt: "Upgrade this repository to nix-haskell-flake 0.24.0. The flake already…"
```

`seihou status --full-prompt` on the same project prints all three paragraphs,
indented under a bare `  Prompt:` header, with no ellipsis, and
`seihou status --help` lists the flag. The manifest hash was identical before and
after a `status` run, confirming nothing was lost and nothing was written.

**The plan held up almost exactly.** Every file it named existed at the path it
gave, every signature it specified compiled as written, and the expected
truncated line it derived by hand — 71 characters between the quotes, an
83-column line — matched the implementation on the first run. The pre-existing
tests it identified as the real regression guards all passed unmodified: the five
blueprint-provenance tests and, critically, the long-reason receipt test whose
space-free fixture pins the cut arithmetic through the hoist.

Three things the plan did not anticipate, all recorded in Surprises &
Discoveries: ADR 0012 was allocated to unrelated work between the plan being
written and implementation starting, so this plan's record is 0013; `okf log add`
emits a spurious `concept not found` warning that does not affect the written
entry; and the full-prompt form indents blank lines, which was left as-is for the
reason in the Decision Log.

**What the next person should take from this.** The defect was not that someone
forgot to bound the prompt — it was that the rule bounding the *reason* lived as
a comment inside one `where` clause, invisible to anyone adding a second free-text
field. Hoisting the helper to module level fixed the immediate bug; ADR 0013 is
what stops the third field from repeating it. The shared helper is the durable
part, not the two width constants.


## Context and Orientation

### The shape of the repository

Seihou is a Haskell project-scaffolding tool built as a multi-package Cabal
workspace. Three packages matter to this plan, and only two are touched:

- `seihou-core/` — the engine library. **Not touched by this plan.**
- `seihou-cli/src/` — a library called `seihou-cli-internal`. Pure helpers and
  renderers live here.
- `seihou-cli/src-exe/` — the `seihou` executable. Only `Main.hs`, the
  command dispatchers, and modules that need `Options.Applicative`,
  `Data.FileEmbed`, `GitHash` or `Paths_seihou_cli` live here.

That split is a rule enforced by a script, `nix/check-cli-module-placement.sh`,
which runs inside `nix flake check` and in the repository's pre-commit hook. It
matters here because this plan edits files on both sides of the line and must keep
each edit where it belongs: rendering logic goes in `seihou-cli/src/`, and
command-line option parsing (which needs `Options.Applicative`) goes in
`seihou-cli/src-exe/`. Do not move a function across that boundary to make
something convenient.

### The four files this plan changes in code

**`seihou-cli/src/Seihou/CLI/StatusRender.hs`** turns a manifest into the text that
`seihou status` prints. Its entry point today is:

```haskell
formatStatus ::
  Bool ->
  Manifest ->
  [TrackedFile] ->
  Maybe [OutdatedEntry] ->
  [(ModuleName, MigrationPlan)] ->
  Text
```

The leading `Bool` is `color`: pass `False` for plain text, which is what the test
suite does. `formatStatus` concatenates a list of section renderers, two of which
this plan touches.

The first is `blueprintSection`, which renders the `Blueprint:` provenance block when
the manifest records one. Its current prompt handling is the defect IR-7 describes:

```haskell
        promptLines = case ab ^. #userPrompt of
          Nothing -> []
          Just p -> ["  Prompt: \"" <> p <> "\""]
```

There is no length bound. Whatever text is in `userPrompt` is emitted verbatim,
newlines and all.

The second is `formatBlueprintMigrations`, forty lines below, which renders one line
per recorded blueprint-migration receipt. It already solved this exact problem for a
different free-text field — a receipt's "not applicable" reason — inside its `where`
clause:

```haskell
    -- `seihou status` is a scannable summary, so a long reason is truncated
    -- rather than wrapped; the manifest keeps the whole of it.
    renderReason MigrationApplied = ""
    renderReason (MigrationNotApplicable reason) = " -- " <> truncateReason reason

    truncateReason reason
      | T.length oneLine <= reasonWidth = oneLine
      | otherwise = T.take (reasonWidth - 1) oneLine <> "…"
      where
        oneLine = T.unwords (T.words reason)

    reasonWidth = 60
```

Read that carefully, because the plan reuses its exact semantics. `T.words` splits on
any run of whitespace and discards it; `T.unwords` rejoins with single spaces. So a
value containing newlines, tabs or double spaces collapses to one line first, and only
then is it measured and cut. When it is cut, `width - 1` characters are kept and the
last character of the budget is spent on a single-character ellipsis `…` (U+2026, one
`Char` in a `Text`), so the result is never longer than `width`.

**`seihou-cli/test/Seihou/CLI/StatusSpec.hs`** is the test module for that renderer.
It builds `Manifest` fixtures and asserts on substrings of the rendered text. It has a
helper `mkBlueprint :: Text -> Maybe Text -> [Text] -> Bool -> Maybe Text ->
AppliedBlueprint` whose last argument is the prompt, and a helper
`withManifestBlueprint :: Maybe AppliedBlueprint -> Manifest -> Manifest`. Both are
reused unchanged by this plan. The existing blueprint tests live in a
`describe "blueprint provenance"` block; the new ones go beside them. The module is
registered in two places, both of which already list `Seihou.CLI.StatusSpec`, so no
build-file change is needed: `seihou-cli/seihou-cli.cabal` line 267, and
`seihou-cli/test/Main.hs`, which imports it and lists `StatusSpec.tests` in the tasty
tree.

**`seihou-cli/src-exe/Seihou/CLI/Commands.hs`** holds every `Options.Applicative`
parser. The record for this command is at line 300:

```haskell
data StatusOpts = StatusOpts
  { statusCheckUpdates :: !Bool
  }
  deriving stock (Eq, Show, Generic)
```

and its parser at line 716:

```haskell
statusParser :: Parser Command
statusParser =
  fmap Status $
    StatusOpts
      <$> switch
        ( long "check-updates"
            <> short 'u'
            <> help "Check installed modules for available updates (requires network)"
        )
```

`statusInfo`, just above it, carries the `--help` footer prose.

**`seihou-cli/src-exe/Seihou/CLI/Status.hs`** is the command handler. It reads the
manifest, computes tracked-file statuses, optionally checks for updates, and then
calls the renderer:

```haskell
      TIO.putStr (formatStatus colorEnabled manifest tracked mEntries pendings)
```

`StatusOpts` is constructed in exactly one place (`statusParser`) and consumed in
exactly one place (`handleStatus`), which is why adding a field to it is cheap.

### Terms used in this plan

- **Manifest** — `.seihou/manifest.json`, a JSON file inside the project that records
  everything Seihou has applied there. It is checked into git alongside the code.
- **Blueprint** — an agent-driven artifact. `seihou agent run <blueprint> "<prompt>"`
  applies a baseline of ordinary modules and then hands an agent the blueprint's
  instructions plus the developer's positional `<prompt>`.
- **`userPrompt`** — the field of the manifest's `blueprint` record that stores that
  positional prompt. It is `Maybe Text`: `Nothing` when no positional argument was
  given. Defined in `seihou-core/src/Seihou/Core/Types.hs` (the `AppliedBlueprint`
  record, around line 673), encoded and decoded in
  `seihou-core/src/Seihou/Manifest/Types.hs` (lines 397 and 409), and written by
  `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` line 302. **This plan changes none of
  those files.** That is the point: the stored prompt is correct and stays whole.
- **Migration receipt** — a record in the manifest saying a blueprint-migration edge
  has been dealt with. A receipt whose outcome is "not applicable" carries a
  free-text reason, which is the value `truncateReason` already bounds.
- **Improvement request (IR)** — a numbered request filed against Seihou by a project
  that consumes it, living in `docs/improvement-requests/` as an OKF bundle (a
  directory of Markdown files with YAML frontmatter, validated against a Dhall
  profile by the `okf` CLI). IR-7 is this plan's motivation.

### Relevant ADRs

Architecture Decision Records live in `docs/adr/` as plain Markdown files named
`NNNN-slug.md`, each opening with `# ADR NNNN — <title>` followed by `- Status:` and
`- Date:` lines. This directory is **not** an OKF bundle — `mori.dhall` declares only
`docs/improvement-requests` under `okfBundles`, and `docs/adr/` has no `profile.dhall`
— so the local filesystem convention is authoritative and no `okf` command applies to
it. The highest allocated number was 0011 when this plan was written; 0012 was
allocated to an unrelated record before implementation began, so this plan's
record is 0013 (see Surprises & Discoveries).

Two existing records bear on this work:

- [`docs/adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md`](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md)
  establishes that the manifest describes the project rather than the machine that ran
  the command, and is checked into git. That is why "keep the whole prompt in the
  manifest and shorten only the rendering" is the right split: the manifest is a
  durable, reviewable artifact, and truncating it would destroy information a reviewer
  may want.
- [`docs/adr/0004-the-manifest-is-the-only-record-of-applied-state.md`](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md)
  states that `.seihou/manifest.json` is the single source of truth for what has been
  applied, with no second lockfile-style file beside it. It follows that any view
  `seihou status` renders is exactly that — a view — and is free to be lossy, because
  the authoritative copy is one file away. This plan makes that implication explicit
  in a new ADR 0013.

[`docs/adr/0010-generated-documentation-is-checked-before-it-is-written.md`](../adr/0010-generated-documentation-is-checked-before-it-is-written.md)
sounds relevant from its title but is not: it governs the OKF documentation bundles
that `seihou-okf-extension docs` generates from a registry, not the hand-written pages
under `docs/cli/`. No other ADR in the corpus concerns terminal rendering.


## Plan of Work

### Milestone 1 — one shared truncation helper, one bounded `Prompt:` line

The point of this milestone is that after it, no project can flood `seihou status`
with a long prompt, and the two places that shorten free text for the summary share
one function, so they cannot drift apart. Nothing about the command line changes yet.

All the work is in `seihou-cli/src/Seihou/CLI/StatusRender.hs` and its spec.

Start by hoisting the existing helper out of `formatBlueprintMigrations`'s `where`
clause to module level, generalised over the width and with the one cosmetic change
recorded in the Decision Log (a cut that lands on a space no longer leaves that space
sitting before the ellipsis).
Delete `truncateReason` and `reasonWidth` from that `where` clause entirely — leaving
a `reasonWidth` behind would shadow the new top-level binding and GHC will warn. Add,
near the bottom of the module beside the other small helpers such as `applyColor`:

```haskell
-- | Collapse every run of internal whitespace to a single space and cut the
-- result to @width@ characters, marking a cut with a trailing ellipsis.
--
-- @seihou status@ is a scannable summary, and the manifest is the record (see
-- docs/adr/0013-status-is-a-bounded-summary-the-manifest-is-the-record.md). Two
-- values the summary renders are unbounded free text kept in full in
-- @.seihou/manifest.json@ — a migration receipt's not-applicable reason and a
-- blueprint's stored user prompt — and this is the single place that decides how
-- much of such a value the summary shows, so the two cannot drift apart.
--
-- The result is never longer than @width@: a cut keeps at most @width - 1@
-- characters and spends the last on the ellipsis. A cut that lands mid-gap has its
-- trailing space stripped, so the output reads @\"... already…\"@ rather than
-- @\"... already …\"@.
truncateForSummary :: Int -> Text -> Text
truncateForSummary width text
  | T.length oneLine <= width = oneLine
  | otherwise = T.stripEnd (T.take (width - 1) oneLine) <> "…"
  where
    oneLine = T.unwords (T.words text)

-- | How much of a blueprint migration's not-applicable reason the summary shows.
-- The reason is a clause appended to an already-long receipt line.
reasonWidth :: Int
reasonWidth = 60

-- | How much of a blueprint's stored user prompt the summary shows. Wider than
-- 'reasonWidth' because a prompt is a whole instruction on a line of its own
-- rather than a trailing clause.
promptWidth :: Int
promptWidth = 72
```

That Haddock comment points at an ADR that does not exist until Milestone 3. That is
deliberate — the comment is where a future reader will look — but if a dangling
reference bothers you mid-plan, write the comment without the ADR line now and add the
line in Milestone 3 alongside the ADR itself.

Then point the existing reason line at it, inside `formatBlueprintMigrations`:

```haskell
    renderReason MigrationApplied = ""
    renderReason (MigrationNotApplicable reason) =
      " -- " <> truncateForSummary reasonWidth reason
```

Finally, bound the prompt line in `blueprintSection`:

```haskell
        promptLines = case ab ^. #userPrompt of
          Nothing -> []
          Just p -> ["  Prompt: \"" <> truncateForSummary promptWidth p <> "\""]
```

Update `blueprintSection`'s Haddock comment, which currently says only "Prompt line:
present only when the user passed a positional prompt", to also say that the prompt is
collapsed to one line and bounded at `promptWidth`, with the whole of it kept in the
manifest.

At the end of this milestone, a manifest whose `userPrompt` is three paragraphs renders
as a single line of at most 84 columns, the existing five blueprint-provenance tests
still pass untouched, and the migration-receipt tests still pass untouched — including
the long-reason test, whose fixture has no spaces and so is blind to the trailing-space
change.

### Milestone 2 — `seihou status --full-prompt`

After this milestone a developer who wants the prompt back in full has a command for
it, and the default stays bounded. Three files change, one on each side of the
library/executable line.

In `seihou-cli/src/Seihou/CLI/StatusRender.hs`, add the display mode and a second
entry point. Put `PromptDisplay` near `ModuleAdvice` at the top of the module:

```haskell
-- | Whether the @Prompt:@ line shows a bounded one-line slice of the blueprint's
-- stored prompt or the whole of it. @seihou status@ renders 'PromptTruncated';
-- @seihou status --full-prompt@ renders 'PromptFull'. Either way the manifest
-- keeps the whole prompt.
data PromptDisplay
  = PromptTruncated
  | PromptFull
  deriving stock (Eq, Show)
```

Rename the existing `formatStatus` body to `formatStatusWith`, give it a leading
`PromptDisplay` argument, thread that argument into `blueprintSection`, and define
`formatStatus` as the truncating default:

```haskell
-- | Render the full @seihou status@ output with the default, bounded prompt.
formatStatus ::
  Bool ->
  Manifest ->
  [TrackedFile] ->
  Maybe [OutdatedEntry] ->
  [(ModuleName, MigrationPlan)] ->
  Text
formatStatus = formatStatusWith PromptTruncated

-- | As 'formatStatus', but with explicit control over how much of the blueprint's
-- stored prompt the @Prompt:@ line shows.
formatStatusWith ::
  PromptDisplay ->
  Bool ->
  Manifest ->
  [TrackedFile] ->
  Maybe [OutdatedEntry] ->
  [(ModuleName, MigrationPlan)] ->
  Text
formatStatusWith display color manifest tracked mEntries pendings = ...
```

The only change inside that body is `++ blueprintSection manifest` becoming
`++ blueprintSection display manifest`. Every other section renderer is untouched.

`blueprintSection` takes the new first argument and delegates the prompt line:

```haskell
blueprintSection :: PromptDisplay -> Manifest -> [Text]
blueprintSection display manifest = case manifest ^. #blueprint of
  ...
        promptLines = case ab ^. #userPrompt of
          Nothing -> []
          Just p -> renderPrompt display p
```

and a new module-level helper renders it:

```haskell
-- | The @Prompt:@ line(s) for a stored prompt. The truncated form is one quoted
-- line; the full form is a bare header followed by the prompt's own lines, each
-- indented under it. The full form is deliberately not quoted: a prompt may
-- contain a @"@ and nothing escapes it, so quotes would not tell a reader where
-- the value ends, while the indentation does.
renderPrompt :: PromptDisplay -> Text -> [Text]
renderPrompt PromptTruncated p =
  ["  Prompt: \"" <> truncateForSummary promptWidth p <> "\""]
renderPrompt PromptFull p =
  "  Prompt:" : map ("    " <>) (T.lines p)
```

Add `formatStatusWith` and `PromptDisplay (..)` to the module's export list.

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, add the field to `StatusOpts` (keeping
the `status` prefix the existing field uses, and the `!` strictness annotation the
record conventions require on every `data` record field):

```haskell
data StatusOpts = StatusOpts
  { statusCheckUpdates :: !Bool,
    -- | Print the blueprint's stored prompt in full instead of the bounded
    -- one-line slice the summary shows by default.
    statusFullPrompt :: !Bool
  }
  deriving stock (Eq, Show, Generic)
```

and the switch to `statusParser`, after the existing one so the applicative order
matches the field order:

```haskell
      <*> switch
        ( long "full-prompt"
            <> help "Print the blueprint's stored prompt in full instead of truncating it"
        )
```

Add a paragraph to `statusInfo`'s `footerDoc`, after the `--check-updates` paragraph
and before the pending-migrations one, in the same `pretty (... :: String)` style the
surrounding lines use:

```haskell
                  line,
                  pretty ("The blueprint's stored prompt is collapsed to one line and truncated" :: String),
                  pretty ("so it cannot dominate the summary. Use --full-prompt to print it in" :: String),
                  pretty ("full; .seihou/manifest.json always holds the whole of it." :: String),
```

In `seihou-cli/src-exe/Seihou/CLI/Status.hs`, change the import to bring in the new
names and pick the display mode from the flag:

```haskell
import Seihou.CLI.StatusRender (PromptDisplay (..), formatArtifactChecks, formatStatusWith)
```

```haskell
      let promptDisplay
            | opts ^. #statusFullPrompt = PromptFull
            | otherwise = PromptTruncated
      TIO.putStr (formatStatusWith promptDisplay colorEnabled manifest tracked mEntries pendings)
```

Note the reads go through `generic-lens` overloaded labels (`opts ^. #statusFullPrompt`),
never record dot syntax, and never record update syntax — that is a repository-wide
convention enforced by `nix/check-record-conventions.sh`. `Status.hs` already imports
`Data.Generics.Labels ()`, which is what makes `#statusFullPrompt` resolve.

At the end of this milestone, `seihou status --help` lists `--full-prompt`, `seihou
status` in a blueprint project prints one bounded prompt line, and `seihou status
--full-prompt` in the same project prints the whole prompt.

### Milestone 3 — documentation, ADR, and improvement-request bookkeeping

Nothing in the product changes here; this milestone makes the repository tell the
truth about what the previous two did, and closes IR-7.

`docs/cli/status.md` is the reference page for this command. Add the new flag to the
options table:

```markdown
| Option | Description |
|--------|-------------|
| `-u, --check-updates` | Check installed modules for available updates (requires network) |
| `--full-prompt` | Print the blueprint's stored prompt in full instead of truncating it |
```

and rewrite its Blueprint bullet, which today says only "…its baseline modules, and the
prompt that was supplied", so it describes the bound and the escape hatch, in the same
voice the page already uses for the truncated migration reason a few lines below.

`docs/user/CHANGELOG.md` has an empty `## Unreleased` heading at the top. Add a
`### Changed` entry under it describing the behaviour change from the reader's point of
view — that `seihou status` no longer floods with a long blueprint prompt, that the
manifest still has all of it, and that `--full-prompt` prints it — matching the
narrative style of the 0.8.0.0 entries below it.

`docs/dev/design/proposed/blueprints.md` describes the status rendering around line 207
and shows an example `Prompt:` line. Its sentence "The Prompt line is omitted when no
positional prompt was supplied" is now incomplete; extend it to say the prompt is
collapsed and truncated, and that `--full-prompt` shows it whole. Leave the example
itself alone: the prompt in it is 39 characters, well under `promptWidth`, so it
renders exactly as shown.

Do **not** edit `docs/dev/documentation-changelog.md`. Its `Prompt:` occurrence at line
263 is inside a dated historical audit entry, and that log records what was true at the
time.

Write `docs/adr/0013-status-is-a-bounded-summary-the-manifest-is-the-record.md`,
following the local convention exactly — `# ADR 0013 — …` then `- Status: Accepted`
and `- Date: 2026-09-16`, then Context / Decision / Consequences sections. Link sibling
ADRs the way `docs/adr/0011-a-migration-receipt-asserts-a-claim-about-the-project.md`
does, by bare filename relative to `docs/adr/` — `[ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md)`,
not the `../adr/…` form this plan uses from `docs/plans/`. Its content: `seihou status`
renders a view, not the record; any unbounded free-text value it shows is collapsed to
one line and cut to a fixed width through `truncateForSummary` in
`seihou-cli/src/Seihou/CLI/StatusRender.hs`; the authoritative copy stays whole in
`.seihou/manifest.json`, which
[ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md) already
establishes as the single source of truth and
[ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md) as a
checked-in artifact; a command that wants the whole value offers an explicit opt-in
flag rather than making the default lossy-or-not depending on the data. Record the
rejected alternative — wrapping the text to the terminal width instead of cutting it —
and why: wrapping keeps the line count proportional to the value's length, which is the
actual defect, and it makes the output depend on terminal width, which makes golden
tests untestable in the same way ADR 0010 describes for clock reads.

Finally, mark IR-7 accepted, following exactly the pattern IR-8 established in this
same working tree. In
`docs/improvement-requests/truncate-the-blueprint-prompt-in-status-output.md`:

- change `status: proposed` to `status: accepted`;
- add `targetPlan: docs/plans/91-truncate-the-blueprint-prompt-in-status-output.md`
  after the `requestId` line;
- update `timestamp:` to the current UTC time in the same `YYYY-MM-DDTHH:MM:SSZ` form;
- leave the `generated:` block alone — it records when the request was produced;
- insert a `## Status` section immediately after the `# Improvement Request: …`
  heading, saying it was accepted, linking this plan by repository-relative path, and
  naming the one place the plan deviates from the request: IR-7 suggests `--full` and
  the plan ships `--full-prompt`, for the reason in the Decision Log.

Then append the log entry with the `okf` CLI rather than by hand, so the entry lands in
the bundle's reserved `log.md` in the format the bundle expects:

```bash
okf log add docs/improvement-requests IR-7 --kind Update \
  -m "IR-7 is accepted and planned in docs/plans/91-truncate-the-blueprint-prompt-in-status-output.md. ..."
```

At the end of this milestone `nix flake check` passes and `okf validate` reports no
diagnostic it did not already report before this plan (see Surprises & Discoveries for
why that is the right bar).


## Concrete Steps

All commands run from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`, unless stated otherwise.

### Before you start

Confirm the baseline builds and the existing blueprint tests pass, so that any later
failure is yours:

```bash
cabal test all --enable-tests --test-options='-p "blueprint provenance"'
```

Expected, verified on this checkout on 2026-09-16:

```text
  Seihou.CLI.StatusRender
    formatStatus
      blueprint provenance
        renders a populated blueprint with version, two baselines, and prompt:                       OK (0.02s)
        renders --no-baseline as the dedicated placeholder:                                          OK
        omits the Prompt line when no positional prompt was supplied:                                OK
        omits the entire blueprint section when manifest.blueprint is Nothing:                       OK
        renders an empty-baseline (no --no-baseline) blueprint with the (none declared) placeholder: OK

All 5 tests passed (0.02s)
Test suite seihou-cli-test: PASS
```

The first run compiles the whole workspace and can take several minutes. If it instead
prints `Error: [Cabal-7043] Cannot test the test suite 'seihou-cli-test'`, you dropped
the `--enable-tests` flag; see Surprises & Discoveries.

### Milestone 1

Make the three edits to `seihou-cli/src/Seihou/CLI/StatusRender.hs` described under
"Plan of Work → Milestone 1": hoist the helper, add the two width constants, and route
both the reason line and the prompt line through `truncateForSummary`.

Then add tests to `seihou-cli/test/Seihou/CLI/StatusSpec.hs`, inside the existing
`describe "blueprint provenance"` block, after the five tests already there. Four
cases, each stated as a property of the rendered text:

```haskell
    -- IR-7: a multi-paragraph prompt used to occupy a dozen lines of the
    -- summary. The manifest still holds all of it.
    it "collapses and truncates a long multi-line prompt to a single bounded line" $ do
      let longPrompt =
            "Upgrade this repository to nix-haskell-flake 0.24.0.\n\n\
            \The flake already pins baikai 0.7, so do not re-pin it.\n\
            \Do not commit anything; leave the tree dirty for review."
          manifest =
            withManifestBlueprint
              (Just $ mkBlueprint "upgrade-flake" Nothing [] False (Just longPrompt))
              (mkManifest [])
          out = formatStatus False manifest [] Nothing []
          promptLines = [l | l <- T.lines out, "  Prompt: " `T.isPrefixOf` l]
      length promptLines `shouldBe` 1
      head promptLines
        `shouldBe` "  Prompt: \"Upgrade this repository to nix-haskell-flake 0.24.0. The flake already…\""
      out `shouldNotSatisfy` T.isInfixOf "leave the tree dirty"

    it "leaves a prompt shorter than the bound untouched and unmarked" $ do
      let manifest =
            withManifestBlueprint
              (Just $ mkBlueprint "short" Nothing [] False (Just "set this up for a payments microservice"))
              (mkManifest [])
          out = formatStatus False manifest [] Nothing []
      out `shouldSatisfy` T.isInfixOf "  Prompt: \"set this up for a payments microservice\""
      out `shouldNotSatisfy` T.isInfixOf "…"

    it "collapses internal whitespace in a short multi-line prompt without truncating" $ do
      let manifest =
            withManifestBlueprint
              (Just $ mkBlueprint "wrapped" Nothing [] False (Just "first line\n\n  second line"))
              (mkManifest [])
          out = formatStatus False manifest [] Nothing []
      out `shouldSatisfy` T.isInfixOf "  Prompt: \"first line second line\""
```

The first test is the one that would have caught IR-7: it asserts that exactly one line
begins with `  Prompt: `, pins that line's exact text, and checks that content from
beyond the cut is absent from the output entirely.

That exact text is worth deriving by hand once, so that a failure tells you something.
Collapsed to one line the fixture prompt begins
`Upgrade this repository to nix-haskell-flake 0.24.0. The flake already pins baikai…`.
Character 71 — the last one `T.take (promptWidth - 1)` keeps — is the space after
`already`, `T.stripEnd` removes it, and the ellipsis takes its place, giving 71
characters between the quotes and an 83-column line (`  Prompt: "` is 11 columns and
the closing quote is one more). If the assertion fails by one character in either
direction, the off-by-one is in `truncateForSummary`, not the fixture.

Do not add a test for the reason path: one already exists and is a better regression
guard than anything written now, because it predates this plan. It is
`truncates a long reason rather than wrapping it` at
`seihou-cli/test/Seihou/CLI/StatusSpec.hs` line 253, and it renders a receipt whose
not-applicable reason is `T.replicate 200 "x"`, then asserts the line contains
`T.replicate 59 "x" <> "…"` and does *not* contain 61 x's. Since that reason has no
internal whitespace, `T.unwords . T.words` is the identity on it, so the test pins the
cut arithmetic exactly. It must pass **unmodified** after the hoist.

Run:

```bash
cabal test all --enable-tests --test-options='-p "StatusRender"'
```

Expect every test under `Seihou.CLI.StatusRender` to report `OK`, including the five
pre-existing blueprint-provenance tests, which must pass **unmodified** — if one of
them now fails, the truncation is firing on a prompt that is under the bound and the
width arithmetic is wrong.

Then run the whole suite and commit:

```bash
cabal test all --enable-tests
git add seihou-cli/src/Seihou/CLI/StatusRender.hs seihou-cli/test/Seihou/CLI/StatusSpec.hs
git commit
```

with a message of this shape:

```text
fix(status): bound the blueprint prompt line in status output

seihou status echoed the stored blueprint prompt verbatim, so a
multi-paragraph prompt pushed the rest of the summary off the screen.
Collapse it to one line and cut it at 72 characters through the same
helper that already bounds a migration receipt's not-applicable reason.
The manifest keeps the whole prompt.

ExecPlan: docs/plans/91-truncate-the-blueprint-prompt-in-status-output.md
Intention: intention_01m2n64h7bevtr2xxfcn81f49b
```

### Milestone 2

Make the edits to the three files described under "Plan of Work → Milestone 2". Build
first, because the `formatStatus` / `formatStatusWith` split and the new `StatusOpts`
field will surface any call site you missed:

```bash
cabal build all
```

Expect a clean build with no warnings about unused or shadowed bindings. A
`-Wunused-top-binds` warning for `formatStatusWith` means you forgot the export list
entry; a type error at `seihou-cli/src-exe/Seihou/CLI/Status.hs` means the argument
order does not match (`PromptDisplay` comes first, before `color`).

Add tests for the full form beside the Milestone 1 tests:

```haskell
    it "prints the whole prompt, indented, under --full-prompt" $ do
      let longPrompt = "First paragraph.\nSecond paragraph that is quite long indeed."
          manifest =
            withManifestBlueprint
              (Just $ mkBlueprint "upgrade-flake" Nothing [] False (Just longPrompt))
              (mkManifest [])
          out = formatStatusWith PromptFull False manifest [] Nothing []
      out `shouldSatisfy` T.isInfixOf "  Prompt:\n    First paragraph.\n    Second paragraph that is quite long indeed."
      out `shouldNotSatisfy` T.isInfixOf "…"

    it "still omits the prompt entirely under --full-prompt when none was supplied" $ do
      let manifest =
            withManifestBlueprint
              (Just $ mkBlueprint "no-prompt" Nothing [] False Nothing)
              (mkManifest [])
          out = formatStatusWith PromptFull False manifest [] Nothing []
      out `shouldNotSatisfy` T.isInfixOf "  Prompt:"
```

The import line at the top of the spec gains the two new names:

```haskell
import Seihou.CLI.StatusRender
  ( PromptDisplay (..),
    formatArtifactChecks,
    formatStatus,
    formatStatusWith,
  )
```

Then verify the flag end to end against a real project. Create a throwaway manifest in
a scratch directory rather than editing a real project's:

```bash
mkdir -p /tmp/seihou-ir7/.seihou
cat > /tmp/seihou-ir7/.seihou/manifest.json <<'JSON'
{
  "version": 6,
  "generatedAt": "2026-09-13T09:41:00Z",
  "modules": [],
  "variables": {},
  "files": {},
  "applications": [],
  "blueprintMigrations": [],
  "blueprint": {
    "name": "fix-nix-haskell-flake-customizations",
    "origin": {"kind": "local", "artifact": "fix-nix-haskell-flake-customizations"},
    "appliedAt": "2026-09-13T09:41:00Z",
    "baselineModules": [],
    "noBaseline": false,
    "userPrompt": "Upgrade this repository to nix-haskell-flake 0.24.0.\n\nThe flake already pins baikai 0.7, so do not re-pin it. flake.nix carries three local customizations that must survive the upgrade.\n\nDo not commit anything; leave the tree dirty for review."
  }
}
JSON
```

That JSON matches this checkout's encoders, which is worth knowing because getting it
wrong produces a decode error rather than a status page. `currentManifestVersion` is
`6` (`seihou-core/src/Seihou/Manifest/Types.hs` line 64). `variables` and `files` are
JSON **objects**, not arrays — they decode into `Map`s. `origin` is a nested object with
a `kind` discriminator (`local`, `remote` or `project`), not an Aeson tag/contents pair.
If the encoders have moved on by the time you read this, or hand-writing the JSON proves
fiddly, get a real manifest instead: copy `.seihou/manifest.json` out of any project that
has had `seihou agent run` applied and lengthen its `userPrompt` string.

Then run the binary you just built against that directory. `cabal run` would resolve the
project relative to the current directory, so ask cabal where the binary is and invoke
it directly:

```bash
SEIHOU=$(cabal list-bin seihou)
cd /tmp/seihou-ir7 && "$SEIHOU" status
```

Expected:

```text
Seihou Status:

Blueprint: fix-nix-haskell-flake-customizations (applied 2026-09-13 09:41 UTC)
  Baseline: (none declared)
  Prompt: "Upgrade this repository to nix-haskell-flake 0.24.0. The flake already…"

Applied modules:
  (none)

Tracked files: 0
  (none)

Variables: 0 resolved
```

A trailing `Artifacts that differ from what this project records:` block may follow,
because the scratch project names a blueprint that is not installed on this machine.
That is the manifest guard doing its job and is irrelevant to what you are checking
here; ignore it.

and:

```bash
"$SEIHOU" status --full-prompt
```

```text
Blueprint: fix-nix-haskell-flake-customizations (applied 2026-09-13 09:41 UTC)
  Baseline: (none declared)
  Prompt:
    Upgrade this repository to nix-haskell-flake 0.24.0.

    The flake already pins baikai 0.7, so do not re-pin it. flake.nix carries three local customizations that must survive the upgrade.

    Do not commit anything; leave the tree dirty for review.
```

Also check the help text lists the flag:

```bash
"$SEIHOU" status --help
```

Expect a line reading `--full-prompt  Print the blueprint's stored prompt in full
instead of truncating it` among the options, and the new footer paragraph below them.

Clean up the scratch directory when done: `cd -` back to the repository root, then
`rm -rf /tmp/seihou-ir7`.

Run the full suite and commit:

```bash
cabal test all --enable-tests
git add seihou-cli/src/Seihou/CLI/StatusRender.hs seihou-cli/src-exe/Seihou/CLI/Commands.hs \
        seihou-cli/src-exe/Seihou/CLI/Status.hs seihou-cli/test/Seihou/CLI/StatusSpec.hs
git commit
```

```text
feat(status): add --full-prompt to print the stored blueprint prompt whole

The summary bounds the Prompt line, so give anyone who wants the whole
instruction a way to see it without opening .seihou/manifest.json.

ExecPlan: docs/plans/91-truncate-the-blueprint-prompt-in-status-output.md
Intention: intention_01m2n64h7bevtr2xxfcn81f49b
```

### Milestone 3

Make the documentation edits and write ADR 0013 as described under "Plan of Work →
Milestone 3". Then record the IR-7 log entry:

```bash
okf log add docs/improvement-requests IR-7 --kind Update \
  -m "IR-7 is accepted and planned in docs/plans/91-truncate-the-blueprint-prompt-in-status-output.md. The plan hoists the existing reason truncation in StatusRender.hs into a shared truncateForSummary helper and routes the blueprint Prompt line through it at a 72-character bound, leaving .seihou/manifest.json untouched. The optional escape hatch ships as seihou status --full-prompt rather than the suggested --full, because status truncates one value among six blocks and a bare --full does not say which; -u and -v are both taken. ADR 0013 records the underlying rule."
```

Check the bundle reports nothing new:

```bash
okf validate docs/improvement-requests --strict \
  --profile docs/improvement-requests/profile.dhall --profile-enforce --log-enforce
```

Expect exactly the eight pre-existing `missing profile-recommended field: reviews`
lines and exit status 1, unchanged from the baseline recorded in Surprises &
Discoveries. Any other line is a regression you introduced.

Then the repository-wide check:

```bash
nix flake check
```

This runs the build, the test suites, `nix/check-cli-module-placement.sh` and
`nix/check-record-conventions.sh`. The placement check is the one most likely to catch
a mistake from Milestone 2: if you put the `--full-prompt` switch anywhere but
`seihou-cli/src-exe/Seihou/CLI/Commands.hs`, or moved rendering out of
`seihou-cli/src/`, it fails and names the module. The record-conventions check fails if
the new `statusFullPrompt` field is missing its `!`.

Commit:

```bash
git add docs/
git commit
```

```text
docs(status): document the bounded prompt line and accept IR-7

Add ADR 0013 recording that seihou status is a bounded summary and the
manifest is the record, update the status CLI reference and the user
changelog, and mark IR-7 accepted against this plan.

ExecPlan: docs/plans/91-truncate-the-blueprint-prompt-in-status-output.md
Intention: intention_01m2n64h7bevtr2xxfcn81f49b
```

Finally, fill in Outcomes & Retrospective in this plan, check off every Progress item
with the date, and record a provenance revision entry:

```bash
bun agents/skills/exec-plan/record-provenance.ts revision \
  --plan docs/plans/91-truncate-the-blueprint-prompt-in-status-output.md \
  --model <your-verified-model-id> --harness <your-harness> \
  --mode implement --note "Implemented all three milestones"
```


## Validation and Acceptance

The change is accepted when all of the following are observably true.

**A long prompt no longer dominates the summary.** In a project whose manifest records
a blueprint with a multi-paragraph `userPrompt`, `seihou status` prints a `Blueprint:`
block exactly three lines tall (header, `  Baseline:`, `  Prompt:`), and the `Prompt:`
line is a single line whose quoted content is at most 72 characters and ends in `…`
when the stored prompt was longer. The test
`collapses and truncates a long multi-line prompt to a single bounded line` asserts
this against a fixture; the scratch-manifest walkthrough in Concrete Steps → Milestone 2
demonstrates it against the real binary.

**Nothing was lost.** After running `seihou status` in that project,
`.seihou/manifest.json` is byte-identical to what it was before — `seihou status` is a
reporting command and writes nothing. Prove it:

```bash
shasum .seihou/manifest.json && seihou status > /dev/null && shasum .seihou/manifest.json
```

Both hashes must match. Additionally, `jq -r '.blueprint.userPrompt' .seihou/manifest.json`
prints the whole prompt including the text that the summary cut.

**The full prompt is reachable from the command line.** `seihou status --full-prompt`
in the same project prints the prompt's every line, indented four spaces under a bare
`  Prompt:` header, with no ellipsis. `seihou status --help` lists the flag.

**A short prompt is untouched.** A prompt of 72 characters or fewer with no internal
line breaks renders exactly as it does today, quoted, with no ellipsis. This is what
keeps the five pre-existing blueprint-provenance tests in
`seihou-cli/test/Seihou/CLI/StatusSpec.hs` passing without modification, and it is the
single best signal that the width arithmetic is right: those tests were written before
this plan and are not adjusted by it.

**The migration-receipt line is unchanged except for one deliberate cosmetic
difference.** The refactor that hoists `truncateReason` into `truncateForSummary` must
not alter receipt rendering at all, save that a reason cut mid-gap no longer carries a
space before its ellipsis (see the Decision Log). Every pre-existing test in the
`blueprint migration receipts` block passes unmodified, including the long-reason test
at line 253, whose fixture has no spaces and is therefore untouched by the change.

**The whole suite and the repository checks are green.**

```bash
cabal test all --enable-tests
nix flake check
```

Both must succeed. `okf validate docs/improvement-requests --strict --profile
docs/improvement-requests/profile.dhall --profile-enforce --log-enforce` must report
the same eight advisory lines it reported before this plan and no others; see Surprises
& Discoveries for why it exits 1 either way.

### Edge cases the implementation must handle

- **`userPrompt` is `Nothing`.** No `Prompt:` line at all, in either display mode. This
  is existing behaviour and there is already a test for it; a second test covers the
  `--full-prompt` path.
- **`userPrompt` is `Just ""`.** `T.words ""` is `[]` and `T.unwords [] ` is `""`, so
  the truncated form renders `  Prompt: ""`, exactly as it does today. The full form
  renders a bare `  Prompt:` header with nothing under it, because `T.lines ""` is `[]`.
  Neither is wrong and neither crashes; the `Just ""` / `Nothing` distinction is
  preserved. Do not add a special case that collapses `Just ""` to no line — that would
  change what the manifest means.
- **A prompt of exactly 72 characters after collapsing.** Rendered whole, with no
  ellipsis: the guard is `T.length oneLine <= width`. A prompt of 73 keeps its first 71
  characters, minus a trailing space if the cut landed on one, plus `…` — so 71 or 72
  characters in total, never more.
- **A prompt containing a `"`.** Unescaped today and unescaped after this change. Out of
  scope; the full form's lack of quoting is partly why it is unquoted.
- **A prompt whose whitespace is tabs or non-breaking spaces.** `T.words` splits on any
  Unicode whitespace, so tabs collapse. A non-breaking space is not whitespace to
  `T.words` and is preserved, which is correct — it is content.


## Idempotence and Recovery

Every step here is a source edit followed by a build, a test run, or a read-only
command, so the whole plan can be re-run from any point without damage.

`cabal build all`, `cabal test all --enable-tests` and `nix flake check` are pure
builds: running them repeatedly changes nothing but the build cache. `seihou status`
and `seihou status --full-prompt` only read `.seihou/manifest.json`; neither writes to
it, which is what the hash check in Validation and Acceptance proves. `okf validate` is
read-only.

The one command that mutates a checked-in file outside your editor is
`okf log add`, which appends an entry to `docs/improvement-requests/log.md`. Running it
twice appends the entry twice. If that happens, delete the duplicate bullet by hand —
`log.md` is an ordinary Markdown file — and re-run `okf validate` to confirm the bundle
is still well-formed.

If a milestone goes wrong after you have committed it, `git revert <sha>` restores the
prior behaviour cleanly: each milestone is self-contained and the three commits do not
depend on one another's *content*, only on their order (Milestone 2 calls
`truncateForSummary`, which Milestone 1 introduces). Reverting Milestone 2 alone leaves
a working, bounded `Prompt:` line with no flag, which is a coherent state and exactly
what IR-7 requires at minimum.

The scratch manifest under `/tmp/seihou-ir7` is disposable; delete it and recreate it
freely. Never test this against a real project's `.seihou/manifest.json` by editing it,
even though `seihou status` cannot corrupt one — use a copy.


## Interfaces and Dependencies

No new package dependencies. Everything this plan needs is already imported by the
modules it touches.

`seihou-cli/src/Seihou/CLI/StatusRender.hs` already imports `Data.Text qualified as T`,
which supplies `T.words`, `T.unwords`, `T.lines`, `T.length`, `T.take` and
`T.stripEnd` — the whole of the truncation and full-rendering logic. It already imports `Control.Lens ((^.))`
and `Data.Generics.Labels ()` for the `#userPrompt` accessor.

`seihou-cli/src-exe/Seihou/CLI/Commands.hs` already imports `Options.Applicative`,
which supplies `switch`, `long` and `help`. This import is the reason that module lives
under `src-exe/` rather than `src/`, per the CLI module-placement convention in
`docs/dev/architecture/overview.md`.

`seihou-cli/src-exe/Seihou/CLI/Status.hs` already imports `Data.Generics.Labels ()`,
so `opts ^. #statusFullPrompt` resolves without a new import; only the
`Seihou.CLI.StatusRender` import line changes, to add `PromptDisplay (..)` and
`formatStatusWith`.

These are the signatures that must exist at the end of each milestone.

At the end of Milestone 1, in `Seihou.CLI.StatusRender` (module-level, not exported —
they are internal to the renderer):

```haskell
truncateForSummary :: Int -> Text -> Text
reasonWidth :: Int
promptWidth :: Int
```

with `formatStatus` unchanged:

```haskell
formatStatus ::
  Bool ->
  Manifest ->
  [TrackedFile] ->
  Maybe [OutdatedEntry] ->
  [(ModuleName, MigrationPlan)] ->
  Text
```

At the end of Milestone 2, additionally in `Seihou.CLI.StatusRender`, both exported:

```haskell
data PromptDisplay
  = PromptTruncated
  | PromptFull
  deriving stock (Eq, Show)

formatStatusWith ::
  PromptDisplay ->
  Bool ->
  Manifest ->
  [TrackedFile] ->
  Maybe [OutdatedEntry] ->
  [(ModuleName, MigrationPlan)] ->
  Text
```

with these internal shapes:

```haskell
blueprintSection :: PromptDisplay -> Manifest -> [Text]
renderPrompt :: PromptDisplay -> Text -> [Text]
```

and in `Seihou.CLI.Commands`:

```haskell
data StatusOpts = StatusOpts
  { statusCheckUpdates :: !Bool,
    statusFullPrompt :: !Bool
  }
  deriving stock (Eq, Show, Generic)
```

`handleStatus :: StatusOpts -> IO ()` in `Seihou.CLI.Status` keeps its signature; only
its body changes.

Two repository-wide conventions constrain these definitions, both enforced by scripts
wired into `nix flake check` and the pre-commit hook:

- **Record conventions** (`nix/check-record-conventions.sh`): every field of a `data`
  record carries `!`; an explicit `deriving stock` strategy; `Generic` in the derive
  list for any record read through `#labels`; fields read with `^. #label`, never
  record dot syntax and never record update syntax. `PromptDisplay` is a plain sum type
  with no fields, so only the explicit `deriving stock` clause applies to it.
- **CLI module placement** (`nix/check-cli-module-placement.sh`): a module belongs in
  `seihou-cli/src-exe/` only if it needs `Options.Applicative`, `Data.FileEmbed`,
  `GitHash` or `Paths_seihou_cli`, or imports a module that is itself trapped there.
  `StatusRender.hs` needs none of those and stays in `seihou-cli/src/`; the option
  parser stays in `Commands.hs` under `src-exe/`.
