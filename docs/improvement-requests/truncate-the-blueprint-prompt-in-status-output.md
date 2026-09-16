---
type: Improvement Request
title: Truncate the blueprint prompt in status output
description: >-
  Stop seihou status from echoing the entire stored blueprint prompt verbatim, which for a detailed
  positional prompt floods the scannable summary with a wall of text; truncate it the way blueprint
  migration reasons are already truncated, and keep the whole of it in the manifest.
generated:
  by: process:claude-code
  at: "2026-09-14T00:00:00Z"
timestamp: 2026-09-14T00:00:00Z
requestId: IR-7
status: proposed
origin: mori://shinzui/okf-profiles
---

# Improvement Request: Truncate the Blueprint Prompt in Status Output

## Context

`seihou status` renders a `Blueprint:` provenance block for a blueprint recorded in the manifest.
The block is a header (name, version, applied timestamp), a `Baseline:` line, and — when the user
passed a positional prompt to `seihou agent run` — a `Prompt:` line. `blueprintSection` in
`seihou-cli/src/Seihou/CLI/StatusRender.hs` prints that prompt verbatim:

```haskell
promptLines = case ab ^. #userPrompt of
  Nothing -> []
  Just p -> ["  Prompt: \"" <> p <> "\""]
```

There is no length bound. Whatever positional prompt was stored in `userPrompt` at apply time is
emitted in full.

## Problem

**The prompt is untruncated, so a detailed one clobbers the status summary.** A positional prompt is
often several paragraphs — pre-established facts, per-file caveats, "do not commit" instructions —
because that is exactly the context a blueprint run needs. When such a prompt is stored, `seihou
status` becomes dominated by a single quoted wall of text that dwarfs every other line (recipe,
module, migration, diff summary). The provenance block stops being scannable, which is the one job
`status` has.

Observed 2026-09-13 in `mori://shinzui/kotei`, whose manifest records the
`fix-nix-haskell-flake-customizations` blueprint with a multi-paragraph upgrade prompt. `seihou
status` prints roughly a dozen lines of prompt text, so the actual status — what is installed,
what differs from disk — is pushed off the top of a normal terminal.

The stored prompt is correct and must stay; the defect is only that the *summary view* reproduces
all of it instead of a scannable slice.

## The precedent already exists in the same file

`formatBlueprintMigrations`, a few lines below `blueprintSection`, already faced this exact tension
and resolved it. A migration's `not-applicable` reason can be arbitrarily long, so it is truncated
for the summary while the manifest keeps the whole of it:

```haskell
-- `seihou status` is a scannable summary, so a long reason is truncated
-- rather than wrapped; the manifest keeps the whole of it.
renderReason (MigrationNotApplicable reason) = " -- " <> truncateReason reason

truncateReason reason
  | T.length oneLine <= reasonWidth = oneLine
  | otherwise = T.take (reasonWidth - 1) oneLine <> "…"
  where
    oneLine = T.unwords (T.words reason)

reasonWidth = 60
```

The blueprint prompt is the same shape of value — durable, kept in full in the manifest, shown in a
scannable summary — and should get the same treatment. It is the one long free-text field in the
`Blueprint:` block that escaped the rule the file already commits to.

## Requested change

Apply the migration-reason discipline to the prompt line:

1. **Collapse and truncate the prompt** for the `status` summary — flatten internal whitespace with
   `T.unwords . T.words` (so a multi-paragraph prompt becomes one line) and cut it to a fixed width
   with a trailing `…`, mirroring `truncateReason`. A single shared truncation helper would keep the
   two blocks honest with each other. A prompt width somewhat wider than 60 is reasonable given it is
   a whole instruction, not a reason clause; the exact width is an author's call.
2. **Leave the manifest untouched.** `userPrompt` stays the full prompt; only the rendered line is
   shortened, exactly as the migration comment describes for reasons.

Optionally, a `--full` / verbose flag on `status` could print the untruncated prompt for anyone who
wants it — but the default must be scannable.

## Scope

`blueprintSection` in `seihou-cli/src/Seihou/CLI/StatusRender.hs` is the only site observed. The
recipe and baseline lines are already short and need no change. This request does not touch what is
stored, how blueprints are applied, or any provenance guarantee — it is purely a rendering bound on
one line of `seihou status`.

## Related

Same file and same underlying principle as the existing `truncateReason` handling for blueprint
migration receipts; this request simply extends that already-stated rule ("`seihou status` is a
scannable summary") to the prompt line it does not yet cover.
