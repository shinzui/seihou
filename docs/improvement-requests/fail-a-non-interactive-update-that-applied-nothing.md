---
type: Improvement Request
title: Fail a non-interactive update that applied nothing
description: >-
  Stop plain seihou update from reporting success when it has no terminal to confirm
  on, since it currently changes nothing, ignores piped answers, shows no prompt,
  exits 0 and gives no hint that --json is the non-interactive path.
generated:
  by: process:claude-code
  at: "2026-11-04T18:07:02Z"
timestamp: 2026-11-04T18:07:02Z
requestId: IR-16
status: proposed
origin: mori://shinzui/seihou-modules
reviews:
  - kind: model
    reviewer: process:claude-code
    provider: anthropic
    model: claude-opus-5-5
    effort: unspecified
    reviewed_at: "2026-11-04T18:07:02Z"
    document_timestamp: "2026-11-04T18:07:02Z"
    scope: content-and-metadata
    outcome: commented
    context: >-
      Author check against the Seihou 0.15.0.0 source and a minimal local
      reproduction. Not an independent approval.
---

# Improvement Request: Fail a Non-Interactive Update That Applied Nothing

## Status

Proposed. Raised from `FRIC-11`
(`mori://shinzui/seihou-modules/okf/friction-log/concepts/FRIC-11`) against Seihou
0.15.0.0. No implementation plan exists.

## Context

A session working in `mori://shinzui/kansoku-ui` ran `seihou update nix-bun-flake` from
a non-interactive shell to take the `nix-bun-flake` 0.6.0 release. It got the update
plan and a cancellation with no visible prompt, then succeeded by repeating the command
with `--json`. The session suggested a one-line hint in the message. Reproducing it
showed the exit status is the larger problem.

## Problem

`seihou-cli/src-exe/Seihou/CLI/Update.hs` defines `confirmApply False = pure False`, so
without a terminal on stdin the update is declined without asking. The caller then
prints the cancellation and returns normally:

```text
$ seihou update child --no-commands </dev/null
Update cancelled; no managed state was changed.
child  1.0.0 -> 1.1.0
exit 0
$ cat child.txt
name=demo v1.0.0
```

- **Scripts see success.** `seihou update && next-step` continues with the project
  still on the old release, and CI reports the update as done.
- **Piped answers are ignored.** `print y | seihou update child` is cancelled the same
  way, even though the same input would be accepted on a terminal.
- **The message describes a choice nobody made.** "Cancelled" reads as a declined prompt,
  and nothing points to `--json`. The help text says `--json` disables prompts, but a
  caller has no reason to look there when the command appears to have worked.

Unresolved conflicts already behave better on the same path: `failInteraction` exits
non-zero with a message saying an interactive terminal or `--force` is required.

## Requested change

1. When an update has changes to apply and no terminal to confirm on, exit non-zero
   instead of reporting cancellation, and keep the guarantee that no managed state
   changes.
2. Say what happened and how to proceed, for example: `No terminal to confirm this
   update; nothing was applied. Pass --json to apply it without prompts, or --dry-run to
   preview it.`
3. Treat end of input at an interactive prompt the same way, since no answer was given.

## Acceptance criteria

- `seihou update </dev/null` with a pending update exits non-zero, changes nothing and
  prints the hint on stderr.
- `seihou update --json` and `--dry-run` behave as they do today.
- With no pending update, a non-interactive `seihou update` still prints "Already up to
  date." and exits 0.
- Answering `n` at a terminal prompt still exits 0, because that is a real decision.
- `docs/cli/update.md` documents the exit status.

## Scope and design questions

This is a behaviour change for any script relying on the current exit 0, so it needs a
release note. A script that does rely on it is probably skipping updates unknowingly.

Whether to add `--yes` is left open. It would give scripts the human-readable output
with no prompt, which `--json` does not, and could also honour a piped `y`. The exit
status and the hint are useful without it.

## Related

- `mori://shinzui/seihou-modules/okf/friction-log/concepts/FRIC-11`
- `mori://shinzui/seihou-modules/okf/friction-log/concepts/FRIC-1`, a related limit on non-interactive update
- `docs/cli/update.md`
