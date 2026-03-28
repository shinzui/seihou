# Fix --commit message stripping triple-backtick fencing

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

When a user runs `seihou run <module> --commit`, the AI-generated commit message is
sometimes wrapped in markdown code fences (triple backticks). This produces git commits
whose message literally begins with ` ```text ` or ` ``` `, which is ugly and incorrect.

After this fix, the commit message will be clean text with no surrounding backtick fencing,
regardless of what the LLM returns.


## Progress

- [x] Add `stripCodeFence` function to `Seihou.CLI.CommitMessage` (2026-03-28)
- [x] Apply `stripCodeFence` to Claude output in `generateCommitMessage` (2026-03-28)
- [x] Add tests for `stripCodeFence` in `CommitMessageSpec.hs` (2026-03-28)
- [x] Build and run tests — all 95 tests pass (2026-03-28)


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Fix in `CommitMessage.hs` by stripping backtick fences from output, rather than
  only adjusting the prompt.
  Rationale: The prompt already says "Output ONLY the commit message, nothing else" but
  Claude still sometimes wraps output in code fences. A defensive strip is more reliable
  than prompt-only mitigation. Both should be applied.
  Date: 2026-03-28

- Decision: Also tighten the prompt to explicitly say "Do not wrap the output in backticks
  or code fences."
  Rationale: Belt-and-suspenders. Reduces frequency of the problem even without the strip.
  Date: 2026-03-28


## Outcomes & Retrospective

All milestones complete. The fix adds a defensive `stripCodeFence` function that removes
markdown code-fence wrapping from Claude's output, and tightens the prompt to explicitly
prohibit code fences. Both the belt (prompt) and suspenders (strip function) are in place.
All 95 tests pass including 6 new `stripCodeFence` tests.


## Context and Orientation

The `--commit` flag was added in commit `50b64af`. When `--commit` is passed to
`seihou run`, the CLI:

1. Stages generated files with `git add` (`seihou-cli/src/Seihou/CLI/Git.hs:gitAdd`)
2. Gets the staged diff via `gitDiffCached`
3. Calls `generateCommitMessage` (`seihou-cli/src/Seihou/CLI/CommitMessage.hs`) which
   invokes `claude -p` with a prompt containing the diff
4. Passes the returned text to `gitCommit` (`Git.hs:gitCommit`)

The bug is at step 3 → 4. Claude's response sometimes wraps the commit message in
markdown code fences like:

    ```
    feat: apply haskell-base module
    ```

or:

    ```text
    feat: apply haskell-base module
    ```

The current code only calls `T.strip` on the output (line 29 of `CommitMessage.hs`),
which removes whitespace but not backtick fencing.

**Key files:**

- `seihou-cli/src/Seihou/CLI/CommitMessage.hs` — commit message generation and prompt
- `seihou-cli/test/Seihou/CLI/CommitMessageSpec.hs` — tests


## Plan of Work

### Milestone 1: Strip backtick fencing and tighten prompt

**Scope:** Add a `stripCodeFence` helper to `CommitMessage.hs` that removes leading/trailing
triple-backtick lines (with optional language tag) from text. Apply it to Claude's output.
Also add an explicit "no code fences" instruction to the prompt. Add unit tests.

**What exists at the end:** `seihou run <module> --commit` produces clean commit messages
even when Claude wraps output in code fences.

**Acceptance criteria:**
- `stripCodeFence` removes ` ```<lang>\n...\n``` ` wrapping
- `stripCodeFence` is a no-op on text without fencing
- Prompt includes explicit "no code fences" instruction
- All existing tests still pass, new tests pass

#### Edits

**File: `seihou-cli/src/Seihou/CLI/CommitMessage.hs`**

1. Add `stripCodeFence :: T.Text -> T.Text` function. Logic:
   - Split text into lines
   - If the first non-empty line starts with ` ``` ` and the last non-empty line is ` ``` `,
     drop both and rejoin
   - Otherwise return input unchanged

2. In `generateCommitMessage`, apply `stripCodeFence` to the output:
   change `pure (T.strip msg)` to `pure (stripCodeFence (T.strip msg))`

3. In `buildPrompt`, add to the Rules section:
   `"- Do not wrap the output in backticks or code fences"`

**File: `seihou-cli/test/Seihou/CLI/CommitMessageSpec.hs`**

4. Export `stripCodeFence` from `CommitMessage` module so tests can import it directly.

5. Add test cases for `stripCodeFence`:
   - Input with ` ```\nmessage\n``` ` → `"message"`
   - Input with ` ```text\nmessage\n``` ` → `"message"`
   - Input without fencing → unchanged
   - Input with backticks in the middle → unchanged
   - Empty input → empty


## Concrete Steps

All commands run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

1. Edit `seihou-cli/src/Seihou/CLI/CommitMessage.hs` — add `stripCodeFence`, apply it,
   tighten prompt.

2. Edit `seihou-cli/test/Seihou/CLI/CommitMessageSpec.hs` — add `stripCodeFence` tests.

3. Build:

       cabal build all

   Expected: compiles with no errors.

4. Run tests:

       cabal test all

   Expected: all tests pass including new `stripCodeFence` tests.


## Validation and Acceptance

1. **Unit tests:** `cabal test all` passes. The new `stripCodeFence` tests verify:
   - Fenced input (with and without language tag) is unwrapped
   - Unfenced input passes through unchanged
   - Edge cases (empty, backticks mid-text) are handled

2. **Manual smoke test:** Run `seihou run <module> --commit` on a test project and
   inspect the resulting git log message — it should not contain triple backticks.


## Idempotence and Recovery

All steps are idempotent. The edits can be re-applied safely. If the build fails, fix
the compilation error and rebuild. No destructive operations.


## Interfaces and Dependencies

No new dependencies. Only standard `Data.Text` functions are needed.

In `seihou-cli/src/Seihou/CLI/CommitMessage.hs`, add:

    stripCodeFence :: T.Text -> T.Text

Export it from the module so tests can import it.
