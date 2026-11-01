---
type: Improvement Request
title: Extend an existing recipe with a single base
description: >-
  Let a recipe reuse one existing recipe and add modules or override bindings,
  with dependency installation, deterministic expansion, validation, and
  provenance handled by Seihou instead of copied module lists or Dhall imports.
generated:
  by: process:codex
  at: "2026-11-01T17:48:21Z"
timestamp: 2026-11-01T20:59:11Z
requestId: IR-14
status: accepted
targetPlan: docs/plans/118-extend-recipes-through-a-single-origin-aware-base.md
origin: mori://shinzui/seihou-modules
reviews:
  - kind: model
    reviewer: process:codex
    provider: openai
    model: gpt-6
    effort: unspecified
    reviewed_at: "2026-11-01T17:49:45Z"
    document_timestamp: "2026-11-01T17:48:21Z"
    scope: content-and-metadata
    outcome: commented
    context: >-
      Author check against the current recipe types, expansion and module
      discovery source, ExecPlan 6, and ADRs 0002 and 0003. Not an independent
      approval. The exact model variant and effort setting were not exposed.
---

# Improvement Request: Extend an Existing Recipe with a Single Base

## Status

Source implementation is accepted through [ExecPlan 118](../plans/118-extend-recipes-through-a-single-origin-aware-base.md): single-base expansion, closure acquisition, schema-13 provenance and guards, ordinary updates/cache refresh, author guidance and generated registry docs are implemented. Source-built real-consumer proofs cover first use, base-only changes and empty-cache clones. The schema is published; the compatible CLI release, producer publication and released installed-binary acceptance remain open. The request remains accepted until that delivery workflow is verified.

## Context

A registry author wants to publish a specialized recipe that reuses an existing
one, for example an organizational service scaffold based on
`mori://shinzui/seihou-modules/templates/haskell-cli-app-repo`, with an additional
organization-specific module and preset bindings. The author should maintain
only the specialization, while fixes to the base's module composition remain
available through the normal upgrade workflow.

[ExecPlan 6](../plans/6-recipe-module-composition.md) deliberately limited recipes
to flat lists of modules and deferred recipe inheritance. At the time this request was raised, source implemented that boundary:

- `Seihou.Core.Types.Recipe` contains module dependencies, variable declarations,
  and prompts, with no parent-recipe reference.
- `Seihou.Composition.Recipe.expandRecipe` produces a primary module, additional
  modules, bindings, declarations, and prompts from that flat list.
- `Seihou.Composition.Resolve` loads those names through `discoverModule`, which
  requires `module.dhall`; listing a recipe as a module does not recursively
  expand it.

## Problem

The author must either copy the base's module list and settings or import and
modify its Dhall record. Copying makes the specialization drift from the base.
Dhall composition works, but the evaluated record hides the relationship from
Seihou's dependency management and provenance. A relative import also depends on
the imported file remaining reachable after installation; a pinned HTTPS import
leaves the author managing another distribution and versioning mechanism.

These are workable local techniques, but shared recipes need a discoverable,
supported way to express and resolve the relationship across registries.

## Requested change

Support one optional base recipe per recipe. An illustrative field is
`extends = Some "haskell-cli-app-repo"`; recipes without a base retain their
current behavior. The final reference representation must also identify a base
from another registry without silently choosing a same-named artifact from a
different origin.

### Expansion and precedence

1. Resolve the complete base chain and expand the oldest base first, appending
   each child's additional modules. Compile and execute the resulting composition
   once, through the existing pipeline, rather than running each recipe in turn.
2. Preserve the base's primary module so extension does not unexpectedly change
   namespace derivation. Permit a derived recipe with no additional modules when
   it only specializes settings; the fully expanded composition must be nonempty.
3. Inherit bindings, declarations, and prompts. For explicit recipe-supplied
   bindings, use ancestor before descendant before CLI precedence, with CLI
   values winning. Document how that integrates with existing config, defaults,
   and prompts; an inherited preset must not be replaced accidentally by an
   ordinary declaration default.
4. Allow a child to specialize a reused module's bindings without executing that
   module twice. Reuse the existing module identity and dependency machinery;
   deduplicate compatible repeated dependencies, and reject conflicting module
   instances or declarations rather than silently discarding them.
5. Reject incompatible variable declarations, ambiguous prompt overrides,
   missing bases, wrong artifact kinds, and direct or indirect cycles. Report the
   recipe chain and conflicting names so authors can fix the declaration.

### Installation, versions, and provenance

- Installing the derived recipe must resolve and install its base chain and
  required modules, including dependencies from another registry. Developers
  must not enumerate transitive dependencies or recreate the author's directory
  layout. Integrate with the dependency-installation work tracked by
  [BUG-2](../bug-reports/install-ignores-recipe-and-module-dependencies.md).
- Define base version selection and compatibility explicitly. Preview and
  manifest provenance must retain the derived recipe and every resolved base's
  identity, version, and origin, so a base-only change is visible and a later run
  can enforce existing stale-artifact and substitution rules.
- Keep `seihou run` local and offline under [ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md).
  Fetch dependencies during installation or the appropriate network-enabled
  upgrade workflow; missing dependencies must produce actionable diagnostics.
- Define how base changes participate in existing upgrade/update behavior and
  how older manifests decode. A newer base must not become an invisible change
  to an otherwise unchanged derived recipe.

## User workflow and acceptance criteria

Starting state: a published organizational registry contains `my-service`, which
extends the published base above and adds an organizational module. The consumer
has Seihou installed, an empty artifact cache, and no author checkouts.

The normal workflow is:

```sh
seihou install <organization-registry> --module my-service
seihou run my-service
```

The first command installs the full dependency closure. The second uses the
ordinary preview/confirmation flow and generates the combined scaffold. No
extra module selectors, Dhall imports, manual cache edits, or wrapper scripts are
required. Documentation and authoring help explain the base relationship and
its override rules.

Acceptance must demonstrate:

1. A base and child in different registries work through the commands above
   with an empty cache. The preview identifies the base chain, and the manifest
   records its resolved provenance.
2. Base files and child additions appear together, shared modules execute once,
   and base/child/CLI binding conflicts follow the documented precedence.
   Derived recipes that only override bindings also work.
3. A fresh clone with the committed manifest can install the required artifacts
   through the supported workflow and run without relying on the first
   developer's filesystem or cache.
4. A compatible base-only upgrade is visible and applied through the ordinary
   workflow. A stale or substituted base is refused before project writes.
5. Missing bases, cycles, conflicting declarations, and conflicting repeated
   modules fail with useful diagnostics before generation or commands run.
6. Existing flat recipes and supported older manifests continue to work without
   author edits. Verification distinguishes source-build results from the
   released CLI/schema/registry artifacts consumers can actually install.

## Scope and design questions

Start with a single base, including chains of single-base extensions. Multiple
parents, removal of inherited modules, arbitrary execution hooks, and module
inheritance are outside this request. Existing Dhall authoring remains valid.

Implementation planning must settle the typed cross-registry reference and
version constraint representation, the child binding-override syntax, prompt
identity and override rules, and the manifest representation of the base chain.
Include the schema change in `mori://shinzui/seihou-schema`, CLI documentation,
and a real published registry example in delivery scope.

## Related

- [ExecPlan 6](../plans/6-recipe-module-composition.md): original recipe design
  and explicit deferral of recipe extension.
- [Module authoring: recipes](../user/module-authoring.md#recipes): current flat
  recipe contract.
- [ADR 0002](../adr/0002-artifact-identity-is-origin-url-plus-name.md) and
  [ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md):
  artifact identity and generation guards that must cover inherited recipes.
- `mori://shinzui/seihou-modules/templates/haskell-cli-app-repo`: concrete base
  recipe motivating reuse. Mori's current registry did not resolve this artifact
  on 2026-11-01; its intended canonical URI is retained.
