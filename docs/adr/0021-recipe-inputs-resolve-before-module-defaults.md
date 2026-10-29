# ADR 0021 — Recipe inputs resolve before module defaults

- Status: Accepted
- Date: 2026-10-28

## Context

A composed module's default cannot answer a required recipe decision. Recipe-only
condition inputs also cannot be reconstructed from module instance records.

## Decision

Resolve recipe declarations and ordered prompts before resolving consumers. Use
CLI, literal recipe bindings, saved recipe inputs, environment, configuration, and
recipe defaults in that order. Broadcast only declared resolved recipe inputs,
above module saved values, parent bindings, exports and defaults. Preserve sources
and validate independently against every consuming declaration. Carry the source
through the broadcast itself so consumer failures identify the original source,
including literal recipe bindings, rather than the temporary explicit-input
channel. Required inputs
remain required when a prompt condition is false; optional absence is valid.

Record recipe inputs at application scope in manifest schema 12. Null means no
historical record; an empty map means the stage accepted no values. The lossless
11-to-12 upgrade records null without inferring choices. Ordinary update may adopt
agreeing saved instance values, while conflicts need explicit input or reconfigure.
A recipe-only required value with no history is new input. Reconfigure discards
both recipe and instance history. Publish adoption only with accepted application
work; previews and failures preserve the original manifest.

Constraints apply to every selected source before effects. Text patterns use
case-sensitive whole-value POSIX extended matching with multiline disabled;
malformed syntax is a failure even for an absent optional input. A binding supplies
a value above ambient preferences, while a constraint rejects disallowed explicit
overrides. Defaults alone do not enforce policy.

## Consequences

First use asks shared questions once, and fresh clones replay the accepted answer
without machine-local config. Adding a consumer does not change the recipe choice.
Literal entry binding flattening and parameterized instance identity remain intact.
No synthetic module or secondary state file represents recipe inputs.

## References

- [ADR 0014](0014-every-semantic-manifest-change-advances-the-schema-version.md)
- [Plan 114](../plans/114-resolve-recipe-variables-and-prompts-before-module-resolution.md)

- [Plan 117](../plans/117-let-recipes-enforce-configured-variable-values.md)
