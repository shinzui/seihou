---
id: 108
slug: restore-module-declared-checkout-effects-without-reapplying-modules
title: "Restore module-declared checkout effects without reapplying modules"
kind: exec-plan
created_at: 2026-10-15T23:30:13Z
intention: "intention_01m50b28ccem2axbbn5tj3k1wt"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-15T23:30:13Z
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-15T23:38:46Z
      mode: "other"
      note: "Complete the code-grounded plan for module-declared checkout effects, portability, legacy compatibility, real consumer adoption and published team acceptance."
---

# Restore module-declared checkout effects without reapplying modules


This ExecPlan is a living document. Keep Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective current. It follows the repository's
`agents/skills/exec-plan/PLANS.md` specification.


## Purpose / Big Picture


A module has effects on the machine where it runs. Git carries generated project
files and the manifest to another checkout, but does not carry those local effects.
A developer must be able to reproduce the module's declared local setup with
`seihou sync`, without applying the module again. The module specification determines
the work; Seihou must not guess it from directory names, scan for skills, recognize
shell-command patterns, or substitute a newer module version.

This plan owns the complete correction, including schema, compiler, manifest,
execution, existing-project adoption, producer publication, documentation, runtime
release, and verification using an executable the team can install. It replaces
the unfinished delivery approach in [plan 107](107-adopt-manifest-owned-skill-links-in-agent-seihou-and-verify-fresh-clone-sync.md)
and builds on the declarative-link engine in [plan 105](105-rebuild-checkout-local-symlinks-from-the-manifest-without-upgrading-artifacts.md).
Integration gaps, usability failures, and defects in this acceptance remain work
in this plan. Do not close an engine milestone as delivery or create another plan
for an omitted part of this outcome. No implementation or release is authorized by
merely writing this plan.

The normal workflow has two distinct intentions. A project maintainer applies a
module, or updates an existing applied module, accepts its normal preview, and
commits the generated files, baselines, ignore rules, and manifest. That application
records the complete resolved checkout setup from the module and its dependencies.
Another developer receives that commit through Git and runs exactly:

```sh
seihou sync
```

The command reproduces the recorded checkout effects. It needs no installed
producers, configuration prompts, transitive module names, or manifest/index edits.
Repeating it repairs declarative outputs and reruns explicitly repeatable checkout
commands. Seihou does not fetch producers, upgrade artifacts, apply migrations,
regenerate managed files, or rewrite the manifest in this workflow. A declared shell
command may itself use the network or external tools; the runtime must not claim
that arbitrary module-supplied shell is offline, read-only, or reversible.

One-time adoption by existing projects is part of delivery, not a prerequisite
silently performed by a test. For the existing planning-skill application the
maintainer uses ordinary `seihou update master-plan`, reviews and accepts the
necessary changes, and commits them through normal Git collaboration. Update owns
source/dependency resolution, saved inputs, necessary schema preparation and
eligible tracked-link adoption. Other team members only need `seihou sync` after
receiving that commit. Preserve unrelated applications and edits. If this ordinary
update still demands manual dependency enumeration, JSON editing, index surgery,
or an unrelated upgrade, fix that friction here before declaring adoption complete.


## Progress


- [ ] Milestone 1: a minimal module-defined checkout command and declarative link survive application and a fresh clone; ordinary sync executes only the recorded local setup, with legacy command behavior preserved and old-runtime refusal demonstrated.
- [ ] Milestone 2: real producer specs and normal adoption work from both the original schema-6 consumer and the partially adopted schema-9 consumer; all intended destinations are verified by name and target, followed by a teammate clone with empty caches.
- [ ] Milestone 3: composition, persistence, update/removal, retry, compatibility and failure contracts pass the focused and full suites, including a non-skill consumer and supported native platforms.
- [ ] Milestone 4: help, agent guidance, diagnostics and ADRs describe one coherent workflow; distribution checks and the semantic guidance audit pass against the release candidate.
- [ ] Milestone 5: schema, producers, runtime and consumer adoption are delivered in dependency order; the installable released executable repeats the untouched-consumer and teammate acceptance, with evidence identifying exact revisions and artifacts.

Planning baseline: source HEAD was `104bda6` during investigation. The earlier
0.10.2.0 proposal and its prepared archives test the withdrawn update-inside-sync
approach; they are not acceptance or releasable artifacts for this plan. Reassess
versions from actual upstream state at implementation time. Existing work remains
in the tree until implementation deliberately replaces it; do not blindly revert
whole commits containing unrelated guidance improvements.


## Surprises & Discoveries


The published `link-skill` 0.3.0 specification declares `.claude/skills/<name>`
and `.agents/skills/<name>`, but never `.codex/skills/<name>`. Its ignore preparation
also omits `.codex`. Read-only inspection of `mori://shinzui/haskell-nix` on yujin
at consumer revision `529fd6d` found those four declarations and four correct links
for `exec-plan` and `master-plan`; both Codex links were absent. The runtime reported
`seihou v0.10.1.0 (104bda6)`, demonstrating why a package version alone cannot identify
a source build. The earlier four-link tests mirrored the incomplete producer spec
and did not prove the user's expected result.

The current runtime has `StepLifecycle = Managed | Seed | Checkout`, but validation
allows `Checkout` only with the symlink strategy. `CheckoutOutputSpec` has one variant,
`DirectorySymlink`. A `Command` has `run`, `workDir`, and `condition`, with no execution
lifecycle. Successful `CommandReceipt` records are portable history, not evidence
that a local effect exists in another checkout.

A decoder experiment with released Seihou `0.10.1.0 (c3bb42b)` establishes an important
compatibility constraint. A temporary, valid versioned module with an extra command
field `lifecycle = Some "checkout"` passed `validate-module` with exit 0: the old
runtime ignored the extra field. A command record with a tagged `action` instead
of the old `run` field failed extraction with exit 1. Neither experiment executed
a shell command. An optional extra field alone is therefore not a safe public
encoding for this feature. Preserve this negative control in executable tests.


## Decision Log


Decision (2026-10-15): the module spec is authoritative. Compile checkout setup
when applying or updating the module and record the resolved instructions in the
existing manifest. Sync consumes that applied specification without resolving
modules or consulting current configuration. This preserves the team contract and
makes results independent of a developer's producer cache.

Decision (2026-10-15): extend the existing checkout mechanism with explicitly
repeatable commands; retain typed directory-link observation and reconciliation.
Do not build a generic plugin resource scheduler, a directory-discovery service,
a new lockfile, or a second machine-local receipt database. Ordinary command
receipts retain their current meaning and never suppress checkout commands.

Decision (2026-10-15): use a tagged command action in the new Dhall schema, with
application and checkout variants. Continue accepting the legacy record containing
`run : Text` in the new runtime, interpreting it as application execution. The
public example is specified below. This is a deliberate schema API change to ensure
that old binaries reject new commands rather than silently misclassifying them.

Decision (2026-10-15): remove the recent sync-to-update fallback. An empty output
map is not authority to upgrade a composition, and a nonempty map does not establish
that a producer implements the intended feature. Legacy adoption belongs to normal
project maintenance, once per project, and is included in this delivery.

Decision (2026-10-15): the explicit invocation of sync executes checkout commands
recorded by trusted project specs. This intentionally extends ADR 0018's previous
no-shell sync boundary; it does not replay historical receipts. Do not install
automatic hooks or claim sync is safe for automatic execution of arbitrary repository
shell. Update the ADR and help before release. Dry-run executes no commands or probes.

Decision (2026-10-15): checkout commands must be repeatable and must keep their
intended writes outside managed/tracked project state. This is a producer contract,
not a sandbox guarantee. Seihou can validate declared working directories and its
own filesystem operations; it cannot prove the behavior of an arbitrary shell
program or roll it back. Report partial execution accurately and leave retry under
the same ordinary sync command.


## Outcomes & Retrospective


The plan is authored; implementation and delivery remain open. The acceptance is
about reproducing module-defined local effects across checkouts, not merely adding
a missing tool directory. Preserve the existing useful link engine, remove the
incorrect update orchestration, and judge completion by published producer/consumer
behavior. Record implementation evidence here as milestones are actually accepted.


## Context and Orientation


A module is a Dhall specification containing generation steps, commands, variables,
and dependencies. A composition is a root module or recipe plus its dependencies.
A module instance is one invocation distinguished by dependency-supplied variables;
the same module can appear more than once with different inputs. An application is
the recorded top-level composition in `.seihou/manifest.json`. These distinctions
matter: filtering by a bare module name loses parameterized instances and their
ordering or ownership.

`seihou-core/src/Seihou/Core/Types.hs` defines `Module`, `Command`, `StepLifecycle`,
`Operation`, `AppliedComposition`, `AppliedInstanceState`, `CommandReceipt`, and
`CheckoutOutputRecord`. `seihou-core/src/Seihou/Dhall/Eval.hs` evaluates a module and
extracts its record fields directly; `commandDecoder` and `stepDecoder` are the
compatibility boundaries. `evalModuleFromFile` must force any newly decoded enum
fields within its existing exception boundary. `seihou-core/src/Seihou/Core/Module.hs`
validates specs, including `checkCheckoutSteps` and ordinary command validation.

`seihou-core/src/Seihou/Composition/Resolve.hs` resolves dependencies and inputs;
`Composition/Instance.hs` defines qualified instance identity. `Composition/Plan.hs`
compiles instances in dependency order. `seihou-core/src/Seihou/Engine/Plan.hs`
contains `compilePlan`, `compileStep`, and `compileCommands`. It evaluates `when`
conditions and substitutes resolved variables, producing `CheckoutOutputOp` for
checkout links and `RunCommandOp` for shell commands. Do not introduce a second
compiler with different substitution, condition, validation, or ordering semantics.

`seihou-cli/src/Seihou/CLI/CommandExecution.hs` selects and executes rendered commands.
`RunChangedCommands` skips matching successful receipts; `RunAllCommands` executes
them, and `DisableCommands` suppresses execution. `seihou-cli/src-exe/Seihou/CLI/Run.hs`
persists generated state before its command phase. `seihou-cli/src/Seihou/CLI/Update.hs`
plans whole applications, reuses saved inputs, and coordinates transactional updates,
including `planCheckoutUpdate`, `applyAcceptedPlan`, and `applyUpdateCheckout`.
Its existing `replaceCheckoutApplications` path already replaces selected owners'
complete link declarations while retaining other owners. Use the analogous application
boundary for checkout command replacement; do not append stale commands forever.

`seihou-core/src/Seihou/Core/Checkout.hs` owns pure declaration/observation/planning
rules. `seihou-core/src/Seihou/Engine/Checkout.hs` observes paths and executes checked
link mutations. `seihou-cli/src/Seihou/CLI/CheckoutSync.hs` reads the manifest and
currently restores links. `seihou-cli/src-exe/Seihou/CLI/Sync.hs` currently adds the
incorrect empty-map adoption fallback through `withCheckoutAdoption` in the update
service. Remove that dependency while preserving truthful status and link summaries.
`seihou-cli/src-exe/Seihou/CLI/Status.hs` must remain observational.

The manifest codec and capability registry are in
`seihou-core/src/Seihou/Manifest/Types.hs`, duplicate-aware raw decoding is in
`Manifest/JSON.hs`, and adjacent schema transforms are in `Manifest/Upgrade.hs`.
The current manifest schema is 9. Schema 10 is the intended next version if still
unallocated when implementation starts; otherwise use the next contiguous version
and update every example and capability reference together.

The authoritative Dhall schema is `mori://shinzui/seihou-schema/packages/seihou-schema`.
The relevant project-relative sources are `Command.dhall`, `Module.dhall`, and
`Removal.dhall` in `mori://shinzui/seihou-schema` (file-artifact URIs pending).
The runtime's `schema/` is a submodule of that repository, and its Nix schema input
must agree with the submodule. Discover its checkout using Mori; change and publish
the owning schema repository, rather than leaving an unpublished submodule edit.

The producer is `mori://shinzui/agent-seihou`, especially
`mori://shinzui/agent-seihou/templates/link-skill`,
`mori://shinzui/agent-seihou/templates/exec-plan`, and
`mori://shinzui/agent-seihou/templates/master-plan`. Its project-relative
`tests/checkout-links.test.ts` currently expects two tool destinations per skill
(file-artifact URI pending). Its parent modules declare explicit dependency
bindings; verify custom source names against those bindings instead of assuming
that renaming a source automatically renames a dependency instance.

Relevant decisions are [ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md)
(portable committed state), [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md)
(one applied-state record), [ADR 0009](../adr/0009-seihou-reads-no-package-manager-format-artifacts-declare-the-command.md)
(artifact-declared behavior instead of ecosystem guesses),
[ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md)
(version semantics and adjacent upgrades), and
[ADR 0018](../adr/0018-checkout-outputs-are-observable-portable-declarations.md)
(observable checkout links and safe ownership). ADR 0018 needs an explicit amendment
for declared checkout commands and removal of update-inside-sync. The ADR corpus
currently uses ordinary Markdown records; do not migrate it to another format as
part of this work.


## Plan of Work


### Milestone 1 — Prove the complete local-setup path early


Introduce a typed command execution lifecycle in the core, with application and
checkout alternatives. The new Dhall command representation uses an action union:

```dhall
let Action = < Apply : Text | Checkout : Text >

in  { Type =
        { action : Action
        , workDir : Optional Text
        , when : Optional Text
        }
    , default = { workDir = None Text, when = None Text }
    , Action = Action
    }
```

An author writes a repeatable setup command through the same `commands` field:

```dhall
S.Command::{
  action = S.Command.Action.Checkout "mkdir -p .local/demo && printf '%s\\n' '{{demo.value}}' > .local/demo/value",
  workDir = None Text
}
```

Ordinary commands use `Action.Apply`. New-runtime decoding also accepts the old
`{ run, workDir, when }` representation as application commands. Reject records
containing both encodings, unknown action tags, or malformed fields. This migration
preserves pinned old schema modules; producers moving to the new schema must convert
ordinary commands to the new constructor too. `Removal.commands` shares the command
type: reject checkout lifecycle there, since removal is not a local-setup declaration.
Migration commands and command-derived variables retain their existing semantics.

Carry the lifecycle through the existing compiler and composition machinery.
Resolve `when`, variables, and working directories during application. Record only
the active rendered checkout commands. Preserve the complete composed ordering,
qualified instance identity, and duplicate occurrence identity. Reuse command-body
rendering and process execution helpers; do not route sync through receipt selection
or full update/application planning.

Keep the rendered setup portable under ADR 0001. Resolve project paths relative to
the receiving checkout, never to the applying machine's absolute project directory,
producer installation or cache. Reuse existing path validation rather than parsing
shell strings to infer paths. A command that invokes a producer-supplied script must
have that script materialized as a committed project asset during application; sync
cannot recover an unrecorded script from a producer cache. Test execution after the
original checkout and producer cache are unavailable and the clone has a different
absolute path. Absolute paths embedded by an author in arbitrary shell remain an
authoring portability defect, not something the runtime can reliably rewrite.

Keep the existing `checkoutOutputs` map for observable links. Add an ordered
`checkoutCommands` list to each `AppliedComposition`, with records containing qualified
instance owner, stable occurrence identity, rendered shell text, and optional portable
working directory. Application ownership is implicit in the containing application.
Do not store completion timestamps, machine IDs, or a second copy of the link map.
The link map and per-application command lists are the two typed parts of the resolved
checkout setup. Build a transient `CheckoutSetupPlan` from them for execution; it is
not another persistent artifact. Unknown owners and duplicate command identities
within an application are invalid.

Introduce the adjacent manifest schema upgrade and capability mapping. New-schema
applications require `checkoutCommands`; the new runtime maps its absence in old-schema
applications to an empty list and retains the old version until an authorized write.
The lossless upgrade adds empty
lists because old specs recorded no checkout-command declarations; it must not promote
command receipts into setup instructions. Empty means no such instructions recorded,
not proof that a legacy project has all desired machine effects. Sync can read and
restore existing schema-9 links without writing a schema upgrade. Older binaries must
reject the new schema before mutation.

Add a small non-skill producer fixture with a managed file, an ignored directory link,
an ordinary command, and a checkout command using a saved variable. Include a child
dependency with its own checkout command. Apply it in checkout A, commit the result,
clone checkout B with empty producer/configuration caches, and run plain `seihou sync`.
The local commands run in dependency order with the recorded inputs, the link exists,
and the ordinary-command sentinel remains absent. Managed files, manifest and index
remain identical. Use an unreachable producer origin or an instrumented resolver to
prove sync does not fetch. This must work through the executable before expanding
coverage. The same fixture must fail the new-local-effect assertion on the previous
released implementation; an old binary must reject the new tagged spec and manifest
without running either sentinel.

Remove `withCheckoutAdoption` and the sync CLI's update orchestration in this slice.
Keep normal restoration independent of whether the link map is empty, partial, or
complete: a command-only application must work. Remove the unpublished adoption-only
`--yes` behavior and its guidance unless upstream evidence shows it was released;
in that case document and test a compatibility treatment without retaining automatic
updates. Do not remove useful update transaction or tracked-link adoption support.


### Milestone 2 — Make real producer adoption satisfy the team workflow


Correct `link-skill`'s module specification and ignore preparation to declare the
intended `.claude/skills/<name>`, `.codex/skills/<name>`, and retained
`.agents/skills/<name>` destinations. Use existing typed checkout steps, not shell
commands, for these observable links. Both planning skills must point to their actual
source directories with valid literal relative targets. The runtime must contain no
agent-tool directory constants. Preserve the separate source convention of the
Claude-specific `claude-skill-link` producer; do not move its source or broaden that
module's declared purpose incidentally.

Publish no producer until candidate validation and ordinary-command acceptance
pass. Before broad tests, rehearse normal update from immutable real consumer states:
`mori://shinzui/haskell-nix` at `5cb50ca` has schema 6 and historical command receipts;
at `529fd6d` it has schema 9 and four existing planning-skill declarations. Also use
the pre-adoption Seihou consumer at `c7c315a^`, which includes unrelated Nix scaffolding
and a tracked discovery link. Resolve full commit identities and retain them in the
evidence. Test from untouched disposable clones; record any producer publication
staging honestly. Do not silently install dependencies, edit manifests or ignore
rules, pre-untrack paths, or accept file conflicts in fixture preparation.

For each starting state run ordinary interactive `seihou update master-plan`, with
empty producer caches and saved inputs. The normal preview must include the necessary
source/dependency changes, ignore changes, declaration additions, and any safe index
adoption. It must preserve unrelated Nix artifacts, existing local edits and staging.
Additive `.gitignore` co-ownership must not require user enumeration. A genuine
whole-file ownership conflict must be named and left unchanged, not solved by
silently upgrading unrelated applications. If update cannot meet this workflow,
correct its selection/certification path in this milestone.

Commit the accepted setup in the disposable project and test a fresh teammate clone
and linked worktree with only `seihou sync`. For the two default planning skills,
independently assert all six named destinations and their literal targets, reachable
`SKILL.md` files, ignored/untracked status, clean Git state, and unchanged manifest
bytes. Do not derive the expected destinations solely from the generated manifest.
Also verify that changing a module spec changes the recorded setup through ordinary
update, while an unadopted newer producer cannot change another developer's sync.


### Milestone 3 — Complete lifecycle, compatibility and failure semantics


Normal run and accepted update execute each selected checkout command as part of
the declared command sequence, once per occurrence, without putting it in ordinary
success receipts. Preserve the relative order of application and checkout commands
during normal execution; splitting all application commands ahead of all checkout
commands would change existing dependency assumptions. Sync selects only checkout
commands and preserves their relative dependency/declaration order. Across independent
applications use deterministic application-ID ordering; cross-application command
prerequisites must be expressed as dependencies within a composition rather than
relying on incidental manifest array order.

Normal update must still recognize a no-op: the mere presence of a repeatable local
command must not force regeneration or make every update actionable. Changes to the
recorded checkout declaration do make an update actionable. `--no-commands` on run
or update suppresses execution of both command lifecycles but does not discard
checkout declarations from the accepted manifest. Ordinary commands retain their
existing receipt policies and identity. A shared module instance within one
composition runs once; distinct instances and separate applications retain their
explicit occurrences. No global deduplication by shell text is allowed.

Replacing or removing an application replaces or removes its command list together
with its other owned state. Removed/false-condition commands cannot survive as stale
instructions. Removal never executes a checkout setup command. Existing link
co-ownership and safe retirement remain intact. A schema upgrade alone never invents
local setup from historical commands. Interrupted update recovery must complete or
be explicitly resolved before sync can execute a mixed old/new project state; reuse
the existing recovery query and supported recovery path, without an implicit update.

The sync service validates the entire recorded setup before mutation. Preflight links
and declared working directories, reject invalid owners/paths and unavailable command
working directories, and show all planned effects on dry-run. Working directories
must be project-relative and real, with no escaping or symlinked ancestry; the default
is the current project root. Do not evaluate shell or probe external tools during
preflight. Commands requiring artifacts from an earlier command keep that relationship
inside the shell command or within existing real working directories; no new general
resource scheduler is introduced.

Materialize the checked declarative links, then execute checkout commands in order.
Link sources must therefore exist before execution; a checkout command cannot be
used to satisfy a missing link source during that same sync. Producers materialize
such source assets during application, or keep an inseparable setup entirely within
one repeatable command instead of declaring a dependency the engine cannot honor.
Stop on the first command failure and report the application, instance, command,
exit code and captured output. Keep already successful local effects and report the
unrun tail. Existing link-phase failure rollback remains in force; do not claim to
roll back shell effects or undo links after shell commands may have used them.
A retry runs the complete recorded checkout-command phase again, which is why the
producer must declare only repeatable commands. No global or per-machine receipt
can cause the retry to skip required work. A failed first application must retain
or roll back desired declarations consistently with its existing run/update
publication boundary; never record local success because the manifest was written.

Sync's own code writes only local declarative outputs and necessary parents; it
never writes managed bytes, the Git index, baselines or the manifest. Arbitrary shell
can violate its producer contract, so documentation and tests must distinguish the
executor's guarantees from the command author's obligations. No automatic hook is
installed. Shell has the invoking user's environment and permissions, as existing
module commands do; portability of external tool requirements is the producer's
responsibility. Generic commands are not reported as "already correct" because
Seihou has no observation contract for their results.

Extend focused tests for legacy record decoding, invalid tagged actions, unknown
new-manifest kinds, required fields, duplicate identities, owner validation, schema
6/9/current transitions, variables and conditions, repeated dependencies, ordering,
command-only/link-only/mixed applications, normal command receipts, no-op update,
`--no-commands`, removal, empty caches, poisoned configuration, newer producers,
collisions, dry-run, failure/retry, stale update recovery, and Git-state preservation.
Do not assert repeatability merely by counting successful process launches: delete
the local sentinel between runs and prove restoration. Run native acceptance on
macOS and Linux; record unavailable platform proof as unfinished, not implicitly
passed. Hostile concurrent filesystem writers and sandboxing arbitrary shell are
outside the existing engine's guarantees.


### Milestone 4 — Make the interface and architecture agree


Default `sync` output must identify created/repaired/unchanged links and executed,
failed or not-run commands. It must clearly report command failure and return nonzero.
`--dry-run` must explain the same recorded work without effects. `--json` must emit
one structured document, with command output captured rather than mixed into the
JSON stream. Preserve existing link-result fields where possible; add explicit command
results and a versioned output contract when incompatibility requires it.

Status observes declarative links without executing commands or looking up remote
producers. It reports the number of declared checkout commands as pending explicit
execution/available setup, not as healthy or broken based on shared receipts. With
no recorded checkout effects it says that explicitly and distinguishes absence of
instructions from successful restoration. Any suggested adoption command must refer
to a recorded root application and actually work through the public CLI.

Update `docs/cli/sync.md`, `docs/cli/status.md`, `docs/user/teams.md`, the module
specification/authoring documentation, both changelogs, embedded help, all affected
agent prompt templates and the shared module reference. Replace the prior promise
that sync fetches upgrades when declarations are missing. Explain that changing the
specification is a maintainer action, while reproducing its local effects is a
checkout action. Amend ADR 0018's no-shell and automatic-adoption text explicitly;
update ADR 0014's version history and retain ADRs 0001/0004's single portable manifest
invariant. Preserve the historical evidence in plans 105/107 without repeating their
completion claims as acceptance of this work.

The schema's change to `Command` also affects removal records, schema exports,
scaffolds, generated references and validation examples. Audit these consumers,
including `seihou-okf-extension`, so the published authoring API works without hand
corrections. Check packaging and run the release skill's complete semantic help and
agent-context audit. Passing an embedding script is not a substitute for reading
what the shipped instructions tell a developer to do.


### Milestone 5 — Deliver and verify the actual team artifacts


Use Mori for dependency source discovery. Verify current authoritative schema tags,
producer revisions and Hackage package versions before choosing pins or PVP bounds;
do not reuse the abandoned 0.10.2.0 assumption. Public Haskell record/constructor
changes must receive the repository-required breaking PVP bump. Follow
`agents/skills/release/SKILL.md`, including all gates, reviewed release notes,
required publication confirmation and dependency upload order.

Publish in dependency order: compatible schema, supporting runtime, then producers
that require that runtime; update runtime schema submodule/Nix pins consistently.
Do not expose a producer requiring an unavailable runtime as a finished workflow.
Then adopt the corrected producer specifications in the affected maintained
consumer projects through ordinary public update commands, review and commit their
state, and deliver those commits through the normal authorized Git workflow.
The runtime, producer and consumer transitions are one delivery obligation.

Repeat the immutable legacy/partial-consumer adoption and fresh-clone/worktree
acceptance with an executable obtained from the published artifact, not the build
used during development. Record its version and revision, acquisition command,
published source/archive identity, producer and consumer commits, initial schema
and cache state, exact commands/prompts, concrete expected paths, output and final
Git/manifest comparisons. Verify at least the explicitly affected remote environment
when access remains authorized; never label a local copy as the remote machine.
If consumer publication, platform proof, installable runtime or authorized installation
remains, keep this milestone open and state that specific gap. Do not substitute a
manual `ln` repair or another source test count for delivery.


## Concrete Steps


Start from the Seihou repository root. These discovery commands locate the external
owners without hard-coding another checkout's absolute path:

```sh
git status --short
mori registry show shinzui/seihou-schema --full
mori registry show shinzui/agent-seihou --full
mori registry show shinzui/haskell-nix --full
mori registry show shinzui/keiro --full
```

Inspect applicable instructions in each discovered checkout before editing it.
Keep all implementation in this plan and preserve unrelated work. The same active
intention is `intention_01m50b28ccem2axbbn5tj3k1wt`. Implementation commits carry this
plan's repository-local ExecPlan trailer (canonical Mori plan URI in other repos)
and that Intention trailer. Use the current branch unless instructed otherwise.

Create the first executable regression in
`seihou-cli/test/Seihou/CLI/CheckoutSyncE2ESpec.hs` and focused compiler/manifest/
command tests alongside their existing suites. Use the built binary's absolute
path in fixtures; do not rely on a possibly stale PATH executable. Build and run
focused acceptance with the existing Cabal/Tasty harness, then the final gates:

```sh
cabal build exe:seihou
cabal list-bin exe:seihou
cabal test seihou-cli-test --test-options='--pattern checkout'
just format
just build
just test
just audit-cli-docs
just check
```

Confirm the focused suite selector actually matches the new tests before treating
it as evidence. Run `cabal check` from each of `seihou-core/`, `seihou-cli/`, and
`seihou-okf-extension/`. Validate changed producer modules and run their Bun
acceptance from `mori://shinzui/agent-seihou`, following its checked-in test entry
points. Its existing checkout test requires explicit `SEIHOU_TEST_BIN` and
`SEIHOU_LEGACY_TEST_BIN`; retain real legacy producer/runtime provenance and update
that harness honestly for the new support version.

For the human workflow, the commands run inside consumer checkouts are ordinary:

```sh
# Project maintainer: one-time adoption of the changed module specification.
seihou update master-plan
# Review and commit the previewed project changes through normal Git workflow.

# Teammate: after cloning or receiving that commit.
seihou sync
seihou sync
```

The comments describe separate roles, not a script every developer must run. In the
non-skill acceptance use a small actual module with a saved input, child dependency,
managed sentinel, ordinary-command sentinel and ignored local setup sentinel. Its
ordinary application occurs only in checkout A. Checkout B runs only sync. Keep the
harness's cloning and cache isolation separate from the user's command transcript.
A fixture must never prepare the local effects it later claims sync created.


## Validation and Acceptance


Acceptance starts with an explicit expected local-effect specification independent
of implementation output. The generic fixture expects its declared link and local
sentinel containing the saved value, dependency-before-parent command order, and
absence of the ordinary-command sentinel. The planning-skill fixture explicitly
expects `exec-plan` and `master-plan` under each of `.claude/skills`, `.codex/skills`
and `.agents/skills`, with targets `../../agents/skills/<name>` and readable source
`SKILL.md` files. Runtime code must not contain these domain-specific expectations.

Prove first application, untouched schema-6 adoption, partial schema-9 adoption,
fresh clone, linked worktree, second sync, deleted local effects, wrong link targets,
producer/configuration changes after application, and command failure followed by
retry. Plain sync is the acceptance command; JSON and dry-run are additional interface
checks. Run the same explicit assertions against the previous release as a negative
control, documenting the expected failing capability rather than treating any nonzero
exit as a meaningful failure.

Capture the manifest bytes, Git index entries and tracked working-file bytes before
and after restoration, treating tracked symlinks as literal link text rather than
following them. These snapshots must remain identical for contract-conforming setup
commands. A real file or directory collision prevents the local execution phase
without clobbering user content. Local command failure returns nonzero, leaves shared
state untouched by Seihou, reports the completed prefix and unrun tail, and permits
retry without receipt surgery. Validate new schemas and command encodings against
old binaries to prove refusal before mutation.

A maintainability review is part of milestone acceptance: there is one spec compiler,
one portable manifest, one existing typed link observer/planner, and one reusable
shell execution path. No skill-directory scanner, command-text recognizer, built-in
producer/version registry, second local completion ledger, or runtime update call
exists in sync. Each new type has one meaning; completion history and replayable
instructions are not interchangeable. Keep the CLI an adapter over library logic.
Resolve violations within this plan before release.

A release is complete only when a teammate can obtain the documented executable and
run the ordinary workflow against committed consumer state. Source-build tests,
prepared tarballs, correct status wording, and an individually repaired machine are
useful evidence but are not that outcome.


## Idempotence and Recovery


Declarative links retain existing collision checks, ownership, relative targets,
preflight and link-phase rollback. Checkout commands are explicit repeatable actions:
running sync twice executes them twice, and deleting their local result then rerunning
restores it. Do not describe generic commands as observed no-ops or promise to reverse
arbitrary side effects. Module authors must make them safe to repeat after interruption.
No machine-local or shared completion record is introduced.

Update retains its existing transaction/recovery mechanism for managed files, index
adoption and manifest publication. Command-side effects may remain after update failure,
which existing transaction errors already distinguish. Record the intended setup
consistently with the accepted application state and make retries use that state.
An older receipt is never a reason to skip a checkout command. Sync must refuse an
unresolved interrupted project update with the existing actionable recovery guidance
instead of executing an inconsistent specification.

The schema upgrade is deterministic and preserves prior data. It adds no inferred
local effects. Legacy projects acquire declarations by applying a specification that
actually declares them; that maintenance may update managed sources and therefore
uses the normal preview and confirmation boundary. No repair script, Git-index edit,
or reinterpretation of historical shell strings is part of normal adoption.


## Interfaces and Dependencies


The minimum new core concepts are a typed command lifecycle and a rendered checkout
command record. Preserve legacy application-command behavior and fingerprint identity;
new lifecycle data must not gratuitously invalidate existing receipts. An ordered
`checkoutCommands` field on `AppliedComposition` stores the local command subset,
while `checkoutOutputs` continues to store typed observable link claims. The manifest
version/capability registry and adjacent codec upgrade define their meaning centrally.

The compiler produces the execution lifecycle and resolved payload together. Normal
application consumes the complete command sequence and records the checkout subset;
sync consumes only that recorded subset plus existing typed links. The sync service
exposes plan, execution and result separately so dry-run cannot execute effects and
failure reporting cannot present proposed work as completed work. Reuse the process
effect and low-level command execution logic without reusing global receipt policy.

No new third-party dependency is expected. Use Mori to inspect dependency APIs if
one is needed; verify released package availability and upstream tags before changing
bounds. Existing schema, producer and consumer repositories are explicit integration
dependencies described above. Their release/adoption work stays under this plan's
acceptance obligation rather than becoming follow-up planning work.
