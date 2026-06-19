PROMPTS

A prompt is a reusable agent-session template. It renders a Markdown prompt
from Seihou variables, local command output, optional guidance blocks, optional
reference files, and an optional user instruction, then starts the configured
provider.

Use a prompt for repeatable agent workflows such as code review, release
preparation, planning, repository inspection, or dependency research. Use a
module or recipe for deterministic file generation. Use a blueprint when an
agent should scaffold or modify a project shape and optionally apply baseline
modules first.

PROMPT STRUCTURE

  A prompt directory looks like:

    review-changes/
      prompt.dhall      Prompt definition (required)
  prompt.md         Markdown body imported by prompt.dhall
  files/            Optional reference files for the agent

  `seihou new-prompt review-changes` creates this layout.

SCHEMA FIELDS

  name           Prompt name. Must match [a-z][a-z0-9-]*.
  version        Optional version for registries and installed origin metadata.
  description    Optional human-facing summary.
  prompt         Required prompt body. Usually `./prompt.md as Text`.
  vars           Typed variables resolved before the prompt is rendered.
  prompts        Interactive questions for missing typed variables.
  commandVars    Variables filled by local command output.
  guidance       Markdown instruction blocks selected after variables resolve.
  files          Reference files under the prompt's files/ directory.
  allowedTools   Optional tool allow-list metadata.
  tags           Optional discovery tags.
  launch         Optional provider/mode/model hints.

  Prompts share the same name lookup namespace as modules, recipes, and
  blueprints. If a directory contains multiple runnable definitions, lookup
  prefers `module.dhall`, then `recipe.dhall`, then `blueprint.dhall`, then
  `prompt.dhall`.

VARIABLES

  Prompt variables use the standard Seihou precedence chain:

    CLI --var, environment, local config, namespace config, context config,
    global config, defaults, interactive prompts.

  Example:

    seihou config set project.name seihou --global
    seihou prompt run review-changes --debug

  A `prompt.md` body containing `{{project.name}}` will render the configured
  value unless a higher-precedence source overrides it.

COMMAND-DERIVED VARIABLES

  `commandVars` fill placeholders from local command output after normal
  variables resolve:

    { name = "git.branch"
    , run = "git branch --show-current"
    , workDir = None Text
    , when = None Text
    , trim = True
    , maxBytes = Some 4096
    }

  Use command variables for compact local context such as branch names, diff
  stats, test summaries, or file lists. Non-zero exits fail rendering, and
  `maxBytes` limits captured output.

PROMPT GUIDANCE

  `guidance` adds Markdown instruction blocks around the prompt body in the
  provider prompt. Use it for repository workflow rules, project-specific
  validation commands, or adaptation based on command-derived variables.

    guidance =
      [ { title = "Haskell repository"
        , body = "Prefer cabal build all and focused cabal test commands."
        , when = Some "Eq repo.kind haskell"
        }
      ]

  Guidance does not apply blueprint baseline modules and does not write
  applied-blueprint provenance.

COMMON COMMANDS

  seihou new-prompt review-changes       Scaffold a prompt
  seihou validate-prompt review-changes  Check prompt.dhall and files/
  seihou prompt run review-changes       Run the prompt with a provider
  seihou prompt run review-changes --debug
                                         Print the complete provider prompt
  seihou list --prompts                  Show only prompt artifacts

PUBLISHING

  Registries can list prompts alongside modules, recipes, and blueprints in a
  `prompts = [...]` field. Install prompt entries with the existing registry
  selector:

    seihou install GIT-URL --module review-changes

  The selector flag is still named `--module` for compatibility, but it can
  select any registry entry kind.

FURTHER READING

  docs/user/prompts.md             prompt authoring guide
  docs/cli/new-prompt.md           command reference for scaffolding
  docs/cli/validate-prompt.md      command reference for validation
  docs/cli/prompt.md               command reference for running prompts
  seihou help variables            variable precedence and overrides
