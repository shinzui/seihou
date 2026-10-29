RECIPES

A recipe is a named deterministic composition of modules, with optional typed
variables, interactive prompts and per-module bindings. Use it when existing
modules already provide the generation logic and one command should apply them.

AUTHOR AND RUN

  seihou new-recipe my-stack --module base --module editor
  seihou validate-recipe ./my-stack

  This creates my-stack/recipe.dhall with the selected modules. Edit the
  generated definition to add variables or bindings. Preserve its field shapes. Put it in a normal search path (for example
  .seihou/modules/my-stack/) or publish/install it through a registry.

  seihou vars my-stack
  seihou run my-stack --dry-run
  seihou run my-stack

  Dependencies resolve before generation. Supply declared values with --var
  or normal config scopes for composition. Validate the descriptor separately:

  seihou validate-recipe ./my-stack </dev/null

  PATH defaults to the current directory. Validation checks Dhall, declarations,
  prompts, condition references and binding names without asking for values,
  finding/installing members, generating files or executing commands. Required
  variables without defaults are valid. Exit codes: valid 0, invalid/unreadable 1,
  missing recipe.dhall 4. Correct the named field and rerun. Dhall imports are
  evaluated normally and remote imports may need network/cache access.

  registry validate checks entry metadata; validate-recipe checks the descriptor;
  run --dry-run resolves values and members to preview composition.

UPDATES

  seihou update my-stack

  Update the recorded root application to fetch sources, reuse accepted
  inputs, apply migrations and preserve project edits. You do not need to
  enumerate transitive modules. Use status to inspect the recorded application.
  Checkout links declared by its modules are restored in fresh clones with sync.
  Seed steps from every contributing instance retain exact claims while the first
  supplier provides initial bytes. Reruns/updates preserve edits and deletion;
  removing the last claim retires settlement without deleting the project file.

CHOOSING AN ARTIFACT

  Module       Deterministic generation steps and template files
  Recipe       Named composition of existing modules
  Blueprint    Agent-driven project work, optionally with baseline modules
  Prompt       Reusable agent-session task without blueprint provenance

SEE ALSO

  seihou help modules
  seihou help variables
  seihou help update
  seihou help registry
  seihou new-recipe --help
  seihou validate-recipe --help

## Installing required modules

`seihou install SOURCE --module RECIPE` installs the selected recipe and its complete
module dependency closure, including external registries declared with
`source = Some "GIT-URL"`. Then use `seihou run RECIPE` with ordinary recipe inputs.
A missing source means the declaring registry during install. Reinstalling repairs
older incomplete installs. Run and dry-run use local modules and never fetch.

Preflight failures leave installed artifacts unchanged. Correct a missing source or
entry and retry the same command. Existing foreign cache entries require an informed
`--force`; contradictory sources within one closure always fail. A local shadow must
have verifiable matching provenance for an explicit source requirement.

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

For example, a recipe can own a shared boolean decision:

```dhall
vars = [ S.VarDecl::{ name = "git.createGithub", type = "bool", required = True } ]
prompts = [ S.Prompt::{ var = "git.createGithub", text = "Create a GitHub repository?" } ]
```

`seihou run RECIPE` asks once; `seihou run RECIPE --var git.createGithub=false`
supplies an explicit answer without a terminal. Modules declaring that name receive
the answer above their own defaults.


Recipe policy: defaults are overridable fallbacks. Literal member bindings outrank
ambient config and saved input; CLI still wins. Add a recipe input constraint to
reject disallowed overrides. For example, bind `git.githubOwner=topagentnetwork`
and declare `validation = Some "^topagentnetwork\$"`. Binding names allow
`[a-z][A-Za-z0-9.-]*`, including camelCase. Patterns are case-sensitive POSIX
extended regexes matching the whole text value with multiline anchors disabled;
`private|public|internal` accepts exactly those values. Malformed patterns fail,
even on absent optional inputs. Recipe and consumer constraints apply independently
to every selected source; errors name the original source and a supported
correction before generation or commands. Ordinary update revalidates saved inputs.
