# ADR 0022 — Recipe descriptor validation is independent of composition

- Status: Accepted
- Date: 2026-10-28

## Context

Recipe authors need to check definitions before their members are published or
installed. Required inputs and conditional prompts are valid declarations even
when no answers exist. Running a composition preview to check syntax couples
this authoring task to member availability, configuration and interactive input.

## Decision

`seihou validate-recipe [PATH]` reads the selected directory's `recipe.dhall`
(defaulting to the current directory), evaluates Dhall through the shared loader,
and calls the pure `Seihou.Core.Recipe.validateRecipe`. It never discovers or
installs members, resolves configuration or values, runs prompts, or plans/executes
composition. Normal Dhall imports retain their network and evaluator-cache behavior;
self-contained descriptors and local imports can be checked offline.

The shared validator owns descriptor-local rules for recipe names, nonempty and
unique members, binding names, unique variable declarations, well-formed POSIX validation patterns, declared prompt
targets and declared references throughout prompt conditions. Composition and
update use the same validator. The Dhall loader owns field shapes, types/defaults
and condition parsing, and malformed conditions identify their prompt and `when`.

Bindings remain literal text addressed to member variables; those variables need
not be recipe declarations. Checking member schemas, condition values, prompt
ordering/cycles and optional expression type lint are outside this contract.
Required declarations need no defaults or answers to be valid.

## Consequences

Authors and CI use the same ordinary command with no registry setup or installed
members. Success means the recipe descriptor is valid, without promising member
availability or correct composition behavior. Exit codes follow local validators:
0 for valid, 1 for load/semantic failure, 4 for a missing descriptor. Errors name
the descriptor and affected fields; independent semantic errors appear together.

Registry metadata validation, descriptor validation and a composition preview
remain separately discoverable workflows. Read-only behavior is verified through
the public binary with closed stdin and snapshots of project/configuration/install
state, including effectful members present, absent, and repeated invocations.

## References

- [Plan 115](../plans/115-validate-recipes-without-running-their-composition.md)
- [ADR 0015](0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md)
- [ADR 0020](0020-dependency-sources-belong-to-producer-edges.md)
- [ADR 0021](0021-recipe-inputs-resolve-before-module-defaults.md)
