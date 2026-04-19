# Module Instance Identity

| Field | Value |
|---|---|
| **Status** | Implemented |
| **Updated** | 2026-04-19 |
| **Created** | 2026-04-19 |
| **Subsystem** | Core — Composition |
| **Reference** | `docs/plans/10-parameterized-dep-multi-instantiation.md` |

## Overview

Seihou treats an invocation of a module in a composition as an instance keyed on the module name plus the parent-supplied variable bindings along the edge that reached it. Two dependency edges to the same child module with different `vars` produce two independent instances; identical edges dedupe to one.

## Motivation

The composition pipeline originally deduplicated by module name alone. When two parents declared a dependency on the same child with different `depVars`, the loader kept only the first-seen invocation and the resolver collapsed the bindings with a left-biased `Map.union`. Authors reusing a helper along multiple edges (the canonical case: `claude-skill-link` invoked once per skill a parent wants to surface) lost one of the invocations silently, producing a broken, partially-applied project.

Identity by parent bindings restores the intuition that the existing `dependencies = [ … ]` list already communicated: each list entry is an invocation. No new authoring syntax is required; the model change happens inside the composition pipeline.

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Identity key | `(ModuleName, ParentVars)` where `ParentVars = Map VarName Text` of the edge's `depVars` | Edge decoration is user-authored, stable across runs, and does not drift with downstream CLI/env overrides |
| Dedup semantics | Exact equality of the normalised parent-var map | Two parents that legitimately want the same child invocation share one instance; different bindings keep them distinct |
| No authoring syntax change | Composition model change only | Avoids an explicit `instances` keyword in `module.dhall` that would push anticipation onto every helper author |
| Overlapping bindings with different values | Emit a distinct instance rather than error | Matches the real-world use case (one helper, many parent-supplied names); erroring would force hand-written N copies of the helper |
| Qualified name scope | Used only where a `ModuleName` must be unique within a composition (`FileRecord.moduleName`, `PatchFileOp.moduleName`, internal manifest grouping) | Keeps user-facing surfaces (`VarSource.FromParent`, `seihou status`, `seihou vars --explain`) readable by rendering the bare name plus the bindings inline |
| Qualified name form | `<bare-name>#<stableHash>` where `stableHash` is the first 8 hex characters of SHA-256 over the canonical `name=value` lines sorted ascending by `VarName` | Deterministic within a run, cheap to compute, vanishingly unlikely to collide at 2^32 for realistic composition sizes |
| Manifest schema | Extend `AppliedModule` with a `parentVars` field; keep the `[AppliedModule]` container shape | The list already tolerated duplicate names structurally; the fix is making the rest of the pipeline stop treating it as a name-indexed set |
| Back-compat | Bump `currentManifestVersion` 1 → 2; decoder treats missing `parentVars` as empty | Version-1 manifests continue to load without migration |

## Domain Model

```haskell
-- In Seihou.Core.Types
newtype ParentVars = ParentVars { unParentVars :: Map VarName Text }
  deriving stock (Eq, Ord, Show)

emptyParentVars :: ParentVars
parentVarsFromDep :: Dependency -> ParentVars

-- In Seihou.Composition.Instance
data ModuleInstance = ModuleInstance
  { instanceModule     :: ModuleName
  , instanceParentVars :: ParentVars
  }
  deriving stock (Eq, Ord, Show)

mkInstance       :: ModuleName -> ParentVars -> ModuleInstance
primaryInstance  :: ModuleName -> ModuleInstance          -- ParentVars mempty
qualifiedName    :: ModuleInstance -> ModuleName          -- <bare> or <bare>#<hash>
stableHash       :: ParentVars   -> Text                  -- 8-char SHA-256 prefix
```

## Pipeline Flow

1. **Load** — `loadComposition` walks dependencies and produces `[(ModuleInstance, Module, FilePath)]`. The primary module and any `-m` additional modules receive `emptyParentVars`; each dependency edge contributes an instance keyed on the edge's `depVars`. `loadTransitive` dedupes by the full `ModuleInstance`, so identical edges share one entry while distinct edges both survive.

2. **Resolve** — `collectParentVars` keys on `ModuleInstance` using a plain `Map.fromList` (no union-merge, because each edge is distinct by construction). `resolveComposedVariables` and `resolveWithPrompts` return `Map ModuleInstance (Map VarName ResolvedVar)`. The visible-exports fold resolves each dependency edge to the exact child instance along that edge, not by bare module name, so per-instance exports do not bleed across siblings.

3. **Graph** — `CompositionGraph` is `Map ModuleInstance Module` plus `Map ModuleInstance [ModuleInstance]`. `buildGraph` dedupes edges so a parent that lists the same `(depModule, depVars)` twice still contributes one edge to the in-degree count. `topoSort` operates on instances end-to-end.

4. **Plan** — `compileComposedPlan` accepts `[(ModuleInstance, Module, FilePath, Map VarName VarValue)]` and passes the instance's `qualifiedName` into `compilePlan` for the `ModuleName` slot. The qualified name flows into `FileRecord.moduleName` and `PatchFileOp.moduleName` so two instances of the same module do not collide on file ownership.

5. **Execute** — `executePlan` takes an additional `Map FilePath ModuleName` ownership map (provided by `compileComposedPlan`'s merge step) and attributes each `FileRecord` to the module that produced the file. Callers without per-file ownership (tests, single-module flows) pass `Map.empty` and the default caller-supplied `ModuleName` wins.

6. **Manifest** — `AppliedModule.parentVars` records the bindings alongside the bare name. `updateAllModules` in the CLI matches existing entries by the `(name, parentVars)` pair so regenerating one invocation does not disturb its sibling.

## Business Rules

1. Two dependency edges with identical `depVars` are one instance; two edges with different `depVars` are two instances.
2. A bare dependency (`vars = [] : List { name : Text, value : Text }`) is the `emptyParentVars` instance.
3. Recipe expansion (`Seihou.Composition.Recipe.expandRecipe`) returns names, not instances; those names become primary instances inside `loadComposition` with `emptyParentVars`.
4. `qualifiedName` returns the bare name unchanged when `parentVars` is empty, so single-instance compositions produce the same file records as before.
5. User-facing surfaces that display a module name render it bare, and optionally append the bindings inline when disambiguation matters.
6. `currentManifestVersion = 2`; version-1 manifests decode with `parentVars = emptyParentVars`.

## Edge Cases

- **Two parents, same child, same bindings** — Dedupe to one instance. Both parents see the same resolved exports.
- **Two parents, same child, different bindings** — Two independent instances. Each parent sees the exports for its own invocation.
- **CLI override same variable for both instances** — Both resolved maps pick up the CLI value. Identity is still the parent bindings, not the resolved value; the manifest still records two entries.
- **Recipe expansion** — The expanded names become `emptyParentVars` instances, then their own `dependencies` lists produce further instances as usual.

## Testing Plan

- `Seihou.Composition.InstanceSpec` — `qualifiedName`/`stableHash` stability and distinctness.
- `Seihou.Composition.GraphSpec` — Diamond test asserting two distinct child instances reach the topo sort; identical-edges test asserting dedup.
- `Seihou.Composition.ResolveSpec` — Two-parent multi-instantiation test asserting both invocations resolve independently with their own `FromParent` provenance.
- `Seihou.Manifest.TypesSpec` — Round-trip for a manifest with two instances of the same module; version-1 decode with default `parentVars`.
- `Seihou.Integration.CompositionSpec` — End-to-end diamond fixture (`multi-instance-helper` / `multi-instance-leaf` / `multi-instance-diamond`) asserting `loadComposition` yields two helper entries and `compileComposedPlan` produces two distinct output files.

## Future Enhancements

- `seihou vars --explain` currently merges resolved maps across instances of the same module name. A future revision should surface per-instance variable tables when multiple instances exist.
- `seihou status` groups instances by bare module name; a compact one-line form that lists both bindings on a single row may be clearer for compositions with many instances.
- The 8-character `stableHash` prefix is adequate for in-composition disambiguation but is not a public identifier. If manifest external tooling ever wants to refer to instances by hash, the full digest (not a prefix) should be exposed under a dedicated field.
