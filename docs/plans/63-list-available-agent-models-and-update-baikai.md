---
id: 63
slug: list-available-agent-models-and-update-baikai
title: "List available agent models and update Baikai"
kind: exec-plan
created_at: 2026-07-15T22:51:47Z
intention: "intention_01kxkzc8m3e22s2cq821eb06sf"
---

# List available agent models and update Baikai

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

Seihou accepts `--model MODEL` for agent and prompt runs, but today users must already know a
provider-specific model identifier. After this change, `seihou agent models` prints the
Anthropic and OpenAI models known to the shipped Baikai catalog, including the newest
`claude-sonnet-5` and `gpt-5.6` family, and an optional `--provider` filter narrows the list.
The output also tells users that provider-native aliases and custom identifiers remain valid;
the new catalog is a discovery aid, not a validator that closes the set of accepted values.

A user can see the behavior without credentials or network access after installation:

```bash
seihou agent models
seihou agent models --provider openai
seihou agent --provider claude-cli models
```

The first command prints all 31 catalog entries supported by Seihou's four agent providers.
The OpenAI filter prints 22 entries, and the Claude/Anthropic filter prints 9. The same change
raises Seihou's Baikai package lower bounds and exact Nix pins to the 2026-07-15 releases, so
the model list is backed by `baikai-0.3.1.0` instead of the Nix build's current
`baikai-0.3.0.0` catalog.


## Progress

- [x] (2026-07-15 16:12 PDT) Verified the Seihou repository identity, the registered Baikai
  source and model guide, and availability of the four planned Hackage releases.
- [x] (2026-07-15 16:17 PDT) Updated all direct Cabal lower bounds and exact Nix pins, then
  passed `cabal build seihou-cli` and `nix build .#seihou-cli --no-link`.
- [x] (2026-07-15 16:20 PDT) Added the pure 31-model catalog, provider mapping, filtering,
  sorting, aligned rendering, and six focused tests; the focused `AgentModelsSpec` passes.
- [x] (2026-07-15 16:24 PDT) Wired `seihou agent models`; direct smoke tests passed for
  unfiltered output, both provider-filter placements, help, invalid providers, irrelevant
  parent `--model`, and free-form custom model parsing.
- [x] (2026-07-15 16:24 PDT) Updated packaged help, the CLI reference, user guide,
  architecture inventory, and changelog with the discovery and advisory-list contracts.
- [ ] Run smoke tests and all repository-wide validation gates, then complete the retrospective.

## Surprises & Discoveries

- Observation: The initially recorded Nix hashes were flat hashes of the compressed Hackage
  tarballs, but `callHackageDirect` verifies recursive hashes of the unpacked sources.
  Evidence: `nix build .#seihou-cli --no-link` reported
  `got: sha256-xcyjJt0+YwlXhxXclAayaJh6i7AFvDGTZRPOgUURXBc=` for `baikai-0.3.1.0`, and
  `nix store prefetch-file --json --unpack` reproduced that value and supplied matching
  recursive hashes for the other three releases.

- Observation: Importing selectors from the broad `Baikai` module is ambiguous under GHC
  9.12 because that module re-exports several records with fields named `provider`, `modelId`,
  and `name`.
  Evidence: The first focused build reported `Ambiguous occurrence 'Baikai.provider'` from
  `Seihou.CLI.AgentModels`; importing `Baikai.Model` directly removed the ambiguity and all
  six focused tests passed.

## Decision Log

- Decision: Add `models` under the existing `seihou agent` command group, with an optional
  `--provider PROVIDER` filter accepted either before or after `models`.
  Rationale: `--model` is shared by the agent and prompt workflows, and the existing `agent`
  group already owns the supported provider vocabulary. This makes discovery adjacent to the
  option it explains without adding another unrelated top-level command.
  Date: 2026-07-15

- Decision: Treat the model list as advisory and continue accepting every non-blank model
  identifier or provider-native alias through `--model`, configuration, and environment
  variables.
  Rationale: Baikai deliberately models identifiers as `Text` because providers and local
  CLIs add models and aliases faster than library releases. Restricting parsing to the shipped
  catalog would break custom deployments and aliases such as `sonnet`.
  Date: 2026-07-15

- Decision: Map Anthropic catalog rows to both `anthropic` and `claude-cli`, and OpenAI rows to
  both `openai` and `codex-cli`, while printing each model only once in an unfiltered list.
  Rationale: Baikai's catalog describes upstream API families, whereas Seihou exposes both an
  API provider and an interactive local CLI for each family. A single row with both compatible
  provider names is useful without duplicating 31 rows.
  Date: 2026-07-15

- Decision: Enumerate the relevant bindings from `Baikai.Models.Generated` in one
  library-visible Seihou module and cover the list with count, uniqueness, filtering, and
  newest-model tests.
  Rationale: `baikai-0.3.1.0` exposes one generated `Model` value per catalog entry but does not
  export an aggregate `[Model]`. Keeping the explicit list in one tested module is the smallest
  downstream solution and avoids scraping dependency source or shipping a second JSON catalog
  at runtime.
  Date: 2026-07-15

- Decision: Update the full set of Baikai packages Seihou directly depends on, while preserving
  the existing `dontCheck` wrappers for `baikai` and `baikai-kit` in Nix.
  Rationale: The core, Claude, OpenAI, and kit packages were released together on 2026-07-15.
  Their published source archives still omit the model JSON/test fixtures needed by their
  upstream test suites, even though they contain all library source, so removing `dontCheck`
  would reintroduce known packaging-only failures.
  Date: 2026-07-15

- Decision: Do not change Seihou's current default models in this plan.
  Rationale: The request is to expose available choices and consume the current catalog. Moving
  the API defaults from `claude-sonnet-4-6` or `gpt-4o-mini` would alter cost and behavior for
  users who did not opt into a new model.
  Date: 2026-07-15

- Decision: Pin `callHackageDirect` with hashes produced by
  `nix store prefetch-file --json --unpack`, not the flat archive hashes originally recorded.
  Rationale: `callHackageDirect` unpacks Hackage source distributions before verifying them,
  and the recursive hashes are the values accepted by the repository's Nix build.
  Date: 2026-07-15


## Outcomes & Retrospective



## Context and Orientation

All paths in this plan are relative to the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Seihou is a multi-package Haskell project. `seihou-cli/seihou-cli.cabal` defines a private,
test-importable library named `seihou-cli-internal`, the `seihou` executable, and the
`seihou-cli-test` suite. The repository follows a library-first convention documented in
`docs/dev/architecture/overview.md`: pure catalog, filtering, and formatting code belongs in
`seihou-cli/src/Seihou/CLI/`, while the parser and command dispatcher remain under
`seihou-cli/src-exe/` because they depend on `optparse-applicative` or executable-only command
types.

`seihou-cli/src-exe/Seihou/CLI/Commands.hs` defines `AgentOpts`, the `AgentCommand` sum type,
the `agentParser`, and a shared `modelOption`. Its current subcommands are `assist`,
`bootstrap`, `setup`, and `run`. Parent `--provider` and `--model` flags are stored on
`AgentOpts`; the runnable subcommands also accept local copies so flags work before or after
the subcommand. `seihou-cli/src-exe/Main.hs` dispatches those constructors and resolves their
provider/model settings through `Seihou.CLI.AgentConfig`.

`seihou-cli/src/Seihou/CLI/AgentCompletion.hs` defines the four supported `AgentProvider`
constructors and the canonical `providerFromText`/`providerToText` conversion functions.
`claude-cli` and `codex-cli` launch interactive local tools; `anthropic` and `openai` make
direct API completions. `--model` remains a free-form `Text` value throughout
`seihou-cli/src/Seihou/CLI/AgentConfig.hs`, and that behavior must not become enum validation.

Baikai is Seihou's provider abstraction dependency. Per the repository's `AGENTS.md`, its
registered source was located with `mori registry show shinzui/baikai --full` at
`/Users/shinzui/Keikaku/bokuno/baikai`, and its curated model guide is registered as
`mori://shinzui/baikai/docs/models-and-providers`. In release `baikai-0.3.1.0`, the exposed
module `Baikai.Models.Generated` contains one `Baikai.Model` binding per generated catalog
entry. `Baikai.Model` exposes `modelId`, `name`, and `provider` selectors, but the generated
module has no aggregate list. Seihou only supports the catalog's `anthropic` and `openai`
families; `deepseek` and `openrouter` entries are outside Seihou's four-provider configuration
and must not be displayed as selectable Seihou agent models.

The current dependency state is mixed rather than fully current. The three Baikai bounds in
the library, executable, and test stanzas of `seihou-cli/seihou-cli.cabal` start at
`baikai ^>=0.3.0.0`, and the executable also starts at `baikai-kit ^>=0.1.0.1`. Those ranges
can permit later compatible versions, but `nix/haskell-overlay.nix` reproducibly selects exact
older releases: `baikai`, `baikai-claude`, and `baikai-openai` at `0.3.0.0`, and `baikai-kit`
at `0.1.0.1`. `cabal list --simple-output baikai` and the registered Baikai release tags show
the current releases are `baikai-0.3.1.0`, `baikai-claude-0.3.0.1`,
`baikai-openai-0.3.0.1`, and `baikai-kit-0.1.0.2`.

User-visible command help is split across parser text in
`seihou-cli/src-exe/Seihou/CLI/Commands.hs`, the packaged help topic
`seihou-cli/help/agent.md`, the command reference `docs/cli/agent.md`, and the guide
`docs/user/agent-assistance.md`. `CHANGELOG.md` records unreleased behavior, and the project
structure inventory in `docs/dev/architecture/overview.md` must mention any new internal
library module. Tests follow tasty plus hspec: each spec exports `tests :: IO TestTree`, is
listed in `seihou-cli/seihou-cli.cabal`, and is registered in `seihou-cli/test/Main.hs`.


## Plan of Work

### Milestone 1: Align Cabal and Nix on the current Baikai releases

Update every direct Baikai constraint in `seihou-cli/seihou-cli.cabal`. Use
`baikai ^>=0.3.1.0` in the internal library, executable, and test suite;
`baikai-claude ^>=0.3.0.1` and `baikai-openai ^>=0.3.0.1` in the library and executable; and
`baikai-kit ^>=0.1.0.2` in the executable. These lower bounds guarantee that the compiled
catalog contains the models this feature promises instead of merely allowing the resolver to
choose an older compatible package.

In `nix/haskell-overlay.nix`, update the four exact Hackage packages and hashes to:

```text
baikai         0.3.1.0  sha256-xcyjJt0+YwlXhxXclAayaJh6i7AFvDGTZRPOgUURXBc=
baikai-claude  0.3.0.1  sha256-77bDSzeGfYlnKDmjHwpNaXezqOSgQUbO26hDoGYyP8w=
baikai-openai  0.3.0.1  sha256-meDqBNMvjlhTWFHVji0yJmg1381bB6HwQdo3SfWLm/w=
baikai-kit     0.1.0.2  sha256-kt+CMLJrn1No/reIPwLP6d8hpaxT5O940tGZfQacXNg=
```

Retain `dontCheck` around `baikai` and `baikai-kit`, and rewrite their comments to name the
new versions while explaining that the published archives still omit `data/models` or test
fixtures. At this milestone's end, `cabal build seihou-cli` and
`nix build .#seihou-cli --no-link` resolve and compile the new release family without any CLI
behavior change.

### Milestone 2: Add one testable catalog and renderer

Create `seihou-cli/src/Seihou/CLI/AgentModels.hs` in the internal library. Import
`Baikai.Models.Generated` qualified and construct `availableAgentModels :: [Baikai.Model]`
from every Anthropic and OpenAI binding in `baikai-0.3.1.0`; do not include DeepSeek or
OpenRouter. The explicit binding list is:

```haskell
[ Models.anthropic_claude_fable_5
, Models.anthropic_claude_haiku_4_5
, Models.anthropic_claude_opus_4_5
, Models.anthropic_claude_opus_4_6
, Models.anthropic_claude_opus_4_7
, Models.anthropic_claude_opus_4_8
, Models.anthropic_claude_sonnet_4_5
, Models.anthropic_claude_sonnet_4_6
, Models.anthropic_claude_sonnet_5
, Models.openai_gpt_4_1
, Models.openai_gpt_4_1_mini
, Models.openai_gpt_4_1_nano
, Models.openai_gpt_4o
, Models.openai_gpt_4o_mini
, Models.openai_gpt_5
, Models.openai_gpt_5_1
, Models.openai_gpt_5_2
, Models.openai_gpt_5_4
, Models.openai_gpt_5_4_mini
, Models.openai_gpt_5_4_nano
, Models.openai_gpt_5_5
, Models.openai_gpt_5_6
, Models.openai_gpt_5_6_luna
, Models.openai_gpt_5_6_sol
, Models.openai_gpt_5_6_terra
, Models.openai_gpt_5_mini
, Models.openai_gpt_5_nano
, Models.openai_o1
, Models.openai_o3
, Models.openai_o3_mini
, Models.openai_o4_mini
]
```

Expose pure helpers that map each row to compatible Seihou providers, filter by an optional
provider, sort first by Baikai family and then by `modelId`, and render an aligned text table.
The unfiltered table must print each model once with a `PROVIDERS` column containing
`anthropic, claude-cli` or `openai, codex-cli`. End with a count and the guidance that the
catalog is not exhaustive and arbitrary provider-specific aliases remain accepted.

Add `Seihou.CLI.AgentModels` to the internal library's `exposed-modules`. Create
`seihou-cli/test/Seihou/CLI/AgentModelsSpec.hs`, add it to the test suite's `other-modules`,
and register it in `seihou-cli/test/Main.hs`. Test that all 31 `modelId` values are unique,
the two newest families are present, Anthropic and Claude CLI filters return the same 9 IDs,
OpenAI and Codex CLI filters return the same 22 IDs, and formatted output includes names,
provider labels, counts, and the free-form alias guidance. At this milestone's end, the pure
catalog test passes even though no command is wired yet.

### Milestone 3: Expose the command and document the discovery contract

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, add an `AgentModelsOpts` record carrying
`modelsProvider :: Maybe Text` and add `AgentModels AgentModelsOpts` to `AgentCommand`.
Register `models` alongside `assist`, `bootstrap`, `setup`, and `run`. Give it a local
`--provider` option by reusing `providerOption`, so both of these forms work:

```bash
seihou agent --provider openai models
seihou agent models --provider openai
```

Update the parent and shared `--model` help strings to say that `seihou agent models` lists
known choices, and add `models` to the `seihou agent --help` footer. The `models` parser does
not accept a local `--model` because it is listing choices. If a parent `--model` is supplied
before `models`, dispatch must fail clearly instead of silently ignoring it.

In `seihou-cli/src-exe/Main.hs`, dispatch `AgentModels` without calling
`loadAgentModelConfig`: absence of `--provider` means list all models, not filter to the
configured default provider. Prefer the subcommand-local provider over the parent provider,
parse an explicitly supplied value with the existing `providerFromText`, print parse errors
with the same `Error: ...` and exit-failure behavior as runnable agent commands, then print
the pure formatter's result. This command must not inspect API keys, contact a provider, or
read agent configuration.

Update `seihou-cli/help/agent.md`, `docs/cli/agent.md`, and
`docs/user/agent-assistance.md` with the command syntax, provider filtering examples, the
API/CLI family mapping, and the advisory-not-validation rule. Add an entry under
`CHANGELOG.md`'s `[Unreleased]` section for the new discovery command and Baikai catalog
refresh. Add `Seihou.CLI.AgentModels` to the internal-library inventory in
`docs/dev/architecture/overview.md`. At this milestone's end, direct command smoke tests,
the complete test suite, formatting checks, and the Nix package build all pass.


## Concrete Steps

Work from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`. Confirm repository identity
and the dependency source before editing:

```bash
mori show --full
mori registry show shinzui/baikai --full
mori registry docs shinzui/baikai
cabal list --simple-output baikai
```

The package list must include the release family used by this plan:

```text
baikai 0.3.1.0
baikai-claude 0.3.0.1
baikai-kit 0.1.0.2
baikai-openai 0.3.0.1
```

Make the Milestone 1 Cabal and Nix edits, then run:

```bash
cabal build seihou-cli
nix build .#seihou-cli --no-link
```

After adding `AgentModels.hs` and its tests, run the focused suite:

```bash
cabal test seihou-cli-test --test-options '--pattern "Seihou.CLI.AgentModels"'
```

Expected focused evidence is a passing spec that reports 31 unique rows, 9 Claude-family
rows, and 22 OpenAI-family rows. After wiring the parser and dispatcher, exercise both flag
placements and the unfiltered output:

```bash
cabal run seihou -- agent models
cabal run seihou -- agent models --provider openai
cabal run seihou -- agent --provider claude-cli models
cabal run seihou -- agent --help
```

The exact table spacing may change to accommodate the longest name, but the unfiltered output
must have this shape and include the shown newest rows:

```text
Available agent models:

MODEL                 NAME                  PROVIDERS
...
claude-sonnet-5       Claude Sonnet 5       anthropic, claude-cli
...
gpt-5.6               GPT-5.6               openai, codex-cli
gpt-5.6-terra         GPT-5.6 Terra         openai, codex-cli
...

31 models found.
Provider-specific aliases and custom model IDs remain accepted by --model.
```

Verify failure and compatibility paths. The first two commands must exit non-zero with a
useful error; the third must succeed in debug mode without contacting OpenAI, proving that the
listing did not turn `--model` into validation:

```bash
cabal run seihou -- agent models --provider unknown
cabal run seihou -- agent --model gpt-5.6 models
cabal run seihou -- agent --debug --provider openai --model custom-model assist "check custom model parsing"
```

Finish with the repository-wide gates:

```bash
nix fmt -- --fail-on-change
cabal build all
cabal test all
nix build .#seihou-cli --no-link
git diff --check
```

Commit in coherent, working increments using Conventional Commits. Every implementation
commit must end with both active trailers:

```text
feat(agent): list available Baikai models

ExecPlan: docs/plans/63-list-available-agent-models-and-update-baikai.md
Intention: intention_01kxkzc8m3e22s2cq821eb06sf
```


## Validation and Acceptance

Acceptance requires behavior, dependency alignment, and documentation to agree.

Running `seihou agent models` exits successfully without provider credentials, prints exactly
31 unique catalog model IDs, includes `claude-sonnet-5`, `gpt-5.6`, `gpt-5.6-luna`,
`gpt-5.6-sol`, and `gpt-5.6-terra`, and names compatible API and CLI providers for each row.
Running the command with `--provider anthropic` or `--provider claude-cli` prints the same 9
Claude-family rows; `--provider openai` or `--provider codex-cli` prints the same 22
OpenAI-family rows. Both parent and subcommand filter placements work. An unknown provider
uses the existing supported-provider diagnostic and exits non-zero, and a parent `--model`
on the listing command is rejected as irrelevant rather than ignored.

The listing is advisory: `seihou agent --debug --provider openai --model custom-model assist
"check"` still parses and runs the debug path. Existing config-resolution tests remain green,
proving that environment and config model values are still free-form.

`seihou agent --help`, the packaged `seihou help agent` topic, the CLI reference, and the user
guide all point users to `seihou agent models` and explain that local CLI aliases may extend
the catalog. No documentation claims that the catalog validates live provider availability.

`cabal build all` and `cabal test all` pass with the raised lower bounds. The focused
`AgentModelsSpec` covers count, uniqueness, filtering, newest rows, and rendering. Finally,
`nix build .#seihou-cli --no-link` succeeds using the four exact 2026-07-15 Hackage versions
and hashes from Milestone 1, proving the reproducible build no longer uses the older catalog.


## Idempotence and Recovery

All edits are source, dependency metadata, tests, and documentation; there are no migrations,
network calls at command runtime, or user-data writes. Cabal builds, tests, formatter checks,
model listing commands, and Nix builds are safe to repeat.

If a Hackage hash is mistyped, Nix fails before building and reports the actual hash. Verify a
single archive again with `nix store prefetch-file --json --unpack` and its official Hackage
URL, then replace only that package's hash in `nix/haskell-overlay.nix`. The `--unpack` flag is
required because `callHackageDirect` uses the recursive hash of the unpacked source rather
than the flat hash of the compressed tarball. Do not search or inspect
`/nix/store`; the prefetch command's JSON hash is sufficient. If Cabal cannot see the
2026-07-15 packages, run `cabal update` and retry.

If work stops partway through the command wiring, the dependency and pure catalog milestones
remain independently buildable. Resume from the first unchecked Progress entry. When changing
the explicit catalog list, rerun the focused spec before the full suite; its uniqueness and
family-count assertions catch accidental duplicates or omissions from this release. Keep the
plan's Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective sections
current at every stopping point.


## Interfaces and Dependencies

`seihou-cli/src/Seihou/CLI/AgentModels.hs` must expose this pure surface (minor naming changes
are acceptable only if all roles remain explicit):

```haskell
availableAgentModels :: [Baikai.Model]
providersForModel :: Baikai.Model -> [AgentProvider]
filterAgentModels :: Maybe AgentProvider -> [Baikai.Model] -> [Baikai.Model]
formatAgentModels :: Maybe AgentProvider -> [Baikai.Model] -> Text
```

`providersForModel` maps `Baikai.provider == "anthropic"` to
`[AgentProviderAnthropic, AgentProviderClaudeCli]` and `Baikai.provider == "openai"` to
`[AgentProviderOpenAI, AgentProviderCodexCli]`. `filterAgentModels Nothing` returns all rows;
a `Just` filter retains rows whose compatible-provider list contains that provider. Formatting
uses Baikai's exported `modelId`, `name`, and `provider` selectors and Seihou's existing
`providerToText`; no second record containing copied model metadata is needed.

`seihou-cli/src-exe/Seihou/CLI/Commands.hs` must add:

```haskell
data AgentModelsOpts = AgentModelsOpts
  { modelsProvider :: Maybe Text
  }

data AgentCommand
  = AgentAssist AssistOpts
  | AgentBootstrap BootstrapOpts
  | AgentSetup SetupOpts
  | AgentRun BlueprintRunOpts
  | AgentModels AgentModelsOpts
```

The real declaration should preserve the repository formatter's constructor ordering. The
parser remains an `optparse-applicative` concern in the executable. Catalog and renderer code
must not import `Options.Applicative`, so the test suite can import it through
`seihou-cli-internal`.

The direct package dependencies and reproducible versions are `baikai-0.3.1.0` for the model
type and generated catalog, `baikai-claude-0.3.0.1` and `baikai-openai-0.3.0.1` for the
existing provider implementations, and `baikai-kit-0.1.0.2` for the existing kit commands.
No new package or network service is introduced. Runtime model listing operates only on
compiled Haskell values from `Baikai.Models.Generated`.
