---
id: 61
slug: add-prompt-guidance
title: "Add prompt guidance"
kind: exec-plan
created_at: 2026-06-19T20:45:52Z
intention: "intention_01kvgszstbevga4pp0jx00t8wg"
---

# Add prompt guidance

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, a prompt author can package repo-specific or project-specific guidance with a reusable `prompt.dhall`, and `seihou prompt run` will render that guidance around the normal prompt body before launching Claude Code, Codex, Anthropic, or OpenAI. This gives prompts the same kind of surrounding context that blueprints already receive, without making prompts apply baseline modules or record blueprint provenance.

The observable behavior is that a prompt can declare guidance blocks such as "when this repository has a `cabal.project`, prefer `cabal build` and `cabal test`" or "when this project uses Nix, run `nix flake check`." The author expresses the detection through existing typed variables or `commandVars`, and each guidance block uses the same optional `when` expression language already used by interactive prompts and command-derived variables. Running `seihou prompt run NAME --debug` prints a complete system prompt that includes the current Seihou project context, prompt identity, reference-file list, selected guidance blocks, the rendered prompt body, and any one-off user instruction.


## Progress

- [x] Add the prompt-guidance Dhall schema primitive to the external `shinzui/seihou-schema` checkout and the local `schema/` mirror. Completed 2026-06-19T21:02:49Z.
- [x] Extend the Haskell prompt domain model, Dhall decoder, and validation rules to carry guidance blocks. Completed 2026-06-19T21:02:49Z.
- [x] Add prompt-run system-prompt rendering, including conditional guidance selection after command-derived variables are resolved. Completed 2026-06-19T21:02:49Z.
- [x] Update prompt scaffolding, tests, user docs, CLI docs, help text, and changelog material. Completed 2026-06-19T21:02:49Z.
- [x] Run the targeted core, CLI, schema, formatting, and build validation commands and record the results here. Completed 2026-06-19T21:06:10Z.

Focused validation run 2026-06-19T21:02:49Z:

```text
cabal test seihou-core-test --test-options '--pattern "Seihou.Core.AgentPrompt"'
All 15 tests passed (0.02s)

cabal test seihou-cli-test --test-options '--pattern "Seihou.CLI.PromptRender"'
All 3 tests passed (0.02s)
```

Final validation run 2026-06-19T21:06:10Z:

```text
dhall type --file schema/AgentPrompt.dhall
PromptGuidance : { Type : Type, default : { when : Optional Text } }

dhall type --file /Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/AgentPrompt.dhall
PromptGuidance : { Type : Type, default : { when : Optional Text } }

nix fmt
formatted 1 files (0 changed) in 302ms

cabal build all
Exit code 0

cabal test all
Test suite seihou-okf-extension-test: PASS
Test suite seihou-core-test: PASS
Test suite seihou-cli-test: PASS

nix build .#seihou-cli --no-link
Exit code 0
```

Smoke validation used a temporary installed search path because `seihou prompt run` does not discover arbitrary directories outside project, user, or installed search paths:

```text
XDG_CONFIG_HOME="$tmp/config" cabal run seihou -- new-prompt guided-demo --path "$tmp/config/seihou/installed/guided-demo"
XDG_CONFIG_HOME="$tmp/config" cabal run seihou -- validate-prompt "$tmp/config/seihou/installed/guided-demo"
XDG_CONFIG_HOME="$tmp/config" cabal run seihou -- prompt run guided-demo --debug --namespace guided-demo

Prompt 'guided-demo' is valid.
## Prompt Guidance
### Repository workflow
Inspect the project before editing, keep changes scoped, and run the smallest useful validation command.
```


## Surprises & Discoveries

- The external `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema` checkout already had an unrelated `Step.dhall` documentation change before the schema commit for this plan. Evidence from `git -C /Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema diff -- Step.dhall` shows only a comment addition for valid patch values. It was left untouched by this plan's commits.


## Decision Log

- Decision: Model prompt guidance as a list of named Markdown blocks on `AgentPrompt`, not as a new runnable artifact and not as an extension of `Blueprint`.
  Rationale: The user's request is a follow-up to first-class prompts. The desired behavior is to adjust a prompt for a specific repo or project while keeping prompt runtime semantics: no baseline module application, no `.seihou/manifest.json` applied-blueprint record, and continued use of `seihou prompt run`.
  Date: 2026-06-19

- Decision: Give each guidance block `title : Text`, `body : Text`, and `when : Optional Text`.
  Rationale: This is enough to express repo-specific guidance in plain Markdown, while reusing Seihou's existing expression parser and evaluator for conditional selection. Repo/project detection can come from normal variables or from `commandVars`, which already run local commands safely and produce resolved variables.
  Date: 2026-06-19

- Decision: Render prompts through a new prompt-run system template, similar to `seihou-cli/data/blueprint-prompt.md`, instead of sending only the rendered prompt body to the provider.
  Rationale: Guidance must be framed as instructions and context for the agent, not merely appended to the user's task. A system template also lets `--debug` expose the exact provider input and keeps prompt rendering consistent with the blueprint path.
  Date: 2026-06-19


## Outcomes & Retrospective

Implemented prompt guidance end to end. `AgentPrompt` now carries `PromptGuidance` blocks decoded from Dhall with a backwards-compatible missing-field default. Validation rejects blank guidance titles and bodies and rejects `when` conditions that reference undeclared typed or command-derived variables. `seihou prompt run` now renders a complete provider prompt with current project context, prompt identity, reference files, selected guidance, the rendered prompt body, and the optional one-off user instruction before calling the existing provider launch path.

New prompt scaffolds include a starter guidance block, and prompt documentation, CLI references, embedded help, README, and changelog material describe the new field and debug behavior. The local `schema/` gitlink checkout and the external `shinzui/seihou-schema` checkout both typecheck with the new schema primitive, and the Nix flake now stages the checked-in `schema` submodule commit for `seihou-core` and `seihou-cli` builds. No blueprint baseline or applied-blueprint manifest behavior was added to prompts.


## Context and Orientation

Seihou is a Haskell project with two main packages: `seihou-core` for domain types, Dhall loading, validation, composition, and effects; and `seihou-cli` for command-line handlers and user-facing runners. The repository also carries a local Dhall schema mirror under `schema/`, while the registered dependency `shinzui/seihou-schema` lives at `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema`. The user-provided `AGENTS.md` instructions require using `mori` before guessing at dependency APIs; the initial research did that with `mori show --full`, `mori registry list`, and `mori registry show shinzui/seihou-schema --full`.

A "prompt" in this repository is a first-class runnable artifact stored in a directory containing `prompt.dhall`, `prompt.md`, and optional reference files in `files/`. In Haskell it is named `AgentPrompt` because `Prompt` already means an interactive question for a variable. The relevant domain type is `AgentPrompt` in `seihou-core/src/Seihou/Core/Types.hs`. It has `name`, `version`, `description`, `prompt`, `vars`, `prompts`, `commandVars`, `guidance`, `files`, `allowedTools`, `tags`, and `launch`.

A "blueprint" is an agent-driven scaffolding artifact. It has a richer runner in `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`: it validates a `Blueprint`, resolves variables, optionally applies baseline modules, gathers project context, renders `seihou-cli/data/blueprint-prompt.md`, launches the provider, and records applied-blueprint provenance in `.seihou/manifest.json`. Prompt guidance should borrow the context-rendering idea from blueprints, but not the baseline or manifest behavior.

The prompt runner is `seihou-cli/src-exe/Seihou/CLI/PromptRun.hs`. It discovers a `RunnableAgentPrompt`, validates it with `validateAgentPrompt` from `seihou-core/src/Seihou/Core/AgentPrompt.hs`, resolves normal variables through `resolveWithPrompts`, resolves command-derived variables with `resolveCommandVars`, substitutes `{{variable.name}}` placeholders into `prompt.prompt`, gathers project context, renders `seihou-cli/data/prompt-run-prompt.md` through `Seihou.CLI.PromptRender.renderPromptSystemPrompt`, and then calls `runRenderedAgentPrompt`. `--debug` prints the complete provider prompt without contacting a provider.

The shared context and formatting helpers live in `seihou-cli/src/Seihou/CLI/AgentLaunch.hs`. `gatherAgentContext` records the current directory, whether `.seihou/` and `.seihou/manifest.json` exist, whether `module.dhall` exists, local module hints, and available modules from search paths. `formatSeihouProjectState`, `formatManifestState`, `formatModuleDhallState`, `formatLocalModules`, `formatAvailableModules`, and `formatReferenceFiles` are already exported and can be reused by the prompt runner.

The Dhall decoder for prompts is `agentPromptDecoder` in `seihou-core/src/Seihou/Dhall/Eval.hs`. The validation module `seihou-core/src/Seihou/Core/AgentPrompt.hs` checks prompt name format, optional version, non-empty body, unique variables, prompt references, command variables, guidance, files, tags, and allowed tools. The expression parser and evaluator are in `seihou-core/src/Seihou/Core/Expr.hs`; `evalExpr :: Map VarName VarValue -> Expr -> Bool` is exported and used for guidance `when` conditions.

The schema files to update are `schema/AgentPrompt.dhall` in this repo and `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/AgentPrompt.dhall` in the dependency checkout. `schema/package.dhall` and the dependency checkout's `package.dhall` export schema primitives. `seihou-core/src/Seihou/Core/Scaffold.hs` emits fresh prompt scaffolds through `promptDhall` and `exampleAgentPromptMarkdown`; the current scaffold is self-contained rather than schema-importing because the public schema pin can lag local development.

Existing documentation for prompts is in `docs/user/prompts.md`, `docs/cli/prompt.md`, `docs/cli/validate-prompt.md`, `docs/cli/new-prompt.md`, and `seihou-cli/help/prompts.md`. Existing blueprint documentation in `docs/user/blueprints.md` is useful as a comparison point, especially the distinction that prompts do not apply baseline modules.


## Plan of Work

Milestone 1 adds schema and core domain support. At the end of this milestone, `prompt.dhall` can contain a `guidance` list, Haskell can decode it into an `AgentPrompt`, and validation can reject malformed guidance before any provider launch. The independently verifiable outcome is a core test that decodes a prompt with guidance and checks that empty titles, empty bodies, and bad condition references fail validation.

Add a new prompt-guidance schema record in both schema locations. The simplest shape is:

```dhall
let PromptGuidance =
      { Type = { title : Text, body : Text, when : Optional Text }
      , default = { when = None Text }
      }
```

Then add `guidance : List PromptGuidance.Type` to `AgentPrompt.Type`, `guidance = [] : List PromptGuidance.Type` to `AgentPrompt.default`, and export `PromptGuidance` from `AgentPrompt.dhall`. If `package.dhall` has top-level exports for nested prompt pieces, add a top-level `PromptGuidance` export there too; otherwise keep it nested as `S.AgentPrompt.PromptGuidance.Type`, matching how `PromptFile` and `Launch` are exposed today.

In `seihou-core/src/Seihou/Core/Types.hs`, add:

```haskell
data PromptGuidance = PromptGuidance
  { title :: Text,
    body :: Text,
    condition :: Maybe Expr
  }
  deriving stock (Eq, Show, Generic)
```

Export `PromptGuidance (..)` and insert a new `guidance :: [PromptGuidance]` field into `AgentPrompt`. Put the field after `commandVars` and before `files`, because guidance is rendered after all variables, including command-derived variables, are known, and before reference-file metadata in the prompt-run template. Update every positional `AgentPrompt` construction in tests and code.

In `seihou-core/src/Seihou/Dhall/Eval.hs`, add `promptGuidanceDecoder :: Decoder PromptGuidance` near `commandVarDecoder`. It should mirror `commandVarDecoder`'s `when` handling by reading `when` as `Optional Text` and storing `parseWhen whenText` in `condition`. Add `field "guidance" (list promptGuidanceDecoder)` to `agentPromptDecoder`, and force guidance conditions in `evalAgentPromptFromFile` with `mapM_ (\g -> evaluate g.condition) p.guidance`.

In `seihou-core/src/Seihou/Core/AgentPrompt.hs`, add `checkAgentPromptGuidance` and include it in `pureErrs`. It should reject guidance blocks whose `title` or `body` is blank after trimming. It should also flag guidance `when` expressions that reference variables unknown to the prompt. Build the known set from `p.vars` and `p.commandVars`; then use `exprRefs` from `Seihou.Core.Expr` to collect variable names from each `condition`. Error text should be precise enough for authors, for example `guidance 'Haskell project' references undeclared variable: repo.kind`.

Update `seihou-core/test/Seihou/Core/AgentPromptSpec.hs`. Extend `goodAgentPrompt`, helper constructors, and `samplePromptDhall` with the new `guidance` field. Add tests that decode guidance, accept a valid guidance block, reject blank title/body, and reject a guidance condition that references a variable not declared in either `vars` or `commandVars`.

Milestone 2 adds prompt-run rendering. At the end of this milestone, `seihou prompt run NAME --debug` prints a full system prompt containing selected guidance and repository context instead of only the raw prompt body. The independently verifiable outcome is a CLI-level or pure formatter test that proves a guidance block whose `when` evaluates true appears in the debug output, while a false block does not.

Add a new embedded Markdown template at `seihou-cli/data/prompt-run-prompt.md`. It should be similar in spirit to `seihou-cli/data/blueprint-prompt.md`, but it must say the session is a Seihou prompt rather than a blueprint and must not mention baseline application or applied-blueprint commits. The template should include these placeholders:

```text
{{cwd}}
{{seihou_project_state}}
{{manifest_state}}
{{module_dhall_state}}
{{local_modules}}
{{available_modules}}
{{prompt_name}}
{{prompt_version}}
{{prompt_description}}
{{reference_files}}
{{prompt_guidance}}
{{prompt_body}}
{{user_prompt}}
```

In `seihou-cli/src-exe/Seihou/CLI/PromptRun.hs`, embed the template with `Data.FileEmbed.embedFile`, as `AgentRun` does for `blueprint-prompt.md`. Import `gatherAgentContext`, the context formatters, `formatReferenceFiles`, and `substitute` from `Seihou.CLI.AgentLaunch`. Add pure helpers:

```haskell
renderPromptSystemPrompt ::
  AgentContext ->
  AgentPrompt ->
  Map VarName ResolvedVar ->
  Text ->
  Text

formatPromptGuidance ::
  Map VarName ResolvedVar ->
  [PromptGuidance] ->
  Text
```

`formatPromptGuidance` should convert `Map VarName ResolvedVar` into `Map VarName VarValue`, keep guidance blocks with `condition = Nothing` or `evalExpr bindings condition = True`, and render each selected block as Markdown with a heading derived from `title` followed by `body`. When no blocks are selected, it should return `(no prompt guidance)`. Keep the exact rendering stable so tests can assert substrings.

Modify `handlePromptRun` so that after command variables resolve, it still computes `renderedPrompt = renderPromptBody resolved prompt.prompt`, but then calls `ctx <- gatherAgentContext` and `systemPrompt = renderPromptSystemPrompt ctx prompt resolved renderedPrompt`. Pass `systemPrompt` to `runRenderedAgentPrompt` instead of passing `renderedPrompt` directly. Keep `opts.runPromptPrompt` as the initial or one-off user prompt argument, matching the existing provider interface.

Update tests in `seihou-cli/test`. If there is no existing `PromptRun` test module, add one and register it from `seihou-cli/test/Main.hs`. The lowest-friction test is pure: expose `renderPromptSystemPrompt` and `formatPromptGuidance` from `PromptRun`, construct a small `AgentContext`, a small `AgentPrompt`, and a resolved variable map, then assert that debug-rendered text includes `## Prompt Guidance`, includes the true block body, omits the false block body, and still includes the prompt body. If exporting these helpers from an executable module is awkward, move them into a new library module such as `seihou-cli/src/Seihou/CLI/PromptRender.hs` and have both the executable handler and tests import that module. Prefer the new library module if Cabal visibility makes executable-module testing brittle.

Milestone 3 updates scaffolding, docs, and validation examples. At the end of this milestone, newly scaffolded prompts show authors how to use guidance, the user docs explain the difference between guidance and the prompt body, and `validate-prompt` docs describe the new checks. The independently verifiable outcome is that `seihou new-prompt demo`, `seihou validate-prompt demo`, and `seihou prompt run demo --debug` show a guidance section without contacting a provider.

In `seihou-core/src/Seihou/Core/Scaffold.hs`, add the explicit `PromptGuidance` type alias to the self-contained `promptDhall` output and include a starter `guidance` field. Keep it minimal; for example:

```dhall
, guidance =
  [ { title = "Repository workflow"
    , body = "Inspect the project before editing, keep changes scoped, and run the smallest useful validation command."
    , when = None Text
    }
  ]
```

Update `exampleAgentPromptMarkdown` only if the body currently repeats instructions that now belong in guidance. Do not remove the body entirely; it should remain the task-specific user prompt template.

Update `docs/user/prompts.md` to describe `guidance` as structured Markdown blocks rendered around the prompt body. Include an example where a `commandVar` detects a project kind and a guidance block uses `when = Some "Eq repo.kind haskell"`. Make clear that guidance is for repo/project adaptation and workflow rules, while `prompt` remains the main task body. Update the field table, the running behavior description, and the reference-file section if needed.

Update `docs/cli/prompt.md` so `--debug` says it prints the complete rendered provider prompt, including context and guidance. Update `docs/cli/validate-prompt.md` to include guidance title/body and guidance condition reference checks. Update `docs/cli/new-prompt.md`, `seihou-cli/help/prompts.md`, `README.md`, and the appropriate changelog file if their prompt descriptions list every prompt field or debug behavior. Keep the docs consistent: prompt guidance does not imply blueprint baselines, scaffold generation, or manifest provenance.

Milestone 4 runs final validation and records results. At the end of this milestone, the code is formatted, focused tests pass, and the plan's living sections record what changed and what remains.


## Concrete Steps

Start from the repository root:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
```

Confirm the project identity and dependency source locations before editing:

```bash
mori show --full
mori registry show shinzui/seihou-schema --full
```

The first command should identify `shinzui/seihou` as a Haskell application with `seihou-core` and `seihou-cli` packages. The second should show the schema checkout path:

```text
Path: /Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema
```

Implement Milestone 1 by editing these files:

```text
/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/AgentPrompt.dhall
/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/package.dhall
schema/AgentPrompt.dhall
schema/package.dhall
seihou-core/src/Seihou/Core/Types.hs
seihou-core/src/Seihou/Dhall/Eval.hs
seihou-core/src/Seihou/Core/AgentPrompt.hs
seihou-core/test/Seihou/Core/AgentPromptSpec.hs
```

After Milestone 1, run the focused core tests:

```bash
cabal test seihou-core-test --test-options '--pattern "Seihou.Core.AgentPrompt"'
```

The expected successful transcript ends with a passing Tasty/Hspec summary. The exact number of examples may change as tests are added, but failures should be zero:

```text
0 failures
```

Implement Milestone 2 by adding the prompt-run template and rendering helpers:

```text
seihou-cli/data/prompt-run-prompt.md
seihou-cli/src-exe/Seihou/CLI/PromptRun.hs
seihou-cli/src/Seihou/CLI/PromptRender.hs
seihou-cli/seihou-cli.cabal
seihou-cli/test/Seihou/CLI/PromptRenderSpec.hs
seihou-cli/test/Main.hs
```

If the pure helper module is not needed, omit `Seihou.CLI.PromptRender`; otherwise add it to the `exposed-modules` or `other-modules` stanza that matches the existing `seihou-cli` test pattern. After Milestone 2, run:

```bash
cabal test seihou-cli-test --test-options '--pattern "Seihou.CLI.PromptRender"'
```

The expected result is a passing test that shows selected guidance is included and unselected guidance is omitted.

Implement Milestone 3 by editing docs and scaffolding:

```text
seihou-core/src/Seihou/Core/Scaffold.hs
docs/user/prompts.md
docs/cli/prompt.md
docs/cli/validate-prompt.md
docs/cli/new-prompt.md
seihou-cli/help/prompts.md
README.md
CHANGELOG.md
docs/user/CHANGELOG.md
```

Smoke-test the scaffold in a temporary directory. The command below uses a temporary `XDG_CONFIG_HOME` so it does not depend on user config:

```bash
tmp=$(mktemp -d)
XDG_CONFIG_HOME="$tmp/config" cabal run seihou -- new-prompt guided-demo --path "$tmp/guided-demo"
XDG_CONFIG_HOME="$tmp/config" cabal run seihou -- validate-prompt "$tmp/guided-demo"
XDG_CONFIG_HOME="$tmp/config" cabal run seihou -- prompt run guided-demo --debug --namespace guided-demo
```

If discovery cannot find a prompt outside the configured search paths, run the debug command from the generated prompt directory or copy the directory under one of the standard Seihou search paths for the smoke. Record the exact working command in this plan's Progress section.

Run formatting and the broader build/test gates:

```bash
nix fmt
cabal build all
cabal test all
```

If the project convention is to run through the Seihou wrapper, use:

```bash
seihou run
```

Only use the wrapper if it is documented for this repository or already used by nearby plans; otherwise the Cabal commands above are sufficient.


## Validation and Acceptance

The feature is accepted when all of the following are true.

A `prompt.dhall` with `guidance` decodes successfully. A minimal example should look like:

```dhall
{ name = "review-guided"
, version = Some "0.1.0"
, description = Some "Review with repo guidance"
, prompt = "Review {{project.name}}."
, vars =
  [ { name = "project.name"
    , type = "text"
    , default = Some "seihou"
    , description = None Text
    , required = False
    , validation = None Text
    }
  ]
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
, commandVars =
  [ { name = "repo.kind"
    , run = "if test -f cabal.project; then echo haskell; else echo unknown; fi"
    , workDir = None Text
    , when = None Text
    , trim = True
    , maxBytes = Some 100
    }
  ]
, guidance =
  [ { title = "Haskell repository"
    , body = "Prefer `cabal build all` and focused `cabal test` commands for validation."
    , when = Some "Eq repo.kind haskell"
    }
  ]
, files = [] : List { src : Text, description : Optional Text }
, allowedTools = None (List Text)
, tags = [ "review" ]
, launch = None { provider : Optional Text, mode : Optional Text, model : Optional Text }
}
```

Validation rejects malformed guidance with actionable errors. A blank title or body should produce messages containing `guidance title must not be empty` or `guidance body must not be empty`. A condition that references an undeclared variable should produce a message containing `guidance` and `references undeclared variable`.

`seihou prompt run NAME --debug` prints a complete provider prompt. The output must include the current environment block, prompt identity block, reference-file block, prompt guidance block, and the rendered task body. It must include guidance whose `when` expression evaluates true against resolved normal plus command-derived variables, omit guidance whose `when` evaluates false, and print `(no prompt guidance)` when none are selected.

Non-debug prompt runs continue to use the existing provider configuration and launch path. CLI providers still start Claude Code or Codex through `runRenderedAgentPrompt`; API providers still send a one-shot completion. Prompt runs still do not apply blueprint `baseModules` and still do not write applied-blueprint provenance into `.seihou/manifest.json`.

The following commands pass from the repository root:

```bash
nix fmt
cabal build all
cabal test all
```


## Idempotence and Recovery

The schema and Haskell edits are additive, with one important compatibility requirement: the `AgentPrompt` Dhall default must set `guidance = []`, and scaffolded prompt records must include an explicit empty-list type or a starter list. Existing prompt records that use `S.AgentPrompt::{ ... }` should continue to evaluate because record completion fills the new field from the default. Existing self-contained prompt records without `guidance` will fail against a strict Haskell decoder unless the decoder is made backwards-compatible. To preserve existing prompt artifacts, implement `agentPromptDecoder` so missing `guidance` decodes as an empty list, using the same missing-field defaulting pattern already present in registry decoding if available. If that is too invasive, update the plan's Decision Log before accepting a breaking schema change.

The prompt-run rendering change is safe to retry. If the debug output is wrong, run the pure formatter tests first, then run `seihou prompt run NAME --debug`; debug mode never contacts a provider. If non-debug launches fail, verify that `runRenderedAgentPrompt` still receives the same provider config and initial prompt argument as before, with only the rendered system prompt changed.

The temporary smoke-test directory can be deleted after validation. Do not delete project files or reset the Git worktree. If generated scaffold output is wrong, edit `seihou-core/src/Seihou/Core/Scaffold.hs`, rerun `seihou new-prompt` in a fresh temporary directory, and validate again.

If edits to `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema` reveal that the dependency checkout has uncommitted unrelated changes, do not revert them. Work with the current file contents and record any relevant drift in Surprises & Discoveries.


## Interfaces and Dependencies

The new core interface is:

```haskell
data PromptGuidance = PromptGuidance
  { title :: Text,
    body :: Text,
    condition :: Maybe Expr
  }
  deriving stock (Eq, Show, Generic)

data AgentPrompt = AgentPrompt
  { name :: ModuleName,
    version :: Maybe Text,
    description :: Maybe Text,
    prompt :: Text,
    vars :: [VarDecl],
    prompts :: [Prompt],
    commandVars :: [CommandVar],
    guidance :: [PromptGuidance],
    files :: [BlueprintFile],
    allowedTools :: Maybe [Text],
    tags :: [Text],
    launch :: Maybe AgentPromptLaunch
  }
```

The new Dhall schema interface is:

```dhall
let PromptGuidance =
      { Type = { title : Text, body : Text, when : Optional Text }
      , default = { when = None Text }
      }
```

`AgentPrompt.Type` must contain `guidance : List PromptGuidance.Type`, and `AgentPrompt.default` must contain `guidance = [] : List PromptGuidance.Type`.

The prompt-rendering interface should live in `seihou-cli/src/Seihou/CLI/PromptRender.hs` if tests need a library module:

```haskell
module Seihou.CLI.PromptRender
  ( renderPromptSystemPrompt,
    formatPromptGuidance,
  )
where
```

It should depend on `Seihou.CLI.AgentLaunch.AgentContext`, `Seihou.CLI.AgentLaunch.substitute`, the existing `format*` helpers, `Seihou.Core.Expr.evalExpr`, and `Seihou.Core.Types`. It should not depend on process execution, provider execution, manifest writing, or blueprint baseline code.

The executable handler `seihou-cli/src-exe/Seihou/CLI/PromptRun.hs` should continue to own discovery, validation, variable resolution, command-derived variable execution, and provider launch. Its only behavior change is that it renders a prompt-run system prompt after `resolveCommandVars` succeeds.

This plan depends on the already-completed prompt initiative documented in `docs/masterplans/6-first-class-prompt-support.md`, especially EP-51 through EP-55. It also depends on the local schema dependency `shinzui/seihou-schema`, found through `mori registry show shinzui/seihou-schema --full`.
