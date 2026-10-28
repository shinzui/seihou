VARIABLES

Variables are named, typed values that modules use to customize generated
output. They are declared in module.dhall and resolved at generation time
from multiple sources.

DECLARING VARIABLES

  Each declaration has name, type, optional default/description/validation,
  and a required flag. Supported CLI types are text, bool, int, list text,
  and choice. Text lists are comma-separated; choices use a prompt's choices.
  list bool/list int decode as types but their CLI coercion is not implemented.
  Required variables with no resolved value prompt interactively or fail when
  no prompt can supply a value. Optional variables may remain unset.

RESOLUTION ORDER

  Highest precedence first:

  1. CLI overrides       --var project.name=my-app
  2. Saved inputs        Ordinary update only (unless --reconfigure)
  3. Environment         SEIHOU_VAR_PROJECT_NAME
  4. Local config        .seihou/config.dhall
  5. Namespace config    ~/.config/seihou/namespaces/<ns>/config.dhall
  6. Context config      ~/.config/seihou/contexts/<ctx>/config.dhall
  7. Global config       ~/.config/seihou/config.dhall
  8. Parent bindings     Parameterized dependencies
  9. Default value       Declared in the artifact

  Interactive prompts fill missing values after this resolution. Initial
  generation has no saved-input tier. Agent provider/model/effort/trace
  settings use a different precedence chain; see `seihou help agent`.

EXPORTS

  A module can export variables so that dependent modules can use them.
  Exports are declared in module.dhall and make a variable's resolved value
  available to any module that depends on this one.

INSPECTING VARIABLES

  seihou vars <module>                 List declared variables
  seihou vars <module> --explain       Show resolved values with provenance
  seihou vars <module> --var k=v       Supply values for resolution

  The --explain flag is especially useful for debugging: it shows where each
  variable's value came from (CLI, config, default, export, etc.).

NAMESPACING

  The namespace selects a separate config file, not a prefix added to every
  variable name. Use --namespace NS to override the artifact's default
  namespace. `seihou vars NAME --explain` reports the resolved source.

## Recipe inputs

Recipe inputs are resolved before module variables. A required recipe boolean
without a default asks once on an interactive terminal, even when every consuming
module defaults it to false. In automation, supply `--var git.createGithub=false`
(or configuration); missing required choices fail before generation.

Recipe precedence is CLI, literal recipe bindings, saved recipe inputs on update,
environment, local/namespace/context/global configuration, then recipe defaults.
Resolved recipe inputs override module saved values and defaults. Each consumer
still validates the value. Explicit false is a value, not an omitted answer.
Optional prompt conditions see typed recipe values and earlier answers; a false
condition skips interaction but does not waive a required declaration.

Successful runs record recipe inputs in the checked-in manifest, including inputs
used only by conditions. `seihou update RECIPE` reuses them in fresh clones;
`--reconfigure` discards saved choices. Older applications adopt agreeing consumer
values during ordinary preview; conflicts require `--var KEY=VALUE` or
`--reconfigure`. Saving prompted values to local config remains optional and
respects `--save-prompted` and `--no-save-prompted`; previews do not save them.
