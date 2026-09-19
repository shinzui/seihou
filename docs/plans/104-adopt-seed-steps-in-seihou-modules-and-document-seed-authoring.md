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
---

# Adopt seed steps in seihou-modules and document seed authoring

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

This plan is EP-6 of the MasterPlan
`docs/masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md`.
Hard dependencies, all of which must be Complete:
`docs/plans/101-create-seed-files-once-during-seihou-run.md` (EP-3),
`docs/plans/102-keep-seed-files-out-of-status-diff-and-remove.md` (EP-4), and
`docs/plans/103-reconcile-seed-steps-during-seihou-update-and-release-managed-files-to-seeds.md`
(EP-5). It also relies on the schema commit pushed by
`docs/plans/99-declare-seed-steps-in-the-module-schema-and-validate-them.md` (EP-1).

Most of the work happens in a second repository, the `seihou-modules` registry
(`mori://shinzui/seihou-modules`, checked out at `/Users/shinzui/Keikaku/bokuno/seihou-modules`;
confirm the path with `mori registry show shinzui/seihou-modules`). The rest is documentation
in this repository (`mori://shinzui/seihou`).


## Purpose / Big Picture

Seihou now supports *seed files*: a step marked `lifecycle = Some "seed"` in `module.dhall`
creates its file once, when the path is absent, and then hands it to the project. Seihou never
overwrites, content-tracks, merges into, reports, or deletes a seed; `seihou status` shows only
a count of them; and `seihou update` *releases* files that an earlier module release managed.
None of that helps users until the modules they install use it.

The trigger for this initiative was the `haskell-cli-app` module: it generates `CHANGELOG.md`,
`README.md`, two `.cabal` files, and three Haskell sources that every project edits on day one,
so `seihou status` reports them as `modified by user` forever. After this plan:

- `haskell-cli-app`, `haskell-library`, and `haskell-keiro-project` in `seihou-modules` declare
  their project-owned files as seeds and bump their versions.
- A new project generated from `haskell-cli-app` can edit its changelog, cabal files, and
  sources and still see a clean `seihou status` for the files the module keeps managing.
- An existing project upgrades with `seihou upgrade haskell-cli-app` followed by
  `seihou update haskell-cli-app`, and the formerly managed files are released without a
  prompt, keeping every edit.
- `docs/user/module-authoring.md` in this repository explains how to choose between a seed and
  a managed step, and `docs/user/CHANGELOG.md` announces the feature.


## Progress

- [ ] Milestone 1: classify every step of the three Haskell modules (and survey the other
      modules); record the classification in this plan's Decision Log.
- [ ] Milestone 2: re-pin the schema in the three modules, add `lifecycle`, bump versions,
      validate, and regenerate the registry's OKF docs; commit in `seihou-modules`.
- [ ] Milestone 3: verify with the real CLI — a fresh project and an upgrade of an existing
      project (edited files survive, status is clean).
- [ ] Milestone 4: authoring guidance and user changelog in this repository; seihou-modules
      ADR update; MasterPlan distillation hand-off.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Choose seeds by one test: "Will every project edit this file as part of normal
  development, in ways the module cannot predict?" Yes → seed. No, or the module must keep
  changing it across releases → managed.
  Rationale: The failure being fixed is status noise from files that were always meant to
  diverge. Files a module continues to own (formatter configuration, license text, Nix
  plumbing, `.gitignore` blocks) must stay managed so module releases keep reaching them.
  Date: 2026-09-19

- Decision: Initial classification for `haskell-cli-app` (confirm against the working tree in
  Milestone 1): seeds — `CHANGELOG.md`, `README.md`, `{{project.name}}-core/{{project.name}}-core.cabal`,
  `{{project.name}}-cli/{{project.name}}-cli.cabal`, `{{project.name}}-cli/app/Main.hs`,
  `{{project.name}}-cli/src/{{project.namespace}}/Cli.hs`,
  `{{project.name}}-core/src/{{project.namespace}}/Prelude.hs`, and `cabal.project`;
  managed — `LICENSE`, `fourmolu.yaml`. Apply the same reasoning to `haskell-library`
  (seeds: `cabal.project`, the `.cabal` file, `Prelude.hs`, the library root module,
  `test/Spec.hs`, `CHANGELOG.md`, `README.md`; managed: `LICENSE`, `fourmolu.yaml`) and to
  `haskell-keiro-project` (per-package `.cabal` files, sources, `README.md`, and any
  implementation brief are seeds; per-package `LICENSE` files stay managed).
  Rationale: `cabal.project` gains packages and `source-repository-package` stanzas as the
  project grows; the license and formatter configuration are policy the module maintains.
  Date: 2026-09-19

- Decision: Bump each changed module's minor version (for example `haskell-cli-app`
  0.2.0 → 0.3.0) and declare no module `migrations` for the change.
  Rationale: The lifecycle change is applied by `seihou update` itself (EP-5 releases the
  files); a module migration would duplicate it. A minor bump signals a behavior change
  without a breaking file change.
  Date: 2026-09-19


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

**Seihou and modules.** Seihou is a project scaffolding CLI. A *module* is a directory with a
`module.dhall` file and a `files/` directory of sources. Each entry in the module's `steps`
generates one file; `strategy` says how (`copy`, `template`, `dhall-text`, `structured`),
`src` names the source in `files/`, and `dest` the path in the user's project (it may contain
`{{variable}}` placeholders). A *registry* is a repository publishing many modules through a
`seihou-registry.dhall`; users install from it with
`seihou install https://github.com/shinzui/seihou-modules.git --all` into
`~/.config/seihou/installed/`, apply with `seihou run <module>` in a project, refresh installed
copies with `seihou upgrade <module>`, and re-apply newer releases to a project with
`seihou update <module>`. The project's record of what was applied is the committed
`.seihou/manifest.json`.

**Seeds (delivered by EP-1 to EP-5).** A step with `lifecycle = Some "seed"` is a seed:
`seihou run` writes it only when the path is absent and records a *seed receipt* in the
manifest's `seeds` map instead of a content record in `files`; `seihou status` prints
`Seed files: N (created once; owned by the project, not tracked)` instead of listing them;
`seihou remove` never deletes them; `seihou update` never writes an existing seed and
*releases* a formerly managed file (drops its record and baseline, keeps the bytes, records
outcome `released-from-managed`). `seihou validate-module` rejects a seed step that has a
`patch`, uses `structured`, shares a `dest` with a managed step, or is deleted by a removal
step. The field is new in the schema commit EP-1 pushed; `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`
in this repository holds that commit (`schemaUrl`) and its integrity hash (`schemaHash`).

**The registry repository.** `seihou-modules` has `modules/haskell/{haskell-cli-app,haskell-library,haskell-keiro-project,nix-haskell-flake}`,
`modules/typescript/{fumadocs,nix-bun-flake}`, `modules/git/git-init`, `recipes/`,
`blueprints/`, `okf-docs/` (generated documentation per module and recipe, produced by
`seihou okf-docs`; see `docs/cli/okf-docs.md` in this repository), and its own `docs/adr/` and
`docs/plans/`. Each `module.dhall` imports the schema by URL and hash, for example:

```dhall
let S =
      https://raw.githubusercontent.com/shinzui/seihou-schema/b83079d377f22c77292ad5ccf88d1061a58f0c1c/package.dhall
        sha256:1d46697ed3e7ca1b0d9922020e2da034ae6e33f7b482ee454c68d94b536e8c2a
```

and several different commits are pinned across modules today. A module must import a schema
commit whose `Step` has `lifecycle` before record completion (`S.Step::{ …, lifecycle = Some "seed" }`)
type-checks. Read the repository's own `README.md` and any `CLAUDE.md`/`AGENTS.md` in it before
editing; follow its commit conventions (Conventional Commits).

`haskell-cli-app` today (`modules/haskell/haskell-cli-app/module.dhall`, version `0.2.0`) has
ten steps: `cabal.project`, `{{project.name}}-core/{{project.name}}-core.cabal`,
`{{project.name}}-core/src/{{project.namespace}}/Prelude.hs`,
`{{project.name}}-cli/{{project.name}}-cli.cabal`, `{{project.name}}-cli/app/Main.hs`,
`{{project.name}}-cli/src/{{project.namespace}}/Cli.hs`, `LICENSE`, `fourmolu.yaml` (copy),
`CHANGELOG.md`, `README.md`. It depends on `nix-haskell-flake`. The recipe
`recipes/haskell-cli-app-repo/recipe.dhall` composes it.

**Relevant decisions.** In this repository: ADR 0017
(`docs/adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md`, created by EP-1
and amended by EP-2 to EP-5) defines seeds;
[ADR 0013](../adr/0013-status-is-a-bounded-summary-the-manifest-is-the-record.md) explains why
status shows only a count. In `seihou-modules`: ADR 2, "Separate Keiro project seeds from
domain implementation" (`mori://shinzui/seihou-modules`, project-relative path
`docs/adr/2-separate-keiro-project-seeds-from-domain-implementation.md`; an artifact-level Mori
URI for this ADR is pending because the registry does not yet index that bundle) already
describes `haskell-keiro-project`'s generated libraries as *seeds* that "become hand-owned
during implementation" and asks that "Seihou conflict protection must be respected on
reapplication". This plan makes that intent mechanical, and Milestone 4 amends that ADR to say
so.


## Plan of Work

### Milestone 1 — classify

In the `seihou-modules` checkout, list every step of every module
(`grep -n 'dest' modules/*/*/module.dhall`) and apply the test from the Decision Log. Record the
final list per module in this plan's Decision Log, replacing the "initial classification"
entry's details if the working tree differs (steps may have been added since 2026-09-19). For
modules other than the three Haskell ones, record the classification even if the answer is
"no seeds" (likely for `nix-haskell-flake`, `nix-bun-flake`, and `git-init`, whose files are
plumbing the module keeps maintaining; `fumadocs` may have content pages that are seeds —
decide and record). Only the three Haskell modules are changed in this plan unless the survey
finds an equally clear case; any other module goes into Future work in Outcomes.

Acceptance: the Decision Log lists, per module, each `dest` and its lifecycle.

### Milestone 2 — change the modules

For each module being changed:

1. Replace its schema import with the commit and hash from this repository's
   `seihou-cli/src/Seihou/CLI/SchemaVersion.hs` (the commit EP-1 pushed, or a later one).
   Check that no other field the module uses changed meaning between its old pin and the new
   one (read `git -C /Users/shinzui/Keikaku/bokuno/seihou-project/seihou/schema log --oneline <old>..<new>`).
2. Add `, lifecycle = Some "seed"` to each seed step.
3. Bump `version` (minor).
4. Update the module's `README.md` in the registry to say which files are seeds.
5. Run `seihou validate-module <module-dir> --lint` with a Seihou build that includes EP-1 to
   EP-5 and confirm `Seed steps` passes.

Then regenerate the registry's generated documentation with `seihou okf-docs` as the registry
does (see `docs/cli/okf-docs.md` in this repository for the invocation and `--check`), and
commit in `seihou-modules` with a Conventional Commit per module, for example:

```text
feat(haskell-cli-app): hand project-owned files to the project as seeds

Mark CHANGELOG.md, README.md, cabal.project, both .cabal files and the three
Haskell sources as seed steps so seihou status stops reporting them as
modified by user. LICENSE and fourmolu.yaml stay managed. Bump to 0.3.0.

MasterPlan: mori://shinzui/seihou/masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project
ExecPlan: mori://shinzui/seihou/plans/104-adopt-seed-steps-in-seihou-modules-and-document-seed-authoring
Intention: intention_01m2wz5ww3ezmvpf0aenfbgcjx
```

The trailers use `mori://` URIs because the plans live in another repository (see the global
cross-repository reference rule). Push only when the user asks.

Acceptance: every changed module validates; `seihou okf-docs --check` (or the registry's
equivalent) reports no drift.

### Milestone 3 — verify with the real CLI

Install the changed registry from the local checkout into a throwaway configuration directory
so the user's real installation is untouched (set `XDG_CONFIG_HOME` to a temporary directory
for these commands; check `seihou install --help` for installing from a local path).

Fresh project: in an empty temporary directory, `git init`, run
`seihou run haskell-cli-app` (answer the prompts, or pass variables as `seihou run --help`
describes), then confirm `jq '.seeds | keys' .seihou/manifest.json` lists the seeded paths and
`jq '.files | keys'` lists only `LICENSE`, `fourmolu.yaml`, and the `nix-haskell-flake` files.
Edit `CHANGELOG.md` and a `.cabal` file, run `seihou status`, and confirm neither appears and
the `Seed files:` line shows the expected count.

Existing project: in another temporary directory, install the **previous** registry commit
(`git -C <seihou-modules> worktree add <tmp> <old-commit>` and install from it), apply
`haskell-cli-app` 0.2.0, commit, edit `CHANGELOG.md` and the core `.cabal` file, and confirm
`seihou status` shows them as `modified by user`. Then install the new registry commit, run
`seihou update haskell-cli-app --dry-run` and confirm each seed path shows `release to project`;
run `seihou update haskell-cli-app`; confirm the edited files are byte-identical to before
(`git diff --exit-code -- CHANGELOG.md`), `seihou status` no longer lists them, and a second
`seihou update haskell-cli-app` reports the project is already up to date. Record the
transcripts in Surprises & Discoveries or Outcomes.

Acceptance: both scenarios behave as described. Any deviation is a bug in EP-3 to EP-5; record
it in the MasterPlan's Surprises & Discoveries and fix it there before continuing.

### Milestone 4 — documentation and records

In this repository: add a "Choosing a lifecycle: seed or managed" subsection under "Steps and
strategies" in `docs/user/module-authoring.md`, with the one-question test, a short table-free
list of typical seeds and typical managed files, what users see (`Seed files:` line, release
on update), the fact that an older Seihou binary treats a seed as managed, and a link to
ADR 0017. Add a user-facing entry under `## Unreleased` → `### Added` in
`docs/user/CHANGELOG.md` summarizing seed files end to end (field, run, status, update
release, remove). Run the `seihou-update-docs` skill's check if it applies to the range.

In `seihou-modules`: amend ADR 2 with a dated note that `haskell-keiro-project`'s seeds are now
declared with `lifecycle = Some "seed"`, which replaces "conflict protection must be respected
on reapplication" with Seihou leaving those files alone, citing
`mori://shinzui/seihou/adrs/0017-a-seed-file-is-created-once-and-belongs-to-the-project`
(the artifact-level URI shape for ADRs is pending in Mori; also give the project URI
`mori://shinzui/seihou` with path `docs/adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md`).

Then hand off to the MasterPlan's completion: its Outcomes & Retrospective and the ADR
distillation pass are done by whoever marks the MasterPlan complete, per the master-plan skill.


## Concrete Steps

```bash
# in the registry checkout
cd /Users/shinzui/Keikaku/bokuno/seihou-modules
git status --short                       # expect clean before starting
grep -n 'dest' modules/*/*/module.dhall
grep -n 'schemaUrl\|schemaHash' -A1 /Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-cli/src/Seihou/CLI/SchemaVersion.hs
# after editing a module
seihou validate-module modules/haskell/haskell-cli-app --lint
```

Expected validation excerpt:

```text
  ✓ Seed steps
```

Verification scenario (fresh project), with a temporary configuration root:

```bash
export XDG_CONFIG_HOME="$(mktemp -d)"
seihou install /Users/shinzui/Keikaku/bokuno/seihou-modules --all
cd "$(mktemp -d)" && git init -q
seihou run haskell-cli-app
jq '.version, (.seeds | keys), (.files | keys)' .seihou/manifest.json
echo '- note' >> CHANGELOG.md
seihou status
```

Expected: `version` is 8, `seeds` lists the seeded paths, `files` does not, and `seihou status`
does not mention `CHANGELOG.md`.


## Validation and Acceptance

The Milestone 3 scenarios are the acceptance: a new project and an upgraded project both end
with the project-owned files absent from `Tracked files:` and present in the `Seed files:`
count, with every developer edit intact. `seihou validate-module --lint` passes for every
changed module, the registry's generated docs have no drift, and this repository's
`nix flake check` still passes after the documentation edits.


## Idempotence and Recovery

All verification uses temporary directories and a temporary `XDG_CONFIG_HOME`, so the user's
installed modules and real projects are never touched. Registry commits are local until the
user asks to push. If a module change proves wrong after being pushed, fix forward with a new
module version; do not rewrite published registry history, because projects record the origin
and version they applied.


## Interfaces and Dependencies

Consumes: the `lifecycle` field (EP-1), seed behavior of `run` (EP-3), `status`/`remove`
(EP-4), and `update` release (EP-5), all in a Seihou build from this repository. Produces: new
versions of `haskell-cli-app`, `haskell-library`, and `haskell-keiro-project` in
`mori://shinzui/seihou-modules`; the authoring guidance in `docs/user/module-authoring.md`; the
user changelog entry. No code interfaces change in this repository.
