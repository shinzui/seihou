REGISTRY

A multi-artifact repository declares seihou-registry.dhall at its root. Lists
named modules, recipes, blueprints and prompts contain entries with name,
optional version/description, project-relative path and tags. Each path points
to the directory holding the corresponding runnable definition. Names must be
unique across kinds; paths must be relative without parent traversal.

AUTHOR WORKFLOW

  seihou registry sync-versions --dry-run
  seihou registry sync-versions
  seihou registry validate

  Sync-versions reads each item's declared version and refreshes registry
  metadata. It rewrites the whole Dhall file, so review formatting/comments in
  the diff. --check instead exits nonzero on missing, stale or orphaned entries
  without writing; use it in CI. Validate checks structure and version agreement.
  Both commands accept --dir PATH, work locally and do not read installed copies.

  Validate item contents with validate-module, validate-recipe, validate-blueprint or
  validate-prompt as appropriate; registry validation checks metadata.

CONSUMERS

  seihou browse GIT-URL
  seihou install GIT-URL --module NAME
  seihou install GIT-URL --all

  --module can select any entry kind. Applied modules/recipes are advanced with
  update; upgrade refreshes only the installed cache. See git-repository.

SEE ALSO

  seihou registry --help
  seihou help git-repository
  seihou help recipes
  seihou help blueprints
  seihou help prompts

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
