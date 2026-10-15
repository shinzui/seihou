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
