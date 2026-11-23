GIT REPOSITORY

Seihou modules, recipes, blueprints, prompts, and judgements can be shared and
installed from git repositories. A repository can contain a single artifact
or multiple items organized as a registry.

SINGLE-MODULE REPOSITORY

  A repository with a module.dhall at the root is treated as a single
  module. When installed, the module name defaults to the repository name.

    my-module/
      module.dhall
      files/
        ...

  Install with:

    seihou install https://github.com/user/my-module.git
    seihou install https://github.com/user/my-module.git --name custom-name

OTHER SINGLE-ARTIFACT REPOSITORIES

  A repository with a root recipe.dhall, blueprint.dhall, prompt.dhall, or
  judgement.dhall is treated as a single artifact. Install it the same way:

    seihou install https://github.com/user/my-recipe.git
    seihou install https://github.com/user/my-blueprint.git
    seihou install https://github.com/user/my-prompt.git
    seihou install https://github.com/user/my-judgement.git

  Recipes run through `seihou run`; blueprints run through
  `seihou agent run`; prompts run through `seihou prompt run`. Adopt a judgement
  with `seihou run NAME`; see `seihou help judgements`.

REGISTRY REPOSITORY

  A repository with a seihou-registry.dhall at the root is treated as a
  registry containing modules, recipes, blueprints, prompts, or judgements.
  Each item lives in its own subdirectory with its own definition.

    my-templates/
      seihou-registry.dhall
      modules/haskell-base/module.dhall
      recipes/haskell-library/recipe.dhall
      blueprints/api-service/blueprint.dhall
      prompts/review-changes/prompt.dhall
      judgements/license-review/judgement.dhall

  The registry file declares available items with descriptions, versions, and
  tags. Install specific items, all items, or choose interactively:

    seihou install https://github.com/user/templates.git --module haskell-base
    seihou install https://github.com/user/templates.git --all
    seihou install https://github.com/user/templates.git          # interactive

BROWSING BEFORE INSTALLING

  Use 'seihou browse' to inspect a repository without installing anything:

    seihou browse https://github.com/user/templates.git
    seihou browse https://github.com/user/templates.git --tag haskell

  For registry repos, this lists all items with descriptions and tags.

WHERE ITEMS ARE INSTALLED

  Installed items are stored under ~/.config/seihou/installed/<name>/.
  They appear alongside user-created artifacts in the search path:

  1. .seihou/modules/             Project-local items
  2. ~/.config/seihou/modules/    User items
  3. ~/.config/seihou/installed/  Installed (from git)

BOOTSTRAPPING A NEW REPOSITORY

  The agent bootstrap command can create a new module or registry repository
  structure for you:

    seihou agent bootstrap                    # single module
    seihou agent bootstrap --repo             # multi-module with registry

PROJECT UPDATE AND CACHE UPGRADE

  After a module or recipe has been applied to a project, use `seihou update`
  for routine source updates. It stages the newer repository content, reuses
  saved inputs, applies migrations, reconciles generated files with user
  edits, and publishes the installed cache only after the project succeeds.

  `seihou upgrade` is a lower-level cache-maintenance command. It refreshes
  the shared installed copy but does not reconcile templates or user edits in
  the current project. Use it when cache-only maintenance is intentional.
  See `seihou help update` and `seihou help migrations`.
