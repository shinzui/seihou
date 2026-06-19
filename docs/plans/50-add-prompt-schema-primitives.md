---
id: 50
slug: add-prompt-schema-primitives
title: "Add prompt schema primitives"
kind: exec-plan
created_at: 2026-06-19T16:22:12Z
intention: "intention_01kvgax2mfezgsw4rrzsk012qc"
master_plan: "docs/masterplans/6-first-class-prompt-support.md"
---

# Add prompt schema primitives

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, Seihou's schema package can describe first-class prompt artifacts and command-derived variables. A prompt artifact is a directory containing `prompt.dhall`, a Markdown prompt body, and optional reference files; it is meant for reusable agent sessions, not deterministic scaffolding. A command-derived variable is a declared variable whose value is produced by running a local command before prompt rendering.

The visible proof is that a Dhall file using `S.AgentPrompt::{ ... }` and `S.CommandVar::{ ... }` evaluates successfully against both the external schema repository at `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema` and Seihou's local `schema/` mirror.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] 2026-06-19: Marked EP-50 In Progress in `docs/masterplans/6-first-class-prompt-support.md`.
- [x] 2026-06-19: Updated the external `seihou-schema` package with `CommandVar.dhall`, `AgentPrompt.dhall`, `Blueprint.dhall`, migration schema exports, package exports, README export docs, and `examples/agent-prompt.dhall`.
- [x] 2026-06-19: Updated this repository's local `schema/` mirror with matching `CommandVar.dhall`, `AgentPrompt.dhall`, package exports, README export docs, and `schema/examples/agent-prompt.dhall`.
- [x] 2026-06-19: Validated both package roots and both prompt examples with `dhall type --file ...`.
- [x] 2026-06-19: Recorded the schema hash/update workflow needed by later CLI scaffolding work.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Discovery: The external `seihou-schema` checkout was missing the local mirror's migration schema exports in addition to `Blueprint.dhall`.
  Evidence: `diff -u /Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/Module.dhall schema/Module.dhall` showed the local `Module.dhall` had a `migrations : List Migration.Type` field and the external one did not; the external package also lacked `MigrationOp.dhall` and `Migration.dhall`.
  Date: 2026-06-19

- Discovery: The external and local schema packages now normalize to the same Dhall integrity hash.
  Evidence: running `dhall hash < package.dhall` in both `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema` and `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/schema` produced `sha256:fcb8ff3d67d2735e3c946ae18b47e8c0ef195439b478e0b1284665dfca579f5e`.
  Date: 2026-06-19


## Decision Log

Record every decision made while working on the plan.

- Decision: Use `AgentPrompt` as the schema export name and `prompt.dhall` as the on-disk file name.
  Rationale: `Prompt.dhall` already defines interactive variable questions; `AgentPrompt` keeps schema names unambiguous while preserving the user-facing term "prompt".
  Date: 2026-06-19

- Decision: Define command-derived variables as a reusable `CommandVar` record, not as fields embedded only in `AgentPrompt`.
  Rationale: Blueprints or modules may later want the same source type; a reusable record prevents a second incompatible command-variable shape.
  Date: 2026-06-19

- Decision: Synchronize the external schema package with the local mirror's already-existing migration schema while adding prompt primitives.
  Rationale: Later prompt work imports the schema package as a coherent surface. Leaving the external package behind the local mirror would preserve divergent normalized hashes and make `SchemaVersion.hs` updates ambiguous.
  Date: 2026-06-19


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

EP-50 added prompt and command-derived-variable Dhall primitives in both schema locations, added checked examples, and synchronized the external schema package with the local mirror for previously-missing blueprint and migration exports. The external and local `package.dhall` files both typecheck, the prompt examples typecheck, and both packages have the same normalized Dhall hash: `sha256:fcb8ff3d67d2735e3c946ae18b47e8c0ef195439b478e0b1284665dfca579f5e`.

Later CLI scaffolding work should publish or otherwise pin a commit that contains these schema changes, then update `seihou-cli/src/Seihou/CLI/SchemaVersion.hs` so `schemaUrl` points at that commit's raw `package.dhall` and `schemaHash` uses the hash above or the hash recomputed from the committed package. The existing local workflow is documented in `claude/skills/update-seihou-schema/SKILL.md`: compute `dhall hash < schema/package.dhall`, update `SchemaVersion.hs`, update the Nix flake input if the schema source pin changes, then run the relevant build and test gates.


## Context and Orientation

This work spans two checked-out repositories. The schema source of truth discovered with Mori is `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema`. This repository also carries a local schema mirror under `schema/` for tests and embedded examples.

The external schema package currently exports `VarDecl`, `VarExport`, `Prompt`, `Step`, `Command`, `Dependency`, `RemovalStep`, `Removal`, `Module`, and `Recipe` from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/package.dhall`. It does not currently include `Blueprint.dhall`, while this repository's local mirror has `schema/Blueprint.dhall`. Treat that mismatch as a schema-publication cleanup item: do not remove local blueprint support while adding prompt support.

The existing `schema/Blueprint.dhall` shape is useful precedent. It imports `VarDecl`, `Prompt`, and `Dependency`, defines a nested `BlueprintFile` record, and exports a `default` record for Dhall record completion. A prompt artifact should follow the same pattern so authors can write:

```dhall
let S = ./package.dhall

in  S.AgentPrompt::{
    , name = "review-changes"
    , prompt = ./prompt.md as Text
    }
```

In this plan, "schema primitive" means a Dhall file that defines `{ Type, default }` and is exported by `package.dhall`. "Record completion" means Dhall's `S.AgentPrompt::{ ... }` syntax, where omitted fields come from `S.AgentPrompt.default`.


## Plan of Work

Milestone 1 defines the schema records in the external schema repository. Add `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/CommandVar.dhall` with a `Type` containing at least `name : Text`, `run : Text`, `workDir : Optional Text`, `when : Optional Text`, `trim : Bool`, and `maxBytes : Optional Natural`. Use defaults of `workDir = None Text`, `when = None Text`, `trim = True`, and `maxBytes = Some 4096`. Add `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/AgentPrompt.dhall` with fields `name`, `version`, `description`, `prompt`, `vars`, `prompts`, `commandVars`, `files`, `allowedTools`, `tags`, and `launch`. The `files` field should mirror blueprint reference files. The `launch` field should be optional metadata for future runner defaults; keep it simple and optional so the first runner can still use normal agent config.

Milestone 2 updates package exports and examples. Edit `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/package.dhall` to export `CommandVar` and `AgentPrompt`. If the external schema package still lacks `Blueprint.dhall`, either add it from this repository's mirror in the same change or explicitly record why prompt support is proceeding with the mismatch. The preferred outcome is that the external package exports both `Blueprint` and `AgentPrompt`.

Milestone 3 mirrors the schema into this repository. Add matching `schema/CommandVar.dhall` and `schema/AgentPrompt.dhall`, and update `schema/package.dhall`. The local mirror must match field names exactly because Seihou tests and scaffolding use it as a compact reference.

Milestone 4 validates Dhall evaluation. Add small examples under the appropriate test/example location in the schema repository if it has one; otherwise validate with direct `dhall type` or `dhall resolve` commands. In the Seihou repository, make sure a local `schema/package.dhall` import can evaluate a minimal prompt and a prompt with one `commandVars` entry.


## Concrete Steps

Run these commands from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` before editing:

```bash
mori registry show shinzui/seihou-schema --full
rg --files /Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema
sed -n '1,220p' schema/Blueprint.dhall
sed -n '1,220p' schema/package.dhall
```

After editing the external schema package, run from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema`:

```bash
dhall type --file package.dhall
```

After editing the local mirror, run from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`:

```bash
dhall type --file schema/package.dhall
cabal test seihou-core-test --test-options '--pattern Schema'
```

If the test runner does not support the pattern, run the full core suite instead:

```bash
cabal test seihou-core-test
```


## Validation and Acceptance

Acceptance is met when a minimal prompt schema expression evaluates in both schema locations. This expression should typecheck against the local mirror:

```dhall
let S = ./schema/package.dhall

in  S.AgentPrompt::{
    , name = "review-changes"
    , prompt = "Review the current repository."
    , commandVars =
      [ S.CommandVar::{ name = "git.branch", run = "git branch --show-current" }
      ]
    }
```

The expected result is a Dhall record with defaulted `version`, `description`, `vars`, `prompts`, `files`, `allowedTools`, `tags`, and launch metadata.


## Idempotence and Recovery

Schema edits are additive and safe to repeat. If Dhall typechecking fails, inspect the field named in the error and compare the external schema file with the local mirror. Do not delete existing schema files to make the prompt schema typecheck. If the external schema repository has uncommitted unrelated changes, leave them intact and only edit the new prompt-related files and package exports.


## Interfaces and Dependencies

This plan depends on the local `shinzui/seihou-schema` project discovered by Mori. Use Dhall records only; no Haskell code is required in this plan.

At the end, these files must exist and be exported:

```text
/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/CommandVar.dhall
/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/AgentPrompt.dhall
/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/package.dhall
schema/CommandVar.dhall
schema/AgentPrompt.dhall
schema/package.dhall
```

Later plans consume the field names `commandVars`, `files`, `allowedTools`, `tags`, and `prompt` exactly as defined here.
