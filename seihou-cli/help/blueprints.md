BLUEPRINTS

A blueprint is an agent-driven runnable artifact. Modules and recipes use
Seihou's deterministic execution engine to write files from declared steps.
Blueprints instead package a prompt, optional baseline modules, variables,
and reference files for `seihou agent run`.

Use a blueprint when the desired output needs judgement, iteration, or
project-specific design decisions that do not fit a fixed module template.
Use a module or recipe when the same inputs should always produce the same
file plan.

BLUEPRINT STRUCTURE

  A blueprint directory looks like:

    my-blueprint/
      blueprint.dhall     Blueprint definition (required)
      prompt.md           Markdown prompt imported by blueprint.dhall
      files/              Optional reference files for the agent
        example.md
        config.sample

  `seihou new-blueprint my-blueprint` creates this layout. The generated
  `blueprint.dhall` imports `prompt.md` as Text so authors can edit the
  prompt as normal Markdown instead of escaping it through a Dhall string.

SCHEMA FIELDS

  The Dhall record uses the Blueprint schema:

    name           Blueprint name. Must match [a-z][a-z0-9-]*.
    version        Optional dotted version for provenance and status.
    description    Optional human-facing summary.
    prompt         Required prompt body. Usually `./prompt.md as Text`.
    vars           Variables resolved before the prompt is rendered.
    prompts        Interactive questions for missing required variables.
    baseModules    Modules or recipes to apply before the agent runs.
    files          Reference files under the blueprint's files/ directory.
    allowedTools   Optional tool allow-list metadata for the runner.
    tags           Optional discovery tags.

  Blueprints share the same name lookup namespace as modules and recipes.
  If a directory contains more than one runnable definition, lookup prefers
  `module.dhall`, then `recipe.dhall`, then `blueprint.dhall`.

VARIABLES AND PROMPTS

  Blueprint variables use the same declaration and resolution model as
  module variables:

    seihou agent run my-blueprint --var project.name=demo

  Resolution follows the normal precedence chain: CLI overrides, environment,
  local config, namespace config, context config, global config, defaults,
  then interactive prompts. Resolved values are substituted into the blueprint
  prompt with `{{variable.name}}` placeholders before the agent sees it.

  `seihou vars my-blueprint` lists a blueprint's declared variables.

BASELINE MODULES

  `baseModules` lets a blueprint apply deterministic scaffolding before the
  agent starts. This is useful for stable foundations such as a language
  skeleton, Nix setup, CI defaults, or shared repository conventions.

  Each base module entry has the same dependency shape used by recipes:

    { module = "haskell-base"
    , vars = [ { name = "project.name", value = "demo" } ]
    }

  Base modules must resolve to modules or recipes, not other blueprints. The
  agent runner records the applied blueprint in `.seihou/manifest.json` after
  a successful run, including baseline provenance.

REFERENCE FILES

  Files declared in the `files` list must live under the blueprint's `files/`
  directory:

    files =
      [ { src = "example.md", description = Some "Reference README style" }
      ]

  Reference files are meant for examples, snippets, partial templates, design
  notes, or sample configs that help the agent produce the right project. They
  are not copied automatically by the deterministic engine.

COMMON COMMANDS

  seihou new-blueprint api-service       Scaffold a blueprint
  seihou validate-blueprint api-service  Check blueprint.dhall and files/
  seihou list                            List modules, recipes, blueprints, and prompts
  seihou vars api-service                Show blueprint variables
  seihou agent run api-service           Run the blueprint with an agent

  `seihou run api-service` refuses when `api-service` resolves to a blueprint.
  That command is reserved for deterministic modules and recipes; use
  `seihou agent run` for blueprints.

VALIDATION

  `seihou validate-blueprint [PATH]` checks that:

    - blueprint.dhall exists and evaluates
    - the name, version, tags, and allowed tool entries are valid
    - the prompt body is non-empty
    - variables are unique
    - prompts reference declared variables
    - baseModules resolve to modules or recipes
    - declared reference files exist under files/

  If validation fails, fix the reported check before publishing or running
  the blueprint.

FURTHER READING

  docs/cli/new-blueprint.md        command reference for scaffolding
  docs/cli/validate-blueprint.md   command reference for validation
  seihou help variables            variable precedence and overrides
  seihou help modules              deterministic module authoring
