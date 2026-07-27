---
id: 73
slug: support-blueprint-declared-agent-provider-model-and-effort
title: "Support blueprint-declared agent provider, model, and effort"
kind: exec-plan
created_at: 2026-07-27T12:59:08Z
intention: "intention_01kyhtawwsenmtpjxd7sj1c8xc"
---

# Support blueprint-declared agent provider, model, and effort

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Seihou is a project-scaffolding tool. A **blueprint** is one of the things Seihou can run: a
directory containing a `blueprint.dhall` file (a typed configuration file written in the Dhall
configuration language) plus a Markdown prompt body and optional reference files. Running
`seihou agent run <blueprint>` resolves the blueprint's variables, renders its prompt, and hands
that prompt to an AI coding agent — either an interactive local CLI session (`claude` or `codex`)
or a one-shot API completion (Anthropic or OpenAI). Which agent gets used is decided by three
values: the **provider** (`claude-cli`, `codex-cli`, `anthropic`, `openai`), the **model**
(e.g. `claude-opus-4-8`), and the **reasoning effort** (a coarse dial telling a reasoning-capable
model how hard to think: `minimal`, `low`, `medium`, `high`, `xhigh`, `max`).

Today those three values come only from the user's side of the fence: command-line flags,
`SEIHOU_AGENT_*` environment variables, and the `agent.*` / `agent.<command>.*` keys in the
project-local and global config files. The blueprint author has no way to say "this blueprint
needs `max` effort" or "this blueprint is written for Codex". A blueprint that only works well
with a particular provider or that genuinely needs deep reasoning silently runs with whatever
the invoking user happens to have configured — usually the built-in default `claude-cli` with
`claude-opus-4-8` and no effort setting at all.

After this change, a blueprint author can declare those preferences **in the Dhall schema
itself**, and they take effect automatically for anyone who runs the blueprint:

```dhall
let S =
      https://raw.githubusercontent.com/shinzui/seihou-schema/<NEW-COMMIT>/package.dhall
        sha256:<NEW-HASH>

in  S.Blueprint::{
    , name = "payments-service"
    , prompt = ./prompt.md as Text
    , launch = Some S.Launch::{
      , provider = Some "claude-cli"
      , model = Some "claude-opus-4-8"
      , effort = Some "max"
      }
    }
```

The declared values sit in the middle of the existing precedence chain: they **override every
config-file tier** (both the project-local `.seihou/config.dhall` and the global
`~/.config/seihou/config.dhall`, per-command keys included), but they **lose to anything the
invoking user states for this one invocation** — a `--provider` / `--model` / `--effort` flag or a
`SEIHOU_AGENT_*` environment variable. So the blueprint author sets the sane default; the person
at the keyboard always keeps the last word.

The same declaration works for first-class prompt artifacts (`seihou prompt run`), whose schema
already has an (until now completely unused) `launch` record; this plan gives that field real
behavior and adds `effort` to it.

**The observable outcome.** Given a blueprint `deep-thinker` whose `blueprint.dhall` declares
`launch = Some S.Launch::{ model = Some "claude-sonnet-5", effort = Some "max" }`, with nothing
configured anywhere else:

```text
$ seihou agent run deep-thinker --verbose
[info]  Agent: provider claude-cli [built-in default], model claude-sonnet-5 [blueprint: launch.model], effort max [blueprint: launch.effort]
```

and the `claude` process Seihou spawns receives `--model claude-sonnet-5 --effort max` on its
argv (this is asserted end-to-end in a test that puts a fake `claude` script on `PATH` and reads
back the arguments it was called with). Adding a flag overrides the blueprint:

```text
$ seihou agent run deep-thinker --model claude-opus-4-8 --verbose
[info]  Agent: provider claude-cli [built-in default], model claude-opus-4-8 [flag on subcommand], effort max [blueprint: launch.effort]
```

and the spawned `claude` receives `--model claude-opus-4-8 --effort max`. A blueprint that
declares nonsense (`provider = Some "llama"`) is rejected by `seihou validate-blueprint` with an
actionable message and fails the run instead of silently falling back.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Researched the current provider/model/effort resolution chain, the blueprint and prompt
      Dhall schemas, the decoders, the CLI wiring, the validation surface, the docs surface, and
      the end-to-end test harness (2026-07-27).
- [x] Recorded the four scoping decisions (schema shape, precedence position, command scope,
      intention) in the Decision Log (2026-07-27).
- [x] Milestone 1 — Schema: add `schema/Launch.dhall`, wire it into `Blueprint.dhall` and
      `AgentPrompt.dhall`, export it from `package.dhall`, document it in `schema/README.md`,
      commit and push in the submodule, then bump the pin (`SchemaVersion.hs`, submodule pointer,
      `flake.lock`). Done 2026-07-27, commit `4ac515b`; schema commit
      `0e1b875efcf2b4e4b98d93595ea627290459e3ad`, hash
      `sha256:356829d4e2b333ce157615dd7eccd0cd4765f3ef0d94ef637fa8c97398d3b92c`. Verified the
      published pin resolves over HTTPS and `cabal test seihou-core` passes (1023 tests).
- [x] Milestone 2 — Core domain and decoder: `AgentLaunch` type, `Blueprint.launch` field,
      backward-compatible decoders, core validation rule, unit tests. Done 2026-07-27, commit
      `9a84885`. `cabal test all` green (seihou-core 1034 tests, up from 1023).
- [ ] Milestone 3 — Resolution: new declaration tier in `Seihou.CLI.AgentConfig`, deferred
      resolution API, provenance label, precedence unit tests.
- [ ] Milestone 4 — Wiring: `seihou agent run`, `seihou agent migrate`, and `seihou prompt run`
      resolve after loading the artifact; verbose provenance line; end-to-end argv test.
- [ ] Milestone 5 — Validation and scaffolding: `validate-blueprint` / `validate-prompt` checks,
      `seihou new-blueprint` template, `seihou agent config` precedence legend.
- [ ] Milestone 6 — Documentation and distillation: user and CLI docs, both changelogs, schema
      README, architecture note.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **Discovery (2026-07-27): there are two seihou-schema checkouts on this machine and the
  standalone one had drifted.** The canonical schema is the GitHub repository
  `shinzui/seihou-schema` on `master`; both local directories are working copies of it. The git
  submodule inside this repository at `schema/` was exactly at `origin/master` (`2dffa05`), the
  same commit pinned by `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`. The standalone clone at
  `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema` — the copy Mori's registry points
  at for dependency lookup — was 6 commits behind and 3 ahead, and did not contain `2dffa05` at
  all:

  ```text
  $ git -C /Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema status --branch --porcelain
  ## master...origin/master [ahead 3, behind 6]
   M Step.dhall
  ```

  The three "ahead" commits were two content-duplicates of upstream commits (same message, same
  day, different SHA and different `dhall format` output — the work was committed independently in
  both checkouts, and only the submodule's copy was pushed) plus one genuinely local
  `chore: add mori.dhall project config`. The standalone clone was resynced to `origin/master`
  with its `mori.dhall` commit cherry-picked back on top and its uncommitted `Step.dhall` comment
  preserved; nothing was lost. All schema edits in this plan happen in `schema/` (the submodule),
  never in the standalone clone.

- **Discovery (2026-07-27): the `update-seihou-schema` skill's flake step was out of date, and has
  been fixed.** `claude/skills/update-seihou-schema/SKILL.md` step 5 used to say "change the
  commit hash in the `seihou-schema-src` input URL", but `flake.nix` declares
  `seihou-schema-src = { url = "git+file:./schema"; flake = false; }` — it follows the submodule by
  path, so there is no commit hash to edit and only `flake.lock` needs refreshing. The skill has
  been rewritten to say so, to name the canonical repository and both checkouts, to require
  pushing inside the submodule before re-pinning, and to warn against rewriting a published pin.

- **Discovery (2026-07-27): existing prompt fixtures pin the old three-field `launch` record.**
  `seihou-core/test/Seihou/Core/AgentPromptSpec.hs:292`, `RegistrySpec.hs:872`,
  `seihou-cli/test/Seihou/CLI/Registry/ValidateSpec.hs:255`, and
  `seihou-cli/test/Seihou/CLI/Registry/SyncSpec.hs:253` all write
  `launch = Some { provider = ..., mode = ..., model = ... }` literally. Adding an `effort` field
  to the launch decoder without a default would break every one of them — and, worse, would break
  every real prompt authored against an older schema pin. The decoder must therefore default the
  new field (see Milestone 2).


## Decision Log

Record every decision made while working on the plan.

- Decision: the declaration lives in the Dhall schema itself — a new shared `Launch.dhall` record
  in the `seihou-schema` repository (this repo's `schema/` submodule), referenced by both
  `Blueprint.dhall` and `AgentPrompt.dhall` and exported from `package.dhall` as `S.Launch`.
  Rationale: the user asked explicitly for blueprints to declare provider/model/effort "in the
  dhall seihou schema directly". `AgentPrompt.dhall` already carried an inline three-field
  `Launch` record (`provider`, `mode`, `model`), so promoting it to a shared top-level file
  gives one concept, one definition, and one place to add `effort`, instead of two near-identical
  records drifting apart.
  Date: 2026-07-27

- Decision: the declared values sit below the CLI flags and the `SEIHOU_AGENT_*` environment
  variables and above every config-file tier. Full order, highest first: subcommand flag, parent
  `seihou agent` flag, environment variable, **blueprint/prompt declaration**, local
  `agent.<command>.*`, local `agent.*`, global `agent.<command>.*`, global `agent.*`, built-in
  default.
  Rationale: the user's requirement was that the declaration override the globally configured
  agent settings while a command-line argument still overrides the declaration. Environment
  variables are per-invocation overrides in the same spirit as a flag (CI pipelines set
  `SEIHOU_AGENT_PROVIDER` exactly to force a provider), so they stay above the declaration; the
  config files express standing preferences, which is precisely what a blueprint author's
  considered choice should be allowed to override.
  Date: 2026-07-27

- Decision: scope covers `seihou agent run`, `seihou agent migrate`, and `seihou prompt run`.
  Rationale: user selection. `agent migrate` loads the very same `Blueprint` record (for its
  `migrations` list), so ignoring the declaration there would make one command obey the blueprint
  and its sibling ignore it. `prompt run` already had the dormant `launch` field, so wiring it
  now costs one extra call site and removes a documented-but-inert field. `assist`, `bootstrap`,
  and `setup` are out of scope: they have no artifact to read a declaration from.
  Date: 2026-07-27

- Decision: keep the `mode` field on the shared `Launch` record even though nothing reads it, and
  document it as reserved.
  Rationale: `AgentPrompt.dhall` has shipped `mode` since the prompt schema landed; dropping it
  from the shared record would be a breaking schema change for any prompt that sets it. Blueprints
  inherit a field they do not use, which is a smaller cost than a breaking change plus a second
  record type.
  Date: 2026-07-27

- Decision: resolve the provider/model/effort **after** the artifact is loaded, by deferring
  resolution rather than by patching an already-resolved value.
  Rationale: `seihou-cli/src-exe/Main.hs` currently resolves the config *before* dispatching to a
  handler, but the declaration is only known after the handler discovers and decodes the
  blueprint. Patching after the fact would have to re-derive the per-provider default model
  whenever the declaration changes the provider (`applyProviderDefaultModel` in
  `seihou-cli/src/Seihou/CLI/AgentConfig.hs` pins `claude-cli → claude-opus-4-8` and
  `codex-cli → gpt-5.6-terra`), which is easy to get wrong. Deferring keeps a single resolution
  pass with one precedence list.
  Date: 2026-07-27

- Decision: validate the declared strings in the CLI layer, not in `seihou-core`.
  Rationale: the canonical provider and effort vocabularies live in
  `seihou-cli/src/Seihou/CLI/AgentCompletion.hs` (`providerFromText`, `effortFromText`), which
  depends on the `baikai` library. `seihou-core` does not depend on `baikai`
  (`seihou-core/seihou-core.cabal` build-depends has no `baikai`), so duplicating the vocabularies
  there would guarantee drift. `seihou-core` therefore only checks that a declared value is not
  blank; the CLI parses it.
  Date: 2026-07-27

- Decision: link the work to Intention `intention_01kyhtawwsenmtpjxd7sj1c8xc`, minted with
  `mina ci --json "Support blueprint-declared agent provider, model, and effort"`.
  Rationale: user instruction.
  Date: 2026-07-27


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

**No ADR corpus exists in this repository.** There is no `docs/adr/` directory, and `mori.dhall`
declares no OKF bundle whose path is `docs/adr` (its `docs` list contains only
`docs/dev/architecture/overview.md` and `docs/dev/roadmap/v1-milestones.md`). Per the plan
skill's ADR workflow, that means the repository's established convention is preserved as-is: do
**not** create `docs/adr/` or invent OKF frontmatter as an incidental edit of this plan. Durable
architectural context produced by this work belongs in
`docs/dev/architecture/overview.md`, which is the repository's existing home for such notes. If
an ADR corpus is adopted later, the note can be promoted then.

### The repository at a glance

This is a Haskell workspace (GHC, `cabal.project`) with two packages plus one extension package:

- `seihou-core/` — the library holding the domain types (`Seihou.Core.Types`), the Dhall decoders
  (`Seihou.Dhall.Eval`), validation (`Seihou.Core.Blueprint`, `Seihou.Core.AgentPrompt`), and the
  scaffolding templates (`Seihou.Core.Scaffold`).
- `seihou-cli/` — split into a library at `seihou-cli/src/` (module prefix `Seihou.CLI.*`) and an
  executable at `seihou-cli/src-exe/`. Per `CLAUDE.md` and
  `docs/dev/architecture/overview.md` ("CLI Module Placement Convention"), **new modules go in the
  library** unless they need `Options.Applicative`, `Data.FileEmbed`, `GitHash`,
  `Paths_seihou_cli`, or an import of a module already trapped in the executable. The convention is
  mechanically enforced by `nix/check-cli-module-placement.sh`, which runs in `nix flake check`
  and in the pre-commit hook. This plan adds **no new modules**, so the check is unaffected; the
  new library code goes into the existing `seihou-cli/src/Seihou/CLI/AgentConfig.hs`.
- `schema/` — a git submodule containing the `seihou-schema` Dhall schema (remote:
  `git@github.com:shinzui/seihou-schema.git`). This is where the authored schema lives.

Two commands matter for orientation:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
cabal build all      # or: just build
cabal test all       # or: just test
```

### Vocabulary used in this plan

- **Dhall** — a typed, programmable configuration language. A `blueprint.dhall` file evaluates to
  a record. The `::` operator is *record completion*: `S.Blueprint::{ name = "x" }` means "take
  the `Blueprint` schema's `default` record, override these fields, and check the result against
  the schema's `Type`". This is why adding a field with a default to the schema does not break
  existing authored files that use `::`.
- **Schema pin** — generated `blueprint.dhall` files import the schema by URL with an integrity
  hash, e.g. `https://raw.githubusercontent.com/shinzui/seihou-schema/<commit>/package.dhall
  sha256:<hash>`. The URL and hash Seihou emits live in
  `seihou-cli/src/Seihou/CLI/SchemaVersion.hs` (currently commit
  `2dffa0592be47835a60784b89a289226ba990aa8`, hash
  `sha256:01b6f873520459f3958baa34d3f97a49a4263b9a7225a758cddca5ab3a911f61`).
- **Decoder** — a `Dhall.Decoder a` value in `seihou-core/src/Seihou/Dhall/Eval.hs` describing how
  to turn an evaluated Dhall record into a Haskell value. `record (Ctor <$> field "a" ... <*> ...)`
  looks fields up by name, so Dhall field order is irrelevant, but the order of `<*>` must match
  the Haskell constructor's positional field order.
- **`withDefaults`** — a helper defined at `seihou-core/src/Seihou/Dhall/Eval.hs:153`. It wraps a
  decoder and injects a default expression for any field missing from the evaluated record. This
  is how Seihou stays compatible with files authored against older schema pins: `moduleDecoder`
  uses it for `removal` and `migrations`, `blueprintDecoder` for `migrations`. The placeholder
  `noneText` (`None Text`, line 168) is reused even for record-typed `Optional` fields, because
  the `maybe` decoder only inspects whether the value is `None` or `Some` and ignores the type
  annotation.
- **Provider / model / reasoning effort** — see Purpose. Reasoning effort maps to
  `Baikai.ThinkingLevel` (`ThinkingMinimal`, `ThinkingLow`, `ThinkingMedium`, `ThinkingHigh`,
  `ThinkingXHigh`, `ThinkingMax`) from the external `baikai` library, which is also what actually
  spawns `claude` / `codex` or performs an API completion.
- **Provenance** — the label Seihou attaches to a resolved value naming where it came from, e.g.
  `[local: agent.run.model]`. Printed by `seihou agent config`.

### How provider/model/effort resolution works today

The resolver is `seihou-cli/src/Seihou/CLI/AgentConfig.hs`. Its input record is:

```haskell
data AgentConfigInputs = AgentConfigInputs
  { cliProvider :: Maybe Text,
    cliModel :: Maybe Text,
    cliEffort :: Maybe Text,
    cliProviderFromSubcommand :: Bool,
    cliModelFromSubcommand :: Bool,
    cliEffortFromSubcommand :: Bool,
    envProvider :: Maybe Text,
    envModel :: Maybe Text,
    envEffort :: Maybe Text,
    localConfig :: Map Text Text,
    globalConfig :: Map Text Text
  }
```

`gatherAgentConfigInputs` (private, same file) fills it by reading `SEIHOU_AGENT_PROVIDER`,
`SEIHOU_AGENT_MODEL`, `SEIHOU_AGENT_EFFORT` and the local + global config maps.
`resolveAgentModelConfigFor :: AgentCommandName -> AgentConfigInputs -> Either Text (…)` then
picks a winner per field from an ordered candidate list — `providerCandidates`,
`modelCandidates`, `effortCandidates` — using `firstNonBlankWithSource` (leftmost present,
non-blank value wins; whitespace-only counts as absent). Each winner is returned as a
`ResolvedAgentField a = ResolvedAgentField { resolvedValue :: a, resolvedSource :: AgentConfigSource }`,
and `AgentConfigSource` is the provenance enum (`SourceCliSubcommand`, `SourceCliParent`,
`SourceEnv`, `SourceLocalCommand`, `SourceLocalDefault`, `SourceGlobalCommand`,
`SourceGlobalDefault`, `SourceBuiltinDefault`). `agentConfigSourceLabel` turns a source into the
bracketed display label. When no model is configured at all, `applyProviderDefaultModel`
substitutes the provider's pinned default (`claude-cli → claude-opus-4-8`,
`codex-cli → gpt-5.6-terra`) while leaving the source as `SourceBuiltinDefault`.

`loadAgentModelConfigFor` combines the IO gathering with the pure resolution and projects the
result into `AgentModelConfig` (from `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`):

```haskell
data AgentModelConfig = AgentModelConfig
  { agentProvider :: AgentProvider,     -- AgentProviderClaudeCli | …CodexCli | …Anthropic | …OpenAI
    agentModel :: Maybe Text,
    agentEffort :: Maybe ThinkingLevel
  }
```

`seihou-cli/src-exe/Main.hs` resolves **eagerly, before dispatch**. Its local helper
`resolveAgentModelConfigFor` (Main.hs:187) combines the subcommand flag with the parent
`seihou agent` flag (`commandProvider <|> parentProvider`), calls `loadAgentModelConfigFor`,
prints `Error: …` and exits on `Left`, and hands a finished `AgentModelConfig` to the handler:

```haskell
AgentRun blueprintRunOpts -> do
  modelConfig <- resolveAgentModelConfigFor AgentCmdRun agentOpts.agentProvider … 
  handleAgentRun agentOpts.agentDebug modelConfig blueprintRunOpts
```

That eager ordering is the crux of this plan: the blueprint is not loaded until
`handleAgentRun` runs `discoverRunnable`, so the declaration cannot participate in a resolution
that already finished.

`seihou-cli/src/Seihou/CLI/AgentConfigShow.hs` renders `seihou agent config`: a table of every
command's resolved provider/model/effort with provenance labels, followed by `precedenceLegend`
(line 93), a numbered list of the eight tiers.

### The artifacts and their current schemas

`schema/Blueprint.dhall` declares `name`, `version`, `description`, `prompt`, `vars`, `prompts`,
`baseModules`, `files`, `allowedTools`, `tags`, `migrations` — and no launch metadata.
`schema/AgentPrompt.dhall` declares an inline

```dhall
let Launch =
      { Type = { provider : Optional Text, mode : Optional Text, model : Optional Text }
      , default = { provider = None Text, mode = None Text, model = None Text }
      }
```

and a field `launch : Optional Launch.Type`. On the Haskell side that decodes into
`Seihou.Core.Types.AgentPromptLaunch { provider, mode, model :: Maybe Text }` whose doc comment
already anticipates this work ("The CLI runner may use this as a default provider/model/mode
hint"), but **nothing reads it**: a repository-wide grep for `.launch` finds only the type
definition, the decoder, and test fixtures.

Both artifacts are decoded in `seihou-core/src/Seihou/Dhall/Eval.hs`: `blueprintDecoder`
(line 279) and `agentPromptDecoder` (~line 380, with `agentPromptLaunchDecoder` at line 348).
Validation lives in `seihou-core/src/Seihou/Core/Blueprint.hs` (ten numbered rules; each rule is
an exported `checkBlueprint*` function, aggregated by `validateBlueprintWith`) and
`seihou-core/src/Seihou/Core/AgentPrompt.hs` (same shape). The CLI commands
`seihou validate-blueprint` and `seihou validate-prompt` live in
`seihou-cli/src-exe/Seihou/CLI/ValidateBlueprint.hs` and `.../ValidatePrompt.hs`; they call the
individual check functions and render each as a `DiagCheck` line.

### The three consumers in scope

- `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` — `handleAgentRun :: Bool -> AgentModelConfig ->
  BlueprintRunOpts -> IO ()`. Step (a) discovers the blueprint with `discoverRunnable`, step (b)
  prepares variables via `prepareBlueprintExecution`, step (c) optionally applies `baseModules`,
  step (d) renders the system prompt, step (f) launches. Note that `modelConfig.agentProvider` is
  consulted **before** the blueprint is available, at line 124, to decide
  `providerCanMountFiles` (only the two CLI providers can mount the blueprint's `files/`
  directory) — so the resolution must happen after discovery but before that flag is computed.
- `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs` — `handleAgentMigrate`, which discovers the same
  `Blueprint` via `discoverMigrationBlueprint`, then runs one agent session per declared migration
  edge. It also computes `providerCanMountFiles` from the provider, inside `prepare`.
- `seihou-cli/src-exe/Seihou/CLI/PromptRun.hs` — `handlePromptRun :: AgentModelConfig ->
  PromptRunOpts -> IO ()`, which discovers a `RunnableAgentPrompt`, validates it, resolves
  variables and command variables, renders, and launches through
  `Seihou.CLI.AgentRun.runRenderedAgentPrompt`.

The actual process spawn is `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs`
(`launchConfiguredAgentAddingDirs` → `launchClaude` / `launchCodex`, passing
`modelConfig.agentModel` and `modelConfig.agentEffort` to Baikai), and the API path is
`runAgentCompletionWithCliAccess` in `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`.

### Logging

`logIO :: LogLevel -> Eff '[Logger, IOE] () -> IO ()` (`seihou-cli/src/Seihou/CLI/Shared.hs:65`)
runs the logger at a level. Per `seihou-core/src/Seihou/Effect/LoggerInterp.hs`, `logInfo` and
`logDebug` are emitted **only** at `LogVerbose`, `logWarn` from `LogNormal`, `logError` always;
all output goes to **stderr** prefixed with `[info]  `, `[warn]  `, `[error] `. The runners set
`level = if opts.runBlueprintVerbose then LogVerbose else LogNormal`, i.e. `--verbose` turns on
`logInfo`. That is how the provenance line in the Purpose section is printed without disturbing
normal output.

### Test infrastructure

- Unit tests: `seihou-core/test/` and `seihou-cli/test/`, both `tasty` + `tasty-hspec`. Every spec
  module exports `tests :: IO TestTree` and must be registered in the package's `test/Main.hs`
  (import + entry in the `sequence [...]` list) **and** in the `.cabal` file's
  `other-modules`.
- Decoder fixtures are plain inline Dhall records with **no** schema import (see
  `seihou-core/test/fixtures/sample-blueprint/blueprint.dhall` and the `sampleBlueprintDhall`
  helper in `seihou-core/test/Seihou/Core/BlueprintSpec.hs`). Because they bypass record
  completion, they must list every field the decoder requires — which is exactly why new fields
  need `withDefaults`.
- `seihou-core/test/Seihou/Core/ScaffoldSpec.hs` decodes the output of
  `Seihou.Core.Scaffold.blueprintDhall` using a **local** schema path from `resolveSchemaPath`
  (the `schema/` submodule), not the pinned URL, so it exercises the freshly edited schema and
  needs no network.
- End-to-end tests: `seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs` shows the pattern this
  plan reuses. It writes a blueprint into a temp directory, writes a fake `claude` shell script
  that dumps `"$@"` into `$SEIHOU_FAKE_AGENT_LOG` and prints a JSON result, puts it first on
  `PATH`, sets `XDG_CONFIG_HOME` to an empty temp dir (so no real user config leaks in), scrubs
  `SEIHOU_AGENT_*` from the inherited environment, runs the real `seihou` binary via
  `runProcessText`, and asserts on the recorded argv. This is the mechanism that proves the model
  and effort actually reach the agent process.

### Documentation surface

`docs/user/blueprints.md` (§"The blueprint.dhall format" has an example plus a field-reference
table), `docs/user/prompts.md` (same, line 85 shows the old three-field `launch` literal and
line 104 its table row), `docs/cli/agent.md`, `docs/cli/prompt.md`,
`docs/cli/validate-blueprint.md`, `docs/user/config-and-variables.md` (§"Agent provider defaults",
which lists the numbered precedence chain at lines 157–163), `docs/user/agent-assistance.md`,
`schema/README.md`, and the two changelogs: `docs/user/CHANGELOG.md` (curated, user-facing, with
an `## Unreleased` section) and `CHANGELOG.md` at the repository root (engineering).


## Plan of Work

The work splits into six milestones that each leave the tree building and the suite green. The
order is forced by data flow: the schema must exist before the decoder can read it, the decoder
before the resolver has anything to resolve, the resolver before the commands can be wired, and
the behavior before it can be validated and documented.

### Milestone 1 — Extend the Dhall schema and re-pin it

Scope: the `schema/` submodule plus this repository's pin. At the end of this milestone the
schema defines a shared launch record, both artifact schemas reference it, `seihou`'s emitted
pin points at the new commit, and `nix` builds see the same revision. No Haskell behavior changes
yet, but `S.Launch` is authorable and type-checks.

Add `schema/Launch.dhall`, following the file conventions of its siblings (a leading `-- |`
comment block explaining the record and its usage, then a record with `Type` and `default`):

```dhall
-- | Seihou Agent Launch Settings
--
-- Optional launch preferences an agent-driven artifact (a Blueprint or an
-- AgentPrompt) can declare for the agent session it starts. Every field is
-- optional; an omitted field means "let the invoking user's configuration
-- decide".
--
-- Declared values override the user's configuration files (project-local and
-- global `agent.*` keys) but lose to a `--provider` / `--model` / `--effort`
-- flag and to the SEIHOU_AGENT_* environment variables.
--
-- provider : claude-cli | codex-cli | anthropic | openai
-- model    : any provider-specific model name or alias
-- effort   : minimal | low | medium | high | xhigh | max
-- mode     : reserved; currently ignored by the runner
--
-- Usage:
--   let S = ./package.dhall
--   in S.Blueprint::{ name = "payments-service"
--                   , prompt = ./prompt.md as Text
--                   , launch = Some S.Launch::{ effort = Some "max" }
--                   }
{ Type =
    { provider : Optional Text
    , model : Optional Text
    , effort : Optional Text
    , mode : Optional Text
    }
, default =
  { provider = None Text
  , model = None Text
  , effort = None Text
  , mode = None Text
  }
}
```

In `schema/Blueprint.dhall`, add `let Launch = ./Launch.dhall` beside the other imports, add
`, launch : Optional Launch.Type` to `Type` (after `migrations`, to match the Haskell field order
chosen in Milestone 2), add `, launch = None Launch.Type` to `default`, and extend the trailing
re-export list with `, Launch = Launch` so `S.Blueprint.Launch` also resolves. Mention the field
in the file's header comment.

In `schema/AgentPrompt.dhall`, delete the inline `Launch` definition and replace it with
`let Launch = ./Launch.dhall`. Keep the `, Launch` re-export in the returned record so existing
`S.AgentPrompt.Launch` references keep working. The record now gains `effort` and keeps `mode`.

In `schema/package.dhall`, add `, Launch = ./Launch.dhall` (place it next to `PromptGuidance`,
i.e. after the artifact entries, or in the primitive block — either is fine as long as the file
stays alphabetically-agnostic like today).

In `schema/README.md`, add `Launch` to the type list (around line 29–32) and add a short
"Declaring launch settings" section showing the blueprint example above.

Then commit **inside the submodule** and push, because the pin resolves over HTTPS from
`raw.githubusercontent.com` and an unpushed commit cannot be fetched. Afterwards, in the parent
repository: stage the moved submodule pointer, recompute the integrity hash with
`dhall hash < schema/package.dhall`, update both `schemaUrl` (new commit) and `schemaHash` in
`seihou-cli/src/Seihou/CLI/SchemaVersion.hs`, and refresh `flake.lock` (the `seihou-schema-src`
input is `git+file:./schema`, so only the lock changes — no URL edit). The
`claude/skills/update-seihou-schema` skill now documents exactly this sequence and can be followed
verbatim.

Acceptance: `dhall type --file schema/package.dhall` succeeds; a scratch blueprint using
`S.Launch::{ effort = Some "max" }` type-checks against the local schema;
`dhall hash < schema/package.dhall` prints exactly the hash now recorded in `SchemaVersion.hs`;
`cabal test seihou-core` still passes (`ScaffoldSpec` decodes generated blueprints against the
local schema).

### Milestone 2 — Domain type, decoders, and core validation

Scope: `seihou-core`. At the end of this milestone a decoded `Blueprint` carries the declaration,
old files still decode, and `validateBlueprint` / `validateAgentPrompt` reject blank declared
values. Nothing changes about which agent runs yet.

In `seihou-core/src/Seihou/Core/Types.hs`, rename `AgentPromptLaunch` to `AgentLaunch` (the record
is no longer prompt-specific) and add the `effort` field:

```haskell
-- | Optional launch preferences declared by an agent-driven artifact (a
-- 'Blueprint' or an 'AgentPrompt'). Values are raw text here; the CLI parses
-- and validates them, because the provider and effort vocabularies live in the
-- CLI layer. 'mode' is reserved and currently ignored.
data AgentLaunch = AgentLaunch
  { provider :: Maybe Text,
    model :: Maybe Text,
    effort :: Maybe Text,
    mode :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)
```

Update the module's export list (`AgentLaunch (..)` in place of `AgentPromptLaunch (..)`), change
`AgentPrompt.launch` to `Maybe AgentLaunch`, and add `launch :: Maybe AgentLaunch` as the **last**
field of `Blueprint` (after `migrations`).

In `seihou-core/src/Seihou/Dhall/Eval.hs`, rename `agentPromptLaunchDecoder` to
`agentLaunchDecoder`, give it the new field, and default the two fields that older authored files
may lack:

```haskell
-- | Decoder for the shared launch record. @effort@ and @mode@ are defaulted so
-- artifacts authored against a schema pin that predates them still decode.
agentLaunchDecoder :: Decoder AgentLaunch
agentLaunchDecoder =
  withDefaults [("effort", noneText), ("mode", noneText)] $
    record
      ( AgentLaunch
          <$> field "provider" (maybe strictText)
          <*> field "model" (maybe strictText)
          <*> field "effort" (maybe strictText)
          <*> field "mode" (maybe strictText)
      )
```

Extend `blueprintDecoder`: add `("launch", noneText)` to its `withDefaults` list and
`<*> field "launch" (maybe agentLaunchDecoder)` as the final applicative step. Update
`agentPromptDecoder`'s `launch` field to use the renamed decoder, and export
`agentLaunchDecoder` in place of `agentPromptLaunchDecoder`.

In `seihou-core/src/Seihou/Core/Blueprint.hs`, add rule 11 as an exported
`checkBlueprintLaunch :: Blueprint -> [Text]` that reports one message per blank-but-present
field, e.g. `"launch.provider, if specified, must not be empty"`, and add it to the `pureErrs`
chain in `validateBlueprintWith` plus the numbered rule list in the module's doc comment. Add the
mirror-image `checkAgentPromptLaunch` to `seihou-core/src/Seihou/Core/AgentPrompt.hs` and its
`validateAgentPrompt` chain. Factor the per-field blank check into a small shared local helper in
each module rather than exporting a cross-module utility; these are three-line functions.

Tests, in `seihou-core/test/Seihou/Core/BlueprintSpec.hs`: extend the inline `sampleBlueprintDhall`
helper with a full four-field `launch = Some { provider = …, model = …, effort = …, mode = … }`
literal and assert the decoded values; add a case asserting that a blueprint **without** a
`launch` field still decodes with `launch == Nothing` (this is the `withDefaults` regression
test); add cases for `checkBlueprintLaunch`. In
`seihou-core/test/Seihou/Core/AgentPromptSpec.hs`, keep the existing three-field fixture at line
292 exactly as it is — it is now the regression test proving `effort` defaults — and add one new
fixture that sets `effort`.

Acceptance: `cabal test seihou-core` passes, including the untouched old-shape fixtures in
`AgentPromptSpec` and `RegistrySpec`.

### Milestone 3 — A declaration tier in the resolver

Scope: `seihou-cli/src/Seihou/CLI/AgentConfig.hs` and its spec. At the end of this milestone the
resolver understands a fourth-highest tier and can be driven in two phases (gather now, resolve
later), with unit tests pinning the precedence. No command uses it yet.

Add the three declared inputs to `AgentConfigInputs` (`declaredProvider`, `declaredModel`,
`declaredEffort :: Maybe Text`) and to `baseAgentConfigInputs`. Add the provenance constructor
`SourceArtifactDeclaration` to `AgentConfigSource`, positioned between `SourceEnv` and
`SourceLocalCommand` so the declaration order keeps documenting precedence. Insert the new
candidate into all three candidate lists directly after the env candidate:

```haskell
providerCandidates c inputs =
  [ candidate inputs.cliProvider (cliSource inputs.cliProviderFromSubcommand),
    candidate inputs.envProvider SourceEnv,
    candidate inputs.declaredProvider SourceArtifactDeclaration,
    candidate (Map.lookup (agentCommandProviderConfigKey c) inputs.localConfig) SourceLocalCommand,
    …
  ]
```

Teach `agentConfigSourceLabel` to render it, keyed on the command so the label names the artifact
kind the user actually ran:

```haskell
SourceArtifactDeclaration -> declarationLabel c <> ": launch." <> fieldKeyName field
  where
    declarationLabel AgentCmdPromptRun = "prompt"
    declarationLabel _ = "blueprint"
    fieldKeyName ProviderField = "provider"   -- "model", "effort"
```

so labels read `[blueprint: launch.effort]` and `[prompt: launch.model]`.

Add the declaration carrier and the two-phase API. `AgentLaunchDeclaration` deliberately mirrors
only the three fields the resolver understands, so `mode` stays out of the resolution path:

```haskell
data AgentLaunchDeclaration = AgentLaunchDeclaration
  { declarationProvider :: Maybe Text,
    declarationModel :: Maybe Text,
    declarationEffort :: Maybe Text
  }
  deriving stock (Eq, Show)

noAgentLaunchDeclaration :: AgentLaunchDeclaration

-- | Project a decoded artifact's launch record into the resolver's declaration
-- tier. 'mode' is intentionally dropped: it is reserved and unused.
agentLaunchDeclaration :: Maybe AgentLaunch -> AgentLaunchDeclaration

-- | Everything needed to finish resolution later: the command identity plus the
-- flags, environment, and config already gathered. Handlers hold one of these
-- while they load their artifact.
data PendingAgentConfig = PendingAgentConfig
  { pendingCommand :: AgentCommandName,
    pendingInputs :: AgentConfigInputs
  }
  deriving stock (Eq, Show)

loadPendingAgentConfig ::
  AgentCommandName ->
  Maybe Text -> Maybe Text -> Maybe Text ->   -- winning provider/model/effort flags
  Bool -> Bool -> Bool ->                     -- did each flag come from the subcommand?
  IO (Either Text PendingAgentConfig)

resolvePendingAgentConfig ::
  PendingAgentConfig -> AgentLaunchDeclaration -> Either Text ResolvedCommandConfig

resolvedAgentModelConfig :: ResolvedCommandConfig -> AgentModelConfig

-- | Bracketed provenance summary for a verbose log line, e.g.
-- "provider claude-cli [built-in default], model x [blueprint: launch.model], effort max [blueprint: launch.effort]"
formatResolvedAgentProvenance :: ResolvedCommandConfig -> Text
```

`loadPendingAgentConfig` reuses the existing private `gatherAgentConfigInputs`.
`resolvePendingAgentConfig` writes the declaration into the inputs and calls the existing
`resolveAgentModelConfigFor`, returning the provenance-carrying `ResolvedCommandConfig` so callers
get both the effective config and the labels. Keep `loadAgentModelConfig`,
`loadAgentModelConfigFor`, and `loadResolvedAgentConfig` working exactly as before by passing
`noAgentLaunchDeclaration` internally — `seihou agent assist`, `bootstrap`, `setup`, and
`seihou agent config` must not change behavior.

Also add the validation helper the two `validate-*` commands will use in Milestone 5, here in the
CLI library where the vocabularies live:

```haskell
-- | Parse-check a declared launch record, returning one message per invalid
-- value. An empty list means the declaration is usable.
validateAgentLaunchDeclaration :: AgentLaunchDeclaration -> [Text]
```

It runs `providerFromText` on the declared provider and `effortFromText` on the declared effort
and prefixes each error with the offending key, e.g.
`"launch.provider: Unknown agent provider 'llama'. Expected one of: claude-cli, codex-cli, anthropic, openai."`.
It does not check the model, which is free-form by design (`docs/cli/agent.md` states aliases and
custom IDs stay accepted).

Tests in `seihou-cli/test/Seihou/CLI/AgentConfigSpec.hs`, following the existing style: a
declaration beats local per-command config; a declaration beats local and global defaults; a
subcommand flag beats a declaration; a parent flag beats a declaration; an env var beats a
declaration; a blank declared value is skipped in favor of the next tier; a declaration that
changes only the provider still picks up that provider's pinned default model (guarding the
`applyProviderDefaultModel` interaction — declaring `provider = Some "codex-cli"` with no model
must resolve to `gpt-5.6-terra`, not `claude-opus-4-8`); an invalid declared provider or effort
returns `Left` with a message naming the accepted values; and the provenance label for each field
reads `blueprint: launch.<field>` for `AgentCmdRun` / `AgentCmdMigrate` and `prompt: launch.<field>`
for `AgentCmdPromptRun`.

Acceptance: `cabal test seihou-cli` passes, including the untouched
`AgentConfigShowSpec` (behavior for the flat and per-command resolvers is unchanged).

### Milestone 4 — Wire the three commands

Scope: `seihou-cli/src-exe/Main.hs`, `AgentRun.hs`, `AgentMigrate.hs`, `PromptRun.hs`, plus an
end-to-end test. At the end of this milestone the declaration actually changes which agent runs,
and that is provable from the spawned process's argv.

In `Main.hs`, add a helper mirroring the existing `resolveAgentModelConfigFor` but stopping one
step earlier:

```haskell
-- | Gather flags, environment, and config for a command whose artifact may
-- declare its own launch settings. Resolution finishes inside the handler, once
-- the artifact is loaded.
pendingAgentConfigFor ::
  AgentCommandName ->
  Maybe Text -> Maybe Text -> Maybe Text ->   -- parent flags
  Maybe Text -> Maybe Text -> Maybe Text ->   -- subcommand flags
  IO PendingAgentConfig
```

It applies the same `commandFlag <|> parentFlag` combination and the same "print `Error: …` and
exit 1 on `Left`" behavior as the existing helper. Change the `AgentRun`, `AgentMigrate`, and
`PromptRun` dispatch arms to build a `PendingAgentConfig` and pass it to the handler; leave
`AgentAssist`, `AgentBootstrap`, `AgentSetup`, `AgentModels`, and `AgentConfigShow` untouched.

In `AgentRun.hs`, change the signature to
`handleAgentRun :: Bool -> PendingAgentConfig -> BlueprintRunOpts -> IO ()` and resolve
immediately after the blueprint is discovered — **before** the `providerCanMountFiles` computation
at the current line 124, since that depends on the final provider:

```haskell
modelConfig <- resolveArtifactAgentConfig level pending bp
```

where the shared step is factored into one helper (put it in the CLI **library**, in
`Seihou.CLI.AgentConfig`, so all three executable modules can use it without duplicating the
error text):

```haskell
-- | Finish resolution with the artifact's declaration, logging the resolved
-- provenance at verbose level and exiting with an actionable message when the
-- artifact declares an unusable value.
resolveDeclaredAgentConfig ::
  LogLevel ->
  -- | how to name the artifact in error messages, e.g. "blueprint 'payments'"
  Text ->
  PendingAgentConfig ->
  AgentLaunchDeclaration ->
  IO AgentModelConfig
```

On `Left err` it emits
`logError ("Invalid agent settings for " <> label <> ": " <> err)` and exits 1; on success it
emits `logInfo ("Agent: " <> formatResolvedAgentProvenance resolved)` (verbose only, stderr) and
returns the `AgentModelConfig`. Because it needs `LogLevel` and `logIO` it imports
`Seihou.CLI.Shared`, which `AgentConfig` already does.

Apply the same two-line change in `AgentMigrate.hs` (right after `discoverMigrationBlueprint`,
before `prepare`) and `PromptRun.hs` (right after `validateAgentPrompt` succeeds, so an invalid
declaration is reported alongside other prompt errors). In each case the declaration comes from
`agentLaunchDeclaration artifact.launch`.

The end-to-end proof goes in `seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs`, which already
owns the fake-`claude` harness and already contains a `seihou agent run` case ("automatically uses
the batch CLI provider when stdin is not a terminal"). Add two cases modeled on it:

1. A blueprint declaring `launch = Some { provider = None Text, model = Some "claude-sonnet-5",
   effort = Some "max", mode = None Text }`, run with `seihou agent run` and no flags and with
   `SEIHOU_AGENT_*` scrubbed from the environment, must produce a recorded argv containing
   `--model`, `claude-sonnet-5`, `--effort`, and `max`.
2. The same blueprint run as `seihou agent run <name> --model claude-opus-4-8` must record
   `claude-opus-4-8` and must **not** record `claude-sonnet-5`, while still recording
   `--effort` / `max` — proving the flag overrides only the field it names.

Note that the fake `claude` script in that spec must keep printing its JSON line
(`{"result":…,"is_error":false,…}`) because the batch path parses it. Keep asserting on
`T.lines <$> TIO.readFile launchLog` exactly as the existing case does. If the argv assertions
turn out to need a provider-specific flag spelling, read what Baikai emits from the recorded log
in a scratch run first and assert on that rather than guessing.

Acceptance: `cabal test seihou-cli` passes with the two new end-to-end cases; a manual run of the
transcripts in Validation and Acceptance reproduces the `[info]` provenance lines.

### Milestone 5 — Validation, scaffolding, and the precedence legend

Scope: the two `validate-*` commands, the `new-blueprint` template, and
`seihou agent config`'s legend. At the end of this milestone a typo in a declaration is caught
before a run, a freshly scaffolded blueprint shows authors the field exists, and the legend
matches reality.

In `seihou-cli/src-exe/Seihou/CLI/ValidateBlueprint.hs`, add a `DiagCheck` row for the launch
declaration that combines the core blank check (`checkBlueprintLaunch`) with the CLI parse check
(`validateAgentLaunchDeclaration . agentLaunchDeclaration $ bp.launch`), reported at the same
severity as the existing structural checks so an invalid value fails the command's exit code.
Mirror it in `seihou-cli/src-exe/Seihou/CLI/ValidatePrompt.hs`.

In `seihou-core/src/Seihou/Core/Scaffold.hs`, extend `blueprintDhall` with a commented-out
`launch` line so authors discover the field without changing the generated blueprint's behavior:

```haskell
"    -- , launch = Some S.Launch::{ effort = Some \"max\" }",
```

Update the corresponding assertions in `seihou-core/test/Seihou/Core/ScaffoldSpec.hs` (the
generated file must still decode and validate, and the structural assertions must still hold —
`launch` stays `Nothing` because the line is a comment).

In `seihou-cli/src/Seihou/CLI/AgentConfigShow.hs`, insert the new tier into `precedenceLegend`
as item 4 and renumber the rest:

```text
  3. SEIHOU_AGENT_PROVIDER / SEIHOU_AGENT_MODEL / SEIHOU_AGENT_EFFORT environment variables
  4. blueprint.dhall / prompt.dhall  launch.{provider,model,effort}
  5. local  .seihou/config.dhall          agent.<command>.{provider,model,effort}
  …
```

and add a sentence noting that the declaration tier is per-artifact, so `seihou agent config`
cannot show it (there is no blueprint in scope when the command runs). Update
`seihou-cli/test/Seihou/CLI/AgentConfigShowSpec.hs` if it asserts on legend text.

Acceptance: `seihou validate-blueprint` on a blueprint declaring `provider = Some "llama"` exits
non-zero and names the accepted providers; `seihou agent config` prints the nine-tier legend;
`cabal test all` passes.

### Milestone 6 — Documentation and distillation

Scope: docs only, plus the distillation pass required before the plan is complete.

Update `docs/user/blueprints.md`: add `launch` to the `blueprint.dhall` example and to the field
reference table, and add a "Launch settings" section explaining the three fields, the precedence
rule (in the same words as the schema comment), and that `mode` is reserved. Update
`docs/user/prompts.md`: rewrite the line-85 literal to use `S.Launch::{…}`, add `effort` to the
table row, and state that the field is now honored (it previously was not). Update
`docs/cli/agent.md` and `docs/cli/prompt.md` to mention that a blueprint or prompt can declare
defaults which flags and environment variables still override, and
`docs/cli/validate-blueprint.md` with the new check. Update the numbered precedence list in
`docs/user/config-and-variables.md` §"Agent provider defaults" (lines 157–163) to include the new
tier, and cross-reference it from `docs/user/agent-assistance.md`. Add an `## Unreleased` →
`### Added` entry to `docs/user/CHANGELOG.md` in the established voice, and an entry to the root
`CHANGELOG.md`.

Then perform the distillation pass. The repository has no ADR corpus (see Context and
Orientation), so record the durable part — that agent launch settings resolve through a single
ordered chain in `Seihou.CLI.AgentConfig`, that the artifact-declaration tier sits between the
environment and the config files, and that artifact-declared vocabularies are parsed in the CLI
layer because `seihou-core` cannot depend on `baikai` — as a short subsection of
`docs/dev/architecture/overview.md`. Do not create `docs/adr/` for this plan.

Acceptance: `rg -n "launch" docs/user/blueprints.md docs/user/prompts.md docs/cli/agent.md`
shows the new prose; the changelog entries exist; `nix flake check` passes (it runs the docs and
module-placement checks along with the test suites).


## Concrete Steps

All commands run from the repository root unless stated otherwise:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
```

### Milestone 1

Edit the schema inside the submodule, then verify it type-checks and that a blueprint can use the
new field:

```bash
# 1. Edit: schema/Launch.dhall (new), schema/Blueprint.dhall,
#    schema/AgentPrompt.dhall, schema/package.dhall, schema/README.md

dhall type --file schema/package.dhall > /dev/null && echo "package.dhall type-checks"

cat > /tmp/launch-probe.dhall <<'EOF'
let S = ./schema/package.dhall

in  S.Blueprint::{
    , name = "probe"
    , prompt = "body"
    , launch = Some S.Launch::{ provider = Some "claude-cli", effort = Some "max" }
    }
EOF
dhall type --file /tmp/launch-probe.dhall
```

Expected: the second command prints the blueprint's record type, including
`launch : Optional { provider : Optional Text, model : Optional Text, effort : Optional Text, mode : Optional Text }`.

Commit and push in the submodule (Conventional Commits, and note that the submodule is a separate
repository, so its commit does **not** carry this plan's trailers):

```bash
git -C schema add Launch.dhall Blueprint.dhall AgentPrompt.dhall package.dhall README.md
git -C schema commit -m "feat(schema): add shared Launch record with effort"
git -C schema push origin master
git -C schema rev-parse HEAD          # note the new commit hash
dhall hash < schema/package.dhall     # note the new sha256: line
```

Update `seihou-cli/src/Seihou/CLI/SchemaVersion.hs` with the new commit in `schemaUrl` and the new
hash in `schemaHash`, refresh the lock, and check the build:

```bash
nix flake lock --update-input seihou-schema-src   # or: nix flake update seihou-schema-src
cabal build all && cabal test seihou-core
git add schema seihou-cli/src/Seihou/CLI/SchemaVersion.hs flake.lock
git commit   # message body below
```

```text
feat(schema): add shared Launch record for artifact-declared agent settings

Add schema/Launch.dhall with provider, model, effort, and mode; reference it
from Blueprint.dhall and AgentPrompt.dhall; export it as S.Launch. Bump the
schema submodule pointer, the emitted pin in SchemaVersion.hs, and flake.lock.

ExecPlan: docs/plans/73-support-blueprint-declared-agent-provider-model-and-effort.md
Intention: intention_01kyhtawwsenmtpjxd7sj1c8xc
```

### Milestones 2–6

Each milestone ends with the same verification pair and a commit carrying both trailers:

```bash
cabal build all
cabal test all
```

Expected tail of a green run:

```text
All 34 tests passed
```

(the exact count grows as this plan adds specs; what matters is that no test fails and no suite is
skipped).

Commit message shapes, one per milestone:

```text
feat(core): decode artifact-declared agent launch settings
feat(cli): resolve blueprint-declared provider, model, and effort
feat(cli): honor launch declarations in agent run, agent migrate, and prompt run
feat(cli): validate launch declarations and show the new precedence tier
docs(user): document blueprint- and prompt-declared launch settings
```

each with the two trailers:

```text
ExecPlan: docs/plans/73-support-blueprint-declared-agent-provider-model-and-effort.md
Intention: intention_01kyhtawwsenmtpjxd7sj1c8xc
```

Before the final commit, run the full gate:

```bash
nix flake check
```

Expected: no failures. It runs the test suites, the formatting check, and
`nix/check-cli-module-placement.sh`. This plan adds no executable-only modules, so the placement
check should pass unchanged; if it complains, the new code was put in `src-exe/` when it belonged
in `seihou-cli/src/`.


## Validation and Acceptance

Acceptance is behavior, verified by hand in a scratch directory and by the automated suites.

### 1. A blueprint's declaration takes effect

Create a scratch project and a blueprint that declares a model and effort but no provider:

```bash
export SCRATCH=$(mktemp -d)
mkdir -p "$SCRATCH/.seihou/modules/deep-thinker"
cat > "$SCRATCH/.seihou/modules/deep-thinker/blueprint.dhall" <<'EOF'
let S = /Users/shinzui/Keikaku/bokuno/seihou-project/seihou/schema/package.dhall

in  S.Blueprint::{
    , name = "deep-thinker"
    , version = Some "0.1.0"
    , prompt = "Explain what you would change in this repository."
    , launch = Some S.Launch::{ model = Some "claude-sonnet-5", effort = Some "max" }
    }
EOF
cd "$SCRATCH"
```

Run with `--debug` (which renders the prompt and never contacts a provider) plus `--verbose`:

```bash
seihou agent run deep-thinker --verbose --debug 2>&1 >/dev/null
```

Expected on stderr:

```text
[info]  Agent: provider claude-cli [built-in default], model claude-sonnet-5 [blueprint: launch.model], effort max [blueprint: launch.effort]
```

The important part is `[blueprint: launch.model]` and `[blueprint: launch.effort]`: the model is
`claude-sonnet-5` even though nothing in the user's config says so, and the source label names the
blueprint.

### 2. A flag still overrides the declaration

```bash
seihou agent run deep-thinker --model claude-opus-4-8 --verbose --debug 2>&1 >/dev/null
```

Expected:

```text
[info]  Agent: provider claude-cli [built-in default], model claude-opus-4-8 [flag on subcommand], effort max [blueprint: launch.effort]
```

Only the named field moves; `effort` still comes from the blueprint.

### 3. The declaration beats configured defaults

```bash
seihou config set agent.run.model claude-haiku-4-5     # project-local
seihou agent run deep-thinker --verbose --debug 2>&1 >/dev/null
```

Expected: `model claude-sonnet-5 [blueprint: launch.model]` — the blueprint outranks both the
per-command local key and the shared local key. Then confirm the environment still wins:

```bash
SEIHOU_AGENT_MODEL=claude-haiku-4-5 seihou agent run deep-thinker --verbose --debug 2>&1 >/dev/null
```

Expected: `model claude-haiku-4-5 [env: SEIHOU_AGENT_MODEL]`.

### 4. The values reach the agent process

This is what the automated end-to-end cases added in Milestone 4 prove, and it is the acceptance
that matters most because steps 1–3 only inspect Seihou's own accounting. Run them alone for a
fast check:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
cabal test seihou-cli --test-options='--pattern "Agent migrate end-to-end"'
```

Expected: the pattern's cases pass, including "applies a blueprint-declared model and effort to
the launched agent" and "lets a --model flag override the blueprint declaration". Those cases put
a fake `claude` on `PATH` that writes its argv to a file, so a pass means the real argv contained
`--model claude-sonnet-5 --effort max` (case 1) and `--model claude-opus-4-8 … --effort max`
(case 2).

### 5. A bad declaration is caught, not silently ignored

```bash
cd "$SCRATCH/.seihou/modules/deep-thinker"
# change provider to Some "llama"
seihou validate-blueprint; echo "exit=$?"
```

Expected: a failing check line naming the offending key and the accepted values, and a non-zero
exit:

```text
✗ launch settings   launch.provider: Unknown agent provider 'llama'. Expected one of: claude-cli, codex-cli, anthropic, openai.
exit=1
```

And a run refuses rather than falling back:

```bash
cd "$SCRATCH" && seihou agent run deep-thinker --debug; echo "exit=$?"
```

Expected:

```text
[error] Invalid agent settings for blueprint 'deep-thinker': Unknown agent provider 'llama'. Expected one of: claude-cli, codex-cli, anthropic, openai.
exit=1
```

### 6. Prompts behave the same way, and old artifacts still work

Repeat step 1 with `seihou prompt run` against a `prompt.dhall` declaring
`launch = Some S.Launch::{ effort = Some "low" }`; the provenance label must read
`[prompt: launch.effort]`. Then prove backward compatibility: a `prompt.dhall` whose `launch`
literal has only the old three fields (`provider`, `mode`, `model`) must still load — this is
exactly what the preserved fixture at `seihou-core/test/Seihou/Core/AgentPromptSpec.hs:292`
asserts, so `cabal test seihou-core` covers it, and a blueprint with no `launch` field at all must
still load and run.

### 7. The whole gate

```bash
cabal test all
nix flake check
```

Expected: both green. `nix flake check` additionally proves the schema submodule pointer,
`flake.lock`, and `SchemaVersion.hs` agree, because the nix build copies the submodule in for the
Dhall-importing tests.


## Idempotence and Recovery

Every step is safe to re-run. Editing Dhall files, Haskell modules, and docs is idempotent by
nature; `cabal build`, `cabal test`, and `nix flake check` are read-only with respect to the
working tree.

Two steps deserve care:

**The schema push.** `git -C schema push origin master` publishes a commit to a shared repository
and cannot be un-published cleanly. Get the schema right before pushing: run
`dhall type --file schema/package.dhall` and the `/tmp/launch-probe.dhall` check first. If a
mistake ships, do **not** rewrite history on `origin/master` — the previous pin
(`2dffa059…`, hash `sha256:01b6f873…`) is referenced by every already-authored blueprint and
prompt in the wild, and rewriting would break their integrity hashes. Fix forward with a second
commit and re-pin. Recovery from a *local* mistake before pushing is
`git -C schema reset --hard origin/master`.

**The pin bump.** If `SchemaVersion.hs`, the submodule pointer, and `flake.lock` fall out of sync,
the symptom is a Dhall import failure mentioning a hash mismatch, or a nix build that cannot find
the new field. Recover by re-deriving all three from the submodule's actual HEAD:
`git -C schema rev-parse HEAD` for the URL, `dhall hash < schema/package.dhall` for the hash, and
`nix flake lock --update-input seihou-schema-src` for the lock. Dhall caches imports by hash under
`$XDG_CACHE_HOME/dhall`; a stale cache never serves the wrong content (the hash is the key), so
there is nothing to purge, but a machine without network access cannot fetch a *new* pin until it
has once.

The rest of the work is additive: the new schema field is optional with a default, the new decoder
fields are defaulted through `withDefaults`, and the new resolver tier is inert when an artifact
declares nothing. Reverting any single milestone's commit leaves the tree building, with one
ordering constraint: Milestone 1's pin bump should be reverted last, because Milestones 2–6 assume
the schema field exists.


## Interfaces and Dependencies

### External dependencies (no new ones)

- **`dhall` (Haskell library, `>=1.42 && <2`)** — evaluation and decoding. Used through the
  existing `Decoder`, `record`, `field`, `maybe`, `strictText`, and the repository's local
  `withDefaults` helper in `seihou-core/src/Seihou/Dhall/Eval.hs`.
- **`dhall` (CLI)** — `dhall type`, `dhall hash`; already required by the
  `update-seihou-schema` workflow.
- **`baikai` 0.4** — `Baikai.ThinkingLevel.ThinkingLevel` and the interactive/API launch paths.
  Only reached through `seihou-cli/src/Seihou/CLI/AgentCompletion.hs` and
  `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs`; this plan adds no new Baikai surface.
- **`seihou-schema`** — the Dhall schema, vendored as the `schema/` git submodule
  (`git@github.com:shinzui/seihou-schema.git`) and consumed by nix through the
  `seihou-schema-src = { url = "git+file:./schema"; flake = false; }` flake input.

### Schema files (in the `schema/` submodule)

- `schema/Launch.dhall` (new) — `{ Type = { provider : Optional Text, model : Optional Text,
  effort : Optional Text, mode : Optional Text }, default = { … all None … } }`.
- `schema/Blueprint.dhall` — gains `launch : Optional Launch.Type` with default
  `None Launch.Type`, and re-exports `Launch`.
- `schema/AgentPrompt.dhall` — its inline `Launch` is replaced by `./Launch.dhall`; the field type
  is unchanged in name, widened by `effort`.
- `schema/package.dhall` — gains `Launch = ./Launch.dhall`.

### `seihou-core`

`Seihou.Core.Types`:

```haskell
data AgentLaunch = AgentLaunch
  { provider :: Maybe Text, model :: Maybe Text, effort :: Maybe Text, mode :: Maybe Text }

data Blueprint = Blueprint { …existing fields…, launch :: Maybe AgentLaunch }
data AgentPrompt = AgentPrompt { …existing fields…, launch :: Maybe AgentLaunch }
```

`AgentPromptLaunch` is renamed to `AgentLaunch`; the old name is removed (both call sites are
in-tree).

`Seihou.Dhall.Eval`:

```haskell
agentLaunchDecoder :: Decoder AgentLaunch     -- replaces agentPromptLaunchDecoder
blueprintDecoder  :: Decoder Blueprint        -- withDefaults now also covers "launch"
```

`Seihou.Core.Blueprint`: `checkBlueprintLaunch :: Blueprint -> [Text]` (exported, wired into
`validateBlueprintWith`). `Seihou.Core.AgentPrompt`:
`checkAgentPromptLaunch :: AgentPrompt -> [Text]` (exported, wired into `validateAgentPrompt`).
`Seihou.Core.Scaffold.blueprintDhall`: unchanged signature, one commented line added to its
output.

### `seihou-cli` library (`seihou-cli/src/`)

`Seihou.CLI.AgentConfig` — all additions land here (library, so no module-placement impact):

```haskell
data AgentConfigInputs = AgentConfigInputs
  { …existing fields…
  , declaredProvider :: Maybe Text
  , declaredModel :: Maybe Text
  , declaredEffort :: Maybe Text
  }

data AgentConfigSource = … | SourceEnv | SourceArtifactDeclaration | SourceLocalCommand | …

data AgentLaunchDeclaration = AgentLaunchDeclaration
  { declarationProvider :: Maybe Text
  , declarationModel :: Maybe Text
  , declarationEffort :: Maybe Text
  }

noAgentLaunchDeclaration :: AgentLaunchDeclaration
agentLaunchDeclaration   :: Maybe AgentLaunch -> AgentLaunchDeclaration

data PendingAgentConfig = PendingAgentConfig
  { pendingCommand :: AgentCommandName, pendingInputs :: AgentConfigInputs }

loadPendingAgentConfig ::
  AgentCommandName -> Maybe Text -> Maybe Text -> Maybe Text -> Bool -> Bool -> Bool ->
  IO (Either Text PendingAgentConfig)
resolvePendingAgentConfig ::
  PendingAgentConfig -> AgentLaunchDeclaration -> Either Text ResolvedCommandConfig
resolvedAgentModelConfig :: ResolvedCommandConfig -> AgentModelConfig
formatResolvedAgentProvenance :: ResolvedCommandConfig -> Text
validateAgentLaunchDeclaration :: AgentLaunchDeclaration -> [Text]
resolveDeclaredAgentConfig ::
  LogLevel -> Text -> PendingAgentConfig -> AgentLaunchDeclaration -> IO AgentModelConfig
```

Unchanged and still exported with identical behavior: `resolveAgentModelConfig`,
`resolveAgentModelConfigFor`, `loadAgentModelConfig`, `loadAgentModelConfigFor`,
`loadResolvedAgentConfig`, all the config-key and env-var helpers, `agentConfigSourceLabel`
(extended with one new case).

`Seihou.CLI.AgentConfigShow` — `precedenceLegend` gains the declaration tier and renumbers.

### `seihou-cli` executable (`seihou-cli/src-exe/`)

```haskell
Seihou.CLI.AgentRun.handleAgentRun     :: Bool -> PendingAgentConfig -> BlueprintRunOpts -> IO ()
Seihou.CLI.AgentMigrate.handleAgentMigrate
                                       :: Bool -> PendingAgentConfig -> BlueprintMigrationOpts -> IO ()
Seihou.CLI.PromptRun.handlePromptRun   :: PendingAgentConfig -> PromptRunOpts -> IO ()
Main.pendingAgentConfigFor             :: AgentCommandName -> Maybe Text -> Maybe Text -> Maybe Text
                                       -> Maybe Text -> Maybe Text -> Maybe Text
                                       -> IO PendingAgentConfig
```

`Seihou.CLI.AgentRun.runRenderedAgentPrompt` and everything in
`Seihou.CLI.AgentLaunchExec` keep their current signatures — the declaration is fully resolved
into an `AgentModelConfig` before it reaches them, so the launch layer needs no changes at all.
`Seihou.CLI.ValidateBlueprint` and `Seihou.CLI.ValidatePrompt` gain one `DiagCheck` row each.

### Tests

- `seihou-core/test/Seihou/Core/BlueprintSpec.hs` — decode and validation cases for `launch`,
  plus the no-`launch` regression case.
- `seihou-core/test/Seihou/Core/AgentPromptSpec.hs` — the existing three-field fixture is
  preserved as the compatibility test; one new fixture sets `effort`.
- `seihou-core/test/Seihou/Core/ScaffoldSpec.hs` — generated blueprint still decodes and validates.
- `seihou-cli/test/Seihou/CLI/AgentConfigSpec.hs` — the precedence matrix for the new tier,
  including the provider-default-model interaction and the provenance labels.
- `seihou-cli/test/Seihou/CLI/AgentConfigShowSpec.hs` — legend text, if asserted.
- `seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs` — the two argv-level end-to-end cases.

No new spec modules are introduced, so `seihou-core/test/Main.hs`, `seihou-cli/test/Main.hs`, and
the two `.cabal` files need no edits.
