# ADR 0024 — Recipes extend one origin-aware base

- Status: Accepted
- Date: 2026-11-01

## Context

A specialization should retain its relationship to a shared recipe. Copying a
module list hides that relationship from acquisition, updates and provenance;
Dhall record composition leaves distribution and version selection to authors.
The shared cache still has one slot per name, and module-instance identity must
continue to support legitimate parameterized dependencies.

## Decision

A recipe may declare one typed `extends` reference with a recipe name, optional
literal Git source and optional numeric inclusive-minimum/exclusive-before
interval. Resolve default-branch HEAD and validate its declared version; never
search historical tags. Absent sources are materialized from the declaring
registry on acquisition. A base edge requires a recipe; member edges require
modules. Source and interval requirements are producer contracts, independently
of a consumer's `--allow-downgrade` decision.

Expand the complete chain oldest first and compile one module composition. Keep
the oldest first member primary. A derived descriptor may add no modules; the
expanded composition must remain nonempty. Deduplicate identical same-origin
members, reject conflicting declarations and sources, and use `moduleOverrides`
to replace selected keys on exactly one inherited member without adding an
instance. Actual module dependency bindings retain their existing identities.

Recipe bindings remain global by variable name. Apply each child's literal delta
after its ancestor, rejecting unequal same-layer literals in extended chains.
Defaults are fallbacks and cannot replace inherited literals. Redeclarations
retain type, requiredness and validation; nearest supplied defaults/descriptions
win, while absent values preserve their ancestor. Identical repeated questions
deduplicate, explicit `promptOverrides` replace inherited questions in place,
and new questions append. Resolved members and literals retain their declaring
recipe, origin and directory. Descriptor-local checks remain independent of base
availability; merged expansion proves inherited references and compatibility.

Install, candidate update and recipe cache upgrade share a kind-aware closure
planner and normalized staging. Updates acquire the selected candidate roots to
a fixed point, including newly declared external sources. Historical bases and
dropped members are comparison evidence, not mandatory fetch roots; independently
required recorded-release certification can still fetch its own evidence. Run
remains offline. Cache upgrade includes bases even when the child is unchanged,
deduplicates roots and publishes validated entries together on handled failures.
Skipping a changed unversioned entry keeps the selected recipe refresh together.

Manifest schema 13 records an application's ordered recipe nodes with portable
identity, declared version and normalized descriptor digest. Digests prove change,
not identity. Null is unknown older history; accepted run/update adopts current
provenance without asserting which bases produced historical files. Guards compare
the selected application's complete chain. Metadata-only changes are actionable
and preserve unchanged application-command receipts. Run retains generation
provenance on command failure; update rolls it back with managed state.

A fresh clone's missing remote cache is actionable work in normal update, shown
in preview and published only on acceptance. Repeated update becomes a true no-op.
Saved optional omissions are retained; `--reconfigure` revisits optional choices.
The additive JSON schema-version-1 plan fields `recipeChains` and `cacheChanges`
report provenance and cache work without inventing module version changes.

## Consequences

Consumers install a derived root once and run it normally; existing projects use
one ordinary recipe update, including empty-cache clones. No transitive selector
list, hand-edited manifest, secondary lockfile, registry solver or Mori runtime is
required. Multiple parents, inherited-member removal and module inheritance remain
outside this contract. The schema, executable, author guidance and real producer
examples must be released and verified together; source tests alone do not deliver
the workflow to an installed user.

## References

- [ExecPlan 118](../plans/118-extend-recipes-through-a-single-origin-aware-base.md)
- [ADR 0003](0003-a-stale-or-substituted-artifact-is-a-hard-error.md)
- [ADR 0014](0014-every-semantic-manifest-change-advances-the-schema-version.md)
- [ADR 0020](0020-dependency-sources-belong-to-producer-edges.md)
- [ADR 0021](0021-recipe-inputs-resolve-before-module-defaults.md)
- [ADR 0022](0022-recipe-descriptor-validation-is-independent-of-composition.md)
- [ADR 0023](0023-command-receipts-are-published-before-the-command-phase-runs.md)
