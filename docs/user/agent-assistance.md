# AI Agent Assistance

`seihou agent` renders Seihou-aware prompts and sends them to a configured AI
provider. Use it to author modules, bootstrap template repositories, guide
project setup, or run agent-driven blueprints. `seihou prompt` uses the same
provider configuration for reusable prompt artifacts that are not project
scaffolds.

CLI providers start interactive local tools. API providers send one rendered
prompt as a completion request and print one response.

## Providers

| Provider | Requirement | Behavior |
|----------|-------------|----------|
| `claude-cli` | Local `claude` binary on `PATH` and authenticated | Starts interactive Claude Code by default; `--batch` uses `claude -p`. |
| `codex-cli` | Local `codex` binary on `PATH` and authenticated | Starts interactive Codex by default; `--batch` uses `codex exec` with workspace-write sandboxing. |
| `anthropic` | `ANTHROPIC_API_KEY` or `ANTHROPIC_KEY` | Calls the Anthropic Messages API directly (non-interactive). |
| `openai` | `OPENAI_API_KEY` or `OPENAI_KEY` | Calls the OpenAI Chat Completions API directly (non-interactive). |

The default provider is `claude-cli`. When you configure no model, Seihou pins a
deterministic default per provider so it always passes an explicit model to the
local CLI rather than inheriting whatever model the ambient `claude` or `codex`
session happens to have active: `claude-cli` defaults to `claude-opus-4-8` and
`codex-cli` defaults to `gpt-5.6-terra`. This keeps CLI runs reproducible and
avoids accidentally launching a different, possibly token-hungry model that
another session selected. Override either default with a `--model` flag or an
`agent.model` / `agent.<command>.model` config key.

## Selecting a provider

Provider and model flags may appear on either the parent `agent` command or
the subcommand:

```sh
seihou agent --provider codex-cli --model gpt-5 assist "create a module"
seihou agent assist --provider codex-cli --model gpt-5 "create a module"
```

For persistent defaults:

```sh
seihou config set agent.provider codex-cli --global
seihou config set agent.model gpt-5 --global
```

### Per-command provider and model

Each agent command can use a different provider and model. Set
`agent.<command>.provider` or `agent.<command>.model`, where `<command>` is one
of `assist`, `bootstrap`, `setup`, `run`, or `prompt-run`. A per-command key
overrides the shared `agent.provider` / `agent.model` default for that command
only; commands without a per-command key keep using the shared default.

```sh
# Shared default for every agent command:
seihou config set agent.model claude-sonnet-5 --global

# Fast, cheap model just for `assist`:
seihou config set agent.assist.provider codex-cli --global
seihou config set agent.assist.model gpt-5-mini --global

# A strong model just for `run`, in this project only:
seihou config set agent.run.model claude-opus-4-8
```

Configuration is hierarchical: a project's local `.seihou/config.dhall`
overrides the user's global `~/.config/seihou/config.dhall`. A local value wins
over any global value even when the global value is more specific — a local
`agent.model` beats a global `agent.run.model`. Within a single scope, the more
specific per-command key wins over the shared default key.

Resolution order is (highest precedence first):

1. Subcommand `--provider` / `--model`
2. Parent `--provider` / `--model`
3. `SEIHOU_AGENT_PROVIDER` / `SEIHOU_AGENT_MODEL`
4. The blueprint's or prompt's own `launch.provider` / `launch.model` declaration
5. Local `agent.<command>.provider` / `agent.<command>.model`
6. Local `agent.provider` / `agent.model`
7. Global `agent.<command>.provider` / `agent.<command>.model`
8. Global `agent.provider` / `agent.model`
9. Built-in defaults: provider `claude-cli`; model pinned per provider (`claude-cli` → `claude-opus-4-8`, `codex-cli` → `gpt-5.6-terra`)

Tier 4 applies only to the commands that load an artifact — `seihou agent run`,
`seihou agent migrate`, and `seihou prompt run`. A blueprint or prompt author
can declare the agent their prompt was written for, and that declaration
outranks every configured default while still losing to a flag or environment
variable set for one invocation. See
[Blueprints](blueprints.md#launch-settings) and
[Prompts](prompts.md#launch-settings), and
[Configuration and variables](config-and-variables.md#agent-provider-defaults)
for the same chain including effort.

### Reasoning effort

Each command can also configure the model's **reasoning effort** — how hard the
model thinks before acting — with the same hierarchy. Effort is one of six
levels: `minimal`, `low`, `medium`, `high`, `xhigh`, `max`. Use the shared key
`agent.effort`, the per-command key `agent.<command>.effort`, the environment
variable `SEIHOU_AGENT_EFFORT`, or the `--effort LEVEL` flag (on the parent
`agent` command, any subcommand, or `seihou prompt run`).

```sh
seihou config set agent.effort medium --global   # shared default
seihou config set agent.run.effort max            # blueprint runs think hard
seihou prompt run review-changes --effort low     # one-off, cheaper
```

For the local CLI providers this becomes `claude --effort <level>` /
`codex -c model_reasoning_effort=<level>`; for the API providers it maps to the
provider's native reasoning-effort setting. Unlike the model, effort has **no**
built-in default: when unset, Seihou passes no effort flag and the CLI/provider
uses its own default. Higher effort generally means better answers but more
latency and token cost. The full precedence chain is identical to provider and
model, with `agent.<command>.effort` / `agent.effort` occupying the same tiers.

### Inspecting resolved configuration

`seihou agent config` prints the provider, model, and reasoning effort each
agent command resolves to, labelling the source of every value so you can see
exactly why a command uses what it does:

```text
$ seihou agent config
Resolved agent provider, model, effort, and trace per command
(highest-precedence source wins; see precedence list below)

  assist      provider  codex-cli        [global: agent.assist.provider]
              model     gpt-5-mini       [global: agent.assist.model]
              effort    high             [global: agent.effort]
              trace     off              [built-in default]
  run         provider  claude-cli       [built-in default]
              model     claude-opus-4-8  [local: agent.run.model]
              effort    max              [local: agent.run.effort]
              trace     file             [local: agent.run.trace]
  prompt run  provider  claude-cli       [built-in default]
              model     claude-opus-4-8  [built-in default]
              effort    (default)        [built-in default]
              trace     off              [built-in default]
```

The command is read-only; it never changes configuration. Set values with
`seihou config set agent.<command>.{provider,model,effort,trace} ...`. Because
it reflects the live environment, `SEIHOU_AGENT_*` variables set in your shell
also appear in the resolved output. An `effort` of `(default)` means none is
configured, so the CLI/provider picks its own.

## Tracing model calls

When a model call is slow, expensive, or fails, tracing tells you what actually
happened. With tracing on, Seihou records two events per call — one when the
call starts and one when it finishes or fails — each carrying the provider, the
model, the elapsed milliseconds, and, where the provider reports them, the input
and output token counts and the dollar cost. A failed call carries the
provider's error message instead.

Tracing is **off by default**. With it off, nothing is written, nothing extra is
printed, and no file is created.

### Turning it on

`agent.trace` takes one of four values:

| Value | Effect |
|-------|--------|
| `off` | Record nothing. The default. |
| `file` | Append one JSON object per line to the trace file. |
| `stdout` | Print one human-readable line per event to stdout. |
| `stderr` | Print one human-readable line per event to stderr. |

Set it with the shared key `agent.trace`, the per-command key
`agent.<command>.trace`, the environment variable `SEIHOU_AGENT_TRACE`, or the
`--trace SETTING` flag (on the parent `agent` command, any subcommand, or
`seihou prompt run`). The precedence chain is the one provider, model, and
effort already use.

```sh
seihou config set agent.trace file        # record every agent command in this project
seihou config set agent.run.trace file    # ...or only blueprint runs
seihou agent assist "add a health check" --trace stderr   # watch one run go by
```

Prefer `stderr` over `stdout` for watching a run: several commands print
assistant text to stdout, and `--debug` prints the rendered prompt there, so
trace lines on stdout would corrupt output you pipe. `stdout` exists for the
cases where you want traces *in* a pipeline.

### The trace file

The file sink writes to `.seihou/trace.jsonl` inside the project, beside the
manifest and the project config. Point it somewhere else with `agent.tracePath`:

```sh
seihou config set agent.tracePath /tmp/seihou-trace.jsonl
```

`agent.tracePath` is free-form and deliberately simple: local config beats
global config, and that is the whole story. It has no flag, no environment
variable, and no per-command variant.

The file is **JSON Lines** — one complete JSON object per line — and Seihou
*appends* to it, so it accumulates history across runs rather than being
replaced. Delete it when you want a clean slate.

```text
$ seihou config set agent.trace file
$ seihou agent assist "add a health check module"
... normal assistant output ...

$ cat .seihou/trace.jsonl
{"kind":"call_started","eventId":"a1b2c3","timestamp":"2026-07-27T18:04:11Z","provider":"anthropic","model":"claude-sonnet-4-6","maxTokens":8192,"promptSummary":"add a health check module"}
{"kind":"call_finished","eventId":"a1b2c3","timestamp":"2026-07-27T18:04:19Z","provider":"anthropic","model":"claude-sonnet-4-6","latencyMs":7913,"inputTokens":4211,"outputTokens":880,"usd":0.0264}
```

The `kind` tag is `call_started`, `call_finished`, or `call_failed`, and
`eventId` correlates a start with its matching finish or fail. That makes
ordinary tools enough to answer questions:

```sh
# What did this project cost?
jq -s 'map(select(.kind == "call_finished") | .usd) | add' .seihou/trace.jsonl

# What failed, and why?
jq -r 'select(.kind == "call_failed") | "\(.model): \(.errorMessage)"' .seihou/trace.jsonl

# Slowest calls first.
jq -s 'map(select(.kind == "call_finished")) | sort_by(-.latencyMs) | .[0:5]' .seihou/trace.jsonl
```

Token counts and cost are omitted when the provider does not report them. The
two local CLI providers (`claude-cli`, `codex-cli`) are subscription-based and
report neither, so their `call_finished` events carry `latencyMs` but no
`inputTokens`, `outputTokens`, or `usd`. Use an API provider (`anthropic`,
`openai`) if you need cost accounting.

### What tracing does not cover

**Interactive sessions are not traced.** When `seihou agent run` hands off to an
interactive `claude` or `codex` session, it launches that CLI as a subprocess
rather than making a request Seihou can time or price — there is no call for
Baikai to observe, so no events are produced. Tracing covers batch runs
(`--batch`, or automatically when stdin is not a terminal) and the API providers.
If a run produces no trace events, check whether it took the interactive path.

**Traces record calls, not arguments.** An event names the provider, model,
latency, tokens, and cost. It does not record the reasoning effort requested or
the command line a spawned CLI was invoked with, so tracing does not replace
looking at what Seihou actually passed to `claude` or `codex`. Use `--debug` to
see the rendered prompt.

## Discovering models

List the Anthropic and OpenAI models known to the Baikai catalog compiled into
Seihou:

```sh
seihou agent models
seihou agent models --provider openai
seihou agent --provider claude-cli models
```

The API and local CLI providers share catalog families:

| Catalog family | Compatible Seihou providers |
|----------------|-----------------------------|
| Anthropic | `anthropic`, `claude-cli` |
| OpenAI | `openai`, `codex-cli` |

An unfiltered listing prints each model once and names both compatible
providers. A provider filter may appear before or after `models`. The command
uses only compiled catalog data, so it requires no credentials or network
access and does not read configured provider defaults.

The list is advisory. Provider-native aliases such as `sonnet` and custom model
identifiers remain valid values for `--model` even when they are not listed.
Seihou does not use the catalog to validate live availability, and provider
offerings may change independently of a Seihou release.

Agent provider settings are separate from module variable resolution.
Blueprint variables still use the normal variable precedence chain before the
blueprint prompt is rendered.

First-class prompt variables use the same variable precedence chain, then run
any command-derived variables declared by `prompt.dhall` before the final prompt
body is rendered.

## Debug mode

`--debug` prints the resolved prompt and exits without contacting a provider:

```sh
seihou agent --debug assist "inspect this module"
seihou agent --debug --provider openai setup "inspect this prompt"
seihou agent --debug run api-service --var project.name=payments
```

Use debug mode to audit what Seihou will send, test provider selection, and
smoke-check prompts in CI without opening an agent session. A blueprint debug
run still records applied-blueprint provenance in `.seihou/manifest.json`, so
use a disposable project when the manifest must remain untouched.

## Agent commands

### Assist

```sh
seihou agent assist "add a migration to this module"
```

Use `assist` inside an existing Seihou module or template repository. The
prompt includes the current directory, available modules, manifest state, and
schema guidance for module authoring.

### Bootstrap

```sh
seihou agent bootstrap "create a Haskell service template"
seihou agent bootstrap --repo "create a team template registry"
```

Use `bootstrap` when starting a new module or registry from scratch. `--repo`
targets a multi-item repository with `seihou-registry.dhall`.

### Setup

```sh
seihou agent setup "configure this repo with our Haskell template"
```

Use `setup` in a consumer project. The prompt guides the agent through
selecting modules, configuring variables and context, previewing the run,
verifying output, and committing changes when appropriate.

### Run

```sh
seihou agent run api-service "tailor this for payments"
```

Use `run` for blueprints. The runner resolves blueprint variables, optionally
applies baseline modules, renders the blueprint prompt, and records the
successful run in `.seihou/manifest.json`. For interactive `claude-cli` and
`codex-cli` sessions, it mounts the blueprint's existing `files/` directory and
prints the absolute path so the agent can read declared references directly.
API providers instead receive ask-the-user fallback guidance.

Use `--batch` when a blueprint must run without an interactive terminal, such
as from a module migration command:

```sh
seihou agent run api-service --batch
```

Seihou also selects batch mode automatically when stdin is not a terminal.
Batch CLI runs preserve the working directory, blueprint tool policy, and
mounted references while using `claude -p` or `codex exec`. Explicit `--batch`
is recommended in reusable automation because it documents the intended launch
mode.

Blueprint `allowedTools` entries are added to the base runner tools with
duplicates removed. Claude Code receives the effective list through
`--allowedTools`. Codex continues to use its workspace-write sandbox and
on-request approval policy because it has no equivalent per-tool allow-list.

See [Agent-Driven Blueprints](blueprints.md) for blueprint authoring and
publishing details.

## First-Class Prompts

```sh
seihou prompt run review-changes --debug
seihou prompt run review-changes --provider codex-cli
```

Use `seihou prompt run` for reusable agent-session templates such as code
review, release preparation, planning, or repository inspection. Prompts can
resolve typed variables from config, fill placeholders from local commands, and
include reference files. They do not apply blueprint baselines and do not record
applied-blueprint provenance in the manifest.

See [First-Class Prompts](prompts.md) for prompt authoring and publishing
details.

## Seihou Kit

`seihou kit` installs curated Claude Code and Codex skills and subagents from
the `seihou-kit` repository:

```sh
seihou kit list
seihou kit install review-pr
seihou kit install code-reviewer --project
seihou kit update
seihou kit status
```

User-scope installs are available across projects. Project-scope installs are
written into the current repository and can be checked in.

Kit installs provider-native copies for both Claude Code and Codex:

| Scope | Claude Code | Codex |
|-------|-------------|-------|
| User | `~/.config/seihou/agents/.claude/...` | `~/.agents/skills/` and `~/.codex/agents/` |
| Project | `.seihou/agents/.claude/...` | `.agents/skills/` and `.codex/agents/` |

When `seihou agent --provider codex-cli ...` launches from a project,
project-scoped Codex skills and custom agents are available through Codex's
native discovery paths.

## See also

- [Configuration and Variable Resolution](config-and-variables.md#agent-provider-defaults)
- [Agent-Driven Blueprints](blueprints.md)
- [Blueprint Migrations](blueprint-migrations.md)
- [First-Class Prompts](prompts.md)
- [`seihou agent`](../cli/agent.md)
- [`seihou prompt`](../cli/prompt.md)
- [`seihou kit`](../cli/kit.md)
