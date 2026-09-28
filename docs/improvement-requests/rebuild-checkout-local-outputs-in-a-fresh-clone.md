---
type: Improvement Request
title: Rebuild checkout-local outputs, such as skill symlinks, in a fresh clone
description: >-
  Let a module declare outputs that exist only in a working copy, such as gitignored symlinks,
  and give a fresh clone one command that rebuilds them from the manifest without upgrading any
  artifact. Today the committed command receipts tell every clone that the work is done, so a
  cloner cannot get `link-skill`'s symlinks back without an unrelated upgrade.
generated:
  by: process:claude-code
  at: "2026-09-28T17:49:14Z"
requestId: IR-9
status: proposed
origin: mori://shinzui/keiro
acceptanceCriteria:
  - id: AC-1
    statement: A module can declare an output whose lifetime is one working copy, and a declaration that links a directory from the project into a gitignored path can be written without a shell command.
    verification: A `validate-module` test accepts the declaration, and a `seihou run` test on a module declaring it creates the link and records it in the manifest by project-relative source and destination only.
  - id: AC-2
    statement: In a fresh clone of a project whose manifest records checkout-local outputs, one documented seihou command recreates every missing one, without resolving a newer artifact, applying a migration, writing a tracked file, or changing `.seihou/manifest.json`.
    verification: An end-to-end test clones a fixture project with recorded links (and with newer artifact versions installed), runs the command, and asserts that every link exists and that `git status --porcelain` is empty.
  - id: AC-3
    statement: The rebuild command needs no installed copy of the declaring module, is idempotent, and reports each output it created, replaced, or found already correct.
    verification: The AC-2 test runs with an empty install cache, then runs the command a second time and asserts that it reports no changes.
  - id: AC-4
    statement: '`seihou status` reports a checkout-local output that is missing or points somewhere other than recorded, and names the rebuild command.'
    verification: A status render test over a manifest with one missing link and one link pointing at the wrong source.
  - id: AC-5
    statement: A shell command that the manifest records is never run by the rebuild command unless the user passes an explicit flag, so running the rebuild command automatically (from direnv or a git hook) can only create links the manifest records.
    verification: A test with a recorded command and a recorded link, run without the flag, asserts that the link is created and the command is not run.
reviews:
  - kind: model
    reviewer: claude-code
    reviewed_at: "2026-09-28T17:49:14Z"
    document_timestamp: "2026-09-28T17:49:14Z"
    scope: technical-accuracy
    outcome: approved
    provider: anthropic
    model: claude-opus-5-5
    effort: unspecified
    context: >-
      This is the authoring model checking its own work, not an independent review. It read
      seihou-cli/src/Seihou/CLI/CommandExecution.hs (CommandPolicy, planCommands),
      seihou-core/src/Seihou/Core/Types.hs (CommandReceipt, Strategy), schema/Command.dhall,
      schema/Step.dhall, ADRs 0001, 0004, 0009 and 0011, and MasterPlan 12 at fbb1b7c. It ran
      seihou v0.6.0.0 (`update --run-all-commands --dry-run`, targeted and untargeted, with and
      without `--force`, and `run link-skill --dry-run`) in a fresh working copy of mori://shinzui/keiro at
      6b9f5b38, and read link-skill 0.2.0 at mori://shinzui/agent-seihou 4e0a1d7.
---

# Rebuild checkout-local outputs, such as skill symlinks, in a fresh clone

## Status

Proposed. No plan implements this request.

## Context

`link-skill` (mori://shinzui/agent-seihou, 0.2.0) makes a skill in `agents/skills/<name>`
visible to agent tools. It appends to `.gitignore`, then runs four commands:

```dhall
commands =
  [ S.Command::{ run = "mkdir -p .claude/skills" }
  , S.Command::{ run = "ln -sfn ../../agents/skills/{{skill.name}} .claude/skills/{{skill.name}}" }
  , S.Command::{ run = "mkdir -p .agents/skills" }
  , S.Command::{ run = "ln -sfn ../../agents/skills/{{skill.name}} .agents/skills/{{skill.name}}" }
  ]
```

`agent-gitignore`, a dependency, adds `.claude/` and `.agents/` to `.gitignore`. The skill
source is committed, but the links are not, and they cannot be: they are one working copy's
wiring. `exec-plan` and `master-plan` depend on `link-skill`, so any project that uses them is
in the same position.

After a successful run, seihou writes a `CommandReceipt` for each command into
`.seihou/manifest.json`, which is committed (ADR 0001). `planCommands` in
`seihou-cli/src/Seihou/CLI/CommandExecution.hs` skips any command whose fingerprint already has
a receipt under the default `RunChangedCommands` policy.

## Problem

In a fresh clone, the manifest says every link command has already run, and none of the links
exists. seihou cannot tell these apart, because a receipt records that a command ran once on
some machine, not that its result is present in this working copy. For a command that changes
committed files that is correct. For a command whose result is gitignored, it is wrong in every
clone except the first.

### Evidence from mori://shinzui/keiro

A fresh working copy at `6b9f5b38`, with seihou v0.6.0.0:

- The manifest holds 8 `link-skill` receipts: two `mkdir -p` commands and two `ln -sfn` commands
  for each of `exec-plan` and `master-plan`. `.claude/skills` and `.agents/skills` do not exist.
- `seihou update master-plan --run-all-commands --dry-run` is refused with
  `shared_path_requires_applications`, because `.gitignore` is also owned by the
  `nix-haskell-flake` application. This is the closure IR-8 addresses.
- `seihou update --run-all-commands --dry-run` stops at unresolved conflicts on `.envrc` (missing
  here because it is gitignored) and `flake.lock`.
- With `--force` added, the plan does far more than rebuild the links:

  ```text
  exec-plan          0.10.0 -> 0.12.0
  master-plan        0.10.0 -> 0.12.0
  nix-haskell-flake  0.24.0 -> 0.26.0
  Migrations:  3
  Files:       0 created; 11 updated; ...
  Commands:    8 will run; 0 unchanged skipped; 0 disabled
  Conflict:    .envrc (CurrentFileMissing; useGenerated)
  Conflict:    flake.lock (OverlappingEdits; useGenerated)
  ```

  Getting the links back this way means taking three upgrades, three migrations, and a generated
  `flake.lock` over the project's own.

- `seihou run link-skill --var skill.name=exec-plan` does plan the four commands, but it
  re-applies the module. That writes `.seihou/manifest.json` (and patches `.gitignore`), so
  setting up a clone leaves a diff in a committed file. It also requires the cloner to know
  every skill name and to have `link-skill` installed.

In practice, cloners either copy the `ln` commands out of the manifest by hand or don't notice
that the skills are missing. Nothing in `seihou status` shows the gap.

## Why the existing escapes do not cover it

- **`update --run-all-commands`** is the only built-in way to re-run a recorded command, but it
  is tied to `update`, whose job is to move to newer artifact versions. Rebuilding local state and
  upgrading are separate intentions, and a cloner who wants only the first cannot opt out of the
  second. The flag name also does not suggest that it is how to set up a clone.
- **`seihou run <module>`** re-applies the module and rewrites the manifest. That is right for
  reconfiguration but wrong for setting up a clone, which should leave committed files untouched.
- **A local receipt file** (a gitignored `.seihou/local-state.json`) would solve the skipping,
  but ADR 0004 rules out a second record of applied state, and a receipt would still only say
  "ran here once", not "is present now".

## Requested change

### Part 1: a checkout-local output lifetime

MasterPlan 12 is adding an optional `lifecycle` field to `Step`, with values `managed` (today's
behavior) and `seed` (created once, then owned by the project). A checkout-local output is the
opposite of a seed: recreated in every working copy and never committed. The preferred shape is
a third lifetime on that same field, together with a declarative link step, so that seihou can
observe the output on disk instead of trusting a receipt:

```dhall
S.Step::{
, strategy = "symlink"
, src = "agents/skills/{{skill.name}}"
, dest = ".claude/skills/{{skill.name}}"
, lifecycle = Some "checkout"
}
```

The names are illustrative. The properties that matter are:

- The manifest records the link by project-relative `src` and `dest` only, as ADR 0001
  requires. It records no receipt, because whether a link exists in a working copy is not a fact
  about the project.
- seihou creates missing parent directories itself, so the `mkdir -p` commands go away.
- `validate-module` requires both paths to stay inside the project, and `seihou run` warns when
  `dest` is not gitignored.
- `seihou remove` deletes the links it recorded, which it cannot do reliably for arbitrary shell.

If a declarative link is too narrow, a fallback is a `lifecycle`-style marker on `Command` that
says "re-run in every working copy". The declaring module must guarantee the command is
idempotent, since seihou cannot check whether it is satisfied. It covers more cases but gives
up the checks from AC-4.

### Part 2: a command that rebuilds checkout-local outputs

A command, for example `seihou sync` or `seihou setup`, that:

- reads `.seihou/manifest.json` and recreates every missing or wrong checkout-local output,
- never resolves an artifact, applies a migration, writes a tracked file, or writes the manifest,
- needs nothing beyond the manifest, so it works before any module is installed,
- is idempotent and reports what it created, replaced, or found already correct,
- supports `--dry-run` and `--json` like `update`.

`seihou status` should report missing or wrong checkout-local outputs and name this command.

### Automatic invocation

Once the command exists, projects will want to run it automatically, from direnv (the
`nix-haskell-flake` module already generates `.envrc`) or a `post-checkout` hook. That is safe
only because Part 1's link steps are declarative and checked. The manifest is repository content,
so running recorded shell from it on every `cd` would let a pull request run arbitrary code.
If the command fallback from Part 1 is adopted, running those commands should require an
explicit flag (AC-5).

## Alternative without a seihou change

This alternative belongs in mori://shinzui/agent-seihou and is recorded here until a
corresponding request is filed there.

A small module adds a `setup-skills` recipe to the project's Justfile with `append-section`.
It is a dependency of a new `link-skill` 0.3.0, so every project that links a skill through
seihou gets it:

```just
# Link every skill in agents/skills/ into .claude/skills and .agents/skills
setup-skills:
    #!/usr/bin/env bash
    set -euo pipefail
    for dir in .claude/skills .agents/skills; do
      mkdir -p "$dir"
      find "$dir" -maxdepth 1 -type l ! -exec test -e {} \; -delete
      for skill in agents/skills/*/; do
        name=$(basename "$skill")
        ln -sfn "../../agents/skills/$name" "$dir/$name"
      done
    done
```

This works with seihou as it is today: the module writes a committed file once, which is exactly
what a receipt describes correctly, and the recipe does the per-clone work. The design choices:

- **Loop over `agents/skills/*/` instead of replaying the manifest.** keiro's `agents/skills/`
  holds four skills (`exec-plan`, `master-plan`, `keiro-dsl-authoring`, `release`), but only the
  first two have `link-skill` receipts, so replaying recorded commands would miss the other two.
- **Take the Justfile name as a variable.** keiro uses `Justfile`; other consumers use `justfile`.
- **Use a shebang recipe**, so the recipe does not depend on the shell a project sets for `just`
  (keiro sets `zsh`).
- **Use `append-section`, not `append-line-if-absent`.** Recipes share lines like
  `set -euo pipefail`, which `append-line-if-absent` would skip. `tan-service-skills` already adds a
  `setup-claude` recipe with `append-line-if-absent`, so it has this problem.

It does not close the gap this request is about. The manifest still says the links exist in a
clone where they do not, `seihou status` cannot detect missing links, someone still has to run
the recipe, and each module that produces checkout-local state has to ship its own recipe.

## Scope

This request covers outputs whose lifetime is one working copy. It does not change managed or
seed files, command receipts for commands that change committed files, or `update`'s existing
`--run-all-commands` semantics.

## Related

- IR-8: the shared-ownership closure that refuses `seihou update master-plan` in keiro because
  `.gitignore` is co-owned. It fixes one of the refusals above but not the underlying problem.
- MasterPlan 12 (`docs/masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md`):
  adds the `lifecycle` field this request proposes to extend.
- ADR 0004: rules out a local receipt file, which is why Part 1 prefers outputs seihou can
  observe on disk.
