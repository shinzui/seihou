# seihou agent

AI-powered agent commands backed by configurable providers. First-class prompt
artifacts use the same provider configuration through `seihou prompt run`.

## Usage

```text
seihou agent [--debug] [--provider PROVIDER] [--model MODEL] <SUBCOMMAND> [OPTIONS]
```

## Options

| Option | Description |
|--------|-------------|
| `--debug` | Print the resolved system prompt and exit without contacting a provider |
| `--provider PROVIDER` | Use `claude-cli`, `codex-cli`, `anthropic`, or `openai` for this invocation |
| `--model MODEL` | Use a provider-specific model name or alias for this invocation; run `seihou agent models` to list known choices |
| `--effort LEVEL` | Reasoning effort for this invocation: `minimal`, `low`, `medium`, `high`, `xhigh`, or `max` |
| `--trace SETTING` | Record each model call: `off` (default), `file`, `stdout`, or `stderr`. The file destination is `agent.tracePath`, defaulting to `.seihou/trace.jsonl` |

The default provider is `claude-cli`. When no model is configured, Seihou pins a deterministic per-provider default (`claude-cli` → `claude-opus-4-8`, `codex-cli` → `gpt-5.6-terra`) and always passes it explicitly, so a CLI session never inherits whatever model another `claude`/`codex` session left active. Provider and model options may appear on the parent command or on the subcommand:

```sh
seihou agent --provider codex-cli --model gpt-5 assist "create a module"
seihou agent assist --provider codex-cli --model gpt-5 "create a module"
seihou agent --debug --provider openai setup "show the prompt only"
```

Provider, model, effort, and trace values are resolved from CLI flags, environment variables, the artifact's own declaration, per-command and shared config keys (local then global), and defaults. Each command can be configured independently with `agent.<command>.provider` / `agent.<command>.model`, falling back to the shared `agent.provider` / `agent.model` defaults; a local project value always overrides a global one. See [Configuration and Variable Resolution](../user/config-and-variables.md#agent-provider-defaults) for the full precedence chain, and run `seihou agent config` (below) to inspect what resolves for each command.

A blueprint or prompt can also declare the agent it was written for, through a `launch` record in its `blueprint.dhall` or `prompt.dhall`. Those declared values outrank every configured default but still lose to a `--provider`, `--model`, or `--effort` flag and to the `SEIHOU_AGENT_*` environment variables, per field. This applies to `seihou agent run`, `seihou agent migrate`, and `seihou prompt run` — the three commands that load an artifact. Add `--verbose` to a run to see the resolved settings and where each came from:

```text
$ seihou agent run deep-thinker --verbose
[info]  Agent: provider claude-cli [built-in default], model claude-sonnet-5 [blueprint: launch.model], effort max [blueprint: launch.effort]
```

A declaration naming an unknown provider or effort fails the run with an actionable message rather than silently falling back. See [Blueprints](../user/blueprints.md#launch-settings). Note that `launch` does not cover `--trace`: tracing is the operator's choice, not the artifact author's.

`--trace` records what each model call cost in time and money. It is off unless asked for, and it covers batch and API calls only — an interactive `claude`/`codex` session is a spawned subprocess, not a request Seihou can time or price, so it emits no events. See [Tracing model calls](../user/agent-assistance.md#tracing-model-calls).

## Providers

| Provider | Backing implementation | Requirements | Notes |
|----------|-------------------------|--------------|-------|
| `claude-cli` | interactive `claude` | `claude` installed, on `PATH`, and authenticated | Starts a Claude Code session with the rendered Seihou prompt and allowed tool flags. Defaults to `claude-opus-4-8` when no model is configured; the model is always passed explicitly so the session is deterministic |
| `codex-cli` | interactive `codex` | `codex` installed, on `PATH`, and authenticated | Starts a Codex session with the rendered Seihou prompt, workspace-write sandboxing, and on-request approvals. Defaults to `gpt-5.6-terra` when no model is configured; the model is always passed explicitly so the session is deterministic |
| `anthropic` | Anthropic Messages API | `ANTHROPIC_API_KEY` or `ANTHROPIC_KEY` | Defaults to `claude-sonnet-4-6` when no model is configured |
| `openai` | OpenAI Chat Completions API | `OPENAI_API_KEY` or `OPENAI_KEY` | Defaults to `gpt-4o-mini` when no model is configured |

## Subcommands

### agent models

List the models in Seihou's compiled Baikai catalog.

```text
seihou agent models [--provider PROVIDER]
```

The provider filter may appear on the parent command or after the subcommand:

```sh
seihou agent --provider claude-cli models
seihou agent models --provider openai
```

Anthropic catalog rows are compatible with both `anthropic` and `claude-cli`;
OpenAI rows are compatible with both `openai` and `codex-cli`. The unfiltered
table prints each model once with both compatible providers. Listing uses only
compiled data, so it does not read agent configuration, inspect API keys, or
contact a provider.

The catalog is a discovery aid rather than a validation list. Provider-native
aliases and custom model IDs remain accepted by `--model` even when they do not
appear in the table. Passing a parent `--model` to `agent models` is rejected
because a model selection is irrelevant to a listing command.

### agent config

Show the resolved provider and model for every agent command.

```text
seihou agent config
```

Prints one entry per command (`assist`, `bootstrap`, `setup`, `run`, `migrate`, and
`prompt run`) with its resolved provider, model, reasoning effort, and trace
destination, each labelled by the source that supplied the value — a config
scope and key (for example `[local: agent.run.model]` or
`[global: agent.effort]`), an environment variable, or `[built-in default]` —
followed by the precedence legend. An `effort` of `(default)` means none is
configured; a `trace` of `off` means tracing is not enabled. The command is
read-only: it reflects the current environment and config but never changes
them. Set values with
`seihou config set agent.<command>.{provider,model,effort,trace} ...`.

### agent assist

Launch an AI-assisted template authoring session.

```text
seihou agent assist [PROMPT]
```

Renders a Seihou-aware prompt for creating and modifying modules, then starts the configured provider. CLI providers open interactive local agent sessions. API providers receive a one-shot completion request and print the assistant response. The prompt includes context about the current directory, existing modules, manifest state, available modules, and the Seihou module schema.

### agent bootstrap

Bootstrap a new module or multi-module repository.

```text
seihou agent bootstrap [PROMPT] [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `--repo` | Bootstrap a multi-module repository with registry |

Renders a prompt for creating a complete Seihou module from scratch: defining variables, writing templates, setting up prompts, and validating the result. With `--repo`, the prompt targets a multi-module repository with `seihou-registry.dhall`.

### agent setup

Guided project setup: configure, run, and commit.

```text
seihou agent setup [PROMPT]
```

Renders a prompt for using a Seihou module: selecting a module, configuring variables and context, running the module to generate files, verifying output, and committing changes to git.

### agent run

Run an agent-driven blueprint.

```text
seihou agent run BLUEPRINT [PROMPT] [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `--var KEY=VALUE` | Variable override; repeatable |
| `--no-baseline` | Skip applying the blueprint's base modules before rendering the prompt |
| `--namespace NS` | Override namespace for config lookup |
| `--context CTX`, `-c CTX` | Override context for config lookup |
| `--verbose`, `-v` | Show detailed progress messages |
| `--allow-downgrade` | Proceed even when the blueprint or a baseline module installed locally is older than, or from a different source than, `.seihou/manifest.json` records |

Resolves the named blueprint, prompts for required variables, optionally applies its baseline modules, renders the blueprint prompt, and starts the configured provider. A successful run records applied-blueprint provenance in `.seihou/manifest.json`; a `--debug` run does so too, after printing the prompt.

### agent migrate

Run ordered library-upgrade prompts declared by a blueprint.

```text
seihou agent migrate BLUEPRINT [--from VERSION] [--to VERSION] [PROMPT] [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `--from VERSION` | Current library version, dotted numeric. Defaults to the highest version this project's receipts record for the blueprint |
| `--to VERSION` | Target library version, dotted numeric. Defaults to the output of the blueprint's declared `versionProbe` |
| `--var KEY=VALUE` | Variable override; repeatable |
| `--namespace NS` | Override namespace for config lookup |
| `--context CTX`, `-c CTX` | Override context for config lookup |
| `--verbose`, `-v` | Show detailed progress messages |
| `--rerun` | Ignore matching exact-edge receipts, applied ones included, and run the selected steps again |
| `--mark-applied` | Record the pending edges in the window as already applied, without running them |
| `--allow-downgrade` | Proceed even when the blueprint installed locally is older than, or from a different source than, `.seihou/manifest.json` records |

The command plans matching blueprint edges in ascending version order, permitting
undeclared gaps, and starts one provider interaction per edge. It writes a
receipt after each interaction that returns, so an interrupted invocation resumes
at its first unrecorded edge. Migration mode does not apply blueprint baselines
and has no `--force` option.

An edge can report that it does not apply to this project — its precondition is
unmet and it deliberately changed nothing. That is a third outcome, distinct from
both success and provider failure: the reason is printed and recorded, and the
chain **continues to the next edge** rather than halting. Only an applied receipt
suppresses a later run, so an edge recorded as not applicable is planned again
next time without `--rerun`. The run summary counts them:

```text
Completed 2 blueprint migration(s) for 'my-library' (1 not applicable).
```

A chain may span more than one blueprint. An edge can declare that crossing it
*entails* crossing an exact edge of another blueprint, which is how a breaking
change reaches consumers who depend on the library that absorbed it rather than
on the library that shipped it. Entailed edges are expanded recursively, run
before the edge that declares them, and use their own blueprint's reference
files, allowed tools, and variables. Each step's receipt is written under the
blueprint that *owns* it, so a shared edge is crossed once whichever blueprint
you name. An entailed blueprint that is not installed fails the run with an
install hint rather than being skipped.

### Recording an upgrade performed by hand

`--mark-applied` writes a receipt for every pending edge in the resolved window
without starting an agent session, on your assertion that the upgrade has already
been performed:

```text
Marking 2 blueprint migration(s) as already applied, without running them:
  kiroku-upgrade 1.9.0 -> 2.0.0 (entailed by keiro-upgrade 2.4.0 -> 3.0.0)
  keiro-upgrade 2.4.0 -> 3.0.0

Recorded 2 receipt(s). No agent session was started and no file was changed.
```

No provider is contacted and no file in the working tree is read or written; the
only change is to `.seihou/manifest.json`. The window is resolved exactly as it
is for a real run — `--from` and `--to` narrow it the same way — and each receipt
is filed under the blueprint that *owns* its edge, so a marked entailed edge
suppresses a later direct run of that blueprint too.

Marking is scoped to *pending* edges. An edge that already has a receipt is left
alone rather than having its timestamp rewritten, which makes repeated marking a
no-op and marking a wider window purely additive. The outcome recorded is
`applied`, indistinguishable from an earned receipt, so `--rerun` clears a
mistaken marking exactly as it clears any other applied receipt.

Two combinations are refused rather than resolved by precedence, both before the
blueprint is discovered and before anything is read or written: `--mark-applied`
with `--rerun` (which would ask to both skip and force the same edges), and
`--mark-applied` with the parent `--debug` (which would ask a dry run to write
receipts). See
[ADR 0011](../adr/0011-a-migration-receipt-asserts-a-claim-about-the-project.md)
for what a receipt asserts.

### Inferring the version window

Either end of the window may be omitted, and the two ends are resolved
independently — one may be typed while the other is inferred.

| End | Explicit | Inferred from | If neither |
|-----|----------|---------------|------------|
| `--to` | The flag wins | The blueprint's declared `versionProbe`, a command it supplies that prints the version this project depends on | Refuses, naming `--to` and the probe the author could declare |
| `--from` | The flag wins | The highest `to` version among this project's **applied** receipts for that blueprint | Refuses, explaining that this project has no recorded migration to start from |

The two ends deliberately draw on different sources. The probe reads how far the
*dependency* has been bumped; the receipt ledger records how far the *source* has
been migrated. That matches the normal workflow — bump the dependency, then
migrate the source up to it — so at the moment you run the command the lockfile
already names the target.

A receipt recorded as **not applicable** does not count toward the inferred
start. It records that an edge was considered and skipped, which says nothing
about how far the source has been carried.

An inferred end is always reported with the source it came from, verbose or not;
a window silently off by one release would run the wrong sessions against your
source. An end you typed is reported only under `--verbose`, so invocations that
name both versions print exactly what they always did.

```text
Version window: 2.0.0 -> 3.0.0
  --from 2.0.0  [receipt: my-library 1.0.0 -> 2.0.0, applied 2026-08-02]
  --to   3.0.0  [probe: cat .library-version]
```

A probe that exits nonzero, or prints something that is not a dotted numeric
version, is a warning rather than a failure: its command, exit code, and output
are printed, and the command falls through to requiring `--to`. You did not write
the probe and still have the flag.

```sh
seihou agent migrate my-library
seihou agent migrate my-library --from 1.0.0 --to 3.0.0
seihou agent --debug migrate my-library --from 1.0.0 --to 3.0.0
```

For this subcommand, parent `--debug` is a true dry run: it prints every pending
prompt in order, never contacts a provider, and never writes a migration receipt.
It does run the version probe — a probe is required to be read-only, and skipping
it would make debug output diverge from a real run in exactly the way that
matters, since the probe decides which edges are shown. Every step is labelled
with the blueprint that owns it, and an entailed step also says which edge pulled
it in:

```text
Blueprint migrations for keiro-upgrade: 2.4.0 -> 3.0.0
===== [1/2] kiroku-upgrade 1.9.0 -> 2.0.0 (entailed by keiro-upgrade 2.4.0 -> 3.0.0) =====
===== [2/2] keiro-upgrade 2.4.0 -> 3.0.0 =====
```

A receipt records that an edge has been dealt with — by a provider interaction
that returned, or by `--mark-applied` — rather than package-manager verification.
See [Blueprint Migrations](../user/blueprint-migrations.md) for the full workflow
and [Agent-Driven Blueprints](../user/blueprints.md#library-upgrade-migrations)
for the Dhall shape.

## Artifact Guard

`agent run` and `agent migrate` both check the artifacts they are about to use
against what `.seihou/manifest.json` records, and refuse before writing anything
when the local copy is older than, or came from a different repository than, the
project records. This is the same refusal `seihou run` and `seihou migrate`
apply, extended to the agent path; see
[ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md).

`agent run` checks the blueprint and every module its baseline would generate
from. `agent migrate` checks blueprints only, because migration mode applies no
baselines: the blueprint you named, before it plans a single edge, and then every
further blueprint the plan reaches through `entails`, once discovery has found
them and still before any session starts. Neither command checks an artifact it
will not touch: a stale module elsewhere in the project cannot block an unrelated
blueprint, and a cohort member no selected edge entails is never consulted.

A refusal happens before the baseline is applied and before any receipt is
written, so the working tree and the manifest are left byte-identical. The fix
is `seihou upgrade <name>` for a stale copy, or reinstalling from the URL the
manifest records for a substituted one; the message prints the exact command.
`--allow-downgrade` proceeds anyway and prints what it overrode.

Parent `--debug` changes this for `agent migrate` only, because `--debug` means
different things to the two subcommands. It is a true dry run for `agent
migrate`, which writes nothing, so no check runs and a prompt can be inspected
on any machine. `--mark-applied` does not reach the guard by a different route:
it is refused alongside `--debug`, and on its own it runs the guard in full
before recording anything, because a receipt written against a substituted
blueprint would match nothing. It is not a dry run for `agent run`, which still applies the
baseline and still records provenance under `--debug`, so the check runs there
regardless.

## Requirements

At least one configured provider must be usable for non-debug runs. The CLI providers require their local binaries and login state. API providers require their API keys. Debug runs do not contact providers and are safe to use for prompt inspection:

```sh
seihou agent --debug --provider claude-cli assist "inspect this prompt"
seihou agent --debug --provider codex-cli bootstrap --repo "inspect this prompt"
seihou agent --debug --provider openai setup "inspect this prompt"
```

## First-Class Prompts

Use `seihou prompt run PROMPT` for reusable agent-session templates that do not
apply blueprint baselines or record applied-blueprint provenance:

```sh
seihou prompt run review-changes --debug
seihou prompt run review-changes --provider codex-cli
```

See [`seihou prompt`](prompt.md) and [First-Class Prompts](../user/prompts.md).
