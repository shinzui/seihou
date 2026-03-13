GIT REPOSITORY

Seihou modules can be shared and installed from git repositories. A
repository can contain a single module or multiple modules organized
as a registry.

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

MULTI-MODULE REPOSITORY (REGISTRY)

  A repository with a seihou-registry.dhall at the root is treated as a
  registry containing multiple modules. Each module lives in its own
  subdirectory with its own module.dhall.

    my-templates/
      seihou-registry.dhall
      haskell-base/
        module.dhall
        templates/
          ...
      rust-base/
        module.dhall
        templates/
          ...

  The registry file declares available modules with descriptions and tags.
  Install specific modules, all modules, or choose interactively:

    seihou install https://github.com/user/templates.git --module haskell-base
    seihou install https://github.com/user/templates.git --all
    seihou install https://github.com/user/templates.git          # interactive

BROWSING BEFORE INSTALLING

  Use 'seihou browse' to inspect a repository without installing anything:

    seihou browse https://github.com/user/templates.git
    seihou browse https://github.com/user/templates.git --tag haskell

  For multi-module repos, this lists all modules with descriptions and tags.

WHERE MODULES ARE INSTALLED

  Installed modules are stored under ~/.config/seihou/installed/<name>/.
  They appear alongside user-created modules in the module search path:

  1. .seihou/modules/             Project-local modules
  2. ~/.config/seihou/modules/    User modules
  3. ~/.config/seihou/installed/  Installed (from git)

BOOTSTRAPPING A NEW REPOSITORY

  The agent bootstrap command can create a new module or multi-module
  repository structure for you:

    seihou agent bootstrap                    # single module
    seihou agent bootstrap --repo             # multi-module with registry
