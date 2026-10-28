AGENT COMMANDS

`seihou agent` renders Seihou-aware prompts and starts a configured
provider. The agent commands are for AI-assisted
module authoring, bootstrapping, project setup, running agent-driven
blueprints, applying ordered blueprint library migrations, and
repairing a project's manifest state to upgrade a module.

CLI providers open interactive local Claude Code or Codex sessions.
API providers send one rendered prompt as a batch completion and print
one assistant response.

USAGE

  seihou agent [--debug] [--provider PROVIDER] [--model MODEL] [--effort LEVEL] [--trace SETTING] <subcommand> [options]

PARENT OPTIONS

  --debug
      Print the resolved system prompt and exit without contacting any
      provider. Use this to inspect what Seihou would send. Artifact
      debug renders still run declared commandVars/version probes;
      agent upgrade also saves its brief outside the project.

  --provider PROVIDER
      Select the provider for this invocation. Accepted values:
      `claude-cli`, `codex-cli`, `anthropic`, `openai`.

  --model MODEL
      Select a provider-specific model name or alias for this
      invocation. Run `seihou agent models` to list known choices.

  --effort LEVEL
      Reasoning effort: minimal, low, medium, high, xhigh, or max.
      Omitted effort leaves the provider's choice in effect.

  --trace SETTING
      Record model calls: off (default), file, stdout, or stderr.
      File output uses agent.tracePath (local, then global), default
      .seihou/trace.jsonl. Traces cover batch/API calls; interactive
      CLI sessions emit no call events. --debug contacts no provider.

Provider, model, effort and trace options may appear on the parent command or on the
subcommand:

  seihou agent --provider codex-cli --model gpt-5 assist "create a module"
  seihou agent assist --provider codex-cli --model gpt-5 "create a module"
  seihou agent --debug --provider openai setup "inspect this prompt"

PROVIDERS

  claude-cli
      Starts an interactive Claude Code session. Requires the
      `claude` binary on PATH and a working local login. With no
      explicit model, Seihou passes its pinned default, `claude-opus-4-8`.

  codex-cli
      Starts an interactive Codex session. Requires the `codex`
      binary on PATH and a working local login. With no explicit
      model, Seihou passes its pinned default, `gpt-5.6-terra`. Seihou launches Codex
      with workspace-write sandboxing and on-request approvals.

  anthropic
      Uses the Anthropic Messages API. Requires `ANTHROPIC_API_KEY`
      or `ANTHROPIC_KEY`. Defaults to `claude-sonnet-4-6` when no
      model is configured.

  openai
      Uses the OpenAI Chat Completions API. Requires `OPENAI_API_KEY`
      or `OPENAI_KEY`. Defaults to `gpt-4o-mini` when no model is
      configured.

CONFIGURATION

Provider, model, effort and trace resolve independently of module variables.
The first non-blank value wins for each field:

  1. Subcommand CLI flag
  2. Parent agent CLI flag
  3. SEIHOU_AGENT_PROVIDER / MODEL / EFFORT / TRACE environment variables
     (each name has the SEIHOU_AGENT_ prefix)
  4. blueprint.dhall or prompt.dhall launch.{provider,model,effort}
  5. Local agent.<command>.{provider,model,effort,trace}
  6. Local agent.{provider,model,effort,trace}
  7. Global agent.<command>.{provider,model,effort,trace}
  8. Global agent.{provider,model,effort,trace}
  9. Built-in defaults (provider claude-cli; pinned CLI models above;
     API models as above; effort unset; trace off)

Local config is .seihou/config.dhall; global is ~/.config/seihou/config.dhall.
Artifact launch declarations apply only to agent run, agent migrate and
prompt run. launch.mode is reserved and ignored; launch has no trace field.
Use `--verbose` on artifact runs to see resolved settings and sources.
Command key segments are assist, bootstrap, setup, upgrade, run, migrate,
and prompt-run (for `seihou prompt run`).

  seihou agent config
  seihou config set agent.provider codex-cli --global
  seihou config set agent.bootstrap.effort high --global
  seihou config set agent.prompt-run.trace file
  seihou config set agent.tracePath .seihou/trace.jsonl

`seihou agent config` is read-only and shows each command's provider, model,
effort, trace and source. Its table cannot include a specific artifact's
launch declaration; use the run's --verbose output for that.

SUBCOMMANDS

  seihou agent config
      Inspect resolved per-command settings and their sources without
      starting a provider or changing configuration.

  seihou agent models [--provider PROVIDER]
      List the Anthropic and OpenAI models in Seihou's compiled Baikai
      catalog. Filtering by `anthropic` or `claude-cli` returns the same
      Claude-family models; filtering by `openai` or `codex-cli` returns
      the same OpenAI-family models. The filter may appear before or
      after `models`:

        seihou agent --provider claude-cli models
        seihou agent models --provider openai

      Listing models requires no provider credentials, network access,
      or agent configuration. The catalog is a discovery aid, not
      validation: provider-native aliases and custom model IDs remain
      accepted by `--model`. Do not pass `--model` to this listing
      command.

  seihou agent assist [PROMPT]
      Render a prompt for creating or modifying Seihou modules. The
      prompt includes current project context, available modules, and
      the module schema.

  seihou agent bootstrap [PROMPT] [--repo]
      Render a prompt for creating a new module from scratch. With
      `--repo`, target a multi-module repository with
      `seihou-registry.dhall`.

  seihou agent setup [PROMPT]
      Render a prompt for using existing Seihou modules in a project:
      selecting modules, configuring variables, previewing, running,
      verifying, and committing.

  seihou agent upgrade MODULE [PROMPT] [--check]
      Diagnose the project for upgrading MODULE without changing
      anything, write an upgrade brief (findings, a repair playbook
      keyed by update error code, safety rules) outside the project,
      print its path, and start an agent session that repairs the
      manifest state and performs the upgrade. It never fails on
      project or configuration state: problems become findings, and
      when no session can start it says how to use the saved brief.

      --check prints the readiness report and exits 0. Its last line
      is 'Upgrade readiness: ready' or 'Upgrade readiness: not ready
      (N ...)'. When it reads ready, a plain `seihou update MODULE`
      needs no agent.

  seihou agent run BLUEPRINT [PROMPT] [--var KEY=VALUE] [--no-baseline]
      Resolve a blueprint, optionally apply its baseline modules,
      render the blueprint prompt, and send it to the configured
      provider. A successful non-debug run records applied-blueprint
      provenance in `.seihou/manifest.json`.

  seihou agent migrate BLUEPRINT [--from VERSION] [--to VERSION] [PROMPT]
      Run one agent session per in-window migration declared by the blueprint.
      Versions are dotted numbers; gaps are allowed. Successful edges are
      recorded immediately so a later invocation resumes at the first
      unrecorded edge. `--rerun` ignores matching receipts. Migration mode does
      not apply baseModules and exposes neither --no-baseline nor --force.

      Either end of the window may be omitted. --to then comes from the
      blueprint's declared versionProbe, a command it supplies that reads the
      version this project depends on; --from comes from the highest version
      already recorded in this project's receipts. An explicit flag always
      wins, and an inferred end is reported with the source it came from.

      Parent --debug prints every pending migration prompt in order without
      contacting a provider or writing receipts. It does run the version
      probe, which is required to be read-only, so debug planning matches a
      real run.

      --mark-applied records every pending edge in the window as already
      applied, without running them, on your assertion that you performed the
      upgrade by hand. No provider is contacted and no file in the working
      tree is changed. Each receipt is filed under the blueprint that owns its
      edge, so a marked entailed edge suppresses a later direct run of that
      blueprint too; edges that already have receipts are left alone rather
      than restamped. --rerun clears a mistaken marking. The flag is refused
      alongside --rerun or parent --debug, both of which it contradicts.

      A receipt records that an edge has been dealt with -- a provider
      interaction returned, or you marked it -- not package-manager
      verification.

  seihou prompt run PROMPT [USER-PROMPT] [--var KEY=VALUE] [--debug]
      Resolve a reusable prompt, run command-derived variables, render
      the prompt body, and send it to the configured provider. Prompts
      do not apply blueprint baselines or record blueprint provenance.

DEBUG EXAMPLES

  seihou agent --debug --provider claude-cli assist "inspect this prompt"
  seihou agent --debug --provider codex-cli bootstrap --repo "inspect this prompt"
  seihou agent --debug --provider openai setup "inspect this prompt"
  seihou agent --debug run my-blueprint --var project.name=demo
  seihou agent --debug migrate my-library --from 1.0.0 --to 3.0.0
  seihou agent --debug migrate my-library

SEE ALSO

  seihou agent --help
  seihou help config
  seihou help variables
  seihou help prompts
  docs/cli/agent.md
  docs/user/config-and-variables.md


Blueprint migration CLI sessions automatically run in batch mode when stdin is
not a terminal. Use `seihou agent migrate BLUEPRINT --batch` to request batch
mode explicitly, including when only stdout is redirected. Authenticate the
selected `claude` or `codex` CLI first and supply required blueprint inputs with
`--var KEY=VALUE` or normal configuration. Batch mode keeps workspace permissions,
blueprint tools, and reference directories; it does not bypass approvals.
It also preapproves specific read-only Mori discovery commands for dependency
inspection, excluding registry mutations.

Batch processes return when work finishes. With terminal input, sessions remain
interactive: exit each session normally to record its edge. If a batch provider
fails, reports a permission denial, or returns incomplete output, no receipt is
written for that edge. Inspect partial edits, repair the reported problem, and
rerun the same command; completed edges are skipped. Receipts do not verify that
the migrated project builds or passes tests.
