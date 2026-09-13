---
id: 89
slug: add-configurable-opentelemetry-tracing-to-seihou
title: "Add configurable OpenTelemetry tracing to Seihou"
kind: exec-plan
created_at: 2026-09-13T16:43:31Z
intention: "intention_01m2dtcxv4e9gbs6h9j8aez5yw"
provenance:
  created_by:
    model: "gpt-5.6-sol"
    harness: "codex-cli"
    at: 2026-09-13T16:43:31Z
---

# Add configurable OpenTelemetry tracing to Seihou

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this change, a Seihou binary built with OpenTelemetry support can export one trace for a
`seihou` invocation. The trace has a stable command root, useful phase spans for `seihou update`,
and child model-call or interactive-session spans for every configured agent provider, including
both Claude and Codex. A user can then answer “where did this update spend its time?” or “did the
Codex invocation start, finish, and call the model?” in an OTLP-compatible backend such as the
VictoriaTraces instance behind `traces.localhost`.

This capability is opt-in twice. The Cabal flag `otel` is off by default so downstream builders
need not accept the OpenTelemetry dependency closure. The repository's Nix package enables that
flag so the distributed `seihou` executable is capable, but runtime export still defaults to
`off`. A user explicitly selects `telemetry.traces = "otel"` in local/global Seihou config or sets
`SEIHOU_TELEMETRY_TRACES=otel`; only then does Seihou initialize an SDK. Merely inheriting
`OTEL_*` variables must never turn Seihou tracing on. This is important on machines where those
variables already belong to another application.

The existing `agent.trace = off|file|stdout|stderr` feature remains independent. It is a local
Baikai event sink, whereas `telemetry.traces` controls process-wide OTel spans. When both are on,
the Baikai event stream fans out to both sinks. The OTel sink uses
`mori://shinzui/baikai/packages/baikai-trace-otel`, leaves prompt summaries disabled, and parents
each `baikai.call` span under the active Seihou command span.

The user-visible setup is:

    seihou config set telemetry.traces otel --global
    seihou config set telemetry.serviceName seihou --global

    export OTEL_TRACES_EXPORTER=otlp
    export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:10428/insert/opentelemetry
    export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf

    seihou update --dry-run
    SEIHOU_AGENT_PROVIDER=codex-cli seihou agent assist "summarize the pending work"

The first command yields a `seihou.update` trace with plan/apply phase spans; the second yields a
`seihou.agent.assist` trace containing a `baikai.call` child span. An interactive
`seihou agent run` yields a provider-neutral `seihou.agent.session` child span around either the
Claude or Codex subprocess. Detailed spans produced *inside* the provider's terminal UI remain a
separate, provider-owned opt-in: the user guide will give verified Claude Code environment and
Codex `[otel]` recipes, but Seihou will not silently rewrite either tool's telemetry settings or
put collector credentials in process arguments.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Created Mina intention `intention_01m2dtcxv4e9gbs6h9j8aez5yw` and attached it to this
      ExecPlan (2026-09-13).
- [x] Re-read the current Seihou command/configuration paths, agent batch and interactive paths,
      update transaction path, trace tests, architecture notes, and all local ADR headings
      (2026-09-13).
- [x] Located Baikai through Mori, read the current OTel sink source, and verified
      `baikai-trace-otel` 0.4.0.1 against both Hackage and the upstream release tag. Confirmed the
      current shared `mori://shinzui/haskell-nix` pin already packages the required OTel family;
      verified each direct OTel dependency as Hackage 1.0.0.0 with a matching upstream tag
      (2026-09-13).
- [x] Checked the installed Claude Code and Codex CLI telemetry surfaces against their official
      documentation and recorded why provider-native tracing is documented rather than injected
      by Seihou (2026-09-13).
- [ ] Milestone 1: add the opt-in build flag and runtime configuration resolver, with both
      flag-off and flag-on tests.
- [ ] Milestone 2: own the SDK lifecycle at the CLI boundary and emit stable command root spans.
- [ ] Milestone 3: add update planning/application phase spans without changing transaction
      behavior.
- [ ] Milestone 4: compose Baikai OTel call spans and add provider-neutral Claude/Codex
      interactive-session spans.
- [ ] Milestone 5: complete automated and live-collector validation, update user/developer docs,
      and distill the durable decisions into an ADR.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **The packaging blocker recorded by plan 74 is gone (2026-09-13).**
  `docs/plans/74-wire-baikai-call-tracing-into-seihou.md` and the “Adopting
  `baikai-trace-otel`” architecture note describe version 0.3.0.2 as absent from the shared Nix
  registry. Mori now identifies `mori://shinzui/baikai/packages/baikai-trace-otel`; Hackage and
  the upstream tag both identify 0.4.0.1 as current; and the Seihou-pinned revision of
  `mori://shinzui/haskell-nix` contains that version plus
  `mori://iand675/hs-opentelemetry/packages/hs-opentelemetry-api`,
  `mori://iand675/hs-opentelemetry/packages/hs-opentelemetry-sdk`,
  `mori://iand675/hs-opentelemetry/packages/hs-opentelemetry-exporter-otlp`, and
  `mori://iand675/hs-opentelemetry/packages/hs-opentelemetry-semantic-conventions` 1.40.

- **The direct OTel bounds have authoritative release evidence (2026-09-13).**
  The Hackage preferred-version pages for
  `mori://iand675/hs-opentelemetry/packages/hs-opentelemetry-api`,
  `mori://iand675/hs-opentelemetry/packages/hs-opentelemetry-sdk`,
  `mori://iand675/hs-opentelemetry/packages/hs-opentelemetry-exporter-otlp`, and
  `mori://iand675/hs-opentelemetry/packages/hs-opentelemetry-exporter-in-memory` each report
  1.0.0.0. The upstream `iand675/hs-opentelemetry` repository carries a corresponding 1.0.0.0
  package tag for each, so the planned `>=1.0 && <1.1` bounds are grounded in released artifacts
  rather than only the local corpus.

- **Baikai's OTel sink does not automatically inherit the command span (2026-09-13).**
  `otelSink` creates roots unless `defaultOtelSinkOptions.parentContext` is replaced. This is
  intentional: the sink fold drains on a worker thread that cannot see the caller's thread-local
  context. Seihou must capture the current context when it constructs the sink and use
  `otelSinkWith`; otherwise one CLI invocation appears as unrelated traces.

- **`seihou update` does not invoke an agent (2026-09-13).**
  `Seihou.CLI.Update` performs recovery, candidate staging, planning, reconciliation, migrations,
  declared commands, publication, and manifest commit directly. Adding only an OTel branch to
  `Seihou.CLI.AgentTrace.traceSinkFor` would therefore produce no update spans. The SDK lifecycle
  and command root belong above `dispatch`, with explicit update phase spans below it.

- **Agent execution has two observability paths (2026-09-13).**
  Batch/API requests pass through `Seihou.CLI.AgentCompletion` and
  `Baikai.Trace.withTrace`, while terminal sessions pass through
  `Seihou.CLI.AgentLaunchExec` and launch a long-lived child process. The Baikai OTel adapter
  covers only the first. Codex support therefore requires both a Baikai call-span test for
  `codex-cli` batch mode and a provider-neutral subprocess span test for interactive Codex;
  Claude needs the same pair.

- **The ambient service name is unsafe on the motivating machine (2026-09-13).**
  The interactive shell already exports `OTEL_SERVICE_NAME=rei`. If Seihou initializes the SDK
  without resolving its own service name, its spans are mislabeled as Rei. The runtime must use
  `telemetry.serviceName` / `SEIHOU_TELEMETRY_SERVICE_NAME`, defaulting to `seihou`, during SDK
  initialization and restore the prior process environment afterward.

- **Native provider tracing has independent privacy and configuration contracts
  (2026-09-13).** Claude Code tracing is beta and requires
  `CLAUDE_CODE_ENABLE_TELEMETRY=1`, `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`, and an
  `OTEL_TRACES_EXPORTER`; interactive sessions ignore inbound `TRACEPARENT`. Codex uses its own
  `[otel]` configuration, with separate log, metric, and trace exporters. Synthesizing Codex
  config from `OTEL_*` would either discard options or place header credentials in argv. Seihou
  should trace its boundary consistently and document native opt-in instead of changing vendor
  settings behind a general Seihou switch.


## Decision Log

Record every decision made while working on the plan.

- Decision: Runtime OTel export is gated only by `telemetry.traces = "otel"` or
  `SEIHOU_TELEMETRY_TRACES=otel`; its built-in value is `off`.
  Rationale: Standard `OTEL_*` variables configure the selected SDK/exporter but do not express
  consent for every CLI in an inherited shell to emit. This keeps an unconfigured Seihou run
  behaviorally unchanged.
  Date: 2026-09-13

- Decision: Add a manual Cabal flag named `otel`, default it to `False`, and enable it in
  `nix/haskell-overlay.nix` for the repository's packaged executable.
  Rationale: The shipped executable can be enabled at runtime without a custom rebuild, while
  Hackage/downstream builders can omit the OTel dependency closure. A flag-off binary gives a
  clear configuration error if asked for `otel`; it never silently discards requested traces.
  Date: 2026-09-13

- Decision: Introduce Seihou-wide `telemetry.traces` rather than adding `otel` to
  `TraceSetting` / `agent.trace`.
  Rationale: `agent.trace` selects a destination for Baikai model-call events and cannot observe
  `seihou update` or command phases. The two settings can be enabled independently and composed
  when both apply.
  Date: 2026-09-13

- Decision: Configuration precedence is environment, project-local config, global config,
  built-in default. The keys are `telemetry.traces` and `telemetry.serviceName`; the environment
  names are `SEIHOU_TELEMETRY_TRACES` and `SEIHOU_TELEMETRY_SERVICE_NAME`.
  Rationale: This follows the useful subset of Seihou's existing agent resolution pattern,
  provides a one-command override without expanding every command parser, and lets a project
  override a user's global default. Namespace/context config is not loaded at the top-level CLI
  boundary and is therefore deliberately excluded.
  Date: 2026-09-13

- Decision: OTel payloads are content-free by default.
  Rationale: Command names, phase names, provider/model identifiers, exit status, duration,
  token usage, and cost are sufficient for the stated diagnostic goal. The implementation uses
  `defaultOtelSinkOptions { includePromptSummary = False }` and does not attach prompts, argv,
  filesystem paths, generated content, tool input, or tool output.
  Date: 2026-09-13

- Decision: Seihou emits an interactive-session span for both Codex and Claude but does not
  activate either provider's native telemetry.
  Rationale: This gives all configured providers the same guaranteed Seihou observability.
  Native telemetry is versioned, has separate privacy switches, and may require credentials that
  must not be copied into process arguments. Verified provider-specific recipes belong in the
  user guide and remain an explicit second opt-in.
  Date: 2026-09-13

- Decision: Explicit configuration errors are fatal before dispatch; collector/export failures
  are best effort and cannot change the command's exit status.
  Rationale: A misspelled enum or a flag-off binary asked to export is actionable user error.
  Losing an observability backend during an update must not turn a valid update into a failed or
  partially rolled-back transaction. SDK diagnostics may go to stderr, but transaction and agent
  semantics remain authoritative.
  Date: 2026-09-13


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

Seihou is a multi-package Haskell CLI. `seihou-cli/src-exe/Main.hs` parses a `Command` and calls
`dispatch`; the special `extension run` path is recognized from raw arguments before the normal
parser. This entry point is the only place that can reliably bracket every command with one SDK
lifecycle. Parser failures and `--version` terminate inside `optparse-applicative` before
dispatch and are not in scope for tracing.

Configuration is stored as a flat `Map Text Text` in project-local `.seihou/config.dhall` or the
XDG global `config.dhall`. `Seihou.Effect.ConfigReader` and
`Seihou.Effect.ConfigReaderInterp` read those maps. `Seihou.CLI.AgentConfig` is the closest
resolver example: it separates pure precedence/validation from IO loading and reports the source
of each winning value. The new telemetry resolver should follow that split without coupling
telemetry to an agent command.

Local agent-call tracing already exists. `Seihou.CLI.AgentCompletion.TraceSetting` accepts
`off`, `file`, `stdout`, or `stderr`; `Seihou.CLI.AgentTrace.traceSinkForConfig` builds the
selected `Baikai.Trace.Sink.TraceSink`; and `runAgentCompletionWith` passes it to
`Baikai.Trace.withTrace`. `docs/plans/74-wire-baikai-call-tracing-into-seihou.md` records the
original implementation and deliberately deferred OTel. `docs/user/agent-assistance.md`
correctly warns that interactive sessions do not generate these Baikai call events.

The OTel adapter now available as `mori://shinzui/baikai/packages/baikai-trace-otel` exports:

    otelSink :: OpenTelemetry.Trace.Core.Tracer -> TraceSink

    otelSinkWith
      :: OpenTelemetry.Trace.Core.Tracer
      -> OtelSinkOptions
      -> TraceSink

    defaultOtelSinkOptions :: OtelSinkOptions

The option needed here is `parentContext :: Maybe OpenTelemetry.Context.Context`. The current
released adapter is 0.4.0.1 and is compatible with Seihou's Baikai 0.7 family. The shared package
registry is `mori://shinzui/haskell-nix`; its project-relative
`packages/first-party-lock.json` at Seihou's pinned revision already supplies the package and OTel
dependencies. That file does not yet have a more specific Mori artifact URI.

`mori://shinzui/mina` provides a useful lifecycle precedent in the project-relative file
`mina-core/src/Mina/Trace.hs` (an artifact-level URI is not currently registered): initialize one
global tracer provider, make a named tracer, bracket the top-level action, and shut the provider
down so short-lived CLI spans flush. Seihou differs in one important way: Mina auto-enables from
`OTEL_*`, while this plan requires a Seihou-specific opt-in.

`Seihou.CLI.Update` separates `withProjectUpdate` / `planProjectUpdateIn` from
`applyProjectUpdate` / `applyAcceptedPlan`. Planning recovers state, reads the manifest, stages
candidate sources, plans applications and migrations, materializes a staged project, reconciles,
and captures a snapshot. Application validates the snapshot, opens a recoverable transaction,
runs migrations, reapplies reconciliation, executes declared commands, publishes candidates,
writes the manifest, and commits or aborts. Phase spans must surround these existing boundaries;
they must not reorder effects or add new recovery behavior.

Agent execution has two paths. `Seihou.CLI.AgentCompletion` handles API and non-TTY/batch CLI
providers. `Seihou.CLI.AgentLaunchExec` handles interactive Claude and Codex subprocesses through
Baikai. `AgentTraceE2ESpec`, `AgentMigrateE2ESpec`, and `AgentGuardE2ESpec` already show how to put
a fake provider binary on `PATH` and inspect its argv without making a live model call.

The local ADR scan found ADRs 0001 through 0011. They govern manifest identity, artifact
freshness, update state, migration semantics, commands, and generated documentation; none decides
telemetry, observability, or optional dependencies. No existing ADR constrains this design.
Because opt-in semantics, privacy, failure isolation, and the process-wide SDK lifecycle are
durable cross-cutting decisions, Milestone 5 creates the next available ADR (expected 0012)
rather than amending an unrelated record.


## Plan of Work

### Milestone 1 — Optional package capability and runtime configuration

Add a manual `otel` flag to `seihou-cli/seihou-cli.cabal`, defaulting to `False`. Under the flag,
the internal library depends on `baikai-trace-otel ^>=0.4.0.1`,
`hs-opentelemetry-api >=1.0 && <1.1`, `hs-opentelemetry-sdk >=1.0 && <1.1`, and
`hs-opentelemetry-exporter-otlp >=1.0 && <1.1`, and defines a private CPP symbol used only inside
the telemetry runtime module. The OTel-enabled test stanza adds
`hs-opentelemetry-exporter-in-memory >=1.0 && <1.1`. These are the packages registered as
`mori://iand675/hs-opentelemetry/packages/hs-opentelemetry-api`,
`mori://iand675/hs-opentelemetry/packages/hs-opentelemetry-sdk`,
`mori://iand675/hs-opentelemetry/packages/hs-opentelemetry-exporter-otlp`, and
`mori://iand675/hs-opentelemetry/packages/hs-opentelemetry-exporter-in-memory`. Add `-fotel` to
the existing Seihou CLI `configureFlags` in `nix/haskell-overlay.nix`. Do not add local pins: the
current shared registry already owns them.

Create `seihou-cli/src/Seihou/CLI/Telemetry/Config.hs`. It owns the pure vocabulary, precedence,
rendering, and IO loader for `telemetry.traces` and `telemetry.serviceName`. The trace enum accepts
only `off` and `otel`, case-insensitively after trimming. An empty service name is invalid.
`SEIHOU_TELEMETRY_TRACES` and `SEIHOU_TELEMETRY_SERVICE_NAME` win over project-local and global
keys, which win over `off` and `seihou`. Do not let `OTEL_TRACES_EXPORTER`, an endpoint, or
`OTEL_SERVICE_NAME` participate in enablement.

Add `seihou-cli/test/Seihou/CLI/TelemetryConfigSpec.hs` and register it in the test `Main`. Cover
every precedence tier, blank values, invalid enum values, the default-off case with populated
`OTEL_*` variables, and the flag-off “this binary was built without OTel support” diagnostic.
At this milestone, no span is emitted. Acceptance is that
`cabal test seihou-cli-test -f-otel --test-options='--pattern Telemetry'` and
`cabal test seihou-cli-test -fotel --test-options='--pattern Telemetry'` pass, and the Nix
derivation evaluates with `-fotel`.

### Milestone 2 — SDK lifecycle and command roots

Create `seihou-cli/src/Seihou/CLI/Telemetry.hs` as the stable, flag-independent facade. Its OTel
branch may use CPP internally, but callers must not. It loads no configuration itself; it accepts
the resolved config, brackets `initializeGlobalTracerProvider`, makes a tracer named
`seihou-cli`, publishes the active runtime only for the bracket's duration, calls
`forceFlushTracerProvider` after the command span closes, and always calls
`shutdownTracerProvider` on exit. When configuration
is `off`, it runs the supplied action directly and initializes nothing.

Before SDK initialization, temporarily set `OTEL_SERVICE_NAME` from the resolved Seihou service
name and restore its exact prior value after shutdown, including the unset case. This prevents a
shared shell's `OTEL_SERVICE_NAME=rei` from contaminating Seihou without permanently mutating the
parent process environment. Respect standard exporter, endpoint, protocol, header, TLS,
resource-attribute, sampling, and `OTEL_SDK_DISABLED` variables by leaving them to the SDK.

The facade exposes stable helpers and a small test seam rather than leaking SDK types across the
CLI:

    data TelemetryTraceSetting = TelemetryOff | TelemetryOtel

    data TelemetryConfig = TelemetryConfig
      { traces :: TelemetryTraceSetting
      , serviceName :: Text
      }

    withTelemetry :: TelemetryConfig -> IO a -> IO a
    withCommandSpan :: Text -> IO a -> IO a
    withPhaseSpan :: Text -> IO a -> IO a
    withEitherSpan :: Text -> IO (Either e a) -> IO (Either e a)
    currentAgentOtelSink :: IO (Maybe TraceSink)

`withCommandSpan` and `withPhaseSpan` are pass-throughs when no runtime is active. The command
wrapper records success, `ExitCode` failure, and synchronous exceptions without copying exception
messages into attributes, then rethrows so existing exit behavior is unchanged.
`currentAgentOtelSink` captures the caller's current context and returns an `otelSinkWith` whose
prompt summary is disabled and whose `parentContext` is that captured context.

Refactor `seihou-cli/src-exe/Main.hs` so both normal `dispatch` and the early `extension run`
route execute inside `withTelemetry` and a stable root name produced by a total
`commandTelemetryName` mapping. Names contain only command identity (`seihou.update`,
`seihou.agent.assist`, `seihou.agent.run`, and so on), never positional arguments. Add an
in-memory-exporter test seam and `TelemetrySpec` assertions that off mode produces no spans,
enabled mode produces and closes one root, failures set error status and retain the original exit,
shutdown exports a short-lived CLI span, and the service resource is `seihou` even when the prior
ambient service name was `rei`.

### Milestone 3 — Update phase spans

Instrument existing effect boundaries in `seihou-cli/src/Seihou/CLI/Update.hs` with
`withPhaseSpan` / `withEitherSpan`. Do not create spans for pure helper functions and do not move
work merely to make a prettier trace. Planning should expose stable low-cardinality spans for
entry recovery, manifest read, candidate staging, application planning, migration planning,
staged reconciliation, and snapshot capture. Application should expose validation/recovery,
transaction begin, backup preparation, migration execution, actual reconciliation, filesystem
application, declared command execution, candidate publication, manifest write, and transaction
finish/abort.

The span tree must preserve the existing `Either UpdateError` control flow. An update error marks
the current phase and command root as failed without attaching rendered errors, paths, module
names, origin URLs, variable values, or command argv. Dry-run and structured no-op results are
successful outcomes, not errors. Collector failure must not enter `abortUpdate`; telemetry is
outside the update transaction's correctness boundary.

Extend `UpdateSpec` or add `UpdateTelemetrySpec` using the in-memory exporter and existing update
fixtures. Assert span names and parentage for a dry-run plan, a successful application, a
structured no-op, and a representative planning/application error. Also run the existing update
unit, interaction, render, and end-to-end suites unchanged. Acceptance is that turning telemetry
off yields the prior result and filesystem/manifest state exactly, while turning it on changes
only exported spans.

### Milestone 4 — Baikai calls and interactive Claude/Codex sessions

Change `Seihou.CLI.AgentTrace.traceSinkForConfig` to compose the existing selected sink with
`currentAgentOtelSink`. Use `Baikai.Trace.Sink.multiSink` only when two real sinks are present;
avoid wrapping the silent sink unnecessarily. The local `agent.trace` log message and path
semantics remain unchanged. With `agent.trace=file` and OTel enabled, one call must append JSONL
and export one OTel span. With local trace off and OTel enabled, the OTel call span must still be
emitted. With OTel off, the exact current sink is returned.

Because `currentAgentOtelSink` captures the command context before Baikai starts its drain thread,
every `baikai.call` span is a child of the command root. Keep
`defaultOtelSinkOptions.includePromptSummary` false. Preserve the existing `responseError` and
sink-exception behavior in `runAgentCompletionWith`; this milestone changes sink composition, not
provider error semantics.

Wrap the blocking launch in `Seihou.CLI.AgentLaunchExec.launchConfiguredAgentWith` in a
`seihou.agent.session` span. Attach only normalized provider (`anthropic` for Claude CLI,
`openai` for Codex CLI), optional requested model, interaction mode, and child exit code. Mark a
Baikai render refusal, missing executable, or non-zero child exit as error without attaching the
prompt, system prompt, tools, directories, or complete argv. This span is the guaranteed
interactive observability for both providers; do not set Claude telemetry environment variables
and do not pass Codex `-c otel.*` arguments.

Extend `AgentTraceSpec` and `AgentTraceE2ESpec`, plus the existing fake-launch coverage, to prove:

1. API, `claude-cli --batch`, and `codex-cli --batch` calls emit a parented `baikai.call` span.
2. Local file and OTel sinks both receive the same call when both are selected.
3. Interactive Claude and interactive Codex each emit a `seihou.agent.session` child with the
   right provider and exit status.
4. Neither provider's argv/environment gains native telemetry settings.
5. No OTel runtime means no OTel spans and no change to current launch arguments.

### Milestone 5 — Documentation, live proof, and durable decision

Update `docs/user/config-and-variables.md`, `docs/user/agent-assistance.md`, `help/config.md`,
`help/agent.md`, and `help/update.md`. Explain build availability separately from runtime
enablement; show local, global, and environment configuration; list precedence; state that
`OTEL_*` alone does not enable Seihou; show how `agent.trace` composes; document service-name
isolation; and state the content-redaction defaults.

Add a provider-native appendix. For Claude Code, cite the official monitoring guide and show its
explicit beta flags plus standard per-signal OTLP environment. Note that interactive Claude
currently ignores inbound `TRACEPARENT`. For Codex, cite the official configuration reference and
show a minimal `[otel]` table that leaves logs off, metrics off, prompt logging false, and selects
only `trace_exporter`. Make clear that those recipes are optional, provider-owned, and not needed
for Seihou command/Baikai spans.

Replace the stale “Adopting `baikai-trace-otel` Is Packaging Work, Not Seihou Work” subsection in
`docs/dev/architecture/overview.md` with the implemented lifecycle, opt-in, parent-context, and
two-agent-path design. Update the root and user changelogs. Create the next available ADR under
`docs/adr/` recording runtime consent, build optionality, privacy, failure isolation, and why
provider-native telemetry is not injected. Cross-repository references in that ADR must use the
Mori handles recorded in this plan.

Finally, run both Cabal flag configurations, `nix flake check`, and a live OTLP smoke against the
local collector. Acceptance is a visible `seihou` service containing an update trace and both
Codex and Claude agent traces at the Seihou boundary, with provider-native detail present only
when it was separately configured.


## Concrete Steps

Run all repository commands from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

First confirm the dependency records before editing bounds. Mori locates the source; Hackage and
upstream tags confirm the release:

    mori registry show shinzui/baikai --full
    mori registry search baikai-trace-otel
    mori registry show iand675/hs-opentelemetry --full
    git ls-remote --tags https://github.com/shinzui/baikai.git 'baikai-trace-otel-*'
    git ls-remote --tags https://github.com/iand675/hs-opentelemetry.git
    curl -fsSL https://hackage.haskell.org/package/hs-opentelemetry-api/preferred
    curl -fsSL https://hackage.haskell.org/package/hs-opentelemetry-sdk/preferred
    curl -fsSL https://hackage.haskell.org/package/hs-opentelemetry-exporter-otlp/preferred
    curl -fsSL https://hackage.haskell.org/package/hs-opentelemetry-exporter-in-memory/preferred

Expected relevant output includes the canonical package handle and tag:

    mori://shinzui/baikai/packages/baikai-trace-otel
    refs/tags/baikai-trace-otel-0.4.0.1
    refs/tags/hs-opentelemetry-api-1.0.0.0
    refs/tags/hs-opentelemetry-sdk-1.0.0.0
    refs/tags/hs-opentelemetry-exporter-otlp-1.0.0.0
    refs/tags/hs-opentelemetry-exporter-in-memory-1.0.0.0

During Milestones 1 and 2, run the focused configuration/runtime tests in both build modes:

    cabal test seihou-cli-test -f-otel --test-options='--pattern Telemetry'
    cabal test seihou-cli-test -fotel --test-options='--pattern Telemetry'

The flag-off run passes resolver/default tests and never links an OTel package. The flag-on run
also passes in-memory exporter/lifecycle tests. Confirm the clear unavailable-feature path with a
flag-off executable in an isolated XDG/project fixture rather than writing the developer's real
config:

    SEIHOU_TELEMETRY_TRACES=otel cabal run seihou -f-otel -- status

Expected stderr contains:

    Error: OpenTelemetry support is not available in this Seihou build; rebuild with -fotel.

After Milestone 3, run:

    cabal test seihou-cli-test -fotel --test-options='--pattern UpdateTelemetry'
    cabal test seihou-cli-test -fotel --test-options='--pattern Update'

After Milestone 4, run:

    cabal test seihou-cli-test -fotel --test-options='--pattern AgentTrace'
    cabal test seihou-cli-test -fotel --test-options='--pattern AgentMigrate'
    cabal test seihou-cli-test -fotel --test-options='--pattern AgentGuard'

Before completion, run the complete gates:

    cabal test all -f-otel
    cabal test all -fotel
    nix fmt -- --fail-on-change
    nix flake check

For the live smoke, use an isolated project config or the environment override so the repository
does not acquire a personal setting. With the motivating local collector:

    export SEIHOU_TELEMETRY_TRACES=otel
    export SEIHOU_TELEMETRY_SERVICE_NAME=seihou
    export OTEL_TRACES_EXPORTER=otlp
    export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:10428/insert/opentelemetry
    export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
    cabal run seihou -fotel -- update --dry-run
    curl -fsS http://traces.localhost/api/services | jq -e '.data | index("seihou")'

Expected final output from the query is a non-null index. Query recent traces through the same
Jaeger-compatible API and confirm a `seihou.update` root with planning children. Use existing fake
providers for the required automated Claude/Codex proof; a live model invocation is optional and
must not be made by the test suite.


## Validation and Acceptance

The change is accepted only when all of the following behaviors are demonstrated:

1. With neither key nor `SEIHOU_TELEMETRY_TRACES` set, a flag-enabled binary initializes no
   provider and exports no spans, even if `OTEL_TRACES_EXPORTER` and an OTLP endpoint are present.
   Existing stdout, stderr, exit status, files, manifests, agent argv, and local trace output are
   unchanged.

2. A flag-disabled build compiles and passes the complete test suite without any OTel packages in
   its dependency plan. Asking that build for `telemetry.traces=otel` exits before dispatch with
   the documented rebuild instruction; asking for `off` works normally.

3. A flag-enabled build with `telemetry.traces=otel` initializes once per CLI process, labels the
   resource with the resolved service name (default `seihou`, never an inherited `rei`), closes
   the command root on success/failure, flushes before exit, and restores the prior
   `OTEL_SERVICE_NAME` environment exactly.

4. `seihou update --dry-run` exports a successful `seihou.update` root and planning phase spans.
   A successful real update adds application phase spans. A no-op remains success. An update
   error marks spans as error but returns the same `UpdateError`, exit code, filesystem state,
   manifest state, and recovery artifacts as the untraced run.

5. A batch/API call from every provider family produces one `baikai.call` child under its Seihou
   command. Its attributes include provider/model and available usage/cost evidence but contain no
   prompt summary. `agent.trace=file` plus OTel produces both the JSONL event and OTel span; either
   setting can be turned off independently.

6. Interactive `claude-cli` and `codex-cli` launches each produce one
   `seihou.agent.session` child covering subprocess duration and result. Fake-provider tests prove
   Seihou did not inject Claude telemetry variables or Codex `otel.*` argv. This is the required
   Codex support even when the user's Codex installation has no native `[otel]` configuration.

7. Collector unavailability or an export timeout may produce an SDK diagnostic but does not
   alter Seihou's result or route an otherwise successful update through rollback. Explicit
   Seihou configuration errors remain fatal before any work begins.

8. The local live smoke shows service `seihou` in `traces.localhost` and exposes the expected
   update/agent span tree. If the user separately follows the provider-native appendix, Claude or
   Codex may also appear as provider-owned services; removing those provider settings removes the
   detailed native spans without affecting Seihou spans.

9. Both full Cabal configurations, formatting, and `nix flake check` pass. The final docs and ADR
   agree with the implemented config keys, precedence, flag default, privacy behavior, and actual
   span names.


## Idempotence and Recovery

All tests, formatters, and builds are repeatable. In-memory telemetry tests do not contact a
collector. The live smoke exports append-only observability data; repeating it creates another
trace and does not change project state when `update --dry-run` is used.

Runtime config changes are reversible:

    seihou config unset telemetry.traces --global
    seihou config unset telemetry.serviceName --global

or, for one invocation:

    SEIHOU_TELEMETRY_TRACES=off seihou update --dry-run

Do not use a developer's real XDG config in automated tests. Tests must isolate `XDG_CONFIG_HOME`
and the working directory, following the existing agent E2E fixtures. Do not make the live
collector a test dependency.

If SDK initialization fails before dispatch, no Seihou operation has started; fix the environment
or set telemetry to `off` and retry. Once dispatch starts, exporter failures are isolated from the
command. Update's existing transaction/recovery machinery remains the only mechanism for
recovering update mutations; telemetry code must never write inside `.seihou/` or participate in
transaction rollback.

If the OTel dependency closure proves unavailable in a downstream build, retry with `-f-otel`.
The Nix package's `-fotel` change is one additive `configureFlags` entry and can be reverted
without touching runtime/configuration code. If an implementation milestone changes user-visible
span/config semantics, update this living plan and its Decision Log before continuing rather than
silently diverging.


## Interfaces and Dependencies

`Seihou.CLI.Telemetry.Config` owns configuration and should expose at least:

    data TelemetryTraceSetting = TelemetryOff | TelemetryOtel
      deriving stock (Eq, Show)

    data TelemetryConfig = TelemetryConfig
      { traces :: TelemetryTraceSetting
      , serviceName :: Text
      }

    data TelemetryConfigInputs = TelemetryConfigInputs
      { envTraces :: Maybe Text
      , envServiceName :: Maybe Text
      , localConfig :: Map Text Text
      , globalConfig :: Map Text Text
      }

    telemetryTracesConfigKey :: Text
    telemetryServiceNameConfigKey :: Text
    telemetryTracesEnvVar :: String
    telemetryServiceNameEnvVar :: String
    resolveTelemetryConfig :: TelemetryConfigInputs -> Either Text TelemetryConfig
    loadTelemetryConfig :: IO (Either Text TelemetryConfig)

`Seihou.CLI.Telemetry` owns effects and should expose the flag-independent facade named in
Milestone 2. Its internal OTel implementation uses:

- `OpenTelemetry.Trace.initializeGlobalTracerProvider`, `makeTracer`, span creation/status, flush,
  and `shutdownTracerProvider` for a short-lived CLI lifecycle.
- `OpenTelemetry.Context.ThreadLocal.getContext` to capture the active command parent.
- `Baikai.Trace.Sink.OpenTelemetry.otelSinkWith` and `defaultOtelSinkOptions` from
  `mori://shinzui/baikai/packages/baikai-trace-otel`.
- `Baikai.Trace.Sink.multiSink` from `mori://shinzui/baikai/packages/baikai` to preserve local
  agent tracing while adding OTel.

Use `baikai-trace-otel ^>=0.4.0.1`; it declares `baikai ^>=0.7.0` and matches Seihou's current
Baikai family. Use the OTel 1.0 API/SDK range already provided by
`mori://shinzui/haskell-nix`. Before changing these bounds during implementation, repeat the Mori
lookup and verify Hackage plus upstream tags as required by the repository instructions.

`Seihou.CLI.Update` consumes only the flag-independent `withPhaseSpan` and `withEitherSpan`
helpers. `Seihou.CLI.AgentTrace` consumes `currentAgentOtelSink` and `multiSink`.
`Seihou.CLI.AgentLaunchExec` consumes the session-span helper. No type from an OTel package should
escape these telemetry/adapter modules, and `seihou-core` must gain no telemetry dependency.

The backend contract is standard OTLP configuration through `OTEL_*`; Seihou does not invent
endpoint, protocol, header, TLS, or sampling config keys. The only Seihou-specific runtime
contract is consent and service identity. The motivating backend is VictoriaTraces at
`traces.localhost`, but the implementation must work with any collector supported by the Haskell
OTLP exporter.

Provider-native references for documentation and compatibility tests are the official
[Codex configuration reference](https://developers.openai.com/codex/config-reference/) and
[Claude Code monitoring guide](https://docs.anthropic.com/en/docs/claude-code/monitoring-usage).
They are not Seihou library dependencies. Native provider span schemas and exporter lifecycles
remain outside this plan's compatibility promise.
