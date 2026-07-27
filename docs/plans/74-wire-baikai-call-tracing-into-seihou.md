---
id: 74
slug: wire-baikai-call-tracing-into-seihou
title: "Wire baikai call tracing into seihou"
kind: exec-plan
created_at: 2026-07-27T17:02:14Z
intention: "intention_01kyj8dbxde3zta5zyt0y1srxq"
---

# Wire baikai call tracing into seihou

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Seihou is a project-scaffolding tool. Several of its commands hand a rendered prompt to an AI
model and print the reply: `seihou agent assist`, `seihou agent bootstrap`, `seihou agent setup`,
`seihou agent run`, `seihou agent migrate`, and `seihou prompt run`. When one of those calls is
slow, expensive, or fails, the user gets a single line of output and no way to find out what
happened. There is no record of which model was actually called, how long it took, how many tokens
it consumed, what it cost, or — when it fails — what the provider said.

The library Seihou uses to talk to models, **baikai**, already produces exactly that record.
Baikai calls it a **trace**: a small stream of events, one when a call starts and one when it
finishes or fails, each carrying the provider name, model name, elapsed milliseconds, input and
output token counts, dollar cost, and the error text on failure. Baikai emits these events into a
**sink** — a consumer you supply that decides what to do with them (print them, append them to a
file, drop them). Seihou wires up **no sink at all** today, so the events are never produced. A
repository-wide search for `Baikai.Trace`, `TraceSink`, or `withTrace` across every `.hs`,
`.cabal`, and `.nix` file returns nothing.

After this change, a user can turn tracing on and see where their time and money went:

```text
$ seihou config set agent.trace file
$ seihou agent assist "add a health check module"
... normal assistant output ...

$ cat .seihou/trace.jsonl
{"kind":"call_started","eventId":"a1b2c3","timestamp":"2026-07-27T18:04:11Z","provider":"anthropic","model":"claude-sonnet-4-6","maxTokens":8192,"promptSummary":"add a health check module"}
{"kind":"call_finished","eventId":"a1b2c3","timestamp":"2026-07-27T18:04:19Z","provider":"anthropic","model":"claude-sonnet-4-6","latencyMs":7913,"inputTokens":4211,"outputTokens":880,"usd":0.0264}
```

That file is one JSON object per line — the format commonly called **JSON Lines** or **JSONL** —
so ordinary tools can answer questions about it directly:

```text
$ jq -s 'map(select(.kind=="call_finished") | .usd) | add' .seihou/trace.jsonl
0.0264
```

Or, for watching a single run rather than accumulating history:

```text
$ seihou agent assist "add a health check module" --trace stderr
[2026-07-27T18:04:11Z] anthropic claude-sonnet-4-6 START max=8192 add a health check module
[2026-07-27T18:04:19Z] anthropic claude-sonnet-4-6 -> 7913ms in=4211 out=880 $0.0264
```

**The observable outcome.** With `agent.trace` unset — the default — behavior is byte-for-byte
what it is today: no trace file is created, no extra output appears, and no measurable overhead is
added. With it set, every model call the six commands make produces a correlated start event and
either a finish or a fail event, and that is asserted end-to-end by a test that runs the real
`seihou` binary against a fake provider and reads back the resulting JSONL.

**What this plan does not do.** It does not add OpenTelemetry. Baikai ships an optional
`baikai-trace-otel` package that turns the same events into OTel spans, but that package is not
carried by the shared Nix registry this repository builds against and pulls in two new
`hs-opentelemetry-*` dependencies. Milestone 5 writes down exactly what adopting it would require,
as a scoped hand-off, and this plan stops there. Core tracing needs **no new dependency at all** —
`Baikai.Trace` lives in the `baikai` package that `seihou-cli` already depends on.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Researched baikai's trace surface (`Baikai.Trace`, `Baikai.Trace.Sink`,
      `Baikai.Trace.Event`, `Baikai.Cost.Log`), confirmed seihou wires none of it, located the
      single call site all six commands funnel through, and established that `baikai-trace-otel`
      is absent from the shared registry (2026-07-27).
- [x] Recorded the scoping decisions (sink vocabulary, config surface, error-semantics change,
      OTel deferral, intention) in the Decision Log (2026-07-27).
- [x] Milestone 1 — Trace configuration: a `TraceSetting` type, `agent.trace` /
      `agent.<command>.trace` config keys, `agent.tracePath`, `SEIHOU_AGENT_TRACE`, and a
      `--trace` flag, all resolved through the existing precedence chain, with unit tests.
      Nothing emits yet. `cabal test seihou-cli`: 396 tests pass. `seihou agent config` shows a
      trace row per command; `--trace bogus` exits 1 naming all four settings (2026-07-27).
- [x] Milestone 2 — Sink construction: `Seihou.CLI.AgentTrace` turns a resolved `TraceSetting`
      into a `Baikai.TraceSink`, including path resolution for the file sink and parent-directory
      creation, with a new spec driving real events through each sink. `cabal test seihou-cli`:
      408 tests pass (2026-07-27).
- [ ] Milestone 3 — The swap: `runAgentCompletionWith` calls `Baikai.Trace.withTrace` instead of
      `Baikai.completeRequest`, **preserving today's error reporting** across the changed
      exception semantics. This is the milestone with real regression risk; it carries its own
      dedicated tests.
- [ ] Milestone 4 — End-to-end proof and documentation: a test that runs the real binary against
      a fake provider and asserts on the emitted JSONL; user and CLI docs; both changelogs.
- [ ] Milestone 5 — OTel hand-off note: document precisely what adopting `baikai-trace-otel`
      requires. No code.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **Discovery (2026-07-27): `withTrace` and `completeRequest` differ in a way that will silently
  break error reporting if the swap is done naively.** This is the single most important fact in
  this plan. Seihou currently calls:

  ```haskell
  result <- try (Baikai.completeRequest model ctx options) :: IO (Either Baikai.BaikaiError Baikai.Response)
  pure $ case result of
    Left err -> Left (Text.pack (show err))
    Right resp -> …
  ```

  `completeRequest` **throws** a `BaikaiError` on provider failure, which the `try` catches.
  `withTrace` deliberately does not. Its doc comment in
  `/Users/shinzui/Keikaku/bokuno/baikai/baikai/src/Baikai/Trace.hs` states:

  > Unlike the EP-2 `withTrace` (which re-threw the producer's exception), this implementation
  > never throws for producer-side failures: errors flow through the stream as a terminal
  > `EventError` and the drained `Response` carries `stopReason = ErrorReason` plus
  > `errorMessage`.

  So after a naive swap the `try` would never fire, the failure would arrive as a `Right` holding
  an error-shaped `Response` whose assistant text is empty, and Seihou's existing empty-text guard
  would report the misleading `"Provider returned no assistant text."` for every provider error —
  losing the authentication failures, rate limits, and model-not-found messages users currently
  see. Milestone 3 exists specifically to handle this, using
  `Baikai.Response.responseError :: Response -> Maybe BaikaiError`, which returns `Just` exactly
  when the response is error-shaped.

- **Discovery (2026-07-27, during Milestone 1 research): `withTrace` reaches the provider by a
  different route than `completeRequest`, which sharpens — and partly explains — the
  error-semantics hazard above.** `Baikai.Provider.Registry.ApiProvider` has two fields:
  `complete` (synchronous) and `stream`. `completeRequest` calls `complete`; `withTrace` drains
  `withTraceStream`, which calls `stream`. For the two CLI providers those are *not* the same
  code path — `baikai-claude/src/Baikai/Provider/Claude/Cli.hs:102` sets
  `stream = liftCompleteToStream (runClaudeCli cfg)` and `complete = runClaudeCli cfg` directly,
  and the comment there records that the direct path is kept precisely because a streaming
  round trip "would lose the former [`responseId`] and recompute the latter [`latencyMs`] from
  synthetic events". Two consequences for Milestone 3: (a) `Baikai.Stream.liftCompleteToStream`
  wraps the batch call in `trySync` and converts a synchronous exception into an `EventError`,
  which is *why* the provider failures Seihou's `try` catches today will arrive as error-shaped
  responses tomorrow — the `responseError` branch is not optional; (b) Seihou reads only
  assistant text blocks (`responseText`) and, after this change, `responseError`, both of which
  survive the round trip, so losing `responseId` and the directly-measured `latencyMs` costs
  Seihou nothing. Worth knowing before anyone tries to use `Response.latencyMs` here.

- **Discovery (2026-07-27): all six commands funnel through one function, so the swap is a
  one-place change.** `seihou-cli/src/Seihou/CLI/AgentCompletion.hs` exposes `runAgentCompletion`
  and `runAgentCompletionWithCliAccess`; both delegate to the private `runAgentCompletionWith`,
  which holds the only `completeRequest` call in the repository. The six call sites are
  `Assist.hs:62`, `Bootstrap.hs:64`, `Setup.hs:62`, `AgentMigrate.hs:241`, `AgentRun.hs:227`, and
  `PromptRun.hs` (via `AgentRun.runRenderedAgentPrompt`).

- **Discovery (2026-07-27): tracing cannot cover interactive sessions, and this is structural.**
  Baikai has two surfaces and Seihou uses both:
  `Seihou.CLI.AgentCompletion` drives *completion providers*, and
  `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs` drives *interactive providers*
  (`launchClaudeInteractive` / `launchCodexInteractive`), which spawn `claude` or `codex` as
  subprocesses. A grep for `TraceEvent`, `TraceSink`, or `withTrace` in baikai's interactive
  modules returns nothing — subprocess launches emit no trace events, because there is no request
  for baikai to time or price. A blueprint run silently crosses between the two paths depending on
  whether stdin is a terminal (`AgentRun.hs:105`: `batch = opts.runBlueprintBatch || not
  stdinIsTerminal`). Tracing therefore covers batch and API calls only, and the docs must say so
  plainly or users will file bugs about missing traces from interactive sessions. This is the same
  two-path hazard recorded in `docs/dev/architecture/overview.md` under "Agent Launch Settings
  Resolve Through One Ordered Chain".

- **Discovery (2026-07-27): trace events would not have caught the reasoning-effort bug fixed in
  plan 73, so tracing is not a substitute for argv assertions.** `CallStarted` carries `eventId`,
  `timestamp`, `provider`, `model`, `maxTokens`, and `promptSummary` — it does not carry
  `Options.thinking` or the rendered command line. The bug that plan 73 fixed lived between
  `Options` and the spawned `claude` argv, below what a `TraceEvent` observes. Worth stating in
  the docs so tracing is not oversold as a debugging cure-all.


## Decision Log

Record every decision made while working on the plan.

- Decision: expose four trace settings — `off`, `file`, `stdout`, `stderr` — rather than exposing
  baikai's `TraceSink` composition surface to users.
  Rationale: `TraceSink` is a streamly `Fold IO TraceEvent ()`, and its power comes from
  composition (`Fold.tee` to fan out, `Fold.filter` to drop events, `Fold.lmap` to project or
  redact). None of that is expressible in a Dhall config string. A closed four-value vocabulary
  matches how Seihou already models `provider` and `effort`, gets the same validation and
  provenance machinery for free, and leaves the composition surface available later — a future
  `both` setting is just `multiSink [fileSink p, stdoutSink]`.
  Date: 2026-07-27

- Decision: default the file sink to `.seihou/trace.jsonl` inside the project, and make the path
  overridable with a separate `agent.tracePath` key.
  Rationale: `.seihou/` is where Seihou already keeps per-project state (`manifest.json`,
  `config.dhall`), so the trace lands somewhere users already know to look and already ignore in
  git. Splitting the path into its own key keeps the sink vocabulary closed and validatable while
  still allowing `/tmp/seihou-trace.jsonl` or a shared location.
  Date: 2026-07-27

- Decision: trace to **stderr** as the streaming default rather than stdout, and offer `stdout`
  only as an explicit opt-in.
  Rationale: several commands print assistant text to stdout, and `seihou agent run --debug`
  prints the rendered prompt there. Interleaving trace lines into stdout would corrupt output that
  users pipe. Seihou's existing logger already writes all `[info]`/`[warn]`/`[error]` output to
  stderr (`seihou-core/src/Seihou/Effect/LoggerInterp.hs`), so stderr is the established channel
  for out-of-band information. `stdout` remains available because baikai ships `stdoutSink` and
  some users will want traces in a pipeline.
  Date: 2026-07-27

- Decision: preserve today's error text exactly across the `withTrace` swap, by checking
  `Baikai.Response.responseError` on the returned `Response` instead of relying on the `try`.
  Rationale: see the first Surprises entry. Changing observability must not change what a user
  sees when their API key is wrong. The `try` is retained as a belt-and-braces guard for
  downstream-of-the-fold exceptions, which the doc comment says still propagate.
  Date: 2026-07-27

- Decision: defer OpenTelemetry to a follow-up plan and deliver only a hand-off note here.
  Rationale: user selection. `baikai-trace-otel` is not among the packages the shared
  `shinzui/haskell-nix` registry overlay supplies (`nix/haskell-overlay.nix` names only baikai,
  baikai-claude, baikai-openai, and baikai-kit), and it depends on `hs-opentelemetry-api` and
  `hs-opentelemetry-semantic-conventions`, neither of which is in this repository's dependency
  closure. Adopting it is packaging work of unknown size, whereas core tracing needs no new
  dependency. Phasing keeps this plan's risk in the code rather than in the build.
  Date: 2026-07-27

- Decision: trace settings resolve through the existing `Seihou.CLI.AgentConfig` precedence chain,
  including the artifact-declaration tier added by plan 73.
  Rationale: users already understand that chain, `seihou agent config` already displays it, and
  `docs/user/config-and-variables.md` already documents it. Introducing a second, differently
  ordered resolution path for one setting would be gratuitous. A blueprint declaring
  `launch.trace` is not part of this plan — the schema is not extended — but routing through the
  same resolver means adding it later is an insertion, not a redesign.
  Date: 2026-07-27

- Decision (2026-07-27, Milestone 1): group the four per-tier CLI flags into an
  `AgentSettingFlags` record rather than extending the positional argument lists of
  `loadAgentModelConfigFor`, `loadPendingAgentConfig`, and `gatherAgentConfigInputs`.
  Rationale: the plan's literal instruction — thread a fourth flag through the existing
  positional signatures — would have produced eight-argument functions carrying four
  same-typed `Maybe Text` values in a row, twice over, plus four `Bool`s. Any transposition
  would type-check and silently mis-resolve a setting. The record also lets the
  `commandFlag <|> parentFlag` combination and the `isJust commandFlag` provenance marker live
  in one place (`applyAgentSettingFlags`) instead of being duplicated in both `Main.hs`
  helpers. Net effect on the precedence chain: none — the same nine tiers in the same order.
  Date: 2026-07-27

- Decision (2026-07-27, Milestone 1): carry the resolved trace path on
  `ResolvedCommandConfig` as `rccTracePath :: Maybe FilePath`, without provenance.
  Rationale: `resolvedAgentModelConfig` projects a `ResolvedCommandConfig` into the
  `AgentModelConfig` the launch layer consumes, and that record now needs `agentTracePath`.
  Provenance is omitted deliberately: `agent.tracePath` is free-form, has no flag, no
  environment variable, and no per-command variant, so there is no precedence story worth
  displaying — only local-beats-global, which the legend states in prose.
  Date: 2026-07-27

- Decision: link the work to Intention `intention_01kyj8dbxde3zta5zyt0y1srxq`, minted with
  `mina ci --json "Wire baikai call tracing into seihou"`.
  Rationale: user instruction, matching how plan 73 was tracked.
  Date: 2026-07-27


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

**No ADR corpus exists in this repository.** There is no `docs/adr/` directory, and `mori.dhall`
declares no OKF bundle whose path is `docs/adr` — its `docs` list contains only
`docs/dev/architecture/overview.md` and `docs/dev/roadmap/v1-milestones.md`. Per the plan skill's
ADR workflow, the repository's established convention is preserved: do **not** create `docs/adr/`
or invent OKF frontmatter as an incidental edit of this plan. Durable architectural context from
this work belongs in `docs/dev/architecture/overview.md`, which is the repository's existing home
for such notes. This matches what
[`docs/plans/73-support-blueprint-declared-agent-provider-model-and-effort.md`](73-support-blueprint-declared-agent-provider-model-and-effort.md)
concluded and did.

### Relationship to plan 73

Plan 73 (checked in at the path above, complete) added an artifact-declaration tier to the agent
settings resolver and, along the way, bumped baikai to `0.4.1.0` / `baikai-claude 0.4.0.0` /
`baikai-openai 0.4.0.0`. Two things from it matter here and are restated so this plan stands
alone:

1. **The resolver is a single ordered chain.** `seihou-cli/src/Seihou/CLI/AgentConfig.hs` resolves
   each setting from one ordered candidate list, using `firstNonBlankWithSource` (leftmost
   present, non-blank value wins; whitespace-only counts as absent). The precedence enum
   `AgentConfigSource` has its constructors in precedence order, and that ordering *is* the
   documentation. Nine tiers, highest first: subcommand flag, parent `seihou agent` flag,
   environment variable, artifact declaration, local `agent.<command>.*`, local `agent.*`, global
   `agent.<command>.*`, global `agent.*`, built-in default. This plan adds a fourth setting to
   that machinery and must not invent a parallel one.

2. **Seihou has two agent launch paths.** Recorded in `docs/dev/architecture/overview.md`. Only
   the completion path is traceable; see the third Surprises entry.

### The repository at a glance

A Haskell workspace (GHC 9.12, `cabal.project`) with two packages plus one extension package:

- `seihou-core/` — domain types (`Seihou.Core.Types`), Dhall decoders (`Seihou.Dhall.Eval`),
  validation, scaffolding.
- `seihou-cli/` — split into a library at `seihou-cli/src/` (module prefix `Seihou.CLI.*`) and an
  executable at `seihou-cli/src-exe/`. Per `CLAUDE.md` and `docs/dev/architecture/overview.md`
  ("CLI Module Placement Convention"), **new modules go in the library** unless they need
  `Options.Applicative`, `Data.FileEmbed`, `GitHash`, `Paths_seihou_cli`, or an import of a module
  already trapped in the executable. The convention is mechanically enforced by
  `nix/check-cli-module-placement.sh`, which runs in `nix flake check` and the pre-commit hook.
  **This plan adds one new library module** (`Seihou.CLI.AgentTrace`), which is correct placement
  and will pass the check; putting it in `src-exe/` would fail.
- `schema/` — a git submodule holding the `seihou-schema` Dhall schema. **Untouched by this plan.**

Build and test:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
nix develop --command bash -c 'cabal build all'
nix develop --command bash -c 'cabal test all'
```

Running inside `nix develop` matters: the baikai family is supplied by the Nix overlay, not by
Hackage, so a bare `cabal build` may resolve different versions.

### Vocabulary used in this plan

- **Trace** — a record of one model call. In baikai, a small stream of `TraceEvent` values.
- **`TraceEvent`** — defined at
  `/Users/shinzui/Keikaku/bokuno/baikai/baikai/src/Baikai/Trace/Event.hs`. A three-case sum:

  ```haskell
  data TraceEvent
    = CallStarted  { eventId, timestamp, provider, model, maxTokens, promptSummary }
    | CallFinished { eventId, timestamp, provider, model, latencyMs, inputTokens, outputTokens, usd }
    | CallFailed   { eventId, timestamp, provider, model, latencyMs, errorMessage }
  ```

  `eventId` correlates a start with its matching finish or fail within one process run.
  `inputTokens`, `outputTokens`, and `usd` are `Maybe` because subscription-based providers (the
  local CLIs) do not report them; absent fields are omitted from the JSON. The JSON sum encoding
  uses a tag field named `kind` with lower-snake values (`call_started`, `call_finished`,
  `call_failed`), which is what makes `jq 'select(.kind == "call_finished")'` work.

- **Sink** — a consumer of trace events. In baikai, `TraceSink`, defined at
  `/Users/shinzui/Keikaku/bokuno/baikai/baikai/src/Baikai/Trace/Sink.hs`:

  ```haskell
  newtype TraceSink = TraceSink { runSink :: Fold IO TraceEvent () }
  ```

  A **`Fold`** here is a streamly `Streamly.Data.Fold.Fold` — a value describing how to consume a
  stream of inputs. You do not need to understand streamly to complete this plan: the four
  built-in sinks are enough, and this plan constructs no custom folds. They are:

  | Sink | Behavior |
  |------|----------|
  | `silent` | Discards every event. |
  | `stdoutSink` | Prints one human-readable line per event via `renderHuman`. |
  | `fileSink :: FilePath -> IO TraceSink` | Appends one JSON object per line. Opens and closes the file per write — the module comment says this is deliberate, "crash safety beats throughput". |
  | `multiSink :: [TraceSink] -> TraceSink` | Fans every event out to every sink in the list. |

  Note `fileSink` returns `IO TraceSink`, not `TraceSink` — sink construction is effectful, which
  is why Milestone 2 gives it its own function rather than folding it into pure resolution.

- **`renderHuman`** — `TraceEvent -> Text`, exported from the same module. Produces exactly the
  lines shown in the Purpose section, e.g.
  `[2026-07-27T18:04:11Z] anthropic claude-sonnet-4-6 START max=8192 <first 80 chars of prompt>`.
  There is no built-in stderr sink; Milestone 2 builds one from `renderHuman`, which is a
  three-line function.

- **JSON Lines / JSONL** — a text format with one complete JSON object per line, appendable and
  streamable, readable by `jq -s` or any line-oriented tool.

- **Provenance** — the label Seihou attaches to a resolved setting naming where it came from, e.g.
  `[local: agent.run.trace]`. Rendered by `agentConfigSourceLabel`.

### How model calls happen today

The only place Seihou performs a completion is `runAgentCompletionWith` in
`seihou-cli/src/Seihou/CLI/AgentCompletion.hs` (line 176). Reproduced in full, because Milestone 3
rewrites its tail:

```haskell
runAgentCompletionWith :: IO () -> AgentCompletionRequest -> IO (Either Text Text)
runAgentCompletionWith registerProviders req = do
  registerProviders
  initialMessages <-
    maybe
      (pure V.empty)
      (fmap V.singleton . Baikai.userNow)
      req.completionInitialPrompt
  let model = buildBaikaiModel req.completionModelConfig
      ctx =
        Baikai.emptyContext
          { Baikai.systemPrompt = Just req.completionSystemPrompt,
            Baikai.messages = initialMessages
          }
      options = Baikai.emptyOptions {BaikaiOptions.thinking = req.completionModelConfig.agentEffort}
  result <- try (Baikai.completeRequest model ctx options) :: IO (Either Baikai.BaikaiError Baikai.Response)
  pure $ case result of
    Left err -> Left (Text.pack (show err))
    Right resp ->
      let body = responseText resp
       in if Text.null (Text.strip body)
            then Left "Provider returned no assistant text."
            else Right body
```

Two public wrappers sit on top, differing only in which providers they register:

```haskell
runAgentCompletion            :: AgentCompletionRequest -> IO (Either Text Text)
runAgentCompletionWithCliAccess :: [FilePath] -> [String] -> AgentCompletionRequest -> IO (Either Text Text)
```

`AgentCompletionRequest` is a three-field record (`completionSystemPrompt`,
`completionInitialPrompt`, `completionModelConfig`) built by `buildAgentCompletionRequest`. The
plan threads the sink through by adding a field to this record — see Interfaces and Dependencies.

The relevant baikai signatures, from
`/Users/shinzui/Keikaku/bokuno/baikai/baikai/src/Baikai/Trace.hs`:

```haskell
withTrace :: (MonadUnliftIO m) => TraceSink -> Model -> Context -> Options -> m Response
```

It is `completeRequest` with a `TraceSink` prepended — the same trailing three arguments in the
same order — which is why the swap is mechanically small. Its **error semantics differ**; see
Surprises.

And from `/Users/shinzui/Keikaku/bokuno/baikai/baikai/src/Baikai/Response.hs`:

```haskell
responseError :: Response -> Maybe BaikaiError
```

Returns `Just` exactly when the response is error-shaped (`stopReason = ErrorReason`), synthesizing
a `BaikaiError` from the provider's classified `errorInfo` when present and falling back to the
`errorMessage` text otherwise. This is the hook Milestone 3 uses.

### How settings resolve today

`seihou-cli/src/Seihou/CLI/AgentConfig.hs` is the resolver. Its input record after plan 73:

```haskell
data AgentConfigInputs = AgentConfigInputs
  { cliProvider, cliModel, cliEffort :: Maybe Text,
    cliProviderFromSubcommand, cliModelFromSubcommand, cliEffortFromSubcommand :: Bool,
    envProvider, envModel, envEffort :: Maybe Text,
    declaredProvider, declaredModel, declaredEffort :: Maybe Text,
    localConfig, globalConfig :: Map Text Text
  }
```

Each setting has a candidate-list builder (`providerCandidates`, `modelCandidates`,
`effortCandidates`), all with identical shape. `resolveAgentModelConfigFor` picks a winner per
field and returns `ResolvedAgentField a = ResolvedAgentField { resolvedValue :: a, resolvedSource
:: AgentConfigSource }`. `agentConfigSourceLabel :: AgentCommandName -> AgentField ->
AgentConfigSource -> Text` renders the bracketed provenance label, keyed on an `AgentField` enum
(`ProviderField | ModelField | EffortField`).

Config keys follow a fixed shape, e.g.:

```haskell
agentEffortConfigKey :: Text
agentEffortConfigKey = "agent.effort"

agentCommandEffortConfigKey :: AgentCommandName -> Text
agentCommandEffortConfigKey c = "agent." <> agentCommandSegment c <> ".effort"
```

The parsing vocabularies live in `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`:
`providerFromText :: Text -> Either Text AgentProvider` and
`effortFromText :: Text -> Either Text ThinkingLevel`, both case-insensitive with actionable error
messages naming the accepted values. `traceFromText` in this plan copies that shape exactly.

`AgentModelConfig` is the projection the launch layer consumes:

```haskell
data AgentModelConfig = AgentModelConfig
  { agentProvider :: AgentProvider, agentModel :: Maybe Text, agentEffort :: Maybe ThinkingLevel }
```

### CLI flag plumbing

Flags are declared in `seihou-cli/src-exe/Seihou/CLI/Commands.hs` (which is trapped in the
executable by `Options.Applicative`) and combined in `seihou-cli/src-exe/Main.hs`. Every agent
command already carries a `--provider` / `--model` / `--effort` triple on both the parent
`seihou agent` command and each subcommand, combined with `commandFlag <|> parentFlag`. Two helpers
in `Main.hs` do the combining: `resolveAgentModelConfigFor` (eager, for commands with no artifact)
and `pendingAgentConfigFor` (two-phase, added by plan 73, for `agent run` / `agent migrate` /
`prompt run`). Both must learn the new flag.

### Logging

`logIO :: LogLevel -> Eff '[Logger, IOE] () -> IO ()` (`seihou-cli/src/Seihou/CLI/Shared.hs:65`).
Per `seihou-core/src/Seihou/Effect/LoggerInterp.hs`, `logInfo` and `logDebug` emit **only** at
`LogVerbose`; `logWarn` from `LogNormal`; `logError` always. All output goes to **stderr** with
`[info]  ` / `[warn]  ` / `[error] ` prefixes. Runners set
`level = if opts.<cmd>Verbose then LogVerbose else LogNormal`.

### Test infrastructure

- Unit tests: `seihou-core/test/` and `seihou-cli/test/`, both `tasty` + `tasty-hspec`. Every spec
  module exports `tests :: IO TestTree` and must be registered in the package's `test/Main.hs`
  (import plus an entry in the `sequence [...]` list) **and** in the `.cabal` file's
  `other-modules`. This plan adds one new spec module, so both registrations are required.
- End-to-end tests: `seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs` is the model. It writes a
  fixture into a temp directory, writes a fake executable that records its argv and prints a
  canned response, puts it first on `PATH`, sets `XDG_CONFIG_HOME` to an empty temp dir so no real
  user config leaks in, scrubs `SEIHOU_AGENT_*` from the inherited environment, runs the real
  `seihou` binary through `runProcessText`, and asserts on what the fake recorded. Plan 73 added
  `withDeclaredLaunchBlueprint` there, which is the closest template for Milestone 4's harness.

### Documentation surface

`docs/user/agent-assistance.md`, `docs/user/config-and-variables.md` (§"Agent provider defaults",
which holds the nine-tier numbered list), `docs/cli/agent.md`, `docs/cli/prompt.md`,
`docs/cli/config.md`, and the two changelogs: `docs/user/CHANGELOG.md` (curated, user-facing, with
an `## Unreleased` section carrying `### Added` / `### Changed` / `### Fixed` subsections) and
`CHANGELOG.md` at the repository root (engineering).


## Plan of Work

Five milestones. The order is forced by data flow: the setting must resolve before a sink can be
built from it, and a sink must exist before the call site can use one. Milestones 1 and 2 are
additive and inert — nothing changes behavior until Milestone 3, which is deliberately isolated
because it is the only step that can regress existing users.

### Milestone 1 — Resolve a trace setting through the existing chain

Scope: `seihou-cli/src/Seihou/CLI/AgentConfig.hs`, `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`,
`seihou-cli/src-exe/Seihou/CLI/Commands.hs`, `seihou-cli/src-exe/Main.hs`, and the two existing
specs. At the end, `seihou agent config` shows a trace row for every command with correct
provenance, and `--trace stderr` parses — but nothing is emitted yet.

Add the vocabulary to `Seihou.CLI.AgentCompletion`, beside `providerFromText` and
`effortFromText`, because that module already owns the parsing vocabularies:

```haskell
-- | Where trace events for a model call should go.
data TraceSetting = TraceOff | TraceFile | TraceStdout | TraceStderr
  deriving stock (Eq, Show)

traceFromText :: Text -> Either Text TraceSetting
traceToText   :: TraceSetting -> Text
```

`traceFromText` must be case-insensitive and whitespace-tolerant, and its error message must name
every accepted value, matching `effortFromText`'s wording:
`"Unknown trace setting 'syslog'. Expected one of: off, file, stdout, stderr."`

Add `agentTrace :: TraceSetting` and `agentTracePath :: Maybe FilePath` to `AgentModelConfig`, with
`defaultAgentModelConfig` setting `TraceOff` and `Nothing`. Adding fields to this record will break
every construction site; there are few, and the compiler finds them all.

In `Seihou.CLI.AgentConfig`, follow the `effort` precedent exactly:

- Add `cliTrace`, `cliTraceFromSubcommand`, `envTrace`, `declaredTrace` to `AgentConfigInputs` and
  `baseAgentConfigInputs`. Include `declaredTrace` even though no schema field feeds it yet — it
  costs one `Nothing` and keeps all four settings structurally identical, so a future
  `launch.trace` is an insertion rather than a redesign.
- Add `TraceField` to the `AgentField` enum, and teach `fieldName` (used by the
  artifact-declaration label) and `envVarName`, `defaultKey`, `commandKey` about it.
- Add `agentTraceConfigKey = "agent.trace"`, `agentCommandTraceConfigKey`,
  `agentTracePathConfigKey = "agent.tracePath"`, and `agentTraceEnvVar = "SEIHOU_AGENT_TRACE"`.
- Add `traceCandidates` mirroring `effortCandidates`, and `resolveTrace` mirroring `resolveEffort`
  — but note the difference: an unset effort resolves to `Nothing`, whereas an unset trace resolves
  to `TraceOff` with source `SourceBuiltinDefault`. There is no "unset" trace state.
- Extend `resolveAgentModelConfigFor`'s return tuple with the resolved trace field, and
  `ResolvedCommandConfig` with an `rccTrace` field.
- Resolve the path separately. `agent.tracePath` is free-form (any path) and has no per-command
  variant — one key, local then global, no CLI flag. Keep it simple: a small
  `resolveTracePath :: AgentConfigInputs -> Maybe FilePath` reading the one key from local then
  global config.

`Seihou.CLI.AgentConfigShow` gains a trace row per command and a legend mention of
`SEIHOU_AGENT_TRACE`. Its spec asserts on rendered text, so update
`seihou-cli/test/Seihou/CLI/AgentConfigShowSpec.hs` accordingly.

In `Commands.hs`, add `--trace SETTING` to the parent `seihou agent` parser and to each subcommand
parser that already takes `--effort`, plus `seihou prompt run`. In `Main.hs`, thread it through
both `resolveAgentModelConfigFor` and `pendingAgentConfigFor` with the same
`commandFlag <|> parentFlag` combination and the same `isJust commandFlag` subcommand marker.

Tests in `seihou-cli/test/Seihou/CLI/AgentConfigSpec.hs`, following the existing style: `off` when
nothing is set, with `SourceBuiltinDefault`; each tier beats the one below it (subcommand flag >
parent flag > env > declaration > local per-command > local default > global per-command > global
default); case-insensitive parsing (`"  STDERR  "` → `TraceStderr`); a blank value is skipped in
favor of the next tier; an invalid value returns `Left` naming all four accepted settings; and
`agent.tracePath` reads from local before global.

Acceptance: `nix develop --command bash -c 'cabal test seihou-cli'` passes;
`seihou agent config` prints a trace column; `seihou agent assist --trace bogus "x"` exits non-zero
naming the four settings.

### Milestone 2 — Build a sink from a resolved setting

Scope: one new library module, `seihou-cli/src/Seihou/CLI/AgentTrace.hs`, plus its spec. At the
end, a resolved setting can be turned into a live `TraceSink`, provably — but the call site still
does not use one.

This is a new module rather than more code in `AgentCompletion.hs` because it is the only place
that touches the filesystem for tracing (creating the parent directory) and the only place that
imports `Baikai.Trace.Sink`. It goes in `seihou-cli/src/` — the library — since it needs none of
the four executable-trapping dependencies. Putting it in `src-exe/` would fail
`nix/check-cli-module-placement.sh`.

```haskell
module Seihou.CLI.AgentTrace
  ( traceSinkFor,
    resolveTraceFilePath,
    defaultTraceFileName,
    stderrSink,
  )
where
```

- `defaultTraceFileName :: FilePath` — `".seihou" </> "trace.jsonl"`.
- `resolveTraceFilePath :: Maybe FilePath -> FilePath` — the configured `agent.tracePath` when
  set and non-blank, otherwise `defaultTraceFileName`. Pure, so it is trivially testable.
- `stderrSink :: TraceSink` — baikai ships `stdoutSink` but no stderr equivalent, so build one:
  `TraceSink (Fold.drainMapM (Text.IO.hPutStrLn stderr . renderHuman))`. Reuse baikai's
  `renderHuman` rather than inventing a second format.
- `traceSinkFor :: TraceSetting -> Maybe FilePath -> IO TraceSink` — the whole point of the
  module. `TraceOff` → `pure silent`; `TraceStdout` → `pure stdoutSink`; `TraceStderr` →
  `pure stderrSink`; `TraceFile` → resolve the path, `createDirectoryIfMissing True` on its parent
  directory (otherwise a first run in a project without `.seihou/` fails), then `fileSink path`.

Note `Baikai.Trace.Sink.fileSink` already returns `IO TraceSink`, so the `IO` in the signature is
inherent, not incidental.

Tests in a new `seihou-cli/test/Seihou/CLI/AgentTraceSpec.hs` — remember to register it in both
`seihou-cli/test/Main.hs` and `seihou-cli/seihou-cli.cabal`'s `other-modules`. Cover:
`resolveTraceFilePath` for the default, an explicit path, and a blank-string path (must fall back
to the default, matching the resolver's "blank counts as absent" rule); and, in a
`withSystemTempDirectory`, that `traceSinkFor TraceFile` creates a missing parent directory and
that feeding it a synthetic `CallFinished` event through `Fold.drainMapM`-equivalent driving
produces one parseable JSON line whose `kind` is `call_finished`. Drive the fold with
`Streamly.Data.Fold` directly, or — simpler and sufficient — assert that the file exists and is
valid JSONL after one event.

Acceptance: `nix develop --command bash -c 'cabal test seihou-cli'` passes with the new spec
registered and running.

### Milestone 3 — Swap the call site, preserving error reporting

Scope: `runAgentCompletionWith` and `buildAgentCompletionRequest` in
`seihou-cli/src/Seihou/CLI/AgentCompletion.hs`. This is the milestone with regression risk; treat
it carefully and read the first Surprises entry before editing.

Add a fourth field to `AgentCompletionRequest`:

```haskell
data AgentCompletionRequest = AgentCompletionRequest
  { completionSystemPrompt :: Text,
    completionInitialPrompt :: Maybe Text,
    completionModelConfig :: AgentModelConfig,
    -- | The sink trace events go to. 'Baikai.Trace.Sink.silent' when tracing
    -- is off, which is the default and adds no measurable overhead.
    completionTraceSink :: TraceSink
  }
```

`buildAgentCompletionRequest` keeps its current signature by defaulting the field to `silent`, and
a new `buildAgentCompletionRequestWith :: TraceSink -> AgentModelConfig -> Text -> Maybe Text ->
AgentCompletionRequest` sets it. Keeping the old constructor working means the five call sites that
do not yet care about tracing compile unchanged, and Milestone 4 converts them deliberately rather
than in a wide mechanical edit.

Then rewrite the tail of `runAgentCompletionWith`:

```haskell
  result <-
    try (Baikai.Trace.withTrace req.completionTraceSink model ctx options)
      :: IO (Either Baikai.BaikaiError Baikai.Response)
  pure $ case result of
    -- Retained: withTrace does not throw for provider failures, but its doc
    -- comment states downstream-of-the-fold exceptions still propagate --
    -- a sink whose file write fails, for instance.
    Left err -> Left (Text.pack (show err))
    Right resp -> case Baikai.responseError resp of
      -- withTrace surfaces provider failures as an error-shaped Response
      -- rather than an exception. Without this branch every provider error
      -- would fall through to the empty-text guard below and be reported as
      -- "Provider returned no assistant text.", losing the real message.
      Just err -> Left (Text.pack (show err))
      Nothing ->
        let body = responseText resp
         in if Text.null (Text.strip body)
              then Left "Provider returned no assistant text."
              else Right body
```

The `Text.pack (show err)` on both branches is deliberate: it reproduces today's exact error text,
so a user with a bad API key sees precisely what they saw before.

Tests, in `seihou-cli/test/Seihou/CLI/AgentCompletionSpec.hs` (which exists — it already covers
`buildAgentCompletionRequest` and `responseText`). The provider registry is process-global
(`globalProviderRegistry`), so these tests register a stub provider that returns a canned
`Response`:

- a successful response still yields `Right body`;
- an **error-shaped** response (`stopReason = ErrorReason` with an `errorMessage`) yields `Left`
  carrying that message — **not** `"Provider returned no assistant text."`. This is the
  regression test for the whole milestone; write it first and confirm it fails against the naive
  swap before adding the `responseError` branch;
- a successful-but-empty response still yields `Left "Provider returned no assistant text."`, so
  the empty-text guard is not shadowed by the new branch;
- with a file sink, one successful call appends exactly two lines whose `kind` fields are
  `call_started` and `call_finished` and whose `eventId`s are equal — proving correlation;
- with a file sink, one failing call appends `call_started` then `call_failed`.

If registering a stub provider proves impractical in-process, fall back to asserting the pure
projection in a unit test and rely on Milestone 4's end-to-end case for the wiring — but record
that fallback in Surprises & Discoveries with the reason, because it weakens this milestone's
guarantee.

Acceptance: `nix develop --command bash -c 'cabal test all'` passes. The error-shape test must
fail if the `responseError` branch is deleted — verify that by deleting it once, watching the
failure, and restoring it.

### Milestone 4 — Thread the sink through, prove it end to end, document it

Scope: the six call sites, one end-to-end test, and the docs. At the end, the feature is real and
observable from a shell.

Build the sink once per command invocation, next to where the command already resolves its model
config, and pass it into the request. For the four eager commands (`assist`, `bootstrap`, `setup`)
and the batch path of `agent run`, that means calling
`traceSinkFor modelConfig.agentTrace modelConfig.agentTracePath` and using
`buildAgentCompletionRequestWith`. `AgentMigrate.hs:241` runs one call per migration edge and
should build the sink **once** before the loop, so all edges append to the same file with distinct
`eventId`s.

At `LogVerbose`, log one line naming the destination when tracing is on, e.g.
`logInfo ("Trace: writing to " <> path)`, so `--verbose` users can see where the file went.

The end-to-end proof goes in a new `seihou-cli/test/Seihou/CLI/AgentTraceE2ESpec.hs`, modeled on
`AgentMigrateE2ESpec.hs`'s harness (fake executable on `PATH`, empty `XDG_CONFIG_HOME`, scrubbed
`SEIHOU_AGENT_*`, real binary via `runProcessText`). Use `seihou agent run` with a blueprint and a
fake `claude` that prints the batch JSON line, with `SEIHOU_AGENT_TRACE=file` and
`agent.tracePath` pointed inside the temp root. Assert that the trace file exists, holds exactly
two lines, that both parse as JSON, that their `kind` values are `call_started` and
`call_finished`, and that their `eventId` values match. Also assert the negative: the same run
**without** `SEIHOU_AGENT_TRACE` creates no trace file at all — that is the guarantee that
tracing is genuinely off by default.

Because the CLI providers are subscription-based, `inputTokens` / `outputTokens` / `usd` will be
absent from that fixture's `call_finished` event. Assert on `kind` and `eventId`, not on token
counts, or the test will be wrong about what the CLI path reports.

Documentation:

- `docs/user/agent-assistance.md` — a new "Tracing model calls" section: what the events contain,
  the four settings, the default path, a `jq` cost-summing example, and — prominently — that
  **interactive sessions are not traced**, because they launch `claude`/`codex` as subprocesses
  rather than making a request baikai can time or price, and that a blueprint run silently takes
  the interactive path when stdin is a terminal. Also note that traces record call-level
  facts (provider, model, latency, tokens, cost) and not the arguments passed to a spawned CLI, so
  tracing does not replace argv-level debugging.
- `docs/user/config-and-variables.md` — add `agent.trace` / `agent.<command>.trace` /
  `agent.tracePath` and `SEIHOU_AGENT_TRACE` to the agent settings section, noting they use the
  same nine-tier chain already documented there.
- `docs/cli/agent.md` and `docs/cli/prompt.md` — document `--trace`.
- `docs/user/CHANGELOG.md` — an `## Unreleased` → `### Added` entry in the established voice.
- `CHANGELOG.md` — an engineering entry.

Acceptance: the transcripts in Validation and Acceptance reproduce by hand;
`nix develop --command bash -c 'cabal test all'` passes; `nix flake check` passes.

### Milestone 5 — OpenTelemetry hand-off note

Scope: documentation only. No code, no dependency changes.

Add a short subsection to `docs/dev/architecture/overview.md` recording what adopting
`baikai-trace-otel` would require, so a future contributor does not have to rediscover it:

- `otelSink :: Otel.Tracer -> TraceSink` and
  `otelSinkWith :: Otel.Tracer -> OtelSinkOptions -> TraceSink` are ordinary `TraceSink` values,
  so **no seihou code beyond `traceSinkFor` would change** — it gains one branch. The work is
  entirely packaging plus tracer lifecycle.
- `baikai-trace-otel` 0.3.0.2 depends on `hs-opentelemetry-api >=1.0 && <1.1` and
  `hs-opentelemetry-semantic-conventions >=1.40 && <2`, neither currently in this repository's
  dependency closure.
- The shared `shinzui/haskell-nix` registry overlay supplies baikai, baikai-claude, baikai-openai,
  and baikai-kit — **not** baikai-trace-otel (see the comment at the top of
  `nix/haskell-overlay.nix`). Adopting it means either adding it to that registry upstream or
  adding a local pin here, in the manner of the existing `okf-core` Hackage pin in the same file.
- A tracer must be created and shut down around the call, unlike the file and stream sinks which
  need no lifecycle, so `traceSinkFor` would need to become bracket-shaped (or gain a companion
  that is) rather than simply returning a sink.
- Whether it belongs behind a cabal flag so users who do not want the OTel dependency tree can opt
  out.

Acceptance: the note exists and names the package versions and the registry constraint. This
milestone is complete when written; it is a hand-off, not an implementation.


## Concrete Steps

All commands run from the repository root unless stated otherwise:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
```

Use `nix develop` for builds and tests so the baikai family resolves from the Nix overlay:

```bash
nix develop --command bash -c 'cabal build all'
nix develop --command bash -c 'cabal test all'
```

### Reading the baikai source

The trace API is small and worth reading before Milestone 2. Locate it with Mori rather than
guessing at paths:

```bash
mori registry show baikai --full
```

Expected: a `Path:` line reading `/Users/shinzui/Keikaku/bokuno/baikai`. The three files that
matter:

```text
baikai/src/Baikai/Trace.hs         -- withTrace, withTraceStream
baikai/src/Baikai/Trace/Sink.hs    -- TraceSink, silent, stdoutSink, fileSink, multiSink, renderHuman
baikai/src/Baikai/Trace/Event.hs   -- TraceEvent and its JSON encoding
```

Do **not** search `/nix/store` for these; it is enormous and is not the source of truth.

### Per-milestone loop

Each milestone ends with the same verification pair and one commit:

```bash
nix develop --command bash -c 'cabal build all'
nix develop --command bash -c 'cabal test all'
```

Expected tail of a green run (counts grow as this plan adds specs; what matters is that no suite
fails):

```text
Test suite seihou-core-test: PASS
Test suite seihou-cli-test: PASS
Test suite seihou-okf-extension-test: PASS
```

Commit message shapes, one per milestone:

```text
feat(cli): resolve an agent trace setting through the config chain
feat(cli): build baikai trace sinks from the resolved trace setting
feat(cli): emit baikai call traces, preserving provider error reporting
docs(user): document agent call tracing
docs(dev): record what adopting baikai-trace-otel would require
```

Each commit must carry both trailers:

```text
ExecPlan: docs/plans/74-wire-baikai-call-tracing-into-seihou.md
Intention: intention_01kyj8dbxde3zta5zyt0y1srxq
```

Before the final commit, run the full gate:

```bash
nix flake check
```

Expected: no failures. It runs the test suites, the formatting check, and
`nix/check-cli-module-placement.sh`. This plan adds one module to the CLI **library**, so the
placement check passes; if it complains, `Seihou.CLI.AgentTrace` was put in `src-exe/` when it
belonged in `seihou-cli/src/`.

Note that the pre-commit hook runs `treefmt` and will reformat Haskell files, failing the commit
with "files were modified by this hook". That is normal: re-run `git add -A` and commit again.


## Validation and Acceptance

Acceptance is behavior, verified by hand in a scratch directory and by the automated suites.

### 1. Tracing is off by default

```bash
export SCRATCH=$(mktemp -d)
mkdir -p "$SCRATCH/.seihou/modules/tracer"
cat > "$SCRATCH/.seihou/modules/tracer/blueprint.dhall" <<'EOF'
let S = /Users/shinzui/Keikaku/bokuno/seihou-project/seihou/schema/package.dhall

in  S.Blueprint::{
    , name = "tracer"
    , version = Some "0.1.0"
    , prompt = "Say hello."
    }
EOF
cd "$SCRATCH"
seihou agent run tracer --batch
ls -la .seihou/trace.jsonl
```

Expected: the run completes normally and `ls` reports **no such file**. Tracing must cost nothing
and leave nothing behind unless asked for.

### 2. A file trace records a correlated pair

```bash
seihou config set agent.trace file
seihou agent run tracer --batch
cat .seihou/trace.jsonl
```

Expected: exactly two lines, the first `"kind":"call_started"` and the second
`"kind":"call_finished"`, sharing one `eventId`:

```text
{"kind":"call_started","eventId":"…","timestamp":"…","provider":"claude-cli","model":"claude-opus-4-8","maxTokens":…,"promptSummary":"Say hello."}
{"kind":"call_finished","eventId":"…","timestamp":"…","provider":"claude-cli","model":"claude-opus-4-8","latencyMs":…}
```

Token and cost fields are legitimately absent here: `claude-cli` is subscription-based and reports
neither. Confirm the correlation mechanically:

```bash
jq -r '.eventId' .seihou/trace.jsonl | sort -u | wc -l
```

Expected: `1`.

### 3. The stream settings write to the right channel

```bash
seihou agent run tracer --batch --trace stderr 2>/dev/null
```

Expected: **no** trace lines appear, because they went to stderr and were discarded — proving they
are not polluting stdout. Then:

```bash
seihou agent run tracer --batch --trace stderr 2>&1 >/dev/null
```

Expected: the two human-readable lines, and none of the assistant output:

```text
[2026-07-27T18:04:11Z] claude-cli claude-opus-4-8 START max=… Say hello.
[2026-07-27T18:04:19Z] claude-cli claude-opus-4-8 -> 7913ms (no-cost)
```

### 4. A flag overrides configured tracing, and the precedence chain holds

```bash
seihou config set agent.trace file
seihou agent run tracer --batch --trace off
```

Expected: no new lines are appended to `.seihou/trace.jsonl` — the flag wins over the config file.
Then confirm the environment tier:

```bash
SEIHOU_AGENT_TRACE=stderr seihou agent run tracer --batch 2>&1 >/dev/null
```

Expected: the stderr lines, not a file append — the environment variable outranks the config file.

### 5. A bad setting is rejected with an actionable message

```bash
seihou agent run tracer --batch --trace syslog; echo "exit=$?"
```

Expected:

```text
Error: Unknown trace setting 'syslog'. Expected one of: off, file, stdout, stderr.
exit=1
```

### 6. A failing call is recorded as a failure

Force an error by pointing at a provider with no credentials:

```bash
env -u ANTHROPIC_API_KEY seihou agent run tracer --batch --provider anthropic --trace file
tail -1 .seihou/trace.jsonl
```

Expected: a `"kind":"call_failed"` line carrying `latencyMs` and a non-empty `errorMessage`, and —
critically — the **same** user-facing error text on stderr that this command produced before this
plan. That second half is the regression check for Milestone 3: the message must name the real
provider failure, not `"Provider returned no assistant text."`

### 7. The automated proof

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
nix develop --command bash -c 'cabal test seihou-cli'
```

Expected: `Seihou.CLI.AgentTrace`, `Seihou.CLI.AgentConfig`, `Seihou.CLI.AgentCompletion`, and the
new end-to-end spec all pass. The end-to-end case is the one that matters most, because steps 1–6
are manual and easy to run against a stale binary.

### 8. The whole gate

```bash
nix develop --command bash -c 'cabal test all'
nix flake check
```

Expected: both green.


## Idempotence and Recovery

Every step is safe to re-run. Editing Haskell modules and docs is idempotent; `cabal build`,
`cabal test`, and `nix flake check` are read-only with respect to the working tree. No schema
changes, no submodule commits, no pushes to shared repositories, and no dependency-pin changes —
so unlike plan 73, this plan has no irreversible step.

Three points deserve care:

**The file sink appends.** Re-running a traced command adds lines rather than replacing the file,
which is the intended behavior but makes "exactly two lines" assertions order-dependent across
repeated manual runs. Delete `.seihou/trace.jsonl` between manual acceptance steps, or use a fresh
`$SCRATCH`. The automated tests use `withSystemTempDirectory`, so they are immune.

**Milestone 3 is the rollback point.** Milestones 1 and 2 are purely additive and inert: the
setting resolves and a sink can be built, but nothing consumes them, so reverting either leaves a
working tree with dead-but-harmless code. Milestone 3 changes how every model call is made. If a
regression appears after it, revert that single commit — the two below it are independently
useful and need not be unwound. Restated as an ordering constraint: revert Milestone 3 before
Milestones 1–2, never the other way around.

**A misconfigured trace path must not break runs.** If `agent.tracePath` points somewhere
unwritable, `fileSink` will fail. The failure surfaces through the `try` in
`runAgentCompletionWith` (baikai's doc comment confirms downstream-of-the-fold exceptions
propagate), so the user sees an error rather than silent data loss — but the model call may
already have happened and been paid for. If this proves annoying in practice, the fix is to
validate writability in `traceSinkFor` and downgrade to `silent` with a `logWarn`; record that in
the Decision Log if you take it.


## Interfaces and Dependencies

### External dependencies (no new ones)

- **`baikai` ^>=0.4.1.0** — already a `seihou-cli` dependency. This plan newly imports
  `Baikai.Trace` (`withTrace`), `Baikai.Trace.Sink` (`TraceSink (..)`, `silent`, `stdoutSink`,
  `fileSink`, `multiSink`, `renderHuman`), `Baikai.Trace.Event` (`TraceEvent (..)`), and
  `Baikai.Response` (`responseError`). All ship in the package already in the build.
- **`streamly-core`** — reached only through `TraceSink`'s newtype wrapper and, in
  `Seihou.CLI.AgentTrace`, through `Streamly.Data.Fold.drainMapM` to build the stderr sink. It is
  already a transitive dependency of `baikai`; if the compiler demands it as a direct
  `build-depends` entry for `seihou-cli`, add it with the bound baikai itself uses
  (`^>=0.3`) and note it in Surprises & Discoveries, since it is the one dependency-list change
  this plan might need.
- **`aeson`, `directory`, `filepath`, `text`, `time`** — already direct dependencies.
- **`baikai-trace-otel`** — deliberately **not** adopted; see Milestone 5.

### `seihou-cli` library (`seihou-cli/src/`)

`Seihou.CLI.AgentCompletion`:

```haskell
data TraceSetting = TraceOff | TraceFile | TraceStdout | TraceStderr
  deriving stock (Eq, Show)

traceFromText :: Text -> Either Text TraceSetting
traceToText   :: TraceSetting -> Text

data AgentModelConfig = AgentModelConfig
  { agentProvider :: AgentProvider,
    agentModel :: Maybe Text,
    agentEffort :: Maybe ThinkingLevel,
    agentTrace :: TraceSetting,          -- new
    agentTracePath :: Maybe FilePath     -- new
  }

data AgentCompletionRequest = AgentCompletionRequest
  { completionSystemPrompt :: Text,
    completionInitialPrompt :: Maybe Text,
    completionModelConfig :: AgentModelConfig,
    completionTraceSink :: TraceSink     -- new
  }

buildAgentCompletionRequest     :: AgentModelConfig -> Text -> Maybe Text -> AgentCompletionRequest
buildAgentCompletionRequestWith :: TraceSink -> AgentModelConfig -> Text -> Maybe Text -> AgentCompletionRequest
```

`buildAgentCompletionRequest` keeps its signature and defaults the sink to `silent`.
`runAgentCompletion` and `runAgentCompletionWithCliAccess` keep their signatures; only their shared
implementation changes.

`Seihou.CLI.AgentTrace` (**new module, library**):

```haskell
defaultTraceFileName :: FilePath
resolveTraceFilePath :: Maybe FilePath -> FilePath
stderrSink           :: TraceSink
traceSinkFor         :: TraceSetting -> Maybe FilePath -> IO TraceSink
```

`Seihou.CLI.AgentConfig`:

```haskell
data AgentConfigInputs = AgentConfigInputs
  { …existing fields…
  , cliTrace :: Maybe Text
  , cliTraceFromSubcommand :: Bool
  , envTrace :: Maybe Text
  , declaredTrace :: Maybe Text        -- reserved; no schema field feeds it yet
  }

data AgentField = ProviderField | ModelField | EffortField | TraceField

agentTraceConfigKey        :: Text                      -- "agent.trace"
agentCommandTraceConfigKey :: AgentCommandName -> Text  -- "agent.<command>.trace"
agentTracePathConfigKey    :: Text                      -- "agent.tracePath"
agentTraceEnvVar           :: String                    -- "SEIHOU_AGENT_TRACE"

resolveTracePath :: AgentConfigInputs -> Maybe FilePath

data ResolvedCommandConfig = ResolvedCommandConfig
  { …existing fields…
  , rccTrace :: ResolvedAgentField TraceSetting
  }
```

`resolveAgentModelConfigFor`'s return tuple grows a fourth component; `resolvedAgentModelConfig`,
`loadAgentModelConfigFor`, `resolvePendingAgentConfig`, and `formatResolvedAgentProvenance` are
updated to carry it. `PendingAgentConfig`, `AgentLaunchDeclaration`, and
`validateAgentLaunchDeclaration` keep their current shapes — this plan does not extend the schema.

`Seihou.CLI.AgentConfigShow` — one new row per command and a legend mention.

### `seihou-cli` executable (`seihou-cli/src-exe/`)

```haskell
-- Commands.hs: each *Opts record gains a trace flag field, e.g.
data BlueprintRunOpts = BlueprintRunOpts { …, runBlueprintTrace :: Maybe Text }

-- Main.hs: both helpers gain a trace parameter pair (parent, subcommand)
resolveAgentModelConfigFor :: AgentCommandName -> … -> IO AgentCompletion.AgentModelConfig
pendingAgentConfigFor      :: AgentCommandName -> … -> IO PendingAgentConfig
```

`Seihou.CLI.AgentLaunchExec` and the interactive launch path are **unchanged** — they spawn
subprocesses and emit no trace events.

### Tests

- `seihou-cli/test/Seihou/CLI/AgentConfigSpec.hs` — the trace precedence matrix.
- `seihou-cli/test/Seihou/CLI/AgentConfigShowSpec.hs` — the new row and legend text.
- `seihou-cli/test/Seihou/CLI/AgentCompletionSpec.hs` — the error-shape regression tests.
- `seihou-cli/test/Seihou/CLI/AgentTraceSpec.hs` — **new**; sink construction and path resolution.
- `seihou-cli/test/Seihou/CLI/AgentTraceE2ESpec.hs` — **new**; the JSONL end-to-end proof.

The two new spec modules must be registered in **both** `seihou-cli/test/Main.hs` (import plus an
entry in the `sequence [...]` list) and `seihou-cli/seihou-cli.cabal`'s test-suite
`other-modules`. Forgetting the cabal entry produces a confusing "module not found" at link time.
