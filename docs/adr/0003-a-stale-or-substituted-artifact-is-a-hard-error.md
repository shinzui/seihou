# ADR 0003 — Generating from a stale or substituted artifact is a hard error

- Status: Accepted
- Date: 2026-07-28

## Context

[ADR 0001](0001-manifest-is-a-checked-in-machine-independent-artifact.md)
establishes that `.seihou/manifest.json` is committed shared state describing
the project, and [ADR 0002](0002-artifact-identity-is-origin-url-plus-name.md)
establishes how it identifies the artifacts it was generated from. Both leave
open what seihou should *do* when the copy of an artifact installed on this
machine disagrees with what the manifest records.

The failure that matters is specific. Developer A upgrades `haskell-base` to
`2.0.0`, runs seihou, and commits both the regenerated files and the updated
manifest. Developer B pulls that commit but still has `1.4.0` installed. If
seihou regenerates, every file reverts to the older module's output and the
manifest is rewritten to say `1.4.0`. Nothing is corrupt, nothing errors, and
the regression arrives in review looking like an ordinary diff — which is
exactly why nobody catches it.

The same shape applies to identity rather than version: a module with the
recorded name installed from a different repository is a different module, and
generating from it substitutes one artifact for another silently.

## Decision

A command that is about to **generate** from an artifact refuses when the local
copy is older than, or came from somewhere other than, what the manifest
records. `--allow-downgrade` is the only override, and it still prints what it
is overriding.

Because the manifest describes the project and the install cache describes the
machine, the manifest wins. A machine may not silently override a project.

`Seihou.CLI.ManifestGuard` implements the comparison and the refusal for
`seihou run`, `seihou migrate`, `seihou agent run`, and `seihou agent migrate`.
`seihou update` reaches the same user-visible outcome by a different route — see
Consequences.

*Amended 2026-08-16 (`docs/plans/83-guard-the-agent-path-against-stale-and-substituted-artifacts.md`):*
the decision is unchanged; its reach now includes the agent path, which it did
not previously cover. Nothing about a blueprint exempts it. `seihou agent run`
applies the blueprint's baseline modules to the working directory — ordinary
modules generating ordinary files — and then rewrites the manifest to name the
blueprint it used, which is this ADR's opening scenario with a blueprint
substituted for a module. `seihou agent migrate` writes a receipt per edge, and
those receipts suppress future runs of the edges they name, so a blueprint of
the recorded name from a different repository would have its own library's
upgrade prompts run against this project's source. What is guarded is the
identity and version of the artifact being applied, not the determinism of its
output.

### Rejected: warn and continue

A warning is the natural-looking middle ground and is worse than useless here.
The whole problem is that the regression is invisible in review; a line of
warning text scrolled past in a build log does not make it visible. Worse, a
warning that is routinely ignored trains developers to ignore the next one. If
the situation is not serious enough to stop, it is not worth printing.

### Rejected: fetch the recorded version automatically

Auto-fetching looks helpful and is the most invasive option available. It would
make `seihou run` — a local, offline build command — perform network I/O, and
it would mutate `~/.config/seihou/installed/`, which is shared by every project
on the machine, as a side effect. A developer who ran seihou in one project
would find another project's modules changed underneath them, with no obvious
way to undo it. Seihou reports what to run and leaves the developer in control.

### Rejected: refusing a *newer* local copy

Only a strictly older local copy blocks. A newer one is the ordinary upgrade
path — `seihou upgrade` then `seihou run` — and treating it as a problem would
make the normal workflow require a flag.

## Consequences

A refusal costs nothing. It happens before the plan is computed, so the working
tree is byte-identical afterwards, which is what
`seihou-cli/test/Seihou/CLI/SharedManifestE2ESpec.hs` asserts by checking that
`git status --porcelain` is empty after a refused run.

`--allow-downgrade` prints the same blocks under a `! Proceeding anyway`
heading rather than falling silent. A deliberate downgrade is still a change to
shared state and belongs in the terminal and in the diff; silently honouring the
flag would hide precisely what the guard exists to make legible.

The refusal is scoped to the artifacts a command is actually about to generate
from. `seihou run` checks only the modules in the composition it is running, so
one uninstalled or stale module elsewhere in the project cannot block unrelated
work. This mirrors the line drawn for pending-migration detection. On the agent
path the same line means `seihou agent run` checks the blueprint plus every
module in its resolved baseline composition, and `seihou agent migrate` checks
the blueprint alone, because migration mode applies no baselines. A blueprint
recorded in the manifest under a different name is not checked by either.

A dry run is exempt; a command that merely skips one step is not. `seihou agent
migrate --debug` writes nothing at all, so it performs no check and stays usable
for inspecting a prompt on a machine that has never installed the artifact.
`seihou agent run --debug` skips only the provider call — it still applies the
baseline and still records applied-blueprint provenance — so it is checked like
any other run. The rule is that the check follows the writes, not the flag.

Advisory consumers never block. `seihou status`, pending-migration detection,
and `seihou update`'s same-version content comparison report what they cannot
resolve and carry on, so a developer with one missing module can still ask what
state the project is in. The division is: resolving *where* an artifact is is
`Seihou.Core.ArtifactRef`'s question, deciding *whether to generate from it* is
`Seihou.CLI.ManifestGuard`'s, and only the second one stops a command.

`seihou update` does not use the guard, and adding it would have been a
regression. It already refuses a backwards version move through
`validateVersionChange` (`candidate_downgrade`); it cannot substitute a
same-named artifact because it clones from the manifest's own recorded URL; and
it deliberately supports updating a project whose modules are not installed
locally, which the guard's unresolvable verdict would have broken. It has
`--allow-downgrade` for the override the user-visible promise requires, and
nothing else. The promise holds for all three commands; the mechanism differs
for one.

An artifact recorded with a `LocalOrigin` is reported as unverifiable rather
than blocked, per [ADR 0002](0002-artifact-identity-is-origin-url-plus-name.md).
Its version is still compared, because a version comes from the artifact's own
`module.dhall`.

This decision governs the generate path only. What may be written *into* the
machine-global install cache in the first place is a separate question with a
separate override flag, decided in
[ADR 0006](0006-the-install-cache-will-not-silently-substitute-an-artifact.md).
The two compose: the install-time refusal makes the substituted state hard to
reach, and this refusal catches it if a project reaches it anyway.

## References

- [ADR 0001](0001-manifest-is-a-checked-in-machine-independent-artifact.md)
- [ADR 0002](0002-artifact-identity-is-origin-url-plus-name.md)
- [ADR 0006](0006-the-install-cache-will-not-silently-substitute-an-artifact.md)
  — the same reasoning applied one layer earlier, at install time.
- `docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md`
- `docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md`
- `docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md`
- `docs/plans/83-guard-the-agent-path-against-stale-and-substituted-artifacts.md`
  — extends this decision to `seihou agent run` and `seihou agent migrate`.
- `docs/user/teams.md`
