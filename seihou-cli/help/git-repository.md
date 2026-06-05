GIT REPOSITORY

Seihou modules, recipes, and blueprints can be shared and installed from git
repositories. A repository can contain a single runnable item or multiple items
organized as a registry.

SINGLE-MODULE REPOSITORY

  A repository with a module.dhall at the root is treated as a single
  module. When installed, the module name defaults to the repository name.

    my-module/
      module.dhall
      templates/
        ...

  Install with:

    seihou install https://github.com/user/my-module.git
    seihou install https://github.com/user/my-module.git --name custom-name

SINGLE-RECIPE OR SINGLE-BLUEPRINT REPOSITORY

  A repository with a recipe.dhall or blueprint.dhall at the root is treated
  as a single recipe or single blueprint. Install it the same way:

    seihou install https://github.com/user/my-recipe.git
    seihou install https://github.com/user/my-blueprint.git

  Recipes run through `seihou run`; blueprints run through
  `seihou agent run`.

REGISTRY REPOSITORY

  A repository with a seihou-registry.dhall at the root is treated as a
  registry containing multiple modules, recipes, and blueprints. Each item
  lives in its own subdirectory with its own runnable definition.

    my-templates/
      seihou-registry.dhall
      modules/haskell-base/module.dhall
      recipes/haskell-library/recipe.dhall
      blueprints/api-service/blueprint.dhall

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
  They appear alongside user-created modules, recipes, and blueprints in the
  search path:

  1. .seihou/modules/             Project-local items
  2. ~/.config/seihou/modules/    User items
  3. ~/.config/seihou/installed/  Installed (from git)

BOOTSTRAPPING A NEW REPOSITORY

  The agent bootstrap command can create a new module or registry repository
  structure for you:

    seihou agent bootstrap                    # single module
    seihou agent bootstrap --repo             # multi-module with registry

UPGRADE WORKFLOW

  Once installed, modules, recipes, and blueprints can be upgraded with
  `seihou upgrade`. If a newer module version ships migrations (for renames,
  deletions, etc.), the upgrade command surfaces them via an advisory; running
  `seihou migrate <module>` is the post-upgrade step that applies them
  to the current project. See `seihou help migrations`.
