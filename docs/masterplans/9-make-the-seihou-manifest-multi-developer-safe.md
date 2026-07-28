---
id: 9
slug: make-the-seihou-manifest-multi-developer-safe
title: "Make the seihou manifest multi-developer safe"
kind: master-plan
created_at: 2026-07-28T01:48:05Z
intention: "intention_01kyk6fnbyegxss8fqnf3j03tf"
---

# Make the seihou manifest multi-developer safe

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Vision & Scope

Seihou is a project scaffolding tool. When someone runs `seihou run <module>` inside a
project, seihou finds a *module* (a directory containing a `module.dhall` file that
declares variables, file-generation steps, and shell commands), generates files from it,
and then records what it did in a JSON file at `.seihou/manifest.json` inside the
project. That manifest is what makes later runs incremental: it remembers which files
seihou generated, which modules produced them, and which version of each module was
applied. Because it describes the project rather than the machine, teams check
`.seihou/manifest.json` into git alongside the code it describes.

Today that does not survive contact with a second developer. The manifest records where
each module lived *on the machine that ran seihou*, as an absolute filesystem path. A
manifest written on one laptop contains entries like
`/Users/shinzui/.config/seihou/installed/haskell-base`. When a teammate clones the
repository, that path does not exist for them — their home directory is different, and on
a Linux machine even the XDG configuration root differs. Any seihou command that needs to
re-read the module from the recorded path (`seihou migrate`, `seihou upgrade`,
`seihou update`) either fails outright or silently falls back to a different module than
the one the manifest describes. The manifest is, in practice, single-developer state that
happens to be committed to a shared repository.

There is a second, quieter failure. The manifest records the version of each applied
module, but nothing checks that version against what is installed locally before
regenerating. Suppose developer A upgrades the `haskell-base` module to version `2.0.0`,
runs `seihou run`, and commits both the generated files and the updated manifest.
Developer B pulls that commit but still has `haskell-base` version `1.4.0` installed in
`~/.config/seihou/installed/`. When B runs `seihou run`, seihou happily regenerates every
file from the older module and rewrites the manifest to say `1.4.0`. The project silently
regresses, and the regression looks like an ordinary diff in code review. Nothing warns
anybody.

After this initiative, three things are true that are not true today.

First, `.seihou/manifest.json` contains no absolute filesystem paths at all. Every module
and recipe reference in the manifest is recorded as a *portable artifact origin*: the git
URL the artifact was installed from together with its artifact name, or — for artifacts
that live inside the project at `.seihou/modules/<name>` — a repository-relative path.
Two developers on different operating systems who apply the same module produce the same
manifest bytes for those fields. A reviewer reading the manifest diff can tell exactly
which upstream module and version was applied.

Second, every seihou command that needs a module's source directory resolves it from that
portable origin against the local machine's search paths, rather than trusting a recorded
path. When the module is not installed locally, the command stops with a message that
names the module, names the git URL it came from, and gives the exact `seihou install`
command that fixes it — instead of a confusing "file not found" from deep inside a Dhall
evaluation.

Third, seihou refuses to silently downgrade. Before regenerating, `seihou run`,
`seihou update`, and `seihou migrate` compare the version recorded in the manifest against
the version of the artifact actually installed on this machine. If the local copy is
older, the command aborts and tells the developer to run `seihou upgrade`. An explicit
`--allow-downgrade` flag exists for the rare case where pinning back is intentional. The
same comparison catches an *origin mismatch*: a module with the same name installed from a
different git URL than the manifest records is a different module, and seihou says so
rather than generating from it.

The scope includes the manifest schema and its JSON encoding, the resolution layer that
maps a recorded origin back to a directory on this machine, the guard that compares
versions and origins before generation, an in-place upgrade path for manifests already
committed in the old format, and the user-facing documentation for teams sharing a
manifest.

The scope explicitly excludes several things. It does not introduce a lockfile separate
from the manifest — the manifest remains the single source of truth. It does not add
network fetching to `seihou run`; when a module is missing or stale, seihou reports what
to run rather than reaching out on its own. It does not change how generated *files* are
tracked (the `files` map is already keyed by project-relative paths and stays as is), nor
how baselines are stored (`.seihou/baselines/` is content-addressed by SHA-256 and is
already portable). It does not change the Dhall module format itself, and it does not
attempt to make blueprints (agent-driven generation) reproducible beyond recording their
origin the same way modules do.


## Decomposition Strategy

The work splits along a clean seam that already exists in the code: the manifest's
*serialized form* (what bytes land in `.seihou/manifest.json`, owned by
`seihou-core/src/Seihou/Manifest/Types.hs` and the record definitions in
`seihou-core/src/Seihou/Core/Types.hs`) versus the manifest's *consumers* (the CLI
commands under `seihou-cli/src/Seihou/CLI/` and `seihou-cli/src-exe/Seihou/CLI/` that read
a recorded path and hand it to a Dhall evaluator). Changing the serialized form is a
self-contained, heavily testable change; rewiring the consumers is mechanical but touches
seven command modules. Doing both in one plan would produce an ExecPlan with a dozen
milestones and no intermediate point where the tree is provably correct.

That gives the first two child plans. Plan 76 defines the portable origin type, teaches
the manifest encoder and decoder to write and read it, and makes every write site record
it — while keeping a compatibility shim so nothing breaks yet. Plan 77 replaces every read
of a recorded absolute path with a call into a new resolver, so that after plan 77 no
seihou command depends on a path recorded by another machine.

The third concern — refusing accidental downgrades — is genuinely separate: it is a policy
decision applied at command entry points, not a data-model change. It needs plan 76's
version-and-origin data to exist in the manifest and plan 77's resolver to find the local
copy, but its own code lives in one new module plus a handful of call sites. That is plan
78.

The fourth concern is the awkward one, and it is why this is a MasterPlan rather than an
ExecPlan: manifests written by earlier seihou versions are already committed in people's
repositories, containing another developer's absolute paths. Those manifests have to keep
working, and there has to be a deliberate, inspectable way to convert them. Bundling that
into plan 76 would mean plan 76 could not be validated in isolation, because the
conversion needs the resolver from plan 77 to figure out what a legacy path referred to.
So plan 79 owns backwards compatibility and the in-place upgrade, and depends on both.

The fifth is documentation and proof. The initiative's whole value is a workflow claim —
"two developers can now share a manifest safely" — and a claim like that is only credible
with an end-to-end test that actually simulates two machines and with user documentation
that tells teams what to commit and what to expect. Rolling that into the other plans
would scatter it; keeping it as plan 80 means there is one place where the promise is
demonstrated.

An alternative decomposition was considered and rejected: splitting by command
(`seihou run`, `seihou update`, `seihou migrate`, …) so each plan makes one command
multi-developer safe. That was rejected because every command shares the same manifest
type and the same resolver, so per-command plans would each have to define — and then
reconcile — the same shared artifact. The chosen split follows MASTERPLAN.md's principle
of grouping by functional concern rather than by file, and it keeps the shared type owned
by exactly one plan.

Following the ADR workflow in `agents/skills/exec-plan/ADR.md`: this repository has **no**
`docs/adr/` directory and therefore no local ADR corpus. No relevant ADR exists to cite.
This initiative is a strong candidate for creating the first ADRs, because it establishes
durable constraints that outlive the plans — specifically, that the manifest is a
checked-in, machine-independent artifact, and that manifest identity is keyed on origin URL
plus artifact name. Those two decisions are called out in Integration Points below as ADR
candidates, to be written during plan 76 and refined at the end of plan 80.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 76 | Record portable artifact origins in the manifest | docs/plans/76-record-portable-artifact-origins-in-the-manifest.md | None | None | Complete |
| 77 | Resolve manifest artifact origins to local directories | docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md | EP-76 | None | Not Started |
| 78 | Refuse accidental module downgrades and origin mismatches | docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md | EP-76, EP-77 | None | Not Started |
| 79 | Upgrade legacy absolute-path manifests in place | docs/plans/79-upgrade-legacy-absolute-path-manifests-in-place.md | EP-76, EP-77 | EP-78 | Not Started |
| 80 | Document and end-to-end verify the shared-manifest workflow | docs/plans/80-document-and-end-to-end-verify-the-shared-manifest-workflow.md | EP-76, EP-77, EP-78, EP-79 | None | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3).


## Dependency Graph

Plan 76 is the foundation and has no dependencies. It introduces the `ArtifactOrigin`
type in `seihou-core/src/Seihou/Core/Types.hs`, bumps the manifest schema version from 5
to 6, and changes what `seihou run`, `seihou update`, and `seihou agent run` write into
`.seihou/manifest.json`. Nothing else can be built until that type and that encoding
exist, because every other plan either reads the new field or converts to it.

Plan 77 has a hard dependency on plan 76. It cannot compile without the `ArtifactOrigin`
type, and its entire purpose — turning a recorded origin back into a directory on this
machine — is meaningless until origins are recorded. Plan 77 is where the absolute-path
fields stop being consulted: it rewires
`seihou-cli/src-exe/Seihou/CLI/Run.hs`, `seihou-cli/src/Seihou/CLI/Update.hs`,
`seihou-cli/src/Seihou/CLI/Migrate.hs`, `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs`,
`seihou-cli/src-exe/Seihou/CLI/Remove.hs`, `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`,
and `seihou-cli/src-exe/Seihou/CLI/Status.hs` to call the resolver.

Plan 78 has hard dependencies on both 76 and 77. The downgrade guard compares the version
recorded in the manifest (which plan 76 makes reliable and origin-qualified) against the
version of the artifact found locally (which plan 77's resolver locates). Without 77 the
guard would have to re-implement discovery; without 76 it would have no trustworthy
identity to compare against, since two different modules can share a bare name.

Plan 79 has hard dependencies on 76 and 77 and a soft dependency on 78. It converts
manifests written in schema version 5 or earlier, whose only record of a module's source
is another developer's absolute path. Converting such an entry means asking "what artifact
does this path refer to?", which is exactly plan 77's resolver run in reverse, plus a
fallback that matches on artifact name. The dependency on 78 is soft: plan 79's upgrade
command should refuse to write an upgraded manifest that would immediately trip the
downgrade guard, but if 78 is not yet complete, plan 79 can be implemented and validated
without that interaction and the check added afterwards.

Plan 80 depends on all four. Its end-to-end test simulates two developers by running
seihou twice against two different fake home directories over the same project tree, which
requires portable origins (76), local resolution (77), the downgrade refusal (78), and the
legacy-manifest upgrade (79) to all be in place before the scenario is meaningful.

Nothing in this initiative can run fully in parallel, because 76 defines a type that 77,
78, and 79 all consume. However, once 76 and 77 are complete, plans 78 and 79 touch
largely disjoint code — 78 adds a guard module and wires it into command entry points,
while 79 adds a decoder path and a new subcommand — so they can proceed concurrently by
two contributors provided they coordinate on the one shared surface named in Integration
Points below.


## Integration Points

**The `ArtifactOrigin` type.** This is the central shared artifact. It is defined by plan
76 in `seihou-core/src/Seihou/Core/Types.hs` and its JSON encoding is defined by plan 76
in `seihou-core/src/Seihou/Manifest/Types.hs`. Plans 77, 78, 79, and 80 all consume it and
none of them may change its shape without a MasterPlan update recorded in the Decision Log
below. The agreed shape, which every child plan restates in full so it can be implemented
standalone, is a sum type with three constructors: `RemoteOrigin` carrying a git URL, an
artifact name, and an optional registry repository name, for artifacts installed from a
git source into `~/.config/seihou/installed/<name>`; `ProjectOrigin` carrying a
repository-relative path, for artifacts that live inside the project under
`.seihou/modules/<name>`; and `LocalOrigin` carrying only an artifact name, for artifacts
discovered by name in the user's `~/.config/seihou/modules/` directory with no recorded
git provenance. `LocalOrigin` is deliberately weak — it is the honest representation of
"this came from somewhere on that developer's machine and we cannot say where" — and plan
78 treats it as unverifiable rather than pretending otherwise.

**The manifest schema version constant.** `currentManifestVersion` in
`seihou-core/src/Seihou/Manifest/Types.hs` is currently `5`. Plan 76 bumps it to `6` and
owns the doc comment explaining why. Plan 79 owns the decoding of versions 1 through 5 and
must not bump the constant again. If plan 78 or 80 discovers a need for a further field,
the bump to `7` is a MasterPlan-level decision recorded below, not a unilateral change.

**The resolver interface.** Plan 77 defines the module `Seihou.Core.ArtifactRef` in
`seihou-core/src/Seihou/Core/ArtifactRef.hs`, exporting a resolution function that takes
the standard search paths and an `ArtifactOrigin` and returns either a resolution error or
the absolute directory on this machine that holds the artifact's `module.dhall`. Plans 78,
79, and 80 consume that function; plan 77 owns its signature and its error type. The error
type must be renderable to a user-facing message, because plan 78 embeds resolution
failures in its guard output and plan 80 asserts on the exact wording.

**The `.seihou/manifest.json` on-disk contract.** Every plan writes to or reads from this
file. Plan 76 owns the encoder; plan 79 owns the legacy decoder; plans 78 and 80 assert on
the contents. The invariant all four must preserve is that a freshly written manifest
contains no string beginning with `/` or matching a Windows drive prefix in any origin
position — plan 80 encodes that invariant as an automated test so later work cannot
regress it.

**The `.seihou-origin.json` install-metadata file.** Written by `installModuleDir` in
`seihou-cli/src/Seihou/CLI/InstallShared.hs` into
`~/.config/seihou/installed/<name>/.seihou-origin.json`, it already records `sourceUrl`,
`repoName`, `version`, `installedAt`, and `tags`. Plan 76 reads it to build a
`RemoteOrigin` at manifest-write time; plan 77 reads it during resolution to confirm a
locally installed artifact really came from the recorded URL; plan 78 reads its `version`
field as one input to the downgrade comparison. No plan changes its format. Because this
file lives outside the project and is per-machine, no plan may treat it as authoritative
about what the *project* expects — that is the manifest's job.

**ADR candidates.** Two decisions in this initiative are durable enough to outlive the
plans and should become the repository's first ADRs under `docs/adr/`. The first is that
`.seihou/manifest.json` is a checked-in, machine-independent project artifact, and that
absolute filesystem paths are therefore forbidden in it — this constrains all future
manifest fields, not just the ones changed here. The second is that artifact identity in
the manifest is keyed on origin URL plus artifact name rather than on bare name or content
hash, together with the rejected alternatives and why. Plan 76 creates both ADRs since it
makes the decisions concrete; plan 80 revisits them during the final distillation pass and
adds any constraint that implementation revealed.


## Progress

Track milestone-level progress across all child plans. Each entry names the child plan
and the milestone. This section provides an at-a-glance view of the entire initiative.

- [x] EP-76: `ArtifactOrigin` type and JSON encoding exist; round-trip tests pass (2026-07-28)
- [x] EP-76: `seihou run`, `seihou update`, and `seihou agent run` record origins; manifest schema is version 6 (2026-07-28)
- [x] EP-76: First two ADRs written under `docs/adr/` (2026-07-28)
- [ ] EP-77: `Seihou.Core.ArtifactRef` resolver and its error type exist with unit tests
- [ ] EP-77: All seven CLI consumers resolve through the resolver instead of a recorded path
- [ ] EP-78: Version and origin comparison module exists with unit tests
- [ ] EP-78: `seihou run`, `seihou update`, and `seihou migrate` refuse downgrades; `--allow-downgrade` overrides
- [ ] EP-79: Schema versions 1–5 decode into `ArtifactOrigin` without data loss
- [ ] EP-79: `seihou manifest upgrade` converts a committed legacy manifest in place, with `--dry-run`
- [ ] EP-80: Two-developer end-to-end test in the CLI test suite passes
- [ ] EP-80: `docs/user/teams.md` written; CHANGELOG and architecture overview updated
- [ ] EP-80: ADR distillation pass complete


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments, or unexpected
interactions between child plans. Provide concise evidence.

- **EP-76 and EP-77 are less separable than the decomposition assumed.** The
  Decomposition Strategy above claims plan 76 changes the serialized form while
  "commands still find modules the way they do today". That is false for
  `seihou update`, which reads the recorded `source` path *off a decoded manifest*
  in three places: `requirementsFor` in
  `seihou-cli/src/Seihou/CLI/Update/Source.hs` (to locate `.seihou-origin.json`
  and to stage a local fallback), `compareArtifact` inside `versionEvidence` in
  `seihou-cli/src/Seihou/CLI/Update.hs` (to hash the currently-applied artifact),
  and `sameApplication` inside `isUpdateNoOp` in the same file (to decide whether
  an application changed). The moment the decoder stops populating `source`, all
  three misbehave.

  Evidence: with only the encoder changed, two `seihou-cli-test` cases failed. The
  no-op third run of `reuses accepted inputs, keeps dry-run read-only, and
  publishes one coherent update` reported
  `updatedApplications = [ApplicationId "9ce3f1c8…"]` and
  `versions: [{from: "2.0.0", to: "2.0.0", sameVersionContentChanged: true}]`,
  because `hashArtifactDirectory ""` throws and the handler reads a throw as
  "content changed".

  EP-76 repaired all three onto the recorded origin, using a minimal
  CLI-internal helper `artifactDirectoryOnThisMachine` in
  `seihou-cli/src/Seihou/CLI/Update/Source.hs` rather than creating
  `Seihou.Core.ArtifactRef` early, so EP-77 keeps ownership of that module's
  signature and error type. **EP-77 must delete that helper** and move its three
  call sites onto the real resolver; the helper carries a comment saying so.
  The decomposition itself still holds — the boundary just leaks slightly, and
  EP-77 inherits a small, named debt rather than a surprise.

- **The `ArtifactOrigin` shape shipped exactly as agreed in Integration Points.**
  Three constructors, `RemoteOrigin` / `ProjectOrigin` / `LocalOrigin`, with the
  agreed payloads and a tagged JSON encoding. No child plan needs a MasterPlan
  update to consume it.

- **`AppliedBlueprint` needs no origin.** EP-76 confirmed that
  `seihou-core/src/Seihou/Core/Types.hs` records a blueprint's name, version,
  baseline module names, and prompt metadata, but no path, so it was already
  portable. EP-80's no-absolute-paths assertion does not need to cover it.

- **EP-79 has more to restore than the plan text implies.** EP-76's version-6
  guard invalidated eight existing back-compat specs in
  `seihou-core/test/Seihou/Manifest/TypesSpec.hs` that asserted schema versions 1
  through 4 decode with empty defaults. They were replaced with two specs
  asserting the refusal message. EP-79 should restore positive decoding coverage
  for versions 1–5, not merely add new tests alongside them.


## Decision Log

Record every decomposition or coordination decision made while working on the master
plan.

- Decision: Key manifest artifact identity on the git origin URL plus the artifact name,
  not on the bare artifact name alone and not on a content hash of the module directory.
  Rationale: A bare name collides — two registries can both publish a module called
  `haskell-base`, and a manifest that records only the name cannot tell a developer they
  have the wrong one installed. A content hash is precise but changes on every edit to the
  module, so it cannot express "the same module, one version newer", which is exactly the
  relationship the downgrade guard needs to reason about. The git URL plus name is stable
  across versions, already captured at install time in
  `~/.config/seihou/installed/<name>/.seihou-origin.json`, and is meaningful to a human
  reading a manifest diff. Confirmed with the user before decomposition.
  Date: 2026-07-28

- Decision: A locally-installed artifact that is older than the version recorded in the
  manifest causes a hard error, with an explicit `--allow-downgrade` flag as the only
  override. Seihou does not auto-fetch the recorded version.
  Rationale: The failure this initiative exists to prevent is a *silent* regression that
  looks like an ordinary code-review diff. A warning would be ignored; auto-fetching would
  make `seihou run` perform network I/O and mutate the developer's global install
  directory as a side effect of a local build command, which is surprising and hard to
  undo. A hard error with a named remedy (`seihou upgrade`) keeps the developer in
  control, and the escape hatch covers deliberate pinning. Confirmed with the user before
  decomposition.
  Date: 2026-07-28

- Decision: Decompose into five child plans split by functional concern — serialized form
  (EP-76), local resolution (EP-77), downgrade policy (EP-78), legacy compatibility
  (EP-79), and documentation plus end-to-end proof (EP-80) — rather than one plan per CLI
  command.
  Rationale: All the affected commands share one manifest type and one resolver.
  Per-command plans would each have to define and then reconcile the same shared artifact,
  which MASTERPLAN.md's decomposition principles warn against. The chosen split gives each
  plan an independently verifiable outcome and keeps the shared `ArtifactOrigin` type
  owned by exactly one plan.
  Date: 2026-07-28

- Decision: Backwards compatibility for already-committed manifests is its own plan
  (EP-79) rather than part of EP-76.
  Rationale: Converting a legacy entry means answering "which artifact does this foreign
  absolute path refer to?", which needs EP-77's resolver. Folding it into EP-76 would mean
  EP-76 could not be validated in isolation, violating the requirement that each child
  plan be independently verifiable.
  Date: 2026-07-28

- Decision: Introduce a third origin constructor, `LocalOrigin`, carrying only an artifact
  name, for modules discovered in `~/.config/seihou/modules/` with no git provenance.
  Rationale: `seihou-core/src/Seihou/Core/Module.hs` searches three roots — the project's
  `.seihou/modules/`, the user's `~/.config/seihou/modules/`, and the install cache
  `~/.config/seihou/installed/`. Only the third has `.seihou-origin.json`. Modelling the
  second as a `RemoteOrigin` with a fabricated URL would be a lie, and modelling it as a
  `ProjectOrigin` would produce a path that does not exist in the repository. An explicit
  weak constructor lets EP-78 report honestly that such an artifact's provenance cannot be
  verified.
  Date: 2026-07-28

- Decision: This repository has no `docs/adr/` directory today; EP-76 creates it along
  with the initiative's first two ADRs.
  Rationale: `agents/skills/exec-plan/ADR.md` governs the workflow and both the exec-plan
  and master-plan skills expect durable decisions to be promoted there. The two decisions
  above (manifest is machine-independent; identity is origin URL plus name) constrain all
  future manifest work and belong in durable project memory rather than in a plan that
  will be marked complete.
  Date: 2026-07-28

- Decision: Allow EP-76 to land a minimal, explicitly temporary origin-to-directory
  helper (`artifactDirectoryOnThisMachine` in
  `seihou-cli/src/Seihou/CLI/Update/Source.hs`) rather than either leaving the tree
  with a broken `seihou update` or creating `Seihou.Core.ArtifactRef` inside EP-76.
  Rationale: EP-76 discovered that three readers in `seihou update` consume the
  recorded `source` path off a decoded manifest, so schema version 6 cannot land
  without answering "which directory does this origin name here?" (see Surprises &
  Discoveries). Creating `Seihou.Core.ArtifactRef` in EP-76 would claim the module,
  signature, and error type this MasterPlan assigns to EP-77, forcing EP-77 to
  rewrite them. A single CLI-internal helper keeps the shared interface unclaimed,
  and EP-77's scope grows only by "delete this helper and move its three call sites",
  which is smaller than the rewiring EP-77 already owns. The decomposition is
  unchanged; no plan is split, merged, or reordered.
  Date: 2026-07-28

- Decision: `docs/adr/` uses the repository's plain numbered-Markdown convention
  with a `Status`/`Date` header rather than OKF frontmatter.
  Rationale: `agents/skills/exec-plan/ADR.md` says to inspect `mori.dhall` for an
  OKF bundle whose path is `docs/adr` and, when none exists, to preserve the
  repository's established filesystem convention without inventing Mori identity as
  an incidental plan edit. `mori show --full` reports zero bundles for this project,
  and there was no prior `docs/adr/` corpus, so EP-76 established the plain
  convention. Migrating to the shared profile is separate work.
  Date: 2026-07-28


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original vision. Before marking the MasterPlan complete,
distill durable project context from this MasterPlan and its child ExecPlans into
docs/adr/. Keep task-local execution and coordination details here.

(To be filled during and after implementation.)
