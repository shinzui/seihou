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
`seihou run` and `seihou migrate`. `seihou update` reaches the same
user-visible outcome by a different route — see Consequences.

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
work. This mirrors the line drawn for pending-migration detection.

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

## References

- [ADR 0001](0001-manifest-is-a-checked-in-machine-independent-artifact.md)
- [ADR 0002](0002-artifact-identity-is-origin-url-plus-name.md)
- `docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md`
- `docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md`
- `docs/user/teams.md`
