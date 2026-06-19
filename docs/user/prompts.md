# First-Class Prompts

Prompts are reusable agent-session templates. Use a prompt when you want to
render a structured instruction with Seihou variables, local command output,
and reference files, then launch Claude Code or Codex without applying a
scaffold or recording blueprint provenance.

Use a module or recipe for deterministic file generation. Use a blueprint when
an agent should scaffold or modify a project shape, optionally after applying
baseline modules. Use a prompt for repeatable agent workflows such as code
review, release preparation, planning, repository inspection, or dependency
research.

## Prompt Layout

Create a prompt with:

```sh
seihou new-prompt review-changes
```

The command creates:

```text
review-changes/
├── prompt.dhall
├── prompt.md
└── files/
```

- `prompt.dhall` declares metadata, variables, command-derived variables,
  reference files, tags, and optional launch hints.
- `prompt.md` is the Markdown body imported by `prompt.dhall` as
  `./prompt.md as Text`.
- `files/` holds optional reference files that the prompt can name for the
  launched agent.

## The prompt.dhall Format

Fresh prompts are self-contained Dhall records:

```dhall
{ name = "review-changes"
, version = Some "0.1.0"
, description = Some "Review current git changes"
, prompt = ./prompt.md as Text
, vars =
  [ { name = "project.name"
    , type = "text"
    , default = None Text
    , description = Some "Project name for the review header"
    , required = False
    , validation = None Text
    }
  ]
, prompts =
  [ { var = "project.name"
    , text = "Project name?"
    , when = None Text
    , choices = None (List Text)
    }
  ]
, commandVars =
  [ { name = "git.diff"
    , run = "git diff --stat"
    , workDir = None Text
    , when = None Text
    , trim = True
    , maxBytes = Some 20000
    }
  ]
, files =
  [ { src = "review-checklist.md"
    , description = Some "Team review checklist"
    }
  ]
, allowedTools = None (List Text)
, tags = [ "review" ]
, launch = Some { provider = Some "codex-cli", mode = None Text, model = None Text }
}
```

Important fields:

| Field | Purpose |
|-------|---------|
| `name` | Prompt identifier. Must match `[a-z][a-z0-9-]*`. |
| `version` | Optional version used by registries and installed origin metadata. |
| `description` | Human-readable summary shown by `list` and `browse`. |
| `prompt` | Required prompt body. Usually `./prompt.md as Text`. |
| `vars` | Typed variables resolved before rendering. |
| `prompts` | Interactive questions for unresolved typed variables. |
| `commandVars` | Variables filled by local commands after normal variable resolution. |
| `files` | Reference files under `files/`. |
| `allowedTools` | Optional runner metadata for future tool allow-lists. |
| `tags` | Discovery tags for registries, browse, install, and list filters. |
| `launch` | Optional provider, mode, or model hints for this prompt. |

Prompts share a lookup namespace with modules, recipes, and blueprints. If one
directory contains multiple runnable files, discovery prefers `module.dhall`,
then `recipe.dhall`, then `blueprint.dhall`, then `prompt.dhall`.

## Variables From Config

Prompt variables use the same precedence chain as module and blueprint
variables: CLI overrides, environment, local config, namespace config, context
config, global config, defaults, then interactive prompts.

For a reusable review prompt:

```sh
seihou config set project.name seihou --global
seihou prompt run review-changes --debug
```

If `prompt.md` contains:

```text
Review the current changes for {{project.name}}.
```

the debug output includes the globally configured project name unless a higher
precedence source overrides it:

```sh
seihou prompt run review-changes --var project.name=demo --debug
```

## Command-Derived Variables

`commandVars` fill prompt placeholders from local command output. They run
after ordinary variables and prompts, so they can use any already-resolved
value in their `run` string:

```dhall
commandVars =
  [ { name = "git.branch"
    , run = "git branch --show-current"
    , workDir = None Text
    , when = None Text
    , trim = True
    , maxBytes = Some 4096
    }
  ]
```

Then `prompt.md` can refer to:

```text
Current branch: {{git.branch}}
```

Command variables are intentionally constrained:

- Commands run locally before provider launch.
- Non-zero exits fail the prompt render.
- `maxBytes` limits captured output.
- `trim = True` removes surrounding whitespace.
- Unsafe working directories are rejected.

Use command variables for compact context such as branch names, diff stats,
test summaries, or file lists. Avoid collecting secrets or huge command output.

## Reference Files

Declare reference files that live under `files/`:

```dhall
files =
  [ { src = "review-checklist.md"
    , description = Some "Team review checklist"
    }
  ]
```

Validation fails if a declared file is missing. Reference files are not copied
or applied; they are available context for the launched agent and should be
named explicitly in the prompt body.

## Running Prompts

Validate before running:

```sh
seihou validate-prompt review-changes
```

Render without contacting a provider:

```sh
seihou prompt run review-changes --debug
```

Launch with the configured default provider:

```sh
seihou prompt run review-changes
```

Override provider or model for one invocation:

```sh
seihou prompt run review-changes --provider codex-cli
seihou prompt run review-changes --provider claude-cli --model sonnet
```

Provider defaults come from the same agent configuration used by
`seihou agent`: CLI flags, environment variables, local config, global config,
then built-in defaults. See [AI Agent Assistance](agent-assistance.md) for
provider details.

## Publishing Prompts

Registries can publish prompts alongside modules, recipes, and blueprints:

```dhall
{ repoName = "team-prompts"
, repoDescription = Some "Shared agent prompts"
, modules = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }
, recipes = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }
, blueprints = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }
, prompts =
  [ { name = "review-changes"
    , version = Some "0.1.0"
    , path = "prompts/review-changes"
    , description = Some "Review current git changes"
    , tags = [ "review" ]
    }
  ]
}
```

Users can browse, install, and list prompt entries:

```sh
seihou browse https://github.com/org/team-prompts.git --tag review
seihou install https://github.com/org/team-prompts.git --module review-changes
seihou list --prompts
```

The registry selector flag is still named `--module` for compatibility, but it
selects any registry entry kind: module, recipe, blueprint, or prompt.

## See Also

- [AI Agent Assistance](agent-assistance.md)
- [Agent-Driven Blueprints](blueprints.md)
- [Configuration and Variable Resolution](config-and-variables.md)
- [Registries and Multi-Module Repositories](registries-and-multi-module-repos.md)
- [`seihou new-prompt`](../cli/new-prompt.md)
- [`seihou validate-prompt`](../cli/validate-prompt.md)
- [`seihou prompt`](../cli/prompt.md)
