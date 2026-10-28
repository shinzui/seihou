RECIPES

A recipe is a named deterministic composition of modules, with optional typed
variables, interactive prompts and per-module bindings. Use it when existing
modules already provide the generation logic and one command should apply them.

AUTHOR AND RUN

  seihou new-recipe my-stack --module base --module editor

  This creates my-stack/recipe.dhall with the selected modules. Edit the
  generated definition to add variables or bindings. Preserve its field shapes. Put it in a normal search path (for example
  .seihou/modules/my-stack/) or publish/install it through a registry.

  seihou vars my-stack
  seihou run my-stack --dry-run
  seihou run my-stack

  Dependencies resolve before generation. Supply declared values with --var
  or normal config scopes. There is no validate-recipe command; inspect vars
  and the run preview, and use registry validate for published entry metadata.

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
