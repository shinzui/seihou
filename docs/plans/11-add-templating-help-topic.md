# Add a `templating` help topic

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, a Seihou user can run `seihou help templating` in their terminal
and read a concise, self-contained guide to the Template generation strategy —
placeholder substitution, inline `{{#if}}` conditional blocks, the expression
grammar, standalone-block whitespace trimming, error kinds, and common authoring
patterns — without leaving the shell or opening a browser.

Today Seihou ships with six in-terminal help topics (`modules`, `variables`,
`contexts`, `config`, `git-repository`, `kit`) surfaced by the `seihou help`
subcommand. The full template reference already exists as the Markdown document
`docs/user/templating.md`, but that file is not embedded in the binary and is
only discoverable to users who browse the source tree. This plan derives a
terminal-ready condensation of that reference, embeds it at compile time via
`file-embed`, and registers it as a seventh help topic so that:

- `seihou help` lists a new line `templating  Placeholder substitution, {{#if}} blocks, and patterns`.
- `seihou help templating` prints the new topic's content to stdout.
- `seihou help --help` shows `templating` in the TOPIC metavar help text.

The observable proof is the transcript of those three commands after the build
succeeds, shown in the Concrete Steps section below.


## Progress

- [x] Draft `seihou-cli/help/templating.md` in the project's help-topic plain-text format (ALL-CAPS headers, 2-space indentation under headers). (2026-04-19)
- [x] Add `templatingContent :: Text` binding with `$(embedStringFile "help/templating.md")` in `seihou-cli/src/Seihou/CLI/Help.hs`. (2026-04-19)
- [x] Insert a `HelpTopic "templating" ...` entry into the `helpTopics` list in `Help.hs`. (2026-04-19)
- [x] Build: `nix develop --command cabal build seihou`. (2026-04-19)
- [x] Verify `seihou help` now includes a `templating` line in the index. (2026-04-19)
- [x] Verify `seihou help templating` prints the embedded content verbatim. (2026-04-19)
- [x] Verify `seihou help --help` advertises `templating` in its TOPIC argument help text. (2026-04-19)
- [x] Commit with an `ExecPlan: docs/plans/11-add-templating-help-topic.md` trailer. (2026-04-19, commit e4ab869)


## Surprises & Discoveries

- `seihou help --help` prints its `-h,--help` line twice. This is a pre-existing
  quirk of how `helper` and `info` are wired in the help subcommand; it is
  unchanged by this plan and is unrelated to adding a topic. Noted here so a
  future reader of the transcript is not surprised. Evidence (from 2026-04-19):

      Available options:
        TOPIC                    Help topic: modules, variables, contexts, config,
                                 git-repository, kit, templating
        -h,--help                Show this help text
        -h,--help                Show this help text


## Decision Log

- Decision: Model the new topic on `seihou-cli/help/config.md` (medium-length,
  heavy on code examples) rather than the terser `variables.md`.
  Rationale: The templating reference has more distinct concepts (placeholders,
  conditionals, whitespace trim, errors, patterns) than a single-concept topic.
  The `config.md` shape — a short intro paragraph followed by five or six
  ALL-CAPS sections with indented example blocks — fits the material without
  bloating the topic into a wall of text.
  Date: 2026-04-19

- Decision: Condense, do not copy, `docs/user/templating.md`. The help topic
  will cover the same concepts but at roughly one-quarter the length, omitting
  the cross-references section, the extended error-line-numbering digression,
  and the "when you need more than gating" escape-hatch discussion.
  Rationale: Help topics are read in a terminal and must fit a reader's
  working memory on first pass. The full reference lives at
  `docs/user/templating.md` and is the right destination for deeper dives; the
  topic should close with a pointer to that file rather than duplicate it.
  Date: 2026-04-19

- Decision: Keep the existing `padRight 17` column width in
  `Help.hs:listTopics`. The new topic name `templating` is 10 characters —
  well under 17 — so no alignment change is needed.
  Rationale: The widest existing topic name is `git-repository` (14 chars),
  already comfortably padded. Changing the pad width would be an unrelated
  edit.
  Date: 2026-04-19

- Decision: Do not change the cabal file. `Seihou.CLI.Help` is already listed
  in `other-modules`, and `file-embed`'s `embedStringFile` Template Haskell
  splice automatically picks up new files in the `help/` directory at build
  time.
  Rationale: Plan 10's predecessor (`add-help-topics-command.md`) records the
  same observation. Adding topic content is a purely additive change to two
  files (`help/templating.md` and `Help.hs`).
  Date: 2026-04-19


## Outcomes & Retrospective

All acceptance criteria met on the first build. The clean additive nature of
the change (one new file, two two-line edits to `Help.hs`) meant there was no
iteration on the code — the only work was writing the topic body itself.

Observed behaviour on 2026-04-19:

    $ seihou help
    HELP TOPICS

      modules          How Seihou modules work
      variables        Variable declaration, resolution, and overrides
      contexts         Using contexts for environment-specific config
      config           Config scopes, reading, and writing values
      git-repository   Sharing and installing modules from git
      kit              Manage Claude Code skills and subagents
      templating       Placeholder substitution, {{#if}} blocks, and patterns

    Use 'seihou help <topic>' for details.

`seihou help templating` prints the full topic body verbatim.
`seihou help --help` advertises `templating` in the TOPIC argument help text.
`seihou help NONEXISTENT` lists `templating` among the known topics in its
error message.

Lessons: the help-system plan (add-help-topics-command.md) had predicted that
adding topics would be a purely two-file additive change — that prediction
held exactly. No cabal or wiring edits were needed.


## Context and Orientation

Seihou is a composable project scaffolding CLI written in Haskell (GHC 9.12.2,
GHC2024). The codebase is a multi-package Cabal workspace with
`seihou-core` (library) and `seihou-cli` (executable).

**What the Template strategy is.** Seihou modules declare a list of generation
steps, each of which uses one of four strategies: `copy` (verbatim copy),
`template` (variable substitution plus inline boolean gates), `dhall-text`
(evaluate a Dhall expression to produce Text), or `structured` (evaluate a
Dhall expression to produce JSON/YAML). The `template` strategy is the one
this plan documents. It has two powers and only two: replace `{{variable.name}}`
with the resolved value of `variable.name`, and gate regions of the template
on a boolean expression via `{{#if EXPR}}…{{#else}}…{{/if}}` blocks. Anything
more (loops, arithmetic, derived values) belongs to the DhallText strategy.

**Where the full reference lives.** The comprehensive user-facing reference is
`docs/user/templating.md` (387 lines). This plan derives a terminal-ready
condensation from it. A reader who has followed this plan to completion does
not need to have read `docs/user/templating.md` — the relevant material is
summarised in the Interfaces and Dependencies section below.

**How the help system is wired.** The `seihou help` subcommand was added by
the plan `docs/plans/add-help-topics-command.md` (not numbered). The mechanism
is:

1. Plain-text topic files live in `seihou-cli/help/*.md`. Despite the `.md`
   extension, they are NOT rendered — they are printed verbatim with
   `Data.Text.IO.putStrLn`. The convention is ALL-CAPS section headers at
   column 0 and 2-space indentation for body text under a header.
2. The module `seihou-cli/src/Seihou/CLI/Help.hs` embeds each topic file into
   the binary at compile time using `Data.FileEmbed.embedStringFile`
   (returns a `Text` via `OverloadedStrings`). One splice per topic:

        templatingContent :: Text
        templatingContent = $(embedStringFile "help/templating.md")

   The path is resolved relative to the package root
   (`seihou-cli/seihou-cli.cabal` lives there).
3. A top-level list `helpTopics :: [HelpTopic]` in the same file registers
   each topic with a name, a one-line description, and the embedded content:

        HelpTopic "templating"
                  "Placeholder substitution, {{#if}} blocks, and patterns"
                  templatingContent
4. The handler `handleHelpCommand` either lists topics (printing name and
   description in two aligned columns) or prints a named topic's content
   verbatim. Topic lookup is case-insensitive and does `T.toLower name`
   before the `find`.

The `Command` ADT, the subparser wiring, the `Main.hs` dispatch, and the
cabal `other-modules` entry for `Seihou.CLI.Help` are already in place. No
edits outside `seihou-cli/help/templating.md` and
`seihou-cli/src/Seihou/CLI/Help.hs` are required.

**Key files touched by this plan:**

- `seihou-cli/help/templating.md` — new file, plain text.
- `seihou-cli/src/Seihou/CLI/Help.hs` — add one embedding binding and one
  `helpTopics` entry.

**Key files consulted but not modified:**

- `docs/user/templating.md` — the source material being condensed.
- `seihou-cli/help/config.md` — the structural model for the new topic.
- `seihou-cli/help/modules.md` — a second reference for the plain-text style
  convention (ALL-CAPS headers, 2-space indentation, column-aligned command
  tables).


## Plan of Work

The work is a single milestone. At the end, the `seihou help` command
recognises a new topic called `templating`, prints a one-line entry for it
in the index, and reads the embedded topic body on demand.

### Milestone 1: Draft the topic, embed it, register it, verify it

This milestone delivers the whole feature. After it, running
`nix develop --command cabal run seihou -- help templating` prints the topic
body, and `seihou help` lists `templating` alongside the other six topics.

First, write the content file `seihou-cli/help/templating.md`. The exact
structure is described in the Interfaces and Dependencies section below.
The topic has seven sections, each with an ALL-CAPS header at column 0 and
indented body text. The sections are: introduction paragraph (no header);
`PLACEHOLDERS`; `ESCAPING {{`; `CONDITIONAL BLOCKS`; `EXPRESSION LANGUAGE`;
`STANDALONE TAG WHITESPACE`; `ERRORS`; `COMMON PATTERNS`; `WHEN TO USE
DHALL-TEXT INSTEAD`; and a closing `FURTHER READING` section that points at
`docs/user/templating.md`.

Second, edit `seihou-cli/src/Seihou/CLI/Help.hs` in two spots:

1. Append a new embedding binding after the `kitContent` binding (around
   line 54–55). The binding is:

        templatingContent :: Text
        templatingContent = $(embedStringFile "help/templating.md")

2. Add a new element to the `helpTopics` list (around lines 29–37). Place
   it after the `kit` entry so the topic order in the help index remains
   stable and grouped by broad theme (content first, tooling last). The new
   list element is:

        HelpTopic "templating" "Placeholder substitution, {{#if}} blocks, and patterns" templatingContent

Third, build. The Template Haskell splice in the new binding runs at
compile time, so a missing or misspelled path surfaces immediately as a
GHC error pointing at the `$(embedStringFile "help/templating.md")`
expression. Working directory is the repository root
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/`:

    nix develop --command cabal build seihou

Fourth, verify the three user-visible behaviours with the commands in the
Concrete Steps section. The topic must appear in the index, print verbatim
on request, and be named in the `--help` metavar text.

Fifth, commit. One commit for the new topic file and the two edits to
`Help.hs`. The commit message must include the `ExecPlan:` trailer.


## Concrete Steps

All commands are run from the repository root
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/`.

Step 1 — create the topic file. Write `seihou-cli/help/templating.md`
following the content outline in the Interfaces and Dependencies section.
The file is plain text; do not use Markdown code fences, headings, or
lists — only ALL-CAPS section headers and 2-space-indented body text.

Step 2 — edit `seihou-cli/src/Seihou/CLI/Help.hs`. Insert the new
`helpTopics` entry after the existing `kit` entry, and the
`templatingContent` binding after the existing `kitContent` binding.

Step 3 — build:

    nix develop --command cabal build seihou

Expected: clean build with no errors and no warnings from the new code.
A typical success transcript ends with a line such as
`Linking .../seihou-cli/build/seihou/seihou …` and no `warning:` or
`error:` lines. If the `$(embedStringFile "help/templating.md")` splice
cannot find the file, GHC will abort with a message naming the offending
path; fix the path or the working directory and rebuild.

Step 4 — list topics:

    nix develop --command cabal run seihou -- help

Expected output (the `templating` line is new; other lines remain):

    HELP TOPICS

      modules          How Seihou modules work
      variables        Variable declaration, resolution, and overrides
      contexts         Using contexts for environment-specific config
      config           Config scopes, reading, and writing values
      git-repository   Sharing and installing modules from git
      kit              Manage Claude Code skills and subagents
      templating       Placeholder substitution, {{#if}} blocks, and patterns

    Use 'seihou help <topic>' for details.

Step 5 — print the topic:

    nix develop --command cabal run seihou -- help templating

Expected: the full verbatim content of `seihou-cli/help/templating.md`
is written to stdout and the process exits successfully. Run the command
a second time to confirm the output is byte-identical between runs (the
content is compiled in, not read from disk at runtime).

Step 6 — confirm the command metavar:

    nix develop --command cabal run seihou -- help --help

Expected: optparse-applicative's auto-generated help text for the `help`
subcommand, and the `TOPIC` argument's help line includes the string
`templating` among the other topic names.

Step 7 — commit:

    git add seihou-cli/help/templating.md seihou-cli/src/Seihou/CLI/Help.hs
    git commit

Commit message template:

    docs(help): add templating help topic

    Condense docs/user/templating.md into a terminal-ready topic
    covering placeholder substitution, {{#if}} conditional blocks,
    the expression grammar, standalone-block whitespace trimming,
    error kinds, and common authoring patterns. Surfaced by
    `seihou help templating`.

    ExecPlan: docs/plans/11-add-templating-help-topic.md


## Validation and Acceptance

The change is accepted when all of the following hold:

1. `nix develop --command cabal build seihou` completes with no errors
   and no warnings originating in `Seihou.CLI.Help`.
2. `nix develop --command cabal run seihou -- help` prints a line
   starting with `  templating` in the index, placed after the existing
   six topic lines, with the one-line description
   `Placeholder substitution, {{#if}} blocks, and patterns`.
3. `nix develop --command cabal run seihou -- help templating` prints
   the verbatim content of `seihou-cli/help/templating.md` followed by
   a trailing newline (the handler calls `TIO.putStrLn`, which adds a
   newline; this matches every other topic's behaviour).
4. `nix develop --command cabal run seihou -- help --help` shows the
   `TOPIC` metavar and its help text includes the substring `templating`
   (the help text is the comma-joined list of topic names from the
   `helpCommandParser` definition).
5. `nix develop --command cabal run seihou -- help NONEXISTENT` still
   prints `Unknown topic: NONEXISTENT` followed by a list of available
   topics that now includes `templating` — this regression-guards the
   fallback path.
6. Spot-check the content quality: reading the topic end-to-end should
   teach a reader who has never used Template generation enough to write
   a template with placeholders and at least one `{{#if}}` block.
7. The commit message contains the exact line
   `ExecPlan: docs/plans/11-add-templating-help-topic.md` at the end,
   separated from the body by a blank line.


## Idempotence and Recovery

All steps are additive. Creating a new file in `seihou-cli/help/` and
adding one list entry plus one top-level binding to
`seihou-cli/src/Seihou/CLI/Help.hs` is trivially reversible with
`git checkout -- seihou-cli/help/templating.md seihou-cli/src/Seihou/CLI/Help.hs`.

Re-running the build after the edits is safe and deterministic; the
Template Haskell `embedStringFile` splice recomputes the literal on every
recompile of `Help.hs`. If `Help.hs` is edited but the topic file is
missing, GHC will fail at the splice site with a clear "file not found"
message; creating the missing file and rebuilding recovers.

If the commit is made and the topic text is later found wanting, edit
the file, rebuild, and commit a follow-up `docs(help):` change. No
migration or state is involved; the content is pure.


## Interfaces and Dependencies

**Libraries used:**

- `file-embed` (already declared in `seihou-cli/seihou-cli.cabal` at
  `>=0.0.15 && <1`): provides the Template Haskell splice
  `embedStringFile :: FilePath -> Q Exp` which reads a file at compile
  time and splices its contents as an `IsString`-polymorphic literal.
  With the project's `OverloadedStrings` default, the literal is
  elaborated to `Text`.
- `optparse-applicative` (already declared): parses the optional
  `TOPIC` positional argument. No changes to its use.
- `text` (already declared): `Text`, `T.intercalate`, `T.toLower`,
  `T.replicate` used by existing code in `Help.hs`.

**New content file — `seihou-cli/help/templating.md`:**

Plain text (no Markdown rendering). Suggested structure, roughly 120–160
lines total. Each section is separated from the next by a blank line.
The draft below is prescriptive about structure and illustrative about
wording; keep section headers exactly as shown so downstream tooling and
readers see a consistent shape.

The file opens without a section header — a short two-paragraph
introduction summarising what the Template strategy is and the two
powers it has (placeholder substitution and boolean gating). The first
paragraph names the dispatch trigger (the `.tpl` extension). The second
paragraph explains the deliberate ceiling (no loops, no arithmetic) and
points the reader at `dhall-text` for anything richer.

Then the sections, in order:

    PLACEHOLDERS

Explain the `{{variable.name}}` syntax including that surrounding
whitespace inside the braces is ignored. State that variable names match
`[a-zA-Z][a-zA-Z0-9._-]*` — dots are part of the name, not structural.
Then an indented coercion table listing each VarValue form and its
rendered text:

      VText  "hello"     ->  hello
      VBool  True        ->  true
      VBool  False       ->  false
      VInt   42          ->  42
      VList  ["a","b"]   ->  a,b          (comma-separated)

Note that placeholder substitution works in three positions: template
bodies, the `dest` field of a step, and the `run`/`workDir` fields of
shell-command steps.

    ESCAPING {{

Show the `\{{` escape that produces a literal `{{` in output. Note that
there is no `\}}` escape and none is needed. Note that the escape does
not apply to block tags; a template cannot emit a literal `{{#if` —
use the DhallText strategy when that is required.

    CONDITIONAL BLOCKS

Show the two syntaxes:

      {{#if EXPR}} ... {{/if}}
      {{#if EXPR}} ... {{#else}} ... {{/if}}

State that blocks nest to arbitrary depth with nearest-match pairing.
State the untaken-branch rule explicitly: text in the untaken branch is
discarded before the placeholder engine sees it, so unresolved
placeholders and malformed expressions in the untaken branch do not
produce errors. This is deliberate — it lets authors gate optional
features without having to declare every variable referenced inside the
gate.

State that conditional blocks work in template bodies only — not in
`dest`, `run`, `workDir`, or in the pre-evaluation text of DhallText and
Structured steps (those strategies use Dhall's own `if`/`then`/`else`).

    EXPRESSION LANGUAGE

Give the grammar in a single indented block:

      expr     = or_expr
      or_expr  = and_expr  ("||" and_expr)*
      and_expr = not_expr  ("&&" not_expr)*
      not_expr = "!" atom  |  atom
      atom     = "IsSet" NAME
               | "Eq"    NAME VALUE
               | "(" expr ")"
               | "true" | "false"
      VALUE    = "quoted string"  |  bareWord

Then three short paragraphs of explanation: `IsSet foo` tests whether
`foo` has a resolved value; `Eq foo X` compares `foo` to `X` with type
sensitivity (a bool variable needs bare-word `true`/`false`, not quoted
`"true"`); `&&`, `||`, `!`, and parentheses work as usual. Mention that
the same grammar is used by step-level `when` clauses.

    STANDALONE TAG WHITESPACE

Define standalone: a tag is standalone when everything on its line
before the tag is spaces or tabs (or the line starts with the tag) and
everything after is spaces or tabs followed by a newline (or the
template ends). A standalone tag absorbs its leading indent and one
trailing newline. A tag sharing a line with other content keeps all
surrounding whitespace verbatim.

Give one compact before-and-after example:

      prev
        {{#if Eq flag true}}
        body
        {{/if}}
      next

With `flag = true` the output is `prev\n  body\nnext\n`. With
`flag = false` the output is `prev\nnext\n` — no blank-line cruft
either way.

Note that only ASCII space (0x20) and tab (0x09) qualify; NBSP and
other Unicode whitespace do not trigger the trim.

    ERRORS

List the five error kinds with a one-sentence description each:

      UnresolvedPlaceholder   {{name}} references a variable with no value.
      MalformedPlaceholder    {{ opened on a line without a closing }}.
      UnterminatedIf          {{#if}} opener with no matching {{/if}}.
      OrphanBlockToken        {{/if}} or {{#else}} outside any open {{#if}}.
      MalformedIfExpression   Expression inside {{#if ...}} failed to parse.

Each error reports a line number. Block-level errors point at the source
line of the offending tag. Placeholder errors inside a taken branch
report a line number measured in the post-expansion text, which may drift
from the source line by the number of absorbed newlines.

    COMMON PATTERNS

Give three short indented examples:

Optional single line:

      nativeBuildInputs = [
        pkgs.cabal-install
        {{#if Eq nix.postgresql true}}
        pkgs.postgresql
        {{/if}}
      ];

If / else with a default on one line:

      runtime = "{{#if IsSet docker.registry}}{{docker.registry}}/{{project.name}}{{#else}}{{project.name}}{{/if}}";

Version-gated content:

      {{#if Eq ghc.version "ghc912"}}
        -- ghc912-specific build flags
        ghc-options: -Wno-x-partial
      {{/if}}

    WHEN TO USE DHALL-TEXT INSTEAD

One-paragraph escape hatch. Switch the step's strategy to `dhall-text`
(freeform Text) or `structured` (JSON/YAML) when you need to loop over
a list, compute a derived value, choose among many discrete cases, or
merge structured data across modules. Both strategies substitute
`{{variable}}` placeholders first, then evaluate the resulting Dhall
expression — so you still get variable interpolation on the way in.

    FURTHER READING

Point at the three in-repo resources:

      docs/user/templating.md            full reference (this topic condensed)
      docs/user/module-authoring.md      variables, steps, strategies in context
      docs/user/config-and-variables.md  how variables are resolved

**Modified module — `seihou-cli/src/Seihou/CLI/Help.hs`:**

Two additive edits only.

1. In the `helpTopics` list at the top of the module (current lines
   29–37), append a new element after the `"kit"` entry. The edit
   adds a trailing comma to the existing last element and inserts the
   new line:

        helpTopics :: [HelpTopic]
        helpTopics =
          [ HelpTopic "modules" "How Seihou modules work" modulesContent,
            HelpTopic "variables" "Variable declaration, resolution, and overrides" variablesContent,
            HelpTopic "contexts" "Using contexts for environment-specific config" contextsContent,
            HelpTopic "config" "Config scopes, reading, and writing values" configContent,
            HelpTopic "git-repository" "Sharing and installing modules from git" gitRepositoryContent,
            HelpTopic "kit" "Manage Claude Code skills and subagents" kitContent,
            HelpTopic "templating" "Placeholder substitution, {{#if}} blocks, and patterns" templatingContent
          ]

2. Append a new top-level binding after the existing `kitContent`
   binding:

        templatingContent :: Text
        templatingContent = $(embedStringFile "help/templating.md")

No other edits to `Help.hs` are needed. The parser, handler, ADT, and
cabal entries already handle any number of topics uniformly.

**What does NOT change:**

- `seihou-cli/seihou-cli.cabal` — `Seihou.CLI.Help` is already listed in
  `other-modules` and `file-embed` is already a dependency.
- `seihou-cli/src/Seihou/CLI/Commands.hs` — the `HelpCmd` constructor
  already exists.
- `seihou-cli/src/Main.hs` — dispatch to `handleHelpCommand` already
  exists.
- Any test files — the help command has no automated tests today; this
  plan does not add any. If tests are added later, they belong to a
  separate plan about help-topic regression testing.


## A note on maintenance

When `docs/user/templating.md` is later revised (new feature, renamed
error kind, tweaked syntax), the embedded help topic does not update
automatically — it is a condensation, not a view. Whoever updates the
reference should check whether the help topic also needs a matching edit.
The content is short enough that a quick diff pass after any Template
strategy change suffices. This maintenance burden is accepted knowingly
(see Decision Log).
