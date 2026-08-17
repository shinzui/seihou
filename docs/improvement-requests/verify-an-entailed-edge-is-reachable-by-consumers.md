---
type: Improvement Request
title: Verify an entailed edge is reachable by consumers, not just declared locally
description: >-
  Give a blueprint author a way to check that an entailed blueprint's exact edge resolves from the
  source consumers install from, since validate-blueprint correctly ignores the question and the
  --debug preview answers it against the author's own working tree.
generated:
  by: process:claude-code
  at: "2026-08-17T14:00:00Z"
timestamp: 2026-08-17T14:00:00Z
requestId: IR-5
status: proposed
origin: mori://shinzui/okf-profiles
---

# Improvement Request: Verify an Entailed Edge Is Reachable by Consumers

## Context

`entails` (0.7.0.0, EP-85) lets one blueprint's edge require an exact edge of another blueprint.
`docs/user/blueprint-migrations.md` is explicit that resolution is deferred:

> Whether the named blueprint exists and declares that edge is a filesystem question, so it is
> checked when `seihou agent migrate` resolves the cohort rather than here.

and that a failure to resolve is fail-closed:

> Seihou will not skip it: doing so would leave the project half-migrated with no signal at all.

Both decisions are right and this request does not ask to change either.

## Problem

An entailment can be **fully correct and still unreachable by every consumer**, and nothing an
author would run reports it.

Observed during the `mori://shinzui/keiro` 0.13.0.0 release (2026-08-17). `keiro-upgrade`'s
`0.12.0.0 -> 0.13.0.0` edge entails `kiroku-upgrade` `0.7.0.1 -> 0.8.0.0`. The `kiroku-upgrade`
blueprint was authored correctly and declared exactly that edge — but its commit existed only in
the local kiroku checkout. Consumers install blueprints from git, so at that moment every
`seihou agent migrate keiro-upgrade` run would have hit the hard refusal. It was caught by going
looking, one step before an irreversible Hackage upload.

What makes this worth a tooling change rather than a checklist entry is that **the two checks an
author would run both pass, and one of them manufactures false confidence**:

- `seihou validate-blueprint` passes, *correctly*. Whether some other blueprint declares the named
  edge is not a property of the blueprint being validated, and the documentation says so.
- `seihou agent --debug migrate keiro-upgrade --from 0.12.0.0 --to 0.13.0.0` passes and prints a
  perfect two-step plan, each step labelled with its owning blueprint. But it resolves whatever is
  installed on the author's machine — which, for a cohort being authored, is very often a dev
  checkout or a copy installed from a local path.

The preview is exactly the tool a release checklist reaches for here, and it cannot distinguish
"this entailment works" from "this entailment works on my machine". Its reassurance is strongest
precisely where it is least warranted: on the machine where both blueprints were just written.

The failure mode is **asymmetric**. The author sees success; only consumers see the refusal. And
because a cohort's whole purpose is to serve projects that have never heard of the upstream
library, the people who hit it are the least equipped to diagnose it.

## Why the existing surfaces do not cover it

- **`validate-blueprint`** is scoped to one blueprint and should stay that way. Extending it to
  chase entailments *by default* would make a pure, offline, filesystem-free check into a network
  operation.
- **`--debug migrate`** resolves through the ordinary install search path, which is the correct
  behaviour for previewing what *this* machine will run. It is answering a different question than
  the author is asking.
- **`agent migrate`'s existing refusal** is the right runtime behaviour and already prints an
  install hint. It fires on the consumer's machine, which is one machine too late.
- **A per-repo release-checklist step** works — `mori://shinzui/keiro` now carries one
  (`agents/skills/release/SKILL.md`, commit `898c2944`: `git -C <upstream> fetch -q origin` then
  `git branch -r --contains <commit>`, empty output means unpushed). But it has to be reinvented by
  every cohort author, it encodes git specifics seihou already abstracts over, and it only catches
  the unpushed-commit case rather than the general one.

## Requested change

Two changes, in ascending cost. The first is worth doing regardless of whether the second is.

### 1. Report each resolved blueprint's provenance in the preview

`--debug migrate` already tells the agent where reference files live. Have each step's header also
name where its owning blueprint resolved *from* — the `sourceUrl` in `.seihou-origin.json`, or an
explicit marker when there is none:

```text
===== [1/2] kiroku-upgrade 0.7.0.1 -> 0.8.0.0 (entailed by keiro-upgrade 0.12.0.0 -> 0.13.0.0) =====
  resolved from: https://github.com/shinzui/kiroku.git  (installed 2026-08-17)
```

versus

```text
  resolved from: local path /Users/…/kiroku  (no verifiable origin)
```

An author reading the second line would have seen this immediately. It costs one line, needs no
network, has no false negatives, and helps well beyond entailment — a stale install of *any*
blueprint is equally invisible today.

### 2. Resolve entailments against their recorded remote, on request

Add an opt-in mode — `seihou validate-blueprint --resolve-entailments`, or a dedicated
`seihou check-cohort BLUEPRINT` — that, for each declared entailment, fetches the entailed
blueprint from **its recorded `sourceUrl`** rather than the local install, and confirms the exact
`from`/`to` edge exists there.

Keeping it opt-in preserves `validate-blueprint`'s offline guarantee while giving authors one
command that answers the question they actually have. Resolving from the *recorded remote* rather
than from a git working tree matters: seihou resolves installed artifacts, not checkouts, and an
installed copy generally has no working tree to inspect. That framing also covers cases the
git-specific check misses — a stale install, an entailed blueprint whose edge was renamed upstream,
or one published from a repository the author does not control.

A blueprint with no recorded origin cannot be checked this way; saying so explicitly is a useful
answer, not a gap.

## Scope

Blueprint migration entailment (`entails`, `seihou agent migrate`). Nothing here asks to change the
fail-closed refusal, the receipt-identity rules, or the deferral of edge resolution out of
`validate-blueprint`'s default path — all three behaved exactly as designed in the observed case.

## Related

- `docs/adr/0008-an-entailed-migration-edge-is-owned-by-the-blueprint-that-declares-it.md` — edge
  ownership is what makes provenance the right thing to surface: a step's owner is frequently not
  the blueprint the user named, so *where that owner came from* is not something the user can infer.
- IR-4 (`refuse-to-overwrite-an-installation-from-a-different-source.md`) and IR-2
  (`record-artifact-origin-for-agent-applied-artifacts.md`) established that artifact origin is
  identity. Both requests above are that same principle applied one step earlier — at authoring and
  preview time, rather than at install and receipt time.
