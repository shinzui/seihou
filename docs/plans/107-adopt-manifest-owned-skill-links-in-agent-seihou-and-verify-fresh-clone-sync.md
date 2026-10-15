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
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-15T18:21:18Z
      mode: "implement"
      note: "Implement and publish real producer checkout declarations, validate legacy transition, and adopt the existing consumer."
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-15T20:55:55Z
      mode: "implement"
      note: "Reopen at user request: ordinary update must adopt links without manual installation or Git index surgery; sync must give actionable adoption guidance."
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-15T21:19:40Z
      mode: "implement"
      note: "Prepare supporting release: verify published versions, run release gates, correct stale formatter-cache omissions, and prepare released-binary acceptance."
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-15T22:00:33Z
      mode: "implement"
      note: "Correct local-versus-remote acceptance claims; repair and verify all four skill links on yujin.local after receiving the committed adoption."
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

Reopened on 2026-10-15: repairing one checkout did not satisfy the team developer-experience requirement. Milestones 1–7 below are historical implementation evidence, not proof that the ordinary team workflow is complete.
The required ordinary command is `seihou sync` for both older projects and fresh
clones. On an older project it discovers and previews one-time link adoption,
then creates the links after confirmation. Developers commit the resulting
project changes; teammates receive them through Git and run the same command.
No dependency installation list, module-name knowledge, manual index surgery,
or JSON inspection is required. The source implementation passes this workflow;
the supporting 0.10.2.0 release remains outstanding. Released 0.10.1.0 and the
separate yujin.local repair below are historical evidence, not delivery of this
one-command workflow.

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

- [x] Milestone 1 (2026-10-15): link-skill 0.3.0 records both checkout declarations. Real-binary Bun acceptance passed with released 0.9.0.0 (3fe7576) creating schema 6 and four mkdir/ln receipts, then released 0.10.0.0 (de4c4cf) updating existing-correct and missing-link copies under --no-commands. The release-named clone/worktree restoration also passed.
- [x] Milestone 2 (2026-10-15): claude-skill-link 0.2.0 and update-docs retain claude/skills sources; master-plan/exec-plan produce four distinct owned links. All 20 Bun tests pass, including both real legacy command producers, non-default release names, agreeing-owner removal, collision/missing-source atomic refusal, clone/worktree restoration, and old-runtime unknown-strategy refusal. All five module validations pass on released 0.10.0.0.
- [x] Milestone 3 (2026-10-15): producer commit 455d2d6 published to mori://shinzui/agent-seihou on master; remote installation into isolated config reports link-skill 0.3.0, claude-skill-link 0.2.0, unchanged parents, and the full eight-case checkout suite passes against those installed bytes and released runtime 0.10.0.0. README/module/Mori/registry documentation is synchronized and two extension generations are identical across all 18 output files.
- [x] Milestone 4 (2026-10-15): adoption commit c7c315a updates only the existing master-plan application and untracks its discovery link. A fresh clone of that commit with empty XDG config/cache creates four links, then reports four unchanged; deletion and wrong-target repair each change one link. A linked worktree creates all four. Tracked bytes, index entries, manifest bytes and unrelated application state are preserved. ADR 0018 and sync documentation now explain the one-time adoption and intentional untracking prerequisite.
- [x] Milestone 5 (2026-10-15): ordinary remote-backed update with an empty producer cache previews and confirms eligible tracked-link adoption. Executable tests preserve unrelated staging/working edits and cover dry-run, cancellation, failed-command rollback and protected modified objects. Five core adoption tests cover interrupted/committed recovery and later index/working-link edits. An interactive real-consumer rehearsal also refuses an index change made after preview without writing the index or manifest.
- [x] Milestone 6 (2026-10-15): empty-declaration sync names recorded update targets; normal output summarizes created/repaired/unchanged links. CLI help, guides, changelogs and ADRs describe ordinary update followed by clone sync. The pre-adoption consumer passes ordinary interactive update without installation or manual untracking; its fresh clone creates four links, then reports four unchanged, and repairs deletion and retarget drift individually.
- [x] Milestone 7 (2026-10-15): published Seihou 0.10.1.0 (c3bb42b), all three Hackage packages and documentation, and the GitHub release. The user’s normal Nix-profile executable now reports that exact release. Installed-release interactive update passes with empty caches for both the tracked-link consumer and the screenshot’s schema-6 consumer; fresh clones/worktrees create four links, repeated sync changes nothing, and deletion/retarget repair preserves tracked bytes, index and manifest. All 20 producer tests (330 assertions) and five module validations pass with the installed release. The local consumer copy is adopted and pushed at 529fd6d; normal update now reports Already up to date.

- [x] Milestone 8 (2026-10-15): ordinary interactive `seihou sync` on the real pre-adoption schema-6 consumer with empty caches discovers the declaring compositions, reuses seven saved inputs, previews schema 6 -> 9 and four links, then creates all four after one confirmation. Committing that result and cloning it with another empty cache lets a teammate run the same command: four created, then four unchanged; manifest bytes and Git state stay unchanged. A mixed real consumer preserves its unrelated Nix application. Executable regressions cover no consent, dry-run, collisions, unrelated required inputs and existing tracked-link staging. Status points to the ordinary command.
- [ ] Milestone 9: publish the workflow fix and verify the released executable available to the team. A repaired individual checkout or a source-only build does not complete delivery.

Team acceptance: a developer starts in an older supported checkout with committed
skill sources, historical command receipts, and no local producers or skill links.
They run `seihou sync` and accept one preview of the adoption. The command creates
the four links and explains the project changes to commit. Other developers receive
that commit through ordinary Git collaboration and run the same `seihou sync`.
No developer needs to name a root module or dependency, edit JSON, untrack links
manually, or run a separate migration command. Already-adopted checkouts remain
offline and manifest-read-only. Automatic discovery must never apply an unrelated
application upgrade; all adoption changes remain subject to the update transaction
and its existing collision, stale-state, and recovery checks.


Release delivery (2026-10-15): 0.10.1.0 includes a screenshot-driven status fix:
absent remote producers are summarized once as an optional cache, while missing
project-owned producers, machine-local origins and stale/substituted installed
artifacts retain warnings. Regressions cover the distinction and real clone status.
The screenshot's concrete consumer, `mori://shinzui/haskell-nix`, was schema 6
with master-plan/exec-plan 0.10.0 and link-skill 0.2.0. Ordinary update succeeds
without installation, preserves the `.gitignore` customization, runs zero shell
commands and records four outputs. Consumer commit 529fd6d retains that adoption.
Sync now reports four unchanged links there. The earlier claim that the installed
0.10.0.0 binary could not update this consumer was too broad: both installed and
candidate dry runs succeed for its already-untracked discovery links. The new
runtime is required for tracked-link adoption and corrected status presentation.
The bumped source candidate also passes the real consumer clone/worktree proof
(`/tmp/seihou-107-proof-oqz9fslo/result.json`): first sync creates four links,
second sync changes nothing, deletion and wrong-target repair each change one link,
and tracked bytes/index/manifest remain identical. Empty-cache status in the actual
consumer now reports four declared outputs with zero needing attention and one
optional-cache notice (`/tmp/seihou-107-status-proof-jjzilpkn/status.txt`).
The final 0.10.1.0 candidate passes `just format`, `just build`, `just test`
(all 1,993 tests: 1,200 core, 742 CLI, 51 extension), all four native `just check`
checks, all three warning-free `cabal check` commands and `git diff --check`.
All three package archives and Haddock bundles are published on Hackage; downloaded
source archives match the uploaded bytes exactly. The public v0.10.1.0 tag and
[GitHub release](https://github.com/shinzui/seihou/releases/tag/v0.10.1.0) identify
c3bb42bd2525e29d93657f1e48b3bf8552ed727e. A normal Nix profile install of that
public tag, at priority 4 above the existing Home Manager package, activates the
release without replacing a Nix-managed file in place. `command -v seihou` remains
`/Users/shinzui/.nix-profile/bin/seihou`; `seihou --version` reports
`seihou v0.10.1.0 (c3bb42b)`. This closed milestone 7 at the time; milestone 9
still requires delivery of the subsequently requested one-command workflow.


## Surprises & Discoveries


Remote-machine correction (2026-10-15): earlier evidence used a local copy of
`mori://shinzui/haskell-nix`, not the affected checkout on yujin.local. Identical
repository names and manifest state do not establish that the user's other machine
has received an adoption commit. SSH inspection found a clean master at 5cb50ca,
schema 6, link-skill 0.2.0, and zero checkout declarations. The installed executable
reported `seihou v0.10.1.0 (824368c)`. Fetching origin revealed the already-published
adoption commit 529fd6d as the sole missing commit. Fast-forwarding to that commit
and running the ordinary sync command created all four discovery links; no new
runtime release or manual symlink creation was required for this repair.


Release preflight (2026-10-15): cached `nix fmt` missed three required blank lines
in two existing Haskell files. `nix fmt -- --no-cache` made those whitespace-only
changes; the subsequent clean Nix treefmt and all other native checks pass. A
cached formatting success alone is insufficient evidence for the release gate.

Reopening (2026-10-15): remote-backed update already resolves the producer catalog
without installation. The real consumer's empty-cache preview nevertheless claimed
unchanged-version producers had changed content, because a missing old cache hash
was treated as evidence of change. The fix only emits that warning when both hashes
exist and differ; output reconciliation still detects same-version generated-byte
changes against project baselines. Both evidence-present and empty-cache cases pass.

Reopening (2026-10-15): adoption only removes an index entry; it never changes the
working link. Recovery must therefore preserve a later working-link edit rather
than blindly restoring its snapshot. Version-3 journals retain individual index
object IDs, restore only missing entries, and refuse conflicts before restoration.
Existing version-1 and version-2 recovery remains supported.

Review (2026-10-15): applying an old producer with the current runtime does not create an
old-schema fixture. `seihou-cli/src-exe/Seihou/CLI/Run.hs` writes
`currentManifestVersion`, currently 9, regardless of the producer version. The released
v0.9.0.0 runtime writes schema 6; use it to establish the legacy application before switching
to the supporting runtime. This repository's committed schema-7 application supplies a
separate real-consumer transition in Milestone 4.

Review (2026-10-15): Seihou 0.10.0.0 is published on Hackage and its upstream v0.10.0.0 tag
includes checkout sync. It is the released runtime candidate for the acceptance tests;
publication alone does not prove the new producer compositions work with it.


Implementation (2026-10-15): the released 0.10.0.0 runtime supports both actual
producer compositions without engine changes. Parent module definitions remain at their
existing versions; only link-skill (0.3.0) and claude-skill-link (0.2.0) advance.
The selected published schema is 367b0a1390ac1ed3dda6e2cacfdf3e72b1f624df, integrity
sha256:ef20d62c240dfe0e1126e05534d58c467188af4198307ad3c2a4a713bcd93505.

The unmodified documentation generator emits a final blank line in section indexes,
including existing indexes. Regeneration adds that convention to the changed modules
index, so ordinary git diff --check reports only that line. Generation is byte-stable;
`git -c core.whitespace=-blank-at-eof diff --check` validates other whitespace without
hand-editing generated output or changing repository configuration.


Consumer rehearsal (2026-10-15): the existing consumer tracks
`.agents/skills/master-plan` as a Git symlink. Targeted update correctly refuses it with
checkout_path_tracked. Removing only that index entry (`git rm --cached`, retaining the
working link) is required to adopt the ignored checkout declaration. The unrelated tracked
`.claude/skills/update-seihou-schema` stays intact; final snapshots therefore preserve literal
tracked symlink bytes and account for its already-existing parent directory. After untracking,
the remote-producer rehearsal upgrades schema 7 to 9, adds four declarations, preserves all
managed file bytes and saved variables, and leaves the Nix application and file records
identical. No inference-bearing manifest conversion is required.


## Decision Log


Decision (2026-10-15, team workflow): the user rejected the individual-checkout
repair as a substitute for a product fix. The normal sync CLI now owns discovery
and explicitly accepted adoption when declarations are absent. This supersedes
the earlier CLI restriction that empty-declaration sync could only suggest an
update command. The restoration engine remains offline and manifest-read-only;
adoption uses the existing checked update transaction and includes necessary
shared owners automatically in its preview. JSON alone does not approve adoption;
`--yes` is available for automation. No paths or shell receipts are interpreted as
link declarations, and no Git pull is hidden inside sync.

Decision (2026-10-15, reopening): the user rejected the manual adoption workflow
and requested a fix. Extend this plan rather than declaring a separate completed
mechanism sufficient. Remote-backed update already fetches candidate artifacts;
remove redundant prerequisite installation instructions and prove the empty-cache
path. A tracked-symlink transition must be a visible, accepted update operation,
limited to eligible matching links, with stale-state checks and rollback/recovery.
Sync remains manifest-read-only and must never mutate the Git index or infer desired
links from historical shell commands. Update ADR 0018 to distinguish an explicit
accepted adoption from silently untracking arbitrary paths.

Decision (2026-10-15, reopened delivery): the source implementation and released
delivery are distinct milestones. Engine/CLI changes now require a supporting
runtime release under the original release requirement, so leave this plan open
for milestone 7. Do not silently replace the user's Nix-profile executable or
describe an unreleased source build as the already-installed fix.

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


Team workflow remains open for final release delivery. The source candidate was
exercised with the ordinary interactive `seihou sync` command from a disposable
copy of the real schema-6 consumer at 5cb50ca, empty XDG configuration/cache, and
no discovery links. One acceptance created all four links. Committing that result
and cloning it with a second empty configuration let a teammate run the same
command: four links created, then four unchanged, with manifest bytes and tracked
state preserved. A second real consumer at c7c315a^ includes Nix scaffolding;
sync selected only the planning-skill composition and previewed tracked-link
adoption. Its Nix application and exclusively owned file records stayed identical;
no managed source bytes changed. Evidence checkouts are under
`/tmp/seihou-107-team-proof-wck7hbzy`. The CLI suite passed 746 cases, including
adoption, no-consent refusal, dry-run, unrelated required inputs, collisions,
tracked-link staging preservation and a fresh teammate clone. Final integrated
release gates pass: format, build, 1,997 tests (1,200 core, 746 CLI, 51 extension),
four native Nix checks, all three warning-free cabal checks, and whitespace
validation. Published-executable acceptance remains outstanding. The rebuilt
0.10.2.0 (30b0d5b) candidate repeated the untouched schema-6 interactive acceptance
and teammate-clone proof; retained result:
`/var/folders/fn/022xr90s5mz417hz7fllrhv80000gn/T/seihou-107-release-proof-de_y6bxa/result.json`.
Its complete guidance audit passes: 18 help topics, 32 command-help pages,
26 packaged assets, four validated module examples and eight provider-free
prompt renders. Semantic review also corrected a malformed blueprint migration
example and an over-specific schema-transition claim; the corrected blueprint
validates through the candidate executable. All three 0.10.2.0 source archives
and Haddock bundles are prepared; the two private-library bundles are repacked
for Hackage. Packaged help/context bytes match the reviewed sources, and the
dependency plan has only released registry dependencies plus local workspace
components. Release version/changelog confirmation and publication remain open;
no 0.10.2.0 tag, upload or installed-release claim has been made.

All seven original milestones completed on 2026-10-15; the affected remote
checkout was repaired and verified separately later that day, as recorded below.
That earlier update-then-sync workflow was delivered in released and installed
Seihou 0.10.1.0. The current one-command workflow still needs milestone 9. Published producer commit
455d2d6c50ddea5f658443d19d71b05733fc620b in `mori://shinzui/agent-seihou`
provides link-skill 0.3.0 and claude-skill-link 0.2.0. The unchanged parent versions
(master-plan/exec-plan 0.12.0 and update-docs 0.1.0) discover their updated link
dependencies through ordinary application/update. No engine change or additional
runtime release was necessary for the original four milestones; the reopened
tracked-link adoption requires the additional runtime release in milestone 7.
Released Seihou 0.10.0.0 (de4c4cf) is the minimum
tested runtime; 0.9.0.0 (3fe7576) establishes the legacy schema-6 fixtures and
refuses the new strategy before recording outputs.

Validation passed: 20 Bun cases with 330 assertions; eight real-binary checkout cases
with 241 assertions repeated using remotely installed producer bytes; five module
validations; Mori descriptor type checking; and byte-stable regeneration of all 18
generated documentation files. Running the schema-6 transition test against the fixed
old producer snapshot fails specifically on absent checkout declarations. Both runtime
builds succeeded. Producer whitespace validation retains only the unchanged generator's
section-index EOF convention described above. Seihou's normal diff and commit hooks pass.

Consumer adoption commit c7c315a2b72608490a008acd684bb25d1dfc8a0e contains only
`.seihou/manifest.json` and removal of the tracked `.agents/skills/master-plan` entry.
It advances schema 7 to 9, records the four required outputs, and preserves the source
files, saved variables, unrelated Nix application/file records, and legacy module records.
The isolated rehearsal and real update both reported 11 unchanged files, zero generated
file changes, zero commands executed, and no warnings.

The committed-consumer proof is retained at `/tmp/seihou-107-proof-hbn7su1d/result.json`;
its isolated clone has no installed producer artifacts. It records these concise outcomes:

```json
{
  "runtime": "seihou v0.10.0.0 (de4c4cf)",
  "dryRun": {"plannedCreated": 4, "appliedCreated": 0},
  "firstSync": {"plannedCreated": 4, "appliedCreated": 4},
  "secondSync": {"plannedUnchanged": 4, "appliedCreated": 0, "appliedReplaced": 0},
  "afterDeletion": {"appliedCreated": 1},
  "afterWrongTarget": {"appliedReplaced": 1},
  "linkedWorktree": {"appliedCreated": 4},
  "trackedBytesIndexAndManifestUnchanged": true,
  "producerArtifactsPresent": false
}
```

Every link has the literal target ../../agents/skills/exec-plan or
../../agents/skills/master-plan and resolves to its source SKILL.md. Dry-run creates
neither links nor new parents; existing parents for the unrelated tracked schema skill
remain intact. Git porcelain is empty after each consumer proof. Source files and
manifest are committed; discovery links are ignored and absent in the clone before sync.
The producer checkout and Seihou acceptance run were on macOS.

The durable lesson is that a correct engine and installed producer do not themselves
adopt a consumer. The application must record intent once, and a previously tracked
symlink must deliberately leave the index. These lessons are distilled into
[ADR 0018](../adr/0018-checkout-outputs-are-observable-portable-declarations.md) and
[the sync guide](../cli/sync.md); historical plan 105's engine-only boundary is preserved.


Reopened implementation evidence is retained at
`/tmp/seihou-107-ux-mowg21vl/result.json`. In a disposable checkout of the actual
pre-adoption consumer (`c7c315a^`), the current source executable completed ordinary
interactive `seihou update master-plan` with empty XDG configuration/cache. Its
preview proposed adopting `.agents/skills/master-plan`; acceptance staged just that
removal and changed the manifest. All other tracked content, the unrelated Nix
application/version and the source skill bytes were preserved. Eleven managed files
were unchanged; zero commands executed; the final preview had no false same-version
warnings. A separate pending preview detected a newly staged link target and
returned `plan_stale`, preserving the changed index and manifest byte-for-byte.

The adopted disposable commit is bf082cd9732022d4b50b733260201b5366a2aee8. Its
fresh clone has an empty producer cache and reports:

```text
Links: 4 created, 0 repaired, 0 unchanged.
Links: 0 created, 0 repaired, 4 unchanged.
Links: 1 created, 0 repaired, 3 unchanged.  (after deletion)
Links: 0 created, 1 repaired, 3 unchanged. (after wrong-target replacement)
```

The clone's manifest and index remain byte-identical through sync; every link
reaches its committed SKILL.md. Executable regression fixtures also prove the
legacy command-to-declaration transition with empty-cache remote update, cancellation,
dry-run, unrelated staged/unstaged edits, safe refusal and failed-command rollback.
Final-candidate validation: `cabal test all --test-options=--hide-successes`
passes all 1,991 tests (1,200 core, 740 CLI, 51 extension); the focused checkout
suite passes 33 core and 23 CLI cases. Fourmolu checks and `git diff --check` pass.
The subsequent release delivery below supersedes this source-only checkpoint.


Final installed-release acceptance (2026-10-15) uses only
`/Users/shinzui/.nix-profile/bin/seihou`, reporting 0.10.1.0 (c3bb42b).
`/tmp/seihou-107-haskell-nix-ordinary-0oo4fry2/result.json` proves the screenshot
consumer's exact pre-change commit (5cb50ca, schema 6) with an empty cache: the
ordinary interactive command `seihou update master-plan` and its one acceptance
prompt record four declarations, preserve saved inputs, index, `.gitignore`
customizations and unrelated tracked bytes, and require no manual preparation.
`/tmp/seihou-107-release-proof-nyj3cphs/result.json` repeats the original tracked-link
consumer transition with that installed release, including previewed index adoption.
`/tmp/seihou-107-proof-3wesvty2/result.json` proves the committed screenshot consumer
in an empty-cache clone and linked worktree: four creations, four unchanged on the
second sync, one creation after deletion and one replacement after retargeting.
Tracked bytes, index and manifest remain identical throughout sync. All 20 producer
Bun tests (330 assertions) and five actual module validations pass with the installed
release. In the local copy of the screenshot consumer, ordinary update says `Already up to
date.`, status says `Checkout outputs: 4 declared, 0 need attention.`, and sync
reports four unchanged. Both the runtime release and consumer adoption are pushed.

The final ADR distillation confirms ADR 0018 already captures recoverable explicit
adoption, immutable manifest-driven sync, and the distinction between optional remote
producer caches and actual project damage. No additional architecture decision is
needed. The delivery lesson is to prove the installed executable against the actual
reported consumer before declaring the user-facing workflow complete.


Actual remote acceptance (2026-10-15): connected as shinzui@yujin.local and
located `mori://shinzui/haskell-nix` through that machine's Mori registry. The normal
workflow for this existing clean checkout was to receive the committed adoption
and materialize its checkout outputs:

```bash
git fetch origin
git merge --ff-only origin/master
seihou sync
seihou sync
seihou status
```

The first sync reported `Links: 4 created, 0 repaired, 0 unchanged.` The second
reported `Links: 0 created, 0 repaired, 4 unchanged.` Status reported
`Checkout outputs: 4 declared, 0 need attention.` Both exec-plan and master-plan
were verified with `test -L`, `readlink`, and a reachable `SKILL.md` in each of
`.agents/skills` and `.claude/skills`. Their literal targets are
`../../agents/skills/exec-plan` and `../../agents/skills/master-plan` respectively.
Git status remained clean and the existing `.gitignore` customization remained.
This is the first acceptance evidence from the actual affected machine; prior
local and disposable proofs must not be described as remote verification.


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

### Reopened delivery: usable update and sync

Start in `seihou-cli/src/Seihou/CLI/Update.hs`, where `planCheckoutUpdate`
currently fails on tracked destinations before a preview can be rendered, and
`seihou-cli/src-exe/Seihou/CLI/Update.hs`, which already previews and confirms an
ordinary human update. Carry explicit adoption operations through the update plan
and renderer. Only a newly declared destination whose HEAD/index/working entry is
an unchanged symlink matching the candidate's canonical relative target is eligible;
regular objects, staged edits, conflicting links, tracked ancestors, and unrelated
entries remain protected. Check ignore rules as though the eligible path were
untracked. Preserve the working link, remove only the accepted index entry, and
include that operation in transaction recovery. Dry-run and cancellation must not
touch the index. Keep sync's existing strict tracked-path refusal.

Inspect `seihou-core/src/Seihou/Engine/UpdateTransaction.hs` for durable recovery,
`seihou-cli/src/Seihou/CLI/Update/Types.hs` and
`seihou-cli/src/Seihou/CLI/Update/Render.hs` for plan/output changes, and
`seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs` plus
`seihou-cli/test/Seihou/CLI/CheckoutSyncE2ESpec.hs` for existing real-command fixtures.
Extend focused tests rather than duplicating the legacy producer suite. Prove the
empty-cache remote update before broadening variants; expose dependency resolution
defects if that representative path fails.

In `seihou-cli/src/Seihou/CLI/CheckoutSync.hs`, replace the generic empty-declaration
notice with actionable commands derived from recorded application targets. Do not
claim that an arbitrary old application has an available newer declaring release.
Provide a concise human summary of actual sync outcomes while preserving JSON's
planned/applied distinction. Update `docs/cli/sync.md`, `docs/cli/update.md`, CLI
help, and ADR 0018 to teach ordinary update for existing projects and sync for
clones. Original multi-module installation commands below remain historical test
setup, not the recommended existing-project interface.

From the repository root run `cabal build exe:seihou` and focused CLI/core test
patterns while iterating, then `cabal test all` and `git diff --check`. Use the
repository development environment if the current shell lacks dependencies. Show
that the first sync in a fresh adopted clone creates the expected links, a second
sync changes nothing, and tracked bytes and manifest bytes are preserved. Record
concise results here before checking off milestones 5 and 6. Milestone 7 retains
the original supporting-release obligation now that runtime code has changed:
follow the release skill, verify current upstream versions before choosing the
PVP release and bounds, then repeat the ordinary-update and fresh-clone proof
with the released executable. This delivery is now Seihou 0.10.1.0 (c3bb42b),
including the installed Nix-profile executable. For source-development reproduction,
use the executable reported by `cabal list-bin exe:seihou` from the consumer's root
and distinguish it from the installed release. Preserve producer versions
unless their definitions change, and do not replace a Nix-managed binary in place.

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

Untrack the existing `.agents/skills/master-plan` discovery symlink with `git rm --cached .agents/skills/master-plan`, retaining its working-copy link; it cannot remain a tracked destination under the checkout contract. Preserve the unrelated tracked `.claude/skills/update-seihou-schema` link. Apply the proven update in this real checkout while preserving unrelated working changes.
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

Reopened acceptance additionally requires milestones 5–7 above. Exercise an
existing remote-backed application with no installed producer modules using only
the public update command. Its preview must explain any eligible tracked-link
transition; accepting updates intent and stages exactly those removals while
preserving working links and unrelated staged/unstaged changes. Dry-run,
cancellation, ineligible paths, stale plans and failed transactions must not leave
partial index transitions. Recovery must restore an interrupted uncommitted
transition. After adoption, a clone needs only sync, and the human result explains
what changed. An old manifest with no declarations must name its recorded update
target instead of making the user discover producer dependencies. Existing engine
refusal and immutable-sync tests continue to apply.

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

Revision (2026-10-15, implementation): recorded verified producer publication,
released-runtime acceptance and consumer adoption. The real consumer's pre-existing
tracked discovery link required intentional untracking while retaining its working link;
final snapshot checks preserve unrelated tracked symlink text and existing parents.
All original functional acceptance criteria remain satisfied.

Revision (2026-10-15, reopening): the user rejected the delivered adoption UX.
Retained milestones 1–4 as historical evidence and added unfinished milestones 5–6
for a normal update flow, explicit recoverable tracked-link adoption, actionable
sync guidance, and real-command acceptance without manual setup.

Revision (2026-10-15, reopened implementation): completed and verified source
milestones 5–6, including the real interactive pre-adoption consumer and fresh
clone. Added milestone 7 to retain the original runtime-release requirement now
that the fix changes runtime code. The plan remains open for released delivery.
