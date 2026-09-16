# ADR 0013 — `seihou status` is a bounded summary; the manifest is the record

- Status: Accepted
- Date: 2026-09-16

## Context

`seihou status` is the command a developer runs to see, at a glance, what Seihou
has done to the project they are standing in: which recipe or blueprint produced
it, which modules are applied and at what versions, which generated files they
have since edited, and what they should run next. It earns its keep by fitting on
a screen. Six blocks compete for that screen, and any one of them growing without
bound pushes the other five out of view.

Two of the values those blocks render are unbounded free text supplied by a
human, not computed by Seihou:

- A blueprint migration receipt's not-applicable reason, written by an agent
  explaining why an edge's precondition was unmet in this project.
- A blueprint's stored `userPrompt` — the positional argument to
  `seihou agent run <blueprint> "<prompt>"`.

Neither is short in practice. A real blueprint prompt is several paragraphs of
pre-established facts, per-file caveats and "do not commit anything" instructions,
because that is the context the agent needs. Rendered verbatim it opened the
status summary with a dozen wrapped lines.

Each of these was dealt with separately and at a different time. The reason was
bounded when receipts were first rendered, by a `truncateReason` helper private to
one `where` clause, its rationale recorded only as a comment beside it. The prompt
was not bounded at all, and nobody noticed until a consuming project filed
[IR-7](../improvement-requests/truncate-the-blueprint-prompt-in-status-output.md).
That is the shape of the problem: the rule existed, it was correct, and it was
invisible to the next person adding a free-text field to `status`. There will be a
third such field.

## Decision

**`seihou status` renders a view, not the record.** Any unbounded free-text value
it shows is collapsed to a single line and cut to a fixed width, through one
shared helper — `truncateForSummary` in
`seihou-cli/src/Seihou/CLI/StatusRender.hs`. A cut is marked with a trailing
ellipsis so a reader can see that something was elided. The authoritative copy of
every such value stays whole in `.seihou/manifest.json`, which
[ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md) already
establishes as the only record of applied state and
[ADR 0001](0001-manifest-is-a-checked-in-machine-independent-artifact.md) as a
checked-in, reviewable artifact.

Three rules follow, and they are what the decision means in practice:

1. **One helper, not one per field.** Every bounded value goes through
   `truncateForSummary`, which collapses whitespace and cuts. The per-field
   decision is a width constant beside it — `reasonWidth = 60` for a clause
   appended to an already-long receipt line, `promptWidth = 72` for a whole
   instruction on a line of its own. A second truncation implementation is how the
   two drift apart, and how the third field acquires no bound at all.
2. **A command that wants the whole value offers an explicit opt-in flag.**
   `seihou status --full-prompt` prints the stored prompt verbatim. The default is
   bounded unconditionally; it does not become lossy-or-not depending on how long
   the data happens to be, because a reader cannot tell which mode they got
   without knowing the width. An opt-in flag also means a truncation is never the
   only way to see a value, which is what would make it feel like data loss rather
   than a summary.
3. **The full form is delimited by indentation, not by quotes.** A prompt may
   itself contain a `"` and nothing escapes it, so a quoted multi-line value would
   not tell a reader where it ends. Indentation does, and it preserves the
   paragraph structure that is the reason someone asked for the value in full.

## Consequences

Adding a free-text field to the status summary now has an obvious answer: route it
through `truncateForSummary` with its own width constant, and if the whole value is
worth reading in a terminal, add a flag for it. The rule is written down rather
than reconstructed from a comment in one `where` clause.

Truncation is display-only and reversible. `seihou status` is a reporting command
that writes nothing, so `.seihou/manifest.json` is byte-identical across a run and
`jq -r '.blueprint.userPrompt' .seihou/manifest.json` prints the whole prompt
including the text the summary cut. Nothing downstream reads the rendered text.

The rejected alternative was **wrapping** the text to the terminal width instead
of cutting it. It fails on both counts. Wrapping keeps the rendered line count
proportional to the value's length, which is the actual defect — a
three-paragraph prompt still costs a dozen lines, just neater ones. And it makes
the output depend on the terminal width, so the same manifest renders differently
in two shells and there is no stable text for a golden test to assert against —
the same untestability [ADR 0010](0010-generated-documentation-is-checked-before-it-is-written.md)
describes for a clock read embedded in generated output.

Two smaller consequences of the shared helper. A cut that lands mid-gap has its
trailing space stripped, so the result reads `"… The flake already…"` rather than
`"… The flake already …"`; this changed receipt-reason rendering too, which is
intended — the two fields are meant to look alike. And the helper's contract is
"at most `width` characters", not "exactly `width` when cut", because of that
strip.

This decision covers the `status` summary. It says nothing about commands whose
output *is* the value — a future `seihou manifest show` or similar would be
rendering the record, not a view of it, and would not truncate.

## References

- [ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md) — the
  manifest is the only record of applied state, which is what makes a lossy view
  safe.
- [ADR 0001](0001-manifest-is-a-checked-in-machine-independent-artifact.md) — the
  manifest is checked in and reviewable, so the whole value is one file away.
- [ADR 0010](0010-generated-documentation-is-checked-before-it-is-written.md) —
  the untestability of output that varies with its environment, which is why
  wrapping was rejected.
- [ADR 0007](0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md) — the
  not-applicable outcome whose free-text reason was the first bounded value.
- `docs/plans/91-truncate-the-blueprint-prompt-in-status-output.md` — the
  implementation.
- `docs/improvement-requests/truncate-the-blueprint-prompt-in-status-output.md` —
  IR-7, the request this answers.
- `docs/cli/status.md` — the user-facing description of the bounded prompt line
  and `--full-prompt`.
