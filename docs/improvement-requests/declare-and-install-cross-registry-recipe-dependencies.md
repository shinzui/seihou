---
type: Improvement Request
title: Declare and install cross-registry recipe dependencies
description: Let a recipe declare authoritative sources for modules in other registries and install the required dependency closure through the ordinary install command without requiring users to install whole registries or guess module origins.
requestId: IR-12
status: proposed
origin: mori://tan/tan-seihou-modules
affects: mori://shinzui/seihou
affectedVersion: 0.11.0.1
generated:
  by: codex-cli/gpt-6.1-sol
  at: "2026-10-28T12:26:39Z"
timestamp: 2026-10-28T12:26:39Z
reviews:
  - kind: model
    reviewer: codex-cli/gpt-6.1-sol
    reviewed_at: 2026-10-28T12:30:01Z
    document_timestamp: 2026-10-28T12:26:39Z
    scope: content-and-metadata
    outcome: approved
    context: Author self-review against current source, installed CLI evidence, and the local profile; not an independent review.
    provider: openai
    model: gpt-6.1-sol
    effort: unspecified
---

# Declare and install cross-registry recipe dependencies

## Context and evidence

The TAN recipe must compose new modules from `mori://tan/tan-seihou-modules`
with `mori://shinzui/seihou-modules/templates/haskell-keiro-project`,
`mori://shinzui/seihou-modules/templates/git-init`, and
`mori://shinzui/agent-seihou/templates/master-plan`, including transitive modules
such as `mori://shinzui/seihou-modules/templates/nix-haskell-flake`.
A new developer should install the selected recipe and run it without learning
that closure or installing unrelated artifacts from all three registries.

The dependency declaration in `mori://shinzui/seihou-schema` has only `module`
and `vars`; `Dependency.dhall` is the project-relative source (artifact URI
pending). The loader discovers bare module names from local search paths.
Nothing in the recipe records which external registry supplies a dependency.
Even a future same-registry closure walk cannot infer those authoritative origins.

The existing [BUG-2](../bug-reports/install-ignores-recipe-and-module-dependencies.md)
already covers the more basic failure to install a recipe's dependencies from
its own registry. It was reproduced again on 2026-10-28 with installed
`seihou v0.11.0.1 (4ade3fb)` and an empty isolated `XDG_CONFIG_HOME`:

```text
$ seihou install https://github.com/shinzui/seihou-modules.git --module haskell-cli-app-repo
1 entry installed.
$ seihou run haskell-cli-app-repo --dry-run --no-save-prompted
[error] Module 'haskell-cli-app' not found.
```

Only `haskell-cli-app-repo` was present in the isolated installed directory.
This request extends the delivery requirement to explicit cross-registry sources;
it does not duplicate BUG-2's same-registry report.

## Requested behavior and acceptance

Provide a producer-owned way to declare dependency origins, compatible with the
existing source-identity rules, and have ordinary installation acquire the exact
required closure. The representation is an upstream design decision: a source map,
qualified references, or another declarative contract is acceptable. It must work
for both recipe members and transitive module dependencies and survive installed
artifacts without a source checkout.

From an empty install cache, one normal install of the TAN recipe must acquire its
local and two external registries' required artifacts. Its first run must resolve
all modules without a transitive `--module` list, three registry-wide `--all`
installs, source-path edits, or prior machine state. Report source conflicts and
unavailable dependencies before claiming that the artifact is ready to run.
Preserve refusal to replace a same-name artifact from a different origin; never
silently choose an arbitrary registered project or weaken origin checks.

Show install and run evidence against the executable intended for delivery,
including an external transitive dependency, repeated installation, unavailable
source, and a same-name/different-origin collision. Module generation must remain
separate from dependency acquisition: a dry-run must not unexpectedly mutate the
machine-wide install cache.

## Related work and handoff

[IR-4](refuse-to-overwrite-an-installation-from-a-different-source.md) and
[ADR 0006](../adr/0006-the-install-cache-will-not-silently-substitute-an-artifact.md)
constrain origin collision handling. BUG-2 remains the existing dependency-closure
report. The user will fix these upstream capabilities before implementation of
`mori://tan/tan-seihou-modules/masterplans/1-bootstrap-tan-keiro-projects-with-a-cross-registry-recipe`;
the TAN registry should consume that contract rather than ship an installer wrapper.
