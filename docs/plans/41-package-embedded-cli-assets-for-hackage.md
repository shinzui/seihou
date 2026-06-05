---
id: 41
slug: package-embedded-cli-assets-for-hackage
title: "Package embedded CLI assets for Hackage"
kind: exec-plan
created_at: 2026-06-05T14:33:58Z
intention: "intention_01ktc3hwwneswaz13bvr1tb6f9"
master_plan: "docs/masterplans/5-first-public-release-readiness.md"
---

# Package embedded CLI assets for Hackage

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, the `seihou-cli` source distribution contains every Markdown file that the executable embeds at compile time. A downstream Hackage builder can unpack `seihou-cli-<version>.tar.gz`, compile `exe:seihou`, and not fail with `help/agent.md: openFile: does not exist`.

This matters because local builds compile from the repository checkout, where `seihou-cli/help/` and `seihou-cli/data/` exist. Hackage builds compile from the Cabal source distribution, which only includes files known to Cabal.


## Progress

- [x] Add `extra-source-files` entries for embedded CLI help files. Completed 2026-06-05 by adding the ten `help/*.md` files referenced by `Seihou.CLI.Help` to `seihou-cli/seihou-cli.cabal`.
- [x] Add `extra-source-files` entries for embedded agent prompt templates. Completed 2026-06-05 by adding the four `data/*.md` prompt files referenced by executable modules to `seihou-cli/seihou-cli.cabal`.
- [x] Regenerate source distributions and confirm the files are present in `seihou-cli` tarball. Completed 2026-06-05 with `cabal sdist all` and `tar -tzf dist-newstyle/sdist/seihou-cli-0.2.0.0.tar.gz | rg "^(seihou-cli-0.2.0.0/(data|help)/)"`.
- [x] Build `exe:seihou` from unpacked `seihou-core` and `seihou-cli` source distributions. Completed 2026-06-05; the temporary project compiled and linked `exe:seihou` from the unpacked tarballs.


## Surprises & Discoveries

The audit confirmed that `cabal sdist all` can succeed while the resulting `seihou-cli` tarball is incomplete. The failure appears only when compiling from the unpacked tarball.

The unpacked source distribution build emitted existing `-Wx-partial` warnings in `seihou-core/src/Seihou/Composition/Recipe.hs` for `head` and `tail`. That warning belongs to `docs/plans/45-make-recipe-expansion-total.md`; it did not block this packaging fix.


## Decision Log

- Decision: Fix this in `extra-source-files`, not by changing the embed paths.
  Rationale: The executable intentionally embeds help and prompt text at compile time. Cabal already supports declaring non-Haskell source files for source distributions.
  Date: 2026-06-05


## Outcomes & Retrospective

To be filled during and after implementation.

Implemented on 2026-06-05. `seihou-cli/seihou-cli.cabal` now declares the embedded Markdown assets in `extra-source-files`, `cabal sdist all` includes those files in the CLI tarball, `cabal build all` passes from the repository checkout, and `cabal build exe:seihou` passes from freshly unpacked `seihou-core` and `seihou-cli` source distributions.


## Context and Orientation

The package file is `seihou-cli/seihou-cli.cabal`. The executable target imports `Data.FileEmbed` in several modules and embeds repository-relative files at compile time.

The embedded help files are referenced from `seihou-cli/src-exe/Seihou/CLI/Help.hs` with calls such as:

```haskell
agentContent = $(embedStringFile "help/agent.md")
```

The embedded prompt templates are referenced from:

- `seihou-cli/src-exe/Seihou/CLI/Assist.hs`
- `seihou-cli/src-exe/Seihou/CLI/Bootstrap.hs`
- `seihou-cli/src-exe/Seihou/CLI/Setup.hs`
- `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`

The files that must be packaged currently live under `seihou-cli/help/` and `seihou-cli/data/`.


## Plan of Work

Milestone 1 adds Cabal source distribution metadata. Edit `seihou-cli/seihou-cli.cabal` near the package header, before component stanzas, and add an `extra-source-files` section that includes every embedded Markdown asset. At minimum it must include:

```text
data/assist-prompt.md
data/bootstrap-prompt.md
data/setup-prompt.md
data/blueprint-prompt.md
help/agent.md
help/blueprints.md
help/config.md
help/contexts.md
help/git-repository.md
help/kit.md
help/migrations.md
help/modules.md
help/templating.md
help/variables.md
```

If new embedded files appear during implementation, include them too. Use `rg -n "embed(File|StringFile)" seihou-cli/src seihou-cli/src-exe` to verify the full list.

Milestone 2 proves the tarball includes those files. Run `cabal sdist seihou-cli` or `cabal sdist all`, then inspect `dist-newstyle/sdist/seihou-cli-0.2.0.0.tar.gz` with `tar -tzf`.

Milestone 3 builds from source distributions. Unpack `seihou-core` and `seihou-cli` tarballs into a temporary directory, create a temporary `cabal.project` that lists both unpacked package directories, and run `cabal build exe:seihou` there. This reproduces a downstream Hackage-style build while still making the local `seihou-core` tarball available before it is published.


## Concrete Steps

From the repository root:

```bash
rg -n "embed(File|StringFile)" seihou-cli/src seihou-cli/src-exe
cabal sdist all
tar -tzf dist-newstyle/sdist/seihou-cli-0.2.0.0.tar.gz | rg "^(seihou-cli-0.2.0.0/(data|help)/)"
```

Expected evidence after the fix is that every embedded file appears under `seihou-cli-0.2.0.0/data/` or `seihou-cli-0.2.0.0/help/`.

Then run the unpacked build:

```bash
tmp=$(mktemp -d)
tar -xzf dist-newstyle/sdist/seihou-core-0.2.0.0.tar.gz -C "$tmp"
tar -xzf dist-newstyle/sdist/seihou-cli-0.2.0.0.tar.gz -C "$tmp"
printf 'packages: seihou-core-0.2.0.0 seihou-cli-0.2.0.0\nwrite-ghc-environment-files: never\n' > "$tmp/cabal.project"
cd "$tmp"
cabal build exe:seihou
```

The important expected result is that the build does not fail with a missing `help/*.md` or `data/*.md` file during Template Haskell splicing.


## Validation and Acceptance

Acceptance requires all of the following:

- `tar -tzf dist-newstyle/sdist/seihou-cli-0.2.0.0.tar.gz` lists the embedded help and prompt files.
- Building `exe:seihou` from unpacked `seihou-core` and `seihou-cli` source distributions reaches normal compilation/linking without missing embedded files.
- `cabal build all` still works from the repository checkout.

If the unpacked build fails for an unrelated dependency reason, record the exact output in Surprises & Discoveries and still verify that the missing embedded-file failure is gone.


## Idempotence and Recovery

Adding `extra-source-files` is idempotent. If a file is listed twice, remove the duplicate. Re-running `cabal sdist all` overwrites the generated tarballs under `dist-newstyle/sdist/` and does not change tracked source files.


## Interfaces and Dependencies

This plan depends on Cabal's `extra-source-files` package field. No Haskell API changes are required. It touches `seihou-cli/seihou-cli.cabal` and validates files referenced by `Data.FileEmbed` in the executable modules.
