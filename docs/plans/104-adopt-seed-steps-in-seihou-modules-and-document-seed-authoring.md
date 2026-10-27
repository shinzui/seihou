---
id: 104
slug: adopt-seed-steps-in-seihou-modules-and-document-seed-authoring
title: "Adopt seed steps in seihou-modules and document seed authoring"
kind: exec-plan
created_at: 2026-09-19T13:59:13Z
intention: "intention_01m2wz5ww3ezmvpf0aenfbgcjx"
master_plan: "docs/masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md"
provenance:
  created_by:
    model: "claude-opus-5[1m]"
    harness: "claude-code"
    at: 2026-09-19T13:59:13Z
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-27T00:43:50Z
      mode: "update"
      note: "Refresh producers and require one-command adoption plus released installed-binary evidence"
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-27T02:20:02Z
      mode: "implement"
      note: "Audit current producer classifications and prepare isolated CLI seed candidate for early adoption proof"
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-27T00:43:50Z
      verdict: "approved"
      note: "Reviewed revised plan against current source and cross-plan contracts; approval is for implementation design, not runtime delivery"
---

# Adopt seed steps in seihou-modules and document seed authoring

This ExecPlan is a living document. Maintain Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective.

This is EP-6 of [MasterPlan 12](../masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md).
Milestone 1 is read-only classification plus a disposable candidate for early integration and
has no hard dependency. Milestones 2–4 require completed
[plan 101](101-create-seed-files-once-during-seihou-run.md),
[plan 102](102-keep-seed-files-out-of-status-diff-and-remove.md), and
[plan 103](103-reconcile-seed-steps-during-seihou-update-and-release-managed-files-to-seeds.md).
The declaration is provided by [plan 99](99-declare-seed-steps-in-the-module-schema-and-validate-them.md).

## Purpose / Big Picture

Project authors receive editable starter files without permanent drift warnings or future
module updates overwriting them. Producers declare `lifecycle = Some "seed"`; existing
projects adopt through one ordinary command:

```bash
seihou update haskell-cli-app
```

That command fetches candidates/dependencies and reuses saved inputs. Its normal confirmation
includes managed-to-seed releases; no per-file release prompts or manual manifest/index work
are required. Fresh users still install the registry once and run their chosen module. A
fresh clone of an adopted project uses committed receipts: an absent settled seed stays absent,
even with an empty cache; checkout setup remains the separate ordinary `seihou sync` workflow.

## Progress

- [x] (2026-10-27) Milestone 1: current three-module classification and command/removal audit supplied the early producer candidate for EP-5's real-consumer proof.
- [x] (2026-10-27) Milestone 2: publish runtime support first, then CLI 0.4.0, library 0.3.0 and Keiro project 0.3.0 with validated seed declarations and current catalog docs.
- [x] (2026-10-27) Milestone 3: installed released runtime passes fresh, real existing, cloned/worktree, repeated and removal workflows using the public registry and empty caches.
- [x] (2026-10-27) Milestone 4: current user/author guides, both changelogs, CLI agent context, conceptual and compiled command help, and cross-repository ADR delivery evidence are published.

## Surprises & Discoveries

Final installed-command review (2026-10-26 Pacific): published/installed 0.11.0.0
passed all public-source acceptance, but `remove --help` still contained the old
universal removal-specification restriction and a checkout-only selector label.
Conceptual topic/render checks did not establish parser-footer correctness. The
patch 0.11.0.1 updates compiled run/update/remove/status/diff/migrate and agent-run
help, with a targeted audit of these lifecycle promises. Seed-only installed
removal also passes: no custom spec, immutable preview, exact retirement and
preservation of edited bytes under force. The patch changes guidance only; runtime
seed semantics remain those shipped in 0.11.0.0. Its published and installed checks
now pass; the release evidence below closes this gate.

Native packaging check (2026-10-26 Pacific): all 2,080 Cabal tests and the 0.11.0.0
help/context audit pass (18 topics, 32 command pages, six example modules and eight
provider-free renders). Actual `nix build .#default` found FRIC-2: the composed
`mori://shinzui/haskell-nix` scope resolves Hspec/core/discover 2.11.18 but leaves
hspec-api 2.11.17, whose exact core bound refuses configuration. The local overlay
now selects published hspec-api 2.11.18 with its tarball hash; Hackage normal status,
exact core bound and upstream 2.11.18 tag were verified. The next native check
found tasty-hspec 1.2.0.4 revision 8 caps QuickCheck below the scope's 2.18;
Mori-local adapter source passes arguments between same-scope Hspec and
`tasty-quickcheck` rather than importing QuickCheck internals. Its latest registry
release/revision and upstream v1.2.0.4 tag were checked. A scoped jailbreak retains
all native package tests to verify compatibility. No application dependency bound
changed. The same packaging review found Git-only fixture schema lookup would
fail after Nix stages a plain source tree. The builder now records the fetched
schema revision and tests copy it only when it matches the executable pin; native
Git-backed fixtures continue preserving the developer's submodule state. Native package acceptance now passes with all 1,251 core, 778 CLI and 51 extension
tests enabled. Hackage Haddocks for all three packages build, and private-sublibrary
archives are flattened/repacked by the release recipe. FRIC-2 is resolved by this
verified scope correction. The root Cabal suites independently pass with their
resolved released dependency versions. Publication follows these completed gates.


Release authorization (2026-10-26 Pacific): the user approved runtime 0.11.0.0,
producer publication and installation, then explicitly required all relevant docs,
CLI agent context and help guides to be updated. Package versions and all five
internal core bounds are now 0.11.0.0; release notes and current guides describe
the complete runtime rather than the old source-only/temporary refusal state.
The semantic review covers all 18 help topics and seven task templates plus the
shared module reference. It corrects old removal restrictions, stale update and
recovery guidance, default force wording and blueprint seed ownership; the upgrade
playbook now names seed release/adoption remedies. The provider-free audit also
validates a sixth example module containing the exact documented seed declaration.
Authorization alone did not close delivery; the published/installed checks below now pass.


Producer refresh (2026-10-27): while EP-5 proceeded, the producer advanced to
`b017e386856575da9b6d28059a22942bb6f63c2b` and the Keiro template became 0.2.0.
The earlier 19-step Keiro candidate is historical preparation, not the final
classification. Re-reading current source added OpenAPI/probe tests, API/fixture
starter configuration and optional Mori inventory to seed ownership. The maintained
Nix tools import and `scripts/keiro-test-env` remain managed. No root/nested
AGENTS.md or CLAUDE.md exists in that producer checkout. Existing intervening commits
were retained. Upstream HEAD/registry confirmed CLI 0.3.1, library 0.2.0 and Keiro
0.2.0; no artifact release tags exist. The release candidate advances those to
0.4.0, 0.3.0 and 0.3.0, rather than reusing the early disposable CLI 0.3.2 version.


Review (2026-10-26): Mori's registry snapshot lagged the producer working tree. Direct reads
show `haskell-cli-app` 0.3.1 with additional root-module/test, per-package changelog/license,
and managed `nix/haskell-cli-app.nix` steps; `haskell-library` is 0.2.0. The old plan's ten-step
0.2.0 CLI list is obsolete. `docs/cli/update.md` already promises direct remote fetching, so
requiring `seihou upgrade` first is unnecessary. `git diff --exit-code` against HEAD cannot
prove preservation of edits that already existed before update.

## Decision Log

Decision (2026-10-26): classify current destinations by ongoing ownership, not file extension.
Cabal files, application sources/tests, changelogs, README, and domain implementation starters
are seed candidates. Generated package integration such as `nix/haskell-cli-app.nix`, policy
licenses, and shared configuration remain managed where releases must continue updating them.
Review `cabal.project`, `justfile`, workspace declarations, and implementation briefs against
actual producer intent. Do not freeze a stale list or assume every generated Nix file is a seed.

Decision (2026-10-26): release runtime support before publishing producers that promise seeds.
Older binaries can ignore the field and overwrite project-owned files; that is not a harmless
status-only fallback. This initiative does not add a module minimum-client-version schema,
but producer docs state the verified minimum release and a compatibility check records old-client
behavior. Keep delivery open until the authorized publication/install steps are completed.

## Outcomes & Retrospective

All four milestones and delivery gates are complete. The released/installed evidence below supersedes the earlier source-preparation status.
Producer commit `3bfe34f` in `mori://shinzui/seihou-modules` changes only classified
lifecycle/schema/version declarations, corresponding author/registry/generated docs,
the producer ADR and existing acceptance assertions. No producer template bytes,
application dependency bounds, or unrelated producer history were changed. The
published lifecycle-capable schema pin is
`7d02695f5a716384ec2174a018c20ee680ab3d13`; its integrity hash is preserved in the
three declarations. Existing direct commands/removals/migrations remain absent.
Nix dependency historical migration paths were re-audited and do not target seeds.

| Artifact | Published version | Seeds | Managed |
|----------|-----------|-------|---------|
| `mori://shinzui/seihou-modules/templates/haskell-cli-app` | 0.4.0 | 12 | Nix package integration and three licenses |
| `mori://shinzui/seihou-modules/templates/haskell-library` | 0.3.0 | 7 | License and fourmolu policy |
| `mori://shinzui/seihou-modules/templates/haskell-keiro-project` | 0.3.0 | 28 | Seven licenses, .gitignore patch, Nix tools and test-environment helper |

The Keiro seed list includes conditional Mori inventory; CLI/library test starters
remain conditional. The producer scripts now verify settled seed preservation under
changed namespace inputs, force, authored edits and deletion, rather than expecting
managed conflicts. All module validation passes with lint; pre-existing advisory
unused/default-only-variable findings remain. Registry versions validate and 18 OKF
concepts were regenerated using the source-built extension. Catalog documentation
commit `fbb42b3` also exposes project ownership and the minimum runtime directly
in registry descriptions and generated concept summaries; module output bytes
remain those accepted at 3bfe34f.

Source validation evidence, using Seihou development 0.10.1.0 at runtime commit
`5ad7c32` (publication version unchanged):

- Ordinary empty-cache registry install (one `install URL --all`) and one library
  run with explicit ordinary project variables produced seven receipts; repeat
  `update haskell-library` was a no-op and preserved an authored changelog. The
  isolated HOME Git configuration redirected the public producer URL to the local
  candidate commit; no user installation was changed. Evidence locator:
  `/tmp/seihou-seed-library-project` records the project path; `evidence.json`
  is alongside that project directory.
- Native library `nix develop --no-write-lock-file -c cabal build all` and `cabal test all`
  pass, with status/diff excluding edited seeds. Existing library Cabal metadata
  warns about parent-relative LICENSE/CHANGELOG paths when packaging; seed changes
  preserve those bytes. This is a pre-existing distribution limitation, not a failed
  build/test hidden by fixture repair.
- The producer's CLI bootstrap `--case cli-bare` passes actual generation, canonical
  lock, Nix evaluation/native package build, compiler shell and repeat generation.
  Evidence is `/tmp/seihou-seed-cli-native/receipt.json` and its command logs.
- The producer's full Keiro check passes both names/contexts, six Cabal package
  checks, workspace/recipes, Mori/Cabal parity, interactive opt-in/skip through
  module and agent baseline, and seed preservation. Its `--live` acceptance also
  builds/tests all six packages and proves private PostgreSQL fixtures, distinct
  leases, generated probes/OpenAPI/Hurl assertions, failure propagation, service
  shutdown and clone cleanup. The retained fixture/log locator is
  `/tmp/nix-shell.kaqwm1/seihou-keiro-bootstrap-hqkjdg1l/.artifacts/acceptance`.
- The actual Reiko working state at `eb3f9cb54534c68f4c0c67e64856273edcb30f71`
  passed ordinary adoption in EP-5; a new copy against producer 3bfe34f also
  previews and applies 12 seeds with lossless schema 10→11, preserves all three
  edited snapshots, and returns `Already up to date` on repeat. Cancellation preserves manifest,
  index and separately saved edited changelog/Cabal bytes. The disposable fixture
  is located by `/tmp/seihou-seed-final-adoption.json`.
- Fresh clone and detached worktree, both with committed receipts and a deliberately
  deleted changelog, report `Already up to date` with empty installed caches and
  preserve deletion/manifest bytes. Evidence locator:
  `/tmp/seihou-seed-portable-evidence.json`.
- Installed `/Users/shinzui/.nix-profile/bin/seihou`, version 0.10.1.0 at c3cbd9b,
  demonstrably ignores seed lifecycle, records managed hashes and overwrites edits
  under force. The compatibility check used a disposable one-file module only.
  `/tmp/seihou-seed-old-client-evidence.json` locates its receipt. This confirms
  runtime release must precede producer publication; decoder support is insufficient.

### Published and installed acceptance (2026-10-27 UTC / 2026-10-26 Pacific)

Runtime release `v0.11.0.0` is commit `5bd3002bbe555d53a391b65f4e3afe6b8ec12678`.
All three packages were published in dependency order, with Hackage normal-version
JSON and actual uploaded module-documentation pages verified. Producer `master`
was then published through `9cea336fea6f3397e1bfdb966fb6259784c881c9` in
`mori://shinzui/seihou-modules`. Registry declarations expose CLI 0.4.0, library
0.3.0 and Keiro project 0.3.0; their output bytes are those accepted at `3bfe34f`.
No artifact-tag convention existed, so publication used the registry's normal Git
HEAD workflow. Runtime 0.11.0.0 preceded seed-producing publication; old-client
safety was never inferred from decoding success.

Final help patch `v0.11.0.1` is commit
`4ade3fb63a0ec550b8a519d61b76c18b8de59b62`. It changes compiled guidance and the audit without changing seed runtime semantics. All three lockstep packages
and their Haddocks are public on Hackage. The GitHub release is
[0.11.0.1](https://github.com/shinzui/seihou/releases/tag/v0.11.0.1), following
[0.11.0.0](https://github.com/shinzui/seihou/releases/tag/v0.11.0.0).
Both source distribution sets were created from clean detached release checkouts.
The published Nix tag builds with native package tests enabled. Independent Cabal
and native suites pass 1,251 core, 778 CLI and 51 extension tests (2,080 total);
all three `cabal check` runs, formatting and four flake checks pass. One existing
completion expectation caught changed help-prefix wording; the retained prefix and
seed clarification pass the repeated CLI suite before patch publication.

The user's executable is `/Users/shinzui/.nix-profile/bin/seihou`, reporting
`seihou v0.11.0.1 (4ade3fb)`. The profile selects the public GitHub tag at this
exact commit, ahead of the retained Home Manager package; no unrelated system
configuration was activated. The installed audit passes 18 topics, 32 top-level
command pages plus nested agent-run help, 26 packaged assets, six actual authoring
examples and eight provider-free prompt renders. It verifies seed eligibility,
preservation and consent guidance in compiled command help as well as embedded
topics/context. The source-only proofs above are not substituted for this result.

Installed/public-source acceptance uses isolated empty HOME/XDG caches with no
Git URL rewrite or substituted registry. The normal fresh sequence is:

```bash
seihou install https://github.com/shinzui/seihou-modules.git --all
seihou run haskell-cli-app
```

The second command resolves ordinary project and dependency prompts. Automation
supplies the three project values plus the two Nix service choices through the
normal `--var` flags for CLI/library; it performs no internal repair. The Keiro
provider-free `seihou agent --debug run haskell-keiro-service` baseline also exercises
opted-in Mori inventory. All three record 12/7/28 receipts, preserve authored edits
and deletion through forced reruns, report seeds without content comparison, and
return `Already up to date` without manifest changes on ordinary update.

An isolated copy of actual `mori://shinzui/reiko` tracked working bytes at
`eb3f9cb54534c68f4c0c67e64856273edcb30f71` starts from its saved schema-10 manifest,
legacy CLI application, recorded SSH producer origin and empty cache. The only
adoption command is:

```bash
seihou update haskell-cli-app
```

Normal confirmation previews `release to project`, includes the recorded Nix
dependency and losslessly prepares schema 11. Cancellation preserves manifest,
index and existing edits; acceptance preserves the changelog and both Cabal files,
records 12 receipts and repeats as a no-op. The actual Reiko checkout is untouched.
A fresh clone and detached worktree each retain committed receipts and a deliberately
deleted changelog through ordinary update with separate empty caches. A generated
project-local seed-only module also passes immutable removal preview and
`seihou remove release-seed-removal --force` without a custom spec, retiring its
claim while preserving authored bytes.

Retained evidence: `/tmp/seihou-release-acceptance-root` locates the final receipt
and 25 ordinary-command logs (plus interactive cancellation/apply transcripts);
`/tmp/seihou-release-removal-root` locates the removal receipt.
`/tmp/seihou-release-patch-installed-audit.log` records the installed audit;
`/tmp/seihou-release-patch-tag-build.log` records the released Nix build.
The final acceptance root is
`/var/folders/xf/z_902qyd0dg5m6n8pjv1vk300000gn/T/seihou-released-acceptance-4buauofb`.
These are disposable acceptance artifacts, not prerequisites imposed on developers.

ADR 0017 and the producer Keiro ADR record final release-order and delivered
workflow evidence; the producer ADR completion is commit `556b217` in
`mori://shinzui/seihou-modules` (documentation only). FRIC-1 is resolved across
the initiative; this child's
[FRIC-2](../friction-log/2-native-nix-test-scope-mixes-incompatible-hspec-releases.md)
is resolved with verified Hspec scope alignment and all native tests retained.
No release, installation, producer adoption or documentation gate remains open.

## Context and Orientation

Discover the producer with Mori, then read its own agent instructions before editing:

```bash
mori registry show shinzui/seihou-modules --full
mori registry docs shinzui/seihou-modules
```

Canonical artifacts are `mori://shinzui/seihou-modules/templates/haskell-cli-app`,
`mori://shinzui/seihou-modules/templates/haskell-library`, and
`mori://shinzui/seihou-modules/templates/haskell-keiro-project`. At review time the checkout is
`/Users/shinzui/Keikaku/bokuno/seihou-modules`; paths in commands are locators, not durable
cross-repository identities. Their module directories contain `module.dhall`, templates,
README, commands, and optional removal declarations. Read recipes and the Keiro blueprint
that compose them; their public workflow must retain dependencies and saved inputs.

The schema pin is recorded in this repository's `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`;
use an already published compatible schema, preserving checkout command fields. Re-pinning
must not change the user's dirty schema submodule incidentally. The receipt minimum is
historically schema 8; current code is schema 10 and plan 100 adds exact-owner versioning.
Use the implemented current version in acceptance, never assert every manifest is version 8.

[ADR 0017](../adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md) defines
settlement and lifecycle transitions; [ADR 0018](../adr/0018-checkout-outputs-are-observable-portable-declarations.md)
separates checkout repair. Relevant producer decision: `mori://shinzui/seihou-modules`,
project-relative `docs/adr/2-separate-keiro-project-seeds-from-domain-implementation.md`
(artifact-level URI pending because this plain ADR corpus has no discovered artifact handle).
It makes generated Keiro libraries project-owned starters, rather than complete domain implementations.

## Current producer audit (2026-10-26)

Source is `mori://shinzui/seihou-modules` at revision
`f822a12aa5657fdae90bab297b19491f8b26e5d9`. No root or nested AGENTS.md was
present. Its unrelated untracked plan was left alone. Current declarations have
no direct commands, removals, or migrations in any of the three modules.

| Producer | Seed destinations | Retained managed destinations |
|---|---|---|
| `mori://shinzui/seihou-modules/templates/haskell-cli-app` 0.3.1 | `cabal.project`; both package Cabal files; core Prelude/root module; CLI Main/parser; conditional CLI test (`project.tests`); root and both package changelogs; README (12 steps total) | `nix/haskell-cli-app.nix`; root/core/CLI LICENSE |
| `mori://shinzui/seihou-modules/templates/haskell-library` 0.2.0 | `cabal.project`; package Cabal file; Prelude/root module; conditional test (`project.tests`); changelog; README (7 steps total) | root LICENSE; `fourmolu.yaml` |
| `mori://shinzui/seihou-modules/templates/haskell-keiro-project` 0.1.0 | `cabal.project`; core Prelude; workspace/shared DSL; justfile; README; bootstrap brief; all six package Cabal files and source stubs (19 steps total) | additive `.gitignore`; root and six package LICENSE files |

`cabal.project`, justfile, domain workspace/DSL and the implementation brief are
project-owned because applications extend them as implementation grows. Package
Nix wiring stays managed because it integrates shared packaging outputs. Licenses
remain policy-managed. The common dependency
`mori://shinzui/seihou-modules/templates/nix-haskell-flake` manages shared Nix,
lock, ignore, formatter, direnv, and optional service configuration. Its historical
migration deletes only `treefmt.nix`; the newer migration shell removes the old
`.envrc` ignore line. Neither targets the proposed seeds. No shell sandbox is
assumed. Current producer staging needs no generated Git step: normal Git usage
tracks both managed and seed outputs.

The isolated candidate is `/var/folders/xf/z_902qyd0dg5m6n8pjv1vk300000gn/T/seihou-seed-adoption-bv9n5e6n/producer` at local commit
`435643cd458674b5c346b5944badb0b21cfca124`, cloned with full recorded-release history from
the source revision. Its CLI declaration and registry entry are proposed 0.3.2,
with twelve seed steps and the executable's already-pinned published schema.
`seihou validate-module <candidate>/modules/haskell/haskell-cli-app --lint` passed
all validation and lint checks. This is neither a published release nor an installed
producer; the real producer checkout and user installation remain untouched.

The actual pre-seed consumer is `mori://shinzui/reiko` at source revision
`eb3f9cb54534c68f4c0c67e64856273edcb30f71`. Its tracked working-tree bytes (including the
schema-10 manifest, baselines, saved inputs, edited Cabal files and changelog)
were copied to `/var/folders/xf/z_902qyd0dg5m6n8pjv1vk300000gn/T/seihou-seed-adoption-bv9n5e6n/project` and committed only inside that disposable
fixture. Its recorded CLI module is 0.1.0, predating recorded applications; no
application, origin or ownership was repaired. Snapshots of root changelog and
both package Cabal files are stored outside the project in `/var/folders/xf/z_902qyd0dg5m6n8pjv1vk300000gn/T/seihou-seed-adoption-bv9n5e6n/before`.
The empty isolated configuration at `/var/folders/xf/z_902qyd0dg5m6n8pjv1vk300000gn/T/seihou-seed-adoption-bv9n5e6n/home` contains only Git URL
routing from the real recorded remote to the candidate repository. It contains
no installed modules or optional caches. Setup is fixture preparation, never a
step required of developers. EP-5 M2 owns running the ordinary update against
this preserved state; a legacy-adoption failure remains engine work.

## Plan of Work

### Milestone 1 — classify and supply early integration

Read current `module.dhall` files and list each resolved destination, conditional step, its
proposed lifecycle, and any command/removal/migration that mutates it. Record the result here.
Survey other modules for conflicts only; changing additional producers is outside this initial
three-module scope. Check generated seeds are included by normal Git staging/documentation.

In a disposable producer checkout, mark a minimal representative CLI candidate without
publishing it or changing the user's installations. Supply that candidate and its exact source
revision to EP-5 Milestone 2, together with an actual pre-seed consumer. This is an integration
artifact, not a release. Neither this milestone nor EP-5 waits for EP-6's completion, avoiding
a dependency cycle. Any integration failure remains work in the owning engine plan.

### Milestone 2 — author and prepare releases

After EP-3/EP-4/EP-5 complete, mark the agreed steps as seeds, use the compatible schema pin,
bump each module from its *then-current* version, and update producer README/generated docs.
Verify available versions against the upstream registry history and release tags where they
exist; Mori's local snapshot alone is insufficient. No dependency bounds are selected here.

Validate with the tested binary (`seihou validate-module <module-dir> --lint`) and regenerate
registry documentation using its current documented commands. Remove or revise declarative
removal/migration actions that would touch seeds; audit shell commands too, because lifecycle
checks cannot sandbox shell. No migration script should duplicate automatic managed-to-seed
release. Preserve useful managed Nix/package integration and verify fresh generated packages
still meet the producer's existing build acceptance.

Prepare Seihou release notes and producer changes as concrete reviewable artifacts. Record
which runtime release implements every command, not merely the lifecycle decoder. If publishing
or installing needs authorization under the active task, complete the local work first and
request only that remaining action; leave this milestone/delivery gate open until done. Follow
Conventional Commits with canonical cross-repository trailers:

```text
MasterPlan: mori://shinzui/seihou/masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project
ExecPlan: mori://shinzui/seihou/plans/104-adopt-seed-steps-in-seihou-modules-and-document-seed-authoring
Intention: intention_01m2wz5ww3ezmvpf0aenfbgcjx
```

### Milestone 3 — verify what a developer can run

Use disposable projects and isolated configuration/cache for acceptance. A local registry path
is suitable for source testing but does not prove remote fetching or release availability.
For delivery, use the published registry and the actual installed Seihou executable. Record
executable path/version, runtime source tag, producer declared versions and revisions, schema,
and all preparation commands. No prerequisite manual cache filling or internal JSON editing.

Fresh use has the ordinary one-time install followed by run (normal variable prompts are allowed):

```bash
seihou install https://github.com/shinzui/seihou-modules.git --all
seihou run haskell-cli-app
```

Edit a changelog and Cabal file, repeat run with force, and prove exact byte preservation;
delete a seed and prove no resurrection. Check status and diff show only managed drift. Repeat
the seed behavior for library and the Keiro baseline workflow using their current public commands.
Do not execute unrelated remote-creation commands as test preparation.

For existing use, preserve a real pre-change consumer with its remote origin and edits. From
an empty optional cache run only `seihou update haskell-cli-app`, accepting the normal preview.
No `seihou upgrade`, extra installation, transitive targets, or flag is part of the happy path.
Compare edited bytes with separately saved before-update snapshots using `cmp`; verify released
paths disappear from managed records, new absent seeds appear once, and a second update is a
no-op. A missing managed file becoming a seed remains missing. Exercise supported older
manifest schemas through the command's automatic lossless preparation; origin inference for
pre-schema-6 manifests remains the documented explicit migration boundary.

Commit the accepted fixture state, clone it and create a linked worktree with empty caches,
and verify receipts preserve deletion and seed edits. Run sync only for recorded checkout
setup; it must never seed or reapply modules. Test removal leaves seed bytes and removes only
the selected claims. Count commands and prompts separately for initial install, adoption,
repeat use, clone setup, and recovery; include unavoidable setup in the evidence.

### Milestone 4 — docs and durable evidence

In `docs/user/module-authoring.md`, explain when to choose managed/seed/checkout, supported
seed strategies, composition precedence, receipt lifetime, no reseed flag, explicit reverse
adoption, and shell limitations. Show one short seed declaration and ordinary adoption command.
Update `docs/user/CHANGELOG.md` and root release notes. State the minimum tested runtime release
and that older clients may still manage seed declarations. Do not describe unreleased work as available.

Update the producer Keiro ADR using its discovered local contract and cite this repository
with canonical Mori references. The current plain ADR fallback is project URI
`mori://shinzui/seihou` plus project-relative
`docs/adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md`, with artifact URI
pending; do not invent an unverified `adrs/...` handle. Record implementation/delivery evidence
in ADR 0017 and the MasterPlan, and distill durable lessons without copying task transcripts.

## Concrete Steps

From the producer checkout located through Mori:

```bash
rg -n 'dest|lifecycle|commands|removal' modules/haskell/haskell-cli-app/module.dhall modules/haskell/haskell-library/module.dhall modules/haskell/haskell-keiro-project/module.dhall
seihou validate-module modules/haskell/haskell-cli-app --lint
seihou validate-module modules/haskell/haskell-library --lint
seihou validate-module modules/haskell/haskell-keiro-project --lint
```

Resolve the source binary using `cabal list-bin exe:seihou` in this repository for local proofs.
Use the installed release for final delivery checks. Run the producer's existing generated-doc
and package checks, then this repository's `git diff --check` and relevant documentation checks.

## Validation and Acceptance

All three producers declare the correct files, preserve ongoing managed integration, and
pass their existing validation/build workflow. Fresh and existing consumers, clones/worktrees,
and removal show project ownership using ordinary supported commands. Runtime release,
published producers, and installed executable are recorded separately and all must pass before
calling this initiative delivered. No schema-only or local-checkout proof substitutes for that.

## Idempotence and Recovery

Acceptance uses disposable consumers/configuration. Preserve unrelated checkout changes and
fix published producer mistakes with a new version. Retrying update follows its normal recovery;
seed edits never require manual baseline repair. Removing the final receipt intentionally ends
settlement memory; document that later reapplication can create a missing path again.

## Interfaces and Dependencies

Milestone 1 supplies EP-5's candidate artifact without enabling published seed use. Later
milestones consume complete engine/reporting behavior and own producer release/adoption evidence.
No new core API is defined here. Local authoring-guide edits stay in this repository; producer
changes carry canonical project/artifact references.

Revision note (2026-10-26): refresh actual producers, move minimal consumer proof early, make
ordinary update own adoption, and keep publication/install evidence in the completion scope.
