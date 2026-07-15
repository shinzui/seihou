# Agent-Driven Blueprints

Blueprints are Seihou's escape hatch for project shapes that need judgement,
iteration, or design choices that do not fit a fixed template. A module or
recipe produces a deterministic file plan. A blueprint packages a prompt,
optional baseline modules, resolved variables, and reference files for
`seihou agent run`.

Use a blueprint when an agent should adapt examples and conventions to the
project in front of it, often after applying baseline modules. Use a module or
recipe when the same inputs should always produce the same outputs. Use a
prompt when you want a reusable agent-session workflow without scaffold
baselines or manifest provenance.

## Blueprint layout

Create a blueprint with:

```sh
seihou new-blueprint api-service
```

The command creates:

```text
api-service/
├── blueprint.dhall
├── prompt.md
└── files/
```

- `blueprint.dhall` declares the blueprint metadata, variables, baseline
  modules, and reference files.
- `prompt.md` is the Markdown prompt body imported by `blueprint.dhall` as
  `./prompt.md as Text`.
- `files/` holds optional examples, snippets, partial templates, or sample
  configs for the agent to consult.

## The blueprint.dhall format

Fresh blueprints use the schema package and Dhall record completion:

```dhall
let S =
      https://raw.githubusercontent.com/shinzui/seihou-schema/<commit>/package.dhall
        sha256:<hash>

in  S.Blueprint::{
    , name = "api-service"
    , version = Some "0.1.0"
    , description = Some "API service scaffold"
    , prompt = ./prompt.md as Text
    , vars =
      [ S.VarDecl::{
        , name = "project.name"
        , type = "text"
        , description = Some "The project name"
        , required = True
        }
      ]
    , prompts =
      [ S.Prompt::{
        , var = "project.name"
        , text = "What is your project name?"
        }
      ]
    , baseModules = [] : List S.Dependency.Type
    , files = [] : List S.Blueprint.BlueprintFile.Type
    , tags = [ "api" ]
    }
```

Important fields:

| Field | Purpose |
|-------|---------|
| `name` | Blueprint identifier. Must match `[a-z][a-z0-9-]*`. |
| `version` | Optional version recorded in status and registry metadata. |
| `prompt` | Required prompt body. Usually `./prompt.md as Text`. |
| `vars` | Variables resolved before the prompt is rendered. |
| `prompts` | Interactive questions for missing variables. |
| `baseModules` | Modules or recipes to apply before the agent runs. |
| `files` | Reference files under the blueprint's `files/` directory. |
| `allowedTools` | Optional runner metadata for tool allow-lists. |
| `tags` | Discovery tags for registries, browse, install, and list filters. |

Blueprints share a lookup namespace with modules, recipes, and prompts. If one
directory contains more than one runnable file, discovery prefers
`module.dhall`, then `recipe.dhall`, then `blueprint.dhall`, then
`prompt.dhall`.

## Variables

Blueprint variables resolve through the same hierarchy as module variables:
CLI overrides, environment variables, local config, namespace config, context
config, global config, defaults, then interactive prompts.

```sh
seihou agent run api-service --var project.name=payments
seihou vars api-service
```

Resolved values are substituted into `prompt.md` with `{{variable.name}}`
placeholders before the prompt is sent to the configured provider.

## Baseline modules

`baseModules` applies deterministic scaffolding before the agent starts:

```dhall
baseModules =
  [ { module = "haskell-base"
    , vars = [ { name = "project.name", value = "payments" } ]
    }
  , { module = "nix-flake", vars = [] : List { name : Text, value : Text } }
  ]
```

Use baselines for stable foundations: language skeletons, Nix setup, CI
defaults, shared repository conventions. Base entries must resolve to modules
or recipes, not other blueprints.

Skip the baseline for a one-off run with:

```sh
seihou agent run api-service --no-baseline --var project.name=payments
```

## Reference files

Declare reference files that the agent should consult:

```dhall
files =
  [ { src = "example-readme.md"
    , description = Some "Reference README tone and structure"
    }
  ]
```

Each `src` is relative to the blueprint's `files/` directory. Validation fails
if the file is missing. Reference files are not copied automatically; they are
context for the agent.

## Running a blueprint

Run blueprints through the agent command:

```sh
seihou agent run api-service "make this a payments service"
```

The runner:

1. Discovers and validates the named blueprint.
2. Resolves blueprint variables and prompts for required missing values.
3. Applies `baseModules`, unless `--no-baseline` is set.
4. Renders the blueprint prompt and project context.
5. Starts the configured provider.
6. Records applied-blueprint provenance in `.seihou/manifest.json` after a
   successful non-debug run.

`seihou run api-service` refuses when `api-service` resolves to a blueprint.
That command is reserved for deterministic modules and recipes.

## Validation

Before publishing or running a blueprint:

```sh
seihou validate-blueprint api-service
```

Validation checks that `blueprint.dhall` evaluates, the prompt is non-empty,
variables are unique, prompts reference declared variables, base modules
resolve to modules or recipes, and declared reference files exist. Add
`--lint` for advisory warnings about best practices.

## Publishing blueprints

Registries can publish blueprints alongside modules, recipes, and prompts:

```dhall
{ repoName = "team-templates"
, repoDescription = Some "Team project starters"
, modules = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }
, recipes = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }
, blueprints =
  [ { name = "api-service"
    , version = Some "0.1.0"
    , path = "blueprints/api-service"
    , description = Some "Agent-guided API service scaffold"
    , tags = [ "api", "agent" ]
    }
  ]
, prompts = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }
}
```

Users can browse, install, list, and filter blueprints with the same registry
commands used for modules and recipes:

```sh
seihou browse https://github.com/team/team-templates.git --tag agent
seihou install https://github.com/team/team-templates.git --module api-service
seihou list --blueprints
```

## See also

- [AI Agent Assistance](agent-assistance.md)
- [Configuration and Variable Resolution](config-and-variables.md)
- [First-Class Prompts](prompts.md)
- [Registries and Multi-Module Repositories](registries-and-multi-module-repos.md)
- [`seihou new-blueprint`](../cli/new-blueprint.md)
- [`seihou validate-blueprint`](../cli/validate-blueprint.md)
- [`seihou agent`](../cli/agent.md)
