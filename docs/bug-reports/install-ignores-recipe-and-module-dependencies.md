---
type: Bug Report
title: "`seihou install` installs a recipe or module without its declared dependencies, so the installed artifact cannot run"
description: >-
  Installing a recipe (or module) from a registry with `seihou install --module <name>` installs only
  the named entry and never its transitive `modules`/`dependencies`, so the first `seihou run <name>`
  fails with "Module '<dep>' not found" even though the dependency is present in the same registry.
bugId: BUG-2
affects: mori://shinzui/seihou
affectedVersion: 0.9.0.0
origin: mori://shinzui/seihou-modules
severity: degraded
status: reported
generated:
  by: process:claude-code
  at: "2026-10-05T19:45:54Z"
observed: >-
  `seihou install https://github.com/shinzui/seihou-modules.git --module github-repo` reports the
  recipe installed, but `seihou run github-repo` then aborts with `Module 'repo-dir' not found`, because
  the `github-repo` recipe's declared `modules = [{ module = "repo-dir", ... }]` dependency was never
  installed alongside it.
expected: >-
  Installing a recipe or module should also install the transitive `modules`/`dependencies` it declares
  (the same closure `seihou run` resolves at run time), so the installed artifact is runnable, or the
  install should fail loudly naming the unsatisfied dependencies rather than silently reporting success.
workaround: >-
  Install each missing dependency explicitly — `seihou install <git-url> --module repo-dir` — or install
  the whole registry with `--all`. After the dependency is present, `seihou run github-repo` resolves
  and runs normally.
reproduction:
  - Start from a machine where the `repo-dir` module is not installed (`ls ~/.config/seihou/installed | grep repo-dir` prints nothing).
  - Run `seihou install https://github.com/shinzui/seihou-modules.git --module github-repo` and observe it report `Installed recipe as: github-repo` with no mention of `repo-dir`.
  - Run `seihou run github-repo --dry-run --var repo.parentDir=/tmp/x --var repo.name=demo --var git.githubOwner=shinzui --var git.githubVisibility=private`.
  - Observe it fail with `ERROR Module 'repo-dir' not found.` and the three searched paths, even though `repo-dir` exists in the same registry the recipe was installed from.
timestamp: "2026-10-29T13:01:54Z"
reviews:
  - kind: model
    reviewer: codex-cli/gpt-6.1-sol
    reviewed_at: "2026-10-29T13:01:54Z"
    document_timestamp: "2026-10-29T13:01:54Z"
    scope: catalog-metadata
    outcome: commented
    context: Structural metadata review while closing BUG-3; historical behavior and disposition are unchanged and were not reverified. No historical review is inferred.
    provider: openai
    model: gpt-6.1-sol
    effort: unspecified
---

# Bug Report: `seihou install` ignores a recipe's (or module's) declared dependencies

## What is wrong

`seihou install --module <name>` resolves and installs **only** the registry entries named on the
command line. It never reads the installed artifact's declared dependency closure — a recipe's
`modules` list, or a module's `dependencies` list — and so never installs those dependencies.

The result is an artifact that reports a successful install but cannot run: the dependency it needs is
resolved by `seihou run`, not by `seihou install`, so the gap only surfaces on first use, as a
`Module '<dep>' not found` error.

## Where it was observed

Reproduced directly while installing the `github-repo` recipe from
`mori://shinzui/seihou-modules`. The recipe (`recipes/github-repo/recipe.dhall`) declares:

```dhall
, modules =
  [ { module = "repo-dir", vars = [] : List { name : Text, value : Text } }
  ]
```

`github-repo` had been installed on its own, so `~/.config/seihou/installed/` contained `github-repo`
but not `repo-dir`.

## What happens

```
$ seihou run github-repo --var repo.parentDir="~/Keikaku/hub/haskell" \
    --var repo.name="cabal-project" --var git.githubOwner="shinzui" \
    --var git.githubVisibility="private"
ERROR Module 'repo-dir' not found.
ERROR Searched in:
ERROR   /Users/shinzui/Keikaku/hub/haskell/.seihou/modules
ERROR   /Users/shinzui/.config/seihou/modules
ERROR   /Users/shinzui/.config/seihou/installed
```

## Why this happens

In `seihou-cli/src-exe/Seihou/CLI/Install.hs`:

- `selectModules` (lines 353–374) handles `--module` by mapping each requested name to a registry
  entry via `findEntry` over `allEntries registry`. The selection is exactly the names the user typed;
  there is no step that reads a selected entry's `modules`/`dependencies` and adds them to the set.
- `installRegistryEntry` (lines 454–494) installs one entry's directory. For a recipe
  (`hasRecipe`, lines 490–494) it copies `recipe.dhall` via `installModuleDir` and reports success
  without inspecting the recipe's `modules`. For a module (lines 465–488) it decodes and validates
  `module.dhall` but likewise never acts on its `dependencies`.

So nothing in the install path computes or installs the dependency closure that `seihou run` later
requires. `--all` happens to work only because it installs every entry, dependencies included, by
brute force.

## Why this is a bug, not an improvement request

`seihou install --module <name>` is behavior seihou already provides and documents: it installs an
artifact from a registry so it can be run. Installing a recipe whose sole purpose is to compose a
dependency module, in a way that guarantees the recipe cannot run, is that provided capability failing
in its ordinary case — not a request for new behavior. The parallel is `seihou run`, which *does*
resolve the same closure; install and run disagree about what "installed" means.

## Suggested direction

Resolve the transitive closure at install time: after `selectModules`, expand the selection with each
entry's declared `modules`/`dependencies` found in the same registry (de-duplicated, order-stable), and
install them too. Where a declared dependency is not present in the registry, fail the install naming
the unsatisfied dependency rather than reporting success. A focused regression would install a recipe
with one dependency via `--module` and assert the dependency lands in
`~/.config/seihou/installed/` and that `seihou run <recipe> --dry-run` resolves.

## Related

- `recipes/github-repo/recipe.dhall` and `modules/git/repo-dir/module.dhall` in
  `mori://shinzui/seihou-modules` — the recipe/dependency pair the defect was reproduced with.
