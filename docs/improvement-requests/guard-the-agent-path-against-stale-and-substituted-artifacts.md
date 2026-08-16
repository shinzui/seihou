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
timestamp: 2026-08-16T00:00:00Z
requestId: IR-3
status: completed
completedAt: "2026-08-16T00:00:00Z"
targetPlan: docs/plans/83-guard-the-agent-path-against-stale-and-substituted-artifacts.md
resolution: >-
  seihou agent run and seihou agent migrate now consult ManifestGuard before doing any work and
  refuse on the same terms as seihou run, with a --allow-downgrade override that prints what it
  overrode. agent run checks the blueprint plus every module in its resolved baseline composition;
  agent migrate checks the blueprint alone, against the applied-blueprint entry or, failing that,
  the most recent receipt for it. The blanket --debug exemption this request asked for was applied
  to agent migrate only: agent run --debug still applies the baseline and still records provenance,
  so exempting it would have left the hole open. ADR 0003 was amended rather than duplicated.
origin: mori://shinzui/okf-profiles
---

# Improvement Request: Guard the Agent Path Against Stale and Substituted Artifacts

## Status

Completed 2026-08-16 by
[`docs/plans/83-guard-the-agent-path-against-stale-and-substituted-artifacts.md`](../plans/83-guard-the-agent-path-against-stale-and-substituted-artifacts.md).
See [Resolution](#resolution). Depended on
[IR-2](record-artifact-origin-for-agent-applied-artifacts.md), which landed first: the guard had
nothing to compare against until the agent-path records carried an origin.

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

## Resolution

All four requested changes landed.

`seihou agent run` checks before `applyBaseline` and before any variable prompt, so a refusal
leaves the working tree and `.seihou/manifest.json` byte-identical — the property
`seihou-cli/test/Seihou/CLI/AgentGuardE2ESpec.hs` asserts by hashing the manifest and checking
`git status --porcelain` after each refused run. `seihou agent migrate` checks after the blueprint
is discovered and validated and before `planBlueprintMigrationChain`, so a substituted blueprint is
refused rather than having another library's edges planned against this project's source.

Point 2 was implemented one step further than written. The request asks for the resolved
`baseModules` to be checked; `seihou run` in fact guards the *resolved composition*, transitive
dependencies included, and declared base modules are only its roots. `loadComposition` therefore
moved out of `applyBaseline` into `handleAgentRun` as `loadBaselineComposition`, so the guard sees
the same module set the baseline would generate from and the composition is evaluated once per run.

Point 4's scoping rule is honoured on both commands. `agent run` checks the blueprint and its
baseline composition; `agent migrate` checks the blueprint alone, because migration mode applies no
baselines and checking modules it will not touch would refuse for unrelated artifacts. A blueprint
recorded in the manifest under a different name is ignored by both.

Two details differ from the request as written.

The blanket `--debug` exemption was applied to `agent migrate` only. The request justifies the
exemption on the grounds that `--debug` "contacts no provider, applies no baseline, and writes
nothing". That is true of `agent migrate` and false of `agent run`, which under `--debug` still
applies the baseline to the working directory and still records applied-blueprint provenance naming
the local blueprint's version; only the provider call is skipped. Exempting it would have left
[ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md)'s opening scenario
reachable through the one flag the change advertised as safe. The exemption's purpose — never
refuse a command that writes nothing — is preserved exactly where it applies, and the rule is now
stated in the ADR as "the check follows the writes, not the flag".

The command's identity record is read from receipts as well as from the applied-blueprint entry.
`agent migrate` writes receipts and never writes that entry, so a project that has only ever
migrated a blueprint records its identity exclusively in receipts; without the fallback the path
this request calls out as worst would have had nothing to compare against in exactly the projects
that use it.

`seihou status` now also reports a stale or substituted blueprint, so a developer can find out
before a command refuses — the passive signal this request correctly says is not sufficient on its
own, kept as a complement rather than a substitute.

The decision itself did not change, only its reach, so
[ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md) was amended rather than
joined by a second record restating the same judgement.
