# ADR 0009 — Seihou reads no package-manager format; the artifact declares the command

- Status: Accepted
- Date: 2026-08-16

## Context

`seihou agent migrate` runs a library's upgrade guidance across a version
window. Both ends of that window were mandatory flags, typed by hand:

```bash
seihou agent migrate keiro-upgrade --from 2.4.0 --to 3.0.0
```

`docs/user/blueprint-migrations.md` gave the reason plainly: "Seihou is
language-agnostic and does not read Cabal, npm, Cargo, or Maven files to guess
which version you are on or where you are going."

Being language-agnostic is right and is not up for revision. Seihou scaffolds
Haskell, TypeScript, Nix, and anything else a module author targets; a set of
built-in dependency readers would grow one branch per ecosystem, each of which
can be wrong in a version seihou has never seen, and each of which becomes a
compatibility obligation the moment a consumer depends on it.

But *making the user do the lookup* is not the only way to get there, and the
cost of that lookup rises sharply once a chain can cross libraries
([ADR 0008](0008-an-entailed-migration-edge-is-owned-by-the-blueprint-that-declares-it.md)).
A consumer knows which keiro version they are on. Asking them which kiroku
version keiro pulls in transitively asks them for something they have no reason
to know — and the whole point of entailment is that they should not have to.

## Decision

Seihou reads no package-manager format, in any ecosystem, ever. When a version
must be discovered from a project, **the artifact declares the command that
reads it and seihou runs that command**.

The first instance is `versionProbe` on `schema/Blueprint.dhall`: an optional
shell string, run in the project root, whose output supplies the default `--to`
for `seihou agent migrate`.

```dhall
versionProbe = Some "jq -r .dependencies.my-library package.json"
versionProbe = Some "nix eval --raw .#keiroVersion"
```

The blueprint's author is the only party who knows where their library's version
lives in a consumer's project, and they already ship the upgrade knowledge; the
lookup command belongs beside it. This is the same shape the schema already uses
for `RunCommand` migration operations and for command-derived variables — "the
artifact author supplies a shell command" is an established pattern here, and a
version probe is the read-only member of that family.

Four properties are part of the decision rather than of the implementation:

- **A probe is advisory, and a broken one degrades rather than fails.** A
  nonzero exit, unparseable output, or a timeout is reported — command, exit
  code, output — and the command falls through to requiring the explicit flag.
  The person holding the failure did not write the probe and must keep a way
  through.
- **An explicit flag always wins**, and is never overridden by a probe. Nothing
  that worked before a probe existed changes behaviour when one is added
  upstream.
- **A probe must be read-only**, because it runs on someone else's project
  without their review, and it runs under `--debug`.
- **Anything seihou infers is reported with its source**, before the inference
  is acted on. A window silently off by one release runs the wrong agent
  sessions against the user's source, and the report is the only place that is
  visible.

### The two ends of a window come from different places

`--to` comes from the probe; `--from` comes from the receipt ledger. This is not
symmetric and must not be made so.

The probe reads how far the *dependency* has been bumped in this project. The
receipt ledger records how far the *source* has been migrated. The normal
workflow is to bump the dependency and then carry the source up to it, so at the
moment the command runs, the lockfile already names the target and the receipts
name the start. Using the probe for `--from` would report nothing to do for
every project that bumped its lockfile first — that is, for the workflow the
feature exists to serve.

The `--from` half is an application of
[ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md) rather than
a new source of truth: the manifest already records what was applied, so no new
state is persisted and no lockfile is introduced. Only receipts recorded
`MigrationApplied` count. A `MigrationNotApplicable` receipt
([ADR 0007](0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md)) records
that an edge was considered and this project did not need it, which says nothing
about how far the source has been carried; counting it would start the window
above edges that never ran and skip them permanently.

### Rejected: built-in ecosystem readers

Seihou could detect `package.json`, `cabal.project`, `Cargo.toml`, `flake.lock`,
`pom.xml` and read a dependency's version directly. This is what the sentence in
the documentation was refusing, and it is still refused.

Every reader is a parser for a format seihou does not own, versioned by someone
else, with per-ecosystem resolution rules — workspaces, overrides, lockfile
versus manifest, transitive versus direct. A wrong answer here is worse than no
answer, because it silently runs the wrong upgrade edges against real source.
And the set is unbounded: adding scaffolding for a new ecosystem would newly
require a dependency reader for it.

Declaring the command inverts the maintenance: the person who knows the answer
writes one line, in their own repository, versioned with the library it
describes.

### Rejected: extending this to `seihou migrate`

Deterministic module migrations plan their window from what the manifest records
about an applied module — a version seihou itself wrote. There is nothing to
discover, so there is nothing to probe. This decision covers versions that live
in a project's own dependency declarations, which is a blueprint-side concern.

## Consequences

The ordinary invocation becomes `seihou agent migrate keiro-upgrade`, and the
consumer is asked for a version only when seihou genuinely cannot know one — the
first run in a project, or a blueprint whose author declared no probe. Both
refusals name the flag that resolves them, and the first-run message explains
what seihou does not know rather than complaining about what was not typed.

`--debug` for `agent migrate` gains its single exception to contacting nothing:
the probe runs. The window decides which edges are rendered, so a debug run that
skipped it would preview a different chain than the real one — diverging in
exactly the way that makes a dry run worthless. This is consistent with the rule
the guard follows, that a check tracks what a command *writes* rather than which
flag was passed; a probe writes nothing.

Declaring a probe is optional and additive. Blueprints published before
`versionProbe` existed keep working unchanged, and a consumer of one passes
`--to` exactly as before.

The principle generalises beyond this field. When some future command needs a
fact that lives in a project's ecosystem-specific files, the answer is a
declared command on the artifact that knows about it — not a reader inside
seihou, and not a new file for seihou to persist.

## References

- [ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md) — why the
  inferred `--from` reads existing receipts instead of new state.
- [ADR 0007](0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md) — the
  outcome that must not count as migration progress.
- [ADR 0008](0008-an-entailed-migration-edge-is-owned-by-the-blueprint-that-declares-it.md) —
  the cohort chains that made a hand-typed window untenable.
- `docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md`
- `docs/plans/86-infer-the-blueprint-migration-version-window.md`
- `docs/user/blueprint-migrations.md` — "Supply a version probe" and "How the
  version window is inferred".
