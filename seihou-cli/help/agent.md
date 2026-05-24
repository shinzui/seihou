AGENT COMMANDS

`seihou agent` renders Seihou-aware prompts and sends them to a
configured Baikai provider. The agent commands are for AI-assisted
module authoring, bootstrapping, project setup, and running
agent-driven blueprints.

The provider call is a batch completion: Seihou sends one rendered
prompt and prints one assistant response. The CLI-backed providers do
not open an interactive Claude Code or Codex session, and Baikai does
not expose tool calling through those CLI provider paths.

USAGE

  seihou agent [--debug] [--provider PROVIDER] [--model MODEL] <subcommand> [options]

PARENT OPTIONS

  --debug
      Print the resolved system prompt and exit without contacting any
      provider. Use this to inspect what Seihou would send.

  --provider PROVIDER
      Select the provider for this invocation. Accepted values:
      `claude-cli`, `codex-cli`, `anthropic`, `openai`.

  --model MODEL
      Select a provider-specific model name or alias for this
      invocation.

Parent options must appear before the subcommand:

  seihou agent --provider codex-cli --model gpt-5 assist "create a module"
  seihou agent --debug --provider openai setup "inspect this prompt"

PROVIDERS

  claude-cli
      Uses Baikai's `claude -p` provider. Requires the `claude`
      binary on PATH and a working local login. With no explicit
      model, the CLI chooses its own default.

  codex-cli
      Uses Baikai's `codex exec` provider. Requires the `codex`
      binary on PATH and a working local login. With no explicit
      model, the CLI chooses its own default.

  anthropic
      Uses the Anthropic Messages API. Requires `ANTHROPIC_API_KEY`
      or `ANTHROPIC_KEY`. Defaults to `claude-sonnet-4-6` when no
      model is configured.

  openai
      Uses the OpenAI Chat Completions API. Requires `OPENAI_API_KEY`
      or `OPENAI_KEY`. Defaults to `gpt-4o-mini` when no model is
      configured.

CONFIGURATION

Provider and model values resolve independently from module variables.
The first non-blank value wins:

  1. Parent CLI flags: `--provider`, `--model`
  2. Environment: `SEIHOU_AGENT_PROVIDER`, `SEIHOU_AGENT_MODEL`
  3. Local config: `.seihou/config.dhall`
  4. Global config: `~/.config/seihou/config.dhall`
  5. Built-in defaults: provider `claude-cli`, no explicit model

Set personal defaults globally:

  seihou config set agent.provider codex-cli --global
  seihou config set agent.model gpt-5 --global

Use environment variables for a temporary shell session:

  export SEIHOU_AGENT_PROVIDER=openai
  export SEIHOU_AGENT_MODEL=gpt-4o-mini

SUBCOMMANDS

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

  seihou agent run BLUEPRINT [PROMPT] [--var KEY=VALUE] [--no-baseline]
      Resolve a blueprint, optionally apply its baseline modules,
      render the blueprint prompt, and send it to the configured
      provider. A successful non-debug run records applied-blueprint
      provenance in `.seihou/manifest.json`.

DEBUG EXAMPLES

  seihou agent --debug --provider claude-cli assist "inspect this prompt"
  seihou agent --debug --provider codex-cli bootstrap --repo "inspect this prompt"
  seihou agent --debug --provider openai setup "inspect this prompt"
  seihou agent --debug run my-blueprint --var project.name=demo

SEE ALSO

  seihou agent --help
  seihou help config
  seihou help variables
  docs/cli/agent.md
  docs/user/config-and-variables.md
