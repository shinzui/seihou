---
id: 107
slug: adopt-manifest-owned-skill-links-in-agent-seihou-and-verify-fresh-clone-sync
title: "Adopt manifest-owned skill links in agent-seihou and verify fresh-clone sync"
kind: exec-plan
created_at: 2026-10-15T17:52:00Z
intention: "intention_01m50b28ccem2axbbn5tj3k1wt"
provenance:
  created_by:
    model: "gpt-6.1-sol"
    harness: "codex-cli"
    at: 2026-10-15T17:52:00Z
  revisions:
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-15T17:54:56Z
      mode: "other"
      note: "Create four-milestone producer adoption and published existing-consumer fresh-clone acceptance plan"
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-15T18:13:48Z
      mode: "update"
      note: "Address review with a legacy 0.9.0.0 schema-6 fixture and explicit transition assertions; refresh released runtime candidate and committed checkout context."
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-15T18:11:47Z
      verdict: "changes-requested"
      note: "Milestone 1 must establish and assert a pre-schema-9 fixture; applying an old producer with the current binary already writes schema 9. Verified producer definitions, update path, ADRs, and published 0.10.0.0 availability."
---

# Adopt manifest-owned skill links in agent-seihou and verify fresh-clone sync

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Make the skill modules people already use benefit from `seihou sync`. After a one-time
application of updated producer modules, a developer clones a project, runs `seihou sync`,
and gets its declared skill discovery links without installing modules, upgrading artifacts,
running migrations, or changing the committed manifest. Deleting a link and running sync
again restores it.

[Plan 105](105-rebuild-checkout-local-symlinks-from-the-manifest-without-upgrading-artifacts.md)
implemented the engine but left producer adoption separate. This follow-up owns that missing
delivery: convert both agent-seihou link modules, publish usable producer versions with a
supporting runtime, adopt them in this repository's existing master-plan application, and
prove the committed consumer works in a fresh clone with an empty producer cache. Changing
module syntax alone is not completion.


## Progress

- [ ] Milestone 1: the real link-skill module records both checkout declarations and upgrades a verified pre-schema-9 command-based application without replaying shell commands.
- [ ] Milestone 2: claude-skill-link and its update-docs composition work declaratively; exec-plan/master-plan composition and meaningful regression cases pass against the real binary.
- [ ] Milestone 3: versioned producer changes, compatible runtime availability, and consistent generated/user documentation are published and verified through a remote installation.
- [ ] Milestone 4: this repository's existing master-plan application records the new declarations; its committed state restores all four discovery links in a fresh clone and a linked worktree without producer installations or tracked changes.


## Surprises & Discoveries

Review (2026-10-15): applying an old producer with the current runtime does not create an
old-schema fixture. `seihou-cli/src-exe/Seihou/CLI/Run.hs` writes
`currentManifestVersion`, currently 9, regardless of the producer version. The released
v0.9.0.0 runtime writes schema 6; use it to establish the legacy application before switching
to the supporting runtime. This repository's committed schema-7 application supplies a
separate real-consumer transition in Milestone 4.

Review (2026-10-15): Seihou 0.10.0.0 is published on Hackage and its upstream v0.10.0.0 tag
includes checkout sync. It is the released runtime candidate for the acceptance tests;
publication alone does not prove the new producer compositions work with it.


## Decision Log

Decision (2026-10-15): completion includes published producer adoption and one committed
existing consumer, followed by fresh-clone proof. Plan 105's engine tests cannot substitute
for that outcome. This repository is the concrete consumer; a fleet-wide upgrade of other
projects is outside this plan.

Decision (2026-10-15): convert both active link producers. Keep the existing source convention
of each: link-skill uses agents/skills, while claude-skill-link uses claude/skills. Moving
update-docs to a different source tree would introduce an unnecessary content migration.

Decision (2026-10-15): record intent through ordinary module application/update, never by
editing checkoutOutputs by hand or parsing command receipts. Keep historical content-move
migrations in exec-plan/master-plan; remove only the current link producers' shell setup.

Decision (2026-10-15): use separate legacy and supporting executables for the transition
test. Assert the legacy schema and command receipts before updating, so a current-runtime
fixture cannot silently replace the required schema-upgrade proof.


## Outcomes & Retrospective



## Context and Orientation

This plan lives in Seihou and coordinates changes to the producer project
`mori://shinzui/agent-seihou`. A producer is a module that declares generated files and local
links; a consumer is a project to which that module has been applied. A checkout output is
desired local filesystem wiring recorded in the committed manifest and reconstructed by
observing each working copy. Unlike a command receipt, it does not assert that every clone
has already run setup.

Locate producer and dependency checkouts with Mori before reading their APIs:

```bash
mori registry list
mori registry search agent-seihou
mori registry show shinzui/agent-seihou --full
mori registry docs shinzui/agent-seihou
mori registry show shinzui/seihou-schema --full
mori registry docs shinzui/seihou-schema
```

At planning time the producer checkout is `/Users/shinzui/Keikaku/bokuno/agent-seihou`.
Use the current Mori result if it moves. All producer paths below are qualified by
`mori://shinzui/agent-seihou`; project-relative file references in that project have
artifact-level URIs pending unless a specific URI is given. Registry observation is stale:
it does not yet expose link-skill, although the checkout contains it. A failed
`mori path mori://shinzui/agent-seihou/templates/link-skill` must not cause an ambiguous
reference or omission of that module.

The producer file `modules/link-skill/module.dhall`
(`mori://shinzui/agent-seihou/templates/link-skill`) is version 0.2.0 and uses an older schema
pin. It appends `.agents/` to `.gitignore`, depends on claude-gitignore, and runs four shell
commands: two mkdir commands and two ln commands exposing agents/skills/{{skill.name}}
through .claude/skills and .agents/skills. The producer file
`modules/claude-skill-link/module.dhall`
(`mori://shinzui/agent-seihou/templates/claude-skill-link`) is version 0.1.0 and exposes
claude/skills/{{skill.name}} only through .claude/skills. Its schema pin and explicit empty
step type predate lifecycle, so conversion must update both the import and the step values.

In the same producer project, `modules/exec-plan/module.dhall` and
`modules/master-plan/module.dhall` are version 0.12.0 and depend on link-skill; master-plan
also includes exec-plan. Their historical migrations contain shell links following source
moves, but those migrations are not the current producer mechanism. The file
`modules/update-docs/module.dhall` still generates into claude/skills and depends on
claude-skill-link. The file `blueprints/hackage-release/prompt.md` already calls link-skill
after creating its source directory; it should benefit without a second link implementation.

The producer's `seihou-registry.dhall`, root `README.md`, and module READMEs describe the
published interface. Its `okf-docs/` directory is generated with
`seihou-okf-extension docs --force`; never hand-edit those generated documents. Existing
helper-script tests live in its `tests/provenance.test.ts` and run with Bun.

In Seihou, `schema/Step.dhall` declares lifecycle. Schema 9 stores checkoutOutputs, a map
keyed by destination with a typed directory-symlink specification and application owners.
The implementation and user contract are in `docs/cli/sync.md`,
`docs/user/module-authoring.md`, `docs/user/manifest-upgrade.md`, and the real-binary tests
`seihou-cli/test/Seihou/CLI/CheckoutSyncE2ESpec.hs`. Consult that test for environment isolation,
tracked-byte snapshots, and clone/worktree checks rather than reproducing engine internals.
The schema upstream HEAD was verified as 367b0a1390ac1ed3dda6e2cacfdf3e72b1f624df during
planning, and its Step.dhall contains lifecycle. Mori's local schema checkout still has an
older Step.dhall. Reverify upstream before selecting the producer pin and integrity hash.

The committed Seihou manifest at planning time is schema 7. It records a master-plan 0.12.0
application with exec-plan/link-skill instances and a separate nix-haskell-flake application.
It also retains older module records including claude-skill-link. Update the master-plan
application through the public command, preserve other applications and legacy records,
and do not use a no-target update. At review time the manifest, baseline, and Nix changes
were already committed in d70ada4 and b628fd4, and the working tree was clean before the
review metadata was appended. Recheck current state at implementation time, preserve any
new unrelated edits, and prove the transition in a disposable copy before adopting in the
real checkout.

Relevant local decisions are [ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md),
which prohibits machine-local values in the committed manifest;
[ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md), which makes the
manifest the sole portable applied-state record;
[ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md), which
requires ordered, lossless upgrades without inventing missing facts; and
[ADR 0018](../adr/0018-checkout-outputs-are-observable-portable-declarations.md), which defines
checkout links, ownership, observation, and safe refusal. A symlink step must use checkout
lifecycle, no patch, a real project directory source, and an ignored untracked destination.
Sync never replays receipts or rewrites the manifest. No new architecture is required here.


## Plan of Work

### Milestone 1: prove the real link-skill transition first

In `mori://shinzui/agent-seihou`, change `modules/link-skill/module.dhall` to use a verified
published schema with lifecycle. Keep its variable interface and ignore behavior. Replace
the four setup commands with two S.Step values using the declarations below. Sources are
project-relative paths, not literal relative link text and not module files/ assets.

```dhall
S.Step::{
  strategy = "symlink",
  lifecycle = Some "checkout",
  src = "agents/skills/{{skill.name}}",
  dest = ".claude/skills/{{skill.name}}"
}
```

The second step has the same source and destination `.agents/skills/{{skill.name}}`.
Keep the existing .gitignore patch. Neither mkdir nor ln remains in the current commands
list. Parent creation and target calculation belong to Seihou. Choose a new module version
after inspecting current upstream declarations; do not reuse 0.2.0 with changed behavior.

Add `tests/checkout-links.test.ts` in that producer project. SEIHOU_TEST_BIN selects the
supporting executable; SEIHOU_LEGACY_TEST_BIN selects the released Seihou 0.9.0.0 executable
used only to create the old application. Record both executables' version output. Copy the
real link-skill 0.2.0 module and its dependencies from a fixed pre-conversion producer commit
into a temporary Git project's local module directory; record that commit in the fixture
setup. Create the real skill source directory and apply the old module with the legacy
executable, allowing its setup commands to establish real links and command receipts.

Before invoking the supporting executable, assert that the manifest is schema 6, has no
checkoutOutputs field, records link-skill 0.2.0 and its mkdir/ln command receipts, and that
the expected links exist. Never manufacture the old manifest JSON or downgrade its version
by hand. Then replace the local producer with the candidate and use the supporting
executable's public update path with --no-commands. Exercise both existing-correct-link
adoption and missing-link creation from independent copies of the legacy fixture. Assert
that the manifest advances from the verified starting version to at least 9 and records
both declarations with the chosen skill name. Old receipts may remain as history but cannot
suppress the declarations, and their shell commands must not be replayed.
The test must fail for the old producer. This early real producer/consumer check is required
before expanding the conversion to the other modules.

### Milestone 2: cover legacy linking and existing compositions

In `mori://shinzui/agent-seihou`, convert `modules/claude-skill-link/module.dhall` to one
symlink/checkout step from `claude/skills/{{skill.name}}` to
`.claude/skills/{{skill.name}}`, preserving its dependency and variable interface. Update
its schema and module version. Do not move the tracked update-docs source files.

Extend `tests/checkout-links.test.ts` to apply the actual update-docs module with explicit
required variables and the actual master-plan module with its exec-plan dependency. Run
them with --no-commands and empty personal configuration. The latter composition must
produce four distinct declarations: master-plan and exec-plan in each discovery directory,
with source directories generated in the same application. Validate owner information and
that one agreeing owner cannot remove another's claim. Include a direct link-skill case
using a non-default name such as release so the tests cannot pass through hard-coded names.

Exercise missing source and occupied real-directory refusal without source loss or partial
manifest changes. Verify the current declared outputs are links, not managed file records
or baseline content. Historical exec-plan/master-plan migration operations remain intact;
they may be required for consumers older than the source-tree move. Do not add a new shell
migration to record checkout intent. If actual composition exposes a defect required to
meet these outcomes, fix it and add the focused regression rather than weakening acceptance.

### Milestone 3: make adoption available and document the exact route

In `mori://shinzui/agent-seihou`, synchronize module versions and descriptions in
`seihou-registry.dhall` and root `README.md`. Update `modules/link-skill/README.md` and
`modules/claude-skill-link/README.md` to describe declarations, required real sources,
collision refusal, and fresh-clone sync. Correct the stale link-skill source description
that still says claude/skills. Update the exec-plan/master-plan/update-docs module READMEs
where they describe current setup. Distinguish historical migration commands from current
checkout declarations. Correct link-skill's blanket non-removable claim: describe the
automatic checkout cleanup precisely without promising removal of unrelated shared patches.
Regenerate `okf-docs/` through the extension and verify a second generation is byte-stable.

Provide exact first-install and existing-application commands, including a dry run before
update. Document that installing a new producer or running manifest upgrade alone does not
record desired links. Existing compositions must be successfully applied once, their source
directories and ignore rules committed, and the changed manifest committed. After that,
clones use only sync. Document the minimum tested released Seihou version; the schema import
does not by itself establish runtime compatibility. Confirm an older binary fails on the
unknown symlink strategy rather than silently recording file output.

Use Seihou 0.10.0.0 as the initial released runtime candidate. Review verified its
[Hackage publication](https://hackage.haskell.org/package/seihou-cli-0.10.0.0) and upstream
v0.10.0.0 tag at de4c4cf0ea9d89120e6d2d1f9938541fa97a5fa8, whose changelog includes checkout
sync. Recheck availability and run the acceptance cases against that release. If a required
fix makes a newer runtime necessary, publish that supporting release and repeat the affected
acceptance cases. Prepare all checks before any release action; follow the release skill
when actually cutting a Seihou release. Commit and publish
the producer changes using its established branch/version conventions, then install from
the published remote into an isolated configuration and rerun the representative tests.
Record actual runtime version, schema commit/hash, producer commit, and module versions.
The producer registry has no local tags at planning time; do not invent a tag requirement
when publication is normally a committed version on its default branch. Parent modules
need version bumps only if their own definitions change or established publication rules
require them; prove that dependency-only changes are discovered by update.

### Milestone 4: adopt an existing consumer and prove clones work

First rehearse against a disposable copy of this repository's committed state using the
published modules and supporting binary. Update only the master-plan application, preserving
its saved variables. Establish the expected four declarations. Compare tracked content,
module versions, unrelated application state, and migration reports before and after. No
unrelated Nix artifact upgrade or new flake.lock is acceptable as a consequence of this
adoption. If the saved manifest requires inference-bearing origin conversion, report and
perform the explicit manifest command with its dry run rather than editing JSON.

Apply the proven update in this real checkout while preserving unrelated working changes.
Record only the intended adoption changes in a reviewable commit. If concurrent changes
prevent safe separation, finish the proof in a disposable checkout and leave the real
adoption milestone unfinished with a concrete handoff; never stash, reset, or overwrite
someone else's work to satisfy a checkbox.

Clone the committed adopted consumer to a new temporary directory and use an empty
XDG_CONFIG_HOME and XDG_CACHE_HOME. Confirm no producer artifacts are present. Capture
tracked file bytes, Git index entries, and manifest bytes. Run status, sync --dry-run --json,
sync --json, and sync --json again. The first apply creates all four links and the second
reports them unchanged. Their literal targets are ../../agents/skills/exec-plan or
../../agents/skills/master-plan, as applicable, and following them reaches SKILL.md.
Tracked bytes, index entries, and manifest bytes stay identical. Delete one link and
prove sync recreates it; retarget one link incorrectly and prove sync repairs it. Repeat
the basic restoration in a linked worktree. Finally distill any durable adoption lesson
into ADR 0018 or the user documentation and record the actual evidence in this plan.


## Concrete Steps

From the Seihou repository root, inspect state and build the real binaries. None of these
commands traverses /nix/store. Use the existing development environment if dependencies are
not available in the current shell.

```bash
git status --short
cabal build exe:seihou exe:seihou-okf-extension
cabal list-bin exe:seihou
cabal list-bin exe:seihou-okf-extension
git ls-remote https://github.com/shinzui/seihou-schema.git HEAD
```

Export SEIHOU_TEST_BIN as the absolute executable printed by list-bin. Obtain Seihou
0.9.0.0 from its released package or build upstream tag v0.9.0.0 in a separate checkout,
and export SEIHOU_LEGACY_TEST_BIN as its absolute executable path. Keep the legacy executable
separate from the current build and the user's default installation. Verify the versions:

```bash
"$SEIHOU_LEGACY_TEST_BIN" --version
"$SEIHOU_TEST_BIN" --version
```

The first command must report 0.9.0.0; the second must identify the supporting candidate
(initially 0.10.0.0). From the producer checkout reported by Mori, run these commands after
implementing the modules and test:

```bash
git status --short
"$SEIHOU_TEST_BIN" validate-module modules/link-skill
"$SEIHOU_TEST_BIN" validate-module modules/claude-skill-link
"$SEIHOU_TEST_BIN" validate-module modules/exec-plan
"$SEIHOU_TEST_BIN" validate-module modules/master-plan
"$SEIHOU_TEST_BIN" validate-module modules/update-docs
bun test tests/checkout-links.test.ts
bun test
seihou-okf-extension docs --force
git diff --check
```

Use the just-built extension's absolute path if the installed extension cannot read the
new schema. Regenerate a second time and require identical output. The integration test
must fail with an actionable message when either executable variable is missing, the legacy
version is wrong, or the fixture's starting-schema/receipt assertions fail; it must not
silently skip its acceptance cases. Isolate all project/cache writes in temporary directories.

After publication, from a disposable consumer use a fresh configuration and the supporting
released binary to install actual remote artifacts:

```bash
seihou install https://github.com/shinzui/agent-seihou.git --module master-plan --module exec-plan --module link-skill --module agent-gitignore --module claude-gitignore --module update-docs --module claude-skill-link
seihou update master-plan --dry-run --json --no-commands
seihou update master-plan --json --no-commands
git diff -- .seihou/manifest.json
```

Inspect the candidate module versions before applying; update can fetch the recorded
remote, so do not assume a global installed version alone pins the candidate. Retain saved
inputs; do not use --reconfigure or --force to conceal a conflict. The expected manifest
contains four checkout entries owned by the selected application, and the unrelated
nix-haskell-flake application remains at its previous version. Before applying to the real
checkout, repeat its dry run against the current working state and inspect the exact diff.

For the final proof, after committing only the intended consumer changes, run from Seihou
root with SEIHOU_TEST_BIN pointing to the supporting executable:

```bash
checkout_proof=$(mktemp -d)
git clone --quiet . "$checkout_proof/clone"
mkdir -p "$checkout_proof/config" "$checkout_proof/cache"
cd "$checkout_proof/clone"
cp .seihou/manifest.json "$checkout_proof/manifest.before"
XDG_CONFIG_HOME="$checkout_proof/config" XDG_CACHE_HOME="$checkout_proof/cache" "$SEIHOU_TEST_BIN" status
XDG_CONFIG_HOME="$checkout_proof/config" XDG_CACHE_HOME="$checkout_proof/cache" "$SEIHOU_TEST_BIN" sync --dry-run --json
XDG_CONFIG_HOME="$checkout_proof/config" XDG_CACHE_HOME="$checkout_proof/cache" "$SEIHOU_TEST_BIN" sync --json
XDG_CONFIG_HOME="$checkout_proof/config" XDG_CACHE_HOME="$checkout_proof/cache" "$SEIHOU_TEST_BIN" sync --json
cmp .seihou/manifest.json "$checkout_proof/manifest.before"
git status --porcelain
readlink .claude/skills/exec-plan
readlink .agents/skills/master-plan
```

The test harness supplies the stronger tracked-byte/index assertions and linked-worktree
variant; the manual proof must also succeed. Empty porcelain output, identical manifest,
correct literal targets, and no second-apply changes are required. Existing unrelated
checkout declarations, if any have landed meanwhile, must be inventoried and accounted for
explicitly rather than changing the four required skill outputs.

Commits in Seihou use Conventional Commits and a repository-local ExecPlan trailer.
Commits in another repository use the canonical cross-repository plan reference:

```text
feat(skills): declare checkout links for skill discovery

ExecPlan: mori://shinzui/seihou/plans/107-adopt-manifest-owned-skill-links-in-agent-seihou-and-verify-fresh-clone-sync
Intention: intention_01m50b28ccem2axbbn5tj3k1wt
```


## Validation and Acceptance

The required regression suite is the producer's real-binary Bun integration test, followed
by its ordinary Bun suite and module validation. It must exercise both original command
producers, an old application with real command receipts, update-docs composition, and the
master-plan/exec-plan composition. The legacy transition must assert schema 6 and absent
checkoutOutputs before update, then schema 9 or later and the expected declarations after
update. A fixture created with the supporting runtime cannot satisfy this criterion.
Milestone 4 separately proves adoption from this repository's committed schema-7 application.
Declaration application must work under --no-commands.
Do not replace actual module evaluation with a handwritten representative module; that
would repeat the adoption gap this plan exists to close.

For each cloned fixture, declarations and sources are committed while discovery links are
ignored and absent. With no installed modules, dry-run creates no links or parents, the
first sync creates expected links, and the next sync changes nothing. Manifest bytes,
tracked sources and generated skill bytes, index entries, and recorded module versions
remain unchanged by sync. Repair after deletion and wrong-target replacement must work.
A real object occupying a discovery path must be preserved on refusal. The legacy
claude-skill-link case follows claude/skills without relocating its sources.

The delivered consumer proof must use this repository's existing recorded application,
the published producer commit, and a supporting released runtime. Record the consumer
adoption commit and short JSON summaries for first and second sync, not large transcripts.
Passing temporary fixtures without publication or without the committed consumer adoption
does not complete this plan. A missing prerequisite release remains unfinished work.

Engine changes are not expected. If a real producer interaction requires a core or CLI
fix, add a focused regression in the existing checkout suites, run the affected suite and
build, and broaden to the repository's required gates for that code change. Pure producer
and documentation changes do not require unrelated repeated full engine tests.


## Idempotence and Recovery

Perform old-to-new experiments in temporary Git projects and isolate personal configuration.
Local install clones committed HEAD, so uncommitted producer edits are not a valid install
test: copy the real module directories into temporary project-local modules during early
development, or test a committed producer snapshot. Never change the user's global cache
to impersonate a released producer.

Use dry runs and snapshots before consumer updates. Preserve existing unrelated work; do
not automatically reset or stash it. If an update fails, verify the manifest and links
still match their pre-update state before retrying, using Seihou's existing recovery path
when a transaction remains. A collision needs deliberate resolution, not a shell force
replacement. Published module versions are immutable evidence: fixes get new versions.

Sync is repeatable and manifest-read-only. Disposable clones/worktrees can be retained for
inspection, and removal of a disposable worktree must use git worktree remove only after
checking its contents. Rolling back adoption means reverting the specific adoption commit
and using the corresponding compatible producer/runtime; it is not permission to delete
tracked source directories or downgrade unrelated artifacts.


## Interfaces and Dependencies

This is a standalone follow-up to plan 105, not a child of the seed MasterPlan. It uses
the existing Step fields strategy, lifecycle, src, dest, condition, and patch; schema-9
DirectorySymlink declarations; ordinary run/update composition; and sync's observation
contract. No new manifest field, lifecycle, output kind, shell-replay option, or dependency
library is proposed.

External projects are `mori://shinzui/agent-seihou` for producer definitions and tests, and
`mori://shinzui/seihou-schema/packages/seihou-schema` for the published Dhall contract.
Verify selected schema revisions against upstream Git and the runtime against Hackage and
upstream release tags, because the local Mori corpus can lag. Use Bun's existing test and
process facilities, Git for fixtures, and the actual Seihou binary. Do not introduce a new
test dependency merely to wrap these commands. Runtime release work, if needed, follows
the repository's release skill and its package/build/test gates.

At completion, update this plan's evidence and relevant user documentation/ADR context to
show that producer adoption now exists. Keep plan 105's historical implementation boundary
accurate; its completed engine milestone must not be rewritten as proof of this follow-up's
consumer adoption.

Revision (2026-10-15): addressed the pre-implementation review by requiring a legacy-runtime
fixture with explicit before/after schema assertions, naming published 0.10.0.0 as the
runtime candidate, and refreshing the committed checkout state. These changes prevent a
false-positive upgrade test and remove stale implementation context.
