---
type: Bug Report
title: "A recipe cannot enforce a variable that global config sets, so a TAN repository is created under a personal GitHub account"
description: >-
  A recipe has no way to hold a module variable to a fixed value once the user sets it in global
  config. Dependency var bindings reject camelCase names such as `git.githubOwner`, and a recipe
  VarDecl's pattern validation silently accepts unrecognized patterns from every source, including config. `seihou run
  tan-keiro-project` with `git.createGithub=true` therefore creates the repository under whatever
  owner the user configured globally, not the organization the recipe declares.
bugId: BUG-3
affects: mori://shinzui/seihou
affectedVersion: 0.12.1.0
origin: mori://tan/tan-platform
severity: degraded
status: reported
generated:
  by: "claude-code/claude-opus-5-5"
  at: "2026-10-28T20:45:00Z"
observed: >-
  With `seihou config set git.githubOwner shinzui --global` (the one-time setup git-init's own help
  recommends), `seihou run tan-keiro-project --var git.createGithub=true ...` resolves
  `git.githubOwner = "shinzui"` and plans `gh repo create shinzui/<repo>`. That happens although the
  recipe declares `git.githubOwner` with `default = Some "topagentnetwork"`, and also when the
  recipe adds `validation = Some "^topagentnetwork$"`. Pinning the value as a dependency var on
  `git-init` instead is rejected at install:
  `modules.vars: invalid var binding name 'git.githubOwner' in module 'git-init'`.
expected: >-
  A recipe should be able to fix a module variable for every run. One way is a dependency var
  binding, which must accept the variable names modules actually declare, camelCase included.
  Failing that, the recipe's declared `validation` should apply to the resolved value whatever its
  source, so an out-of-policy global value fails before any effect instead of being used.
workaround: >-
  Pass `--var git.githubOwner=topagentnetwork` explicitly; a command-line var takes precedence over
  global config. mori://tan/tan-platform's `transition kickoff` now prints it in every recipe
  command it previews.
reproduction:
  - Set a personal owner globally with `seihou config set git.githubOwner someone-else --global`.
  - In an empty directory, run `seihou run tan-keiro-project --dry-run --no-save-prompted --var project.name=probe --var project.namespace=Probe --var project.description=probe --var git.createGithub=true --var git.repoName=probe --var nix.redpanda=false`.
  - Observe `git.githubOwner = "someone-else"` and `gh repo create someone-else/probe` in the plan, although the recipe defaults the owner to `topagentnetwork`.
  - Add `validation = Some "^topagentnetwork\$"` to the recipe's `git.githubOwner` VarDecl, reinstall, and rerun; observe the same plan with no validation error.
  - Instead add `vars = [ { name = "git.githubOwner", value = "topagentnetwork" } ]` to the recipe's `git-init` dependency and reinstall; observe `invalid var binding name 'git.githubOwner'`.
---

# Bug Report: A recipe cannot enforce a variable that global config sets

## What is wrong

A recipe declares the organization its projects belong to, but a user's global config silently
overrides it. Both mechanisms a recipe has for holding the value fail:

1. **Dependency var bindings reject camelCase names.** `checkVarBindingNames` in
   `seihou-core/src/Seihou/Core/Recipe.hs` (and the same rule for `baseModule` in
   `seihou-core/src/Seihou/Core/Blueprint.hs`) requires `[a-z][a-z0-9.-]*`. Modules declare
   camelCase variables, for example git-init's `git.githubOwner`, `git.createGithub` and
   `git.githubVisibility`. Those are valid module variables that a recipe still cannot bind.
2. **The pattern matcher accepts unrecognized patterns.** Configuration already passes through
   the shared validator. Its matcher recognizes only `[a-z][a-z0-9-]*` and returns success for
   every other pattern, including `^topagentnetwork$`. This affects every selected source. The
   original report attributed the failure specifically to configuration; source inspection and
   CLI reproductions corrected that diagnosis.

A recipe default is the lowest precedence, so with neither mechanism available the recipe has no
way to stop a global value.

## Where it was observed

`mori://tan/tan-seihou-modules`'s `tan-keiro-project` recipe creates TAN service repositories.
Its `git.createGithub` description and prompt say the repository is created "under
topagentnetwork", and it defaults `git.githubOwner` to `topagentnetwork`. The repository owner had
set `git.githubOwner = shinzui` globally, as git-init's own help text recommends ("set globally
with `seihou config set git.githubOwner <value> --global`").

On 2026-10-28, while bootstrapping `market-data-service` and `agent-qualification-service`, the
resolved inputs showed `git.githubOwner = "shinzui"`. The run used `git.createGithub=false`, so
nothing was created in the wrong place. With it set to true, both TAN repositories would have
been created under the personal account. The repositories were then created under
`topagentnetwork` by hand.

## Why this is a bug, not an improvement request

The binding rule contradicts the names modules are allowed to declare: a recipe cannot bind a
variable that its own dependency defines. A declared pattern that silently accepts unsupported syntax is a validation gap. In both cases the declared policy is silently not enforced, and the
effect is an outward-facing GitHub repository created in the wrong account.

## Suggested direction

- Accept camelCase in binding names: allow `[a-z][A-Za-z0-9.-]*`, the shape module var names
  already use. A recipe could then pin `git.githubOwner` on its git-init dependency.
- Apply a recipe's declared `validation` to the final resolved value whatever its source
  (default, config, context, prompt or `--var`), and report which source supplied a rejected
  value.
- Consider printing the source of each resolved input in the plan, for example
  `git.githubOwner = "shinzui" (global config)`, so an override is visible before `--commit`.

## Related

- `mori://tan/tan-platform` commit `818b03a` makes `transition kickoff` pass the owner explicitly
  as a workaround.


## Implementation verification

Plan [117](../plans/117-let-recipes-enforce-configured-variable-values.md) replaces
that matcher with whole-value POSIX extended validation and preserves original
sources through recipe consumer validation. The candidate TAN recipe binds the
owner above personal preferences and constrains explicit overrides. Tests verify
that invalid run/update/reconfigure inputs preserve generated files, command logs
and manifests. The bug remains reported until released/installed Seihou and the
published recipe pass the same workflow; an unreleased source fix is not delivery.
