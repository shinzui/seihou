---
type: Improvement Request
title: Guard the agent path against stale and substituted artifacts
description: >-
  Apply the ADR 0003 refusal to seihou agent run and seihou agent migrate, which write baseline
  files and migration receipts today without ever consulting ManifestGuard, so a substituted or
  downgraded blueprint is caught on the agent path as it already is on the module path.
generated:
  by: process:claude-code
  at: "2026-08-06T17:12:58Z"
timestamp: 2026-08-06T17:12:58Z
requestId: IR-3
status: proposed
origin: mori://shinzui/okf-profiles
---

# Improvement Request: Guard the Agent Path Against Stale and Substituted Artifacts

## Status

Proposed. Depends on [IR-2](record-artifact-origin-for-agent-applied-artifacts.md): the guard has
nothing to compare against until the agent-path records carry an origin.

## Context

[ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md) decides that a command
about to generate from an artifact refuses when the local copy is older than, or came from
somewhere other than, what the manifest records:

> The same shape applies to identity rather than version: a module with the recorded name installed
> from a different repository is a different module, and generating from it substitutes one
> artifact for another silently.

It rejects the warn-and-continue alternative directly:

> A warning is the natural-looking middle ground and is worse than useless here. The whole problem
> is that the regression is invisible in review; a line of warning text scrolled past in a build
> log does not make it visible.

`Seihou.CLI.ManifestGuard` implements the comparison and the refusal.

## Problem

`ManifestGuard` is imported by `Run.hs`, `Migrate.hs`, `ManifestUpgrade.hs`, and `Status.hs`. It is
imported by neither `src-exe/Seihou/CLI/AgentRun.hs` nor `src-exe/Seihou/CLI/AgentMigrate.hs`. No
guard runs anywhere on the agent path.

That path is not read-only. `seihou agent run` applies the blueprint's `baseModules` to the working
directory before rendering the prompt — `applyBaseline` in `AgentRun.hs`, described in its own
comment as mirroring the module flow — and those modules generate files exactly as `seihou run`
does. The same command then writes an `AppliedBlueprint` entry to `.seihou/manifest.json`.
`seihou agent migrate` writes a receipt per edge, and those receipts suppress future runs of the
edges they name.

So the two failures ADR 0003 exists to stop are both reachable:

- **Downgrade.** Developer A upgrades a blueprint, runs it, and commits the regenerated baseline
  output and the manifest. Developer B still has the older blueprint installed. `seihou run` would
  refuse; `seihou agent run` applies the older baseline and rewrites the manifest to name the older
  version. This is ADR 0003's opening scenario with a blueprint substituted for a module.
- **Substitution.** A blueprint resolving to a name installed from a different repository is a
  different blueprint. Its baseline modules are different modules, and it writes a manifest entry
  and receipts under the recorded name.

The human-in-the-loop argument is weaker here than it looks. Baselines are applied *before* the
provider session starts, so the files land whether or not the operator reads the prompt. `--batch`
removes the operator entirely — `claude -p` or `codex exec` with workspace access, which
`docs/user/blueprints.md` documents as the path a module `RunCommand` migration uses to invoke a
blueprint. And on the migrate path the operator sees less than nothing: a substituted blueprint's
edges are dropped as already-applied, per IR-2.

## Why the existing mechanisms do not cover it

- **`seihou status`** calls `checkAppliedArtifacts` and will report a mismatch once IR-2 gives it
  an origin to check. But status is a command a developer chooses to run; ADR 0003's whole argument
  is that a passive signal is not enough at the point of generation.
- **The `seihou run` refusal** does not transfer. `seihou run` refuses outright when the name
  resolves to a blueprint — that is the documented split — so nothing about the blueprint path
  reaches the guarded code.
- **Blueprint non-determinism** is not a reason to skip the check. What is guarded is the identity
  and version of the artifact being applied, not the determinism of its output, and the baseline
  half of a blueprint run is ordinary module generation.

## Requested change

Have `seihou agent run` and `seihou agent migrate` consult `ManifestGuard` before doing work, and
refuse on the same terms as `seihou run` and `seihou migrate`, with the same `--allow-downgrade`
override printing what it overrides.

Specifically:

1. In `agent run`, check the blueprint against the recorded `AppliedBlueprint` before
   `applyBaseline`, so a refusal leaves the working tree byte-identical — the property
   `SharedManifestE2ESpec.hs` already asserts for `seihou run`.
2. Check the resolved `baseModules` too. They are modules, they generate files, and a blueprint
   run is the one path on which they are applied without the `seihou run` guard.
3. In `agent migrate`, check before planning edges, so a substituted blueprint is refused rather
   than having its edges silently dropped as already-applied.
4. Scope each refusal to the artifacts the command is about to use, matching the line ADR 0003
   draws for `seihou run`.

Debug runs should not check. `--debug` contacts no provider, applies no baseline, and writes
nothing, so it stays usable for inspecting a prompt on any machine.

## Scope

`seihou agent run` and `seihou agent migrate`. `seihou prompt run` applies no baseline and records
no provenance, so it has nothing to compare and is deliberately excluded.

## Related

- [IR-2](record-artifact-origin-for-agent-applied-artifacts.md) — a prerequisite. Without an origin
  on the agent-path records the guard can only compare versions, which catches the downgrade half
  and none of the substitution half.
- [IR-4](refuse-to-overwrite-an-installation-from-a-different-source.md) — the same collision
  addressed one layer earlier, at install time rather than at use time.
- [ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md) — the decision this
  extends to a path it does not currently reach.
